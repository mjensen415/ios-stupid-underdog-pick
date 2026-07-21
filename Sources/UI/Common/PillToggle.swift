import SwiftUI

// Capsule pill selector -- extracted from SeasonLeaderboardView's inline
// season-pill styling (the only place this pattern lived before Groups
// needed it a second and third time: leaderboard scope, join-mode).
struct PillToggle<T: Hashable>: View {
  let options: [(label: String, value: T)]
  @Binding var selection: T
  var scrollable = false

  var body: some View {
    let content = HStack(spacing: 8) {
      ForEach(options, id: \.value) { option in
        let active = option.value == selection
        Button {
          selection = option.value
        } label: {
          Text(option.label)
            .font(BoldTheme.Fonts.body(13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // GREEN, not gold -- PillToggle can appear more than once on the
            // same screen at once (e.g. GroupDetailView's tab selector +
            // leaderboard-scope selector simultaneously), so its active
            // state can't be gold without competing with the screen's one
            // true primary-action CTA.
            .background(active ? BoldTheme.Colors.green : BoldTheme.Colors.text.opacity(0.07))
            .foregroundColor(active ? BoldTheme.Colors.bgPage : BoldTheme.Colors.textDim)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }

    if scrollable {
      ScrollView(.horizontal, showsIndicators: false) { content }
    } else {
      content
    }
  }
}
