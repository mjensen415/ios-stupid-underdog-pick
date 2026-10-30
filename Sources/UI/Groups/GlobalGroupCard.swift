import SwiftUI

// "Global · everyone": the catch-all group every player is already in.
// For CFB / Pro Ball / Pickems it's the site-wide standings (picks without a
// group count there), so there's nothing to join: the card opens that game's
// global board. Port of the web's components/groups/GlobalGroupCard.tsx.
// See Core/GlobalGroups.swift.

private struct GlobalBadge: View {
  var body: some View {
    // Gray, not yellow: yellow is for your next action only (de-slop #5).
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(BoldTheme.Colors.track)
      .frame(width: 42, height: 42)
      .overlay(Image(systemName: "globe").font(.system(size: 19, weight: .semibold)).foregroundColor(BoldTheme.Colors.text))
      .accessibilityHidden(true)
  }
}

/// One game's Global group (Groups tab, top of the list).
struct GlobalGroupCard: View {
  let game: CurrentGame

  var body: some View {
    NavigationLink(destination: GlobalBoardView(game: game)) {
      HStack(spacing: 14) {
        GlobalBadge()
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 8) {
            Text(GlobalGroups.title)
              .font(BoldTheme.Fonts.display(20))
              .foregroundColor(BoldTheme.Colors.text)
            Text(GlobalGroups.label(game).uppercased())
              .font(BoldTheme.Fonts.mono(9.5, weight: .bold))
              .tracking(0.8)
              .foregroundColor(BoldTheme.Colors.green)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          Text(GlobalGroups.tagline)
            .font(BoldTheme.Fonts.body(12.5))
            .foregroundColor(BoldTheme.Colors.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(BoldTheme.Colors.textFaint)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(BoldTheme.Colors.glassStrong)
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.green.opacity(0.35), lineWidth: 1.5))
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Global \(GlobalGroups.label(game)) leaderboard")
    .accessibilityIdentifier("globalGroupCard")
  }
}

/// Every game's Global group in one row (Home's groups list). CFB / Pro Ball
/// / Pickems open the global board; Hoops / Pucks open their page, which
/// lands on the global league.
struct GlobalGroupsRow: View {
  @EnvironmentObject private var appState: AppState
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  /// Pushes the global board for a game (Home owns the navigation stack).
  let openBoard: (CurrentGame) -> Void

  private var hpSports: [HpSport] { HpSport.allCases.filter { featureFlags.isVisible($0.flag) } }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 14) {
        GlobalBadge()
        VStack(alignment: .leading, spacing: 2) {
          Text(GlobalGroups.title)
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
          Text(GlobalGroups.tagline)
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          chip("CFB") { openBoard(.cfb) }
          chip("Pro Ball") { openBoard(.nfl) }
          chip("Pickems") { openBoard(.pickems) }
          ForEach(hpSports) { s in
            chip(s.name) { appState.goToHoopsPucks(s) }
          }
        }
      }
    }
    .padding(BoldTheme.Space.cardPad)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private func chip(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label)
        .font(BoldTheme.Fonts.body(13, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.text)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(BoldTheme.Colors.track))
    }
    .buttonStyle(.plain)
  }
}

/// A game's global standings, pushed from a Global card. No NavigationStack
/// of its own (it's always pushed onto one).
struct GlobalBoardView: View {
  let game: CurrentGame
  @Environment(\.supabaseClient) private var client
  @State private var selection = 0 // 0 weekly, 1 season
  @State private var pickemsSeason: Int?
  @State private var pickemsWeek: Int?
  @State private var pickemsLastGame: PickemsGameRow?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(GlobalGroups.label(game).uppercased())
          .font(BoldTheme.Fonts.mono(10, weight: .semibold))
          .tracking(1)
          .foregroundColor(BoldTheme.Colors.green)
        Text(GlobalGroups.tagline)
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.top, 8)

      if game == .pickems {
        ScrollView {
          PickemsStandingsView(season: pickemsSeason, week: pickemsWeek, lastGame: pickemsLastGame, globalOnly: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .task { await loadPickemsContext() }
      } else {
        Picker("Mode", selection: $selection) {
          Text("Weekly").tag(0)
          Text("Season").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)

        if selection == 0 {
          WeeklyLeaderboardView(sport: game.rawValue, groupSlug: nil)
        } else {
          SeasonLeaderboardView(sport: game.rawValue, groupSlug: nil)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .navigationTitle(GlobalGroups.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbarBackground(BoldTheme.Colors.bgPage, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarColorScheme(.light, for: .navigationBar)
  }

  private func loadPickemsContext() async {
    guard let client, pickemsSeason == nil else { return }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: "nfl")
      pickemsSeason = ctx.season
      pickemsWeek = ctx.week
      let games = try await PickemsService(client: client).fetchGames(season: ctx.season, week: ctx.week)
      pickemsLastGame = games.max(by: { $0.startTime < $1.startTime })
    } catch {
      // Tiebreaker line just won't show; standings still need a season.
    }
  }
}
