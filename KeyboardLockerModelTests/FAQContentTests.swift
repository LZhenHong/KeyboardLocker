import Foundation
import Testing

struct FAQContentTests {
  @Test
  func parsesSectionsEntriesAndBlockKinds() {
    let markdown = """
      # Document Title

      Intro paragraph that is not rendered.

      ## First Section

      **Q: First question?**

      Answer paragraph with `inline code` and a second line.

      - bullet one
      - bullet two

      1. step one
      2. step two

      ```bash
      klock lock
      klock status --json
      ```

      **Q: Second question?**

      ## Second Section

      **Q: Third question?**

      Another answer.
      """

      let content = FAQContentParser.parse(markdown)

      #expect(content.sections.count == 2)
      #expect(content.sections[0].title == "First Section")
      #expect(content.sections[1].title == "Second Section")

      let entries = content.sections[0].entries
      #expect(entries.count == 2)
      #expect(entries[0].question == "First question?")
      #expect(entries[0].blocks == [
        .paragraph("Answer paragraph with `inline code` and a second line."),
        .bullet("bullet one"),
        .bullet("bullet two"),
        .numbered(1, "step one"),
        .numbered(2, "step two"),
        .code("klock lock\nklock status --json"),
      ])
      // A question with no answer blocks is still an entry.
      #expect(entries[1] == FAQContent.Entry(question: "Second question?", blocks: []))

      #expect(content.sections[1].entries == [
        FAQContent.Entry(question: "Third question?", blocks: [.paragraph("Another answer.")]),
      ])
  }

  @Test
  func topicHeadingsBecomeEntries() {
    let markdown = """
      ## Section

      ### First topic

      Body text.

      ### Second topic

      More text.
      """

      let content = FAQContentParser.parse(markdown)

      #expect(content.sections.count == 1)
      #expect(content.sections[0].entries == [
        FAQContent.Entry(question: "First topic", blocks: [.paragraph("Body text.")]),
        FAQContent.Entry(question: "Second topic", blocks: [.paragraph("More text.")]),
      ])
  }

  @Test
  func numberedListRequiresPlainIntegerPrefix() {
    let markdown = """
      ## S

      **Q: q?**

      10. ten
      1.5 not an item
      x. not an item
      """

      let content = FAQContentParser.parse(markdown)

      #expect(content.sections[0].entries[0].blocks == [
        .numbered(10, "ten"),
        .paragraph("1.5 not an item\nx. not an item"),
      ])
  }

  @Test
  func loadReturnsNilWhenResourceIsMissing() {
    #expect(FAQContent.load(bundle: Bundle()) == nil)
  }

  /// Guard for the shipped document: the FAQ users see in the popover is the repository's
  /// `FAQ.md`, so a malformed edit must fail here rather than render as a half-empty page.
  @Test
  func shippedFAQDocumentParsesCompletely() throws {
    let content = try #require(FAQContent.load())

    #expect(content.intro?.isEmpty == false)
    #expect(content.sections.map(\.title) == [
      "Basics",
      "Unlock Gestures",
      "Timers",
      "Automation",
      "Widget & Control",
      "Feedback",
      "Troubleshooting",
    ])
    #expect(content.sections.reduce(0) { $0 + $1.entries.count } == 22)

    for section in content.sections {
      for entry in section.entries {
        #expect(!entry.question.isEmpty)
        #expect(!entry.blocks.isEmpty)
      }
    }

    // The document's own contracts the page relies on: a numbered unlock list, and fenced code.
    let allBlocks = content.sections.flatMap(\.entries).flatMap(\.blocks)
    #expect(allBlocks.contains { if case .numbered = $0 { return true }; return false })
    #expect(allBlocks.contains { if case .code = $0 { return true }; return false })
  }

  /// Guard for the shipped document: the Usage Guide users see in the app is the repository's
  /// `Usage.md`, so a malformed edit must fail here rather than render as a half-empty page.
  @Test
  func shippedUsageGuideDocumentParsesCompletely() throws {
    let content = try #require(FAQContent.load(resource: "Usage"))

    #expect(content.intro?.isEmpty == false)
    #expect(content.sections.map(\.title) == [
      "Getting Started",
      "Locking and Unlocking",
      "Timing",
      "While Locked",
      "Beyond the Menu Bar",
    ])
    #expect(content.sections.reduce(0) { $0 + $1.entries.count } == 9)

    for section in content.sections {
      for entry in section.entries {
        #expect(!entry.question.isEmpty)
        #expect(!entry.blocks.isEmpty)
      }
    }

    // The document's own contract the page relies on: numbered first-launch steps.
    let allBlocks = content.sections.flatMap(\.entries).flatMap(\.blocks)
    #expect(allBlocks.contains { if case .numbered = $0 { return true }; return false })
  }
}
