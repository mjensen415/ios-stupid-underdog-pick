import SwiftUI

// Read-only counterpart to ProfileView -- shown when tapping another
// player's name (leaderboard rows, group member/leaderboard rows). Only
// surfaces what's actually publicly readable: profiles RLS makes
// display_name/avatar_url public, and leaderboard_totals is public too, but
// the picks table is locked to `user_id = auth.uid()` with no exception --
// nobody can read another user's individual picks, only their season/career
// win-loss/points totals. No account/notifications/delete sections here;
// those only make sense for your own session.
struct PublicProfileView: View {
  let userId: UUID
  @Environment(\.supabaseClient) private var client

  @State private var profile: ProfileRow?
  @State private var careerTotals: CareerTotals?
  @State private var seasonTotals: [TotalsLeaderboardRow] = []
  @State private var streak: Int = 0
  @State private var pickHistory: [PickHistoryRow] = []
  @State private var loadError: String?
  @State private var isLoading = true

  var body: some View {
    Form {
      if let profile {
        Section {
          HStack {
            Spacer()
            VStack(spacing: 10) {
              ZStack {
                if let urlString = profile.avatar_url, let url = URL(string: urlString) {
                  AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: avatarPlaceholder
                    }
                  }
                } else {
                  avatarPlaceholder
                }
              }
              .frame(width: 72, height: 72)
              .clipShape(Circle())
              Text(profile.display_name?.isEmpty == false ? profile.display_name! : "Player")
                .font(BoldTheme.Fonts.body(20, weight: .bold))
                .foregroundColor(BoldTheme.Colors.text)
            }
            Spacer()
          }
          .listRowBackground(BoldTheme.Colors.bgPage)
        }
        .listRowBackground(BoldTheme.Colors.bgPage)

        Section {
          if streak > 0 {
            HStack(spacing: 6) {
              Text("🔥").font(.system(size: 13))
              Text(verbatim: "\(streak)-week streak")
                .font(BoldTheme.Fonts.body(13, weight: .semibold))
                .foregroundColor(BoldTheme.Colors.text)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(BoldTheme.Colors.track)
            .clipShape(Capsule())
            .listRowInsets(EdgeInsets())
            .padding(.horizontal, 16).padding(.top, 4)
          }

          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("All-time record").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
              Text(verbatim: "\(careerTotals?.wins ?? 0)W – \(careerTotals?.losses ?? 0)L")
                .font(BoldTheme.Fonts.display(22))
                .foregroundColor(BoldTheme.Colors.text)
            }
            Spacer()
            if let w = careerTotals?.wins, let l = careerTotals?.losses, w + l > 0 {
              VStack(alignment: .trailing, spacing: 2) {
                // Wins / (wins + losses). SUP scores outright wins only -- covering
                // the spread isn't enough -- so this is a win rate, not a cover rate.
                Text("Win rate").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
                Text(verbatim: "\(Int((Double(w) / Double(w + l) * 100).rounded()))%")
                  .font(BoldTheme.Fonts.display(22))
                  .foregroundColor(BoldTheme.Colors.text)
              }
              Spacer()
            }
            VStack(alignment: .trailing, spacing: 2) {
              Text("Points").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
              Text(formatPoints(careerTotals?.totalPoints))
                .font(BoldTheme.Fonts.display(22))
                .foregroundColor(BoldTheme.Colors.text)
            }
          }
          .padding(.vertical, 4)

          ForEach(seasonTotals) { row in
            HStack {
              Text(verbatim: "\(row.season ?? 0)").foregroundColor(BoldTheme.Colors.text)
              Spacer()
              Text(verbatim: "\(row.wins ?? 0)W-\(row.losses ?? 0)L")
                .font(BoldTheme.Fonts.mono(13))
                .foregroundColor(BoldTheme.Colors.textDim)
              Text(formatPoints(row.totalPoints))
                .font(BoldTheme.Fonts.mono(15, weight: .semibold))
                .foregroundColor(BoldTheme.Colors.text)
                .frame(minWidth: 50, alignment: .trailing)
            }
          }

          if seasonTotals.isEmpty {
            Text("No picks yet this season.").foregroundColor(BoldTheme.Colors.textDim)
          }
        } header: {
          Label("Record", systemImage: "trophy.fill")
        }
        .listRowBackground(BoldTheme.Colors.card)

