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

        monitor.onBurst = { [weak self] keyCode, mods, count in
            self?.handleBurst(keyCode: keyCode, modifiers: mods, count: count)
        }
        reconfigureWatched()
        if !monitor.start() {
            Self.log.error("hotkey monitor failed to start (trusted=\(AccessibilityPermission.isGranted, privacy: .public))")
        }
        updateAutocomplete()
        updateProofread()
        setupStars()

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
        proofread.configure(cfg,
                            engine: EngineFactory.makeLanguageTool(appState: appState),
                            language: s.languageToolLanguage)
        // Both features consume Tab, so only one popup may be live at a time.
        proofread.onSessionChange = { [weak self] active in
            if active { self?.autocomplete.suspend() } else { self?.autocomplete.resume() }
        }
        proofread.onAddWord = { [weak self] word in
            guard let self else { return }
            self.appState.settings.personalDictionary = PersonalDictionary.adding(word, to: self.appState.settings.personalDictionary)
        }
        // Many words change at once, so the result is always previewed before it is written.
        proofread.onFixAll = { [weak self] context, result, count in
            self?.preview.show(title: "Fix all (\(count))", original: context.text, result: result,
                               near: context.anchor) { [weak self] in
                UsageLog.record(.proofread, .applied, detail: "fixAll:\(count)")
                self?.replace(context, with: result)
            }
        }
    }

    // MARK: - Stars

    private func setupStars() {
        stars.appAllowed = { [weak self] in self?.proofreadAppAllowed() ?? false }
        stars.onOpen = { [weak self] context, view in self?.openStarMenu(context, at: view) }
        updateStars()
    }

    private func updateStars() {
        let s = appState.settings
        let on = s.enabled && AccessibilityPermission.isGranted
        stars.apply(FieldStarController.Config(fieldEnabled: on && s.starFieldEnabled,
                                               selectionEnabled: on && s.starSelectionEnabled))
    }

    /// Stars follow the Proofread app filter: an app where checking is unwanted wants no star either.
    private func proofreadAppAllowed() -> Bool {
        let s = appState.settings
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        switch s.proofreadAppMode {
        case "allow": return s.proofreadApps.contains(bundle)
        case "deny": return !s.proofreadApps.contains(bundle)
        default: return true
        }
    }

    /// What a star menu item does.
    enum StarAction {
        case fix, spelling, translate, removeTells
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
        add("Fix", "wand.and.stars") { [weak self] in self?.runStarAction(.fix, context) }
        add("Fix spelling", "textformat.abc") { [weak self] in self?.runStarAction(.spelling, context) }
        add("Translate", "globe") { [weak self] in self?.runStarAction(.translate, context) }
        add("Remove AI tells", "eraser") { [weak self] in self?.runStarAction(.removeTells, context) }
        let keys = appState.settings.actionKeys.filter { !$0.prompt.isEmpty }
        if !keys.isEmpty {
            menu.addItem(.separator())
            for key in keys {
                let title = key.label.isEmpty ? key.key : key.label
                add(title, "sparkle") { [weak self] in self?.runStarAction(.actionKey(key), context) }
            }
        }
        menu.addItem(.separator())
        add("Custom prompt…", "text.bubble") { [weak self] in self?.askForPrompt(context) }
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
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
    }

    private func askForPrompt(_ context: StarContext) {
        UsageLog.record(.customPrompt, .shown)
        customPrompt.show(recent: appState.settings.recentPrompts,
                          scope: context.isSelection ? "Selection" : "Whole text",
                          near: context.anchor) { [weak self] prompt, showOnly, save in
            self?.rememberPrompt(prompt, saveAsActionKey: save)
            self?.runStarAction(.prompt(prompt, showOnly: showOnly), context)
        }
    }

    private func rememberPrompt(_ prompt: String, saveAsActionKey: Bool) {
        var recent = appState.settings.recentPrompts.filter { $0 != prompt }
        recent.insert(prompt, at: 0)
        appState.settings.recentPrompts = Array(recent.prefix(5))
        if saveAsActionKey, !appState.settings.actionKeys.contains(where: { $0.prompt == prompt }) {
            appState.settings.actionKeys.append(ActionKey(key: "", label: String(prompt.prefix(40)), prompt: prompt))
        }
    }

    /// Runs a star action on the context's text, then previews (or shows) the result.
    private func runStarAction(_ action: StarAction, _ context: StarContext) {
        let text = context.subject
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let settings = appState.settings
        if case .translate = action {
            UsageLog.record(.star, .accepted, detail: "translate")
            Task { await translateAndShow(text, historyKind: .translate) }
            return
        }
        guard !isBusy else { return }
        beginBusy()
        let started = ContinuousClock.now
        let (feature, title, detail): (UsageFeature, String, String) = switch action {
        case .fix: (.fix, "Fix", "source:star")
        case .spelling: (.spelling, "Fix spelling", "source:star")
        case .removeTells: (.removeTells, "Remove AI tells", "source:star")
        case .actionKey(let key): (.actionKey, key.label.isEmpty ? key.key : key.label, key.key)
        case .prompt: (.customPrompt, "Custom prompt", "source:star")
        case .translate: (.translate, "Translate", "source:star")
        }
        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }
            do {
                var result: String
                switch action {
                case .spelling:
                    result = try await EngineFactory.makeLanguageTool(appState: self.appState).correct(text)
                case .removeTells:
                    result = try await self.removeTells(from: text, settings: settings)
                case .fix, .actionKey, .prompt, .translate:
                    let instruction: String = switch action {
                    case .actionKey(let key): key.prompt
                    case .prompt(let prompt, _): prompt
                    default: settings.defaultPrompt
                    }
                    let engine = EngineFactory.make(kind: settings.defaultEngine, appState: self.appState)
                    result = try await engine.process(text: text, instruction: instruction)
                    if settings.maskAISlop { result = MaskAISlop.apply(to: result, rules: settings.maskRules) }
                }
                if Task.isCancelled { return }
                self.recordHistory(kind: .action, input: text, output: result, engine: settings.defaultEngine.displayName)
                let ms = UsageLog.elapsed(since: started)
                if case .prompt(_, true) = action {
                    UsageLog.record(feature, .shown, detail: detail, ms: ms)
                    self.popup.show(title: title, text: result, original: text)
                    return
                }
                let apply = { [weak self] in
                    UsageLog.record(feature, .applied, detail: detail, ms: ms)
                    self?.replace(context, with: result)
                }
                var note: String?
                if case .removeTells = action {
                    let left = MaskAISlop.stockPhrases(in: result)
                    if !left.isEmpty { note = "Stock phrases left: " + left.joined(separator: ", ") }
                }
                if settings.previewFromMenu {
                    self.preview.show(title: title, original: text, result: result, note: note,
                                      near: context.anchor, onApply: apply)
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
        var result = MaskAISlop.apply(to: text, rules: settings.maskRules.union(MaskAISlopRule.removeTells))
        if settings.removeTellsWithAI {
            let engine = EngineFactory.make(kind: settings.defaultEngine, appState: appState)
            result = try await engine.process(text: result, instruction: Self.removeTellsPrompt)
            result = MaskAISlop.apply(to: result, rules: settings.maskRules.union(MaskAISlopRule.removeTells))
        }
        return result
    }

    static let removeTellsPrompt = """
        Rewrite this text so it no longer reads as AI-generated: drop stock phrases (delve, truly, \
        game-changer, "it's worth noting", "важно отметить" and the like), filler and over-enthusiastic \
        tone, and use plain punctuation. Keep the meaning, the language, names, numbers and the line \
        structure. Reply with the rewritten text only.
        """

    /// Puts `result` in place of the context's text: back in its app, select the range, paste.
    private func replace(_ context: StarContext, with result: String) {
        let app = NSRunningApplication(processIdentifier: context.pid)
        app?.activate()
        Task { @MainActor [weak self] in
            // Let the app take focus back before selecting in it.
            try? await Task.sleep(for: .milliseconds(200))
            _ = ProofreadAX.select(context.appRange, in: context.element)
            try? await Task.sleep(for: .milliseconds(80))
            TextInjector.replaceSelection(with: result, restorePrevious: self?.appState.settings.restoreClipboard ?? true,
                                          target: TextInjector.FocusTarget(app: app))
        }
    }

    func stop() {
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

    private func handleBurst(keyCode: UInt16, modifiers: HotkeyModifiers, count: Int) {
        let s = appState.settings
        guard s.enabled, !appState.isRecordingShortcut else { return }

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

        guard !isBusy else { return }

        if matches(s.defaultActionHotkey) {
            runDefaultAction()
        } else if matches(s.translateHotkey) {
            runTranslate()
        } else if matches(s.screenTranslateHotkey) {
            translateFromScreen()
        } else if let key = s.actionKeys.first(where: { $0.hotkey.map(matches) == true }) {
            // A custom action key bound to its own shortcut: run its prompt on the selection.
            runDefaultAction(fixedInstruction: key.prompt, actionKey: key.key)
        }
    }

    /// Marks the coordinator busy and schedules a watchdog so a stalled operation can never
    /// permanently block future hotkeys.
    private func beginBusy() {
        isBusy = true
        appState.isProcessing = true
        installEscMonitor()
        busyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isBusy = false
            self?.appState.isProcessing = false
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
            if event.keyCode == 53 { self?.currentTask?.cancel(); return nil }
            return event
        }
    }

    private func removeEscMonitor() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case OCRService.OCRError.cancelled = error { return true }
        return false
    }

    /// Runs the text pipeline on the current selection. With `fixedInstruction` (a per-key
    /// shortcut) the whole selection is the content; otherwise the separator/key syntax is parsed.
    private func runDefaultAction(fixedInstruction: String? = nil, forceCopy: Bool = false,
                                  actionKey: String? = nil) {
        let settings = appState.settings
        let feature: UsageFeature = actionKey == nil ? .fix : .actionKey
        let source = forceCopy ? "source:menu" : "source:hotkey"
        let started = ContinuousClock.now
        let engine = EngineFactory.make(kind: settings.defaultEngine, appState: appState)
        beginBusy()
        // Capture where the result must land before the (possibly slow) engine call.
        let target = TextInjector.FocusTarget.capture()

        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }

            // The default-action hotkey is Cmd+C-based, so the selection is already on the pasteboard.
            // A per-action-key shortcut (fixedInstruction) or a menu invocation (forceCopy) does NOT
            // copy, so we copy it ourselves.
            let selection = (fixedInstruction != nil || forceCopy)
                ? SelectionReader.copyCurrentSelection()
                : SelectionReader.currentSelection(previousChangeCount: Int.min)

            guard let text = selection,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UsageLog.record(feature, .failed, reason: "noSelection", detail: actionKey ?? source)
                self.popup.show(title: "BindAll", text: "No text selected.")
                return
            }

            let parsed: ParsedAction
            if let fixedInstruction {
                parsed = ParsedAction(
                    content: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    instruction: fixedInstruction,
                    hadExplicitInstruction: true
                )
            } else {
                parsed = PromptParser.parse(
                    text: text,
                    separator: settings.separator,
                    defaultPrompt: settings.defaultPrompt,
                    actionKeys: settings.actionKeys
                )
            }

            do {
                var result = try await engine.process(text: parsed.content, instruction: parsed.instruction)
                if Task.isCancelled { return }
                if settings.maskAISlop {
                    result = MaskAISlop.apply(to: result, rules: settings.maskRules)
                }
                self.recordHistory(kind: .action, input: parsed.content, output: result,
                                   engine: settings.defaultEngine.displayName)
                let original = parsed.content
                let replace = {
                    TextInjector.replaceSelection(with: result, restorePrevious: settings.restoreClipboard, target: target)
                    UsageLog.record(feature, .applied, detail: actionKey ?? source,
                                    ms: UsageLog.elapsed(since: started))
                }
                if settings.previewFromHotkeys {
                    self.preview.show(title: actionKey.map { "Action \($0)" } ?? "Fix", original: original,
                                      result: result, near: NSEvent.mouseLocation, onApply: replace)
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
        Task { [weak self] in
            guard let self else { return }
            defer { self.endBusy() }

            let selection = forceCopy
                ? SelectionReader.copyCurrentSelection()
                : SelectionReader.currentSelection(previousChangeCount: Int.min)
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
    private enum MenuAction { case fix, translate }

    func menuFix() { runFromMenu(.fix) }
    func menuTranslate() { runFromMenu(.translate) }
    func menuScreenTranslate() { translateFromScreen() }

    func menuQuickTranslate() {
        UsageLog.record(.quickTranslate, .shown, detail: "source:menu")
        quickTranslate.toggle()
    }

    private func runFromMenu(_ which: MenuAction) {
        guard appState.settings.enabled, !isBusy else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            switch which {
            case .fix: self.runDefaultAction(forceCopy: true)
            case .translate: self.runTranslate(forceCopy: true)
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
    func recordHistory(kind: HistoryEntry.Kind, input: String, output: String, engine: String) {
        guard appState.settings.historyEnabled else { return }
        HistoryStore.shared.record(kind: kind, input: input, output: output, engine: engine)
    }

    /// Shared translation + popup, using the configured two-language pair.
    private func translateAndShow(_ text: String, historyKind: HistoryEntry.Kind) async {
        let settings = appState.settings
        let feature: UsageFeature = historyKind == .ocr ? .ocr : .translate
        let started = ContinuousClock.now
        let detected = LanguageDetector.detect(text)
        let detectedCode = detected?.languageCode?.identifier
        let sourceSetting = settings.sourceLanguage
        let from: Locale.Language?
        let targetCode: String
        if sourceSetting == AppLanguages.autoTag {
            // Auto-detect the source; translate into the configured target.
            from = detected
            targetCode = settings.targetLanguage
        } else {
            // Explicit source: bidirectional pair {source, target}.
            from = detected ?? Locale.Language(identifier: sourceSetting)
            targetCode = (detectedCode == sourceSetting) ? settings.targetLanguage : sourceSetting
        }
        let target = Locale.Language(identifier: targetCode)
        let sourceDisplay = detectedCode.map { AppLanguages.name(for: $0) } ?? AppLanguages.name(for: sourceSetting)

        // Nothing to translate when the text is already in the target language. This is the common
        // false trigger for the download prompt when the source is auto-detected.
        if let detectedCode, detectedCode == targetCode {
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
                popup.show(
                    title: "Translation",
                    text: "\(sourceDisplay) -> \(AppLanguages.name(for: targetCode)) is not downloaded yet. Open System Settings > General > Language & Region > Translation Languages to download it, then try again."
                )
                return
            }
        }

        do {
            let translation = try await translationCoordinator.translate(text, from: from, to: target)
            recordHistory(kind: historyKind, input: text, output: translation, engine: "Apple Translation")
            UsageLog.record(feature, .shown, ms: UsageLog.elapsed(since: started))
            popup.show(title: "Translation", text: translation, original: text, sourceLanguage: sourceDisplay,
                       targetLanguage: AppLanguages.name(for: targetCode))
        } catch {
            UsageLog.record(feature, .failed, reason: "error")
            popup.show(title: "Translation failed", text: error.localizedDescription)
        }
    }
}
