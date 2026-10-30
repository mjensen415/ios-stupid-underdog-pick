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
  /// Any game this week still to kick off, lined or not. A new week before
  /// lines post has upcoming games but no pickable ones -- that's "Make
  /// pick", not "Missed".
  @Published var cfbWeekUpcoming = false
  @Published var nflWeekUpcoming = false
  @Published var cfbOffseason = false
  @Published var nflOffseason = false
  @Published var profile: ProfileRow?

  // "This week" row detail: the picked team for each Underdog sport, and
  // Pickems progress for the current NFL week.
  @Published var pickDetailCfb: HomePickDetail?
  @Published var pickDetailNfl: HomePickDetail?
  /// Last week's Underdog pick per sport (the week before the live one),
  /// for Home's one-line "Last week:" result. Nil = no pick last week.
  @Published var lastWeekDetailCfb: HomePickDetail?
  @Published var lastWeekDetailNfl: HomePickDetail?
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
      cfbWeekUpcoming = await weekHasUpcomingGame(client: client, season: cfbCtx.season, week: cfbCtx.week, sport: "cfb")
      cfbWindowLoaded = true
      cfbOffseason = await cfbOffseasonTask
      pickDetailCfb = await fetchPickDetail(client: client, pick: myPickCfb)
      lastWeekDetailCfb = await fetchLastWeek(client: client, season: cfbCtx.season, week: cfbCtx.week, sport: "cfb")
    }
    if let nflCtx {
      async let nflPickTask = try? PicksService(client: client).myPick(season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      async let nflKickoffTask = fetchNextOpenKickoff(client: client, season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      async let nflOffseasonTask = checkOffseason(client: client, season: nflCtx.season, sport: "nfl")
      myPickNfl = await nflPickTask ?? nil
      nextOpenKickoffNfl = await nflKickoffTask
      nflWeekUpcoming = await weekHasUpcomingGame(client: client, season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      nflWindowLoaded = true
      nflOffseason = await nflOffseasonTask
      pickDetailNfl = await fetchPickDetail(client: client, pick: myPickNfl)
      lastWeekDetailNfl = await fetchLastWeek(client: client, season: nflCtx.season, week: nflCtx.week, sport: "nfl")
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

  /// The pick (and its game) from the week before `week`, same sport.
  private func fetchLastWeek(client: SupabaseClient, season: Int, week: Int, sport: String) async -> HomePickDetail? {
    guard week > 1,
          let pick = try? await PicksService(client: client).myPick(season: season, week: week - 1, sport: sport)
    else { return nil }
    return await fetchPickDetail(client: client, pick: pick)
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
  private func weekHasUpcomingGame(client: SupabaseClient, season: Int, week: Int, sport: String) async -> Bool {
    // nil (couldn't check) -> assume games remain rather than claim "Missed"
    guard let w = await fetchWeekPickWindow(client: client, season: season, week: week, sport: sport) else { return true }
    return w.upcoming > 0
  }

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
  var teamName: String { (pickedIsHome ? game.homeDisplay : game.awayDisplay) ?? "Your pick" }
  var opponent: String { (pickedIsHome ? game.awayDisplay : game.homeDisplay) ?? "Opponent" }
  var spread: Double? { pick.winPoints(on: game) }
  var isLocked: Bool { pick.locked_spread != nil }
  var lineNote: String? { pick.lineNote(on: game) }
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
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  @EnvironmentObject private var proStore: ProStore
  @StateObject private var viewModel = HomeViewModel()
  // Follows the shared CFB | PRO BALL | PICKEMS switcher (Pickems is NFL).
  private var sport: Sport { appState.currentGame == .cfb ? .cfb : .nfl }
  @State private var showCreateGroup = false
  @State private var showJoinGroup = false
  @State private var showInvitePicker = false
  @State private var pushGroupSlug: String?
  @State private var pushGlobalBoard: CurrentGame?
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
  /// DEBUG-only simulator preview: SIMCTL_CHILD_SUP_CONTESTS=proball_underdog
  /// (comma list of cfb_underdog / proball_underdog / pickems) forces which
  /// contests count as yours.
  private var debugContests: Set<String>? {
    #if DEBUG
    if let v = ProcessInfo.processInfo.environment["SUP_CONTESTS"] { return Set(v.split(separator: ",").map(String.init)) }
    #endif
    return nil
  }
  private var underdogCfbActive: Bool {
    if let d = debugContests { return d.contains("cfb_underdog") }
    return viewModel.myGroups.contains { $0.game_type != .pickems && ($0.sport == .cfb || $0.sport == .both) }
      || gameInterests.contains("cfb_underdog")
  }
  private var underdogProBallActive: Bool {
    if let d = debugContests { return d.contains("proball_underdog") }
    return viewModel.myGroups.contains { $0.game_type != .pickems && ($0.sport == .nfl || $0.sport == .both) }
      || gameInterests.contains("proball_underdog")
  }
  private var pickemsActive: Bool {
    if let d = debugContests { return d.contains("pickems") }
    return viewModel.myGroups.contains { $0.game_type == .pickems || $0.game_type == .both }
      || gameInterests.contains("pickems")
  }
  private var hasAnyContest: Bool { underdogCfbActive || underdogProBallActive || pickemsActive }
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

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            topRow
            // Live games across the sports you can see (round 3); hidden
            // when nothing is live.
            LiveTickerStrip(topPadding: BoldTheme.Space.s3)
            if viewModel.hasLoaded {
              contestsSection
              if proStore.showEntry(flags: featureFlags) {
                sectionHeader("Pro")
                NavigationLink { ProView() } label: { ProEntryCard() }
                  .buttonStyle(.plain)
              }
              groupsSection
              discoverSection
              recapSection
              quickActionsRow
            } else {
              ProgressView()
                .tint(BoldTheme.Colors.text)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            }
          }
          .padding(.horizontal, BoldTheme.Space.margin)
          .padding(.top, BoldTheme.Space.s2)
          .padding(.bottom, BoldTheme.Space.s5)
        }
      }
      .navigationBarHidden(true)
      // No nav bar here, so give the status bar its own page-coloured strip --
      // otherwise cards scroll up under the clock.
      .safeAreaInset(edge: .top, spacing: 0) {
        Color.clear.frame(height: 0)
          .background(BoldTheme.Colors.bgPage.opacity(0.94), ignoresSafeAreaEdges: .top)
      }
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
      .navigationDestination(item: $pushGlobalBoard) { game in
        GlobalBoardView(game: game)
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
      guard let url = SiteLinks.url(path: result.joinUrl) else { return }
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
        quickAction(label: "Create group", systemImage: "plus", gold: false) { showCreateGroup = true }
        quickAction(label: "Join group", systemImage: "link", gold: false) { showJoinGroup = true }
        quickAction(label: "Invite friends", systemImage: "square.and.arrow.up", gold: false, action: handleInviteTap)
      }
    }
    .padding(.top, BoldTheme.Space.s5)
    .padding(.bottom, BoldTheme.Space.s2)
  }

  private func quickAction(label: String, systemImage: String, gold: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ZStack {
          Circle()
            .fill(gold ? BoldTheme.Colors.gold : BoldTheme.Colors.card)
            .frame(width: 50, height: 50)
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
        }
        Text(label).font(BoldTheme.Fonts.body(12, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
      }
    }
  }

  // ── Greeting (de-slop #16/#17): two lines, no "WELCOME BACK." ───────
  private var greeting: String {
    let h = Calendar.current.component(.hour, from: Date())
    let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    guard let first = viewModel.profile?.display_name?
      .split(separator: " ").first.map(String.init), !first.isEmpty else { return part }
    return "\(part), \(first)"
  }

  /// The contest Home leads with (the yellow block): CFB if you play it,
  /// else Pro Ball Underdog. Nil = no Underdog contest yet.
  private var primarySport: String? {
    if underdogCfbActive { return "cfb" }
    if underdogProBallActive { return "nfl" }
    return nil
  }

  /// Next kickoff you can still pick for the lead contest.
  private var primaryKickoff: Date? {
    primarySport == "cfb" ? viewModel.nextOpenKickoffCfb : primarySport == "nfl" ? viewModel.nextOpenKickoffNfl : nil
  }

  private var countdownLine: Text? {
    guard let k = primaryKickoff else { return nil }
    let secs = max(0, Int(k.timeIntervalSinceNow))
    let d = secs / 86_400, h = (secs % 86_400) / 3600, m = (secs % 3600) / 60
    let txt = d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(max(m, 1))m"
    return Text("Picks lock in ") + Text(verbatim: txt).foregroundColor(BoldTheme.Colors.text).font(BoldTheme.Fonts.body(15, weight: .semibold))
  }

  private var topRow: some View {
    HStack(alignment: .center, spacing: BoldTheme.Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: greeting)
          .font(BoldTheme.Fonts.body(22, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
        if viewModel.hasLoaded, let countdownLine {
          countdownLine
            .font(BoldTheme.Fonts.body(15))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
      }
      Spacer()
      Button {
        showProfile = true
      } label: {
        Circle()
          .fill(BoldTheme.Colors.text)
          .frame(width: 36, height: 36)
          .overlay(
            Text(initials)
              .font(BoldTheme.Fonts.display(17))
              .foregroundColor(BoldTheme.Colors.gold)
          )
      }
      .accessibilityLabel("Profile")
    }
    .padding(.top, BoldTheme.Space.s2)
    // Presented as a sheet rather than a NavigationLink push -- ProfileView
    // has its own internal NavigationStack (it's also a standalone tab
    // root), and nesting that inside Home's NavigationStack would double
    // up the nav bar.
    .sheet(isPresented: $showProfile) {
      ProfileView()
    }
  }

  // ── Last week's result (round 2): one quiet body-size line under the
  // yellow block, for the same contest. Hidden with no pick last week. ──
  @ViewBuilder private var lastWeekLine: some View {
    let detail = primarySport == "cfb" ? viewModel.lastWeekDetailCfb : primarySport == "nfl" ? viewModel.lastWeekDetailNfl : nil
    if let detail {
      Button { appState.requestedTab = 3 } label: {
        LastWeekLine(detail: detail)
      }
      .buttonStyle(.plain)
      .padding(.top, BoldTheme.Space.s3)
      .accessibilityHint("Opens My Picks")
    }
  }

  private func sectionHeader(_ title: String, link: String? = nil, action: (() -> Void)? = nil) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
      Spacer()
      if let link, let action {
        Button(action: action) {
          Text(link).font(BoldTheme.Fonts.body(14, weight: .semibold)).foregroundColor(BoldTheme.Colors.green)
        }
      }
    }
    .padding(.top, BoldTheme.Space.s5)
    .padding(.bottom, BoldTheme.Space.s2)
  }

  // ── Your Contests -- one row per game this account is actually playing,
  // so someone in only one game never has to wade through the others to
  // find their pick. Mirrors web's Home.tsx exactly. ──────────────────────
  private var contestsSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showPickemsIntroBanner {
        PickemsIntroBanner(dismissing: dismissingIntro) {
          Task { await dismissPickemsIntro() }
          appState.goToPickems()
        } onDismiss: {
          Task { await dismissPickemsIntro() }
        }
        .padding(.top, BoldTheme.Space.s4)
      }

      if hasAnyContest {
        // This week's pick: the one solid-yellow block on the screen (#19).
        if let primarySport {
          let isCfb = primarySport == "cfb"
          PickBlock(
            sport: isCfb ? "CFB" : "Pro Ball",
            week: isCfb ? viewModel.cfbContext?.week : viewModel.nflContext?.week,
            status: isCfb
              ? underdogStatus(pick: viewModel.myPickCfb, detail: viewModel.pickDetailCfb, kickoff: viewModel.nextOpenKickoffCfb, upcoming: viewModel.cfbWeekUpcoming, loaded: viewModel.cfbWindowLoaded, offseason: viewModel.cfbOffseason)
              : underdogStatus(pick: viewModel.myPickNfl, detail: viewModel.pickDetailNfl, kickoff: viewModel.nextOpenKickoffNfl, upcoming: viewModel.nflWeekUpcoming, loaded: viewModel.nflWindowLoaded, offseason: viewModel.nflOffseason),
            detail: isCfb ? viewModel.pickDetailCfb : viewModel.pickDetailNfl,
            kickoff: primaryKickoff
          ) {
            appState.goToUnderdog(sport: primarySport)
          }
          .padding(.top, BoldTheme.Space.s4)
          lastWeekLine
        }

        // Every other contest you play, as compact rows (#20).
        let others: [AnyView] = [
          (primarySport != "nfl" && underdogProBallActive) ? AnyView(ContestRow(
            kind: .underdog, sport: "Pro Ball", week: weekShort(viewModel.nflContext),
            status: underdogStatus(pick: viewModel.myPickNfl, detail: viewModel.pickDetailNfl, kickoff: viewModel.nextOpenKickoffNfl, upcoming: viewModel.nflWeekUpcoming, loaded: viewModel.nflWindowLoaded, offseason: viewModel.nflOffseason),
            detail: viewModel.pickDetailNfl, kickoff: viewModel.nextOpenKickoffNfl
          ) { appState.goToUnderdog(sport: "nfl") }) : nil,
          pickemsActive ? AnyView(ContestRow(
            kind: .pickems, sport: "Pro Ball", week: weekShort(viewModel.nflContext),
            status: pickemsStatus,
            progress: viewModel.pickemsTotal > 0 ? (viewModel.pickemsPicked, viewModel.pickemsTotal) : nil
          ) { appState.goToPickems() }) : nil,
        ].compactMap { $0 }
        if !others.isEmpty {
          sectionHeader("This week")
          ListCard(rows: others)
        }

        // Every contest you're not in yet gets a one-tap way in -- a
        // Pro-Ball-only player still sees College Underdog here, etc.
        let joinable: [(key: String, kind: JoinContestRow.Kind, sport: String, blurb: String)] = [
          underdogCfbActive ? nil : ("cfb_underdog", .underdog, "CFB", "One underdog a week. If they win outright, you win the points."),
          underdogProBallActive ? nil : ("proball_underdog", .underdog, "Pro Ball", "One underdog a week. If they win outright, you win the points."),
          pickemsActive ? nil : ("pickems", .pickems, "Pro Ball", "Pick every game's winner. 1 point each."),
        ].compactMap { $0 }
        if !joinable.isEmpty {
          sectionHeader("Join another contest")
          ListCard(rows: joinable.map { c in
            AnyView(JoinContestRow(kind: c.kind, sport: c.sport, blurb: c.blurb) {
              Task { await joinContest(c.key) }
            })
          })
        }
      } else {
        sectionHeader("Get started")
        VStack(spacing: BoldTheme.Space.cardGap) {
          GameCardView(game: .underdog, compact: true) {
            appState.requestedTab = 1
          }
          GameCardView(game: .pickems, compact: true) {
            appState.goToPickems()
          }
        }
      }
    }
  }

  /// Record the contest on the profile (so it shows under This Week from
  /// now on), then take them straight to it.
  private func joinContest(_ key: String) async {
    guard let client, let profile = viewModel.profile else { return }
    if let next = try? await ProfilesService(client: client).addGameInterest(key, to: profile.game_interests) {
      viewModel.profile?.game_interests = next
    }
    switch key {
    case "cfb_underdog": appState.goToUnderdog(sport: "cfb")
    case "proball_underdog": appState.goToUnderdog(sport: "nfl")
    default: appState.goToPickems()
    }
  }

  /// "Week 3", or blank until the context loads.
  private func weekShort(_ ctx: CurrentContext?) -> String {
    ctx.map { "Week \(formatWeekLabel($0.week))" } ?? ""
  }

  /// Picked (or its result once played); otherwise "Pick now" while any
  /// pickable game is still to come, "Missed" only once all have kicked
  /// off, and a neutral CTA while still loading.
  private func underdogStatus(pick: Pick?, detail: HomePickDetail?, kickoff: Date?, upcoming: Bool, loaded: Bool, offseason: Bool) -> ContestRow.Status {
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
    if kickoff != nil { return .cta("Pick now →") }
    // No lined game open: lines not posted yet (new week) vs week over.
    return upcoming ? .cta("Make pick →") : .missed
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
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader("Your groups", link: "Find a group") {
        appState.requestedTab = 4 // Groups tab
      }

      // The Global group: everyone's in it, no group needed.
      GlobalGroupsRow { pushGlobalBoard = $0 }
        .padding(.bottom, viewModel.myGroups.isEmpty ? 0 : BoldTheme.Space.cardGap)

      if viewModel.myGroups.isEmpty {
        BoldTheme.FlatCard {
          Text("No private groups yet. Start one for your friends, or join with a code.")
            .font(BoldTheme.Fonts.body(14))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
      } else {
        ListCard(rows: viewModel.myGroups.map { g in
          AnyView(Button { pushGroupSlug = g.slug } label: {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 2) {
                Text(g.name)
                  .font(BoldTheme.Fonts.body(15, weight: .semibold))
                  .foregroundColor(BoldTheme.Colors.text)
                Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")" + (g.my_role == .owner ? " · you own it" : g.my_role == .admin ? " · you're an admin" : ""))
                  .font(BoldTheme.Fonts.body(13))
                  .foregroundColor(BoldTheme.Colors.textDim)
              }
              Spacer(minLength: 0)
              if let rank = g.rank {
                Text(verbatim: "#\(rank)").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
              }
              Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(BoldTheme.Colors.textFaint)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain))
        })
      }
    }
  }

  private var discoverSection: some View {
    Group {
      if !viewModel.discoverGroups.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          sectionHeader("Public groups")
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BoldTheme.Space.s2) {
              ForEach(viewModel.discoverGroups) { g in
                Button { appState.requestedTab = 4 } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(g.name)
                      .font(BoldTheme.Fonts.body(14, weight: .semibold))
                      .foregroundColor(BoldTheme.Colors.text)
                      .lineLimit(2)
                      .multilineTextAlignment(.leading)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")")
                      .font(BoldTheme.Fonts.body(13))
                      .foregroundColor(BoldTheme.Colors.textDim)
                    Spacer(minLength: 0)
                  }
                  .padding(BoldTheme.Space.s3)
                  .frame(width: 148, height: 88, alignment: .topLeading)
                  .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
                }
                .buttonStyle(.plain)
              }
            }
          }
          .scrollClipDisabled()
        }
      }
    }
  }

  private var recapSection: some View {
    Group {
      if !viewModel.recap.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          sectionHeader("Dogs that won last week")
          ListCard(rows: viewModel.recap.map { hit in
            AnyView(HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 2) {
                Text(hit.match_description ?? "")
                  .font(BoldTheme.Fonts.body(15, weight: .semibold))
                  .foregroundColor(BoldTheme.Colors.text)
                Text(verbatim: "Final: \(hit.score_display ?? "")")
                  .font(BoldTheme.Fonts.body(13))
                  .foregroundColor(BoldTheme.Colors.textDim)
              }
              Spacer()
              Text(hit.line_display ?? "").font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.green)
            })
          })
        }
      }
    }
  }
}

