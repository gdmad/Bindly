# BindAll — AGENTS.md

macOS menu-bar utility that acts on the current selection via global hotkeys: AI text correction /
custom prompts, on-device translation, and screen-region OCR translation.

## Stack
- **Swift 6 + SwiftUI + AppKit**, target **macOS 26**
- Hand-authored Xcode project (`BindAll.xcodeproj`, file-system-synchronized group — new source files
  are picked up automatically, no need to edit `project.pbxproj`)
- Frameworks: `FoundationModels` (on-device LLM), `Translation` + `NaturalLanguage` (translation),
  `Vision` (OCR), `ServiceManagement` (launch at login), `Security` (Keychain)
- Menu-bar agent: `LSUIElement = true` (no Dock icon)
- Bundle id: `com.evgeny.bindall`

## Structure

```
BindAll/
├── App/
│   ├── BindAllApp.swift        # @main; placeholder SwiftUI Settings scene — UI is AppKit-driven
│   ├── AppDelegate.swift       # NSStatusItem menu (actions + shortcuts), settings window, icon, login
│   ├── StatusIconRenderer.swift / StatusIconTwinkle.swift # the drawn tray icon and its busy wave
│   └── AppState.swift          # @Observable: settings persistence, Keychain keys (keychainRevision), isProcessing;
│                               # views read it via @Environment(AppState.self), AppKit code via Observations { }
├── Hotkeys/
│   ├── HotkeyMonitor.swift     # CGEventTap; detects N presses of key+modifiers within a time window
│   ├── HotkeyCoordinator.swift # Orchestrates hotkey → selection → engine / translation / OCR
│   └── AccessibilityPermission.swift
├── Selection/
│   ├── SelectionReader.swift   # Reads selection from the pasteboard (AX attribute fallback)
│   ├── TextInjector.swift      # Sets pasteboard + synthesizes Cmd+V; copy helper
│   ├── EdgeWhitespace.swift / ReplaceTarget.swift # pure: a result keeps the subject's edges; where it goes now
│   └── InjectedEvents.swift    # Marks/detects BindAll's own synthetic keys, so proofread/autocomplete ignore each other's writes
├── Engines/
│   ├── AIEngine.swift          # protocol + EngineError
│   ├── AppleFoundationEngine.swift   # FoundationModels on-device LLM (temperature 0)
│   ├── OpenAICompatibleEngine.swift  # DeepSeek / OpenRouter / OpenAI / Ollama (one client)
│   ├── LanguageToolEngine.swift      # LanguageTool client: correct() applies all fixes;
│   │                                 # check()/parseMatches()/issues() feed Proofread
│   ├── TranslationService.swift      # Apple Translation framework + NL language detection
│   ├── TranslationLayout.swift # pure: puts the source's line breaks back into a translation
│   ├── LanguagePair.swift      # pure: which way a translation goes, for every entry point
│   ├── OCRParagraphs.swift     # pure: joins wrapped OCR lines back into paragraphs
│   └── OCRService.swift        # screencapture region + Vision text recognition
├── Voice/                      # Push to Talk (off by default)
│   ├── HoldKeyPolicy.swift            # pure: hold / quick tap / used as a modifier / Esc
│   ├── HoldKeyMonitor.swift           # key tap on its own thread (right Option or a custom key)
│   ├── SpeechRecorder.swift           # AVAudioEngine (or a test file) -> SpeechAnalyzer
│   ├── AudioLevelMeter.swift          # input loudness: the mic's level and the silent-input hint
│   └── PushToTalkController.swift     # session: note by the caret, optional translation, paste
├── Autocomplete/               # word completion while typing (off by default)
│   ├── AutocompleteEngine.swift       # NSSpellChecker completions/guesses + recasing + partial-word; Mode (baseline/context/semantic) + scorer re-ranking
│   ├── AutocompleteController.swift   # two CGEventTaps on own thread (listen-only monitor + active suppressor); AX/keystroke word; suggestions, next-word, accept
│   ├── AutocompleteLearningStore.swift# learned counts + bi/trigrams; next-word backoff + RU seed; contextScore() ranks completions by preceding words (thread-safe)
│   ├── LearnedWordAudit.swift         # pure: which learned words look like typos (dictionary check comes in as a closure)
│   ├── AutocompleteInsertion.swift    # pure: append the suggestion's remainder vs. delete-and-retype (never passes through an empty field)
│   ├── SemanticRanker.swift           # experimental: NLContextualEmbedding (Cyrillic) cosine re-ranking, debug-only
│   ├── ru_bigrams_ctx.txt             # RU bigram seed (Leipzig news, CC BY 4.0) -- feeds both next-word and completion ranking
│   ├── ru_trigrams.txt                # RU trigram seed (Leipzig news, CC BY 4.0) for completion ranking
│   └── AutocompleteOverlay.swift      # non-activating floating list shown near the caret (PopupKit)
├── Proofread/                  # step through LanguageTool's findings one at a time
│   ├── TextIssue.swift                # shared issue model (UTF-16 ranges, stable ids)
│   ├── IssueMerger.swift              # merge/shift/context-checked relocate/firstIssue -- pure range algebra
│   ├── ProofreadCache.swift           # paragraph segmentation + per-paragraph issue cache
│   ├── HiddenBreaks.swift             # pure: block breaks Chromium leaves out of AXValue (align leaves, check text, map back, seam candidates)
│   ├── ProofreadSkips.swift           # pure: places the user skipped (rule + text + context keys)
│   ├── FixAll.swift                   # pure: every issue's first fix applied at once
│   ├── PersonalDictionary.swift       # pure: words never flagged as misspellings
│   ├── PreSendPolicy.swift            # pure: what a key does for the check before sending
│   ├── PreSendGuard.swift             # its Return tap (own thread, on only while armed)
│   ├── ListMarkers.swift              # pure: list numbers/bullets glued to their item ("1.Buy")
│   ├── AppOffsetMap.swift             # pure: value offsets <-> the app's own (Slack drops some newlines)
│   ├── ProofreadLanguage.swift        # language resolution; ru/uk disambiguation for "auto"
│   ├── LanguageToolProofreadProvider.swift # actor: paragraph-scoped checks + cache
│   ├── ProofreadAX.swift              # focused field text/selection, word bounds, in-place select
│   ├── TextOccurrence.swift           # pure: the occurrence of a word nearest an offset (leaf lookup)
│   ├── IssueApplier.swift             # validated single fix: AX write, else verified select+paste
│   ├── WordBoundary.swift             # word range under the caret (click-to-proofread trigger)
│   ├── UnderlineGeometry.swift        # pure geometry: rect flip, underline drop/thickness, line check
│   ├── IssueKindStyle.swift           # one source of truth for issue-kind color and symbol
│   ├── RecheckPolicy.swift            # pure: whether the post-write pass re-checks (defers to a click's check)
│   ├── ProofreadClickPolicy.swift     # pure: what a click does (probe a word / dismiss / ignore a selection)
│   ├── UnderlineOverlay.swift         # click-through panel with a straight underline under every found issue
│   └── ProofreadController.swift      # session, key tap (only while the popup is up), click popup
├── Actions/
│   ├── ActionRouter.swift      # EngineFactory (builds an AIEngine from settings)
│   └── MaskAISlop.swift        # typography normalizer (dashes/quotes/emoji)
│   ├── LocalTransform.swift / KeyboardLayoutMap.swift # pure: built-in keys done without a model
├── UI/
│   ├── SettingsView.swift      # tab bar + selected tab (see "Settings layout"); `showSettingsTab` in the environment switches tabs
│   ├── SettingsTab / SettingsTabBar / SettingsTabRow / SettingsTabButton / SettingsTabContent .swift
│   │                           # in-window tab bar, NOT TabView: on macOS 26+ a Tab-built TabView moves
│   │                           # the tabs into the title bar as overflowing icons. ViewThatFits picks the
│   │                           # widest layout that fits: icon+title, icon over title, icons only
│   ├── GeneralSettingsView / ShortcutsSettingsView / ActionsSettingsView (AI Actions) /
│   │   TranslationSettingsView (+ TranslationSection, TranslationStatusRow, LanguagePicker) .swift
│   ├── HoldKeyPicker / AdvancedDisclosure / SettingsNavigation .swift # hold-key choice, folded "Advanced" blocks, `showSettingsTab`
│   ├── HelpHint / HelpHeader / HelpToggleRow .swift # help icon, header with help, and the Form toggle
│   │                           # with a help hint (keeps the hint's Button out of the Toggle's label)
│   ├── AutocompleteSettingsView.swift  # autocomplete tab (on/off, count, layout, language, learning, per-app)
│   ├── LearnedWordsView / TypoFilterRow / LearnedWordRow .swift # learned-words sheet
│   ├── LanguageSelectionBinding.swift  # Binding<[String]>.contains(code) / .isAuto for menu toggles
│   ├── ProofreadSettingsView.swift     # proofread tab (on/off, fixes, layout, language, per-app)
│   ├── AppFilterSection.swift          # shared per-app allow/deny section (autocomplete + proofread)
│   ├── ActionKeysSettingsView.swift / ActionKeyRow.swift # action keys (name, instruction, shortcut, show-only); rows bound by id, never by index
│   ├── ProvidersSettingsView.swift     # AI provider connections (keys, models; drafts written back deferred)
│   ├── ShortcutRecorder.swift / HotkeyFormatter.swift # click-to-record shortcut field, glyph formatting
│   ├── DarkFieldStyle / ClearFocusOnAppear / DeferredWrite .swift # input box style, no auto-focus on
│   │                           # tab appear, deferred settings writes from text fields
│   ├── LanguageToolConnectionSection.swift # LT mode/URL/credentials block on the Proofread tab
│   ├── PopupKit.swift          # shared popup metrics/panel/placement/tile measuring (AppKit geometry, not views)
│   ├── PopupPresenter.swift    # owns a popup's non-activating panel; generic present(view), no AnyView
│   ├── PopupChrome.swift       # material panel + hairline border modifier (reads Reduce Transparency from the environment)
│   ├── PopupCell.swift         # one item: selection pill, selected/button accessibility traits
│   ├── PopupItemsLayout.swift  # the one column/line/tile layout both popups use
│   ├── PopupTilePacker.swift   # pure: how many cells fit the tile's first row
│   ├── ProofreadPopover.swift  # the fixes popup: presenter + placement above the word
│   ├── FixesPopupView.swift    # the fixes popup's content: header + PopupItemsLayout
│   ├── FixesPopupHeader / FixesPopupSummary / FixesPopupSkipButton .swift # kind + wording + counter, then the Skip icon
│   ├── FixesPopupFixAllButton.swift   # Fix all: wand icon and count in the header row
│   ├── StarShape.swift                # the star as a vector path
│   ├── StarActivity.swift             # busy flag the star animates on
│   ├── StarBusyView.swift / BrandPalette.swift # the working star (orbits) and the icon's colors
│   ├── FloatingPanelHost.swift        # the borderless, content-sized window behind result/preview/prompt
│   ├── PanelPlacement.swift / FocusedField.swift # next to the field: below, above, or centered
│   ├── PanelWidth.swift / ResultMarkdown.swift # pure: window width from the text, Markdown in results
│   ├── PanelChrome.swift / PanelActionBar.swift  # shared window look and button row
│   ├── FixesPopupAddWordButton.swift  # book icon: add the word to the personal dictionary
│   ├── PersonalDictionarySection.swift # Settings -> Proofread: the dictionary's words
│   ├── PopupMessageView.swift  # one-line notice in the same chrome
│   ├── FirstMouseHostingView.swift # NSHostingView that accepts the first click on a never-key panel
│   ├── HistoryPanelView.swift / HistoryRow.swift / HistoryDetail.swift # History popover from the menu bar
│   ├── PopupController.swift   # floating NSPanel for translation/results; closes on Esc/Close only
│   ├── PopupModel.swift / PopupView.swift / PopupHeader.swift / PopupOriginalSection.swift
│   │                           # result popup: header drags the window, copy-original icon
│   ├── WindowDragHandle.swift  # NSView that drags its window: over each header (beside, not over, the preview's switch), under `PanelChrome` and Quick Translate so margins and gaps drag too; text stays selectable
│   ├── KeyablePanel.swift      # NSPanel that can become key from an accessory app
│   ├── QuickTranslate*.swift   # Quick Translate window: controller, @Observable model, view, language
│   │                           # bar, input (vertical TextField: system placeholder level with the
│   │                           # caret; Return translates, Shift+Return inserts a newline), output,
│   │                           # action bar ([Clear] ... [Close][Copy]), footer
│   ├── CopyButton.swift / CloseButton.swift # the shared translation-window buttons (Copy is the
│   │                           # prominent one, "Copied" for 1.5 s)
│   └── CopyShortcutMonitor.swift # Cmd+C in a translation window: the selection if there is one,
│                               # otherwise the whole translation
└── Store/
    ├── Settings.swift          # Codable settings, ProviderKind, HotkeyConfig
    ├── ActionKey.swift         # {key, label, prompt, hotkey?}; built-in w / u / l / о / гг
    ├── KeychainStore.swift     # API keys (generic password)
    ├── ShortcutConflicts.swift # pure: every shortcut in the settings and the duplicate check
    ├── SelectionCommand.swift  # star actions also offered in the menu bar and as optional shortcuts
    └── LoginItemManager.swift  # SMAppService launch-at-login
Tests/
├── Unit/                       # pure-logic assertions (no XCTest host needed): Harness.swift (check/eq and
│                               # shared helpers), one <Area>Tests.swift per area (Actions, Proofread,
│                               # Autocomplete, Settings, UI, Voice), main.swift runs them all
├── run_tests.sh
├── eval_autocomplete.sh        # autocomplete ranking evaluator (hit@1/hit@3/MRR per prefix)
├── eval_autocomplete.swift     # harness: RU corpus, cold/warm store, baseline|context|semantic modes
├── gen_ru_ngrams.py            # rebuilds ru_bigrams_ctx.txt / ru_trigrams.txt from a sentence corpus
└── ru_eval_corpus.txt          # 105 RU sentences (80 hand-written + 25 Leipzig news) used by the evaluator
Info.plist                      # LSUIElement, version (source of truth for version)
```

