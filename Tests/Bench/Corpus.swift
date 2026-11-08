import Foundation

/// Sentences with known mistakes: each `wrong` word should be flagged and corrected to `right`.
/// Typical chat typos, Russian and English, plus clean sentences to count false alarms.
struct BenchCase {
    let language: String
    let text: String
    let fixes: [(wrong: String, right: String)]
}

enum Corpus {
    static let cases: [BenchCase] = [
        BenchCase(language: "ru", text: "Вчера малако было свежее, а сегодня уже кислое.", fixes: [("малако", "молоко")]),
        BenchCase(language: "ru", text: "Я обезательно пришлю отчёт завтра утром.", fixes: [("обезательно", "обязательно")]),
        BenchCase(language: "ru", text: "Давай встретимся в понедельник, если ты не протиа.", fixes: [("протиа", "против")]),
        BenchCase(language: "ru", text: "Это была очень интересная презинтация.", fixes: [("презинтация", "презентация")]),
        BenchCase(language: "ru", text: "Он сказал что придёт позже.", fixes: [("сказал", "сказал,")]),
        BenchCase(language: "ru", text: "Мы обсудили бюджет и сроки, всё в порядке.", fixes: []),
        BenchCase(language: "ru", text: "Пожалуйста проверь ощибки в тексте.", fixes: [("ощибки", "ошибки"), ("Пожалуйста", "Пожалуйста,")]),
        BenchCase(language: "ru", text: "Завтра будет сильный ветер и дождь.", fixes: []),
        BenchCase(language: "ru", text: "Нам нужно согласовать этот вопрос с руководстом.", fixes: [("руководстом", "руководством")]),
        BenchCase(language: "ru", text: "Заказчик не успел прислать техническое заданние.", fixes: [("заданние", "задание")]),
        BenchCase(language: "en", text: "I will definately send the report tomorrow.", fixes: [("definately", "definitely")]),
        BenchCase(language: "en", text: "Their going to the meeting at noon.", fixes: [("Their", "They're")]),
        BenchCase(language: "en", text: "Please recieve the attached document.", fixes: [("recieve", "receive")]),
        BenchCase(language: "en", text: "The budget and the deadline are both fine.", fixes: []),
        BenchCase(language: "en", text: "We should of called them earlier.", fixes: [("should of", "should have")]),
        BenchCase(language: "en", text: "This is a seperate issue for the next sprint.", fixes: [("seperate", "separate")]),
        BenchCase(language: "en", text: "Its a good idea to check the logs first.", fixes: [("Its", "It's")]),
        BenchCase(language: "en", text: "The weather is nice today.", fixes: []),
        BenchCase(language: "en", text: "I am writting to confirm the date.", fixes: [("writting", "writing")]),
        BenchCase(language: "en", text: "Lets meet on Monday if your free.", fixes: [("Lets", "Let's"), ("your", "you're")]),
    ]
}