/// "Last week: Baylor +1.5 · won, +1.5 pts". Green only on a won result;
/// a loss is just dim (no red alarm).
struct LastWeekLine: View {
  let detail: HomePickDetail

  var body: some View {
    let line = detail.spread.map { " +\(jsNumber($0))" } ?? ""
    HStack(spacing: 6) {
      if detail.outcome == .win {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(BoldTheme.Role.won)
      }
      (Text("Last week: ").foregroundColor(BoldTheme.Colors.textDim)
        + Text(verbatim: detail.teamName + line).foregroundColor(BoldTheme.Colors.text).font(BoldTheme.Fonts.body(15, weight: .semibold))
        + result)
        .font(BoldTheme.Fonts.body(15))
        .lineLimit(2)
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(BoldTheme.Colors.textFaint)
    }
    .contentShape(Rectangle())
  }

  private var result: Text {
    switch detail.outcome {
    case .win:
      let pts = detail.spread.map { ", +\(jsNumber($0)) pts" } ?? ""
      return Text(verbatim: " · won\(pts)").foregroundColor(BoldTheme.Role.won)
    case .loss:
      return Text(" · lost").foregroundColor(BoldTheme.Colors.textDim)
    case .pending:
      return Text(" · in progress").foregroundColor(BoldTheme.Colors.textDim)
    }
  }
}

