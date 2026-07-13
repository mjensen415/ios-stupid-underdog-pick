import SwiftUI
import Supabase

@MainActor
struct EmailLoginView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var appState: AppState

  @State private var email: String = ""
  @State private var password: String = ""
  @State private var isLoading = false
  @State private var errorText: String?
#if DEBUG
  @State private var showDiagnostics = false
#endif

  var body: some View {
    VStack(spacing: 16) {
      Form {
        Section("Sign in") {
          TextField("Email", text: $email)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocorrectionDisabled(true)
            .submitLabel(.next)

          SecureField("Password", text: $password)
            .textContentType(.password)
            .submitLabel(.go)
            .onSubmit { Task { await signIn() } }

          if let e = errorText {
            Text(e)
              .foregroundStyle(.red)
              .font(.footnote)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("auth_error_text")
          }

          Button {
            Task { await signIn() }
          } label: {
            if isLoading {
              ProgressView()
            } else {
              Text("Sign In")
                .frame(maxWidth: .infinity, alignment: .center)
            }
          }
          .disabled(!canSubmit || isLoading)
          .accessibilityIdentifier("auth_sign_in_button")
        }
      }

      #if DEBUG
      DebugAuthConfigOverlay()
        .padding(.horizontal)
      Button("Diagnostics") { showDiagnostics = true }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("auth_diagnostics_button")
        .sheet(isPresented: $showDiagnostics) {
          AuthDiagnosticsSheet()
        }
      #endif
    }
    .navigationTitle("Login")
  }

  private var canSubmit: Bool {
    client != nil &&
    !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !password.isEmpty
  }

  private func signIn() async {
    guard let client else {
      errorText = "Client not available. Check SUPABASE_URL / SUPABASE_ANON_KEY."
      return
    }
    isLoading = true
    errorText = nil
    defer { isLoading = false }

    do {
      let auth = AuthService(client: client)
      let session = try await auth.signIn(email: email, password: password)
      appState.session = session
      #if DEBUG
      print("[Auth] signed in user:", session.user.email ?? session.user.id.uuidString)
      #endif
    } catch {
      errorText = friendlyAuthError(error)
      #if DEBUG
      print("[Auth][ERR]", error.localizedDescription)
      #endif
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
    return raw
  }
}

#if DEBUG
private struct DebugAuthConfigOverlay: View {
  @Environment(\.supabaseClient) private var client

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Debug: Auth Configuration")
        .font(.footnote).bold()
      if let client {
        Text("Client: OK").font(.footnote)
      } else {
        Text("Client: MISSING").foregroundStyle(.red).font(.footnote)
      }
      Text("Check Info.plist keys SUPABASE_URL / SUPABASE_ANON_KEY if missing.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }
}
#endif

#if DEBUG
private struct AuthDiagnosticsSheet: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text("Diagnostics").font(.title3.bold())
        Group {
          Text("Bundle Identifier: \(Bundle.main.bundleIdentifier ?? "unknown")")
          if let urlStr = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String {
            Text("Info.plist SUPABASE_URL: \(urlStr.replacingOccurrences(of: "https://", with: "https://…"))")
          } else {
            Text("Info.plist SUPABASE_URL: (missing)").foregroundStyle(.red)
          }
          Text("ENV Keys Present:")
          let env = ProcessInfo.processInfo.environment
          ForEach(env.keys.filter { $0.uppercased().contains("SUPABASE") }.sorted(), id: \.self) { k in
            let val = env[k] ?? ""
            let red = val.count > 12 ? String(val.prefix(6)) + "…" + String(val.suffix(4)) : val
            Text("  \(k) = \(red)")
              .font(.footnote)
          }
        }
        .font(.footnote)
        .textSelection(.enabled)
        Text("Tip: Scheme → Run → Arguments → Environment Variables. Or set Info.plist keys.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .presentationDetents([.medium, .large])
  }
}
#endif

