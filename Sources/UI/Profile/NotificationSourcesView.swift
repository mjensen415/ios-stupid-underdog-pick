import SwiftUI
import Supabase

/// Which contests and groups a player hears from. The Notifications
/// section's toggles pick the *kind* of push (reminders, kickoff, results,
/// recap); this screen picks *where from*. Off = a notification_mutes row;
/// send-push drops muted players server-side.
struct NotificationSourcesView: View {
  @Environment(\.supabaseClient) private var client

  @State private var mutes: Set<String> = []
  @State private var groups: [MyGroup] = []
  @State private var loaded = false
  @State private var errorMessage: String?

  private static let contests: [(key: String, title: String, detail: String)] = [
    ("cfb", "College Underdog", "Reminders, kickoff, results and recaps for your CFB pick"),
    ("nfl", "Pro Ball Underdog", "Reminders, kickoff, results and recaps for your Pro Ball pick"),
  ]

  var body: some View {
    List {
      Section {
        ForEach(Self.contests, id: \.key) { c in
          Toggle(isOn: binding(scope: "contest", key: c.key)) {
            VStack(alignment: .leading, spacing: 2) {
              Text(c.title)
              Text(c.detail)
                .font(BoldTheme.Fonts.body(12))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
          }
        }
      } header: {
        Text("Contests")
      }
      .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

      Section {
        if !loaded {
          ProgressView().tint(BoldTheme.Colors.gold)
        } else if groups.isEmpty {
          Text("You're not in any Underdog Pick groups yet.")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
        } else {
          ForEach(groups) { g in
            Toggle(g.name, isOn: binding(scope: "group", key: g.group_id.uuidString.lowercased()))
          }
        }
      } header: {
        Text("Groups")
      } footer: {
        Text("Group recaps, plus alerts for picks you made only inside that group. Your main pick follows the contest switch above.")
      }
      .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

      if let errorMessage {
        Section {
          Text(errorMessage).foregroundColor(.red)
        }
        .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
      }
    }
    .scrollContentBackground(.hidden)
    .background(BoldTheme.Colors.bgPage)
    .navigationTitle("Notify me about")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private func binding(scope: String, key: String) -> Binding<Bool> {
    Binding(
      get: { !mutes.contains("\(scope)|\(key)") },
      set: { on in
        let id = "\(scope)|\(key)"
        if on { mutes.remove(id) } else { mutes.insert(id) }
        guard let client else { return }
        Task {
          do {
            try await PushService(client: client).setMuted(scope: scope, key: key, muted: !on)
            await MainActor.run { errorMessage = nil }
          } catch {
            await MainActor.run {
              // Put the switch back so it never shows a state the server doesn't have.
              if on { mutes.insert(id) } else { mutes.remove(id) }
              errorMessage = "Couldn't save that change. Try again."
            }
          }
        }
      }
    )
  }

  private func load() async {
    guard let client else { return }
    async let m = try? PushService(client: client).fetchMutes()
    async let g = try? GroupsService(client: client).fetchMyGroups()
    let (mutesValue, groupsValue) = await (m, g)
    await MainActor.run {
      mutes = mutesValue ?? []
      groups = (groupsValue ?? [])
        .filter { $0.game_type != .pickems && $0.my_role != .pending }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      loaded = true
    }
  }
}
