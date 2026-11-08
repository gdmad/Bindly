import NaturalLanguage

/// Whether a model answered in another language than the text it was given. Only when both are
/// recognized with confidence: short or mixed text says nothing either way.
enum LanguageMatch {
    static func differs(input: String, output: String, confidence: Double = 0.8) -> Bool {
        guard let a = confident(input, confidence), let b = confident(output, confidence) else { return false }
        return a != b
    }

    private static func confident(_ text: String, _ threshold: Double) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, p) = recognizer.languageHypotheses(withMaximum: 1).first, p >= threshold else { return nil }
        return language
    }
}
