import SwiftUI

// Circular initials avatar for groups/members that have no avatar_url yet.
struct AvatarInitials: View {
  let name: String
  var size: CGFloat = 40

  private var initials: String {
    let parts = name.split(separator: " ").prefix(2)
    let letters = parts.compactMap { $0.first }.map { String($0) }
    return letters.isEmpty ? "?" : letters.joined().uppercased()
  }

  var body: some View {
    Circle()
      .fill(BoldTheme.Colors.green.opacity(0.4))
      .overlay(
        Text(initials)
          .font(BoldTheme.Fonts.body(size * 0.38, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
      )
      .frame(width: size, height: size)
  }
}
