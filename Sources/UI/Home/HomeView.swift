import SwiftUI
import Supabase

// Mirrors src/pages/Home.tsx on web -- same sections, same corrected card
// model (picks have no group_id, so there's exactly one "this week's pick"
// status for the whole account, not one per contest/group).

private enum Sport: String { case cfb, nfl }

@MainActor
final class HomeViewModel: ObservableObject {
  @Published var isLoading = false
  /// False until the first load finishes -- Home shows a spinner instead of
  /// flashing the new-user "Get started" state and "WEEK 0".
  @Published var hasLoaded = false
  @Published var season: Int?
  @Published var week: Int?
  @Published var isOffseason = false
  @Published var myPick: Pick?
  @Published var nextOpenKickoff: Date?
  @Published var myRank: MyRank?
  @Published var myGroups: [MyGroup] = []
  @Published var discoverGroups: [DiscoverGroup] = []
  @Published var recap: [RecapHit] = []
  @Published var streak: Int = 0

  // Your Contests -- both sports' context/pick/kickoff independent of
  // whichever one the sportToggle currently shows, since a contest row can
  // be active for either (or both) regardless of what's on screen below.
  @Published var cfbContext: CurrentContext?
  @Published var nflContext: CurrentContext?
  @Published var myPickCfb: Pick?
  @Published var myPickNfl: Pick?
  @Published var nextOpenKickoffCfb: Date?
  @Published var nextOpenKickoffNfl: Date?
  /// Set once each sport's open-kickoff lookup has finished, so the
  /// contest row doesn't flash "Missed" while it's still loading.
  @Published var cfbWindowLoaded = false
  @Published var nflWindowLoaded = false
  @Published var cfbOffseason = false
  @Published var nflOffseason = false
  @Published var profile: ProfileRow?

  // "This week" row detail: the picked team for each Underdog sport, and
  // Pickems progress for the current NFL week.
  @Published var pickDetailCfb: HomePickDetail?
  @Published var pickDetailNfl: HomePickDetail?
  @Published var pickemsPicked = 0
  @Published var pickemsTotal = 0
  @Published var pickemsOpen = 0
  /// Open (not yet locked) games with no pick -- 0 means nothing left to do.
  @Published var pickemsOpenUnpicked = 0
  @Published var pickemsLoaded = false

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func load(userId: UUID, sport: String) async {
    guard let client else { return }
    isLoading = true
    defer { isLoading = false; hasLoaded = true }

    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: sport)
      season = ctx.season
      week = ctx.week