## Settings layout
General (startup, Replacing text: restore clipboard and both preview switches, Data, Stars, Popups,
Status, About) · Shortcuts (every global shortcut and both voice hold keys, one collision check
across all) · AI Actions (engine, default prompt, action keys, Mask AI Slop with its rules) ·
Translation (pair, status, the dictation target) · Autocomplete · Proofread (Checking, Fixes popup,
Personal dictionary, LanguageTool server folded while Free, Apps) · Voice (the two dictations, speech
language, permissions) · Providers (connections only). Rarely changed options sit in
`AdvancedDisclosure` blocks, which remember whether they are open. Every section header is a
`HelpHeader`, and every toggle a `HelpToggleRow`.

## Triggers (defaults, all configurable in Settings → Shortcuts)
- **Cmd+C ×2** → default action: the default prompt (spelling/grammar) on the whole selection
- **Cmd+C ×3** → translate the selection, shown in a popup near the cursor
- **Cmd+E** → OCR: select a screen region, recognize text, translate
- **Shift+Cmd+E** → Quick Translate window
- **Explain selection / Summarize selection** → no shortcut by default (`explainHotkey`,
  `summarizeHotkey` are optional); also in the menu bar. They are for reading someone else's text, so
  they are not in the star menu: the result opens in the popup, the text stays, nothing goes to
  history (`HotkeyCoordinator.Reading`, run through `runDefaultAction` with `showOnly`)
