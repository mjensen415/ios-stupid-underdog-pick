import SwiftUI

func hideKeyboard() {
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
  // Tap-away-to-dismiss for screens with a text field (search bars,
  // numeric tiebreaker input). `simultaneousGesture` so it never blocks
  // taps on rows, buttons, or swipe actions underneath.
  func dismissKeyboardOnTap() -> some View {
    simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
  }
}
