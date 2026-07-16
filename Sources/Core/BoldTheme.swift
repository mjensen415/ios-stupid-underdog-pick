import SwiftUI

// Native port of winner-circle-dev's src/lib/boldTheme.ts -- keep these two
// files in sync. Same palette, same font roles (display/body/mono), just
// Swift-native color/font APIs instead of CSS custom properties.
enum BoldTheme {
  enum Colors {
    static let bgPage    = Color(hex: 0x0A1A10)
    static let gold      = Color(hex: 0xFFD23A)
    static let green     = Color(hex: 0x0E5A3A)
    static let text       = Color(hex: 0xF2EFE3)
    static let textDim    = Color(hex: 0xF2EFE3).opacity(0.6)
    static let textFaint  = Color(hex: 0xF2EFE3).opacity(0.4)
    static let border     = Color(hex: 0xF2EFE3).opacity(0.12)
    static let surface    = Color(hex: 0xF2EFE3).opacity(0.03)
    static let track      = Color(hex: 0x1F3A2A)
  }

  // DM Sans variable font instantiated as static weights (see
  // Sources/Resources/Fonts) -- Google Fonts only ships DM Sans as a single
  // variable-axis file, so these are pre-instanced at wght=400/500/600/700,
  // opsz=14 (text optical size) rather than the display 9pt default.
  enum FontName {
    static let display   = "BebasNeue-Regular"
    static let bodyReg   = "DMSans-Regular"
    static let bodyMed   = "DMSans-Medium"
    static let bodySemi  = "DMSans-SemiBold"
    static let bodyBold  = "DMSans-Bold"
    static let monoReg   = "DMMono-Regular"
    static let monoMed   = "DMMono-Medium"
  }

  enum Fonts {
    static func display(_ size: CGFloat) -> Font { .custom(FontName.display, size: size) }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
      switch weight {
      case .bold, .heavy, .black: return .custom(FontName.bodyBold, size: size)
      case .semibold: return .custom(FontName.bodySemi, size: size)
      case .medium: return .custom(FontName.bodyMed, size: size)
      default: return .custom(FontName.bodyReg, size: size)
      }
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
      weight == .medium || weight == .semibold || weight == .bold
        ? .custom(FontName.monoMed, size: size)
        : .custom(FontName.monoReg, size: size)
    }
  }

  // repeating-linear-gradient(135deg, transparent 0 12px, rgba(0,0,0,.04) 12px 13px)
  // -- CSS repeating-linear-gradient has no direct SwiftUI equivalent; ported
  // as a tiling Canvas view. Use HatchOverlay() as a background/overlay.
  struct HatchOverlay: View {
    var angle: Angle = .degrees(135)
    var color: Color = .black.opacity(0.04)
    var band: CGFloat = 1
    var period: CGFloat = 13

    var body: some View {
      Canvas { context, size in
        context.rotate(by: angle)
        let diag = sqrt(size.width * size.width + size.height * size.height)
        var x: CGFloat = -diag
        while x < diag {
          let rect = CGRect(x: x, y: -diag, width: band, height: diag * 2)
          context.fill(Path(rect), with: .color(color))
          x += period
        }
      }
      .drawingGroup()
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
