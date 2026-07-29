import SwiftUI
import Supabase

// One-time, skippable first-run flow: favorite team -> first pick -> group.
// Shown by RootView as a full-screen cover when profiles.has_onboarded is
// false, dismissed (and never shown again) once any exit path completes.
struct OnboardingFlowView: View {
  let client: SupabaseClient
  @EnvironmentObject var appState: AppState
  @Binding var isPresented: Bool

  @State private var step = 1
  @State private var teams: [Team] = []
  @State private var search = ""
  @State private var activeConference: String?
  @State private var selectedTeamId: UUID?
  @State private var existingPick: Pick?
  @State private var season: Int?
  @State private var week: Int?
  @State private var saving = false

  private var haptic: UISelectionFeedbackGenerator { UISelectionFeedbackGenerator() }

  // Mirrors web's CONFERENCE_ORDER (src/hooks/useCfbNews.ts) so the
  // drill-down reads the same on both platforms -- Power 4 + notable
  // Group of 5 first, National catch-all last.
  private static let conferenceOrder = [
    "SEC", "Big Ten", "Big 12", "ACC",
    "American Athletic", "Mountain West", "Sun Belt", "Conference USA", "MAC", "Independent",
    "National",
  ]

  private var teamsByConference: [String: [Team]] {
    Dictionary(grouping: teams) { $0.conference ?? "Independent" }
  }

