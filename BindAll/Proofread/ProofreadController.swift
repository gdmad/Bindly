import AppKit
import Carbon.HIToolbox
import os

/// Steps the user through the issues LanguageTool found in the focused field, one at a time.
///
/// Two ways in:
///   - the Proofread shortcut checks the whole field and starts at the first issue;
///   - a single click inside a problem word pops the fixes for it up on its own.
/// The current issue is never selected in the user's own field -- its underline already marks it,
/// and leaving a selection behind fought both the app's own UI (Slack's formatting toolbar lands on
/// a selection) and the user's own editing (one Backspace would delete the whole selected word). See
/// `showCurrent()`.
///
/// Threading: an active `CGEventTap` is only alive while the popup is showing, and its callback does
/// nothing but read a lock-protected snapshot and hand the key to main. See `AutocompleteController`
/// for why that matters -- an active tap makes the window server wait on us for every keystroke.
@MainActor
final class ProofreadController {
    enum AppFilterMode: String { case all, allow, deny }

    struct Config {
        var enabled = false
        var maxReplacements = 3
        var layout = PopupLayout.column
        var fontSize: CGFloat = 13
        var minLength = 12
        var restoreClipboard = false
        var appMode = AppFilterMode.all
        var apps: Set<String> = []
        /// `PersonalDictionary.set` of the user's words.
        var dictionary: Set<String> = []
        /// "Check before sending" in chat apps (`PreSendPolicy.chatApps`).
        var preSend = false
    }

    private var config = Config()
    /// "Fix all": the field (as a star context), the corrected text and how many fixes it holds.
    /// The coordinator shows the preview and writes the result, the way the star's actions do.
    var onFixAll: ((StarContext, String, Int) -> Void)?
    /// "Add to dictionary": the coordinator stores the word; `configure` then brings the new set back.
    var onAddWord: ((String) -> Void)?
    private var provider: LanguageToolProofreadProvider?
    /// Places the user skipped; see `ProofreadSkips`.
    private var skips = ProofreadSkips()
    /// Whether the fixes popup is open, for the usage log's shown/dismissed pairs.
    private var popupShown = false
    /// Went into the fixes with ↓: only then do the arrows choose among them.
    private var browsing = false
    private var inputSourceObserver: NSObjectProtocol?
    private let popover = ProofreadPopover()
    private let underlines = UnderlineOverlay()
    private static let log = Logger(subsystem: "com.evgeny.bindall", category: "proofread")

    // Live state: what was found in the focused field. Outlives the popup -- the underlines stay up
    // while the user reads, and a click can open the fixes without another round trip.
    private var target: ProofTarget?
    private var issues: [TextIssue] = [] {
        didSet {
            guard issues.count != oldValue.count else { return }
            // After the change settles: the field star shows the count.
            DispatchQueue.main.async { [weak self] in self?.onIssuesChange?() }
        }
    }
    /// The number of issues changed (found, fixed, skipped, cleared).
    var onIssuesChange: (() -> Void)?
    /// The field text the current `issues` were found in; a re-check is pointless while it matches.
    private var lastCheckedText = ""
    // Navigation state: which issue the popup is on.
    private var currentIndex = 0
    private var selectedReplacement = 0
    private var checkTask: Task<Void, Never>?
    /// Bumped on every new check and on end(); a result that comes back stale is dropped.
    private var generation = 0
    /// True while a check started from a click (one that carries the clicked word) is in flight. The
    /// post-write re-check stands down for it rather than cancelling it -- see `RecheckPolicy`.
    private var pendingSelectionCheck = false
    /// Accessibility state as of the last `configure()`, so a false -> true transition can force a
    /// fresh monitor install (see `configure`).
    private var lastAXGranted = false

    /// Typing pause that triggers a live re-check.
    private let typingPause: TimeInterval = 0.6
    private var keyMonitor: Any?
    private var typingDebounce: DispatchWorkItem?

    /// The last server error, so live checking reports it once instead of on every pause.
    private var lastError: String?
    /// True while a fix is being applied (the applier waits for the app's selection to settle).
    private var isApplying = false

    // Key interception, alive only while the popup is up.
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var tapEnabled = false
    /// Whether a navigable popup session is currently announced to `onSessionChange`.
    private var sessionActive = false
    /// The one piece of state the tap callback reads. It lives outside the main actor because the
    /// callback runs on the tap thread and must decide without hopping or blocking.
    private let shared = SharedState()

