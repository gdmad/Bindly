import Foundation

// Compares Apple's built-in text features with what BindAll uses now. Not part of the app.
var report = "# Apple built-ins vs BindAll today\n\n"
report += await runSpellBench()
report += await runOCRBench()
report += runSpeechBench()
print(report)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bench-report.md")
try? report.write(to: out, atomically: true, encoding: .utf8)
