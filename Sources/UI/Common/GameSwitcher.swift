import SwiftUI

// One CFB | PRO BALL | PICKEMS switcher used on Home, Games/Pickems,
// My Picks and Groups. Bound to appState.currentGame, so switching on any
// screen carries over to the others.
struct GameSwitcher: View {
  @EnvironmentObject private var appState: AppState

  private let options: [(CurrentGame, String)] = [(.cfb, "CFB"), (.nfl, "PRO BALL"), (.pickems, "PICKEMS")]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(options, id: \.0) { game, label in
        let active = appState.currentGame == game
        Button {
          guard !active else { return }
          UISelectionFeedbackGenerator().selectionChanged()
          withAnimation(.easeInOut(duration: 0.2)) { appState.currentGame = game }
        } label: {
          Text(label)
            .font(BoldTheme.Fonts.body(13, weight: .bold))
            .tracking(0.4)
            .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
              RoundedRectangle(cornerRadius: 11)
                .fill(active ? (game == .pickems ? BoldTheme.Colors.pickemsAccent.opacity(0.18) : BoldTheme.Colors.gold) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
      }
    }
    .padding(4)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}
