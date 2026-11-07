import AVFoundation
import CoreGraphics
import Foundation

func runUITests() {
    print("PanelWidth")
    check(PanelWidth.fitting(["Ok"]) == 380, "a short text gets the narrowest window")
    check(PanelWidth.fitting([String(repeating: "word ", count: 80)]) == 560, "a long line gets the widest")
    let middle = PanelWidth.fitting([String(repeating: "x", count: 64)])
    check(middle > 380 && middle < 560, "in between follows the text (\(middle))")
    check(PanelWidth.fitting(["short\n" + String(repeating: "x", count: 64)]) == middle,
          "several lines: the longest one counts")
    check(PanelWidth.fitting(["Ok"], font: .systemFont(ofSize: 13)) == PanelWidth.fitting([""]), "empty is the narrowest too")

    print("ResultMarkdown")
    check(ResultMarkdown.plain("**Что это говорит**") == "Что это говорит", "bold loses its asterisks")
    check(ResultMarkdown.plain("## Итог\nтекст") == "Итог\nтекст", "a heading becomes its title")
    check(ResultMarkdown.plain("- один\n- два") == "- один\n- два", "list lines and line breaks stay")
    check(ResultMarkdown.plain("2 * 3 = 6") == "2 * 3 = 6", "a lone asterisk is text")
    check(ResultMarkdown.render("**a** b").runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true },
          "bold is styled")

    print("PopupTilePacker")
    check(PopupTilePacker.topRowCount(widths: [], spacing: 4, maxContent: 100) == 0, "no items: no first row")
    check(PopupTilePacker.topRowCount(widths: [50], spacing: 4, maxContent: 10) == 1,
          "a single item keeps its row even when it does not fit")
    check(PopupTilePacker.topRowCount(widths: [30, 30, 30], spacing: 4, maxContent: 500) == 3,
          "everything that fits stays on the first row")
    check(PopupTilePacker.topRowCount(widths: [30, 30, 30], spacing: 4, maxContent: 64) == 2,
          "packing stops at the item that would overflow")
    // 30 + 4 + 30 = 64 exactly: the boundary belongs to the first row.
    check(PopupTilePacker.topRowCount(widths: [30, 30], spacing: 4, maxContent: 64) == 2,
          "an item that fits exactly stays on the first row")
    check(PopupTilePacker.topRowCount(widths: [30, 30], spacing: 4, maxContent: 63) == 1,
          "the spacing counts towards the width")
    check(PopupTilePacker.topRowCount(widths: [500, 20], spacing: 4, maxContent: 100) == 1,
          "an over-wide first item does not drag the next one along")

    print("PopupLayout tile grid")
    check(PopupLayout.tileColumns(forCount: 1) == 1, "one item: one column")
    check(PopupLayout.tileColumns(forCount: 2) == 1, "two items: one column")
    check(PopupLayout.tileColumns(forCount: 3) == 2, "three items: two columns")
    check(PopupLayout.tileColumns(forCount: 5) == 3, "five items: three columns")
    check(PopupLayout.tileColumns(forCount: 6) == 3, "six items: three columns")
    // Horizontal movement walks row-major order and wraps.
    check(PopupLayout.tileIndex(from: 0, deltaX: 1, deltaY: 0, count: 5) == 1, "tile right")
    check(PopupLayout.tileIndex(from: 2, deltaX: 1, deltaY: 0, count: 5) == 3, "tile right crosses rows")
    check(PopupLayout.tileIndex(from: 4, deltaX: 1, deltaY: 0, count: 5) == 0, "tile right wraps")
    check(PopupLayout.tileIndex(from: 0, deltaX: -1, deltaY: 0, count: 5) == 4, "tile left wraps")
    // Vertical movement steps a whole row and clamps at the ends.
    check(PopupLayout.tileIndex(from: 0, deltaX: 0, deltaY: 1, count: 5) == 3, "tile down row 0 -> row 1")
    check(PopupLayout.tileIndex(from: 1, deltaX: 0, deltaY: 1, count: 5) == 4, "tile down col 2")
    check(PopupLayout.tileIndex(from: 2, deltaX: 0, deltaY: 1, count: 5) == 4, "tile down clamps at the end")
    check(PopupLayout.tileIndex(from: 3, deltaX: 0, deltaY: -1, count: 5) == 0, "tile up row 1 -> row 0")
    check(PopupLayout.tileIndex(from: 4, deltaX: 0, deltaY: -1, count: 5) == 1, "tile up col 2")
    check(PopupLayout.tileIndex(from: 0, deltaX: 0, deltaY: -1, count: 5) == 0, "tile up clamps at the start")
    check(PopupLayout.tileIndex(from: 3, deltaX: 1, deltaY: 0, count: 2) == 0, "tile wraps in a one-column grid")
    // A width-measured first row changes the vertical jump, not the horizontal walk.
    check(PopupLayout.tileIndex(from: 0, deltaX: 0, deltaY: 1, count: 6, topRowCount: 4) == 4,
          "measured top row: down lands under the same column")
    check(PopupLayout.tileIndex(from: 1, deltaX: 0, deltaY: 1, count: 6, topRowCount: 4) == 5,
          "measured top row: down col 2")
    check(PopupLayout.tileIndex(from: 2, deltaX: 0, deltaY: 1, count: 6, topRowCount: 4) == 5,
          "measured top row: down clamps when the second row is shorter")
    check(PopupLayout.tileIndex(from: 5, deltaX: 0, deltaY: -1, count: 6, topRowCount: 4) == 1,
          "measured top row: up col 2")
    check(PopupLayout.tileIndex(from: 4, deltaX: 1, deltaY: 0, count: 6, topRowCount: 4) == 5,
          "measured top row: horizontal walk unchanged")
    check(PopupLayout.tileIndex(from: 5, deltaX: 1, deltaY: 0, count: 6, topRowCount: 4) == 0,
          "measured top row: horizontal wraps")
    check(PopupLayout.tileIndex(from: 0, deltaX: 0, deltaY: 1, count: 6) == 3,
          "default topRowCount keeps the even split")
    // Everything measured onto one row: there is no second row to move to.
    check(PopupLayout.tileIndex(from: 1, deltaX: 0, deltaY: 1, count: 4, topRowCount: 4) == 1,
          "one full row: down does nothing")
    check(PopupLayout.tileIndex(from: 2, deltaX: 0, deltaY: -1, count: 4, topRowCount: 4) == 2,
          "one full row: up does nothing")
    check(PopupLayout.tileIndex(from: 1, deltaX: 0, deltaY: 1, count: 4, topRowCount: 9) == 1,
          "a topRowCount past the end is treated as one full row")
    check(PopupLayout.tileIndex(from: 1, deltaX: 1, deltaY: 0, count: 4, topRowCount: 4) == 2,
          "one full row still walks horizontally")
    check(PopupLayout.tileIndex(from: 0, deltaX: 0, deltaY: 1, count: 3, topRowCount: 1) == 1,
          "a one-item first row steps down item by item")
    check(PopupLayout.tileIndex(from: 0, deltaX: 0, deltaY: 1, count: 1) == 0, "a lone item stays put")

    print("TranslationLayout")
    eq(TranslationLayout.restore(source: "Привет!\nКак\nдела?", translation: "Hello!\n\nHow\n\nthings?"),
       "Hello!\nHow\nthings?", "the model's blank lines become the source's single breaks")
    eq(TranslationLayout.restore(source: "Один.\n\nДва.\nТри.", translation: "One.\n\nTwo.\n\nThree."),
       "One.\n\nTwo.\nThree.", "each break takes the source's own run")
    eq(TranslationLayout.restore(source: "А.\nБ.\nВ.", translation: "A. B.\n\nC."),
       "A. B.\nC.", "a merged paragraph caps runs at the source's longest")
    eq(TranslationLayout.restore(source: "Одна строка", translation: "One line\n"), "One line",
       "a trailing newline from the model is dropped")
    eq(TranslationLayout.restore(source: "Без переносов", translation: "No breaks"), "No breaks", "no breaks, nothing to do")

    print("OCRParagraphs")
    func ocrLine(_ text: String, x: CGFloat = 0.1, top: CGFloat, height: CGFloat = 0.04) -> OCRParagraphs.Line {
        OCRParagraphs.Line(text: text, box: CGRect(x: x, y: top - height, width: 0.6, height: height))
    }
    eq(OCRParagraphs.join([ocrLine("содержит только json, папки", top: 0.9),
                           ocrLine("LanguageTool нет.", top: 0.85)]),
       "содержит только json, папки LanguageTool нет.", "a wrapped line joins its paragraph")
    eq(OCRParagraphs.join([ocrLine("Первый абзац.", top: 0.9), ocrLine("Второй абзац.", top: 0.78)]),
       "Первый абзац.\nВторой абзац.", "a wide gap starts a new paragraph")
    eq(OCRParagraphs.join([ocrLine("Заголовок", top: 0.9), ocrLine("Отступ", x: 0.3, top: 0.85)]),
       "Заголовок\nОтступ", "a jump in the left edge starts a new paragraph")
    eq(OCRParagraphs.join([ocrLine("автодопол-", top: 0.9), ocrLine("нения тесты", top: 0.85)]),
       "автодополнения тесты", "a hyphenated wrap is rejoined")
    eq(OCRParagraphs.join([ocrLine("Москва -", top: 0.9), ocrLine("Питер", top: 0.85)]),
       "Москва - Питер", "a dash before a capital is kept")

    print("StatusIconTwinkle")
    do {
        let all = stride(from: 0.0, to: 2.0, by: 0.01).flatMap { StatusIconTwinkle.frames(at: $0) }
        check(all.allSatisfy { $0.alpha >= StatusIconTwinkle.dim - 1e-9 && $0.alpha <= 1 + 1e-9 }, "alphas stay between dim and full")
        check(all.allSatisfy { $0.scale >= 1 - 1e-9 && $0.scale <= 1.35 + 1e-9 }, "scales stay between idle and peak")
        let first = StatusIconTwinkle.frames(at: 0)
        check(abs(first[0].alpha - 1) < 1e-9 && first[0].scale > 1.09, "the first frame already has the big sparkle lit")
        check(first[1].alpha < 0.5 && first[2].alpha < 0.5, "and the small ones dim")
        let second = StatusIconTwinkle.frames(at: StatusIconTwinkle.stagger)
        check(abs(second[1].alpha - 1) < 1e-9 && second[0].alpha < 1, "the next one peaks a stagger later")
        let third = StatusIconTwinkle.frames(at: 2 * StatusIconTwinkle.stagger)
        check(abs(third[2].alpha - 1) < 1e-9, "then the last")
        check(zip(StatusIconTwinkle.frames(at: 0.3), StatusIconTwinkle.frames(at: 0.3 + StatusIconTwinkle.period))
            .allSatisfy { abs($0.alpha - $1.alpha) < 1e-6 && abs($0.scale - $1.scale) < 1e-6 }, "it repeats every period")
        check(StatusIconTwinkle.stopTime(endedAt: 0.2) == 2 * StatusIconTwinkle.period, "a quick action still plays two rounds")
        check(StatusIconTwinkle.stopTime(endedAt: 2.4) == 3 * StatusIconTwinkle.period, "a longer one ends at the end of its round")
    }

    print("PanelPlacement")
    do {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 400, height: 200)
        let low = PanelPlacement.origin(size: size, near: CGRect(x: 100, y: 500, width: 300, height: 30), window: nil, visible: visible)
        check(low == NSPoint(x: 100, y: 500 - PanelPlacement.gap - 200), "under the field when there is room")
        let high = PanelPlacement.origin(size: size, near: CGRect(x: 100, y: 100, width: 300, height: 30), window: nil, visible: visible)
        check(high == NSPoint(x: 100, y: 130 + PanelPlacement.gap), "above it when there is not")
        let tall = NSSize(width: 400, height: 500)
        let window = CGRect(x: 200, y: 100, width: 600, height: 600)
        let middle = PanelPlacement.origin(size: tall, near: CGRect(x: 100, y: 380, width: 300, height: 30), window: window, visible: visible)
        check(middle == NSPoint(x: 300, y: 150), "centered on the app's window when neither fits")
        let right = PanelPlacement.origin(size: size, near: CGRect(x: 900, y: 500, width: 80, height: 30), window: nil, visible: visible)
        check(right.x == 1000 - 400 - PanelPlacement.inset, "kept inside the right edge")
        let left = PanelPlacement.origin(size: size, near: CGRect(x: -50, y: 500, width: 80, height: 30), window: nil, visible: visible)
        check(left.x == PanelPlacement.inset, "and the left one")
    }
}
