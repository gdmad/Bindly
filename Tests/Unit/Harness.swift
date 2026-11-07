import AVFoundation
import CoreGraphics
import Foundation

// Tiny assertion harness (avoids needing an XCTest bundle/host for pure-logic tests).

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ \(message)")
    }
}
func eq(_ a: String, _ b: String, _ message: String) {
    check(a == b, "\(message)  (got: \(a.debugDescription))")
}

func eqArr(_ a: [String], _ b: [String], _ message: String) {
    check(a == b, "\(message)  (got: \(a))")
}

func issue(_ location: Int, _ length: Int, source: IssueSource = .languageTool,
           kind: IssueKind = .spelling, original: String = "x",
           replacements: [String] = [], ruleId: String? = nil) -> TextIssue {
    TextIssue(range: NSRange(location: location, length: length), kind: kind, shortMessage: "",
              message: "", replacements: replacements, ruleId: ruleId, source: source, original: original)
}

func decodeSettings(_ json: String) -> Settings {
    try! JSONDecoder().decode(Settings.self, from: json.data(using: .utf8)!)
}