        Section {
          if pickHistory.isEmpty {
            Text("No locked picks yet. Picks show up here once their game starts.")
              .font(BoldTheme.Fonts.body(14))
              .foregroundColor(BoldTheme.Colors.textDim)
          } else {
            ForEach(pickHistory) { row in
              HStack(spacing: 10) {
                Text(verbatim: "Wk \(row.week)")
                  .font(BoldTheme.Fonts.mono(13))
                  .foregroundColor(BoldTheme.Colors.textDim)
                  .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                  Text(row.pickedTeam?.shortName ?? row.pickedTeam?.name ?? "Unknown")
                    .font(BoldTheme.Fonts.body(15, weight: .semibold))
                    .foregroundColor(BoldTheme.Colors.text)
                  Text(verbatim: "vs \(row.opponent?.shortName ?? row.opponent?.name ?? "Unknown")")
                    .font(BoldTheme.Fonts.body(13))
                    .foregroundColor(BoldTheme.Colors.textDim)
                }
                Spacer()
                if row.isFinal {
                  if row.won {
                    SupPill(text: "Won +\(Int(row.awardedPoints))", kind: .green)
                  } else {
                    SupPill(text: "Lost", kind: .gray)
                  }
                } else {
                  SupPill(text: "Live", kind: .gray)
                }
              }
              .padding(.vertical, 4)
            }
          }
        } header: {
          Label("Pick history", systemImage: "checklist")
        }
        .listRowBackground(BoldTheme.Colors.card)
      } else if let loadError {
        Section {
          Text(loadError).foregroundColor(BoldTheme.Role.lost)
          Button("Try again") { Task { await load() } }
            .foregroundColor(BoldTheme.Colors.text)
        }
        .listRowBackground(BoldTheme.Colors.card)
      } else if isLoading {
        ProgressView().tint(BoldTheme.Colors.text)
          .listRowBackground(BoldTheme.Colors.bgPage)
      }
    }
    .scrollContentBackground(.hidden)
    .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
    .navigationTitle(profile?.display_name?.isEmpty == false ? profile!.display_name! : "Player")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(BoldTheme.Colors.bgPage, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarColorScheme(.light, for: .navigationBar)
    .tint(BoldTheme.Colors.text)
    .task { await load() }
  }

  private var avatarPlaceholder: some View {
    ZStack {
      BoldTheme.Colors.text.opacity(0.08)
      Text(initials)
        .font(BoldTheme.Fonts.body(22, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.text)
    }
  }

  private var initials: String {
    let name = profile?.display_name?.isEmpty == false ? profile!.display_name! : "?"
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap { $0.first }
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }

  private func formatPoints(_ x: Double?) -> String {
    guard let x else { return "0" }
    return x.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(x)) : String(format: "%.1f", x)
  }

  private func load() async {
    isLoading = true
    loadError = nil
    defer { isLoading = false }
    guard let client else { loadError = "Not signed in."; return }
    do {
      let p = try await ProfilesService(client: client).fetchProfile(userId: userId)
      guard let p else {
        await MainActor.run { loadError = "Couldn't find this player." }
        return
      }
      await MainActor.run { profile = p }

      async let career = try? LeaderboardService(client: client).fetchMyCareerTotals(userId: userId)
      async let seasons = try? LeaderboardService(client: client).fetchMySeasonTotals(userId: userId)
      async let ctx = try? ContextService(client: client).getCurrentContext()
      async let streakResult: Int? = {
        guard let ctx = try? await ContextService(client: client).getCurrentContext() else { return nil }
        return try? await LeaderboardService(client: client).fetchStreak(userId: userId, season: ctx.season)
      }()
      let (careerResult, seasonsResult, streakValue, ctxValue) = await (career, seasons, streakResult, ctx)
      var picksResult: [PickHistoryRow] = []
      if let ctxValue {
        picksResult = (try? await LeaderboardService(client: client).fetchPicksHistory(userId: userId, season: ctxValue.season)) ?? []
      }
      await MainActor.run {
        careerTotals = careerResult ?? nil
        seasonTotals = seasonsResult ?? []
        streak = streakValue ?? 0
        pickHistory = picksResult
      }
    } catch {
      await MainActor.run { loadError = "Couldn't load this player's profile." }
    }
  }
}
