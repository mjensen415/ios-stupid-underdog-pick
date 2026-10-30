import AuthenticationServices
import SwiftUI
import Supabase

// .forgot mirrors the web Auth.tsx's third mode: same card, email only,
// sends a password-reset link instead of signing in.
enum AuthMode { case signin, signup, forgot }

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
  /// Raw nonce for the Apple request in flight (Apple gets its SHA-256).
  @State private var appleNonce: String?
  @State private var errorMessage: String?
  @State private var showMagicLink = false
  /// Set once a reset link was requested; the forgot card swaps its button
  /// for a confirmation instead of a toast (no toast system on this screen).
  @State private var resetSentTo: String?
  /// Read once per appearance -- AuthView is rebuilt after every sign-out,
  /// so this is always the method from the most recent sign-in.
  @State private var lastUsed: LoginMethod? = LastLoginStore.lastMethod()

  /// Defaults to sign-in. Taking a starting mode lets the snapshot tests
  /// render the forgot-password card without driving taps.
  init(initialMode: AuthMode = .signin) {
    _mode = State(initialValue: initialMode)
  }

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
        .ignoresSafeArea()

      ScrollView {
        BoldTheme.GlassCard(radius: 28, padding: 32) {
        VStack(alignment: .leading, spacing: 0) {
          if mode == .forgot {
            Button {
              setMode(.signin)
            } label: {
              Text("← Back to sign in")
                .font(BoldTheme.Fonts.body(14))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
            .padding(.bottom, 24)
          }

          SupIcon(variant: mode == .forgot ? .football : .monogram)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding(.bottom, 22)

          Text(title)
            .font(BoldTheme.Fonts.body(32, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)

          Text(subtitle)
            .font(BoldTheme.Fonts.body(15))
            .foregroundColor(BoldTheme.Colors.textDim)
            .padding(.top, 8)
            .padding(.bottom, 26)

          if let errorMessage {
            Text(errorMessage)
              .font(BoldTheme.Fonts.body(14))
              .foregroundColor(BoldTheme.Role.lost)
              .padding(.bottom, 12)
          }

          if mode != .forgot {
            BoldOAuthButton(style: .light, title: "Continue with Google", isLoading: googleLoading) {
              Task { await signInWithGoogle() }
            } icon: {
              AnyView(Image("GoogleLogo").resizable().frame(width: 18, height: 18))
            }
            .lastUsedTab(lastUsed == .google)
            .padding(.bottom, 10)

            // Apple's own button (HIG: system button, not a look-alike).
            // Black reads clearly on the light card; the app is light-only.
            SignInWithAppleButton(mode == .signup ? .signUp : .continue) { request in
              let nonce = AppleNonce.random()
              appleNonce = nonce
              configureAppleRequest(request, rawNonce: nonce, scopes: [.fullName, .email])
            } onCompletion: { result in
              Task { await finishAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            // The system button keeps the label it was created with.
            .id(mode == .signup)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
              if appleLoading {
                RoundedRectangle(cornerRadius: 14).fill(.black)
                ProgressView().tint(.white)
              }
            }
            .allowsHitTesting(!appleLoading && client != nil)
            .lastUsedTab(lastUsed == .apple)

            HStack(spacing: 12) {
              Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
              Text("or").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
              Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
            }
            .padding(.vertical, 22)
          }

          HStack(spacing: 8) {
            BoldMonoLabel(text: "Email")
            // Web shows the email tag only while signing in (not on
            // create-account or reset), as an inline pill rather than a tab.
            if mode == .signin && lastUsed == .email {
              SupPill(text: "Last used", kind: .gray)
            }
          }
          .padding(.bottom, 7)
          BoldTextField(text: $email, placeholder: "you@school.edu", keyboardType: .emailAddress, textContentType: .emailAddress)
            .padding(.bottom, 16)

          if mode != .forgot {
            HStack {
              BoldMonoLabel(text: "Password")
              Spacer()
              Button(showPassword ? "Hide" : "Show") { showPassword.toggle() }
                .font(BoldTheme.Fonts.body(12))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
            .padding(.bottom, 7)
            BoldTextField(text: $password, placeholder: "••••••••", isSecure: !showPassword, textContentType: .password)

            // Stacked and right-aligned like the web's lone "Forgot it?" link;
            // side by side, the two links wrapped mid-phrase on a phone.
            VStack(alignment: .trailing, spacing: 10) {
              // Same copy as web. Only offered while signing in -- someone
              // creating an account has no password to forget yet.
              if mode == .signin {
                Button("Forgot it? Happens to the best of us.") { setMode(.forgot) }
              }
              Button("Use a magic link instead") { showMagicLink = true }
            }
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 10)
            .padding(.bottom, 20)
          } else {
            Spacer().frame(height: 4)
          }

          if mode == .forgot, let sentTo = resetSentTo {
            resetSentConfirmation(sentTo)
          } else {
            BoldPrimaryButton(title: cta, isLoading: loading, disabled: !canSubmit) {
              Task { await submit() }
            }
          }

          if mode == .forgot {
            (Text("Heads up: ").foregroundColor(BoldTheme.Colors.green).fontWeight(.bold)
              + Text("the reset link won't stay valid forever. Like your last upset pick, don't sit on it."))
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(BoldTheme.Colors.textDim)
              .lineSpacing(3)
              .padding(16)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(BoldTheme.Colors.green.opacity(0.14))
              .overlay(RoundedRectangle(cornerRadius: 13).stroke(BoldTheme.Colors.green.opacity(0.25), lineWidth: 1))
              .clipShape(RoundedRectangle(cornerRadius: 13))
              .padding(.top, 20)
          } else {
          HStack(spacing: 4) {
            Text(mode == .signin ? "New to the chaos?" : "Already running a streak?")
              .foregroundColor(BoldTheme.Colors.textDim)
            Button(mode == .signin ? "Create an account" : "Sign in") {
              setMode(mode == .signin ? .signup : .signin)
            }
            .foregroundColor(BoldTheme.Colors.green)
            .fontWeight(.bold)
          }
          .font(BoldTheme.Fonts.body(14))
          .frame(maxWidth: .infinity)
          .padding(.top, 22)
          }
        }
        }
        .frame(maxWidth: 440)
        .padding(24)
      }
    }
    .sheet(isPresented: $showMagicLink) { MagicLinkView() }
  }

  // Copy per mode -- the forgot strings are the web's Auth.tsx verbatim.
  private var title: String {
    switch mode {
    case .signin: return "Back for more."
    case .signup: return "Pick the dog."
    case .forgot: return "Lost the plot?"
    }
  }

  private var subtitle: String {
    switch mode {
    case .signin: return "Your streak missed you."
    case .signup: return "Win the points. Brag forever. Free, always."
    case .forgot: return "Drop your email. We'll send a reset link so you can get back to losing responsibly."
    }
  }

  private var cta: String {
    switch mode {
    case .signin: return "Sign in"
    case .signup: return "Create account"
    case .forgot: return "Send reset link"
    }
  }

  private var canSubmit: Bool {
    let hasEmail = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return client != nil && hasEmail && (mode == .forgot || !password.isEmpty)
  }

  private func setMode(_ newMode: AuthMode) {
    mode = newMode
    errorMessage = nil
    resetSentTo = nil
  }

  private func resetSentConfirmation(_ sentTo: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Reset link sent")
        .font(BoldTheme.Fonts.body(15, weight: .bold))
        .foregroundColor(BoldTheme.Colors.green)
      // Supabase doesn't reveal whether the address has an account, so
      // neither do we -- "if" keeps this honest for a mistyped email.
      Text("If \(sentTo) has an account, a reset link is on its way. Open it on this phone or any browser, set a new password, then sign in here with it.")
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.text)
        .fixedSize(horizontal: false, vertical: true)
      Button("Back to sign in") { setMode(.signin) }
        .font(BoldTheme.Fonts.body(14, weight: .bold))
        .foregroundColor(BoldTheme.Colors.green)
        .padding(.top, 6)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.6))
    .overlay(RoundedRectangle(cornerRadius: 13).stroke(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 13))
  }

  private func submit() async {
    guard let client else { return }
    loading = true
    errorMessage = nil
    defer { loading = false }

    do {
      let auth = AuthService(client: client)
      switch mode {
      case .signup:
        try await auth.signUp(email: email, password: password)
        if let session = try? await client.auth.session {
          LastLoginStore.remember(user: session.user)
          appState.session = session
        }
      case .signin:
        let session = try await auth.signIn(email: email, password: password)
        LastLoginStore.remember(user: session.user)
        appState.session = session
      case .forgot:
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        try await auth.sendPasswordReset(email: trimmed)
        resetSentTo = trimmed
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
      LastLoginStore.remember(user: session.user)
      appState.session = session
    } catch {
      errorMessage = "Google sign-in didn't complete. Try again."
    }
  }

  private func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
    errorMessage = nil
    let nonce = appleNonce
    appleNonce = nil
    switch result {
    case .failure(let error):
      // Closing the Apple sheet isn't an error worth showing.
      if !AppleCredential.isCancel(error) {
        errorMessage = "Apple sign-in didn't complete. Try again."
      }
    case .success(let authorization):
      appleLoading = true
      defer { appleLoading = false }
      do {
        guard let client else { throw URLError(.notConnectedToInternet) }
        guard let nonce else { throw AppleCredential.Failure.missingToken }
        let credential = try AppleCredential(authorization: authorization, rawNonce: nonce)
        let session = try await AuthService(client: client).signInWithApple(credential: credential)
        LastLoginStore.remember(user: session.user)
        appState.session = session
      } catch {
        #if DEBUG
        print("[Auth][Apple][ERR]", error.localizedDescription)
        #endif
        errorMessage = "Apple sign-in didn't complete. Try again."
      }
    }
  }

  private func friendlyAuthError(_ error: Error) -> String {
    if let reset = error as? AuthService.PasswordResetError {
      // Supabase's built-in sender is capped at ~3 emails/hour project-wide
      // (known issue; custom SMTP is the fix) -- say so plainly.
      return reset.isRateLimited
        ? "Too many reset emails just went out. Wait a bit and try again, or use a magic link."
        : "Couldn't send the reset link. Check the email and try again."
    }
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

// "LAST USED" tab that sits on top of the sign-in button this device used
// last -- the web's <LastUsed> wrapper: a green tab 22pt tall, inset 18pt
// each side. Web tucks the tab's bottom under the button; here it stops at
// the button's edge instead, so it never covers part of Apple's system
// button (HIG: don't alter or obscure it) or the Google chip.
private struct LastUsedTab: ViewModifier {
  let show: Bool

  func body(content: Content) -> some View {
    if show {
      ZStack(alignment: .top) {
        Text("Last used")
          .font(BoldTheme.Fonts.body(12, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
          .padding(.top, 5)
          .frame(maxWidth: .infinity, minHeight: 22, alignment: .top)
          .background(BoldTheme.Colors.track)
          .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
          .padding(.horizontal, 18)
          .accessibilityHidden(true)
        content
          .padding(.top, 22)
          .accessibilityHint("Last used on this device")
      }
    } else {
      content
    }
  }
}

private extension View {
  func lastUsedTab(_ show: Bool) -> some View { modifier(LastUsedTab(show: show)) }
}