    /// Written on main, read on the tap thread, guarded by its own lock.
    private final class SharedState: @unchecked Sendable {
        struct Snapshot {
            var isActive = false
            /// Went into the fixes with ↓ (see `ProofreadKeyPolicy`).
            var browsing = false
            var atFirst = true
            var layout = PopupLayout.column
            /// The popup sits above the word: ↑ goes into the fixes.
            var opensUpward = true
        }

        private var lock = os_unfair_lock()
        private var value = Snapshot()

        var snapshot: Snapshot {
            get {
                os_unfair_lock_lock(&lock)
                defer { os_unfair_lock_unlock(&lock) }
                return value
            }
            set {
                os_unfair_lock_lock(&lock)
                value = newValue
                os_unfair_lock_unlock(&lock)
            }
        }

        var isActive: Bool {
            get { snapshot.isActive }
            set { var s = snapshot; s.isActive = newValue; snapshot = s }
        }
    }


    // Auto-popup on click.
    private var mouseMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var clickDebounce: DispatchWorkItem?

    /// Set by the coordinator so a proofread session can silence autocomplete: both features eat Tab.
    var onSessionChange: ((Bool) -> Void)?
    private let preSend = PreSendGuard()
    /// An autocomplete suggestion is up: its Return wins over the pre-send check.
    private var suggestionVisible = false
    private var menuOpen = false

    var isSessionActive: Bool { !issues.isEmpty && target != nil }

    /// Issues found in `element` by the last check, for the star menu.
    func issueCount(in element: AXUIElement) -> Int {
        guard let target, CFEqual(target.element, element) else { return 0 }
        return issues.count
    }

    /// Opens the fixes popup on the first issue (from the star menu).
    func showFirstIssue() {
        guard !issues.isEmpty else { return }
        focusIssue(0)
    }

    // MARK: - Lifecycle

    func configure(_ config: Config, engine: LanguageToolEngine, language: String) {
        if preSend.onAction == nil { preSend.onAction = { [weak self] in self?.handlePreSend($0) } }
        let dictionaryChanged = config.dictionary != self.config.dictionary
        self.config = config
        if dictionaryChanged, !issues.isEmpty {
            issues = PersonalDictionary.filter(issues, words: config.dictionary)
            redrawUnderlines()
        }
        let provider = self.provider ?? LanguageToolProofreadProvider(engine: engine, language: language)
        self.provider = provider
        Task { await provider.configure(engine: engine, language: language) }

        // `NSEvent.addGlobalMonitorForEvents` for .keyDown silently fails without Accessibility, and
        // the monitor-installed guards below then block a retry forever. Force a fresh install the
        // moment permission actually becomes available, instead of waiting for the app to restart.
        let granted = AccessibilityPermission.isGranted
        let justGranted = granted && !lastAXGranted
        lastAXGranted = granted
        if justGranted, config.enabled {
            Self.log.notice("Accessibility just granted; reinstalling proofread monitors")
            stopClickMonitor()
            stopTypingMonitor()
        }

        if config.enabled {
            startClickMonitor()
        } else {
            stopClickMonitor()
        }
        if config.enabled {
            startTypingMonitor()
        } else {
            stopTypingMonitor()
            end()
        }
    }

    func stop() {
        preSend.stop()
        end()
        stopClickMonitor()
        stopTypingMonitor()
    }

    // MARK: - Entry points
    //
    // There is no shortcut: checking happens on its own after a pause in typing, and the fixes are
    // opened by clicking a underlined word. Tab still moves to the next issue while the popup is up.

    /// Mouse-up: show the fixes for the clicked word. When the live pass already checked this text
    /// the popup opens instantly; otherwise the click doubles as a check request.
    private func clickedInText() {
        guard config.enabled, AccessibilityPermission.isGranted, appAllowed() else { return }
        guard case .axField(let found) = ProofreadAX.focus(), found.isEditable else { return }
        guard found.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= config.minLength else { return }

        var probe: NSRange
        switch ProofreadClickPolicy.action(selection: found.selection, caret: found.caret, in: found.text) {
        case .ignore:
            return
        case .dismiss:
            // Clicked whitespace or an empty spot: close the popup but keep the underlines.
            endNavigation()
            return
        case .probe(let word):
            probe = word
            // The caret comes from the app's selection, which in Chromium is indexed differently
            // from the value we measured the word in. Translate it back into our offsets, so the
            // popup belongs to the word actually clicked. With an offset map `focus()` has already
            // done that exactly.
            let clicked = (found.text as NSString).substring(with: word)
            if found.offsetMap == nil,
               let appRange = ProofreadAX.alignedRange(word, expecting: clicked, in: found.element),
               appRange != word,
               let ourRange = WordBoundary.wordRange(at: word.location - (appRange.location - word.location),
                                                     in: found.text) {
                probe = ourRange
            }
        }

        let sameField = target?.element == found.element
        // The click landed on something we already knew was a problem: worth saying so if the fresh
        // check disagrees, instead of closing the popup without a word.
        let hadIssue = sameField && IssueMerger.firstIssue(in: issues, overlapping: probe) != nil
        target = found
        if sameField, found.text == lastCheckedText,
           showFixes(overlapping: probe) {
            return // already known: no round trip
        }
        // The issues belong to the field they were found in; keep them only while the field is.
        if !sameField { issues = [] }
        // Either the text is new or the click missed every known issue (ranges may have drifted
        // after an applied fix). Re-check and open the popup from the fresh result.
        check(text: found.text, offset: 0, selection: probe, announceMiss: hadIssue)
    }

