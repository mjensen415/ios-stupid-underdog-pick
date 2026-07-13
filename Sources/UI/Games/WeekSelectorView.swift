import SwiftUI

struct WeekSelectorView: View {
  let season: Int
  let week: Int
  
  var body: some View {
    HStack {
      Text("Season \(season)")
      Spacer()
      Text("Week \(week)")
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .padding(.horizontal)
  }
}