- **Proofread** (LanguageTool), only when enabled on Settings → Proofread, has **no shortcut**: a
  pause in typing (~0.6 s) re-checks the focused field and underlines every issue in place
  (straight underlines; spelling is red, grammar yellow, punctuation green, style blue -- LanguageTool's own
  palette). Clicking an
  underlined word shows its fixes instantly -- the issues are already known, no round trip. In the
  popup: arrows or mouse hover choose a fix (the column layout uses up/down for fixes and
  left/right for problem words, the line swaps them, and the tile uses both axes for fixes), Return
  or a click applies it, Tab steps between problem words (wrapping around), Esc closes it (the
  underlines stay). Both popups share `UI/PopupKit.swift` (system-menu look: material panel, standard
  selection pill, no zoom or animation; honours Reduce Transparency and Differentiate Without Color),
  take their text size from Settings → General, and their layout
  (Column / Line / Tile -- two rows) from their own setting, shared with autocomplete. The number of fixes listed per issue is a setting
  (1-10, default 3). Underlines follow scrolling and window moves, go down while typing and come
  back with the fresh result, and disappear on an app switch. Apps that expose no word coordinates
  (many Electron/web fields) get no underlines; the popup still works if their text is readable.
  Chromium-based apps only build an accessibility tree when asked, so `ProofreadAX` sets
  `AXManualAccessibility` on the frontmost process once (`enableElectronAccessibilityIfNeeded`).
  One LanguageTool rule is hidden on purpose (`LanguageToolEngine.ignoredProofreadRules`):
  `UPPERCASE_SENTENCE_START`, "this sentence does not start with an uppercase letter". It is right by
  the book and wrong for chat, where nearly every message starts in lowercase -- left on, it put a
  permanent green underline (LanguageTool files it under `typographical`, which maps to punctuation)
  on the first word of everything. It is filtered where matches become issues, not via the request's
  `disabledRules`, because the "Correct" action shares the engine and there capitalising the start is
  a legitimate fix. To hide another rule, add its id to that set.
  **A selection never opens the popup** (`ProofreadClickPolicy`): editors put their own controls over
  a selection -- Slack's formatting toolbar lands exactly where the fixes popup would -- so
  double-clicking a word or dragging across a paragraph that holds an underlined one is left alone,
  and only a plain click into a word asks for fixes. For the same reason the popup never selects the
  word it is about (`showCurrent()`, in any app, not just Chromium/Electron -- a selection left
  behind once the popup closes turned a single Backspace into deleting the whole word); the underline
  already marks it, and `IssueApplier` makes the selection itself right before pasting a fix.
