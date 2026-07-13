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
    // Capture environment values to avoid dynamic member lookup issues
    let localAppState = appState
    let localClient = client

    // Resolve context from AppState using a helper to accommodate different property names
    func resolveContext(from appState: AppState) -> (season: Int, week: Int)? {
      // Prefer a `currentContext` property if available via key-path; otherwise, try `context`.
      // Since we can't reflect types safely here, use optional chaining on known names via closures.
      // Replace these accessors with your actual AppState API if different.
      if let ctx = (appState as AnyObject).value(forKey: "currentContext") as? NSObject,
         let season = ctx.value(forKey: "season") as? Int,
         let week = ctx.value(forKey: "week") as? Int {
        return (season, week)
      }
      if let ctx = (appState as AnyObject).value(forKey: "context") as? NSObject,
         let season = ctx.value(forKey: "season") as? Int,
         let week = ctx.value(forKey: "week") as? Int {
        return (season, week)
      }
      return nil
    }

    guard let localClient else { return }
    guard let context = resolveContext(from: localAppState) else { return }

    isSubmitting = true
    defer { isSubmitting = false }
    do {
      // Upsert via PicksService using DI; we need season/week from context
      let picks = PicksService(client: localClient)
      try await picks.upsertPick(gameId: game.id, pickedTeamId: teamId, season: context.season, week: context.week)
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

