import SwiftUI

struct ToastModifier: ViewModifier {
  @Binding var message: String?
  func body(content: Content) -> some View {
    ZStack {
      content
      if let msg = message {
        VStack {
          Spacer()
          Text(msg)
            .font(.footnote)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(radius: 2)
            .padding(.bottom, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { message = nil }
          }
        }
      }
    }
  }
}

extension View {
  func toast(_ message: Binding<String?>) -> some View {
    self.modifier(ToastModifier(message: message))
  }
}


