import SwiftUI
import Supabase

// Mirrors src/pages/Home.tsx on web -- same sections, same corrected card
// model (picks have no group_id, so there's exactly one "this week's pick"
// status for the whole account, not one per contest/group).

private enum Sport: String { case cfb, nfl }

@MainActor
final class HomeViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var season: Int?
  @Published var week: Int?
  @Published var isOffseason = false
  @Published var myPick: Pick?
  @Published var firstKickoff: Date?
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
  @Published var firstKickoffCfb: Date?
  @Published var firstKickoffNfl: Date?
  @Published var cfbOffseason = false
  @Published var nflOffseason = false
  @Published var profile: ProfileRow?

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func load(userId: UUID, sport: String) async {
    guard let client else { return }
    isLoading = true
    defer { isLoading = false }

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
    async let kickoffTask = fetchFirstKickoff(client: client, season: season, week: week, sport: sport)
    async let rankTask = try? LeaderboardService(client: client).fetchMyRank(userId: userId, season: season, sport: sport)
    async let groupsTask = try? GroupsService(client: client).fetchMyGroups()
    async let discoverTask = try? GroupsService(client: client).fetchDiscoverGroups(limit: 6)
    async let recapTask = fetchRecap(client: client, season: season, week: week, sport: sport)
    async let streakTask = try? LeaderboardService(client: client).fetchStreak(userId: userId, season: season, sport: sport)

    myPick = await pickTask ?? nil
    firstKickoff = await kickoffTask
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
      async let cfbKickoffTask = fetchFirstKickoff(client: client, season: cfbCtx.season, week: cfbCtx.week, sport: "cfb")
      async let cfbOffseasonTask = checkOffseason(client: client, season: cfbCtx.season, sport: "cfb")
      myPickCfb = await cfbPickTask ?? nil
      firstKickoffCfb = await cfbKickoffTask
      cfbOffseason = await cfbOffseasonTask
    }
    if let nflCtx {
      async let nflPickTask = try? PicksService(client: client).myPick(season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      async let nflKickoffTask = fetchFirstKickoff(client: client, season: nflCtx.season, week: nflCtx.week, sport: "nfl")
      async let nflOffseasonTask = checkOffseason(client: client, season: nflCtx.season, sport: "nfl")
      myPickNfl = await nflPickTask ?? nil
      firstKickoffNfl = await nflKickoffTask
      nflOffseason = await nflOffseasonTask
    }
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

  private func fetchFirstKickoff(client: SupabaseClient, season: Int, week: Int, sport: String) async -> Date? {
    struct Row: Decodable { let start_time: Date }
    guard let res = try? await client
      .from("v_games_named")
      .select("start_time")
      .eq("season", value: season)
      .eq("week", value: week)
      .eq("sport", value: sport)
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
  @State private var sport: Sport = .cfb
  @State private var showCreateGroup = false
  @State private var showJoinGroup = false
  @State private var showInvitePicker = false
  @State private var pushGroupSlug: String?
  @State private var showPickems = false
  @State private var shareURL: URL?
  @State private var showShareSheet = false
  @State private var dismissingIntro = false

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
            sportToggle
            quickActionsRow
            contestsSection
            groupsSection
            discoverSection
            recapSection
          }
          .padding(18)
        }
      }
      .navigationBarHidden(true)
      .task {
        if let client, let userId = appState.session?.user.id {
          viewModel.configure(client: client)
          await viewModel.load(userId: userId, sport: sport.rawValue)
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
      .navigationDestination(isPresented: $showPickems) {
        PickemsView()
      }
      .onChange(of: appState.requestedPickems) { _, requested in
        guard requested else { return }
        showPickems = true
        appState.requestedPickems = false
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
    HStack(spacing: 34) {
      quickAction(label: "Create Group", systemImage: "plus", gold: true) { showCreateGroup = true }
      quickAction(label: "Join Group", systemImage: "link", gold: false) { showJoinGroup = true }
      quickAction(label: "Invite Friends", systemImage: "square.and.arrow.up", gold: false, action: handleInviteTap)
    }
    .padding(.bottom, 20)
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
        Text(verbatim: viewModel.isOffseason ? "OFFSEASON" : "WEEK \(formatWeekLabel(viewModel.week ?? 0)) · \(sport.rawValue.uppercased()) \(viewModel.season ?? 0)")
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
    .padding(.bottom, 16)
  }

  private var sportToggle: some View {
    HStack(spacing: 4) {
      ForEach([Sport.cfb, Sport.nfl], id: \.self) { s in
        let active = s == sport
        Button {
          sport = s
        } label: {
          Text(s == .cfb ? "🏈 CFB" : "🏈 PRO BALL")
            .font(BoldTheme.Fonts.body(13, weight: .bold))
            .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? Color.white : Color.clear)
            .cornerRadius(10)
            .shadow(color: active ? Color(hex: 0x142A1C).opacity(0.14) : .clear, radius: 6, y: 3)
        }
      }
    }
    .padding(4)
    .background(Color(hex: 0x16241B).opacity(0.07))
    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .cornerRadius(13)
    .padding(.bottom, 20)
  }

  // ── Your Contests -- one row per game this account is actually playing,
  // so someone in only one game never has to wade through the others to
  // find their pick. Mirrors web's Home.tsx exactly. ──────────────────────
  private var contestsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if showPickemsIntroBanner {
        PickemsIntroBanner(dismissing: dismissingIntro) {
          Task { await dismissPickemsIntro() }
          showPickems = true
        } onDismiss: {
          Task { await dismissPickemsIntro() }
        }
      }

      Text(hasAnyContest ? "YOUR CONTESTS" : "GET STARTED")
        .font(BoldTheme.Fonts.mono(10, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)

      if hasAnyContest {
        VStack(spacing: 10) {
          if underdogCfbActive {
            ContestRow(
              title: "Underdog Pick — CFB",
              sublabel: viewModel.cfbOffseason ? "Offseason" : "Week \(formatWeekLabel(viewModel.cfbContext?.week ?? 0)) · \(viewModel.cfbContext?.season ?? 0)",
              isOffseason: viewModel.cfbOffseason,
              picked: viewModel.myPickCfb != nil,
              countdown: countdownText(myPick: viewModel.myPickCfb, kickoff: viewModel.firstKickoffCfb)
            ) {
              appState.requestedSport = "cfb"
              appState.requestedTab = 1
            }
          }
          if underdogProBallActive {
            ContestRow(
              title: "Underdog Pick — Pro Ball",
              sublabel: viewModel.nflOffseason ? "Offseason" : "Week \(formatWeekLabel(viewModel.nflContext?.week ?? 0)) · \(viewModel.nflContext?.season ?? 0)",
              isOffseason: viewModel.nflOffseason,
              picked: viewModel.myPickNfl != nil,
              countdown: countdownText(myPick: viewModel.myPickNfl, kickoff: viewModel.firstKickoffNfl)
            ) {
              appState.requestedSport = "nfl"
              appState.requestedTab = 1
            }
          }
          if pickemsActive {
            ContestRow(
              title: "Pro Ball Pickems",
              sublabel: viewModel.nflOffseason ? "Offseason" : "Week \(viewModel.nflContext?.week ?? 0) · \(viewModel.nflContext?.season ?? 0)",
              isOffseason: viewModel.nflOffseason,
              picked: false,
              countdown: nil
            ) {
              showPickems = true
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
              showPickems = true
            }
          }
        }
      }
    }
    .padding(.bottom, 22)
  }

  private func countdownText(myPick: Pick?, kickoff: Date?) -> String? {
    guard myPick == nil, let kickoff else { return nil }
    let diff = kickoff.timeIntervalSinceNow
    guard diff > 0 else { return "Locked" }
    let hours = Int(diff / 3600)
    let minutes = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
    if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
    return "\(hours)h \(minutes)m"
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

      Button { showCreateGroup = true } label: {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(BoldTheme.Colors.gold).frame(width: 42, height: 42)
              .overlay { BoldTheme.HatchOverlay().clipShape(Circle()) }
            Text("+").font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.text)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text("Start a group").font(BoldTheme.Fonts.body(14.5, weight: .heavy)).foregroundColor(BoldTheme.Colors.text)
            Text("Invite friends, run your own pool, set your own bragging rights.")
              .font(BoldTheme.Fonts.body(12))
              .foregroundColor(BoldTheme.Colors.textDim)
          }
          Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.28))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BoldTheme.Colors.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .cornerRadius(16)
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
  let title: String
  let sublabel: String
  let isOffseason: Bool
  let picked: Bool
  let countdown: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      BoldTheme.GlassCard(strong: true, radius: 16, padding: 14) {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text(title).font(BoldTheme.Fonts.body(14.5, weight: .heavy)).foregroundColor(BoldTheme.Colors.text)
            Text(sublabel).font(BoldTheme.Fonts.mono(10.5)).foregroundColor(BoldTheme.Colors.textDim)
          }
          Spacer()
          statusView
        }
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var statusView: some View {
    if isOffseason {
      Text("Offseason")
        .font(BoldTheme.Fonts.body(11.5, weight: .bold))
        .foregroundColor(BoldTheme.Colors.textDim)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(BoldTheme.Colors.track)
        .clipShape(Capsule())
    } else if picked {
      Text("Picked ✓")
        .font(BoldTheme.Fonts.body(11.5, weight: .bold))
        .foregroundColor(BoldTheme.Colors.green)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(BoldTheme.Colors.green.opacity(0.13))
        .overlay(Capsule().strokeBorder(BoldTheme.Colors.green.opacity(0.28)))
        .clipShape(Capsule())
    } else if let countdown {
      Text(verbatim: countdown == "Locked" ? "Locked" : "Locks in \(countdown)")
        .font(BoldTheme.Fonts.body(11.5, weight: .bold))
        .foregroundColor(Color(hex: 0xA6402A))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color(hex: 0xC6402A).opacity(0.13))
        .overlay(Capsule().strokeBorder(Color(hex: 0xC6402A).opacity(0.28)))
        .clipShape(Capsule())
        .fixedSize()
    } else {
      Text("Make Pick →").font(BoldTheme.Fonts.display(15)).foregroundColor(BoldTheme.Colors.goldDeep)
    }
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
      : "Straight-up picks on every NFL game, every week. Play in a group, chase the leaderboard."
  }
  private var badges: [String] { game == .underdog ? ["CFB · Free", "Pro Ball · Entry fee"] : ["NFL · Free to start"] }
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
        Text("Pick every NFL game's winner each week — no spreads, just wins. Play in a group, chase the leaderboard.")
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
