import Foundation

/// Week 0 and Week 1 both display as "0/1" everywhere in the app.
/// Frontend display only -- mirrors src/lib/weekLabel.ts on web. The two
/// remain distinct week numbers in the data (games, picks, leaderboard);
/// only the rendered label changes.
func formatWeekLabel(_ week: Int) -> String {
  (week == 0 || week == 1) ? "0/1" : String(week)
}
