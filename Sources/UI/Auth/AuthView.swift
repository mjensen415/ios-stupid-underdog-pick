import SwiftUI
import Supabase

struct AuthView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  @State private var showEmailLogin = false
  @State private var showSignUp = false
  @State private var showMagicLink = false
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: AppTheme.Spacing.lg) {
        Spacer()
        Text("Stupid Underdog Pick")
          .font(.largeTitle).bold()

        if let errorMessage { Text(errorMessage).foregroundColor(.red) }

        Button("Log In") { showEmailLogin = true }
          .buttonStyle(.borderedProminent)

        Button("Sign Up") { showSignUp = true }

        Button("Magic Link") { showMagicLink = true }

        Button {
          Task { await signInWithGoogle() }
        } label: {
          Label("Continue with Google", systemImage: "globe")
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)

        if isLoading {
          ProgressView().padding(.top, AppTheme.Spacing.sm)
        }

        Spacer()
      }
      .padding()
      .sheet(isPresented: $showEmailLogin) { EmailLoginView().environmentObject(appState) }
      .sheet(isPresented: $showSignUp) { SignUpView().environmentObject(appState) }
      .sheet(isPresented: $showMagicLink) { MagicLinkView() }
    }
  }

  private func signInWithGoogle() async {
    isLoading = true
    defer { isLoading = false }
    do {
      guard let client else { throw URLError(.notConnectedToInternet) }
      let auth = AuthService(client: client)
      guard let redirect = URL(string: "sup://underdog") else { throw URLError(.badURL) }
      _ = try await auth.signInWithGoogle(redirect: redirect)
    } catch {
      errorMessage = "Sign-in didn’t complete. Try again."
    }
  }
}
