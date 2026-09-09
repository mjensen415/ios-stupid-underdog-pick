import SwiftUI

/// One selectable contest in the switcher -- purely presentational, built by
/// whichever screen presents the sheet (Home has the richest data: real
/// per-sport context/pick state; Games only knows its own sport toggle plus
/// a static Pickems option). Selecting a card runs `action` and dismisses.
struct SwitchGameOption: Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let statusText: String?
  let statusColor: Color
  let accent: Color
  let isCurrent: Bool
  let action: () -> Void
}

/// Replaces the old CFB/Pro Ball pill toggle, which flipped a small header
/// label and re-scoped a couple of Home's own widgets but didn't actually
/// take you anywhere -- confusing since CFB Underdog, Pro Ball Underdog, and
/// Pickems are genuinely separate contests (different groups, different
/// picks, and for Pickems a different scoring mechanic entirely), not one
/// screen with a filter. This sheet makes switching an explicit, one-tap
/// jump into the chosen contest instead.
struct SwitchGameSheet: View {
  let options: [SwitchGameOption]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          ForEach(options) { option in
            Button {
              option.action()
              dismiss()
            } label: {
              card(for: option)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(16)
      }
      .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
      .navigationTitle("Switch Game")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
  }

  private func card(for option: SwitchGameOption) -> some View {
    HStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 10)
        .fill(option.accent.opacity(0.14))
        .frame(width: 44, height: 44)
        .overlay {
          Image(systemName: "sportscourt.fill")
            .foregroundColor(option.accent)
        }

      VStack(alignment: .leading, spacing: 3) {
        Text(option.title)
          .font(BoldTheme.Fonts.body(15, weight: .heavy))
          .foregroundColor(BoldTheme.Colors.text)
        Text(option.subtitle)
          .font(BoldTheme.Fonts.mono(10.5))
          .foregroundColor(BoldTheme.Colors.textDim)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 6) {
        if option.isCurrent {
          Text("CURRENT")
            .font(BoldTheme.Fonts.mono(9, weight: .semibold))
            .foregroundColor(option.accent)
        }
        if let statusText = option.statusText {
          Text(statusText)
            .font(BoldTheme.Fonts.body(11, weight: .bold))
            .foregroundColor(option.statusColor)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(option.statusColor.opacity(0.13))
            .clipShape(Capsule())
        }
      }
    }
    .padding(14)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(option.isCurrent ? option.accent.opacity(0.45) : BoldTheme.Colors.border, lineWidth: option.isCurrent ? 1.5 : 1)
    )
    .cornerRadius(16)
  }
}
