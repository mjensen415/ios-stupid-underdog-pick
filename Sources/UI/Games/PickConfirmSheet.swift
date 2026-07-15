import SwiftUI
import Supabase

struct PickConfirmSheet: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  @Environment(\.dismiss) private var dismiss

  let game: Game
  let teamId: UUID
  let onComplete: (Bool, Error?) -> Void

  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text("Confirm Pick").font(.title2).bold()
        Text("Week \(game.week), Season \(game.season)")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
          Text("Game")
            .font(.headline)
          Text("\(game.awayTeam ?? "Away") @ \(game.homeTeam ?? "Home")")
          Text("Picking: \(selectedTeamName)")
            .foregroundStyle(.primary)
        }

        if let errorMessage { Text(errorMessage).foregroundColor(.red) }

        Button(isSubmitting ? "Submitting…" : "Confirm Pick") {
          Task { await confirm() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting)

        Button("Cancel", role: .cancel) { dismiss() }
        Spacer()
      }
      .padding()
      .navigationTitle("Confirm")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
  }

  private func confirm() async {
    guard let localClient = client else { return }

    isSubmitting = true
    defer { isSubmitting = false }
    do {
      // The pick is *for* `game`, which already carries its own season/week --
      // no need to ask "what's the current season/week" separately (the
      // previous version used Objective-C KVC reflection to grope AppState
      // for a "currentContext"/"context" property that doesn't exist there
      // at all -- AppState only has client/session/startupError, and it
      // doesn't inherit NSObject, so value(forKey:) on it would have
      // crashed at runtime rather than just failing to find the key).
      let picks = PicksService(client: localClient)
      try await picks.upsertPick(gameId: game.id, pickedTeamId: teamId, season: game.season, week: game.week)
      onComplete(true, nil)
      dismiss()
    } catch {
      onComplete(false, error)
      errorMessage = error.localizedDescription
    }
  }

  private var selectedTeamName: String {
    if teamId == game.homeTeamId { return game.homeTeam ?? "Home" }
    if teamId == game.awayTeamId { return game.awayTeam ?? "Away" }
    return "Selected team"
  }
}

