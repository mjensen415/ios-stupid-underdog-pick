import SwiftUI

struct WeekPicker: View {
  let weeks: [Int]
  @Binding var selected: Int
  var body: some View {
    Menu {
      ForEach(weeks, id: \.self) { wk in
        Button {
          selected = wk
        } label: {
          Label("Week \(wk)", systemImage: wk == selected ? "checkmark" : "circle")
        }
      }
    } label: {
      Label("Week \(selected)", systemImage: "calendar")
        .font(.subheadline.bold())
    }
  }
}


