import SwiftUI
import Supabase

struct SignUpView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  @State private var email = ""
  @State private var password = ""
  @State private var errorMessage: String?
  @State private var isLoading = false

  var body: some View {
    Form {
      Section("Sign Up") {
        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
        SecureField("Password", text: $password)
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        Button {
          Task { await signUp() }
        } label: { Text(isLoading ? "Signing up…" : "Create Account") }
        .disabled(isLoading)
      }
    }
    .navigationTitle("Sign Up")
  }

  private func signUp() async {
    isLoading = true
    defer { isLoading = false }
    do {
      guard let client else { throw URLError(.notConnectedToInternet) }
      let auth = AuthService(client: client)
      try await auth.signUp(email: email, password: password)
      // After sign up, try fetching current session
      if let session = try? await client.auth.session {
        appState.session = session
      }
      dismiss()
    } catch {
      errorMessage = "Couldn’t create the account. Try a different email/password."
    }
  }
}

