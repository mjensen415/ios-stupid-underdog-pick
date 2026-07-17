import SwiftUI

struct WeekSelectorView: View {
  let season: Int
  let week: Int
  
  var body: some View {
    HStack {
      Text(verbatim: "Season \(season)")
      Spacer()
      Text(verbatim: "Week \(week)")
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .padding(.horizontal)
  }
}

