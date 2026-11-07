import ApplicationServices
import Foundation

/// The text a star stands for: the selection, or the whole field. Captured when the star is shown,
/// because by the time an action finishes focus may be elsewhere (the prompt or preview panel).
struct StarContext {
    let element: AXUIElement
    let pid: pid_t
    /// The field's whole value.
    let text: String
    /// The selection in value offsets; empty for the field star.
    let selection: NSRange
    let offsetMap: AppOffsetMap?
    /// Where the star is, AppKit screen coordinates: panels open next to it.
    let anchor: NSPoint
    /// Read-only text (see `ProofTarget.isEditable`) gets the reading actions only.
    var isEditable = true

    var isSelection: Bool { selection.length > 0 }

    /// What the action runs on.
    var subject: String {
        isSelection ? (text as NSString).substring(with: selection) : text
    }

    /// The subject's place in `text` (value offsets).
    var subjectRange: NSRange {
        isSelection ? selection : NSRange(location: 0, length: (text as NSString).length)
    }

    /// The range to select before pasting the result, in the app's own offsets.
    var appRange: NSRange {
        offsetMap?.appRange(subjectRange) ?? subjectRange
    }
}
