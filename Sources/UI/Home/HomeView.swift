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
  @State private var shareURL: URL?
  @State private var showShareSheet = false

  // groups-create-invite is admin-only server-side (assertIsGroupAdmin) --
  // only owner/admin rows can actually generate a link.
  private var inviteableGroups: [MyGroup] {
    viewModel.myGroups.filter { $0.my_role == .owner || $0.my_role == .admin }
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
            pickStatusCard
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
        Text(verbatim: viewModel.isOffseason ? "OFFSEASON" : "WEEK \(viewModel.week ?? 0) · \(sport.rawValue.uppercased()) \(viewModel.season ?? 0)")
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

  private var pickStatusCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("THIS WEEK").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)

      BoldTheme.GlassCard(strong: true, radius: 18, padding: 16) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(verbatim: "GLOBAL · \(sport.rawValue.uppercased())").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.green)
            Spacer()
            if let rank = viewModel.myRank {
              Text(verbatim: "#\(rank.rank) of \(rank.totalPlayers)")
                .font(BoldTheme.Fonts.mono(11))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
          }

          Text(statusHeadline)
            .font(BoldTheme.Fonts.display(24))
            .foregroundColor(BoldTheme.Colors.text)

          if !viewModel.isOffseason {
            statusPill
            pickButton
          }
        }
      }
    }
    .padding(.bottom, 22)
  }

  private var statusHeadline: String {
    if viewModel.isOffseason { return "SEASON HASN'T STARTED" }
    return viewModel.myPick != nil ? "YOU'RE IN THIS WEEK" : "MAKE YOUR PICK"
  }

  @ViewBuilder
  private var statusPill: some View {
    if viewModel.myPick != nil {
      Text("Picked ✓")
        .font(BoldTheme.Fonts.body(11.5, weight: .bold))
        .foregroundColor(BoldTheme.Colors.green)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(BoldTheme.Colors.green.opacity(0.13))
        .overlay(Capsule().strokeBorder(BoldTheme.Colors.green.opacity(0.28)))
        .clipShape(Capsule())
    } else if let countdown = countdownText {
      Text(verbatim: "Locks in \(countdown)")
        .font(BoldTheme.Fonts.body(11.5, weight: .bold))
        .foregroundColor(Color(hex: 0xA6402A))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color(hex: 0xC6402A).opacity(0.13))
        .overlay(Capsule().strokeBorder(Color(hex: 0xC6402A).opacity(0.28)))
        .clipShape(Capsule())
    }
  }

  private var countdownText: String? {
    guard viewModel.myPick == nil, let kickoff = viewModel.firstKickoff else { return nil }
    let diff = kickoff.timeIntervalSinceNow
    guard diff > 0 else { return "Locked" }
    let hours = Int(diff / 3600)
    let minutes = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
    if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
    return "\(hours)h \(minutes)m"
  }

  private var pickButton: some View {
    Button {
      appState.requestedSport = sport.rawValue
      appState.requestedTab = 1 // Games tab
    } label: {
      ZStack {
        if viewModel.myPick == nil {
          BoldTheme.HatchOverlay()
        }
        Text(viewModel.myPick != nil ? "VIEW PICK" : "MAKE YOUR PICK")
          .font(BoldTheme.Fonts.display(17))
          .foregroundColor(BoldTheme.Colors.text)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 42)
      .background(
        viewModel.myPick != nil
          ? AnyView(Color.white.opacity(0.85))
          : AnyView(LinearGradient(colors: [Color(hex: 0xFFDD5C), Color(hex: 0xFFD23A)], startPoint: .top, endPoint: .bottom))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(viewModel.myPick != nil ? BoldTheme.Colors.border : Color.clear, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .shadow(color: viewModel.myPick != nil ? .clear : Color(hex: 0xFFD23A).opacity(0.35), radius: 10, y: 5)
    }
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