/// Flat card holding compact rows with hairlines between them (#20).
private struct ListCard: View {
  let rows: [AnyView]
  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
        row
          .padding(.horizontal, BoldTheme.Space.cardPad)
          .padding(.vertical, BoldTheme.Space.s3)
          .frame(minHeight: 52)
          .overlay(alignment: .top) {
            if i > 0 { Rectangle().fill(BoldTheme.Colors.border).frame(height: 1) }
          }
      }
    }
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
    .clipShape(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous))
  }
}

/// This week's pick for the lead contest -- the one yellow block (#19),
/// with the ink-on-yellow primary button.
struct PickBlock: View {
  let sport: String
  let week: Int?
  let status: ContestRow.Status
  let detail: HomePickDetail?
  let kickoff: Date?
  let action: () -> Void

  private var headline: String {
    switch status {
    case .offseason: return "Offseason"
    case .won(let pts): return "\(detail?.teamName ?? "Your dog") won \(pts)".trimmingCharacters(in: .whitespaces)
    case .lost: return "\(detail?.teamName ?? "Your dog") lost"
    case .missed: return "No pick this week"
    case .picked, .live:
      guard let detail else { return "You're picked" }
      return detail.teamName + (detail.spread.map { " +\(jsNumber($0))" } ?? "")
    default: return "You haven't picked yet"
    }
  }