      struct CountRow: Decodable { let id: UUID }
      let gameCountRes = try await client
        .from("games")
        .select("id")
        .eq("season", value: ctx.season)
        .eq("sport", value: sport)
        .limit(1)
        .execute()
      let games = (try? JSONDecoder().decode([CountRow].self, from: gameCountRes.data)) ?? []
      isOffseason = games.isEmpty
    } catch {
      isOffseason = true
    }

    guard let season, let week, !isOffseason else { return }

    async let pickTask = try? PicksService(client: client).myPick(season: season, week: week, sport: sport)
    async let kickoffTask = fetchNextOpenKickoff(client: client, season: season, week: week, sport: sport)
    async let rankTask = try? LeaderboardService(client: client).fetchMyRank(userId: userId, season: season, sport: sport)
    async let groupsTask = try? GroupsService(client: client).fetchMyGroups()
    async let discoverTask = try? GroupsService(client: client).fetchDiscoverGroups(limit: 6)
    async let recapTask = fetchRecap(client: client, season: season, week: week, sport: sport)
    async let streakTask = try? LeaderboardService(client: client).fetchStreak(userId: userId, season: season, sport: sport)

    myPick = await pickTask ?? nil
    nextOpenKickoff = await kickoffTask
    myRank = await rankTask ?? nil
    myGroups = await groupsTask ?? []
    discoverGroups = await discoverTask ?? []
    recap = await recapTask
    streak = await streakTask ?? 0

    profile = try? await ProfilesService(client: client).fetchMyProfile()

    let cfbCtx = try? await ContextService(client: client).getCurrentContext(sport: "cfb")
    let nflCtx = try? await ContextService(client: client).getCurrentContext(sport: "nfl")
    cfbContext = cfbCtx
    nflContext = nflCtx
    if let cfbCtx {
      async let cfbPickTask = try? PicksService(client: client).myPick(season: cfbCtx.season, week: cfbCtx.week, sport: "cfb")
      async let cfbKickoffTask = fetchNextOpenKickoff(client: client, season: cfbCtx.season, week: cfbCtx.week, sport: "cfb")
      async let cfbOffseasonTask = checkOffseason(client: client, season: cfbCtx.season, sport: "cfb")
      myPickCfb = await cfbPickTask ?? nil
      nextOpenKickoffCfb = await cfbKickoffTask
      cfbWindowLoaded = true
      cfbOffseason = await cfbOffseasonTask
      pickDetailCfb = await fetchPickDetail(client: client, pick: myPickCfb)
    }
    if let nflCtx {
      async let nflPickTask = try? PicksService(client: client).myPick(season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      async let nflKickoffTask = fetchNextOpenKickoff(client: client, season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      async let nflOffseasonTask = checkOffseason(client: client, season: nflCtx.season, sport: "nfl")
      myPickNfl = await nflPickTask ?? nil
      nextOpenKickoffNfl = await nflKickoffTask
      nflWindowLoaded = true
      nflOffseason = await nflOffseasonTask
      pickDetailNfl = await fetchPickDetail(client: client, pick: myPickNfl)
      await loadPickemsProgress(client: client, userId: userId, season: nflCtx.season, week: nflCtx.week)
    }
  }

  /// The picked game + team logo, for the "This week" row. The logo comes
  /// from the same v_games_named row (home/away_logo_url) -- a separate
  /// teams lookup was intermittently coming back empty.
  private func fetchPickDetail(client: SupabaseClient, pick: Pick?) async -> HomePickDetail? {
    guard let pick else { return nil }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    guard let res = try? await client
      .from("v_games_named")
      .select("id, season, week, status, home_name, away_name, home_team_id, away_team_id, favorite_team_id, start_time, betting_line, latest_spread, picks_locked, home_points, away_points, sport, home_logo_url, away_logo_url")
      .eq("id", value: pick.game_id)
      .limit(1)
      .execute(),
      let game = try? dec.decode([Game].self, from: res.data).first
    else { return nil }
    struct Logos: Decodable { let home_logo_url: String?; let away_logo_url: String? }
    let logos = try? JSONDecoder().decode([Logos].self, from: res.data).first
    let logo = pick.picked_team_id == game.homeTeamId ? logos?.home_logo_url : logos?.away_logo_url
    return HomePickDetail(pick: pick, game: game, logoURL: logo.flatMap(URL.init(string:)))
  }

  private func loadPickemsProgress(client: SupabaseClient, userId: UUID, season: Int, week: Int) async {
    let service = PickemsService(client: client)
    let games = (try? await service.fetchGames(season: season, week: week, sport: "nfl")) ?? []
    let picks = (try? await service.fetchMyPicks(userId: userId, gameIds: games.map(\.id))) ?? [:]
    pickemsTotal = games.count
    pickemsOpen = games.filter { !$0.isLocked }.count
    pickemsOpenUnpicked = games.filter { !$0.isLocked && picks[$0.id] == nil }.count
    pickemsPicked = picks.count
    pickemsLoaded = true
  }

  private func checkOffseason(client: SupabaseClient, season: Int, sport: String) async -> Bool {
    struct CountRow: Decodable { let id: UUID }
    guard let res = try? await client
      .from("games")
      .select("id")
      .eq("season", value: season)
      .eq("sport", value: sport)
      .limit(1)
      .execute()
    else { return true }
    let games = (try? JSONDecoder().decode([CountRow].self, from: res.data)) ?? []
    return games.isEmpty
  }

  /// Earliest kickoff among games you can still pick (has a line, hasn't
  /// started). nil once every pickable game has kicked off. Previously this
  /// was the week's FIRST kickoff, so the contest row read "Locked" as soon
  /// as Thursday's game started even though the weekend slate was open.
  private func fetchNextOpenKickoff(client: SupabaseClient, season: Int, week: Int, sport: String) async -> Date? {
    struct Row: Decodable { let start_time: Date }
    guard let res = try? await client
      .from("v_games_named")
      .select("start_time")
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
      .gt("start_time", value: ISO8601DateFormatter().string(from: Date()))
      .not("latest_spread", operator: .is, value: "null")
      .order("start_time", ascending: true)
      .limit(1)
      .execute()
    else { return nil }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    return try? dec.decode([Row].self, from: res.data).first?.start_time
  }

  private func fetchRecap(client: SupabaseClient, season: Int, week: Int, sport: String) async -> [RecapHit] {
    guard week > 1 else { return [] }
    let res = try? await client
      .from("v_recap_underdogs_hit")
      .select("game_id, match_description, line_display, score_display, abs_spread")
      .eq("season", value: season)
      .eq("week", value: week - 1)
      .eq("sport", value: sport)
      .order("abs_spread", ascending: false)
      .limit(4)
      .execute()
    guard let res else { return [] }
    return (try? JSONDecoder().decode([RecapHit].self, from: res.data)) ?? []
  }
}

