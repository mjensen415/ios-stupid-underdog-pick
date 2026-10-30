import SwiftUI

// The image ShareLink hands off -- iOS's equivalent of web's canvas-rendered
// share card (src/lib/shareCard.ts). Rendered off-screen via ImageRenderer,
// not shown directly in the UI.
struct ShareCardView: View {
  let dogName: String
  let spread: Double
  let favoriteName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Text("STUPID").foregroundColor(BoldTheme.Colors.text)
        Text("UNDERDOG").foregroundColor(BoldTheme.Colors.text)
        Text("PICK").foregroundColor(BoldTheme.Colors.text)
      }
      .font(BoldTheme.Fonts.body(22, weight: .bold))
      .padding(.bottom, 28)

      Text("My pick this week")
        .font(BoldTheme.Fonts.body(18, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textDim)
        .padding(.bottom, 8)

      Text(dogName.uppercased())
        .font(BoldTheme.Fonts.display(44))
        .foregroundColor(BoldTheme.Colors.text)
        .lineLimit(2)

      Text(verbatim: "vs \(favoriteName)")
        .font(BoldTheme.Fonts.body(16))
        .foregroundColor(BoldTheme.Colors.textDim)
        .padding(.bottom, 20)

      Text(verbatim: "+\(jsNumber(spread))")
        .font(BoldTheme.Fonts.display(88))
        .foregroundColor(BoldTheme.Colors.text)
      // Outright wins only: covering isn't enough to win the points.
      Text("points if it wins outright")
        .font(BoldTheme.Fonts.body(18, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textDim)

      Spacer()
    }
    .padding(40)
    .frame(width: 700, height: 420, alignment: .topLeading)
    .background(BoldTheme.Colors.bgPage)
  }
}

@MainActor
func renderShareCardImage(dogName: String, spread: Double, favoriteName: String) -> UIImage? {
  let renderer = ImageRenderer(content: ShareCardView(dogName: dogName, spread: spread, favoriteName: favoriteName))
  renderer.scale = 2
  return renderer.uiImage
}
