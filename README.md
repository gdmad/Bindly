<p align="center">
  <img src="assets/logo.png" width="120" alt="BindAll logo">
</p>

<h1 align="center">BindAll</h1>

<p align="center">
  A minimal macOS menu-bar utility that acts on the currently selected text with global shortcuts —
  fix grammar, run custom prompts, translate, and OCR-translate from the screen.<br>
  On-device by default (Apple Intelligence + Apple Translation), with optional cloud providers.
</p>

No Dock icon: BindAll lives in the menu bar (`LSUIElement`); the icon pulses while an action runs.

## Features

- **Fix / transform text** — select text, press the shortcut, and the corrected result replaces it in
  place. Uses the Apple on-device model by default, or a cloud provider.
- **Action keys** — saved, named instructions, run from the star menu or **their own global
  shortcut**. Built in: Formal tone, Polite request.
- **Text tools** — UPPERCASE, lowercase and Fix keyboard layout, done without AI and exactly; in the
  star menu and with optional shortcuts.
- **Explain / Summarize** — for text someone else wrote: select it and pick Explain selection or
  Summarize selection in the menu bar, or give them a shortcut on the Shortcuts tab. The result opens
  in a window; the text is left as it is.
- **Translate** — on-device translation (Apple Translation) into your target language with source
  auto-detection, shown in a popup near the cursor with the original text and Copy.
- **Quick Translate** — a window to type text and translate it on the fly, with a Source/Target
  language pair and swap.