struct HomePickDetail {
  let pick: Pick
  let game: Game
  let logoURL: URL?

  var pickedIsHome: Bool { pick.picked_team_id == game.homeTeamId }
  var teamName: String { (pickedIsHome ? game.homeTeam : game.awayTeam) ?? "Your pick" }
  var opponent: String { (pickedIsHome ? game.awayTeam : game.homeTeam) ?? "Opponent" }
  var spread: Double? { pick.picked_team_id == game.derivedUnderdogTeamId ? game.underdogSpread : nil }
  var outcome: Game.PickOutcome { game.outcome(forPickedTeamId: pick.picked_team_id) }
  var isLive: Bool { game.status == "in_progress" }

  /// "vs Army · Fri 1:00 PM", or the score once it's live/final.
  var subline: String {
    if let h = game.homePoints, let a = game.awayPoints, isLive || game.status == "final" {
      let (mine, theirs) = pickedIsHome ? (h, a) : (a, h)
      return "vs \(opponent) · \(isLive ? "Live " : "")\(mine)–\(theirs)"
    }
    let f = DateFormatter()
    f.dateFormat = "EEE h:mm a"
    return "vs \(opponent) · \(f.string(from: game.startTime))"
  }
}

struct RecapHit: Decodable, Identifiable {
  let game_id: UUID
  let match_description: String?
  let line_display: String?
  let score_display: String?
  let abs_spread: Double

  var id: UUID { game_id }
}

