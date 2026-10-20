import SwiftUI

// One CFB | PRO BALL | PICKEMS switcher used on Games/Pickems, My Picks and
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

  private let options: [(CurrentGame, String)] = [(.cfb, "CFB"), (.nfl, "PRO BALL"), (.pickems, "PICKEMS")]

  private var hpOptions: [HpSport] {
    HpSport.allCases.filter { featureFlags.isVisible($0.flag) }
  }

  var body: some View {
    let compact = !hpOptions.isEmpty
    HStack(spacing: 4) {
      ForEach(options, id: \.0) { game, label in
        let active = activeHp == nil && appState.currentGame == game
        segment(label: label, active: active, compact: compact,
                fill: game == .pickems ? BoldTheme.Colors.pickemsAccent.opacity(0.18) : BoldTheme.Colors.gold) {
          withAnimation(.easeInOut(duration: 0.2)) {
            appState.hpSport = nil
            appState.currentGame = game
          }
        }
      }
      ForEach(hpOptions) { sport in
        segment(label: sport.name.uppercased(), active: activeHp == sport, compact: compact, fill: BoldTheme.Colors.gold) {
          appState.goToHoopsPucks(sport)
        }
      }
    }
    .padding(4)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func segment(label: String, active: Bool, compact: Bool, fill: Color, action: @escaping () -> Void) -> some View {
    Button {
      guard !active else { return }
      UISelectionFeedbackGenerator().selectionChanged()
      action()
    } label: {
      Text(label)
        .font(BoldTheme.Fonts.body(compact ? 11.5 : 13, weight: .bold))
        .tracking(compact ? 0.2 : 0.4)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 11).fill(active ? fill : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}
