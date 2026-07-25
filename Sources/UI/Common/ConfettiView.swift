import SwiftUI

// A one-shot confetti burst, Canvas-driven rather than a stack of animated
// views -- cheap to redraw every frame regardless of particle count. Mirrors
// web's <Confetti> in IndexBold.tsx: re-fires whenever `trigger` changes,
// stays invisible (and non-interactive) once the burst finishes.
struct ConfettiView: View {
  var trigger: AnyHashable
  var colors: [Color] = [BoldTheme.Colors.gold, BoldTheme.Colors.green, .white]
  var count: Int = 40

  @State private var particles: [Particle] = []
  @State private var startDate = Date()

  private struct Particle {
    var x: CGFloat // 0...1, fraction of width
    var y: CGFloat // 0...1, fraction of height, negative = above the view
    var vx: CGFloat
    var vy: CGFloat
    var rotation: Double
    var spin: Double
    var size: CGFloat
    var color: Color
  }

  var body: some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        let elapsed = timeline.date.timeIntervalSince(startDate)
        guard elapsed < 1.4 else { return }
        let fade = elapsed > 1.0 ? max(0, 1 - (elapsed - 1.0) / 0.4) : 1
        for p in particles {
          let t = CGFloat(elapsed)
          let x = (p.x + p.vx * t) * size.width
          let y = (p.y + p.vy * t * t) * size.height // vy*t^2 -- gentle gravity
          var ctx = context
          ctx.opacity = fade
          ctx.translateBy(x: x, y: y)
          ctx.rotate(by: .radians(p.rotation + p.spin * Double(t)))
          let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
          ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(p.color))
        }
      }
      .allowsHitTesting(false)
    }
    .onAppear { fire() }
    .onChange(of: trigger) { _, _ in fire() }
  }

  private func fire() {
    startDate = Date()
    particles = (0..<count).map { _ in
      Particle(
        x: CGFloat.random(in: 0.2...0.8),
        y: CGFloat.random(in: -0.1...0.05),
        vx: CGFloat.random(in: -0.35...0.35),
        vy: CGFloat.random(in: 0.5...0.9),
        rotation: Double.random(in: 0...(2 * .pi)),
        spin: Double.random(in: -6...6),
        size: CGFloat.random(in: 6...11),
        color: colors.randomElement() ?? BoldTheme.Colors.gold
      )
    }
  }
}