struct HomeView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject var appState: AppState
  @StateObject private var viewModel = HomeViewModel()
  // Follows the shared CFB | PRO BALL | PICKEMS switcher (Pickems is NFL).
  private var sport: Sport { appState.currentGame == .cfb ? .cfb : .nfl }
  @State private var showCreateGroup = false
  @State private var showJoinGroup = false
  @State private var showInvitePicker = false
  @State private var pushGroupSlug: String?
  @State private var shareURL: URL?
  @State private var showShareSheet = false
  @State private var dismissingIntro = false
  @State private var showProfile = false

  // groups-create-invite is admin-only server-side (assertIsGroupAdmin) --
  // only owner/admin rows can actually generate a link.
  private var inviteableGroups: [MyGroup] {
    viewModel.myGroups.filter { $0.my_role == .owner || $0.my_role == .admin }
  }

  // A contest counts as "yours" if you're in an eligible group for it, or
  // (for a brand-new account with no groups yet) if onboarding's "what do
  // you want to play" step recorded interest in it. Underdog Pick has no
  // group requirement to make a pick at all, so group membership is a
  // signal here, not a gate. Mirrors web's Home.tsx exactly.
  private var gameInterests: [String] { viewModel.profile?.game_interests ?? [] }
  private var underdogCfbActive: Bool {
    viewModel.myGroups.contains { $0.game_type != .pickems && ($0.sport == .cfb || $0.sport == .both) }
      || gameInterests.contains("cfb_underdog")
  }
  private var underdogProBallActive: Bool {
    viewModel.myGroups.contains { $0.game_type != .pickems && ($0.sport == .nfl || $0.sport == .both) }
      || gameInterests.contains("proball_underdog")
  }
  private var pickemsActive: Bool {
    viewModel.myGroups.contains { $0.game_type == .pickems || $0.game_type == .both }
      || gameInterests.contains("pickems")
  }
  private var hasAnyContest: Bool { underdogCfbActive || underdogProBallActive || pickemsActive }
  private var showExploreUnderdog: Bool { !underdogCfbActive && !underdogProBallActive }
  private var showExplorePickems: Bool { !pickemsActive }
  private var showPickemsIntroBanner: Bool {
    guard let profile = viewModel.profile else { return false }
    return profile.has_onboarded && !profile.pickems_intro_dismissed && !pickemsActive
  }

  private var initials: String {
    let email = appState.session?.user.email ?? "??"
    return String(email.prefix(2)).uppercased()
  }

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()
        BoldTheme.AmbientBlobs().ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            topRow
            if viewModel.hasLoaded {
              contestsSection
              groupsSection
              discoverSection
              recapSection
              quickActionsRow
            } else {
              ProgressView()
                .tint(BoldTheme.Colors.goldDeep)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            }
          }
          .padding(18)
        }
      }
      .navigationBarHidden(true)
      // onAppear (not .task) so returning from Games/Pickems after making a
      // pick refreshes the This Week rows.
      .onAppear {
        Task {
          if let client, let userId = appState.session?.user.id {
            viewModel.configure(client: client)
            await viewModel.load(userId: userId, sport: sport.rawValue)
          }
        }
      }
      .onChange(of: sport) { _, newSport in
        if let userId = appState.session?.user.id {
          Task { await viewModel.load(userId: userId, sport: newSport.rawValue) }
        }
      }
      .refreshable {
        if let userId = appState.session?.user.id {
          await viewModel.load(userId: userId, sport: sport.rawValue)
        }
      }
      .navigationDestination(item: $pushGroupSlug) { slug in
        GroupDetailView(slug: slug)
      }
      .sheet(isPresented: $showCreateGroup) {
        CreateGroupView {
          if let userId = appState.session?.user.id {
            await viewModel.load(userId: userId, sport: sport.rawValue)
          }
        }
      }
      .sheet(isPresented: $showJoinGroup) {
        JoinGroupView {
          if let userId = appState.session?.user.id {
            await viewModel.load(userId: userId, sport: sport.rawValue)
          }
        }
      }
      .sheet(isPresented: $showInvitePicker) {
        InviteGroupPickerSheet(groups: inviteableGroups) { group in
          showInvitePicker = false
          Task { await shareGroupInvite(group) }
        }
      }
      .sheet(isPresented: $showShareSheet) {
        if let shareURL {
          ActivityShareSheet(activityItems: [shareURL])
        }
      }
    }
  }

  private func handleInviteTap() {
    if inviteableGroups.isEmpty {
      showCreateGroup = true
    } else if inviteableGroups.count == 1, let only = inviteableGroups.first {
      Task { await shareGroupInvite(only) }
    } else {
      showInvitePicker = true
    }
  }

  private func shareGroupInvite(_ group: MyGroup) async {
    guard let client else { return }
    do {
      let result = try await GroupsService(client: client).createInvite(groupId: group.group_id, maxUses: nil, expiresAt: nil)
      guard let url = URL(string: "https://www.stupidunderdogpick.com\(result.joinUrl)") else { return }
      shareURL = url
      showShareSheet = true
    } catch {
      // Invite creation failing here (e.g. a network blip) isn't worth a
      // blocking alert -- the group's own Invite panel remains available
      // as a fallback with its own error handling.
    }
  }

  private var quickActionsRow: some View {
    VStack(spacing: 0) {
      Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
        .padding(.bottom, 20)
      HStack(spacing: 34) {
        quickAction(label: "Create Group", systemImage: "plus", gold: true) { showCreateGroup = true }
        quickAction(label: "Join Group", systemImage: "link", gold: false) { showJoinGroup = true }
        quickAction(label: "Invite Friends", systemImage: "square.and.arrow.up", gold: false, action: handleInviteTap)
      }
    }
    .padding(.top, 4)
    .padding(.bottom, 8)
  }

  private func quickAction(label: String, systemImage: String, gold: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ZStack {
          Circle()
            .fill(gold ? BoldTheme.Colors.gold : Color.white.opacity(0.7))
            .frame(width: 50, height: 50)
            .overlay(gold ? nil : Circle().strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
            .overlay { if gold { BoldTheme.HatchOverlay().clipShape(Circle()) } }
            .shadow(color: Color(hex: 0x142A1C).opacity(gold ? 0.22 : 0.08), radius: 8, y: 4)
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
        }
        Text(label).font(BoldTheme.Fonts.body(12, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
      }
    }
  }

  private var topRow: some View {
    HStack(spacing: 10) {
      SupIcon(variant: .monogram)
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color(hex: 0x142A1C).opacity(0.3), radius: 6, y: 4)

      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: !viewModel.hasLoaded || viewModel.week == nil ? " " : (viewModel.isOffseason ? "OFFSEASON" : "WEEK \(formatWeekLabel(viewModel.week ?? 0)) · \(sport == .cfb ? "CFB" : "PRO BALL") \(viewModel.season ?? 0)"))
          .font(BoldTheme.Fonts.mono(10, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.green)
        HStack(spacing: 8) {
          Text("WELCOME BACK.")
            .font(BoldTheme.Fonts.display(19))
            .foregroundColor(BoldTheme.Colors.text)
          if viewModel.streak > 0 {
            Text(verbatim: "🔥 \(viewModel.streak)-week streak")
              .font(BoldTheme.Fonts.mono(11, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.goldDeep)
              .padding(.horizontal, 9).padding(.vertical, 3)
              .background(BoldTheme.Colors.goldDeep.opacity(0.1))
              .clipShape(Capsule())
          }
        }
      }

      Spacer()

      Button {
        showProfile = true
      } label: {
        Circle()
          .fill(BoldTheme.Colors.text)
          .frame(width: 34, height: 34)
          .overlay(
            Text(initials)
              .font(BoldTheme.Fonts.display(13))
              .foregroundColor(BoldTheme.Colors.gold)
          )
          .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
      }
      .accessibilityLabel("Profile")
    }
    .padding(.bottom, 16)
    // Presented as a sheet rather than a NavigationLink push -- ProfileView
    // has its own internal NavigationStack (it's also a standalone tab
    // root), and nesting that inside Home's NavigationStack would double
    // up the nav bar.
    .sheet(isPresented: $showProfile) {
      ProfileView()
    }
  }

  // ── Your Contests -- one row per game this account is actually playing,
  // so someone in only one game never has to wade through the others to
  // find their pick. Mirrors web's Home.tsx exactly. ──────────────────────
  private var contestsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if showPickemsIntroBanner {
        PickemsIntroBanner(dismissing: dismissingIntro) {
          Task { await dismissPickemsIntro() }
          appState.goToPickems()
        } onDismiss: {
          Task { await dismissPickemsIntro() }
        }
      }

      Text(hasAnyContest ? "THIS WEEK" : "GET STARTED")
        .font(BoldTheme.Fonts.mono(10, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)

      if hasAnyContest {
        VStack(spacing: 10) {
          if underdogCfbActive {
            ContestRow(
              kind: .underdog,
              sport: "CFB",
              week: weekShort(viewModel.cfbContext),
              status: underdogStatus(pick: viewModel.myPickCfb, detail: viewModel.pickDetailCfb, kickoff: viewModel.nextOpenKickoffCfb, loaded: viewModel.cfbWindowLoaded, offseason: viewModel.cfbOffseason),
              detail: viewModel.pickDetailCfb
            ) {
              appState.goToUnderdog(sport: "cfb")
            }
          }
          if underdogProBallActive {
            ContestRow(
              kind: .underdog,
              sport: "Pro Ball",
              week: weekShort(viewModel.nflContext),
              status: underdogStatus(pick: viewModel.myPickNfl, detail: viewModel.pickDetailNfl, kickoff: viewModel.nextOpenKickoffNfl, loaded: viewModel.nflWindowLoaded, offseason: viewModel.nflOffseason),
              detail: viewModel.pickDetailNfl
            ) {
              appState.goToUnderdog(sport: "nfl")
            }
          }
          if pickemsActive {
            ContestRow(
              kind: .pickems,
              sport: "Pro Ball",
              week: weekShort(viewModel.nflContext),
              status: pickemsStatus,
              progress: viewModel.pickemsPicked > 0 && viewModel.pickemsTotal > 0 ? (viewModel.pickemsPicked, viewModel.pickemsTotal) : nil
            ) {
              appState.goToPickems()
            }
          }
        }
      }

      if showExploreUnderdog || showExplorePickems {
        if hasAnyContest {
          Text("EXPLORE OTHER GAMES")
            .font(BoldTheme.Fonts.mono(10, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textFaint)
            .padding(.top, 4)
        }
        VStack(spacing: 10) {
          if showExploreUnderdog {
            GameCardView(game: .underdog, compact: true) {
              appState.requestedTab = 1
            }
          }
          if showExplorePickems {
            GameCardView(game: .pickems, compact: true) {
              appState.goToPickems()
            }
          }
        }
      }
    }
    .padding(.bottom, 22)
  }

  /// "WEEK 3", or blank until the context loads.
  private func weekShort(_ ctx: CurrentContext?) -> String {
    ctx.map { "WEEK \(formatWeekLabel($0.week))" } ?? ""
  }

  /// Picked (or its result once played); otherwise "Pick now" while any
  /// pickable game is still to come, "Missed" only once all have kicked
  /// off, and a neutral CTA while still loading.
  private func underdogStatus(pick: Pick?, detail: HomePickDetail?, kickoff: Date?, loaded: Bool, offseason: Bool) -> ContestRow.Status {
    if offseason { return .offseason }
    if pick != nil {
      guard let detail else { return .picked }
      if detail.isLive { return .live }
      switch detail.outcome {
      case .win: return .won(detail.spread.map { "+\(formatSpread($0))" } ?? "")
      case .loss: return .lost
      case .pending: return .picked
      }
    }
    guard loaded else { return .neutral("Make pick →") }
    return kickoff == nil ? .missed : .cta("Pick now →")
  }

  private var pickemsStatus: ContestRow.Status {
    if viewModel.nflOffseason { return .offseason }
    guard viewModel.pickemsLoaded else { return .neutral("Make picks →") }
    let picked = viewModel.pickemsPicked, total = viewModel.pickemsTotal
    if total > 0 && picked >= total { return .picked }
    if viewModel.pickemsOpenUnpicked > 0 { return .cta("Make picks →") }
    // Every still-open game is picked -- nothing left to do this week.
    if viewModel.pickemsOpen > 0 && picked > 0 { return .picked }
    return picked == 0 ? .missed : .partial(picked, total)
  }

  private func formatSpread(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
  }

  private func dismissPickemsIntro() async {
    guard let client, !dismissingIntro else { return }
    dismissingIntro = true
    try? await ProfilesService(client: client).dismissPickemsIntro()
    viewModel.profile = try? await ProfilesService(client: client).fetchMyProfile()
    dismissingIntro = false
  }

  private var groupsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("YOUR GROUPS").font(BoldTheme.Fonts.display(20)).foregroundColor(BoldTheme.Colors.text)
        Spacer()
        Button {
          appState.requestedTab = 4 // Groups tab
        } label: {
          Text("Discover public groups →").font(BoldTheme.Fonts.body(12, weight: .bold)).foregroundColor(BoldTheme.Colors.green)
        }
      }

      if viewModel.myGroups.isEmpty {
        BoldTheme.GlassCard(radius: 16, padding: 24) {
          Text("You're not in any groups yet.")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity)
        }
      } else {
        ForEach(viewModel.myGroups) { g in
          Button { pushGroupSlug = g.slug } label: {
            BoldTheme.GlassCard(strong: true, radius: 14, padding: 16) {
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  HStack(spacing: 8) {
                    Text(g.name).font(BoldTheme.Fonts.body(14, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
                    if g.my_role != .member { RoleBadge(role: g.my_role) }
                  }
                  Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")")
                    .font(BoldTheme.Fonts.body(11.5))
                    .foregroundColor(BoldTheme.Colors.textDim)
                }
                Spacer()
                if let rank = g.rank {
                  Text(verbatim: "#\(rank)").font(BoldTheme.Fonts.mono(13, weight: .semibold)).foregroundColor(BoldTheme.Colors.goldDeep)
                }
              }
            }
          }
          .padding(.bottom, 8)
        }
      }
    }
    .padding(.bottom, 22)
  }

  private var discoverSection: some View {
    Group {
      if !viewModel.discoverGroups.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("DISCOVER").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(viewModel.discoverGroups) { g in
                BoldTheme.GlassCard(strong: true, radius: 14, padding: 12) {
                  VStack(alignment: .leading, spacing: 8) {
                    Text(g.name).font(BoldTheme.Fonts.body(12.5, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
                    Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")")
                      .font(BoldTheme.Fonts.mono(9.5))
                      .foregroundColor(BoldTheme.Colors.textDim)
                    Button { appState.requestedTab = 4 } label: {
                      Text("View")
                        .font(BoldTheme.Fonts.body(11, weight: .bold))
                        .foregroundColor(BoldTheme.Colors.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(BoldTheme.Colors.green.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BoldTheme.Colors.green.opacity(0.35)))
                        .cornerRadius(8)
                    }
                  }
                }
                .frame(width: 148)
              }
            }
          }
        }
        .padding(.bottom, 22)
      }
    }
  }

  private var recapSection: some View {
    Group {
      if !viewModel.recap.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("DOGS THAT HIT LAST WEEK").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
          BoldTheme.GlassCard(strong: true, radius: 16, padding: 6) {
            VStack(spacing: 0) {
              ForEach(Array(viewModel.recap.enumerated()), id: \.element.id) { index, hit in
                HStack(spacing: 10) {
                  Circle().fill(BoldTheme.Colors.gold).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(BoldTheme.Colors.gold.opacity(0.22), lineWidth: 3).scaleEffect(1.6))
                  VStack(alignment: .leading, spacing: 1) {
                    Text(hit.match_description ?? "").font(BoldTheme.Fonts.body(12.5, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
                    Text(verbatim: "Final: \(hit.score_display ?? "")").font(BoldTheme.Fonts.body(11)).foregroundColor(BoldTheme.Colors.textDim)
                  }
                  Spacer()
                  Text(hit.line_display ?? "").font(BoldTheme.Fonts.display(17)).foregroundColor(BoldTheme.Colors.green)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                  if index > 0 { Rectangle().fill(BoldTheme.Colors.border).frame(height: 1) }
                }
              }
            }
            .padding(.horizontal, 8)
          }
        }
      }
    }
  }
}

