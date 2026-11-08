import Foundation

/// Text typed in the wrong keyboard layout, put back: "Ghbdtn" -> "Привет", "руддщ" -> "hello".
/// Key by key between the US and Russian (ЙЦУКЕН) layouts; a model gets this wrong as often as not.
enum KeyboardLayoutMap {
    private static let english = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&")
    private static let russian = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,\"№;:?")

    private static let toRussian = Dictionary(zip(english, russian), uniquingKeysWith: { first, _ in first })
    private static let toEnglish = Dictionary(zip(russian, english), uniquingKeysWith: { first, _ in first })

    /// Mostly Latin letters: typed for Russian on the US layout; otherwise the other way round.
    static func convert(_ text: String) -> String {
        let latin = text.unicodeScalars.filter { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }.count
        let cyrillic = text.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
        let map = latin >= cyrillic ? toRussian : toEnglish
        return String(text.map { map[$0] ?? $0 })
    }
}