  private var subline: String? {
    if let detail {
      if let note = detail.lineNote { return "\(detail.subline) · \(note)" }
      return detail.subline
    }
    if status == .missed { return "Every game has kicked off. Catch the next one." }
    guard let kickoff else { return nil }
    let f = DateFormatter()
    f.dateFormat = "EEE h:mm a"
    return "Next game kicks off \(f.string(from: kickoff))"
  }

  private var buttonLabel: String {
    switch status {
    case .picked: return "Change pick"
    case .cta, .neutral: return "Pick your dog"
    default: return "See games"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: BoldTheme.Space.s3) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: "\(sport)\(week.map { " · Week \(formatWeekLabel($0))" } ?? "") · underdog pick")
          .font(BoldTheme.Fonts.body(13, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text.opacity(0.7))
        HStack(alignment: .center, spacing: 10) {
          if let detail {
            RetryingAsyncImage(url: detail.logoURL) { img in
              img.resizable().scaledToFit()
            } placeholder: {
              Image(systemName: "football").resizable().scaledToFit().padding(5).foregroundColor(BoldTheme.Colors.text.opacity(0.4))
            }
            .frame(width: 34, height: 34)
          }
          Text(verbatim: headline)
            .font(BoldTheme.Fonts.display(34))
            .foregroundColor(BoldTheme.Colors.text)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
          if detail?.isLocked == true {
            Image(systemName: "lock.fill")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.text.opacity(0.6))
              .accessibilityLabel("Line locked")
          }
        }
        if let subline {
          Text(verbatim: subline)
            .font(BoldTheme.Fonts.body(14))
            .foregroundColor(BoldTheme.Colors.text.opacity(0.75))
        }
      }
      Button(buttonLabel, action: action)
        .buttonStyle(SupInkButtonStyle())
    }
    .padding(BoldTheme.Space.cardPad)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.gold))
  }
}