- **OCR translate** — drag-select a screen region; text is recognized (Vision) and translated.
- **Proofread (LanguageTool)** — optional: shortly after you pause typing, the focused field is
  checked by a [LanguageTool](https://languagetool.org) server (public, self-hosted, or Premium) and
  every issue is underlined in place. Click an underlined word to pick a fix; Tab moves to the next
  issue, and applying a fix walks straight to the next one when several are found. No shortcut
  involved. Enable and configure it all on the Proofread tab. In Self-hosted mode BindAll can install
  and run its own portable LanguageTool (own Java runtime, one folder, ~540 MB, listens on this Mac
  only) with one click, and remove it completely with another; a server of your own stays available
  as a second choice.
  **Google Docs and other sites:** Google Docs draws its text on a canvas that macOS accessibility
  cannot read, so BindAll cannot check it. Use the LanguageTool browser extension there and point it
  at the same server: in the extension's settings, Advanced settings -> local or other server, URL
  `http://127.0.0.1:<port>/v2` for BindAll's local server (or your self-hosted URL). Some users report
  the extension failing against a local server in Chromium, and the extension's own terms may change,
  so check it works before relying on it.
- **Providers** — Apple on-device (default), DeepSeek, OpenRouter, OpenAI, Ollama. Add an API key,
  pick a model, Test connection. OpenRouter has a "free models only" filter.
- **History** — the last results are kept locally and reachable from the menu bar (click to copy).
- **Mask AI Slop** — optional: normalize em/en dashes, smart quotes/apostrophes, strip emoji.
- **Word autocomplete** *(off by default)* — as you type, a list of case-matched completions appears
  near the caret; arrow keys move the selection, **Tab** (and optionally Return) inserts. Completions
  are ranked by the preceding words, not just personal frequency; it also predicts the next word
  after a space and learns the words you use, locally, with a review sheet that flags likely typos
  for cleanup. Enable and configure it all on the Autocomplete tab: count, layout, text size,
  dictionary language, and per-app allow/deny.
- **Launch at login**, automatic light/dark, and in-app **Check for Updates**.

## Where it works

Checked so far (more apps as they are tested):

| App | Autocomplete | Proofread | Stars |
|---|---|---|---|
| TextEdit | inline + list | yes | yes |
| Slack | list | yes (lists, quotes, code blocks, emoji) | yes |
| Claude (desktop) | list | yes | yes |
| Google Docs | no (canvas, no accessible text) | no | no |

## Default shortcuts

All shortcuts are configurable in Settings → Actions → Shortcuts.

| Shortcut | Action |
|---|---|
| `Cmd+C` ×2 | Fix / run the default action on the selection |
| `Cmd+C` ×3 | Translate the selection (popup) |
| `Cmd+E` | OCR: select a screen region and translate it |
| `Shift+Cmd+E` | Open Quick Translate |
| `Esc` | Cancel the action in progress |

Because `Cmd+C` is the real copy shortcut, pressing it the configured number of times both copies the
selection and triggers BindAll. Per-action-key shortcuts (any combo you record) copy the selection
themselves.

## Install

Download the latest `BindAll-<version>.dmg` from [Releases](https://github.com/gdmad/BindAll/releases),
open it, and drag **BindAll** into **Applications**.

The build is **not notarized** (no paid Apple Developer account), so macOS blocks it on first launch.
Open **System Settings → Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to
BindAll. You only do this once.

## Permissions

1. **Accessibility** — required to detect the shortcut key taps and to paste results back. On first
   launch BindAll asks for it; grant it in *System Settings → Privacy & Security → Accessibility*.
   The tap starts automatically once granted (no relaunch needed).
2. **Apple Intelligence** — needed only for the on-device text engine. Enable it in System Settings;
   the General tab shows live status. Cloud providers work without it.
3. **Translation language packs** may download once on first use.

## Privacy

- API keys are stored in the **Keychain**, never in plain settings or the repo.
- The default engine and translation run **on device**. Cloud providers are used only if you select
  one and add a key.
- History is stored locally in `~/Library/Application Support/BindAll/` and never includes API keys;
  it can be turned off and cleared.

## Build from source

Requirements: **macOS 26**, **Xcode 26**.

```sh
open BindAll.xcodeproj
```

In Xcode, select the **BindAll** target → *Signing & Capabilities* → set **your** Team (a stable
signature keeps the Accessibility grant across rebuilds). Then Run. From the CLI without signing:

```sh
xcodebuild -scheme BindAll build CODE_SIGNING_ALLOWED=NO
```

Build a distributable `.dmg`:

```sh
./scripts/release.sh             # local-signed dmg in .release/
./scripts/release.sh --notarize  # Developer ID + notarization (paid account required)
```

## Tests

Pure-logic unit tests (no Xcode host needed):

```sh
./Tests/run_tests.sh
```

The autocomplete ranking has its own evaluator under `Tests/` (see [AGENTS.md](AGENTS.md) for how
to run it).

## Architecture

```
BindAll/
  App/           AppDelegate (menu bar, settings window, icon), AppState, UpdateChecker
  Hotkeys/       HotkeyMonitor (CGEventTap), HotkeyCoordinator, AccessibilityPermission
  Selection/     TextInjector (synthetic Cmd+C / Cmd+V), InjectedEvents
  Engines/       AIEngine, AppleFoundationEngine, OpenAICompatibleEngine, LanguageToolEngine,
                 TranslationService, OCRService
  Actions/       ActionRouter (EngineFactory), MaskAISlop
  Autocomplete/  AutocompleteController (CGEventTap), AutocompleteEngine, AutocompleteLearningStore,
                 AutocompleteOverlay, LearnedWordAudit
  Proofread/     ProofreadController, ProofreadAX, IssueApplier, IssueMerger, UnderlineOverlay
  UI/            SettingsView + one view per tab, PopupKit (shared popup chrome/placement)
  Store/         Settings, ActionKey, KeychainStore, HistoryStore, LoginItemManager, AppLanguages
Tests/           run_tests.sh, Unit/ (unit tests by area), E2E/, autocomplete ranking evaluator
```

The visible UI (status item, settings window, popups) is driven from `AppDelegate` with AppKit; the
SwiftUI `App` only hosts the settings views. See [AGENTS.md](AGENTS.md) for the full structure and
contributor conventions.

## Credits

- Russian autocomplete seed data (next-word prediction and completion ranking): bigram and trigram
  frequencies from the Leipzig Corpora Collection, `rus_news_2023` sample, licensed
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## License

[MIT](LICENSE) © Evgeny Mishenko