    /// Typing paused: re-check the focused field so the underlines match what is on screen now.
    /// `resumeIndex`, when given (only by `recheckAfterWrite`, right after a fix landed), asks the
    /// fresh result to reopen the popup on the issue now sitting at that position -- see `check`.
    private func typingPaused(resumeIndex: Int? = nil) {
        guard config.enabled, AccessibilityPermission.isGranted, appAllowed() else { return }
        guard case .axField(let found) = ProofreadAX.focus(), found.isEditable else { clearLive(); return }
        guard found.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= config.minLength else {
            clearLive()
            return
        }

        let sameField = target?.element == found.element
        target = found
        if sameField, found.text == lastCheckedText {
            // Nothing changed (arrow keys, modifiers): just put the underlines back.
            redrawUnderlines()
            return
        }
        if !sameField { issues = [] }
        // Paragraph cache keeps this to one request for the paragraph actually edited. A resume only
        // makes sense against the same field the fix was applied in.
        check(text: found.text, offset: 0, resumeIndex: sameField ? resumeIndex : nil)
    }

    // MARK: - Checking

    /// Checks `text`; `selection`, when given, is the word the user clicked and decides whether the
    /// fixes pop up afterwards. Checking is always in the background now, so nothing is shown while
    /// it runs -- only a server error the user has not seen yet.
    private func check(text: String, offset: Int, selection: NSRange? = nil, announceMiss: Bool = false,
                       resumeIndex: Int? = nil) {
        guard let provider else { return }
        generation &+= 1
        let gen = generation
        checkTask?.cancel()
        pendingSelectionCheck = selection != nil
        // Glued list markers ("1.Buy") get a space for the check in any app; it only matters where an
        // app reports them that way.
        let breaks = (target?.breaks ?? .none).addingSpaces(ListMarkers.markerEnds(in: text))
        let chromiumElement = target.flatMap { ProofreadAX.isChromium(pid: $0.pid) ? $0.element : nil }
        let offsetMap = target?.offsetMap

        checkTask = Task { [weak self] in
            guard let self else { return }
            defer { if gen == self.generation { self.pendingSelectionCheck = false } }
            do {
                var found = breaks.mapBack(try await provider.check(breaks.checkText(text)), to: text)
                guard !Task.isCancelled, gen == self.generation else { return }
                if let element = chromiumElement {
                    ProofreadAX.cachingLeaves {
                        found.removeAll { ProofreadAX.crossesVisualBreak($0, text: text, in: element, map: offsetMap) }
                    }
                }
                let rebased = offset == 0 ? found : ProofreadCache.rebase(found, to: offset)
                self.lastError = nil
                self.applyResults(rebased, selection: selection, announceMiss: announceMiss, resumeIndex: resumeIndex)
            } catch {
                guard !Task.isCancelled, gen == self.generation else { return }
                // Live checking runs unprompted, so report a problem once rather than on every pause.
                let message = Self.describe(error)
                if message != self.lastError {
                    self.lastError = message
                    self.flash(message)
                }
            }
        }
    }

    private func applyResults(_ found: [TextIssue], selection: NSRange?, announceMiss: Bool = false,
                              resumeIndex: Int? = nil) {
        // Cap once at the door so the popup, arrow navigation and accept all see the same list.
        issues = IssueMerger.capReplacements(PersonalDictionary.filter(skips.filter(found), words: config.dictionary),
                                             limit: config.maxReplacements)
        lastCheckedText = target?.text ?? ""
        redrawUnderlines()

        if let selection {
            // The popup only opens for a clicked word that sits on an issue.
            if !showFixes(overlapping: selection), announceMiss {
                // The word was underlined a moment ago and is not any more: say so rather than
                // leaving the click looking like it did nothing.
                flash("Nothing to fix here any more.")
            }
            return
        }
        // Fixing an issue removes exactly one element from the array, so whatever was next in
        // document order now sits at the fixed issue's old index -- no matching needed, just clamp.
        // An out-of-range index (the fixed issue was the last one) correctly opens nothing.
        if let resumeIndex, !issues.isEmpty {
            focusIssue(min(resumeIndex, issues.count - 1))
        }
    }