// ── Your Contests row ────────────────────────────────────────────────────
private struct ContestRow: View {
  enum Kind { case underdog, pickems }
  enum Status: Equatable {
    case offseason, picked, live, lost, missed
    case won(String)
    case partial(Int, Int)
    /// Gold call-to-action chip ("Pick now →", "Make picks →").
    case cta(String)
    /// Plain text CTA while status is still loading.
    case neutral(String)
  }

  let kind: Kind
  /// Primary label -- the sport ("CFB" / "Pro Ball").
  let sport: String
  /// "WEEK 3" (blank while loading).
  let week: String
  let status: Status
  var detail: HomePickDetail? = nil
  var progress: (picked: Int, total: Int)? = nil
  let action: () -> Void

  private var gameLabel: String { kind == .pickems ? "PICKEMS" : "UNDERDOG PICK" }
  private var gameColor: Color { kind == .pickems ? BoldTheme.Colors.pickemsAccent : BoldTheme.Colors.goldDeep }

  var body: some View {
    Button(action: action) {
      BoldTheme.GlassCard(strong: true, radius: 16, padding: 14) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
              Text(week.isEmpty ? gameLabel : "\(gameLabel) · \(week)")
                .font(BoldTheme.Fonts.mono(10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(gameColor)
              Text(sport)
                .font(BoldTheme.Fonts.display(26))
                .foregroundColor(BoldTheme.Colors.text)
            }
            Spacer()
            statusView
          }

          if let detail {
            Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
            HStack(spacing: 10) {
              RetryingAsyncImage(url: detail.logoURL) { img in
                img.resizable().scaledToFit()
              } placeholder: {
                Image(systemName: "football").resizable().scaledToFit().padding(5).foregroundColor(BoldTheme.Colors.textFaint)
              }
              .frame(width: 30, height: 30)
              VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                  Text(detail.teamName)
                    .font(BoldTheme.Fonts.body(15, weight: .bold))
                    .foregroundColor(BoldTheme.Colors.text)
                    .lineLimit(1)
                  if let sp = detail.spread {
                    Text(verbatim: "+\(sp == sp.rounded() ? String(format: "%.0f", sp) : String(format: "%.1f", sp))")
                      .font(BoldTheme.Fonts.mono(13, weight: .semibold))
                      .foregroundColor(BoldTheme.Colors.goldDeep)
                  }
                }
                Text(detail.subline)
                  .font(BoldTheme.Fonts.body(12))
                  .foregroundColor(BoldTheme.Colors.textDim)
                  .lineLimit(1)
              }
              Spacer(minLength: 0)
            }
          }