// ── Compact contest rows (de-slop #20) ─────────────────────────────────
/// A contest you're not in yet: compact row with an outline "Join" pill.
private struct JoinContestRow: View {
  enum Kind { case underdog, pickems }
  let kind: Kind
  let sport: String
  let blurb: String
  let action: () -> Void

  private var gameLabel: String { kind == .pickems ? "Pickems" : "Underdog pick" }

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "\(sport) · \(gameLabel)")
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
          Text(blurb)
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        SupPill(text: "Join", kind: .outline)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// "Pro Ball · Underdog pick" / "Week 8 · locks Sun 1:00 PM" / one pill.
struct ContestRow: View {
  enum Kind { case underdog, pickems }
  enum Status: Equatable {
    case offseason, picked, live, lost, missed
    case won(String)
    case partial(Int, Int)
    /// Still to do ("Pick now", "Make picks").
    case cta(String)
    /// Still loading.
    case neutral(String)
  }

  let kind: Kind
  /// The sport ("CFB" / "Pro Ball").
  let sport: String
  /// "Week 3" (blank while loading).
  let week: String
  let status: Status
  var detail: HomePickDetail? = nil
  var kickoff: Date? = nil
  var progress: (picked: Int, total: Int)? = nil
  let action: () -> Void

  private var gameLabel: String { kind == .pickems ? "Pickems" : "Underdog pick" }

