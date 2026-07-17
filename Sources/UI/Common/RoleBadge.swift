import SwiftUI

// Native port of src/components/groups/RoleBadge.tsx.
struct RoleBadge: View {
  let role: GroupRole

  private var label: String {
    switch role {
    case .owner: return "Owner"
    case .admin: return "Admin"
    case .member: return "Member"
    case .pending: return "Pending"
    }
  }

  private var icon: String {
    switch role {
    case .owner: return "crown.fill"
    case .admin: return "shield.fill"
    case .member: return "person.fill"
    case .pending: return "clock.fill"
    }
  }

  private var filled: Bool { role == .owner || role == .admin }
  private var dashed: Bool { role == .pending }

  private var background: Color {
    switch role {
    case .owner: return BoldTheme.Colors.gold
    case .admin: return BoldTheme.Colors.green
    case .member, .pending: return .clear
    }
  }

  private var foreground: Color {
    switch role {
    case .owner: return BoldTheme.Colors.bgPage
    case .admin: return BoldTheme.Colors.text
    case .member, .pending: return BoldTheme.Colors.textDim
    }
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon).font(.system(size: 10, weight: .semibold))
      Text(label).font(BoldTheme.Fonts.body(11, weight: .semibold))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .foregroundColor(foreground)
    .background(filled ? background : Color.clear)
    .overlay(
      Capsule()
        .strokeBorder(
          filled ? Color.clear : BoldTheme.Colors.border,
          style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : [])
        )
    )
    .clipShape(Capsule())
  }
}