- Each `ActionKey` may have its own recorded shortcut that runs its prompt on the selection directly.
- **Esc** cancels an in-flight action; any error a cancelled task throws counts as the cancel (`isCancellation` checks `Task.isCancelled`: the on-device model throws its own error, which used to end in an "Error" window).
- **Word autocomplete** (off by default; enable and configure on the Autocomplete tab): as you type, a list of case-matched completions appears near the caret; arrow keys choose,
  **Tab** (and optionally Return) inserts; any other key, a click anywhere, or leaving the app
  dismisses it. Completions are **ranked by the preceding words** (the "Rank by context" setting,
  default on): `AutocompleteLearningStore.contextScore` interpolates learned trigram > learned
  bigram > bundled RU trigram/bigram seeds > personal frequency, and the pool (learned + dictionary
  completions, up to 30) is re-ranked by that score -- this was validated by an experiment, run with
  `Tests/eval_autocomplete.sh` (context beat baseline and a semantic-embedding variant on hit@1/MRR
  against `Tests/ru_eval_corpus.txt`). It can predict the next word
  after a space: the context (up to two preceding words) is read from the focused field via AX where
  one is exposed, the same way the current word is ranked, so it also works after clicking back into
  a sentence or returning from another app -- not only mid-typing-run, which is all the keystroke
  buffer (`prevWord`/`prevWord2`, used as the fallback when AX exposes no text) can see. It also
  learns the words you use (local
  `AutocompleteLearningStore`): a word is learned when a space or punctuation closes it, and when a
  suggestion is accepted. Return deliberately does not learn (it submits password fields).
  Learned words can be reviewed: the "Learned words" sheet flags every word the dictionary does
  not know (`LearnedWordAudit`, pinned words exempt) and can drop them in one go -- anything typed
  twice gets learned, typos included.
  Configurable: count, column/line/tile layout, text
  size, dictionary language, and per-app allow/deny. Uses AX text+caret where available, otherwise a
  keystroke buffer (works in most apps). Skipped in password fields and BindAll's own windows.
  The ranking mode can be overridden for experiments with
  `defaults write com.evgeny.bindall AutocompleteVariant -string baseline|context|semantic`
  (semantic re-ranking via `SemanticRanker` measured poorly on Russian and stays off by default).
  Its tap is an active tap (it consumes Tab/arrows while suggesting), so it runs on a **dedicated
  run-loop thread** and the callback only makes a cheap lock-protected suppression decision; all AX
  and NSSpellChecker work happens on a background queue. Do not move the tap back to the main run
  loop or do AX/spell-checker work in the callback -- that reintroduces per-keystroke input lag.

