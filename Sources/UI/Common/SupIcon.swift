import SwiftUI

// Native port of winner-circle-dev's src/components/SupIcon.tsx, itself
// ported from the "SUP Identity Refresh" Claude Design project
// (SupIcon.dc.html, projectId 343f0b08-2df8-44b0-911c-e87435734b59). Keep
// geometry/colors in sync with that file.
enum SupIconVariant {
  case monogram
  case spread // "The Cover" -- retired/alternate mark
  case football // "Gold Ball" -- chosen app icon mark
}

struct SupIcon: View {
  let variant: SupIconVariant

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      ZStack {
        switch variant {
        case .monogram: monogram(side: side)
        case .spread: spread(side: side)
        case .football: football(side: side)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipped()
    }
  }

  @ViewBuilder
  private func monogram(side: CGFloat) -> some View {
    ZStack {
      RadialGradient(
        colors: [Color(hex: 0x123322), BoldTheme.Colors.bgPage],
        center: UnitPoint(x: 0.5, y: 0.08),
        startRadius: 0,
        endRadius: side * 0.75
      )
      VStack(spacing: 0) {
        Text("SUP")
          .font(BoldTheme.Fonts.display(side * 0.56))
          .foregroundColor(BoldTheme.Colors.gold)
          .shadow(color: .black.opacity(0.35), radius: 0, y: side * 0.0067)
        Rectangle()
          .fill(BoldTheme.Colors.gold)
          .frame(width: side * 0.58, height: side * 0.042)
          .padding(.top, side * 0.03)
        Text("UNDERDOG")
          .font(BoldTheme.Fonts.display(side * 0.12))
          .tracking(side * 0.0408)
          .foregroundColor(Color(hex: 0xF2EFE3).opacity(0.62))
          .padding(.leading, side * 0.0408)
          .padding(.top, side * 0.06)
      }
    }
    .background(BoldTheme.Colors.bgPage)
  }

  @ViewBuilder
  private func spread(side: CGFloat) -> some View {
    ZStack {
      BoldTheme.Colors.bgPage
      HatchPattern(color: BoldTheme.Colors.green.opacity(0.5), band: side * 0.038, period: side * 0.09)
      VStack(spacing: side * 0.075) {
        Chevron()
          .stroke(BoldTheme.Colors.gold, style: StrokeStyle(lineWidth: side * 0.115, lineCap: .round, lineJoin: .round))
          .frame(width: side * 0.34, height: side * 0.34)
        RoundedRectangle(cornerRadius: side * 0.03)
          .fill(BoldTheme.Colors.gold)
          .frame(width: side * 0.42, height: side * 0.062)
      }
    }
  }