          if let progress {
            VStack(alignment: .leading, spacing: 5) {
              GeometryReader { geo in
                ZStack(alignment: .leading) {
                  Capsule().fill(BoldTheme.Colors.track)
                  Capsule().fill(BoldTheme.Colors.pickemsAccent)
                    .frame(width: geo.size.width * CGFloat(min(progress.picked, progress.total)) / CGFloat(max(progress.total, 1)))
                }
              }
              .frame(height: 5)
              Text(verbatim: "\(progress.picked) of \(progress.total) picked")
                .font(BoldTheme.Fonts.body(12))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
          }
        }
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var statusView: some View {
    switch status {
    case .offseason: chip("Offseason", fg: BoldTheme.Colors.textDim, bg: BoldTheme.Colors.track)
    case .picked: chip("Picked ✓", fg: BoldTheme.Colors.green, bg: BoldTheme.Colors.green.opacity(0.13))
    case .live: chip("Live", fg: Color(hex: 0xA6402A), bg: Color(hex: 0xC6402A).opacity(0.13))
    case .won(let pts): chip(pts.isEmpty ? "Won" : "Won \(pts)", fg: BoldTheme.Colors.text, bg: BoldTheme.Colors.gold)
    case .lost: chip("Lost", fg: BoldTheme.Colors.textDim, bg: BoldTheme.Colors.track)
    case .missed: chip("Missed", fg: BoldTheme.Colors.textDim, bg: BoldTheme.Colors.track)
    case .partial(let p, let t): chip("\(p) of \(t)", fg: BoldTheme.Colors.textDim, bg: BoldTheme.Colors.track)
    case .cta(let label): chip(label, fg: BoldTheme.Colors.text, bg: BoldTheme.Colors.gold)
    case .neutral(let label):
      Text(label).font(BoldTheme.Fonts.display(15)).foregroundColor(BoldTheme.Colors.goldDeep)
    }
  }

