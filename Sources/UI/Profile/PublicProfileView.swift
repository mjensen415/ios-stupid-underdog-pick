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
                .font(BoldTheme.Fonts.display(20))
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
                .font(BoldTheme.Fonts.mono(12, weight: .semibold))
                .foregroundColor(BoldTheme.Colors.goldDeep)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(BoldTheme.Colors.goldDeep.opacity(0.1))
            .clipShape(Capsule())
            .listRowInsets(EdgeInsets())
            .padding(.horizontal, 16).padding(.top, 4)
          }

          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("ALL-TIME RECORD").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
              Text(verbatim: "\(careerTotals?.wins ?? 0)W – \(careerTotals?.losses ?? 0)L")
                .font(BoldTheme.Fonts.display(22))
                .foregroundColor(BoldTheme.Colors.text)
            }
            Spacer()
            if let w = careerTotals?.wins, let l = careerTotals?.losses, w + l > 0 {
              VStack(alignment: .trailing, spacing: 2) {
                Text("COVER RATE").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
                Text(verbatim: "\(Int((Double(w) / Double(w + l) * 100).rounded()))%")
                  .font(BoldTheme.Fonts.display(22))
                  .foregroundColor(BoldTheme.Colors.green)
              }
              Spacer()
            }
            VStack(alignment: .trailing, spacing: 2) {
              Text("POINTS").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
              Text(formatPoints(careerTotals?.totalPoints))
                .font(BoldTheme.Fonts.display(22))
                .foregroundColor(BoldTheme.Colors.goldDeep)
            }
          }
          .padding(.vertical, 4)

          ForEach(seasonTotals) { row in
            HStack {
              Text(verbatim: "\(row.season ?? 0)").foregroundColor(BoldTheme.Colors.text)
              Spacer()
              Text(verbatim: "\(row.wins ?? 0)W-\(row.losses ?? 0)L")
                .font(BoldTheme.Fonts.mono(12))
                .foregroundColor(BoldTheme.Colors.textFaint)
              Text(formatPoints(row.totalPoints))
                .font(BoldTheme.Fonts.display(16))
                .foregroundColor(BoldTheme.Colors.green)
                .frame(minWidth: 50, alignment: .trailing)
            }
          }

          if seasonTotals.isEmpty {
            Text("No picks yet this season.").foregroundColor(BoldTheme.Colors.textFaint)
          }
        } header: {
          Label("Trophy Case", systemImage: "trophy.fill")
        }
        .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
      } else if let loadError {
        Section {
          Text(loadError).foregroundColor(.red)
          Button("Retry") { Task { await load() } }
            .foregroundColor(BoldTheme.Colors.goldDeep)
        }
        .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
      } else if isLoading {
        ProgressView().tint(BoldTheme.Colors.gold)
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
    .tint(BoldTheme.Colors.gold)
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
      async let streakResult: Int? = {
        guard let ctx = try? await ContextService(client: client).getCurrentContext() else { return nil }
        return try? await LeaderboardService(client: client).fetchStreak(userId: userId, season: ctx.season)
      }()
      let (careerResult, seasonsResult, streakValue) = await (career, seasons, streakResult)
      await MainActor.run {
        careerTotals = careerResult ?? nil
        seasonTotals = seasonsResult ?? []
        streak = streakValue ?? 0
      }
    } catch {
      await MainActor.run { loadError = "Couldn't load this player's profile." }
    }
  }
}