  private var subline: String {
    var parts: [String] = []
    if !week.isEmpty { parts.append(week) }
    if let detail {
      parts.append(detail.teamName + (detail.spread.map { " +\(jsNumber($0))" } ?? ""))
    } else if let progress {
      parts.append("\(progress.picked) of \(progress.total) picked")
    } else if let kickoff, case .cta = status {
      let f = DateFormatter()
      f.dateFormat = "EEE h:mm a"
      parts.append("locks \(f.string(from: kickoff))")
    }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 10) {
        if let detail {
          RetryingAsyncImage(url: detail.logoURL) { img in
            img.resizable().scaledToFit()
          } placeholder: {
            Image(systemName: "football").resizable().scaledToFit().padding(5).foregroundColor(BoldTheme.Colors.textFaint)
          }
          .frame(width: 28, height: 28)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "\(sport) · \(gameLabel)")
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
          if !subline.isEmpty {
            Text(verbatim: subline)
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(BoldTheme.Colors.textDim)
          }
        }
        Spacer(minLength: 8)
        statusView
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var statusView: some View {
    switch status {
    case .offseason: SupPill(text: "Offseason", kind: .gray)
    case .picked: SupPill(text: "Picked", kind: .green)
    case .live: SupPill(text: "Live", kind: .gray)
    case .won(let pts): SupPill(text: pts.isEmpty ? "Won" : "Won \(pts)", kind: .green)
    case .lost: SupPill(text: "Lost", kind: .gray)
    // Neutral gray, not red (de-slop #21).
    case .missed: SupPill(text: "Missed", kind: .gray)
    case .partial(let p, let t): SupPill(text: "\(p) of \(t)", kind: .gray)
    // Outline so it doesn't compete with the yellow block.
    case .cta, .neutral: SupPill(text: "Pick", kind: .outline)
    }
  }
}

