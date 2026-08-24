import Foundation

/// Week 0 and Week 1 share a single pick slot server-side (upsert_weekly_pick
/// RPC) -- translate its exception code into copy that matches how the rest
/// of the app talks about picks. Mirrors web's friendlyPickError.
func friendlyPickErrorMessage(_ error: Error) -> String {
  let raw = error.localizedDescription
  if raw.contains("WEEK_0_1_PICK_ALREADY_LOCKED") {
    return "Your Week 0/1 pick already locked in -- you can't switch weeks once that game has started."
  }
  return raw
}
