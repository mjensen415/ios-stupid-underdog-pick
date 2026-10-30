import SwiftUI

// Shown at the Pickems entry point for anyone not yet in a group that
// plays Pickems. Picking isn't group-gated server-side: shared picks (no
// group) score on the global Pickems board, so the first choice is the
// Global group (one tap, onPlayGlobal), with Create/Join below it.
struct PickemsWelcomeView: View {
  var onPlayGlobal: (() -> Void)? = nil
  var onJoinedOrCreated: () async -> Void

  @State private var showCreate = false
  @State private var showJoin = false

  private let bullets = [
    "Pick a winner for every game on the board, every week.",
    "Score 1 point for each correct pick.",
    "Everyone who plays is on the Global board. A group adds a private board for your crew.",
    "Weekly ties break on a tiebreaker guess: the combined score of that week's last game, closest without going over.",
  ]

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 20) {
          VStack(spacing: 4) {
            Text("Pro Ball · new")
              .font(BoldTheme.Fonts.body(13, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.textDim)
            Text("Pro Ball Pickems")
              .font(BoldTheme.Fonts.body(30, weight: .bold))
              .foregroundColor(BoldTheme.Colors.text)
              .multilineTextAlignment(.center)
            Text("Pick the winner of every Pro Ball game, every week. 1 point per correct pick — no spreads, no favorites, just wins.")
              .font(BoldTheme.Fonts.body(15))
              .foregroundColor(BoldTheme.Colors.textDim)
              .multilineTextAlignment(.center)
              .padding(.top, 6)
          }
          .padding(.top, 24)

          VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
              .font(BoldTheme.Fonts.body(16, weight: .bold))
              .foregroundColor(BoldTheme.Colors.text)
            ForEach(bullets, id: \.self) { line in
              HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundColor(BoldTheme.Colors.textDim)
                Text(line)
                  .font(BoldTheme.Fonts.body(13.5))
                  .foregroundColor(BoldTheme.Colors.textDim)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(BoldTheme.Space.cardPad)
          .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))

          Text("\(GlobalGroups.tagline) Or create a group and invite your friends, or join one that's already playing.")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .multilineTextAlignment(.center)

          VStack(spacing: 10) {
            if let onPlayGlobal {
              // The one primary action.
              Button(action: onPlayGlobal) {
                Text(GlobalGroups.joinCTA)
              }
              .buttonStyle(SupPrimaryButtonStyle())
              .accessibilityIdentifier("pickemsPlayGlobalButton")
            }
            Button {
              showCreate = true
            } label: {
              Text("Create a Pickems group")
            }
            .buttonStyle(SupSecondaryButtonStyle())
            Button {
              showJoin = true
            } label: {
              Text("Join a group")
            }
            .buttonStyle(SupSecondaryButtonStyle())
          }
        }
        .padding(BoldTheme.Space.margin)
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