Because the Cmd+C triggers are the real copy shortcut, the selection is already on the pasteboard when
a burst fires; the event tap is **listen-only** and does not consume the keystroke. Per-action-key
shortcuts and Correct are not copy shortcuts, so they synthesize Cmd+C first
(`SelectionReader.copyCurrentSelection`). A burst fires immediately once the highest configured press
count for that key is reached (only counts with a larger sibling wait out the time window).
`HotkeyMonitor` reads the pasteboard's change count before a burst's first press and passes it on:
a burst that copied nothing (no selection, a field that refuses copying) never uses the older
clipboard -- only the AX selected text, else "No text selected.". Key auto-repeat and BindAll's own
marked keystrokes (`InjectedEvents`) are not presses. Read-only text (`ProofTarget.isEditable`: neither
the value nor the selected text is settable, e.g. Terminal) gets no field star, no proofreading, and
a selection star with only Show translation, Explain, Summarize and Copy. `replace()` puts a result
back only where its text still is (`ReplaceTarget`: unchanged, or found again near its old place
when there is no offset map), checks the select and the selected text, and otherwise shows the
result to copy ("Not replaced"); the hotkey preview captures its selection (`selectionContext`) and
goes through it. Results keep the subject's leading/trailing whitespace (`EdgeWhitespace`).
Hotkey bursts do nothing while BindAll itself is in front (Quick Translate's toggle aside). Every
engine and translation task is `currentTask`, so Esc cancels it; the local Esc monitor swallows Esc
only while there is a task. The 25 s watchdog cancels the task, not just the busy flag. Fix spelling
skips personal-dictionary words (`LanguageToolEngine.correct(_:dictionary:)`); history records the
engine that actually ran (LanguageTool, Rules, or the AI engine); "Save as action key" keeps Show.
History keeps every result -- shown ones too (Explain, translation popups, Quick Translate, a
closed preview) -- with `HistoryEntry.applied`, set at Apply (`markApplied`); old entries decode as
applied. Fix all and plain dictation (kind `voice`) are recorded as applied. The star's History lists
applied entries only; from the field star an entry is inserted at the caret
(`StarContext.insertsAtCaret`), from the selection star it replaces the selection. One direction
rule for translations, `LanguagePair.resolve` (pure): automatic source -> target; an explicit source
works both ways; unknown language -> target. Used by the shortcut, the star, OCR and dictation that
follows the Translation tab; Quick Translate keeps its own one-way pair but says "already in X"
instead of asking to download X -> X, and checks the pack both ways. OCR shows the recognized text
whenever it cannot be translated (already in the target, no pack, failure).
Stars have their own app filter (`starAppMode`/`starApps`, General tab; stored settings from before
start from the Proofread list). A shown-only result from an editable star's text has Replace in its
window. The preview opens on Result when most of the text changed (`TextDiff.changedShare` > 0.5:
translations, history insertions, rewrites). `SelectionCommand` (Custom prompt, Fix spelling,
Remove AI tells, Replace with translation) also runs on the selection from the menu bar and from
optional shortcuts (`commandHotkeys`), through `selectionContext` and the star's own paths. The
built-in UPPERCASE, lowercase and Fix keyboard layout keys run locally (`LocalTransform`,
`KeyboardLayoutMap`), recognized by their built-in instruction. Mask AI Slop keeps every non-ASCII
character the user typed in the input (`apply(to:rules:keeping:)`); Remove AI tells never takes the
user's "All emoji" rule. Fix spelling is labelled "(LanguageTool)" and, in Free mode, says once in its
preview that the text goes to languagetool.org (`spellingNoticeShown`). "Check before sending" is
dimmed while Proofread is off.

## Engines
- **Engine for text actions** (`Settings → Providers`): Apple on-device, DeepSeek, OpenRouter, OpenAI,
  or Ollama. Cloud providers share one OpenAI-compatible client (`/chat/completions`). This picker and
  the **Provider** picker just below it configure different things -- the Provider section edits
  credentials/model for whichever provider is selected there, not necessarily the one actions run on;
  the Provider list tags the active one with "— active" for exactly this reason. `/models` is a public
  listing on some providers (OpenRouter answers it with no key at all), so it cannot stand in for an
  auth check: `testConnection()` always makes a real `/chat/completions` call, and `listModels()`
  refuses to run with an empty key rather than silently returning an anonymous provider's catalog. A
  401/403 names the provider in the error text, since it is otherwise indistinguishable from a
  same-shaped key belonging to a different provider (`OpenAICompatibleEngine.providerName`). Keys are
  trimmed of whitespace before being saved (`ProvidersSettingsView.saveKey`) -- a pasted key with a
  trailing newline is invisible in the field and would otherwise fail with an unexplained 401.
- **Translation is always on-device** via Apple's `Translation` framework, regardless of the chosen
  engine. It uses a two-language pair (primary/secondary) and translates into whichever the source is
  not; the source is auto-detected with `NaturalLanguage`.
- **Proofread (LanguageTool)** is a separate, optional action (not in the engine dropdown), enabled on
  General. LanguageTool is the only issue source: it is the one engine with real Russian grammar, and
  it reads the sentence, so it finds agreement and punctuation rather than just unknown words.
  (`NSSpellChecker` was tried as an offline layer and dropped -- its Russian guesses are poor: for
  "Прувет" it offers "Прусте"/"Пруте", never "Привет". Harper is English-only and Apple's
  FoundationModels does not support Russian at all, so neither is an option here.) The same settings
  drive it and the legacy `correct()` path. Text is sent one paragraph at a time and cached by
  paragraph text, so editing one sentence costs one request and re-checking costs none.
  The connection is configured on the Proofread tab via an explicit **connection mode**
  (`LanguageToolMode`): **Free public** (`api.languagetool.org`, no credentials -- the public server
  rejects them with HTTP 400), **Premium** (`api.languagetoolplus.com`, a different host, requires
  username + token), or **Self-hosted** (your own URL, no credentials -- the server is reached by URL
  alone, so the tab shows no username or token fields for it).
  `Settings.languageToolConnection(token:)` resolves the real endpoint and puts credentials on the
  wire for Premium only; `LanguageToolEngine.authParams` is a final guard that never sends a
  lone username or apiKey. The Premium token lives in the Keychain. The URL is pre-filled per mode
  but stays editable; there is no settings migration (mode defaults to Free).
- **Slack text, measured on a live composer:** Slack's `AXValue` has a newline after every list item,
  soft line break (Shift+Enter) and emoji, and a numbered or bulleted item's marker glued to its text
  ("1.Buy", "\u{E506}Buy" -- U+E506 is Slack's bullet glyph). Its own string -- what
  `AXStringForRange`, `AXBoundsForRange` and the selection are indexed by -- is the same text with
  those newlines left out (paragraph, quote and code-block newlines stay; it refuses one range over
  the whole field, so it is read in chunks). Two fixes follow:
  - `ListMarkers.markerEnds` finds glued markers at line starts; the check text gets a space there
    (`HiddenBreaks.spaces`), so LanguageTool no longer reads "1.Buy" as a missing space after a full
    stop. `mapBack` removes the inserted characters again.
  - `AppOffsetMap` lines the value up with the app's string character by character (the app's must
    be the value minus some newlines) and translates ranges exactly: `ProofreadAX.offsetMap(for:text:)`
    (Chromium only, cached for the last text) feeds `alignedRange(..., map:)` in the overlay, the
    applier and the click path, and `focus()` translates the app's selection back into value offsets.
  - An issue the overlay still cannot place in the field is dropped from the list
    (`UnderlineOverlay.show` returns its id), so "N of M" equals what is underlined.
  - `ProofreadAX.hiddenBreaks` (leaves matched to the value with a cursor, markers skipped) and the
    `crossesVisualBreak` safety net remain for apps that do glue blocks together without a newline.
- **Skip:** an icon (`eye.slash`) beside the "N of M" counter in the fixes popup header
  (`FixesPopupSkipButton`, its own VoiceOver element), reached with the arrows as the last choice
  (index = `replacements.count`) or clicked. It hides that one place for the rest of the session via
  `ProofreadSkips`, keyed by rule + text + 6 characters of context each side, so it survives
  re-checks and edits elsewhere while the same word in another place still shows.
- **Personal dictionary:** `Settings.personalDictionary`; spelling issues on those words are dropped
  in `applyResults` (`PersonalDictionary.filter`, pure: case-insensitive, ё = е; grammar and style
  stay). The book icon beside Skip (`FixesPopupAddWordButton`, spelling issues only) adds the word
  through `ProofreadController.onAddWord`; the list is edited in Settings -> Proofread
  (`PersonalDictionarySection`).
- **Check before sending** (`preSendCheck`, default off): in chat apps (`PreSendPolicy.chatApps`) a
  plain Return while the field shows issues is held once and the popup says how many are left;
  Return again sends, Tab opens the first issue, Cmd+Return is Fix all, Esc drops it, any other key
  goes through. `PreSendGuard` is an active keyDown tap on its own thread, enabled only while armed
  (issues in a frontmost chat field, no fixes popup, no star menu tracking, no autocomplete suggestion via
  `AutocompleteController.onSuggestionChange`) or warning; keys aimed at another process are never
  touched. `PreSendExtraApps` (UserDefaults, set only by scripts/e2e.sh) adds TextEdit for the E2E.
- **Hover in the fixes popup:** fixes and Skip light up through the arrow selection; Add to
  dictionary, Close (a `PopupCell` like Skip, no longer a Button) and Fix all light up on their own
  (`PopupCell.highlightsOnHover`), in the same selection color as a chosen fix. The E2E moves the pointer before clicking (`hoverThenClick`): a
  click warped onto the panel without a prior move was what made the cross look like it needed two.
- **Fix all:** with two or more fixable issues the fixes popup offers Fix all
  (`FixesPopupFixAllButton`: a `wand.and.stars` icon with the count in the header row, before Skip, Add to dictionary and Close; VoiceOver and the tests know it as "Fix all (N)" through `PopupCell.accessibilityText`); ⌘Return in the popup does the same (`ProofreadKeyPolicy.fixAll`).
  `FixAll.apply` (pure) re-reads the field, relocates each issue and applies its first fix from the
  end, skipping overlaps; `ProofreadController.onFixAll` hands the field as a `StarContext` to the
  coordinator, which always shows the preview and writes the result the way star actions do.
- **Push to Talk** (`Voice/`, Settings -> Voice, off by default): hold right Option (`kVK_RightOption`
  via `flagsChanged`; or a custom key, which the tap keeps out of the app), speak, release; the
  transcript is pasted where the caret is (`TextInjector.replaceSelection`, `FocusTarget` captured at
  the start). Recording starts after `HoldKeyPolicy.minHold` (0.3 s) with no other key pressed, so a
  tap or Option+letter never turns the microphone on; another key or Esc while recording cancels.
  `SpeechRecorder` uses `SpeechTranscriber` where it supports the language and `DictationTranscriber`
  otherwise (Russian is only there), both on-device, models via `AssetInventory`. The language is the
  setting or the keyboard layout's. "Translate before inserting" (or Shift held at release, which
  flips it once) runs Apple Translation first; if that fails the dictation goes to the clipboard.
  **Dictate and translate** (`voiceTranslateEnabled`, off by default -- it opens the microphone; `HoldKeyMonitor` counts mouse clicks and scrolling as "another key", so a Cmd-click never records; `voiceTranslateKey`, right
  Command): its own hold key that always translates, also with plain Push to Talk off.
  `HoldKeyMonitor` watches both keys as slots (one hold at a time). The voice target language is
  "same" by default, meaning the Translation tab's target.
  The note by the caret is the "BindAll Voice" panel (`VoiceIndicatorView`): a violet `mic.fill` (`Color.brand`)
  (`VoiceMicIcon`) that swells with the input level (`AudioLevelMeter`, RMS measured in the audio tap,
  reported through `VoiceLevel` about 12 times a second; still with Reduce Motion). 1.5 s in, no
  buffers or a peak below `AudioLevelMeter.silentDecibels` (-60 dB) shows "The microphone is silent",
  and an empty result is then logged as `silentInput` rather than `nothingHeard`. Each recording logs
  input device, buffers, peak dB and text length (never the text) at `.notice`, category `voice`.
  `PushToTalkTestAudio`
  (UserDefaults, set only by scripts/e2e.sh) feeds a `say` recording instead of the microphone.