  private func chip(_ text: String, fg: Color, bg: Color) -> some View {
    Text(text)
      .font(BoldTheme.Fonts.body(11.5, weight: .bold))
      .foregroundColor(fg)
      .padding(.horizontal, 10).padding(.vertical, 4)
      .background(bg)
      .clipShape(Capsule())
      .fixedSize()
  }
}

// ── "Which game" card -- landing-style card reused for Explore. ─────────
enum GameCardKey { case underdog, pickems }

private struct GameCardView: View {
  let game: GameCardKey
  var compact: Bool = false
  let action: () -> Void

  private var eyebrow: String { game == .underdog ? "UNDERDOG PICK" : "PRO BALL PICKEMS" }
  private var headline: String { game == .underdog ? "PICK THE DOG. BANK THE POINTS." : "PICK EVERY WINNER. NO SPREADS." }
  private var body_: String {
    game == .underdog
      ? "One pick every week. Take the underdog — if they win outright, you bank the spread."
      : "Straight-up picks on every Pro Ball game, every week. Play in a group, chase the leaderboard."
  }
  private var badges: [String] { game == .underdog ? ["CFB · Free", "Pro Ball · Free"] : ["Pro Ball · Free"] }
  private var cta: String { game == .underdog ? "Play Underdog Pick" : "Play Pickems" }

