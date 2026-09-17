import SwiftUI

/// Content of the standalone FAQ window: renders the bundled `FAQ.md` parsed by `FAQContent`.
///
/// The view is presentation-only and holds no state of its own: the document is a static bundle
/// resource loaded once when the window is created, and a load failure is shown honestly rather
/// than replaced with an empty list. It deliberately does not pin its own size — it fills
/// whatever container `FAQWindowPresenter` gives it. Each entry is a disclosure row: the question
/// stays visible, the answer folds away underneath, so 20+ entries scan as a flat list.
struct FAQView: View {
  /// Seeds every row's disclosure state; production leaves rows collapsed, while previews and
  /// the render-verification harness expand them to inspect answers.
  let initiallyExpanded: Bool

  init(initiallyExpanded: Bool = false) {
    self.initiallyExpanded = initiallyExpanded
  }

  private let content = FAQContent.load()

  var body: some View {
    ScrollView {
      if let content {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Frequently Asked Questions")
              .font(.title)
              .fontWeight(.semibold)
            if let intro = content.intro {
              Text(ProseHighlight.attributed(intro))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          Divider()

          VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(content.sections.enumerated()), id: \.offset) { _, section in
              sectionView(section)
            }
          }
        }
        .padding(32)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity)
      } else {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("FAQ is unavailable")
            Text("The bundled FAQ document is missing or unreadable.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Sections

  private func sectionView(_ section: FAQContent.Section) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(section.title)
        .font(.caption.weight(.medium))
        .textCase(.uppercase)
        .foregroundColor(.secondary)

      ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
        FAQRowView(entry: entry, initiallyExpanded: initiallyExpanded)
      }
    }
  }
}

/// One question-and-answer entry, rendered as a disclosure row: the question stays visible and
/// the answer folds away underneath.
private struct FAQRowView: View {
  let entry: FAQContent.Entry

  @State private var expanded: Bool

  init(entry: FAQContent.Entry, initiallyExpanded: Bool) {
    self.entry = entry
    _expanded = State(initialValue: initiallyExpanded)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
          blockView(block)
        }
      }
      .padding(.top, 6)
      .padding(.leading, 2)
    } label: {
      Text(entry.question)
        .font(.headline)
    }
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func blockView(_ block: FAQContent.Block) -> some View {
    switch block {
    case let .paragraph(text):
      inlineText(text)

    case let .bullet(text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•")
          .font(.callout)
          .foregroundColor(.secondary)
        inlineText(text)
      }

    case let .numbered(index, text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("\(index).")
          .font(.callout)
          .foregroundColor(.secondary)
          .monospacedDigit()
        inlineText(text)
      }

    case let .code(code):
      ScrollView(.horizontal) {
        Text(code)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .padding(8)
      }
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
      )
    }
  }

  /// Answer text carries only inline spans (`code`, `**strong**`, `*emphasis*`); block structure
  /// was parsed upstream.
  private func inlineText(_ markdown: String) -> some View {
    Text(ProseHighlight.attributed(markdown))
      .font(.callout)
      .foregroundColor(.secondary)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
