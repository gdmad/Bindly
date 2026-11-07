import AVFoundation
import CoreGraphics
import Foundation

func runSettingsTests() {
    print("Settings proofread and popup keys")
    let sDefaults = decodeSettings("{}")
    check(sDefaults.proofreadMaxReplacements == 3, "missing key defaults max replacements to 3")
    check(sDefaults.popupFontSize == 13, "missing key defaults the popup font size to 13")
    // autocompleteFontSize is the old name; the setting now drives both popups.
    check(decodeSettings(#"{"autocompleteFontSize": 17}"#).popupFontSize == 17,
          "legacy autocompleteFontSize key still honoured")
    check(decodeSettings(#"{"autocompleteFontSize": 17, "popupFontSize": 11}"#).popupFontSize == 11,
          "new popupFontSize key wins over the legacy one")
    // Keys of removed settings must not break decoding of everything else.
    check(decodeSettings(#"{"proofreadAutoOnClick": false, "proofreadMaxReplacements": 5}"#).proofreadMaxReplacements == 5,
          "a removed key is ignored without losing the rest")
    print("Settings.languageToolConnection")
    var s = Settings()
    s.languageToolUsername = "me@x.com"
    s.languageToolBaseURL = "http://home.lan:8081/v2"

    s.languageToolMode = .free
    let free = s.languageToolConnection(token: "secret")
    eq(free.baseURL, "http://home.lan:8081/v2", "free uses the (editable) stored URL")
    check(free.username.isEmpty && free.apiKey.isEmpty, "free never sends credentials, even if filled in")

    s.languageToolMode = .premium
    let prem = s.languageToolConnection(token: "secret")
    eq(prem.baseURL, "http://home.lan:8081/v2", "premium uses the stored URL")
    eq(prem.username, "me@x.com", "premium sends the username")
    eq(prem.apiKey, "secret", "premium sends the token")

    s.languageToolMode = .selfHosted
    let selfh = s.languageToolConnection(token: "secret")
    eq(selfh.baseURL, "http://home.lan:8081/v2", "self-hosted uses the user URL")
    check(selfh.username.isEmpty && selfh.apiKey.isEmpty,
          "self-hosted sends no credentials: the server is reached by URL alone")

    print("Settings persistence: every setting survives a round trip")
    // A setting that reaches the struct but not CodingKeys (or not init(from:)) is silently dropped on
    // save and comes back as its default -- the "I changed it and it did not stick" class of bug. This
    // fixture changes EVERY field, so any such field breaks the round trip below.
    var allChanged = Settings()
    allChanged.enabled = false
    allChanged.defaultEngine = .openai
    allChanged.defaultPrompt = "custom prompt"
    allChanged.actionKeys = [ActionKey(label: "Zap", prompt: "Zap it",
                                       hotkey: HotkeyConfig(keyCode: 6,
                                                            modifiers: HotkeyModifiers(command: true, option: true),
                                                            repeatCount: 1))]
    allChanged.restoreClipboard = true
    allChanged.maskAISlop = true
    allChanged.autocompleteEnabled = true
    allChanged.autocompleteCount = 9
    allChanged.popupFontSize = 20
    allChanged.autocompleteLayout = .tile
    allChanged.autocompleteLanguages = ["ru", "en"]
    allChanged.autocompleteLearn = false
    allChanged.autocompleteNextWord = false
    allChanged.autocompleteAcceptReturn = false
    allChanged.autocompleteInline = false
    allChanged.starFieldEnabled = false
    allChanged.starSelectionEnabled = false
    allChanged.previewFromMenu = false
    allChanged.previewFromHotkeys = true
    allChanged.recentPrompts = ["x"]
    allChanged.maskAISlopRules = ["closers"]
    allChanged.removeTellsWithAI = true
    allChanged.autocompleteContextRanking = false
    allChanged.autocompleteAppMode = "deny"
    allChanged.autocompleteApps = ["com.example.one"]
    allChanged.proofreadMaxReplacements = 7
    allChanged.proofreadLayout = .line
    allChanged.proofreadMinLength = 42
    allChanged.proofreadAppMode = "allow"
    allChanged.proofreadApps = ["com.example.two"]
    allChanged.personalDictionary = ["Swearl"]
    allChanged.preSendCheck = true
    allChanged.pushToTalkEnabled = true
    allChanged.pushToTalkKey = .shortcut(HotkeyConfig(keyCode: 49, modifiers: HotkeyModifiers(command: false, control: true), repeatCount: 1))
    allChanged.pushToTalkLanguage = "ru"
    allChanged.pushToTalkTranslate = true
    allChanged.pushToTalkTargetLanguage = "de"
    allChanged.voiceTranslateEnabled = true
    allChanged.voiceTranslateKey = .rightOption
    allChanged.historyEnabled = false
    allChanged.sourceLanguage = "de"
    allChanged.targetLanguage = "fr"
    allChanged.correctEnabled = true
    allChanged.languageToolMode = .premium
    allChanged.languageToolBaseURL = "http://home.lan:8081/v2"
    allChanged.languageToolUsername = "me@example.com"
    allChanged.languageToolLanguage = "uk"
    allChanged.openRouterFreeOnly = true
    allChanged.providers = [ProviderConfig(kind: .ollama, baseURLOverride: "http://localhost:11434", model: "qwen")]
    allChanged.defaultActionHotkey = HotkeyConfig(keyCode: 1, modifiers: HotkeyModifiers(command: true), repeatCount: 1)
    allChanged.translateHotkey = HotkeyConfig(keyCode: 2, modifiers: HotkeyModifiers(command: true, shift: true), repeatCount: 2)
    allChanged.screenTranslateHotkey = HotkeyConfig(keyCode: 3, modifiers: HotkeyModifiers(command: true, control: true), repeatCount: 1)
    allChanged.quickTranslateHotkey = HotkeyConfig(keyCode: 4, modifiers: HotkeyModifiers(command: true, option: true), repeatCount: 3)
    allChanged.explainHotkey = HotkeyConfig(keyCode: 14, modifiers: HotkeyModifiers(command: false, option: true, control: true), repeatCount: 1)
    allChanged.summarizeHotkey = HotkeyConfig(keyCode: 1, modifiers: HotkeyModifiers(command: false, option: true, control: true), repeatCount: 1)

    let savedSettings = try! JSONEncoder().encode(allChanged)
    check(try! JSONDecoder().decode(Settings.self, from: savedSettings) == allChanged,
          "every setting survives encode -> decode unchanged")

    let savedJSON = try! JSONSerialization.jsonObject(with: savedSettings) as! [String: Any]
    let defaultJSON = try! JSONSerialization.jsonObject(with: try! JSONEncoder().encode(Settings())) as! [String: Any]
    // Guards the fixture itself: a new setting nobody changed above would make the round trip pass for
    // the wrong reason.
    let untouched = savedJSON.keys.filter { key in
        guard let mine = savedJSON[key], let theirs = defaultJSON[key] else { return false }
        return NSDictionary(dictionary: [key: mine]).isEqual(to: [key: theirs])
    }.sorted()
    check(untouched.isEmpty, "the fixture changes every setting (still at default: \(untouched))")
    // And that nothing was added to the struct without a CodingKey, which is how a setting stops saving.
    check(savedJSON.count == Mirror(reflecting: allChanged).children.count,
          "every stored property has a CodingKey (\(savedJSON.count) encoded vs \(Mirror(reflecting: allChanged).children.count) properties)")

    print("Settings default and resilient decoding")
    func decode(_ json: String) -> Settings {
        try! JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }
    check(decode("{}").languageToolMode == .free, "mode defaults to free when absent (no migration)")
    check(decode("{\"languageToolMode\":\"premium\"}").languageToolMode == .premium, "a stored mode is kept")
    check(decode("{\"autocompleteHorizontal\":true}").autocompleteLayout == .line,
          "legacy autocompleteHorizontal=true maps to line")
    check(decode("{\"autocompleteHorizontal\":false}").autocompleteLayout == .column,
          "legacy autocompleteHorizontal=false maps to column")
    check(decode("{\"autocompleteLayout\":\"tile\"}").autocompleteLayout == .tile,
          "the new autocompleteLayout wins over the legacy key")
    check(decode("{}").proofreadLayout == .column, "proofread layout defaults to column")

    print("ShortcutConflicts")
    do {
        var settings = Settings()
        let twice = HotkeyConfig.defaultAction
        check(ShortcutConflicts.isDuplicate(twice, among: [twice]), "the same shortcut is a duplicate")
        check(!ShortcutConflicts.isDuplicate(HotkeyConfig(keyCode: 8, modifiers: HotkeyModifiers(command: true), repeatCount: 1),
                                            among: [twice]), "a different number of presses is not")
        check(!ShortcutConflicts.isDuplicate(HotkeyConfig(keyCode: 8, modifiers: HotkeyModifiers(command: true, shift: true), repeatCount: 2),
                                            among: [twice]), "nor are different modifiers")
        let hold = HotkeyConfig(keyCode: 49, modifiers: HotkeyModifiers(command: false, control: true), repeatCount: 1)
        settings.pushToTalkKey = .shortcut(hold)
        check(ShortcutConflicts.isDuplicate(hold, among: ShortcutConflicts.others(excluding: "fix", in: settings)),
              "a Push to Talk shortcut counts against the others")
        check(!ShortcutConflicts.others(excluding: "ptt", in: settings).contains(hold), "but not against itself")
        settings.pushToTalkKey = .rightOption
        check(ShortcutConflicts.all(in: settings).count == 4 + settings.actionKeys.filter { $0.hotkey != nil }.count,
              "a modifier hold key is no shortcut to clash with")
        let explain = HotkeyConfig(keyCode: 14, modifiers: HotkeyModifiers(command: true, option: true), repeatCount: 1)
        settings.explainHotkey = explain
        check(ShortcutConflicts.others(excluding: "summarize", in: settings).contains(explain),
              "an Explain shortcut counts against the others")
        check(!ShortcutConflicts.others(excluding: "explain", in: settings).contains(explain), "but not against itself")
    }
}
