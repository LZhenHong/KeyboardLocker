import SwiftUI

/// Renders the markdown emphasis spans the FAQ prose carries into colored highlights, in two
/// tiers:
///
/// - `**strong**` — the key phrase or the action to take: accent color.
/// - `*emphasis*` — a caveat, limit, or gotcha: warning orange, bold.
///
/// An actionable phrase and a "but watch out" clause must not read as the same kind of statement,
/// which is what the two tiers earn. Italic is deliberately swapped for bold by rewriting the
/// presentation *intent* rather than assigning a concrete font: SwiftUI resolves the intent
/// against the container's font, so a caveat inside `.callout` prose keeps its callout size.
/// A markdown parse failure falls back to the plain string, so a malformed span degrades to
/// unstyled prose instead of showing `*` markers literally.
enum ProseHighlight {
  static func attributed(_ markdown: String) -> AttributedString {
    guard var attributed = try? AttributedString(
      markdown: markdown,
      options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else {
      return AttributedString(markdown)
    }
    for run in attributed.runs {
      guard let intent = run.inlinePresentationIntent else {
        continue
      }
      if intent.contains(.stronglyEmphasized) {
        attributed[run.range].foregroundColor = .accentColor
      } else if intent.contains(.emphasized) {
        attributed[run.range].foregroundColor = .orange
        attributed[run.range].inlinePresentationIntent = .stronglyEmphasized
      }
    }
    return attributed
  }
}