    /// Opens the popup for the issue under `probe`, if there is one. Keeps the underlines either way.
    /// Returns whether a popup was opened, so a click on a range that no longer holds an issue can
    /// fall back to a fresh check instead of silently doing nothing.
    @discardableResult
    private func showFixes(overlapping probe: NSRange) -> Bool {
        guard let issue = IssueMerger.firstIssue(in: issues, overlapping: probe),
              let index = issues.firstIndex(where: { $0.id == issue.id }) else {
            Self.log.debug("no issue overlaps the click probe \(probe); falling back to a re-check")
            endNavigation()
            return false
        }
        // Select the issue natively (like the shortcut path) so the user sees exactly what will be
        // replaced before accepting. Safe re-entrancy: the click monitor reacts only to real
        // mouse-ups, and an AX selection write generates none.
        focusIssue(index)
        return true
    }

    /// BindAll's own menu (the star's) is tracking: its Return picks an item, never "send".
    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        syncPreSend()
    }

    func setSuggestionVisible(_ visible: Bool) {
        suggestionVisible = visible
        syncPreSend()
    }

    /// Arms the pre-send check while a chat app's field shows issues and nothing else wants Return.
    private func syncPreSend() {
        let pid = target?.pid
        let inChat = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            .map { PreSendPolicy.chatApps.contains($0) || Self.extraChatApps.contains($0) } ?? false
        let armed = config.enabled && config.preSend && inChat && !issues.isEmpty && !popupShown && !suggestionVisible && !menuOpen
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        preSend.update { state in
            state.armed = armed
            state.pid = pid ?? 0
            if !armed && !inChat { state.warning = false }
        }
    }

    /// Only the E2E build sets this (scripts/e2e.sh): TextEdit stands in for a chat app there, where
    /// a Return that gets through is a visible newline instead of a sent message.
    private static let extraChatApps = Set(UserDefaults.standard.stringArray(forKey: "PreSendExtraApps") ?? [])

    private func handlePreSend(_ action: PreSendPolicy.Action) {
        switch action {
        case .warn:
            UsageLog.record(.proofread, .shown, detail: "presend")
            popover.showMessage(PreSendPolicy.warningText(count: issues.count), anchor: currentAnchor(), fontSize: config.fontSize)
        case .send:
            UsageLog.record(.proofread, .dismissed, reason: "sentAnyway", detail: "presend")
            popover.hide()
        case .review:
            UsageLog.record(.proofread, .accepted, detail: "presend:review")
            popover.hide()
            showFirstIssue()
        case .fixAll:
            UsageLog.record(.proofread, .accepted, detail: "presend:fixAll")
            popover.hide()
            fixAll()
        case .dismiss, .passAndDismiss:
            popover.hide()
        case .pass:
            break
        }
    }

    private func redrawUnderlines() {
        defer { syncPreSend() }
        guard !issues.isEmpty, let element = target?.element else {
            underlines.hide()
            return
        }
        let unplaced = underlines.show(issues: issues, element: element, map: target?.offsetMap)
        // An issue that cannot be found in the field would neither underline nor apply; dropping it
        // keeps "N of M" equal to what is on screen.
        if !unplaced.isEmpty {
            Self.log.debug("dropping \(unplaced.count, privacy: .public) issue(s) that could not be placed in the field")
            issues.removeAll { unplaced.contains($0.id) }
            if issues.isEmpty { underlines.hide() }
        }
    }

    // MARK: - Session

    private func focusIssue(_ index: Int) {
        guard index >= 0, index < issues.count else { endNavigation(); return }
        if !popupShown { UsageLog.record(.proofread, .shown) }
        popupShown = true
        // Stepping to another issue keeps you inside the fixes if you were there.
        currentIndex = index
        selectedReplacement = 0
        showCurrent()
        setActive(true)
        syncPreSend()
    }

    /// Shows the popup for the current issue. Never highlights the word in the user's field: editors
    /// put their own controls over a selection -- Slack's formatting toolbar lands exactly where the
    /// popup would -- and a selection left behind after the popup closes is what made a single
    /// Backspace delete the whole word instead of one character. The underline already says which
    /// word this is about, and `IssueApplier` selects the range itself, right before pasting, when a
    /// fix is accepted.
    private func showCurrent() {
        guard currentIndex < issues.count else { endNavigation(); return }
        let issue = issues[currentIndex]

        syncKeySnapshot()
        popover.show(issue: issue, selected: selectedReplacement, softSelection: !browsing,
                     position: "\(currentIndex + 1) of \(issues.count)",
                     anchor: anchor(for: issue),
                     layout: config.layout,
                     fontSize: config.fontSize,
                     onHover: { [weak self] index in self?.hoverReplacement(index) },
                     onAccept: { [weak self] index in self?.acceptReplacement(index) },
                     onClose: { [weak self] in self?.endNavigation(reason: "closeButton") },
                     fixAllCount: FixAll.fixable(issues).count,
                     onAddWord: issue.kind == .spelling ? { [weak self] in self?.addCurrentToDictionary() } : nil,
                     onFixAll: { [weak self] in self?.fixAll() })
        syncKeySnapshot() // where the popup landed decides which arrow goes into it
    }

    /// The "Skip" row comes after the fixes, so its index is the number of fixes.
    private func skipIndex(of issue: TextIssue) -> Int { issue.replacements.count }

    /// Mouse hover over a row: mirror it into the keyboard selection.
    private func hoverReplacement(_ index: Int) {
        guard let issue = issues[safe: currentIndex], index >= 0, index <= skipIndex(of: issue),
              index != selectedReplacement || !browsing else { return }
        // Pointing at a fix is choosing among them, the same as going in with ↓.
        browsing = true
        selectedReplacement = index
        showCurrent()
    }

    /// Mouse click on a row: same path as selecting it with arrows and pressing Return.
    private func acceptReplacement(_ index: Int) {
        guard let issue = issues[safe: currentIndex], index >= 0, index <= skipIndex(of: issue) else { return }
        selectedReplacement = index
        accept()
    }

    private func move(_ delta: Int) {
        guard let issue = issues[safe: currentIndex] else { return }
        selectedReplacement = max(0, min(skipIndex(of: issue), selectedReplacement + delta))
        showCurrent()
    }

    /// Moves the fix selection inside the two-row tile grid.
    /// The Skip row sits below the grid: down from the bottom row reaches it, up leaves it.
    private func moveGrid(dx: Int, dy: Int) {
        guard let issue = issues[safe: currentIndex] else { return }
        let skip = skipIndex(of: issue)
        if selectedReplacement == skip {
            guard dy < 0, skip > 0 else { return }
            selectedReplacement = skip - 1
        } else {
            let next = PopupLayout.tileIndex(from: selectedReplacement, deltaX: dx, deltaY: dy,
                                             count: issue.replacements.count,
                                             topRowCount: popover.lastTileTopCount)
            selectedReplacement = (next == selectedReplacement && dy > 0) ? skip : next
        }
        showCurrent()
    }

    /// Routes an arrow key by layout. The column keeps fixes on the vertical axis and problem
    /// stepping on the horizontal one; the line swaps them; the tile uses both axes for fixes (Tab
    /// still steps between problems).
    /// Only reached while browsing the fixes: the policy already decided the arrow belongs to them.
    private func moveArrow(dx: Int, dy: Int) {
        switch config.layout {
        case .column: move(dy)
        case .line: move(dx)
        case .tile: moveGrid(dx: dx, dy: dy)
        }
    }

    /// Going into the fixes shows the selection in full; backing out returns to the first fix, which
    /// Return would apply, shown softly.
    private func setBrowsing(_ on: Bool) {
        guard popupShown, browsing != on else { return }
        browsing = on
        if !on { selectedReplacement = 0 }
        showCurrent()
    }

    /// Publishes what the key tap needs to decide, after anything that changes it.
    private func syncKeySnapshot() {
        var snap = shared.snapshot
        snap.browsing = browsing
        snap.atFirst = selectedReplacement == 0
        snap.layout = config.layout
        snap.opensUpward = popover.placedAbove
        shared.snapshot = snap
    }

    /// Moves to another issue, wrapping around: Tab and Shift+Tab walk the problem words.
    private func step(_ delta: Int) {
        guard !issues.isEmpty else { endNavigation(); return }
        let next = (currentIndex + delta + issues.count) % issues.count
        focusIssue(next)
    }

    private func accept() {
        guard !isApplying else {
            Self.log.debug("accept ignored: a fix is already being applied")
            return
        }
        if let issue = issues[safe: currentIndex], selectedReplacement == skipIndex(of: issue) {
            skipCurrent()
            return
        }
        guard let issue = issues[safe: currentIndex],
              let replacement = issue.replacements[safe: selectedReplacement] else {
            Self.log.debug("accept: no issue/replacement at \(self.currentIndex)/\(self.selectedReplacement)")
            // With a single fixless issue, stepping would land back on it and repeat forever.
            if issues.count > 1 { step(1) } else { endNavigation() }
            return
        }
        guard let target else {
            // No AX element: the best we can do is hand them the corrected word.
            TextInjector.copyToPasteboard(replacement)
            flash("This app does not expose its text; \"\(replacement)\" is on the clipboard.")
            return
        }

        isApplying = true
        Task { @MainActor [weak self] in
            let result = await IssueApplier.apply(issue, replacement: replacement,
                                                  element: target.element, pid: target.pid,
                                                  restoreClipboard: self?.config.restoreClipboard ?? false)
            guard let self else { return }
            self.isApplying = false
            self.handleApplyResult(result, issue: issue, replacement: replacement)
        }
    }

    /// Every issue's first fix at once. The field is re-read so the result is built on what is there
    /// now; the preview (or the write) is left to `onFixAll`.
    private func fixAll() {
        guard !isApplying, let target, let onFixAll else { return }
        let text = ProofreadAX.currentText(of: target.element) ?? target.text
        let outcome = FixAll.apply(issues, to: text)
        guard outcome.fixed > 0 else { flash("Nothing to fix."); return }
        let anchor = currentAnchor()
        endNavigation(reason: "fixAll")
        UsageLog.record(.proofread, .shown, detail: "fixAll:\(outcome.fixed)")
        onFixAll(StarContext(element: target.element, pid: target.pid, text: text,
                             selection: NSRange(location: 0, length: 0), offsetMap: target.offsetMap,
                             anchor: NSPoint(x: anchor.minX, y: anchor.minY)),
                 outcome.text, outcome.fixed)
    }

    /// The current word goes into the personal dictionary; every underline on it goes at once.
    private func addCurrentToDictionary() {
        guard let issue = issues[safe: currentIndex] else { return }
        let word = issue.original
        UsageLog.record(.proofread, .skipped, reason: "dictionary")
        config.dictionary.insert(PersonalDictionary.normalize(word))
        onAddWord?(word)
        let index = currentIndex
        issues = PersonalDictionary.filter(issues, words: config.dictionary)
        redrawUnderlines()
        if issues.isEmpty { endNavigation() } else { focusIssue(min(index, issues.count - 1)) }
    }

    /// "Not here": forgets this one place for the rest of the session and moves on to whatever
    /// problem now sits at the same position, or closes the popup when none is left.
    private func skipCurrent() {
        guard let issue = issues[safe: currentIndex] else { endNavigation(); return }
        skips.insert(issue)
        UsageLog.record(.proofread, .skipped)
        let index = currentIndex
        issues.remove(at: index)
        redrawUnderlines()
        if issues.isEmpty {
            endNavigation()
        } else {
            focusIssue(min(index, issues.count - 1))
        }
    }

    private func handleApplyResult(_ result: IssueApplier.Result, issue: TextIssue, replacement: String) {
        switch result {
        case .applied(let replacedRange):
            UsageLog.record(.proofread, .applied, detail: issue.ruleId.map { "rule:\($0)" })
            // Captured before endNavigation() resets currentIndex: the issue that was next in order
            // ends up at this same position once the fixed one is gone from the fresh, re-checked list.
            let fixedIndex = currentIndex
            // Slide the remaining ranges so the underlines move with the text right away.
            issues = IssueMerger.shift(issues, replacedRange: replacedRange,
                                       replacementUTF16Length: (replacement as NSString).length)
            // The popup closes rather than jumping straight to the next issue: stepping off these
            // locally shifted ranges is only a guess until the write actually lands (the paste path
            // is asynchronous), which is how the following fix ended up refusing or hitting the wrong
            // word. `recheckAfterWrite` reopens it on fresh, confirmed data once the write is done.
            endNavigation()
            underlines.hide()
            recheckAfterWrite(previousText: lastCheckedText, resumeAt: fixedIndex)
        case .stale:
            UsageLog.record(.proofread, .failed, reason: "stale")
            // The message promises a re-check, so actually run one instead of waiting for the user
            // to type again -- they just clicked a fix and are looking at the field, not typing.
            // The issue that failed keeps its place in the list, so the popup can reopen on it.
            let staleIndex = currentIndex
            lastCheckedText = ""
            flash("The text moved - checking again…")
            endNavigation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.typingPaused(resumeIndex: staleIndex)
            }
        case .failed(let reason):
            UsageLog.record(.proofread, .failed, reason: "notApplied")
            flash(reason)
        }
    }

    /// Waits for the applied fix to actually show up in the field (Chromium pastes asynchronously)
    /// and then re-checks it. Re-checking rather than trusting local arithmetic is what keeps the
    /// next fix honest: every range then comes from the text as it really is. It runs even when the
    /// value never changed, so the underlines can never silently go stale after a fix -- the single
    /// exception is a check started from a click, which `RecheckPolicy` defers to. On success it also
    /// reopens the popup on the next issue (`resumeAt`), so fixing several problems in a row does not
    /// require clicking back into the field after each one.
    private func recheckAfterWrite(previousText: String, resumeAt index: Int) {
        Task { @MainActor [weak self] in
            var changed = false
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard let self, let element = self.target?.element else { return }
                guard let now = ProofreadAX.currentText(of: element) else { continue }
                if now != previousText { changed = true; break }
            }
            guard let self else { return }
            if !changed {
                Self.log.warning("field text did not change after an applied fix; the paste may not have landed")
            }
            guard RecheckPolicy.shouldRecheck(selectionCheckPending: self.pendingSelectionCheck) else {
                Self.log.debug("skipping the post-write re-check: a click's check is already in flight")
                return
            }
            self.lastCheckedText = "" // force a real check, not a redraw
            self.typingPaused(resumeIndex: index)
        }
    }

    /// Closes the popup and disarms the key tap, leaving the underlines and the found issues alone:
    /// they belong to the field, not to this popup.
    /// `reason`, when given, records that an open popup was dismissed and why.
    private func endNavigation(reason: String? = nil) {
        if popupShown, let reason { UsageLog.record(.proofread, .dismissed, reason: reason) }
        popupShown = false
        browsing = false
        currentIndex = 0
        selectedReplacement = 0
        popover.hide()
        setActive(false)
        syncPreSend()
    }

    /// Forgets everything found in the field and takes the underlines down. Used when the focus
    /// moves elsewhere or the feature is switched off.
    private func clearLive() {
        checkTask?.cancel()
        checkTask = nil
        generation &+= 1
        pendingSelectionCheck = false
        // An AX call that never returns would otherwise leave accepts blocked for good.
        isApplying = false
        issues = []
        lastCheckedText = ""
        target = nil
        underlines.hide()
        syncPreSend()
    }

    private func end() {
        endNavigation()
        clearLive()
    }

    /// A transient notice that closes itself; never leaves the key tap armed.
    private func flash(_ text: String, spinner: Bool = false) {
        popover.showMessage(text, anchor: currentAnchor(), fontSize: config.fontSize, spinner: spinner)
        setActive(false)
        guard !spinner else { return }
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.popover.hide()
        }
    }

    // MARK: - Key interception

    /// Arms the tap exactly while the popup is navigable, so ordinary typing never pays for it.
    private func setActive(_ on: Bool) {
        shared.isActive = on
        if on { installTap() }
        if let tap, on != tapEnabled {
            tapEnabled = on
            CGEvent.tapEnable(tap: tap, enable: on)
        }
        // Announced on the session change itself, not on the tap toggle: when the tap could not be
        // created autocomplete must still stand down, or both features consume Tab. Exactly one
        // notification per transition, so the other side can count suspend/resume.
        guard on != sessionActive else { return }
        sessionActive = on
        onSessionChange?(on)
    }

    /// Creates the tap on the main run loop, disabled.
    ///
    /// Autocomplete deliberately keeps its taps off main (see AGENTS.md): its tap sees every
    /// keystroke, so any main-thread hiccup becomes system-wide input lag. This one is different --
    /// it is only enabled while the popup is up, which is a short, deliberate moment when the user is
    /// choosing a fix rather than typing, and the callback only reads a lock-protected flag. If it is
    /// ever left armed while the user types, move it to a dedicated thread like autocomplete's.
    private func installTap() {
        guard tap == nil, AccessibilityPermission.isGranted else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<ProofreadController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handleKey(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                              callback: callback, userInfo: userInfo) else {
            Self.log.error("proofread tapCreate failed (accessibility=\(AccessibilityPermission.isGranted, privacy: .public), inputMonitoring=\(AccessibilityPermission.listenEventAccessGranted, privacy: .public))")
            return
        }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: false)
        tapEnabled = false
    }

    /// Runs on the tap thread. Consumes only the popup's own keys and lets everything else through.
    private nonisolated func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                guard let self, let tap = self.tap, self.tapEnabled else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, shared.isActive else { return Unmanaged.passUnretained(event) }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let snap = shared.snapshot

        switch ProofreadKeyPolicy.action(keyCode: keyCode, command: flags.contains(.maskCommand),
                                         control: flags.contains(.maskControl),
                                         option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift),
                                         browsing: snap.browsing, atFirst: snap.atFirst, layout: snap.layout,
                                         opensUpward: snap.opensUpward) {
        case .enter:
            DispatchQueue.main.async { [weak self] in self?.setBrowsing(true) }
            return nil
        case .leave:
            DispatchQueue.main.async { [weak self] in self?.setBrowsing(false) }
            return nil
        case .move(let dx, let dy):
            DispatchQueue.main.async { [weak self] in self?.moveArrow(dx: dx, dy: dy) }
            return nil
        case .apply:
            DispatchQueue.main.async { [weak self] in self?.accept() }
            return nil
        case .fixAll:
            DispatchQueue.main.async { [weak self] in self?.fixAll() }
            return nil
        case .nextIssue:
            DispatchQueue.main.async { [weak self] in self?.step(1) }
            return nil
        case .previousIssue:
            DispatchQueue.main.async { [weak self] in self?.step(-1) }
            return nil
        case .close(let reason):
            // Closes the popup only: the underlines stay, they are not part of this popup.
            DispatchQueue.main.async { [weak self] in self?.endNavigation(reason: reason) }
            return nil
        case .passAndClose(let reason):
            // The user moved on (caret, selection, shortcut, typing): close, and let the key through.
            DispatchQueue.main.async { [weak self] in self?.endNavigation(reason: reason) }
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Click monitor

    private func startClickMonitor() {
        guard mouseMonitor == nil else { return }
        // A passive monitor, not a tap: it cannot delay the click. Clicks on our own popup are
        // dispatched to this app and never reach a global monitor, so they cannot retrigger us.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            self.clickDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.clickedInText() }
            self.clickDebounce = work
            // Let the app settle its caret/selection before we read it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
        // Switching the input language means the user is about to type, not to pick a fix.
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: AutocompleteController.inputSourceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endNavigation(reason: "languageSwitch") }
        }
    }

    private func stopClickMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        if let inputSourceObserver { DistributedNotificationCenter.default().removeObserver(inputSourceObserver) }
        inputSourceObserver = nil
        clickDebounce?.cancel()
        clickDebounce = nil
    }

    // MARK: - Typing monitor

    /// Live checking: a passive keyDown monitor (no tap, so typing is never delayed) re-checks the
    /// field once the user pauses. The underlines go down on the first keystroke -- the text under
    /// them is moving -- and come back with the fresh result.
    private func startTypingMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            // Our own synthetic keys (the paste that applies a fix, an autocomplete insertion) are
            // not the user typing: reacting to them would hide the underlines and start a second
            // re-check on top of the one the applier already schedules.
            guard !InjectedEvents.isInjected(event) else { return }
            self.underlines.hide()
            self.typingDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.typingPaused() }
            self.typingDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.typingPause, execute: work)
        }
    }

    private func stopTypingMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        typingDebounce?.cancel()
        typingDebounce = nil
    }

    // MARK: - Helpers

    private func appAllowed() -> Bool {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if bundle == Bundle.main.bundleIdentifier { return false }
        switch config.appMode {
        case .all: return true
        case .allow: return config.apps.contains(bundle)
        case .deny: return !config.apps.contains(bundle)
        }
    }

    /// The word's rect in AppKit screen coordinates, so the popup can sit above it. Falls back to
    /// the field's frame, then to a sliver at the mouse.
    private func anchor(for issue: TextIssue) -> CGRect {
        let height = primaryScreenHeight()
        if let element = target?.element {
            if let quartz = ProofreadAX.boundsForRange(issue.range, in: element) {
                return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: height)
            }
            if let quartz = ProofreadAX.frame(of: element) {
                return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: height)
            }
        }
        return mouseAnchor()
    }

    private func currentAnchor() -> CGRect {
        if let issue = issues[safe: currentIndex] { return anchor(for: issue) }
        if let element = target?.element,
           let quartz = ProofreadAX.frame(of: element) {
            return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: primaryScreenHeight())
        }
        return mouseAnchor()
    }

    private func mouseAnchor() -> CGRect {
        let p = NSEvent.mouseLocation
        return CGRect(x: p.x, y: p.y - 8, width: 1, height: 16)
    }

    private func primaryScreenHeight() -> CGFloat {
        (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main)?.frame.height ?? 0
    }

    private static func describe(_ error: Error) -> String {
        if let engineError = error as? EngineError { return engineError.localizedDescription }
        if let urlError = error as? URLError {
            return "LanguageTool server unreachable (\(urlError.code.rawValue))."
        }
        return error.localizedDescription
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
