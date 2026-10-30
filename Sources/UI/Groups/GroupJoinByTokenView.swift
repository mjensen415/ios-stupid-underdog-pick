import SwiftUI

private enum JoinState: Equatable {
  case idle
  case joining
  case success(slug: String, name: String, alreadyMember: Bool)
  case failure(String)
}

struct GroupJoinByTokenView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  @Environment(\.dismiss) private var dismiss
  let token: String

  @State private var state: JoinState = .idle
  @State private var showSignIn = false

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()

        VStack(spacing: 20) {
          Spacer()

          switch state {
          case .idle, .joining:
            ProgressView("Joining group…").tint(BoldTheme.Colors.text).foregroundColor(BoldTheme.Colors.textDim)
          case .success(_, let name, let alreadyMember):
            // GREEN, not gold -- "Go to Group" below is this screen's one
            // primary-action CTA; this icon is just a status indicator (and
            // green reads as "success" here too).
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundColor(BoldTheme.Colors.green)
            Text(alreadyMember ? "Already in!" : "You're in!")
              .font(BoldTheme.Fonts.body(24, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
            Text(name).font(BoldTheme.Fonts.body(15)).foregroundColor(BoldTheme.Colors.textDim)
            Button("Go to group") { dismiss() }
              .buttonStyle(SupPrimaryButtonStyle(fullWidth: false))
          case .failure(let message):
            Image(systemName: "xmark.circle.fill").font(.system(size: 48)).foregroundColor(BoldTheme.Role.lost)
            Text("This invite doesn't work").font(BoldTheme.Fonts.body(24, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
            Text(message).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
            Button("Close") { dismiss() }
              .buttonStyle(SupSecondaryButtonStyle(fullWidth: false))
          }

          Spacer()

          if appState.session == nil {
            VStack(spacing: 10) {
              Text("Sign in to accept this invite").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
              Button("Sign in to join") { showSignIn = true }
                .buttonStyle(SupPrimaryButtonStyle(fullWidth: false))
            }
          }
        }
        .padding(24)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .sheet(isPresented: $showSignIn) {
        MagicLinkView()
      }
      .onChange(of: appState.session) { _, newSession in
        if newSession != nil, state == .idle { Task { await join() } }
      }
      .task {
        if appState.session != nil { await join() }
      }
    }
  }

  private func join() async {
    guard let client else { return }
    state = .joining
    do {
      let result = try await GroupsService(client: client).joinByToken(inviteToken: token)
      state = .success(slug: result.slug, name: result.name, alreadyMember: result.status == "already_member")
    } catch let GroupsService.ServiceError.api(message) {
      state = .failure(message == "invalid_or_expired" ? "This invite is no longer valid." : message)
    } catch {
      state = .failure("An unexpected error occurred.")
    }
  }
}
