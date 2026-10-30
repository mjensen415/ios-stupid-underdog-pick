import SwiftUI

// One CFB | Pro Ball | Pickems switcher used on Games/Pickems, My Picks and
// Groups, plus HOOPS | PUCKS while those flags are on (admins always). Bound
// to appState.currentGame, so switching on any screen carries over to the
// others. Hoops/Pucks are separate products with their own groups: picking
// one opens its page on the Games tab (appState.hpSport) instead of changing
// currentGame -- same as the web's GameSwitcher. No "BETA" labels on iOS
// (App Store rejected those in Aug 2026).
struct GameSwitcher: View {
  @EnvironmentObject private var appState: AppState
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  /// Set on the Hoops/Pucks page so its tab shows as selected.
  var activeHp: HpSport? = nil

  private let options: [(CurrentGame, String)] = [(.cfb, "CFB"), (.nfl, "Pro Ball"), (.pickems, "Pickems")]

  private var hpOptions: [HpSport] {
    HpSport.allCases.filter { featureFlags.isVisible($0.flag) }
  }

  var body: some View {
    let compact = !hpOptions.isEmpty
    HStack(spacing: 4) {
      ForEach(options, id: \.0) { game, label in
        let active = activeHp == nil && appState.currentGame == game
        segment(label: label, active: active, compact: compact) {
          withAnimation(.easeInOut(duration: 0.2)) {
            appState.hpSport = nil
            appState.currentGame = game
          }
        }
      }
      ForEach(hpOptions) { sport in
        segment(label: sport.name, active: activeHp == sport, compact: compact) {
          appState.goToHoopsPucks(sport)
        }
      }
    }
    // Segmented control, not a yellow button: yellow is for the screen's
    // one primary action (de-slop #5). Selected = white pill, ink text.
    .padding(4)
    .background(Capsule().fill(BoldTheme.Colors.track))
  }

  private func segment(label: String, active: Bool, compact: Bool, action: @escaping () -> Void) -> some View {
    Button {
      guard !active else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      action()
    } label: {
      Text(label)
        .font(BoldTheme.Fonts.body(compact ? 13 : 14, weight: active ? .bold : .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Capsule().fill(active ? BoldTheme.Colors.card : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}
