import Foundation

/// In-app rendering model for the user FAQ. The single source of truth is `FAQ.md` at the
/// repository root, copied into the app bundle so the document users read on GitHub and the one
/// shown in the popover can never drift apart.
///
/// The parser accepts only the constrained Markdown subset the document uses — `##` sections,
/// `**Q: …**` entries, paragraphs, `-` / `1.` list items, and fenced code blocks — so the view
/// never needs a general-purpose renderer. Inline spans (`` `code` ``, bold) are left in the block
/// text and rendered by the view.
struct FAQContent: Equatable {
  /// Document preamble, shown under the window title as a one-line framing before the questions.
  var intro: String?
  var sections: [Section]

  struct Section: Equatable {
    var title: String
    var entries: [Entry]
  }

  struct Entry: Equatable {
    var question: String
    var blocks: [Block]
  }

  enum Block: Equatable {
    case paragraph(String)
    case bullet(String)
    case numbered(Int, String)
    case code(String)
  }

  /// Loads and parses the FAQ shipped in the same bundle as the compiled code: the app bundle in
  /// the app, the test bundle in unit tests. A missing or unparsable document yields nil rather
  /// than a silently empty page.
  static func load(bundle: Bundle = Bundle(for: BundleToken.self)) -> FAQContent? {
    guard let url = bundle.url(forResource: "FAQ", withExtension: "md"),
          let markdown = try? String(contentsOf: url, encoding: .utf8) else {
      return nil
    }
    let content = FAQContentParser.parse(markdown)
    return content.sections.isEmpty ? nil : content
  }
}

/// Anchor for bundle lookup: this class is compiled wherever the FAQ sources are, which is also
/// the bundle that receives the FAQ resource.
private final class BundleToken {}

/// Parser for the FAQ's constrained Markdown subset. Paragraphs before the first `##` section
/// become the document intro; content before the first `**Q: …**` of a section is skipped.
enum FAQContentParser {
  static func parse(_ markdown: String) -> FAQContent {
    var intro: String?
    var sections: [FAQContent.Section] = []
    var sectionTitle: String?
    var entries: [FAQContent.Entry] = []
    var question: String?
    var blocks: [FAQContent.Block] = []
    var paragraphLines: [String] = []
    var codeLines: [String]?

    func flushParagraph() {
      guard !paragraphLines.isEmpty else {
        return
      }
      let paragraph = paragraphLines.joined(separator: "\n")
      if question != nil {
        blocks.append(.paragraph(paragraph))
      } else if sectionTitle == nil {
        // Preamble paragraphs form the intro; later ones extend it.
        intro = intro.map { $0 + "\n\n" + paragraph } ?? paragraph
      }
      paragraphLines = []
    }

    func flushCode() {
      guard let lines = codeLines else {
        return
      }
      if question != nil {
        blocks.append(.code(lines.joined(separator: "\n")))
      }
      codeLines = nil
    }

    func flushEntry() {
      flushParagraph()
      flushCode()
      guard let current = question else {
        blocks = []
        return
      }
      entries.append(FAQContent.Entry(question: current, blocks: blocks))
      question = nil
      blocks = []
    }

    func flushSection() {
      flushEntry()
      guard let title = sectionTitle else {
        entries = []
        return
      }
      sections.append(FAQContent.Section(title: title, entries: entries))
      sectionTitle = nil
      entries = []
    }

    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
      // Fenced code is verbatim: no blank-line or list handling inside.
      if codeLines != nil {
        if line.hasPrefix("```") {
          flushCode()
        } else {
          codeLines?.append(line)
        }
        continue
      }

      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        flushParagraph()
        codeLines = []
      } else if trimmed.hasPrefix("## ") {
        flushSection()
        sectionTitle = String(trimmed.dropFirst(3))
      } else if trimmed.hasPrefix("#") {
        flushParagraph()
      } else if trimmed.hasPrefix("**Q:") {
        flushEntry()
        var text = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("**") {
          text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        question = text
      } else if trimmed.hasPrefix("- ") {
        flushParagraph()
        if question != nil {
          blocks.append(.bullet(String(trimmed.dropFirst(2))))
        }
      } else if let (index, text) = numberedItem(trimmed) {
        flushParagraph()
        if question != nil {
          blocks.append(.numbered(index, text))
        }
      } else if trimmed.isEmpty {
        flushParagraph()
      } else {
        paragraphLines.append(trimmed)
      }
    }
    flushSection()
    return FAQContent(intro: intro, sections: sections)
  }

  /// Matches `1. text`-style items; the number must be a plain integer followed by `. `.
  private static func numberedItem(_ line: String) -> (Int, String)? {
    guard let dotIndex = line.firstIndex(of: "."),
          let index = Int(line[line.startIndex ..< dotIndex]),
          line.index(after: dotIndex) < line.endIndex,
          line[line.index(after: dotIndex)] == " " else {
      return nil
    }
    return (index, String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces))
  }
}
