import Foundation

enum DateFormatting {
  // Games span multiple days within a single week -- always include the
  // weekday, not just a numeric date, so it reads at a glance.
  static func formatKickoff(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
    return formatter.string(from: date)
  }
}

