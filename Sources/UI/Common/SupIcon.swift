import SwiftUI

// Native port of winner-circle-dev's src/components/SupIcon.tsx -- keep
// geometry/colors in sync with that file and with the standalone
// public/favicon.svg / iOS AppIcon-1024.png ("The Cover") source.
enum SupIconVariant {
  case monogram
  case spread // "The Cover" -- chosen app icon mark
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
      Rectangle()
        .fill(BoldTheme.Colors.gold)
        .frame(height: side * 0.055)
        .position(x: side / 2, y: side * (1 - 0.145 - 0.0275))
      Text("S")
        .font(BoldTheme.Fonts.display(side * 1.24))
        .foregroundColor(BoldTheme.Colors.gold)
        .frame(width: side, height: side * 0.66)
        .position(x: side / 2, y: side * 0.46)
      Text("UNDERDOG")
        .font(BoldTheme.Fonts.display(side * 0.135))
        .tracking(side * 0.18 * 0.135)
        .foregroundColor(BoldTheme.Colors.text.opacity(0.62))
        .position(x: side / 2, y: side * (1 - 0.066))
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
    SupIcon(variant: .spread).frame(width: 80, height: 80).cornerRadius(18)
  }
  .padding()
  .background(Color.black)
}
