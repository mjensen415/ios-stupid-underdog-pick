import SwiftUI

struct CreateGroupView: View {
  @Environment(\.supabaseClient) private var client
  @Environment(\.dismiss) private var dismiss
  var onCreated: () async -> Void

  @State private var name = ""
  @State private var description = ""
  @State private var isPrivate = true
  @State private var sport: GroupSport = .both
  @State private var gameType: GroupGameType
  @State private var isSubmitting = false
  @State private var errorText: String?

  // Preselects the Game picker -- the Pickems welcome screen wants
  // "Pickems" already picked rather than making someone re-choose what
  // they just came here to do.
  init(defaultGameType: GroupGameType = .underdog, onCreated: @escaping () async -> Void) {
    self.onCreated = onCreated
    self._gameType = State(initialValue: defaultGameType)
  }

  private var nameValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 40 }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Group name", text: $name)
          Text(verbatim: "\(name.count)/40 characters")
            .font(BoldTheme.Fonts.mono(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
        Section {
          TextField("Description (optional)", text: $description, axis: .vertical)
            .lineLimit(3...6)
        }
        Section {
          Picker("Game", selection: $gameType) {
            Text("Underdog Pick").tag(GroupGameType.underdog)
            Text("Pickems").tag(GroupGameType.pickems)
            Text("Both").tag(GroupGameType.both)
          }
          .pickerStyle(.segmented)
          Text(
            gameType == .underdog
              ? "This group plays the classic one-pick-a-week underdog game."
              : gameType == .pickems
              ? "This group plays Pro Ball Pickems -- pick every NFL game's winner."
              : "This group plays both games -- separate leaderboards for each."
          )
          .font(BoldTheme.Fonts.body(12))
          .foregroundColor(BoldTheme.Colors.textDim)
        }
        if gameType != .pickems {
          Section {
            Picker("Sport", selection: $sport) {
              Text("CFB").tag(GroupSport.cfb)
              Text("Pro Ball").tag(GroupSport.nfl)
              Text("Both").tag(GroupSport.both)
            }
            .pickerStyle(.segmented)
            Text(
              sport == .both
                ? "Members can view either sport's underdog-pick leaderboard."
                : "The underdog-pick game is scoped to \(sport == .cfb ? "CFB" : "Pro Ball") only."
            )
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
          }
        }
        Section {
          Toggle("Private Group", isOn: $isPrivate)
          Text("Members need approval to join")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        if let errorText {
          Text(errorText).foregroundColor(.red).font(BoldTheme.Fonts.body(13))
        }
      }
      .navigationTitle("Create Group")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSubmitting {
            ProgressView()
          } else {
            Button("Create") { Task { await submit() } }.disabled(!nameValid)
          }
        }
      }
    }
  }

  private func submit() async {
    guard let client, nameValid else { return }
    isSubmitting = true; errorText = nil
    defer { isSubmitting = false }
    do {
      _ = try await GroupsService(client: client).createGroup(
        name: name.trimmingCharacters(in: .whitespaces),
        description: description.isEmpty ? nil : description,
        isPrivate: isPrivate,
        sport: sport,
        gameType: gameType
      )
      await onCreated()
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
