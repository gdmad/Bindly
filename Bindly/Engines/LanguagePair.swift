import Foundation

/// Which way a translation goes, the same for every entry point (the shortcut, the star, OCR, Quick
/// Translate, dictation). With an automatic source the text goes into the target. With an explicit
/// source the pair works both ways: text in the source language goes into the target, anything else
/// into the source.
enum LanguagePair {
    struct Direction: Equatable {
        /// Nil when the language of the text is unknown: the Translation framework detects it.
        let from: String?
        let to: String
        /// The text is in `to` already: there is nothing to translate.
        var isAlreadyThere: Bool { from == to }
    }

    static func resolve(detected: String?, source: String, target: String) -> Direction {
        if source == AppLanguages.autoTag {
            return Direction(from: detected, to: target)
        }
        let to = detected == nil || detected == source ? target : source
        return Direction(from: detected ?? source, to: to)
    }
}
