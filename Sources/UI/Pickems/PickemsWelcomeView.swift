import SwiftUI

// Shown at the Pickems entry point for anyone not yet in a group that
// plays Pickems -- picking isn't group-gated server-side, but the product
// intent is that the first thing you do here is get into a group, not
// stumble into a pick grid with nowhere for it to show up.
struct PickemsWelcomeView: View {
  var onJoinedOrCreated: () async -> Void

  @State private var showCreate = false
  @State private var showJoin = false

  private let bullets = [
    "Pick a winner for every game on the board, every week.",
    "Score 1 point for each correct pick.",
    "Standings are per-group -- no site-wide leaderboard, just bragging rights among your crew.",
    "Weekly ties break on a tiebreaker guess: the combined score of that week's last game, closest without going over.",
  ]

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 20) {
          VStack(spacing: 4) {
            Text("NFL · NEW")
              .font(BoldTheme.Fonts.mono(10, weight: .semibold))
              .tracking(1.2)
              .foregroundColor(BoldTheme.Colors.green)
            Text("PRO BALL PICKEMS")
              .font(BoldTheme.Fonts.display(38))
              .foregroundColor(BoldTheme.Colors.text)
              .multilineTextAlignment(.center)
            Text("Pick the winner of every NFL game, every week. 1 point per correct pick — no spreads, no favorites, just wins.")
              .font(BoldTheme.Fonts.body(15))
              .foregroundColor(BoldTheme.Colors.textDim)
              .multilineTextAlignment(.center)
              .padding(.top, 6)
          }
          .padding(.top, 24)

          VStack(alignment: .leading, spacing: 10) {
            Text("HOW IT WORKS")
              .font(BoldTheme.Fonts.body(11, weight: .bold))
              .foregroundColor(BoldTheme.Colors.goldDeep)
              .tracking(0.6)
            ForEach(bullets, id: \.self) { line in
              HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundColor(BoldTheme.Colors.green)
                Text(line)
                  .font(BoldTheme.Fonts.body(13.5))
                  .foregroundColor(BoldTheme.Colors.textDim)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(18)
          .background(BoldTheme.Colors.glassStrong)
          .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
          .clipShape(RoundedRectangle(cornerRadius: 16))

          Text("Pickems is played in groups. Create one and invite your friends, or join one that's already playing.")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .multilineTextAlignment(.center)

          VStack(spacing: 10) {
            Button {
              showCreate = true
            } label: {
              Text("Create a Pickems Group")
                .font(BoldTheme.Fonts.display(18))
                .foregroundColor(BoldTheme.Colors.text)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(BoldTheme.Colors.gold)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button {
              showJoin = true
            } label: {
              Text("Join a Group")
                .font(BoldTheme.Fonts.body(14, weight: .bold))
                .foregroundColor(BoldTheme.Colors.text)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
            }
          }
        }
        .padding(20)
      }
    }
    .sheet(isPresented: $showCreate) {
      CreateGroupView(defaultGameType: .pickems) { await onJoinedOrCreated() }
    }
    .sheet(isPresented: $showJoin) {
      JoinGroupView { await onJoinedOrCreated() }
    }
  }
}
