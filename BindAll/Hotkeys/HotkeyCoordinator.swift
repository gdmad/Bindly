import AppKit
import SwiftUI
import Observation
import os

/// Wires global hotkeys to the selection → engine/translation pipeline.
@MainActor
final class HotkeyCoordinator {
    private static let log = Logger(subsystem: "com.evgeny.bindall", category: "hotkeys")

    private let appState: AppState
    private let monitor = HotkeyMonitor()
    private let translationCoordinator = TranslationCoordinator()
    private let voice = PushToTalkController()
    private let popup = PopupController()
    private let autocomplete = AutocompleteController()
    private let proofread = ProofreadController()
    private lazy var quickTranslate = QuickTranslateController(appState: appState)
    private let stars = FieldStarController()
    private let preview = PreviewController()
    private let customPrompt = CustomPromptController()

    private var translationWindow: NSWindow?
    private var settingsObserver: Task<Void, Never>?
    private var retryTimer: Timer?
    private var busyWatchdog: DispatchWorkItem?
    private var isBusy = false
    /// The pasteboard's change count before the last hotkey burst (see `SelectionReader.currentSelection`).
    private var burstChangeCount = 0

    // The in-flight engine task and the Esc monitors that can cancel it.
    private var currentTask: Task<Void, Never>?
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        AccessibilityPermission.requestIfNeeded()
        refreshStatus()
        setupTranslationWindow()

        monitor.onBurst = { [weak self] keyCode, mods, count, changeCount in
            self?.handleBurst(keyCode: keyCode, modifiers: mods, count: count, changeCount: changeCount)
        }
        reconfigureWatched()
        if !monitor.start() {
            Self.log.error("hotkey monitor failed to start (trusted=\(AccessibilityPermission.isGranted, privacy: .public))")
        }
        updateAutocomplete()
        updateProofread()
        setupStars()
        voice.translate = { [weak self] text, code in
            guard let self else { return text }
            return try await self.translateDictation(text, to: code)
        }
        voice.onDictated = { [weak self] text in
            self?.recordHistory(kind: .voice, input: "", output: text, engine: "Speech", applied: true)
        }
        updateVoice()

        // Every settings change -- or a key/token change in the Keychain -- re-applies everything; each
        // step is cheap and idempotent. The first value is the current one, already applied just
        // above, so it is skipped.
        let appState = self.appState
        settingsObserver = Task { [weak self] in
            var isFirst = true
            for await _ in Observations({ (appState.settings, appState.keychainRevision) }) {
                if isFirst { isFirst = false; continue }
                guard let self else { return }
                self.reconfigureWatched()
                self.refreshStatus()
                self.updateAutocomplete()
                self.updateProofread()
                self.updateStars()
                self.updateVoice()
            }
        }

