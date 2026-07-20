import SwiftUI

// Native port of winner-circle-dev's src/lib/boldTheme.ts -- keep these two
// files in sync. "Frost", the light-glass system that replaced Bold (the
// original dark scoreboard-green theme). Property names kept unchanged from
// Bold on purpose so every existing call site keeps working -- only the
// values changed. Source of truth for exact values: the approved "SUP
// Identity Refresh — Light.dc.html" Claude Design doc and its
// sup-home-frost.html mockup.
enum BoldTheme {
  enum Colors {
    static let bgPage    = Color(hex: 0xDFE2DB) // Fog Gray
    static let gold      = Color(hex: 0xFFD23A) // Bank Gold -- unchanged, CTA-only
    static let green     = Color(hex: 0x0E5A3A) // Field Green -- unchanged, links/accents
    static let text       = Color(hex: 0x0A1A10) // Ink
    static let textDim    = Color(hex: 0x16241B).opacity(0.62)
    static let textFaint  = Color(hex: 0x16241B).opacity(0.4)
    static let border     = Color(hex: 0x16241B).opacity(0.14)
    static let surface    = Color(hex: 0x16241B).opacity(0.04)
    static let track      = Color(hex: 0xEDEAE0) // light wall -- logo-fallback circles, muted chips

    // Frost glass-surface recipe -- fill + border pair, used with .background(.ultraThinMaterial)-style blur.
    static let glass       = Color.white.opacity(0.55) // big panels / sheets
    static let glassStrong = Color.white.opacity(0.78) // cards / rows -- more opaque
    static let glassBorder = Color.white.opacity(0.78)
  }

  // Barlow instantiated as static weights + JetBrains Mono (see
  // Sources/Resources/Fonts), replacing DM Sans/DM Mono -- matches Frost's
  // body/mono font roles from the design doc.
  enum FontName {
    static let display   = "BebasNeue-Regular"
    static let bodyReg   = "Barlow-Regular"
    static let bodyMed   = "Barlow-Medium"
    static let bodySemi  = "Barlow-SemiBold"
    static let bodyBold  = "Barlow-Bold"
    static let monoReg   = "JetBrainsMono-Regular"
    static let monoMed   = "JetBrainsMono-SemiBold"
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

  // repeating-linear-gradient(45deg, rgba(10,26,16,0) 0 7px, rgba(10,26,16,.09) 7px 12px)
  // -- CSS repeating-linear-gradient has no direct SwiftUI equivalent; ported
  // as a tiling Canvas view. Use HatchOverlay() as a background/overlay.
  struct HatchOverlay: View {
    var angle: Angle = .degrees(45)
    var color: Color = Color(hex: 0x0A1A10).opacity(0.09)
    var band: CGFloat = 5
    var period: CGFloat = 12

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

  // Frost's three-blob radial-gradient backdrop -- port of AmbientBlobs in
  // web's BoldComponents.tsx. Sits behind a screen's content; render as the
  // first layer in a ZStack, same recipe on every Frost screen (source:
  // SUP Identity Refresh — Light.dc.html / sup-home-frost.html) rather than
  // one-off blur blobs per screen.
  struct AmbientBlobs: View {
    var body: some View {
      GeometryReader { geo in
        ZStack {
          Circle()
            .fill(RadialGradient(colors: [Color(hex: 0x0E5A3A).opacity(0.45), Color(hex: 0x0E5A3A).opacity(0)], center: .center, startRadius: 0, endRadius: 260))
            .frame(width: 520, height: 520)
            .position(x: -80, y: -120)
            .blur(radius: 20)
          Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xFFD23A).opacity(0.5), Color(hex: 0xFFD23A).opacity(0)], center: .center, startRadius: 0, endRadius: 280))
            .frame(width: 560, height: 560)
            .position(x: geo.size.width + 120, y: 340)
            .blur(radius: 20)
          Circle()
            .fill(RadialGradient(colors: [Color(hex: 0x0E5A3A).opacity(0.3), Color(hex: 0x0E5A3A).opacity(0)], center: .center, startRadius: 0, endRadius: 300))
            .frame(width: 600, height: 600)
            .position(x: geo.size.width * 0.3, y: geo.size.height + 100)
            .blur(radius: 24)
        }
      }
      .allowsHitTesting(false)
    }
  }

  // Frost's frosted-glass surface, THE surface language -- ~55-78% white
  // fill + blur + bright hairline rim + soft shadow. `strong` bumps fill
  // opacity for smaller cards/rows (list items, stat tiles) where the
  // lower default opacity reads too translucent. Port of GlassCard in
  // web's BoldComponents.tsx.
  struct GlassCard<Content: View>: View {
    var strong: Bool = false
    var radius: CGFloat = 20
    var padding: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
      content
        .padding(padding)
        .background(.ultraThinMaterial)
        .background(strong ? Color.white.opacity(0.78) : Color.white.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.78), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .shadow(color: Color(hex: 0x142A1C).opacity(0.12), radius: 20, x: 0, y: 14)
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