- **Translation layout:** Apple's model (macOS 27) translates each line as its own segment and
  joins the output with blank lines. The whole text still goes in one request (context matters);
  `TranslationLayout.restore` then swaps the output's newline runs for the source's. OCR lines are
  first joined into paragraphs (`OCRParagraphs`: small vertical gap and aligned left edge = same
  paragraph; a hyphenated wrap is rejoined), since screen line breaks cut sentences in half.
- **Popup keys (Safari / macOS inline predictions model):** a suggestion list or the fixes popup
  takes no navigation keys until the user goes into it with Down. `AutocompleteKeyPolicy` and
  `ProofreadKeyPolicy` (pure, tested) decide per key and state (shown vs browsing): shown -- Tab
  accepts the first suggestion / walks issues (Shift+Tab back), Return applies the first fix
  (autocomplete: Return is not taken, it may send the message), Down enters, Esc closes; every other
  arrow, Return, Shift+arrow, any Cmd/Ctrl/Opt shortcut and typing go to the field and close.
  Browsing -- the layout's arrows move (Up from the first item backs out), Return/Tab accept, Esc
  backs out. Until entered, the first item is shown with a soft highlight (`PopupCell.softSelection`).
  Both popups close when the input source changes (`TISNotifySelectedKeyboardInputSourceChanged`).
  The fixes popup header has Skip (eye) and Close (cross) icons.
- **Inline suggestion (ghost text):** with `autocompleteInline` on (default), when the caret is at the
  end of its line (`InlineCompletion.caretAtLineEnd`) and the app reports a precise rect for the
  character before the caret, the first suggestion's remaining letters
  (`InlineCompletion.suffix`, only when the word simply continues the partial) are drawn in tertiary
  gray right after the caret by `InlineGhostOverlay` (click-through panel). The font comes from the
  field's `AXFont` attribute when reported, otherwise from the line height. Tab accepts as usual;
  Down replaces the inline text with the list (browsing). Mid-line, for corrections, or with no
  precise caret rect, the list is shown as before. The caret rect is the right edge of the last few
  characters of the line, measured as one run with `ProofreadAX.boundsForRange(expecting:)` (which
  falls back to the field's text leaves, where Slack, Claude and other Chromium fields answer; the
  expected text keeps it on the right line, since the leaves leave out the newlines). In a
  multi-line field the caret is translated with `AppOffsetMap` (built uncached on the work queue,
  `workMapCache`). The gray text is drawn by `GhostTextView` from x = 0 (no label inset) in a
  pixel-aligned panel. Why a suggestion went to the list (caret not at a line end, no caret
  geometry, a correction) is logged at `.notice`, category `autocomplete`, once per change.
- **Text leaves** (`ProofreadAX.textLeaves`): depth 8, at most 400 elements visited (the budget
  counts every element, not only the leaves found). A list in Claude's composer puts its text runs
  four levels down, and the old depth of 3 lost them: no gray text and no underlines in any longer,
  structured message. `leafRange` picks the leaf and the occurrence of the expected text nearest the
  estimated offset; `UnderlineOverlay` measures the word and its one-character probe in that same
  leaf. `ProofreadAX.cachingLeaves { }` walks each field once per pass (the underline pass and the
  visual-break filter), and the overlay logs at `.notice` how many issues could not be found or
  measured.
