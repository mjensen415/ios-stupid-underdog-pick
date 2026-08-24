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
          Label("Week \(formatWeekLabel(wk))", systemImage: wk == selected ? "checkmark" : "circle")
        }
      }
    } label: {
      Label("Week \(formatWeekLabel(selected))", systemImage: "calendar")
        .font(.subheadline.bold())
    }
  }
}