  var body: some View {
    Button(action: action) {
      BoldTheme.GlassCard(strong: true, radius: 18, padding: compact ? 16 : 22) {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
          Text(eyebrow).font(BoldTheme.Fonts.mono(10, weight: .bold)).foregroundColor(BoldTheme.Colors.green)
          Text(headline).font(BoldTheme.Fonts.display(compact ? 19 : 26)).foregroundColor(BoldTheme.Colors.text)
          if !compact {
            Text(body_).font(BoldTheme.Fonts.body(13.5)).foregroundColor(BoldTheme.Colors.textDim)
          }
          HStack(spacing: 6) {
            ForEach(badges, id: \.self) { b in
              Text(b)
                .font(BoldTheme.Fonts.mono(10, weight: .semibold))
                .foregroundColor(BoldTheme.Colors.textDim)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(BoldTheme.Colors.track)
                .overlay(Capsule().strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
                .clipShape(Capsule())
            }
          }
          ZStack {
            BoldTheme.HatchOverlay()
            Text(verbatim: "\(cta) →").font(BoldTheme.Fonts.body(13, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
          }
          .padding(.horizontal, 16).padding(.vertical, 9)
          .background(LinearGradient(colors: [Color(hex: 0xFFDD5C), Color(hex: 0xFFD23A)], startPoint: .top, endPoint: .bottom))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
  }
}

// ── One-time re-intro banner for accounts that onboarded before Pickems
// existed (has_onboarded was already true, so the new onboarding step
// never runs for them). ──────────────────────────────────────────────────
private struct PickemsIntroBanner: View {
  let dismissing: Bool
  let onCheckItOut: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    BoldTheme.GlassCard(strong: true, radius: 16, padding: 16) {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("NEW").font(BoldTheme.Fonts.mono(10, weight: .bold)).foregroundColor(BoldTheme.Colors.green)
          Spacer()
          Button(action: onDismiss) {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.textDim)
              .frame(width: 26, height: 26)
              .background(Color.black.opacity(0.05))
              .clipShape(Circle())
          }
          .disabled(dismissing)
        }
        Text("PRO BALL PICKEMS IS HERE").font(BoldTheme.Fonts.display(20)).foregroundColor(BoldTheme.Colors.text)
        Text("Pick every Pro Ball game's winner each week — no spreads, just wins. Play in a group, chase the leaderboard.")
          .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
        Button(action: onCheckItOut) {
          ZStack {
            BoldTheme.HatchOverlay()
            Text("Check it out →").font(BoldTheme.Fonts.body(13, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
          }
          .padding(.horizontal, 16).padding(.vertical, 9)
          .background(LinearGradient(colors: [Color(hex: 0xFFDD5C), Color(hex: 0xFFD23A)], startPoint: .top, endPoint: .bottom))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .fixedSize()
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
      }
    }
  }
}

// ── Invite quick action, 2+ inviteable-groups case -- which group's invite
// link? (0 inviteable groups opens CreateGroupView, 1 shares immediately,
// both handled in HomeView.handleInviteTap without needing this sheet.)
private struct InviteGroupPickerSheet: View {
  let groups: [MyGroup]
  let onPick: (MyGroup) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            Text("Pick a group to share its invite link.")
              .font(BoldTheme.Fonts.body(12.5))
              .foregroundColor(BoldTheme.Colors.textDim)
              .padding(.bottom, 4)
            ForEach(groups) { g in
              Button { onPick(g) } label: {
                HStack {
                  Text(g.name).font(BoldTheme.Fonts.body(13.5, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
                  Spacer()
                }
                .padding(14)
                .background(Color.white.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
                .cornerRadius(12)
              }
            }
          }
          .padding(20)
        }
      }
      .navigationTitle("Invite to which group?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
  }
}

// ── System share sheet wrapper -- SwiftUI's ShareLink can't be triggered
// programmatically after an async fetch (it's a tap-to-share button, see
// GamesView's pick-image share for that pattern); the invite link only
// exists after createInvite() returns, so this goes through
// UIActivityViewController directly instead. ─────────────────────────────
private struct ActivityShareSheet: UIViewControllerRepresentable {
  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