- **Stars** (`Selection/FieldStarController.swift`): one violet four-point star (`StarShape`, a vector
  path with thin rays (`waist` 0.18), 12 pt in a 24 pt target, 13 px at 1x; `Color.brand`, the icon's violet; the panel frame is
  pixel-aligned with `backingAlignedRect` and has no window shadow, so it stays sharp). While an
  action runs (`beginBusy`/`endBusy`, including both translate items) `StarPanel.setBusy` grows the
  panel to `StarButton.busySize` around the same center and `StarBusyView` draws it turning,
  breathing and shifting through the icon's colors (`BrandPalette`) with three small stars on tilted
  orbits (only the color shift with Reduce Motion); it stays shown through typing in a click-through-free non-activating panel (`StarPanel`) -- at the end of the selection
  (below it, away from editors' own selection toolbars) when something is selected, otherwise in the
  focused field's bottom-right corner; never both. Re-evaluated on mouse-up, key-up and app switch
  (debounced), hidden on key-down/scroll; follows the Proofread app filter; skips BindAll itself,
  password and tiny fields. Uses `ProofreadAX.focus(analyze: false)` (no hidden-break walk) and the
  offset map for the selection's end. A click opens an `NSMenu` built by the coordinator: Fix, Fix
  spelling (LanguageTool `correct`), Show translation (popup), Replace with translation (Apple
  Translation, same language pair rules, the result replaces the text through the preview), Remove AI
  tells, action keys (a key with
  `ActionKey.showOnly` shows its result too, from the star and from its own shortcut), Custom
  prompt..., History (the
  last 8 results, `HistoryMenuTitle`; picking one puts its output in place through the preview when
  `previewFromMenu` is on; only with history on), and for the field star "N issues: show the first". `StarContext` captures element, value, selection and map;
  replacing re-activates the app, selects `appRange` and pastes.
- **Windows** (placement is the pure, unit-tested `PanelPlacement.origin(size:near:window:visible:)`; result `PopupController`, `PreviewController`, `CustomPromptController`): one
  `FloatingPanelHost` -- a borderless `KeyablePanel` (Esc via `onEscape`, since borderless panels do
  not reach `onExitCommand`), `sizingOptions = .preferredContentSize`, so it is as big as its content
  (the width is given up front by the pure `PanelWidth.fitting` -- the longest line, 380-560 pt -- so
  the height is measured at the width the text is drawn at; left to SwiftUI's ideal size the text was
  measured as one line and the window came out shorter than its content, hiding its header and
  buttons; the body scrolls past 60% of the screen height; one `setContentSize` after the first
  layout corrects a window that still differs from its content). Result text goes through
  `ResultMarkdown` (inline Markdown styled, headings as bold, Copy without the marks) and follows it as it grows,
  keeping its top edge. Placed by `PanelPlacement`: under the field (`FocusedField.rect()`, the
  focused element), above it when there is no room, else centered on the app's window. Look:
  `.panelChrome()` (material, radius 14, hairline border) and `PanelActionBar` (secondary left,
  Close and the main action right); Quick Translate uses the same bar. `FloatingPanelHost.close()`
  and `QuickTranslateController.close()` order the window out at once but free it on the next main
  run-loop turn: Close is clicked in that very window, and freeing it (with its SwiftUI hierarchy)
  while AppKit is still delivering the click stopped the app after Summarize. The E2E clicks the real
  Close buttons (Summarize from the menu bar, the Fix all preview) and checks the app keeps running. The content goes
  in `IntegralSizeLayout`, which rounds its size up to whole points: with a text-sized width such
  as 483.6 pt the window (483 or 484) and its content kept re-laying each other out until the stack
  ran out (seen with a custom prompt's preview and in the crash logs). `keepOnScreen` runs after a
  resize, not inside its notification, and only moves the window (`setFrameOrigin`).
- **Preview** (`UI/Preview*`): every text-replacing star action shows a word diff (`TextDiff.words`,
  LCS over word+whitespace tokens; `DiffText` renders added on green + underline, removed red +
  strikethrough) with Changes/Result, Close / Copy / Apply (Return). `previewFromMenu` (default on)
  and `previewFromHotkeys` (default off) in Actions. **Custom prompt** (`UI/CustomPrompt*`): a key
  panel with the prompt field, the last 5 prompts (`Settings.recentPrompts`), Save as action key,
  Run (preview, Return) or Show (popup only, Opt+Return).
- **Mask AI Slop rules** (`Actions/MaskAISlopRule.swift`, `MaskAISlop.apply(to:rules:)`): dashes,
  quotes, ellipsis, spaces, emoji (the original five, on by default), decorative trailing emoji,
  Markdown leftovers (`**`, `__`, `#` headings), sign-off lines, and stock phrases (listed only).
  Chosen in Actions -> Mask AI Slop (`Settings.maskAISlopRules`). Inline/fenced code and URLs are
  protected segments and never changed. **Remove AI tells** (star menu) = the chosen rules plus
  `MaskAISlopRule.removeTells`, optionally followed by an AI rewrite (`removeTellsWithAI`); its
  preview notes stock phrases still present.
- **Usage metrics** (`Store/UsageLog.swift`): local only, JSON lines in
  `Application Support/BindAll/Usage/usage-YYYY-MM.jsonl`. Each event: feature, kind
  (shown/accepted/applied/skipped/dismissed/failed), frontmost app, optional ms, and fixed `reason` /
  `detail` tokens chosen by the code -- never user text. `UsageLog.record` is fire-and-forget from any
  thread. Recorded today: autocomplete shown/accepted(index)/dismissed(esc, typedOn, navigation,
  modifier); proofread popup shown/applied(rule)/failed(stale, notApplied)/skipped/dismissed; fix and
  action keys applied/failed with source and ms; translate/OCR shown/failed; Quick Translate opened,
  translated, copied; translation popup copied. Settings -> General shows the count, Show in Finder
  and Clear. Every new feature records its own events.
- **Writing results back:** the frontmost app is captured when an action starts; the result is pasted
  with Cmd+V (reliable across native and Electron/Chromium apps). If focus moved to another app while
  the engine worked, the original app is re-activated first so the result lands where it started.

## Build & test

- **End-to-end** (`./scripts/e2e.sh`, `Tests/E2E/`): builds a separate app "BindAll E2E"
  (`com.evgeny.bindall.e2e`, signed with the dev certificate so its Accessibility grant survives
  rebuilds) with its own UserDefaults and data folder (`AppPaths`: `Application Support/BindAll E2E`),
  writes test settings, launches it and drives TextEdit with synthesized input, then checks the field
  text, the test build's windows (panels are named: "BindAll Underlines: N", "BindAll Fixes",
  "BindAll Suggestions", "BindAll Inline", "BindAll Star", "BindAll Preview", "BindAll Prompt",
  "BindAll Quick Translate"), their AX trees and its usage events. Report: `.build/e2e/report.md`.
  Once: grant "BindAll E2E" Accessibility; quit the real BindAll first. `E2E_ONLY=proofread,quick`
  runs single groups. The star menu is not always in the AX tree, so items are picked with the
  arrows and Return when it is not (`pickMenuItem`); `slack` and `claude` drive those apps (no TextEdit then): Slack in an empty
  "New message" draft, Claude only in the composer of the window in front, left empty by hand, and
  never with Esc (Esc stops a Claude Code session in that app). Chromium word geometry comes from the
  field's AXStaticText children. Skips last for the whole run in every app, so each group types its
  own sentence. Never sends a bare Return outside TextEdit and BindAll's own windows. SwiftUI
  fields ignore Unicode-only synthesized keys, so the driver sets their text through AX.
  Groups (`Tests/E2E/main.swift`, `CoreScenarios.swift`, `ElectronScenarios.swift`): autocomplete,
  proofread, fixAll, dictionary, history, explain, preSend, translateInPlace, voice, stars,
  removeTells, quick, tray, hotkeys (⌘C ⌘C in place, ⌘C ⌘C ⌘C translation window, Restore
  clipboard), starActions (Show translation, an action key, a custom prompt to its result), cancel
  (Esc while an action runs), master (the Enabled switch), settings (every tab of the window), drag (result, preview, prompt and Quick Translate windows move by header and margin),
  slack, claude. Explain and Summarize run from the menu bar (`pressTrayItem`), and explain checks
  the star menu no longer lists them. Star items go through `runStarItem`, which waits for the star to move to the
  selection before clicking it. Checks on model output test its shape (`isShouting`), not its words:
  the on-device model phrases things its own way. A failed precondition is reported as
  "setup: ..." and still counts as a failure. The `say` recording is made once and reused while it
  lasts at least a second.


```bash
xcodebuild -scheme BindAll -configuration Debug build      # build
./Tests/run_tests.sh                                       # pure-logic unit tests
```

For a signing-free local build (CI / no certificate): append `CODE_SIGNING_ALLOWED=NO`.
Open `BindAll.xcodeproj` in Xcode and Run to launch the app (set the signing Team first).

## Permissions
- **Accessibility** — required for the event taps and the synthetic Cmd+V. `HotkeyCoordinator`'s
  2s retry timer polls `AccessibilityPermission.isGranted` and (re)starts the hotkey tap and the
  proofread monitors automatically once it is granted -- no relaunch needed. A macOS upgrade can
  leave the Accessibility checkbox showing granted while `AXIsProcessTrusted()` is actually stale
  (its designated requirement no longer matches what got re-signed); Settings → General → Status
  shows Accessibility and **Global shortcuts** separately for exactly this case -- if shortcuts
  read "Not active" with Accessibility "Granted", remove BindAll from the Accessibility list and
  grant it again. `AccessibilityPermission.listenEventAccessGranted` (Input Monitoring) is
  diagnostic-only, logged when a tap fails to install; it is never requested on its own.
- **Apple Intelligence** — must be enabled for the on-device engine (`AppleFoundationEngine`).
- **Translation language packs** — may download on first use.

## Diagnostics
Failures that used to be silent (a `tapCreate` returning nil, a monitor that never (re)installs) are
now logged via `os.Logger`, subsystem `com.evgeny.bindall`, one category per area (`hotkeys`,
`proofread`, `proofread-ax`, `login-item`, …): `log stream --predicate 'subsystem ==
"com.evgeny.bindall"'`. `ProofreadAX.alignedRange`'s search window now scales with how far into the
text the range sits (`max(16, min(256, location / 20))`) instead of a fixed ±16 UTF-16 units, and a
miss is logged at `.debug` -- a fixed small window is what let long-document offset drift (an app's
own AX bookkeeping disagreeing with ours) silently drop underlines and fixes. All AX calls made
against another app's process now go through a 0.25s `AXUIElementSetMessagingTimeout`
(`ProofreadAX.enableElectronAccessibilityIfNeeded`), so a hung target app cannot hang BindAll's main
thread (and, with it, the active proofread popup tap the system would then disable).

## Key Guarantees
- Menu-bar agent (`LSUIElement`); no Dock icon. The settings window temporarily switches the activation
  policy to `.regular` so it can come to the front, then back to `.accessory` on close.
- **Accent color:** `Assets.xcassets/AccentColor` (BindAll's violet, `#990FE0`, lighter in dark mode,
  with high-contrast variants), named by `NSAccentColorName` in Info.plist, so default buttons,
  toggles, segmented controls, focus rings and the popups' `selectedContentBackgroundColor`
  selection are violet. macOS uses it only while System Settings > Appearance > Accent color is
  Multicolor (the default); a color the user picked there wins, as it should. Menus (the status
  menu, the star's menu) are drawn by macOS in the system accent and stay that way on purpose.
- The status icon is always the same three sparkles, drawn by `StatusIconRenderer` (a template image
  laid out like the `sparkles` symbol, which has no per-layer variable rendering); the three states
  differ only in alpha and size (`AppDelegate.updateStatusIcon`): full while idle, the sparkles
  flaring one after another while an action runs (`StatusIconTwinkle`: a 1 s round, 0.2 s apart,
  dim 0.15, each swelling at its peak; the first frame already has the big one lit, and a wave plays
  at least two rounds and stops at the end of one, so a quick action is seen; frames of the button's
  own image at 20 fps, so the click highlight still works), and the button dimmed to `disabledAlpha` while the
  master switch (`settings.enabled`) is off. It does not gate the menu-bar items: a click is a clear request. The master switch gates the
  hotkey bursts, autocomplete and proofread alike, so "off" must stay visually distinguishable --
  otherwise a disabled app looks exactly like a working one whose shortcuts do nothing.
- The status menu draws every shortcut hint itself (one right-aligned column; Explain, Summarize and the selection commands show none until one is set) and has
  **no real key equivalents**. Give an item a real one and the system reserves its own column right of
  the widest title -- our drawn line counts as a title -- so it lands to the right of ours and moving
  ours only pushes it further; that is why Settings and Quit are drawn too. Their keys still work
  while the menu is open through a local key monitor installed in `menuWillOpen` and removed in
  `menuDidClose`.
- API keys live in the **Keychain**, never in `UserDefaults`.
- Hotkey bursts are debounced by a time window; a busy watchdog (25s) guarantees a stalled operation
  can never permanently block future hotkeys.
- Settings are a single Codable struct persisted to `UserDefaults` and merged with defaults on read.

## AI Instructions

Rules for AI assistants working on this project. **No emojis** in code, comments, docs, or commit
messages. All code, comments, docs, UI strings, and commit messages are in **English**.

### Audit AGENTS.md before changes
Before modifying source, review this file and update it if the change introduces new conventions,
shifts architecture, or deprecates documented behavior. This file is the single source of truth — keep
it in sync with the code.

### Build must stay green
After any code change, the project must compile: `xcodebuild -scheme BindAll build CODE_SIGNING_ALLOWED=NO`.
If logic in `Actions/` or `Engines/` changes, run `./Tests/run_tests.sh` and extend the tests.

### Git hygiene
Commit before starting new work. If the tree has uncommitted changes, checkpoint them first
(`"WIP: checkpoint before <task>"`). Keep each logical change in its own commit.

### Version bump
Before committing a code change, increment the version in `Info.plist`
(`CFBundleShortVersionString`, semver) and bump `CFBundleVersion`.
