import SwiftUI

/// Horizontal week selector (gold pill = selected). Shared by Games (both
/// Underdog contests) and Pickems so every week picker looks and scrolls the
/// same. Scrolls the selected week into view -- Pro Ball has 18 weeks, and
/// the current one shouldn't be off-screen to the right.
struct WeekPills: View {
  let weeks: [Int]
  @Binding var selected: Int

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(weeks, id: \.self) { w in
            let active = w == selected
            Button {
              selected = w
            } label: {
              Text(verbatim: "Week \(formatWeekLabel(w))")
                .font(BoldTheme.Fonts.body(12.5, weight: .bold))
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(active ? BoldTheme.Colors.gold : BoldTheme.Colors.track)
                .foregroundColor(active ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .id(w)
          }
        }
      }
      .onAppear { proxy.scrollTo(selected, anchor: .center) }
      .onChange(of: selected) { _, w in
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(w, anchor: .center) }
      }
      .onChange(of: weeks) { _, _ in proxy.scrollTo(selected, anchor: .center) }
    }
  }
}
