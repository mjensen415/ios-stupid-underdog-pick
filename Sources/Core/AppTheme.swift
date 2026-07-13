import SwiftUI

struct AppTheme {
  struct ColorPalette {
    static let primary = Color("Primary")
    static let secondary = Color("Secondary")
    static let background = Color(.systemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let separator = Color(.separator)
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
  }

  struct Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
  }

  struct Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
  }
}

