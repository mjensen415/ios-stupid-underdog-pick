import SwiftUI

// Native port of src/components/groups/PrivacyChip.tsx.
struct PrivacyChip: View {
  let isPrivate: Bool

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: isPrivate ? "lock.fill" : "globe")
        .font(.system(size: 10, weight: .semibold))
      Text(isPrivate ? "Private" : "Public")
        .font(BoldTheme.Fonts.body(11, weight: .semibold))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .foregroundColor(BoldTheme.Colors.textDim)
    .overlay(Capsule().strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(Capsule())
  }
}