  @ViewBuilder
  private func football(side: CGFloat) -> some View {
    RadialGradient(
      colors: [Color(hex: 0xFCFDFB), Color(hex: 0xE8ECE4), Color(hex: 0xD2D8CD)],
      center: UnitPoint(x: 0.30, y: 0.18),
      startRadius: 0,
      endRadius: side * 0.85
    )
    .overlay(alignment: .topLeading) {
      Circle()
        .fill(RadialGradient(colors: [Color(hex: 0x0E5A3A).opacity(0.34), Color(hex: 0x0E5A3A).opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.31))
        .frame(width: side * 0.62, height: side * 0.62)
        .blur(radius: side * 0.03)
        .offset(x: side * -0.18, y: side * -0.22)
    }
    .overlay(alignment: .bottomTrailing) {
      Circle()
        .fill(RadialGradient(colors: [BoldTheme.Colors.gold.opacity(0.55), BoldTheme.Colors.gold.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.33))
        .frame(width: side * 0.66, height: side * 0.66)
        .blur(radius: side * 0.03)
        .offset(x: side * 0.16, y: side * 0.24)
    }
    .overlay {
      FootballGlyph()
        .frame(width: side * 0.86, height: side * 0.86)
        .rotationEffect(.degrees(-18))
    }
    .clipped()
    .background(BoldTheme.Colors.bgPage)
  }
}

// Hand-shaded football mark, ported 1:1 from the design source's SVG (clip
// path + two directional shading patches + seam lines + laces) -- SwiftUI
// can't parse SVG path strings directly, so each path/line below is the
// same command sequence translated to Canvas/Path calls, coordinates scaled
// from the source's 0-100 viewBox.
private struct FootballGlyph: View {
  var body: some View {
    Canvas { context, size in
      let scale = size.width / 100
      func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }

      var ballShape = Path()
      ballShape.move(to: pt(15, 50))
      ballShape.addCurve(to: pt(50, 24), control1: pt(15, 33), control2: pt(32, 24))
      ballShape.addCurve(to: pt(85, 50), control1: pt(68, 24), control2: pt(85, 33))
      ballShape.addCurve(to: pt(50, 76), control1: pt(85, 67), control2: pt(68, 76))
      ballShape.addCurve(to: pt(15, 50), control1: pt(32, 76), control2: pt(15, 67))
      ballShape.closeSubpath()

      let cream = Color(hex: 0xFBF3DC)
      let outline = Color(hex: 0x4A2E08)

      context.drawLayer { layer in
        layer.clip(to: ballShape)
        layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF0AE2E)))

        var shadowPath = Path()
        shadowPath.move(to: pt(22, 80))
        shadowPath.addQuadCurve(to: pt(90, 40), control: pt(55, 70))
        shadowPath.addLine(to: pt(100, 60))
        shadowPath.addLine(to: pt(100, 100))
        shadowPath.addLine(to: pt(20, 100))
        shadowPath.closeSubpath()
        layer.fill(shadowPath, with: .color(Color(hex: 0xBE7A1B)))

        var highlightPath = Path()
        highlightPath.move(to: pt(10, 44))
        highlightPath.addQuadCurve(to: pt(56, 20), control: pt(30, 26))
        highlightPath.addLine(to: pt(52, 10))
        highlightPath.addQuadCurve(to: pt(4, 40), control: pt(24, 16))
        highlightPath.closeSubpath()
        layer.fill(highlightPath, with: .color(Color(hex: 0xFFD35C)))

        layer.fill(Path(CGRect(x: 25 * scale, y: 22 * scale, width: 6 * scale, height: 56 * scale)), with: .color(cream))
        layer.fill(Path(CGRect(x: 69 * scale, y: 22 * scale, width: 6 * scale, height: 56 * scale)), with: .color(cream))
      }

      context.stroke(ballShape, with: .color(outline), lineWidth: 4 * scale)

      func seam(_ x: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path()
        p.move(to: pt(x, y1))
        p.addLine(to: pt(x, y2))
        return p
      }
      for x: CGFloat in [25, 31, 69, 75] {
        context.stroke(seam(x, 22, 78), with: .color(outline), lineWidth: 2.4 * scale)
      }

      var laceCenterPath = Path()
      laceCenterPath.move(to: pt(34, 50))
      laceCenterPath.addLine(to: pt(66, 50))
      context.stroke(laceCenterPath, with: .color(outline), style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round))
      context.stroke(laceCenterPath, with: .color(cream), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))

      let stitchXs: [CGFloat] = [43, 48, 53, 58]
      for x in stitchXs {
        context.stroke(seam(x, 44, 56), with: .color(outline), style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round))
      }
      for x in stitchXs {
        context.stroke(seam(x, 44, 56), with: .color(cream), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))
      }
    }
  }
}

private struct Chevron: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return p
  }
}

private struct HatchPattern: View {
  let color: Color
  let band: CGFloat
  let period: CGFloat

  var body: some View {
    Canvas { context, size in
      context.rotate(by: .degrees(45))
      let diag = sqrt(size.width * size.width + size.height * size.height)
      var x: CGFloat = -diag
      while x < diag {
        context.fill(Path(CGRect(x: x, y: -diag, width: band, height: diag * 2)), with: .color(color))
        x += period
      }
    }
    .drawingGroup()
  }
}

#Preview {
  HStack(spacing: 16) {
    SupIcon(variant: .monogram).frame(width: 80, height: 80).cornerRadius(18)
    SupIcon(variant: .football).frame(width: 80, height: 80).cornerRadius(18)
    SupIcon(variant: .spread).frame(width: 80, height: 80).cornerRadius(18)
  }
  .padding()
  .background(Color.black)
}
