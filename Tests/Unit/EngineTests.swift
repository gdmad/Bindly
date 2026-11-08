import Foundation

private struct StubEngine: AIEngine {
    let reply: Result<String, Error>
    var delay: Duration = .zero
    func process(text: String, instruction: String) async throws -> String {
        if delay > .zero { try await Task.sleep(for: delay) }
        return try reply.get()
    }
    func testConnection() async throws -> String { "ok" }
}

private func run(_ engine: AIEngine, _ text: String) -> EngineAnswer? {
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var out: EngineAnswer?
    Task.detached {
        out = try? await engine.answer(text: text, instruction: "Fix")
        done.signal()
    }
    done.wait()
    return out
}

func runEngineTests() {
    print("FallbackEngine")
    let russian = "Совещание переносится на четверг, потому что заказчик не успел прислать документы."
    let cloud = StubEngine(reply: .success("Совещание переносится на четверг."))
    func fallback(_ apple: StubEngine, checks: Bool) -> FallbackEngine {
        FallbackEngine(primary: apple, secondary: cloud, secondaryName: "DeepSeek", checksLanguage: checks)
    }
    let fine = run(fallback(StubEngine(reply: .success("Совещание перенесли на четверг.")), checks: true), russian)
    check(fine == EngineAnswer(text: "Совещание перенесли на четверг.", answeredBy: nil), "the Apple answer is kept when it is fine")
    let failed = run(fallback(StubEngine(reply: .failure(EngineError.unavailable("unsupported language"))), checks: true), russian)
    check(failed?.answeredBy == "DeepSeek", "an Apple failure goes to the provider")
    let english = StubEngine(reply: .success("The meeting is moved to Thursday because the client did not send the documents."))
    check(run(fallback(english, checks: true), russian)?.answeredBy == "DeepSeek", "an answer in another language goes to the provider")
    check(run(fallback(english, checks: false), russian)?.answeredBy == nil, "a custom prompt's language is not checked")
    check(run(StubEngine(reply: .success("x")), russian) == EngineAnswer(text: "x", answeredBy: nil), "a plain engine names no one")

    // Esc: a cancelled task does not move on to the provider.
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var cancelledAnswer: EngineAnswer?
    let task = Task.detached {
        cancelledAnswer = try? await fallback(StubEngine(reply: .failure(CancellationError()), delay: .milliseconds(200)), checks: true)
            .answer(text: russian, instruction: "Fix")
        done.signal()
    }
    task.cancel()
    done.wait()
    check(cancelledAnswer == nil, "a cancelled action is not retried elsewhere")

    print("LanguageMatch")
    check(LanguageMatch.differs(input: russian, output: "The meeting is moved to Thursday because the client did not send the documents."),
          "Russian in, English out: differs")
    check(!LanguageMatch.differs(input: russian, output: "Совещание перенесли на четверг из-за документов."), "same language: does not")
    check(!LanguageMatch.differs(input: "ok", output: "да"), "too short to tell: does not")
}
