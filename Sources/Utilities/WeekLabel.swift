import Foundation

/// Pro Ball never actually has a week 0 (confirmed via SQL -- no week=0
/// rows exist in `games` for sport=nfl), so the old "0/1" merge display
/// was a leftover from a week-0 concept that never shipped. Mirrors
/// src/lib/weekLabel.ts on web -- plain passthrough.
func formatWeekLabel(_ week: Int) -> String {
  String(week)
}
