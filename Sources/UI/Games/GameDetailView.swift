import SwiftUI
import Supabase

struct GameDetailView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  let game: Game

  @State private var showConfirm: Bool = false
  @State private var selectedTeamId: UUID?
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("\(game.awayTeam ?? "Away") @ \(game.homeTeam ?? "Home")")
          .font(.title)
          .fontWeight(.bold)
        Text(DateFormatting.formatKickoff(game.startTime)).foregroundStyle(.secondary)
        if let line = game.bettingLine { Text(line).font(.headline) }

        if let errorMessage { Text(errorMessage).foregroundColor(.red) }

        VStack(spacing: 12) {
          Button(action: { selectedTeamId = game.awayTeamId; showConfirm = true }) {
            Text("Pick \(game.awayTeam ?? "Away")")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(isLocked)

          Button(action: { selectedTeamId = game.homeTeamId; showConfirm = true }) {
            Text("Pick \(game.homeTeam ?? "Home")")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(.secondary)
          .disabled(isLocked)

          if isLocked { Text("This game is locked. Picks close at kickoff.").foregroundColor(.orange) }
        }
      }
      .padding()
    }
    .navigationTitle("Game")
    .sheet(isPresented: $showConfirm) {
      if let selectedTeamId { PickConfirmSheet(game: game, teamId: selectedTeamId, onComplete: handlePickComplete) }
    }
  }

  private var isLocked: Bool {
    if game.picksLocked == true { return true }
    return game.startTime < Date()
  }

  private func handlePickComplete(_ success: Bool, _ error: Error?) {
    if success { Haptics.success() }
    if let error { errorMessage = error.localizedDescription }
  }
}
