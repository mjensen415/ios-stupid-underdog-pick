import SwiftUI
import Supabase

struct MagicLinkView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.supabaseClient) private var client
  @State private var email = ""
  @State private var isSent = false
  @State private var errorMessage: String?
  @State private var isLoading = false

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
          Button {
            dismiss()
          } label: {
            Text("← Close")
              .font(BoldTheme.Fonts.body(14))
              .foregroundColor(BoldTheme.Colors.textDim)
          }
          .padding(.bottom, 24)

          SupIcon(variant: .football)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 8)
            .padding(.bottom, 22)

          Text("SKIP THE\nPASSWORD.")
            .font(BoldTheme.Fonts.display(40))
            .lineSpacing(-4)
            .foregroundColor(BoldTheme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)

          Text("Drop your email. We'll send a link that signs you straight in.")
            .font(BoldTheme.Fonts.body(15))
            .foregroundColor(BoldTheme.Colors.textDim)
            .padding(.top, 8)
            .padding(.bottom, 26)

          BoldMonoLabel(text: "EMAIL").padding(.bottom, 7)
          BoldTextField(text: $email, placeholder: "you@school.edu", keyboardType: .emailAddress, textContentType: .emailAddress)
            .padding(.bottom, 20)

          BoldPrimaryButton(title: "SEND LINK", isLoading: isLoading, disabled: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            Task { await send() }
          }

          if isSent {
            Text("Check your email.")
              .font(BoldTheme.Fonts.body(13, weight: .medium))
              .foregroundColor(BoldTheme.Colors.gold)
              .padding(.top, 16)
          }
          if let errorMessage {
            Text(errorMessage)
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(.red)
              .padding(.top, 16)
          }
        }
        .padding(24)
        .frame(maxWidth: 440)
      }
    }
  }

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
      // Without an explicit redirectTo, Supabase falls back to the
      // project's Site URL (the website), so the link opens Safari
      // logged in instead of coming back into the app. Same custom
      // scheme already used for Google/Apple sign-in.
      guard let redirect = URL(string: "sup://underdog") else { throw URLError(.badURL) }
      try await AuthService(client: client).sendMagicLink(to: email, redirectTo: redirect)
      isSent = true
    } catch {
      errorMessage = "Couldn't send the link. Try again."
    }
  }
}
