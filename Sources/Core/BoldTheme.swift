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
    static let gold      = Color(hex: 0xFFD23A) // Bank Gold -- unchanged, CTA-only. Only ~1.1:1 contrast on bgPage -- never use as text on a light background, use goldDeep instead. Fine on dark surfaces (green/black) or as a filled badge background.
    static let goldDeep  = Color(hex: 0x7A5009) // Deep Gold -- same hue as gold, ~5.4:1 contrast on bgPage. Use for gold-meaning TEXT (spreads, "you're #1", stat highlights) on light/glass backgrounds.
    static let green     = Color(hex: 0x0E5A3A) // Field Green -- unchanged, links/accents
    static let text       = Color(hex: 0x0A1A10) // Ink
    static let textDim    = Color(hex: 0x16241B).opacity(0.62)
    static let textFaint  = Color(hex: 0x16241B).opacity(0.4)
    static let border     = Color(hex: 0x16241B).opacity(0.14)
    static let surface    = Color(hex: 0x16241B).opacity(0.04)
    static let track      = Color(hex: 0xEDEAE0) // light wall -- logo-fallback circles, muted chips

    // Pickems accent -- straight-up-winner-picks is a genuinely different
    // contest from Underdog Pick's spread-based mechanic, so it gets its
    // own hue (deep teal) rather than sharing gold/green everywhere. Matches
    // the approved "Pro Ball Pickems Redesign" mockup direction.
    static let pickemsAccent     = Color(hex: 0x0C6E8C)
    static let pickemsAccentDeep = Color(hex: 0x073E4F)

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

    /// Numbers (points, W-L, scores, ranks): Barlow with fixed-width digits
    /// so columns line up -- not JetBrains Mono, which read oddly next to
    /// Barlow names (owner, Oct 30). Every existing `mono(...)` call site
    /// now gets this.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
      body(size, weight: weight == .regular ? .medium : .semibold).monospacedDigit()
    }

    /// JetBrains Mono, for code-like text only (invite tokens, links).
    static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
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

  // Kept for every existing call site, but flat now (de-slop #6, Oct 2026):
  // no material, rim or shadow -- a solid off-white card on the Fog Gray
  // page does the separating. `strong` is accepted and ignored.
  struct GlassCard<Content: View>: View {
    var strong: Bool = false
    var radius: CGFloat = Radius.card
    var padding: CGFloat = Space.cardPad
    @ViewBuilder var content: Content

    var body: some View {
      content
        .padding(padding)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Colors.card))
    }
  }

  /// The de-slop card: flat off-white fill, radius 18, 16 padding.
  struct FlatCard<Content: View>: View {
    var padding: CGFloat = Space.cardPad
    @ViewBuilder var content: Content
    var body: some View {
      content
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Colors.card))
    }
  }
}

// MARK: - De-slop design values (Oct 2026)
// One place for spacing, radius, type roles, colour roles and buttons.
// Source: 01_SUP/design/deslop-2026-10/decisions.md + deslop-mockups.html.
extension BoldTheme {
  /// One spacing scale: 4 / 8 / 12 / 16 / 24 / 32.
  enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    /// Screen side margins.
    static let margin: CGFloat = 16
    /// Gap between cards.
    static let cardGap: CGFloat = 12
    /// Padding inside a card.
    static let cardPad: CGFloat = 16
  }

  enum Radius {
    static let card: CGFloat = 18
    /// Boxes nested inside a card (Last 3, outcome line).
    static let inner: CGFloat = 14
  }

  /// Type roles. Bebas Neue for team names and lines only; Barlow for
  /// everything else, with monospaced digits for numbers in tables;
  /// JetBrains Mono only for code-like text (invite tokens).
  enum TypeRole {
    static func teamName(_ size: CGFloat = 30) -> Font { Fonts.display(size) }
    static func line(_ size: CGFloat = 30) -> Font { Fonts.display(size) }
    static func title(_ size: CGFloat = 22) -> Font { Fonts.body(size, weight: .bold) }
    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font { Fonts.body(size, weight: weight) }
    /// Small all-caps column labels (FAV / DOG / FAVORITE / UNDERDOG).
    static func label(_ size: CGFloat = 10) -> Font { Fonts.body(size, weight: .bold) }
    static func tableNumber(_ size: CGFloat = 12, weight: Font.Weight = .semibold) -> Font { Fonts.mono(size, weight: weight) }
  }

  /// Colour roles. Yellow = your next action only. Green = won / locked.
  /// Red = lost / error. Grays for everything else.
  enum Role {
    static let action = Colors.gold
    static let won = Colors.green
    static let lost = Color(hex: 0xB42318)
    static let wonTint = Color(hex: 0x0E5A3A).opacity(0.10)
    static let lostTint = Color(hex: 0xB42318).opacity(0.10)
    /// The +line: bold ink, not gold/brown.
    static let line = Colors.text
    static let neutralPill = Colors.track
  }
}