// ── "Which game" card -- shown before you're in any contest. ───────────
enum GameCardKey { case underdog, pickems }

private struct GameCardView: View {
  let game: GameCardKey
  var compact: Bool = false
  let action: () -> Void

  private var eyebrow: String { game == .underdog ? "Underdog pick · CFB and Pro Ball · free" : "Pro Ball Pickems · free" }
  private var headline: String { game == .underdog ? "Pick the dog. Win the points." : "Pick every winner. No spreads." }
  private var body_: String {
    game == .underdog
      ? "One pick every week. Take the underdog. If they win outright, you get points equal to the spread."
      : "Straight-up picks on every Pro Ball game, every week. Play in a group, chase the leaderboard."
  }
  private var cta: String { game == .underdog ? "Play Underdog Pick" : "Play Pickems" }

  var body: some View {
    BoldTheme.FlatCard {
      VStack(alignment: .leading, spacing: BoldTheme.Space.s2) {
        Text(eyebrow).font(BoldTheme.Fonts.body(13, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
        Text(headline).font(BoldTheme.Fonts.body(20, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
        Text(body_).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
          .fixedSize(horizontal: false, vertical: true)
        Button(cta, action: action)
          .buttonStyle(game == .underdog ? AnyButtonStyle(SupPrimaryButtonStyle()) : AnyButtonStyle(SupSecondaryButtonStyle()))
          .padding(.top, BoldTheme.Space.s1)
      }
    }
  }
}

/// Type-erased ButtonStyle so one view can switch primary / secondary.
private struct AnyButtonStyle: ButtonStyle {
  private let make: (Configuration) -> AnyView
  init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
  func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// ── One-time re-intro banner for accounts that onboarded before Pickems
// existed (has_onboarded was already true, so the new onboarding step
// never runs for them). ──────────────────────────────────────────────────
private struct PickemsIntroBanner: View {
  let dismissing: Bool
  let onCheckItOut: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    BoldTheme.FlatCard {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("New").font(BoldTheme.Fonts.body(13, weight: .bold)).foregroundColor(BoldTheme.Colors.green)
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
        Text("Pro Ball Pickems is here").font(BoldTheme.Fonts.body(18, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
        Text("Pick every Pro Ball game's winner each week — no spreads, just wins. Play in a group, chase the leaderboard.")
          .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
        Button("Check it out", action: onCheckItOut)
          .buttonStyle(SupSecondaryButtonStyle(fullWidth: false))
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
