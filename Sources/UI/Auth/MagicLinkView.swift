import SwiftUI
import Supabase

struct MagicLinkView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var email = ""
  @State private var isSent = false
  @State private var errorMessage: String?
  @State private var isLoading = false

  var body: some View {
    Form {
      Section("Magic Link") {
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        if isSent { Text("Check your email").foregroundColor(.green) }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        Button {
          Task { await send() }
        } label: { Text(isLoading ? "Sending…" : "Send Link") }
        .disabled(isLoading)
      }
    }
    .navigationTitle("Magic Link")
  }

  @Environment(\.supabaseClient) private var client

  private func send() async {
    errorMessage = nil
    isSent = false
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Please enter your email."
      return
    }

    isLoading = true
    defer { isLoading = false }
    do {
      guard let client else { throw URLError(.notConnectedToInternet) }
      try await AuthService(client: client).sendMagicLink(to: email, redirectTo: nil)
      isSent = true
    } catch {
      errorMessage = "Couldn’t send the link. Try again."
    }
  }
}