extension BoldTheme.Colors {
  /// Flat card fill (web --card, hsl(90 14% 97%)).
  static let card = Color(hex: 0xF7F8F5)
}

// MARK: - Buttons

/// Primary: yellow filled pill, Barlow bold 16, ink text, optional icon.
struct SupPrimaryButtonStyle: ButtonStyle {
  var fullWidth: Bool = true
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(BoldTheme.Fonts.body(16, weight: .bold))
      .foregroundColor(BoldTheme.Colors.text)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 22).padding(.vertical, 14)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
      .background(Capsule().fill(BoldTheme.Colors.gold))
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Capsule())
  }
}

/// Secondary: 1.5pt ink outline pill.
struct SupSecondaryButtonStyle: ButtonStyle {
  var fullWidth: Bool = true
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(BoldTheme.Fonts.body(16, weight: .bold))
      .foregroundColor(BoldTheme.Colors.text)
      .lineLimit(1)
      .padding(.horizontal, 22).padding(.vertical, 14)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
      .overlay(Capsule().strokeBorder(BoldTheme.Colors.text, lineWidth: 1.5))
      .opacity(configuration.isPressed ? 0.6 : 1)
      .contentShape(Capsule())
  }
}

/// The primary button when it sits on a yellow block: ink fill, yellow text.
struct SupInkButtonStyle: ButtonStyle {
  var fullWidth: Bool = true
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(BoldTheme.Fonts.body(16, weight: .bold))
      .foregroundColor(BoldTheme.Colors.gold)
      .lineLimit(1)
      .padding(.horizontal, 22).padding(.vertical, 14)
      .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
      .background(Capsule().fill(BoldTheme.Colors.text))
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Capsule())
  }
}

/// Compact header-size version of the primary / secondary pill (screen
/// headers: "Join", "+ Create").
struct SmallPill: ButtonStyle {
  var primary: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(BoldTheme.Fonts.body(14, weight: .bold))
      .foregroundColor(BoldTheme.Colors.text)
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(Capsule().fill(primary ? BoldTheme.Colors.gold : .clear))
      .overlay(primary ? nil : Capsule().strokeBorder(BoldTheme.Colors.text, lineWidth: 1.5))
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Capsule())
  }
}

/// Small status pill (Missed, Picked, Pick...).
struct SupPill: View {
  enum Kind { case gray, green, outline, action }
  let text: String
  var kind: Kind = .gray
  var body: some View {
    Text(text)
      .font(BoldTheme.Fonts.body(13, weight: .semibold))
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 10).padding(.vertical, 4)
      .foregroundColor(fg)
      .background(Capsule().fill(bg))
      .overlay(kind == .outline ? Capsule().strokeBorder(BoldTheme.Colors.text, lineWidth: 1.5) : nil)
  }
  private var fg: Color {
    switch kind {
    case .gray: return BoldTheme.Colors.textDim
    case .green: return BoldTheme.Colors.green
    case .outline, .action: return BoldTheme.Colors.text
    }
  }
  private var bg: Color {
    switch kind {
    case .gray: return BoldTheme.Colors.track
    case .green: return BoldTheme.Role.wonTint
    case .outline: return .clear
    case .action: return BoldTheme.Colors.gold
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
