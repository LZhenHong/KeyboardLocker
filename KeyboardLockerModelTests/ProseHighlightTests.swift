import SwiftUI
import Testing

struct ProseHighlightTests {
  @Test
  func strongSpansRenderAccentColor() {
    let attributed = ProseHighlight.attributed("before **key phrase** after")

    let strong = run("key phrase", in: attributed)
    #expect(strong?.foregroundColor == .accentColor)
    #expect(run("before ", in: attributed)?.foregroundColor == nil)
    #expect(run(" after", in: attributed)?.foregroundColor == nil)
  }

  @Test
  func emphasisSpansRenderOrangeAndBoldInsteadOfItalic() {
    let attributed = ProseHighlight.attributed("note *watch out* here")

    let emphasis = run("watch out", in: attributed)
    #expect(emphasis?.foregroundColor == .orange)
    #expect(emphasis?.inlinePresentationIntent == .stronglyEmphasized)
  }

  @Test
  func codeSpansKeepTheirPlainContainerColor() {
    let attributed = ProseHighlight.attributed("run `klock unlock` now")

    let code = run("klock unlock", in: attributed)
    #expect(code?.foregroundColor == nil)
    #expect(code?.inlinePresentationIntent?.contains(.code) == true)
  }

  @Test
  func strayMarkersDegradeToUnstyledProse() {
    let attributed = ProseHighlight.attributed("a ** b")

    #expect(String(attributed.characters) == "a ** b")
    #expect(attributed.runs.allSatisfy { $0.foregroundColor == nil })
  }

  private func run(
    _ text: String,
    in attributed: AttributedString
  ) -> AttributedString.Runs.Run? {
    attributed.runs.first { String(attributed[$0.range].characters) == text }
  }
}
