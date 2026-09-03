import SwiftUI

// Real NFL team colors, keyed by teams.short_name -- mirrors web's
// nflTeamColors.ts exactly (same hex values). Team colors aren't
// trademark-protected the way logos/nicknames are, so hardcoding them
// here is safe. primary = helmet shell fill, secondary = facemask stroke.
struct TeamColorPair {
  let primary: Color
  let secondary: Color
}

private let defaultColors = TeamColorPair(primary: Color(hex: 0x16241B), secondary: Color(hex: 0xEDEAE0))

private let nflTeamColors: [String: TeamColorPair] = [
  "ARI": TeamColorPair(primary: Color(hex: 0x97233F), secondary: Color(hex: 0x000000)),
  "ATL": TeamColorPair(primary: Color(hex: 0xA71930), secondary: Color(hex: 0x000000)),
  "BAL": TeamColorPair(primary: Color(hex: 0x241773), secondary: Color(hex: 0x9E7C0C)),
  "BUF": TeamColorPair(primary: Color(hex: 0x00338D), secondary: Color(hex: 0xC60C30)),
  "CAR": TeamColorPair(primary: Color(hex: 0x0085CA), secondary: Color(hex: 0x101820)),
  "CHI": TeamColorPair(primary: Color(hex: 0x0B162A), secondary: Color(hex: 0xC83803)),
  "CIN": TeamColorPair(primary: Color(hex: 0xFB4F14), secondary: Color(hex: 0x000000)),
  "CLE": TeamColorPair(primary: Color(hex: 0x311D00), secondary: Color(hex: 0xFF3C00)),
  "DAL": TeamColorPair(primary: Color(hex: 0x041E42), secondary: Color(hex: 0x869397)),
  "DEN": TeamColorPair(primary: Color(hex: 0xFB4F14), secondary: Color(hex: 0x002244)),
  "DET": TeamColorPair(primary: Color(hex: 0x0076B6), secondary: Color(hex: 0xB0B7BC)),
  "GB": TeamColorPair(primary: Color(hex: 0x203731), secondary: Color(hex: 0xFFB612)),
  "HOU": TeamColorPair(primary: Color(hex: 0x03202F), secondary: Color(hex: 0xA71930)),
  "IND": TeamColorPair(primary: Color(hex: 0x002C5F), secondary: Color(hex: 0xA2AAAD)),
  "JAX": TeamColorPair(primary: Color(hex: 0x006778), secondary: Color(hex: 0xD7A22A)),
  "KC": TeamColorPair(primary: Color(hex: 0xE31837), secondary: Color(hex: 0xFFB81C)),
  "LV": TeamColorPair(primary: Color(hex: 0x000000), secondary: Color(hex: 0xA5ACAF)),
  "LAC": TeamColorPair(primary: Color(hex: 0x0080C6), secondary: Color(hex: 0xFFC20E)),
  "LAR": TeamColorPair(primary: Color(hex: 0x003594), secondary: Color(hex: 0xFFA300)),
  "MIA": TeamColorPair(primary: Color(hex: 0x008E97), secondary: Color(hex: 0xFC4C02)),
  "MIN": TeamColorPair(primary: Color(hex: 0x4F2683), secondary: Color(hex: 0xFFC62F)),
  "NE": TeamColorPair(primary: Color(hex: 0x002244), secondary: Color(hex: 0xC60C30)),
  "NO": TeamColorPair(primary: Color(hex: 0xD3BC8D), secondary: Color(hex: 0x101820)),
  "NYG": TeamColorPair(primary: Color(hex: 0x0B2265), secondary: Color(hex: 0xA71930)),
  "NYJ": TeamColorPair(primary: Color(hex: 0x125740), secondary: Color(hex: 0xFFFFFF)),
  "PHI": TeamColorPair(primary: Color(hex: 0x004C54), secondary: Color(hex: 0xA5ACAF)),
  "PIT": TeamColorPair(primary: Color(hex: 0x101820), secondary: Color(hex: 0xFFB612)),
  "SF": TeamColorPair(primary: Color(hex: 0xAA0000), secondary: Color(hex: 0xB3995D)),
  "SEA": TeamColorPair(primary: Color(hex: 0x002244), secondary: Color(hex: 0x69BE28)),
  "TB": TeamColorPair(primary: Color(hex: 0xD50A0A), secondary: Color(hex: 0x34302B)),
  "TEN": TeamColorPair(primary: Color(hex: 0x0C2340), secondary: Color(hex: 0xC8102E)),
  "WSH": TeamColorPair(primary: Color(hex: 0x5A1414), secondary: Color(hex: 0xFFB612)),
]

func teamColors(_ shortName: String?) -> TeamColorPair {
  guard let shortName else { return defaultColors }
  return nflTeamColors[shortName.uppercased()] ?? defaultColors
}