        // The event tap can only be installed once Accessibility is granted. Poll so the user does
        // not have to relaunch after granting permission, and keep the status indicators live.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshStatus()
                if !self.monitor.isRunning, AccessibilityPermission.isGranted {
                    self.reconfigureWatched()
                    if !self.monitor.start() {
                        Self.log.error("hotkey monitor retry failed to start")
                    }
                }
                self.updateAutocomplete()
                // Proofread's monitors have their own guard against a permission grant that arrived
                // after they last tried to install -- see ProofreadController.configure(). Calling it
                // every tick is what lets that self-heal without a relaunch.
                self.updateProofread()
            }
        }
    }

    /// Starts or stops autocomplete depending on the setting and Accessibility.
    private func updateAutocomplete() {
        let s = appState.settings
        var cfg = AutocompleteController.Config()
        cfg.maxSuggestions = s.autocompleteCount
        cfg.layout = s.autocompleteLayout
        cfg.fontSize = CGFloat(max(10, min(20, s.popupFontSize)))
        cfg.languages = s.autocompleteLanguages
        cfg.learn = s.autocompleteLearn
        cfg.nextWord = s.autocompleteNextWord
        cfg.acceptReturn = s.autocompleteAcceptReturn
        cfg.inline = s.autocompleteInline
        cfg.contextRanking = s.autocompleteContextRanking
        cfg.appMode = AutocompleteController.AppFilterMode(rawValue: s.autocompleteAppMode) ?? .all
        cfg.apps = Set(s.autocompleteApps)
        autocomplete.configure(cfg)
        // The master switch stands everything down, per the "BindAll enabled" toggle's own help text.
        if s.enabled, s.autocompleteEnabled, AccessibilityPermission.isGranted {
            autocomplete.start()
        } else {
            autocomplete.stop()
        }
    }

    /// Pushes the current settings into the proofread controller. It has no shortcut: checking runs
    /// on its own after a pause in typing, and the fixes open on a click into an underlined word.
    private func updateProofread() {
        let s = appState.settings
        var cfg = ProofreadController.Config()
        // The master switch stands everything down, per the "BindAll enabled" toggle's own help text.
        cfg.enabled = s.enabled && s.correctEnabled
        cfg.maxReplacements = s.proofreadMaxReplacements
        cfg.layout = s.proofreadLayout
        cfg.fontSize = CGFloat(max(10, min(20, s.popupFontSize)))
        cfg.minLength = s.proofreadMinLength
        cfg.restoreClipboard = s.restoreClipboard
        cfg.appMode = ProofreadController.AppFilterMode(rawValue: s.proofreadAppMode) ?? .all
        cfg.apps = Set(s.proofreadApps)
        cfg.dictionary = PersonalDictionary.set(s.personalDictionary)
        cfg.preSend = s.preSendCheck
        proofread.configure(cfg,
                            engine: EngineFactory.makeLanguageTool(appState: appState),
                            language: s.languageToolLanguage)
        // Both features consume Tab, so only one popup may be live at a time.
        proofread.onSessionChange = { [weak self] active in
            if active { self?.autocomplete.suspend() } else { self?.autocomplete.resume() }
        }
        autocomplete.onSuggestionChange = { [weak self] visible in self?.proofread.setSuggestionVisible(visible) }
        proofread.onAddWord = { [weak self] word in
            guard let self else { return }
            self.appState.settings.personalDictionary = PersonalDictionary.adding(word, to: self.appState.settings.personalDictionary)
        }
        // Many words change at once, so the result is always previewed before it is written.
        proofread.onFixAll = { [weak self] context, result, count in
            self?.preview.show(title: "Fix all (\(count))", original: context.text, result: result,
) { [weak self] in
                UsageLog.record(.proofread, .applied, detail: "fixAll:\(count)")
                self?.recordHistory(kind: .action, input: context.text, output: result, engine: "LanguageTool", applied: true)
                self?.replace(context, with: result)
            }
        }
    }

    // MARK: - Stars

    private func setupStars() {
        stars.appAllowed = { [weak self] in self?.starAppAllowed() ?? false }
        stars.onOpen = { [weak self] context, view in self?.openStarMenu(context, at: view) }
        updateStars()
    }

    private func updateVoice() {
        let s = appState.settings
        var cfg = PushToTalkController.Config()
        cfg.enabled = s.enabled && s.pushToTalkEnabled
        cfg.key = s.pushToTalkKey
        cfg.translateKeyEnabled = s.enabled && s.voiceTranslateEnabled
        cfg.translateKey = s.voiceTranslateKey
        cfg.language = s.pushToTalkLanguage
        cfg.translate = s.pushToTalkTranslate
        cfg.targetLanguage = s.pushToTalkTargetLanguage == "same" ? s.targetLanguage : s.pushToTalkTargetLanguage
        cfg.restoreClipboard = s.restoreClipboard
        cfg.fontSize = CGFloat(max(10, min(20, s.popupFontSize)))
        voice.configure(cfg)
    }

    /// Push to Talk's "translate before inserting": Apple Translation, nothing when it is already
    /// in that language.
    /// Following the Translation tab ("same"), it uses that pair both ways like every other
    /// translation; a target picked for voice is one-way.
    private func translateDictation(_ text: String, to code: String) async throws -> String {
        let detected = LanguageDetector.detect(text)?.languageCode?.identifier
        let s = appState.settings
        let direction = s.pushToTalkTargetLanguage == "same"
            ? LanguagePair.resolve(detected: detected, source: s.sourceLanguage, target: s.targetLanguage)
            : LanguagePair.resolve(detected: detected, source: AppLanguages.autoTag, target: code)
        if direction.isAlreadyThere { return text }
        let translation = try await translationCoordinator.translate(text, from: direction.from.map { Locale.Language(identifier: $0) },
                                                                     to: Locale.Language(identifier: direction.to))
        recordHistory(kind: .translate, input: text, output: translation, engine: "Apple Translation", applied: true)
        return translation
    }

    private func updateStars() {
        let s = appState.settings
        let on = s.enabled && AccessibilityPermission.isGranted
        stars.apply(FieldStarController.Config(fieldEnabled: on && s.starFieldEnabled,
                                               selectionEnabled: on && s.starSelectionEnabled))
    }

    /// Stars have their own app list (Settings > General > Stars).
    private func starAppAllowed() -> Bool {
        let s = appState.settings
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        switch s.starAppMode {
        case "allow": return s.starApps.contains(bundle)
        case "deny": return !s.starApps.contains(bundle)
        default: return true
        }
    }

    /// What a star menu item does.
    enum StarAction {
        case fix, spelling, translate, translateInPlace, removeTells
        case reading(Reading)
        case actionKey(ActionKey)
        case prompt(String, showOnly: Bool)
    }

    private func openStarMenu(_ context: StarContext, at view: NSView) {
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String, _ action: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, action: action)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if !context.isEditable {
            // Text that cannot be changed (a terminal, a log): only what reads it.
            add("Show translation", "globe") { [weak self] in self?.runStarAction(.translate, context) }
            add("Explain", "questionmark.bubble") { [weak self] in self?.runStarAction(.reading(.explain), context) }
            add("Summarize", "text.alignleft") { [weak self] in self?.runStarAction(.reading(.summarize), context) }
            add("Copy", "doc.on.doc") {
                UsageLog.record(.star, .accepted, detail: "copy")
                TextInjector.copyToPasteboard(context.subject)
            }
            popUp(menu, under: view)
            return
        }
        add("Fix", "wand.and.stars") { [weak self] in self?.runStarAction(.fix, context) }
        add(SelectionCommand.spelling.title, "textformat.abc") { [weak self] in self?.runStarAction(.spelling, context) }
        add("Show translation", "globe") { [weak self] in self?.runStarAction(.translate, context) }
        add("Replace with translation", "character.bubble") { [weak self] in self?.runStarAction(.translateInPlace, context) }
        add("Remove AI tells", "eraser") { [weak self] in self?.runStarAction(.removeTells, context) }
        // The user's own AI actions in a submenu of their own, so the list can grow without
        // pushing the built-in items apart.
        let keys = appState.settings.actionKeys.filter { !$0.prompt.isEmpty }
        if !keys.isEmpty {
            menu.addItem(.separator())
            let submenu = NSMenu()
            for key in keys {
                let item = ClosureMenuItem(title: key.title) { [weak self] in self?.runStarAction(.actionKey(key), context) }
                item.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
                submenu.addItem(item)
            }
            let actions = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
            actions.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            actions.submenu = submenu
            menu.addItem(actions)
        }
        menu.addItem(.separator())
        add("Custom prompt…", "text.bubble") { [weak self] in self?.askForPrompt(context) }
        if let history = historyMenu(for: context) { menu.addItem(history) }
        if !context.isSelection {
            let count = proofread.issueCount(in: context.element)
            if count > 0 {
                menu.addItem(.separator())
                add(count == 1 ? "1 issue: show it" : "\(count) issues: show the first", "text.magnifyingglass") { [weak self] in
                    UsageLog.record(.star, .accepted, detail: "proofread")
                    self?.proofread.showFirstIssue()
                }
            }
        }
        popUp(menu, under: view)
    }

    private func popUp(_ menu: NSMenu, under view: NSView) {
        // popUp blocks until the menu closes, so the flag spans exactly the tracking.
        proofread.setMenuOpen(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
        proofread.setMenuOpen(false)
    }

    /// Recent results; picking one puts it in place of the star's text, through the preview when
    /// that is on. Nil when history is off or empty.
    private func historyMenu(for context: StarContext) -> NSMenuItem? {
        let entries = HistoryStore.shared.entries.filter(\.applied).prefix(HistoryMenuTitle.count)
        guard appState.settings.historyEnabled, !entries.isEmpty else { return nil }
        let submenu = NSMenu()
        for entry in entries {
            let item = ClosureMenuItem(title: HistoryMenuTitle.title(for: entry)) { [weak self] in
                self?.insertFromHistory(entry, context)
            }
            item.toolTip = "\(entry.kind.label) · \(entry.engine)\n\(entry.output)"
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    /// From the selection star an entry replaces the selection; from the field star it goes in at
    /// the caret -- replacing the whole draft with an old result would throw the draft away.
    private func insertFromHistory(_ entry: HistoryEntry, _ context: StarContext) {
        UsageLog.record(.star, .accepted, detail: "history")
        var context = context
        context.insertsAtCaret = !context.isSelection
        let apply: () -> Void = { [weak self] in self?.replace(context, with: entry.output) }
        if appState.settings.previewFromMenu {
            preview.show(title: "From history", original: context.subject, result: entry.output,
                         onApply: apply)
        } else {
            apply()
        }
    }

    private func askForPrompt(_ context: StarContext) {
        UsageLog.record(.customPrompt, .shown)
        customPrompt.show(recent: appState.settings.recentPrompts,
                          scope: context.isSelection ? "Selection" : "Whole text",
) { [weak self] prompt, showOnly, save in
            self?.rememberPrompt(prompt, saveAsActionKey: save, showOnly: showOnly)
            self?.runStarAction(.prompt(prompt, showOnly: showOnly), context)
        }
    }

    private func rememberPrompt(_ prompt: String, saveAsActionKey: Bool, showOnly: Bool) {
        var recent = appState.settings.recentPrompts.filter { $0 != prompt }
        recent.insert(prompt, at: 0)
        appState.settings.recentPrompts = Array(recent.prefix(5))
        if saveAsActionKey, !appState.settings.actionKeys.contains(where: { $0.prompt == prompt }) {
            appState.settings.actionKeys.append(ActionKey(label: String(prompt.prefix(40)), prompt: prompt, showOnly: showOnly))
        }
    }

    /// Runs a star action on the context's text, then previews (or shows) the result.
    private func runStarAction(_ action: StarAction, _ context: StarContext) {
        let text = context.subject
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let settings = appState.settings
        if case .translate = action {
            UsageLog.record(.star, .accepted, detail: "translate")
            guard !isBusy else { return }
            beginBusy()
            currentTask = Task { await translateAndShow(text, historyKind: .translate); endBusy() }
            return
        }
        if case .translateInPlace = action {
            UsageLog.record(.star, .accepted, detail: "translateInPlace")
            guard !isBusy else { return }
            beginBusy()
            currentTask = Task { await translateAndShow(text, historyKind: .translate, replacing: context); endBusy() }
            return
        }
        guard !isBusy else { return }
        beginBusy()
        let started = ContinuousClock.now
        let (feature, title, detail): (UsageFeature, String, String) = switch action {
        case .fix: (.fix, "Fix", "source:star")
        case .spelling: (.spelling, "Fix spelling", "source:star")
        case .removeTells: (.removeTells, "Remove AI tells", "source:star")
        case .actionKey(let key): (.actionKey, key.title, key.logToken)
        case .prompt: (.customPrompt, "Custom prompt", "source:star")
        case .translate, .translateInPlace: (.translate, "Translate", "source:star")
        case .reading(let reading): (reading.feature, reading.title, "source:star")
        }
        let showOnly = switch action {
        case .reading, .prompt(_, true): true
        case .actionKey(let key): key.showOnly
        default: false
        }
        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }
            do {
                var result: String
                switch action {
                case .spelling:
                    result = try await EngineFactory.makeLanguageTool(appState: self.appState)
                        .correct(text, dictionary: PersonalDictionary.set(settings.personalDictionary))
                case .removeTells:
                    result = try await self.removeTells(from: text, settings: settings)
                case .actionKey(let key) where key.localTransform != nil:
                    result = key.localTransform!.apply(to: text)
                case .fix, .actionKey, .prompt, .translate, .translateInPlace, .reading:
                    let instruction: String = switch action {
                    case .actionKey(let key): key.prompt
                    case .prompt(let prompt, _): prompt
                    case .reading(let reading): reading.prompt
                    default: settings.defaultPrompt
                    }
                    let engine = EngineFactory.make(kind: settings.defaultEngine, appState: self.appState)
                    result = try await engine.process(text: text, instruction: instruction)
                    if settings.maskAISlop { result = MaskAISlop.apply(to: result, rules: settings.maskRules, keeping: text) }
                }
                if Task.isCancelled { return }
                let ms = UsageLog.elapsed(since: started)
                let engineName = switch action {
                case .spelling: "LanguageTool"
                case .removeTells: settings.removeTellsWithAI ? settings.defaultEngine.displayName : "Rules"
                default: settings.defaultEngine.displayName
                }
                // Kept either way; only an applied one is offered by the star's History.
                let entry = self.recordHistory(kind: .action, input: text, output: result, engine: engineName)
                if showOnly {
                    UsageLog.record(feature, .shown, detail: detail, ms: ms)
                    // A shown result of the user's own editable text can still be put in its place.
                    let replace: (() -> Void)? = context.isEditable ? { [weak self] in
                        UsageLog.record(feature, .applied, detail: detail, ms: ms)
                        self?.markApplied(entry)
                        self?.replace(context, with: result)
                    } : nil
                    self.popup.show(title: title, text: result, original: text, onReplace: replace)
                    return
                }
                let apply = { [weak self] in
                    UsageLog.record(feature, .applied, detail: detail, ms: ms)
                    self?.markApplied(entry)
                    self?.replace(context, with: result)
                }
                // Remove AI tells always lists what no rule could take out; other actions do when the
                // "Point out stock phrases" rule is on.
                var note: String?
                let listsPhrases = if case .removeTells = action { true } else {
                    settings.maskAISlop && settings.maskRules.contains(.stockPhrases)
                }
                if listsPhrases {
                    let left = MaskAISlop.stockPhrases(in: result)
                    if !left.isEmpty { note = "Stock phrases left: " + left.joined(separator: ", ") }
                }
                // Said once: with the Apple engine chosen, nothing else here leaves the Mac.
                if case .spelling = action, settings.previewFromMenu, settings.languageToolMode == .free, !settings.spellingNoticeShown {
                    note = "Fix spelling checks the text on languagetool.org (the free public server). Another server: Proofread > LanguageTool."
                    self.appState.settings.spellingNoticeShown = true
                }
                if settings.previewFromMenu {
                    self.preview.show(title: title, original: text, result: result, note: note,
                                      onApply: apply)
                } else {
                    apply()
                }
            } catch {
                if self.isCancellation(error) { return }
                UsageLog.record(feature, .failed, reason: "error", detail: detail)
                self.popup.show(title: "Error", text: error.localizedDescription)
            }
        }
    }

    /// Mechanical clean-up first (always including Markdown leftovers, trailing emoji and sign-offs),
    /// then, when asked for, an AI pass over what no rule can fix: stock phrases and filler.
    private func removeTells(from text: String, settings: Settings) async throws -> String {
        var result = MaskAISlop.apply(to: text, rules: Self.removeTellsRules(settings))
        if settings.removeTellsWithAI {
            let engine = EngineFactory.make(kind: settings.defaultEngine, appState: appState)
            result = try await engine.process(text: result, instruction: Self.removeTellsPrompt)
            result = MaskAISlop.apply(to: result, rules: Self.removeTellsRules(settings))
        }
        return result
    }

    /// The user's own rules plus every text-changing one -- but not "All emoji": Remove AI tells
    /// leaves emoji in a sentence on purpose (it takes the decorative ones at line ends).
    private static func removeTellsRules(_ settings: Settings) -> Set<MaskAISlopRule> {
        settings.maskRules.subtracting([.emoji]).union(MaskAISlopRule.removeTells)
    }

    static let removeTellsPrompt = """
        Rewrite this text so it no longer reads as AI-generated: drop stock phrases (delve, truly, \
        game-changer, "it's worth noting", "важно отметить" and the like), filler and over-enthusiastic \
        tone, and use plain punctuation. Keep the meaning, the language, names, numbers and the line \
        structure. Reply with the rewritten text only.
        """

    /// Puts `result` in place of the context's text: back in its app, select the range, paste.
    /// Only where the text still is: a preview can wait while the user types on, and a paste over a
    /// stale range (or over a selection the app did not make) loses or duplicates text. Then the
    /// result is shown to copy instead.
    private func replace(_ context: StarContext, with result: String) {
        let result = EdgeWhitespace.wrap(result, like: context.subject)
        let app = NSRunningApplication(processIdentifier: context.pid)
        app?.activate()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Let the app take focus back before selecting in it.
            try? await Task.sleep(for: .milliseconds(200))
            let current = ProofreadAX.currentText(of: context.element)
            let unchanged = current == context.text
            // The app's offsets map is only good for the text it was made from.
            let range: NSRange? = if unchanged {
                context.appRange
            } else if context.offsetMap == nil, let current {
                ReplaceTarget.range(context.subjectRange, in: context.text, now: current)
            } else {
                nil
            }
            guard let range, ProofreadAX.select(range, in: context.element) else {
                return self.showUnplaced(result)
            }
            try? await Task.sleep(for: .milliseconds(80))
            if let selected = ProofreadAX.selectedText(of: context.element), !selected.isEmpty,
               !Self.sameText(selected, context.subject) {
                return self.showUnplaced(result)
            }
            TextInjector.replaceSelection(with: result, restorePrevious: self.appState.settings.restoreClipboard,
                                          target: TextInjector.FocusTarget(app: app))
        }
    }

    /// The focused field's selection, when it can be put back later (see `replace`).
    private static func selectionContext() -> StarContext? {
        guard case .axField(let t) = ProofreadAX.focus(analyze: false), t.selection.length > 0, t.isEditable else { return nil }
        return StarContext(element: t.element, pid: t.pid, text: t.text, selection: t.selection,
                           offsetMap: t.offsetMap, anchor: .zero)
    }

    /// Whitespace aside: web editors report list and paragraph breaks their own way.
    private static func sameText(_ a: String, _ b: String) -> Bool {
        func squeezed(_ s: String) -> String { s.filter { !$0.isWhitespace && !$0.isNewline } }
        return squeezed(a) == squeezed(b)
    }

    private func showUnplaced(_ result: String) {
        UsageLog.record(.star, .failed, reason: "textChanged")
        popup.show(title: "Not replaced: the text has changed", text: result)
    }

    func stop() {
        voice.stop()
        stars.stop()
        settingsObserver?.cancel()
        settingsObserver = nil
        retryTimer?.invalidate()
        retryTimer = nil
        monitor.stop()
        autocomplete.stop()
        proofread.stop()
        popup.close()
        translationWindow?.orderOut(nil)
    }

    func refreshStatus() {
        appState.accessibilityGranted = AccessibilityPermission.isGranted
        appState.hotkeysActive = monitor.isRunning
        appState.appleEngineStatus = AppleFoundationEngine.availabilityStatus().message
    }

    // MARK: - Setup

    private func setupTranslationWindow() {
        guard translationWindow == nil else { return }
        let host = NSHostingController(rootView: TranslationHostView(coordinator: translationCoordinator))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.borderless]
        // Keep it a 1x1, fully transparent window placed at a NORMAL on-screen coordinate. Putting it
        // at extreme offscreen coordinates makes Mission Control zoom out to fit it (shrinking every
        // other window). Excluding it from cycling/Mission Control keeps it out of the way.
        let origin = NSScreen.main?.frame.origin ?? .zero
        window.setFrame(NSRect(x: origin.x, y: origin.y, width: 1, height: 1), display: false)
        window.alphaValue = 0.0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        window.level = .normal
        window.orderBack(nil)
        translationWindow = window
    }

    private func reconfigureWatched() {
        let s = appState.settings
        let configs = [s.defaultActionHotkey, s.translateHotkey, s.screenTranslateHotkey, s.quickTranslateHotkey]
            + [s.explainHotkey, s.summarizeHotkey].compactMap { $0 } + Array(s.commandHotkeys.values)
            + s.actionKeys.compactMap(\.hotkey)

        // Group configs that share key+modifiers so the monitor knows the highest press count to
        // expect for that key and can fire immediately once it is reached.
        var grouped: [String: WatchedHotkey] = [:]
        for hk in configs {
            let m = hk.modifiers
            let key = "\(hk.keyCode)|\(m.command)\(m.option)\(m.control)\(m.shift)"
            if var existing = grouped[key] {
                existing.maxRepeat = max(existing.maxRepeat, hk.repeatCount)
                grouped[key] = existing
            } else {
                grouped[key] = WatchedHotkey(keyCode: hk.keyCode, modifiers: m, maxRepeat: hk.repeatCount)
            }
        }
        monitor.setWatched(Array(grouped.values))
    }

    // MARK: - Burst handling

    private func handleBurst(keyCode: UInt16, modifiers: HotkeyModifiers, count: Int, changeCount: Int) {
        let s = appState.settings
        guard s.enabled, !appState.isRecordingShortcut else { return }
        burstChangeCount = changeCount
        // In BindAll's own windows (Settings, a result) Cmd+C is just copying.
        let inBindAll = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier

        func matches(_ h: HotkeyConfig) -> Bool {
            h.keyCode == keyCode && h.modifiers == modifiers && h.repeatCount == count
        }

        // Quick Translate opens an interactive window; it does not need a selection and is allowed
        // even while another action is in flight.
        if matches(s.quickTranslateHotkey) {
            UsageLog.record(.quickTranslate, .shown, detail: "source:hotkey")
            quickTranslate.toggle()
            return
        }

        guard !isBusy, !inBindAll else { return }

        if matches(s.defaultActionHotkey) {
            runDefaultAction()
        } else if matches(s.translateHotkey) {
            runTranslate()
        } else if matches(s.screenTranslateHotkey) {
            translateFromScreen()
        } else if s.explainHotkey.map(matches) == true {
            runReading(.explain)
        } else if s.summarizeHotkey.map(matches) == true {
            runReading(.summarize)
        } else if let command = SelectionCommand.allCases.first(where: { s.commandHotkeys[$0.settingsKey].map(matches) == true }) {
            runCommand(command)
        } else if let key = s.actionKeys.first(where: { $0.hotkey.map(matches) == true }) {
            // A custom action key bound to its own shortcut: run its prompt on the selection.
            runDefaultAction(fixedInstruction: key.prompt, actionKey: key, showOnly: key.showOnly)
        }
    }

    /// Marks the coordinator busy and schedules a watchdog so a stalled operation can never
    /// permanently block future hotkeys.
    private func beginBusy() {
        isBusy = true
        appState.isProcessing = true
        stars.setBusy(true)
        installEscMonitor()
        busyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // Stop the action too: left running, a late result would be pasted wherever the user is
            // by then, with Esc no longer able to stop it.
            if self?.currentTask != nil { UsageLog.record(.fix, .failed, reason: "timeout") }
            self?.currentTask?.cancel()
            self?.currentTask = nil
            self?.isBusy = false
            self?.appState.isProcessing = false
            self?.stars.setBusy(false)
            self?.removeEscMonitor()
        }
        busyWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    private func endBusy() {
        busyWatchdog?.cancel()
        busyWatchdog = nil
        isBusy = false
        appState.isProcessing = false
        stars.setBusy(false)
        currentTask = nil
        removeEscMonitor()
    }

    // MARK: - Esc cancellation

    /// While busy, Esc (key code 53) cancels the in-flight engine task. A global monitor catches it
    /// when another app has focus (the usual case); a local monitor catches it in our own windows.
    private func installEscMonitor() {
        guard escGlobalMonitor == nil, escLocalMonitor == nil else { return }
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.currentTask?.cancel() }
        }
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only while there is something to cancel: otherwise Esc belongs to the window.
            guard event.keyCode == 53, let task = self?.currentTask else { return event }
            task.cancel()
            return nil
        }
    }

    private func removeEscMonitor() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
    }

    /// Esc cancels the running task; engines report that in their own ways (the on-device model
    /// throws its own error, not `CancellationError`), so a cancelled task counts whatever it threw --
    /// otherwise Esc ended in an "Error" window.
    private func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case OCRService.OCRError.cancelled = error { return true }
        return false
    }

    /// Explain and Summarize: about text someone else wrote, so the result is only shown.
    nonisolated enum Reading {
        case explain, summarize

        var title: String { self == .explain ? "Explain" : "Summary" }
        var feature: UsageFeature { self == .explain ? .explain : .summarize }
        var prompt: String {
            switch self {
            case .explain: """
                Explain what this text says and means in plain words, briefly, in the same language as the \
                text. Spell out jargon, abbreviations and anything implied. Reply with the explanation only, as plain text without Markdown.
                """
            case .summarize: """
                Summarize this text in one to three sentences, in the same language as the text. Keep names, \
                numbers and decisions. Reply with the summary only, as plain text without Markdown.
                """
            }
        }
    }

    private func runReading(_ reading: Reading, forceCopy: Bool = false) {
        runDefaultAction(fixedInstruction: reading.prompt, forceCopy: forceCopy, showOnly: true, reading: reading)
    }

    /// Runs the text pipeline on the current selection with `fixedInstruction`, or the default prompt.
    private func runDefaultAction(fixedInstruction: String? = nil, forceCopy: Bool = false,
                                  actionKey key: ActionKey? = nil, showOnly: Bool = false, reading: Reading? = nil) {
        let actionKey = key?.logToken
        let actionTitle = key?.title ?? reading?.title
        let settings = appState.settings
        let feature: UsageFeature = reading?.feature ?? (actionKey == nil ? .fix : .actionKey)
        let source = forceCopy ? "source:menu" : "source:hotkey"
        let started = ContinuousClock.now
        let engine = EngineFactory.make(kind: settings.defaultEngine, appState: appState)
        beginBusy()
        // Capture where the result must land before the (possibly slow) engine call.
        let target = TextInjector.FocusTarget.capture()
        // And the selection itself, for a preview: by the time Apply is clicked the user may have
        // moved on, and a plain paste would land over whatever is selected then.
        let anchor = settings.previewFromHotkeys && !showOnly ? Self.selectionContext() : nil

        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }

            // The default-action hotkey is Cmd+C-based, so the selection is already on the pasteboard.
            // A per-action-key shortcut (fixedInstruction) or a menu invocation (forceCopy) does NOT
            // copy, so we copy it ourselves.
            let selection = (fixedInstruction != nil || forceCopy)
                ? SelectionReader.copyCurrentSelection()
                : SelectionReader.currentSelection(previousChangeCount: self.burstChangeCount)

            guard let text = selection,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UsageLog.record(feature, .failed, reason: "noSelection", detail: actionKey ?? source)
                self.popup.show(title: "BindAll", text: "No text selected.")
                return
            }

            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let instruction = fixedInstruction ?? settings.defaultPrompt

            do {
                let local = key?.localTransform
                var result: String
                if let local { result = local.apply(to: content) } else {
                    result = try await engine.process(text: content, instruction: instruction)
                }
                if Task.isCancelled { return }
                if settings.maskAISlop, local == nil {
                    result = MaskAISlop.apply(to: result, rules: settings.maskRules, keeping: content)
                }
                let entry = self.recordHistory(kind: .action, input: content, output: result,
                                               engine: settings.defaultEngine.displayName)
                if showOnly {
                    UsageLog.record(feature, .shown, detail: actionKey ?? source, ms: UsageLog.elapsed(since: started))
                    self.popup.show(title: actionTitle ?? "Result", text: result, original: content)
                    return
                }
                let original = content
                let replace = { [weak self] in
                    self?.markApplied(entry)
                    if let anchor, Self.sameText(anchor.subject, text) {
                        self?.replace(anchor, with: result)
                    } else {
                        TextInjector.replaceSelection(with: EdgeWhitespace.wrap(result, like: text),
                                                      restorePrevious: settings.restoreClipboard, target: target)
                    }
                    UsageLog.record(feature, .applied, detail: actionKey ?? source,
                                    ms: UsageLog.elapsed(since: started))
                }
                if settings.previewFromHotkeys {
                    self.preview.show(title: actionTitle ?? "Fix", original: original,
                                      result: result, onApply: replace)
                } else {
                    replace()
                }
            } catch {
                if self.isCancellation(error) {
                    UsageLog.record(feature, .dismissed, reason: "cancelled", detail: actionKey ?? source)
                    return
                }
                UsageLog.record(feature, .failed, reason: "error", detail: actionKey ?? source,
                                ms: UsageLog.elapsed(since: started))
                self.popup.show(title: "Error", text: error.localizedDescription)
            }
        }
    }

    private func runTranslate(forceCopy: Bool = false) {
        beginBusy()
        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }

            let selection = forceCopy
                ? SelectionReader.copyCurrentSelection()
                : SelectionReader.currentSelection(previousChangeCount: self.burstChangeCount)
            guard let text = selection,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UsageLog.record(.translate, .failed, reason: "noSelection")
                self.popup.show(title: "BindAll", text: "No text selected.")
                return
            }
            await self.translateAndShow(text, historyKind: .translate)
        }
    }

    // MARK: - Menu entry points

    /// Invoked from the status menu. Runs after a short delay so the menu fully dismisses and focus
    /// returns to the previously active app before the selection is copied.
    private enum MenuAction { case fix, translate, explain, summarize }

    func menuFix() { runFromMenu(.fix) }
    func menuTranslate() { runFromMenu(.translate) }
    func menuExplain() { runFromMenu(.explain) }
    func menuSummarize() { runFromMenu(.summarize) }
    func menuScreenTranslate() { translateFromScreen() }

    func menuCommand(_ command: SelectionCommand) {
        guard !isBusy else { return }
        // As `runFromMenu`: the menu closes and the app gets its focus back first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.runCommand(command) }
    }

    /// A star action on the focused field's selection, without the star.
    private func runCommand(_ command: SelectionCommand) {
        UsageLog.record(.star, .accepted, detail: "command:\(command.rawValue)")
        guard let context = Self.selectionContext() else {
            popup.show(title: "BindAll", text: "Select the text to change first, in a field you can type in.")
            return
        }
        switch command {
        case .customPrompt: askForPrompt(context)
        case .spelling: runStarAction(.spelling, context)
        case .removeTells: runStarAction(.removeTells, context)
        case .translateInPlace: runStarAction(.translateInPlace, context)
        }
    }

    func menuQuickTranslate() {
        UsageLog.record(.quickTranslate, .shown, detail: "source:menu")
        quickTranslate.toggle()
    }

    private func runFromMenu(_ which: MenuAction) {
        // A click is a clear request: the master switch stands down only what fires by itself.
        guard !isBusy else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            switch which {
            case .fix: self.runDefaultAction(forceCopy: true)
            case .translate: self.runTranslate(forceCopy: true)
            case .explain: self.runReading(.explain, forceCopy: true)
            case .summarize: self.runReading(.summarize, forceCopy: true)
            }
        }
    }

    /// Captures a screen region, OCRs it, then translates the recognized text. Triggered from the menu.
    func translateFromScreen() {
        guard !isBusy else { return }
        beginBusy()
        Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }
            do {
                let text = try await OCRService.captureAndRecognize()
                await self.translateAndShow(text, historyKind: .ocr)
            } catch {
                UsageLog.record(.ocr, .failed, reason: self.isCancellation(error) ? "cancelled" : "error")
                if self.isCancellation(error) { return }
                self.popup.show(title: "OCR", text: error.localizedDescription)
            }
        }
    }

    /// Records a successful operation in history (if enabled in settings).
    private func markApplied(_ id: UUID?) {
        if let id { HistoryStore.shared.markApplied(id) }
    }

    /// Returns the entry's id, for `markApplied` once the result goes into the text.
    @discardableResult
    func recordHistory(kind: HistoryEntry.Kind, input: String, output: String, engine: String, applied: Bool = false) -> UUID? {
        guard appState.settings.historyEnabled else { return nil }
        return HistoryStore.shared.record(kind: kind, input: input, output: output, engine: engine, applied: applied)
    }

    /// Shared translation + popup, using the configured two-language pair.
    /// With `context` the translation replaces the star's text (through the preview when that is on)
    /// instead of opening in the popup.
    private func translateAndShow(_ text: String, historyKind: HistoryEntry.Kind, replacing context: StarContext? = nil) async {
        let settings = appState.settings
        let feature: UsageFeature = historyKind == .ocr ? .ocr : .translate
        let started = ContinuousClock.now
        let detected = LanguageDetector.detect(text)
        let detectedCode = detected?.languageCode?.identifier
        let sourceSetting = settings.sourceLanguage
        let direction = LanguagePair.resolve(detected: detectedCode, source: sourceSetting, target: settings.targetLanguage)
        let from = direction.from.map { Locale.Language(identifier: $0) }
        let targetCode = direction.to
        let target = Locale.Language(identifier: targetCode)
        let sourceDisplay = detectedCode.map { AppLanguages.name(for: $0) } ?? AppLanguages.name(for: sourceSetting)

        // Nothing to translate when the text is already in the target language. This is the common
        // false trigger for the download prompt when the source is auto-detected.
        // From the screen the recognized text is a result in itself: shown whenever it cannot be
        // translated, instead of only saying why.
        let isOCR = historyKind == .ocr
        if direction.isAlreadyThere {
            if isOCR { return popup.show(title: "Recognized text: already in \(AppLanguages.name(for: targetCode))", text: text) }
            popup.show(title: "Translation",
                       text: "This text is already in \(AppLanguages.name(for: targetCode)).")
            return
        }

        // Only block on a missing language pack when the source is actually known and differs from
        // the target (checking both directions, since a pack installed one way covers both). With an
        // unknown source, let the Translation framework auto-detect and surface any real problem
        // itself, rather than guessing a source and prompting to download something already present.
        if let from, from.languageCode?.identifier != targetCode {
            let forward = await TranslationSupport.isInstalledConfirmed(from: from, to: target)
            let backward = await TranslationSupport.isInstalledConfirmed(from: target, to: from)
            if !forward && !backward {
                if isOCR {
                    return popup.show(title: "Recognized text: \(sourceDisplay) -> \(AppLanguages.name(for: targetCode)) is not downloaded", text: text)
                }
                popup.show(
                    title: "Translation",
                    text: "\(sourceDisplay) -> \(AppLanguages.name(for: targetCode)) is not downloaded yet. Open System Settings > General > Language & Region > Translation Languages to download it, then try again."
                )
                return
            }
        }

        do {
            let translation = try await translationCoordinator.translate(text, from: from, to: target)
            if Task.isCancelled { return }
            let entry = recordHistory(kind: historyKind, input: text, output: translation, engine: "Apple Translation")
            UsageLog.record(feature, .shown, ms: UsageLog.elapsed(since: started))
            if let context {
                let title = "Translate: \(sourceDisplay) → \(AppLanguages.name(for: targetCode))"
                let apply: () -> Void = { [weak self] in
                    UsageLog.record(feature, .applied, detail: "inPlace")
                    self?.markApplied(entry)
                    self?.replace(context, with: translation)
                }
                if settings.previewFromMenu {
                    preview.show(title: title, original: text, result: translation, onApply: apply)
                } else {
                    apply()
                }
                return
            }
            popup.show(title: "Translation", text: translation, original: text, sourceLanguage: sourceDisplay,
                       targetLanguage: AppLanguages.name(for: targetCode))
        } catch {
            if isCancellation(error) { return }
            UsageLog.record(feature, .failed, reason: "error")
            if isOCR { return popup.show(title: "Recognized text: translation failed", text: text) }
            popup.show(title: "Translation failed", text: error.localizedDescription)
        }
    }
}
