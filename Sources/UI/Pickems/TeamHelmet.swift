import SwiftUI

// Same helmet-shell shape as web's TeamHelmet.tsx (identical control points,
// just SwiftUI Path instead of an SVG <path>) so both platforms render the
// same silhouette. Coordinates are in a 100x90 design space, scaled to the
// shape's actual frame.
struct HelmetShellShape: Shape {
  func path(in rect: CGRect) -> Path {
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 90 * rect.height)
    }
    var path = Path()
    path.move(to: pt(10, 45))
    path.addCurve(to: pt(55, 8), control1: pt(10, 20), control2: pt(30, 8))
    path.addCurve(to: pt(90, 45), control1: pt(80, 8), control2: pt(92, 25))
    path.addCurve(to: pt(68, 72), control1: pt(89, 58), control2: pt(82, 68))
    path.addLine(to: pt(60, 72))
    path.addCurve(to: pt(44, 58), control1: pt(58, 62), control2: pt(52, 58))
    path.addLine(to: pt(28, 58))
    path.addCurve(to: pt(10, 45), control1: pt(16, 58), control2: pt(10, 55))
    path.closeSubpath()
    return path
  }
}

// Facemask cage -- three open curve segments, stroked only.
struct HelmetMaskShape: Shape {
  func path(in rect: CGRect) -> Path {
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 90 * rect.height)
    }
    var path = Path()
    path.move(to: pt(85, 30))
    path.addCurve(to: pt(45, 34), control1: pt(70, 26), control2: pt(55, 26))
    path.move(to: pt(83, 42))
    path.addCurve(to: pt(46, 48), control1: pt(68, 40), control2: pt(54, 42))
    path.move(to: pt(78, 54))
    path.addCurve(to: pt(48, 60), control1: pt(66, 54), control2: pt(55, 56))
    return path
  }
}

struct TeamHelmet: View {
  let logoUrl: String?
  let primaryColor: Color
  let secondaryColor: Color
  var size: CGFloat = 36

  private var scale: CGFloat { size / 100 }
  private var helmetHeight: CGFloat { size * 90 / 100 }

  var body: some View {
    ZStack {
      HelmetShellShape().fill(primaryColor)
      HelmetShellShape().stroke(secondaryColor, lineWidth: 2)
      if let logoUrl, let url = URL(string: logoUrl) {
        RetryingAsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Color.clear
        }
        .frame(width: 34 * scale, height: 34 * scale)
        .clipShape(Circle())
        .position(x: 48 * scale, y: 38 * scale)
      }
      HelmetMaskShape().stroke(secondaryColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
    .frame(width: size, height: helmetHeight)
  }
}
