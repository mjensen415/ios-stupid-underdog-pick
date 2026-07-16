import SwiftUI

// Shared styling for the Bold-themed auth screens -- mirrors
// winner-circle-dev's src/pages/Auth.tsx (Field/PrimaryButton/MonoLabel).

struct BoldMonoLabel: View {
  let text: String
  var body: some View {
    Text(text)
      .font(BoldTheme.Fonts.mono(11))
      .tracking(0.9)
      .foregroundColor(BoldTheme.Colors.textFaint)
  }
}

struct BoldTextField: View {
  @Binding var text: String
  let placeholder: String
  var isSecure = false
  var keyboardType: UIKeyboardType = .default
  var textContentType: UITextContentType?

  @State private var focused = false

  var body: some View {
    Group {
      if isSecure {
        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(BoldTheme.Colors.textFaint))
      } else {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(BoldTheme.Colors.textFaint))
          .keyboardType(keyboardType)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
      }
    }
    .textContentType(textContentType)
    .font(BoldTheme.Fonts.body(16))
    .foregroundColor(BoldTheme.Colors.text)
    .padding(.horizontal, 16)
    .frame(height: 50)
    .background(focused ? BoldTheme.Colors.gold.opacity(0.06) : BoldTheme.Colors.text.opacity(0.04))
    .overlay(
      RoundedRectangle(cornerRadius: 13)
        .stroke(focused ? BoldTheme.Colors.gold : BoldTheme.Colors.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .onTapGesture { focused = true }
    // SwiftUI has no reliable cross-field focus notification without
    // @FocusState wired at the call site -- approximate the web's focus
    // ring by flipping on tap; call sites needing exact focus tracking
    // should promote this to @FocusState later.
  }
}

struct BoldPrimaryButton: View {
  let title: String
  var isLoading = false
  var disabled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        BoldTheme.HatchOverlay(angle: .degrees(45), color: BoldTheme.Colors.bgPage.opacity(0.09), band: 5, period: 12)
        if isLoading {
          ProgressView().tint(BoldTheme.Colors.bgPage)
        } else {
          Text(title)
            .font(BoldTheme.Fonts.display(22))
            .tracking(0.9)
            .foregroundColor(BoldTheme.Colors.bgPage)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(
        LinearGradient(colors: [Color(hex: 0xFFDD5C), BoldTheme.Colors.gold], startPoint: .top, endPoint: .bottom)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .shadow(color: BoldTheme.Colors.gold.opacity(0.22), radius: 12, y: 6)
    }
    .disabled(disabled || isLoading)
    .opacity((disabled || isLoading) ? 0.7 : 1)
  }
}

struct BoldOAuthButton: View {
  enum Style { case light, glass }
  let style: Style
  let title: String
  var isLoading = false
  let action: () -> Void
  @ViewBuilder let icon: () -> AnyView

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        if isLoading {
          ProgressView().tint(style == .light ? BoldTheme.Colors.bgPage : BoldTheme.Colors.text)
        } else {
          icon()
          Text(title)
            .font(BoldTheme.Fonts.body(15, weight: .bold))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .foregroundColor(style == .light ? BoldTheme.Colors.bgPage : BoldTheme.Colors.text)
      .background(style == .light ? BoldTheme.Colors.text : BoldTheme.Colors.text.opacity(0.05))
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(style == .glass ? BoldTheme.Colors.border : Color.clear, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .disabled(isLoading)
  }
}