  private var searchResults: [Team] {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return [] }
    return teams.filter { $0.name.lowercased().contains(q) }
  }

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      BoldTheme.AmbientBlobs()

      VStack(spacing: 20) {
        HStack {
          HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { s in
              Capsule()
                .fill(s <= step ? BoldTheme.Colors.green : BoldTheme.Colors.border)
                .frame(width: s == step ? 24 : 8, height: 6)
            }
          }
          Spacer()
          Button {
            Task { await finish() }
          } label: {
            HStack(spacing: 4) {
              Text("Skip onboarding")
              Image(systemName: "xmark")
            }
            .font(BoldTheme.Fonts.mono(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)

        BoldTheme.GlassCard(strong: true, radius: 16, padding: 20) {
          switch step {
          case 1: teamStep
          case 2: pickStep
          default: groupStep
          }
        }
        .padding(.horizontal, 20)

        Spacer()
      }
    }
    .task {
      do {
        let ctx = try await ContextService(client: client).getCurrentContext()
        season = ctx.season
        week = ctx.week
        if let s = season, let w = week {
          existingPick = try? await PicksService(client: client).myPick(season: s, week: w)
        }
        teams = try await loadTeams()
      } catch {
        teams = (try? await loadTeams()) ?? []
      }
    }
  }

  // Full CFB team set, fetched once -- small enough (~130 rows) to group
  // client-side by conference for the drill-down rather than paginate.
  private func loadTeams() async throws -> [Team] {
    let res = try await client.from("teams")
      .select("id, name, short_name, logo_url, conference")
      .eq("sport", value: "cfb")
      .order("name")
      .execute()
    return try JSONDecoder().decode([Team].self, from: res.data)
  }

  @ViewBuilder private var teamStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("STEP 1 OF 3").font(BoldTheme.Fonts.mono(11, weight: .semibold)).foregroundColor(BoldTheme.Colors.green)
      Text("Got a team you follow?").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
      Text("We'll use it to flag when they're a live dog. Totally optional.")
        .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)

      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundColor(BoldTheme.Colors.textFaint)
        TextField("Or search for a team…", text: $search)
          .font(BoldTheme.Fonts.body(14))
      }
      .padding(10)
      .background(Color.white.opacity(0.6))
      .cornerRadius(8)

      teamPickerList

      Button {
        step = 2
      } label: {
        Text("Continue").frame(maxWidth: .infinity)
      }
      .buttonStyle(GoldButtonStyle())
    }
  }

  private func teamRow(_ t: Team) -> some View {
    Button {
      haptic.selectionChanged()
      selectedTeamId = t.id
      Task { try? await ProfilesService(client: client).setFavoriteTeam(t.id) }
    } label: {
      HStack(spacing: 10) {
        AsyncImage(url: t.logo_url.flatMap { URL(string: $0) }) { phase in
          if case .success(let img) = phase { img.resizable().scaledToFit() }
          else { Circle().fill(BoldTheme.Colors.track) }
        }
        .frame(width: 24, height: 24)
        Text(t.name).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.text)
        Spacer()
        if selectedTeamId == t.id {
          Image(systemName: "checkmark").foregroundColor(BoldTheme.Colors.green)
        }
      }
      .padding(.vertical, 10).padding(.horizontal, 4)
      .background(selectedTeamId == t.id ? BoldTheme.Colors.green.opacity(0.1) : Color.clear)
    }
  }

  // Search flattens across every conference for people who already know
  // the name; otherwise it's a two-level drill-down (conference, then team
  // within it) instead of one long flat list.
  @ViewBuilder private var teamPickerList: some View {
    ScrollView {
      VStack(spacing: 0) {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
          ForEach(searchResults) { t in
            teamRow(t)
            Divider().opacity(0.3)
          }
          if searchResults.isEmpty {
            Text("No teams found.")
              .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textFaint)
              .padding(.vertical, 16)
          }
        } else if let activeConference {
          Button {
            self.activeConference = nil
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
              Text(activeConference)
            }
            .font(BoldTheme.Fonts.body(12, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.green)
          }
          .padding(.vertical, 8).padding(.horizontal, 4)
          .frame(maxWidth: .infinity, alignment: .leading)

          ForEach(teamsByConference[activeConference] ?? []) { t in
            teamRow(t)
            Divider().opacity(0.3)
          }
        } else {
          ForEach(Self.conferenceOrder.filter { !(teamsByConference[$0] ?? []).isEmpty }, id: \.self) { conf in
            Button {
              activeConference = conf
            } label: {
              HStack {
                Text(conf).font(BoldTheme.Fonts.body(14, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
                Spacer()
                Text("\(teamsByConference[conf]?.count ?? 0)")
                  .font(BoldTheme.Fonts.mono(11)).foregroundColor(BoldTheme.Colors.textFaint)
                Image(systemName: "chevron.right").foregroundColor(BoldTheme.Colors.textFaint)
              }
              .padding(.vertical, 10).padding(.horizontal, 4)
            }
            Divider().opacity(0.3)
          }
        }
      }
    }
    .frame(maxHeight: 220)
    .background(Color.white.opacity(0.4))
    .cornerRadius(8)
  }

  @ViewBuilder private var pickStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("STEP 2 OF 3").font(BoldTheme.Fonts.mono(11, weight: .semibold)).foregroundColor(BoldTheme.Colors.green)
      Text("Make your first pick").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)

      if existingPick != nil {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.circle.fill").foregroundColor(BoldTheme.Colors.green)
          Text("You're in — you've already got a pick locked in this week.")
            .font(BoldTheme.Fonts.body(13, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
        }
        .padding(14)
        .background(BoldTheme.Colors.green.opacity(0.1))
        .cornerRadius(8)

        Button { step = 3 } label: {
          Text("Continue").frame(maxWidth: .infinity)
        }
        .buttonStyle(GoldButtonStyle())
      } else {
        Text("Pick one underdog. If they cover the spread, you bank those points toward the season leaderboard.")
          .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)

        Button {
          Task {
            await finish()
            appState.requestedTab = 1 // Games tab
          }
        } label: {
          Text("Take me to this week's dogs").frame(maxWidth: .infinity)
        }
        .buttonStyle(GoldButtonStyle())

        Button { step = 3 } label: {
          Text("I'll pick later").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  @ViewBuilder private var groupStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("STEP 3 OF 3").font(BoldTheme.Fonts.mono(11, weight: .semibold)).foregroundColor(BoldTheme.Colors.green)
      Text("SUP is better with rivals").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
      Text("Start a group and invite the people you actually want to beat — or join one with a code.")
        .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)

      Button {
        Task {
          await finish()
          appState.requestedTab = 4 // Groups tab
        }
      } label: {
        HStack { Image(systemName: "person.2.fill"); Text("Start or join a group") }.frame(maxWidth: .infinity)
      }
      .buttonStyle(GoldButtonStyle())

      Button {
        Task { await finish() }
      } label: {
        Text("Maybe later").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textFaint)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func finish() async {
    guard !saving else { return }
    saving = true
    try? await ProfilesService(client: client).completeOnboarding()
    // Ask for push permission once, right as onboarding wraps -- after the
    // user has already seen real value (team, pick, or group), not at cold
    // launch. Existing users who upgrade past this build never see
    // onboarding again, so they get the same ask from a manual button in
    // Profile > Notifications instead.
    _ = await PushService(client: client).requestPermission()
    isPresented = false
  }
}


private struct GoldButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(BoldTheme.Fonts.body(14, weight: .semibold))
      .padding(.vertical, 13)
      .background(BoldTheme.Colors.gold)
      .foregroundColor(BoldTheme.Colors.text)
      .cornerRadius(8)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
  }
}
