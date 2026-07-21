import SwiftUI
import Supabase

// Mirrors src/pages/Home.tsx on web -- same sections, same corrected card
// model (picks have no group_id, so there's exactly one "this week's pick"
// status for the whole account, not one per contest/group).

private enum Sport { case cfb, nfl }

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

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func load(userId: UUID) async {
    guard let client else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let ctx = try await ContextService(client: client).getCurrentContext()
      season = ctx.season
      week = ctx.week

      struct CountRow: Decodable { let id: UUID }
      let gameCountRes = try await client
        .from("games")
        .select("id")
        .eq("season", value: ctx.season)
        .limit(1)
        .execute()
      let games = (try? JSONDecoder().decode([CountRow].self, from: gameCountRes.data)) ?? []
      isOffseason = games.isEmpty
    } catch {
      isOffseason = true
    }

    guard let season, let week, !isOffseason else { return }

    async let pickTask = try? PicksService(client: client).myPick(season: season, week: week)
    async let kickoffTask = fetchFirstKickoff(client: client, season: season, week: week)
    async let rankTask = try? LeaderboardService(client: client).fetchMyRank(userId: userId, season: season)
    async let groupsTask = try? GroupsService(client: client).fetchMyGroups()
    async let discoverTask = try? GroupsService(client: client).fetchDiscoverGroups(limit: 6)
    async let recapTask = fetchRecap(client: client, season: season, week: week)

    myPick = await pickTask ?? nil
    firstKickoff = await kickoffTask
    myRank = await rankTask ?? nil
    myGroups = await groupsTask ?? []
    discoverGroups = await discoverTask ?? []
    recap = await recapTask
  }

  private func fetchFirstKickoff(client: SupabaseClient, season: Int, week: Int) async -> Date? {
    struct Row: Decodable { let start_time: Date }
    guard let res = try? await client
      .from("v_games_named")
      .select("start_time")
      .eq("season", value: season)
      .eq("week", value: week)
      .order("start_time", ascending: true)
      .limit(1)
      .execute()
    else { return nil }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withFallback
    return try? dec.decode([Row].self, from: res.data).first?.start_time
  }

  private func fetchRecap(client: SupabaseClient, season: Int, week: Int) async -> [RecapHit] {
    guard week > 1 else { return [] }
    let res = try? await client
      .from("v_recap_underdogs_hit")
      .select("game_id, match_description, line_display, score_display, abs_spread")
      .eq("season", value: season)
      .eq("week", value: week - 1)
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

            if sport == .nfl {
              nflComingSoon
            } else {
              pickStatusCard
              groupsSection
              discoverSection
              recapSection
            }
          }
          .padding(18)
        }
      }
      .navigationBarHidden(true)
      .task {
        if let client, let userId = appState.session?.user.id {
          viewModel.configure(client: client)
          await viewModel.load(userId: userId)
        }
      }
      .refreshable {
        if let userId = appState.session?.user.id {
          await viewModel.load(userId: userId)
        }
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
        Text(verbatim: viewModel.isOffseason ? "OFFSEASON" : "WEEK \(viewModel.week ?? 0) · CFB \(viewModel.season ?? 0)")
          .font(BoldTheme.Fonts.mono(10, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.green)
        Text("WELCOME BACK.")
          .font(BoldTheme.Fonts.display(19))
          .foregroundColor(BoldTheme.Colors.text)
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
          Text(s == .cfb ? "🏈 CFB" : "🏈 NFL")
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

  private var nflComingSoon: some View {
    BoldTheme.GlassCard(radius: 16, padding: 32) {
      VStack(spacing: 8) {
        Text("NFL UNDERDOG")
          .font(BoldTheme.Fonts.display(26))
          .foregroundColor(BoldTheme.Colors.gold)
        Text("Coming soon. Switch back to CFB to keep picking.")
          .font(BoldTheme.Fonts.body(14))
          .foregroundColor(BoldTheme.Colors.textDim)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var pickStatusCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("THIS WEEK").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)

      BoldTheme.GlassCard(strong: true, radius: 18, padding: 16) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("GLOBAL · CFB").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.green)
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
        Text("MY GROUPS").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
        Spacer()
        Button {
          appState.requestedTab = 4 // Groups tab
        } label: {
          Text("See all →").font(BoldTheme.Fonts.body(12, weight: .bold)).foregroundColor(BoldTheme.Colors.green)
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
        ForEach(viewModel.myGroups.prefix(3)) { g in
          Button { appState.requestedTab = 4 } label: {
            BoldTheme.GlassCard(strong: true, radius: 14, padding: 16) {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(g.name).font(BoldTheme.Fonts.body(14, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
                  Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")")
                    .font(BoldTheme.Fonts.body(11.5))
                    .foregroundColor(BoldTheme.Colors.textDim)
                }
                Spacer()
                if let rank = g.rank {
                  Text(verbatim: "#\(rank)").font(BoldTheme.Fonts.display(18)).foregroundColor(BoldTheme.Colors.green)
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
