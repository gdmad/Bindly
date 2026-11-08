import AppKit
import FoundationModels
import NaturalLanguage

/// One checker's verdict on one sentence.
struct Finding {
    let range: NSRange
    let suggestion: String?
}

struct Score {
    var expected = 0, found = 0, fixedRight = 0, falseAlarms = 0, ms: [Double] = []
    var line: String {
        let avg = ms.isEmpty ? 0 : ms.reduce(0, +) / Double(ms.count)
        return "found \(found)/\(expected), right fix \(fixedRight)/\(expected), false alarms \(falseAlarms), avg \(Int(avg)) ms"
    }
}

func score(_ c: BenchCase, _ findings: [Finding], ms: Double, into s: inout Score) {
    let ns = c.text as NSString
    s.expected += c.fixes.count
    s.ms.append(ms)
    var matched = Set<Int>()
    for fix in c.fixes {
        let wrong = ns.range(of: fix.wrong)
        guard wrong.location != NSNotFound else { continue }
        if let (index, f) = findings.enumerated().first(where: { NSIntersectionRange($0.element.range, wrong).length > 0 }) {
            s.found += 1
            matched.insert(index)
            // The fix is right when putting the suggestion in gives the expected words.
            if let suggestion = f.suggestion {
                let fixed = ns.replacingCharacters(in: f.range, with: suggestion)
                if fixed.contains(fix.right) { s.fixedRight += 1 }
            }
        }
    }
    s.falseAlarms += findings.indices.filter { !matched.contains($0) }.count
}

// MARK: NSSpellChecker

func spellChecker(_ c: BenchCase) -> [Finding] {
    let checker = NSSpellChecker.shared
    checker.automaticallyIdentifiesLanguages = false
    _ = checker.setLanguage(c.language)
    let ns = c.text as NSString
    let types = NSTextCheckingResult.CheckingType.spelling.rawValue | NSTextCheckingResult.CheckingType.grammar.rawValue
    let results = checker.check(c.text, range: NSRange(location: 0, length: ns.length), types: types,
                                options: [.orthography: NSOrthography.defaultOrthography(forLanguage: c.language)],
                                inSpellDocumentWithTag: 0, orthography: nil, wordCount: nil)
    var out: [Finding] = []
    for r in results {
        if r.resultType == .spelling {
            let guess = checker.guesses(forWordRange: r.range, in: c.text, language: c.language, inSpellDocumentWithTag: 0)?.first
            out.append(Finding(range: r.range, suggestion: guess))
        } else if r.resultType == .grammar {
            for detail in r.grammarDetails ?? [] {
                let range = (detail[NSGrammarRange] as? NSValue)?.rangeValue ?? r.range
                let correction = (detail[NSGrammarCorrections] as? [String])?.first
                out.append(Finding(range: NSRange(location: r.range.location + range.location, length: range.length), suggestion: correction))
            }
        }
    }
    return out
}

// MARK: LanguageTool

func languageTool(_ c: BenchCase, server: String) -> [Finding]? {
    var request = URLRequest(url: URL(string: server + "/check")!)
    request.httpMethod = "POST"
    let lang = c.language == "ru" ? "ru-RU" : "en-US"
    let body = "text=\(c.text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)&language=\(lang)"
    request.httpBody = Data(body.utf8)
    request.timeoutInterval = 15
    let done = DispatchSemaphore(value: 0)
    var data: Data?
    URLSession.shared.dataTask(with: request) { d, _, _ in data = d; done.signal() }.resume()
    done.wait()
    guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let matches = json["matches"] as? [[String: Any]] else { return nil }
    // LanguageTool counts UTF-16 units like NSString.
    return matches.compactMap { m in
        guard let offset = m["offset"] as? Int, let length = m["length"] as? Int else { return nil }
        let suggestion = (m["replacements"] as? [[String: Any]])?.first?["value"] as? String
        return Finding(range: NSRange(location: offset, length: length), suggestion: suggestion)
    }
}

// MARK: Foundation Models (the current Fix)

let fixPrompt = "Fix spelling, grammar and punctuation. Keep the same language and formatting. Return only the corrected text."

func foundationModels(_ c: BenchCase) async -> String? {
    guard case .available = SystemLanguageModel.default.availability else { return nil }
    let session = LanguageModelSession(instructions: fixPrompt)
    return try? await session.respond(to: c.text, options: GenerationOptions(temperature: 0)).content
}

func runSpellBench() async -> String {
    var report = "## Spelling and grammar\n\n"
    let servers = [("LanguageTool (free public)", "https://api.languagetool.org/v2"),
                   ("LanguageTool (your server)", "http://192.168.31.105:8081/v2")]
    for language in ["ru", "en"] {
        let cases = Corpus.cases.filter { $0.language == language }
        report += "### \(language)\n\n| Checker | Result |\n|---|---|\n"
        var apple = Score()
        for c in cases {
            let t = Date()
            let f = spellChecker(c)
            score(c, f, ms: Date().timeIntervalSince(t) * 1000, into: &apple)
        }
        report += "| NSSpellChecker | \(apple.line) |\n"
        for (name, url) in servers {
            var lt = Score()
            var reachable = true
            for c in cases {
                let t = Date()
                guard let f = languageTool(c, server: url) else { reachable = false; break }
                score(c, f, ms: Date().timeIntervalSince(t) * 1000, into: &lt)
                usleep(300_000) // the public server limits the rate
            }
            report += "| \(name) | \(reachable ? lt.line : "not reachable") |\n"
        }
        // The model rewrites the sentence: a fix counts when the right word is in and the wrong one out.
        var fm = Score()
        var answered = 0
        for c in cases {
            let t = Date()
            guard let out = await foundationModels(c) else { continue }
            answered += 1
            fm.ms.append(Date().timeIntervalSince(t) * 1000)
            fm.expected += c.fixes.count
            for fix in c.fixes where out.contains(fix.right) && !out.contains(fix.wrong + " ") {
                fm.found += 1; fm.fixedRight += 1
            }
            if c.fixes.isEmpty, out.trimmingCharacters(in: .whitespacesAndNewlines) != c.text { fm.falseAlarms += 1 }
        }
        report += "| Foundation Models (Fix) | \(answered == 0 ? "unavailable" : fm.line + ", \(answered)/\(cases.count) answered") |\n\n"
    }
    // Explain and Summarize on Russian text: does the on-device model answer in Russian, and at all?
    let russian = "Совещание переносится на четверг, потому что заказчик не успел прислать ТЗ и правки к макетам."
    for (name, instruction) in [("Explain", "Explain what this text says and means in plain words, briefly, in the same language as the text. Reply with the explanation only, as plain text without Markdown."),
                                ("Summarize", "Summarize this text in one to three sentences, in the same language as the text. Reply with the summary only, as plain text without Markdown.")] {
        let t = Date()
        let session = LanguageModelSession(instructions: instruction)
        let answer = (try? await session.respond(to: russian, options: GenerationOptions(temperature: 0)).content) ?? ""
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(answer)
        let lang = recognizer.dominantLanguage?.rawValue ?? "none"
        report += "- Foundation Models \(name) on Russian text: answer in `\(lang)`, \(answer.count) characters, \(Int(Date().timeIntervalSince(t) * 1000)) ms\n"
    }
    report += "\n"
    let languages = SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier }
    report += "Foundation Models supported languages include ru: \(languages.contains("ru")), en: \(languages.contains("en")).\n\n"
    return report
}
