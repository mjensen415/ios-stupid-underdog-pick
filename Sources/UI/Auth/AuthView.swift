import SwiftUI
import Supabase

private enum AuthMode { case signin, signup }

struct AuthView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client

  @State private var mode: AuthMode = .signin
  @State private var email = ""
  @State private var password = ""
  @State private var showPassword = false
  @State private var loading = false
  @State private var googleLoading = false
  @State private var appleLoading = false
  @State private var errorMessage: String?
  @State private var showMagicLink = false

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      RadialGradient(
        colors: [BoldTheme.Colors.green.opacity(0.55), BoldTheme.Colors.bgPage.opacity(0)],
        center: UnitPoint(x: 0.5, y: -0.05),
        startRadius: 0,
        endRadius: 420
      )
      .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SupIcon(variant: .monogram)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 8)
            .padding(.bottom, 22)

          Text(mode == .signin ? "WELCOME BACK,\nDEGENERATE." : "PICK THE\nDOG.")
            .font(BoldTheme.Fonts.display(40))
            .lineSpacing(-4)
            .foregroundColor(BoldTheme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)

          Text(mode == .signin ? "Your streak missed you." : "Bank the points. Brag forever. Free, always.")
            .font(BoldTheme.Fonts.body(15))
            .foregroundColor(BoldTheme.Colors.textDim)
            .padding(.top, 8)
            .padding(.bottom, 26)

          if let errorMessage {
            Text(errorMessage)
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(.red)
              .padding(.bottom, 12)
          }

          BoldOAuthButton(style: .light, title: "Continue with Google", isLoading: googleLoading) {
            Task { await signInWithGoogle() }
          } icon: {
            AnyView(Image("GoogleLogo").resizable().frame(width: 18, height: 18))
          }
          .padding(.bottom, 10)

          BoldOAuthButton(style: .glass, title: "Continue with Apple", isLoading: appleLoading) {
            Task { await signInWithApple() }
          } icon: {
            AnyView(Image(systemName: "apple.logo").font(.system(size: 16)))
          }

          HStack(spacing: 12) {
            Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
            Text("OR").font(BoldTheme.Fonts.mono(11)).tracking(1.1).foregroundColor(BoldTheme.Colors.textFaint)
            Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
          }
          .padding(.vertical, 22)

          BoldMonoLabel(text: "EMAIL").padding(.bottom, 7)
          BoldTextField(text: $email, placeholder: "you@school.edu", keyboardType: .emailAddress, textContentType: .emailAddress)
            .padding(.bottom, 16)

          HStack {
            BoldMonoLabel(text: "PASSWORD")
            Spacer()
            Button(showPassword ? "Hide" : "Show") { showPassword.toggle() }
              .font(BoldTheme.Fonts.body(12))
              .foregroundColor(BoldTheme.Colors.textDim)
          }
          .padding(.bottom, 7)
          BoldTextField(text: $password, placeholder: "••••••••", isSecure: !showPassword, textContentType: .password)

          Button("Use a magic link instead") { showMagicLink = true }
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 10)
            .padding(.bottom, 20)

          BoldPrimaryButton(
            title: mode == .signin ? "SIGN IN" : "CREATE ACCOUNT",
            isLoading: loading,
            disabled: !canSubmit
          ) {
            Task { await submit() }
          }

          HStack(spacing: 4) {
            Text(mode == .signin ? "New to the chaos?" : "Already running a streak?")
              .foregroundColor(BoldTheme.Colors.textDim)
            Button(mode == .signin ? "Create an account" : "Sign in") {
              mode = mode == .signin ? .signup : .signin
              errorMessage = nil
            }
            .foregroundColor(BoldTheme.Colors.gold)
            .fontWeight(.bold)
          }
          .font(BoldTheme.Fonts.body(14))
          .frame(maxWidth: .infinity)
          .padding(.top, 22)
        }
        .padding(24)
        .frame(maxWidth: 440)
      }
    }
    .sheet(isPresented: $showMagicLink) { MagicLinkView() }
  }

  private var canSubmit: Bool {
    client != nil && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
  }

  private func submit() async {
    guard let client else { return }
    loading = true
    errorMessage = nil
    defer { loading = false }

    do {
      let auth = AuthService(client: client)
      if mode == .signup {
        try await auth.signUp(email: email, password: password)
        if let session = try? await client.auth.session {
          appState.session = session
        }
      } else {
        let session = try await auth.signIn(email: email, password: password)
        appState.session = session
      }
    } catch {
      errorMessage = friendlyAuthError(error)
    }
  }

  private func signInWithGoogle() async {
    googleLoading = true
    defer { googleLoading = false }
    do {
      guard let client else { throw URLError(.notConnectedToInternet) }
      let auth = AuthService(client: client)
      guard let redirect = URL(string: "sup://underdog") else { throw URLError(.badURL) }
      let session = try await auth.signInWithGoogle(redirect: redirect)
      appState.session = session
    } catch {
      errorMessage = "Google sign-in didn't complete. Try again."
    }
  }

  private func signInWithApple() async {
    appleLoading = true
    defer { appleLoading = false }
    do {
      guard let client else { throw URLError(.notConnectedToInternet) }
      let auth = AuthService(client: client)
      guard let redirect = URL(string: "sup://underdog") else { throw URLError(.badURL) }
      let session = try await auth.signInWithApple(redirect: redirect)
      appState.session = session
    } catch {
      errorMessage = "Apple sign-in didn't complete. Try again."
    }
  }

  private func friendlyAuthError(_ error: Error) -> String {
    let raw = error.localizedDescription
    if raw.localizedCaseInsensitiveContains("invalid login") ||
       raw.localizedCaseInsensitiveContains("invalid email or password") {
      return "Invalid email or password. Please try again."
    }
    if raw.localizedCaseInsensitiveContains("network") {
      return "Network error. Check your connection and try again."
    }
    return mode == .signup ? "Couldn't create the account. Try a different email/password." : raw
  }
}
