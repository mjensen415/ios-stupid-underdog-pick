import SwiftUI

// Shared SUP Pro pieces: where-to-watch capsules and the "Last 3" recent
// form box. Ports of the web's components/WatchLinks.tsx and
// components/RecentForm.tsx. No prices and no purchase prompts anywhere.

enum SUPColors {
  static let liveRed = Color(hex: 0xB42318)
  static let winGreenBg = Color(hex: 0x0E5A3A).opacity(0.14)
  static let lossRedBg = Color(hex: 0xB42318).opacity(0.12)
  /// Light text on solid green/ink surfaces (TEXT_ON_GREEN on the web).
  static let textOnGreen = Color(hex: 0xF2EFE3)
}

/// Gold surface with the diagonal hatch (primary buttons, DOG WIN tags).
struct GoldHatchBackground: View {
  var radius: CGFloat = 4
  var body: some View {
    RoundedRectangle(cornerRadius: radius)
      .fill(BoldTheme.Colors.gold)
      .overlay(BoldTheme.HatchOverlay().clipShape(RoundedRectangle(cornerRadius: radius)))
  }
}

/// Opens an https link so the network's app (ESPN, Peacock...) takes over
/// as a universal link when installed, else Safari.
private struct OpenLinkButton<Label: View>: View {
  let url: URL
  @ViewBuilder var label: Label
  @Environment(\.openURL) private var openURL
  var body: some View {
    Button { openURL(url) } label: { label }
      .buttonStyle(.borderless)
  }
}

/// Layout A's middle-column capsule: "▶ ESPNU", or once live a red
/// "● WATCH NOW · ESPNU". Nothing when no linked network.
struct WatchPill: View {
  let link: WatchLink
  var live: Bool = false

  var body: some View {
    if let url = link.url {
      OpenLinkButton(url: url) {
        HStack(spacing: 4) {
          if live {
            Circle().fill(Color.white).frame(width: 5, height: 5)
            Text("WATCH NOW · \(link.label)")
          } else {
            Image(systemName: "play.fill").font(.system(size: 7))
            Text(link.label)
          }
        }
        .font(BoldTheme.Fonts.body(10.5, weight: .bold))
        .lineLimit(1)
        .fixedSize()
        .foregroundColor(live ? .white : BoldTheme.Colors.gold)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(live ? SUPColors.liveRed : BoldTheme.Colors.text))
      }
      .accessibilityLabel(link.deep ? "Open this game on ESPN (\(link.label))" : "Watch on \(link.label)")
    }
  }
}

/// The full chip row (pick sheet, Hoops/Pucks cards): every linked network,
/// local channels as plain names.
struct WatchChips: View {
  let links: [WatchLink]
  var live: Bool = false

  var body: some View {
    if !links.isEmpty {
      let primary = live ? links.first(where: { $0.url != nil }) : nil
      let rest = links.filter { $0 != primary }
      HStack(spacing: 6) {
        if let primary {
          WatchPill(link: primary, live: true)
        } else {
          Text("Watch")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        ForEach(rest, id: \.label) { l in
          if l.url != nil {
            WatchPill(link: l)
          } else {
            Text(l.label + (l.local ? " · local" : ""))
              .font(BoldTheme.Fonts.body(10.5, weight: .bold))
              .foregroundColor(BoldTheme.Colors.text)
              .padding(.horizontal, 8).padding(.vertical, 3)
              .background(Capsule().fill(BoldTheme.Colors.text.opacity(0.06)))
          }
        }
      }
    }
  }
}

/// One teaser for non-Pro players, shown once per list -- no price, no link
/// to buy anything.
struct WatchProTeaser: View {
  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
      Text("Where to watch")
      Text("· Pro").foregroundColor(BoldTheme.Colors.textDim)
    }
    .font(BoldTheme.Fonts.body(11.5, weight: .bold))
    .foregroundColor(BoldTheme.Colors.text)
    .padding(.horizontal, 10).padding(.vertical, 4)
    // Neutral, so it doesn't compete with the yellow Lock in button.
    .background(Capsule().fill(BoldTheme.Colors.card))
    .accessibilityLabel("Where to watch is a Pro tool")
  }
}

/// W / L / T chip.
struct FormResultChip: View {
  let game: FormGame
  var body: some View {
    Text(game.won ? "W" : game.tie ? "T" : "L")
      .font(BoldTheme.Fonts.body(10, weight: .bold))
      .foregroundColor(game.won ? BoldTheme.Colors.green : SUPColors.liveRed)
      .frame(width: 18, height: 18)
      .background(RoundedRectangle(cornerRadius: 5).fill(game.won ? SUPColors.winGreenBg : SUPColors.lossRedBg))
  }
}

/// "Last 3" box for one team (pick card, Pro): W/L, score and the team's own
/// line, then "@ Opponent · 10/8" on its own line, and a "Dog win +N" badge
/// on its own line too -- nothing in here truncates (de-slop #26).
struct RecentFormBox: View {
  let games: [FormGame]?
  var loading: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(verbatim: "Last \(games.map { $0.isEmpty ? 3 : $0.count } ?? 3)")
          .font(BoldTheme.Fonts.body(12, weight: .semibold))
        Spacer()
        if let games, !games.isEmpty {
          Text(RecentForm.record(games)).font(BoldTheme.TypeRole.tableNumber(12))
        }
      }
      .foregroundColor(BoldTheme.Colors.textDim)

      if loading {
        Text("Loading…").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
      } else if games?.isEmpty ?? true {
        Text("No finished games yet.").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
      } else if let games {
        ForEach(Array(games.enumerated()), id: \.offset) { _, g in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            FormResultChip(game: g)
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 4) {
                Text(verbatim: "\(g.ourPts)–\(g.theirPts)")
                  .font(BoldTheme.TypeRole.tableNumber(12))
                  .foregroundColor(BoldTheme.Colors.text)
                Spacer(minLength: 2)
                if g.line != nil {
                  Text(RecentForm.fmtLine(g.line))
                    .font(BoldTheme.TypeRole.tableNumber(12, weight: .regular))
                    .foregroundColor(BoldTheme.Colors.textDim)
                }
              }
              .lineLimit(1)
              Text(verbatim: "\(g.away ? "@" : "vs") \(g.opponent) · \(RecentForm.fmtDate(g.date))")
                .font(BoldTheme.Fonts.body(12))
                .foregroundColor(BoldTheme.Colors.textDim)
                .fixedSize(horizontal: false, vertical: true)
              if g.dogWin {
                Text(verbatim: "Dog win \(RecentForm.fmtLine(g.line))")
                  .font(BoldTheme.Fonts.body(10.5, weight: .bold))
                  .foregroundColor(SUPColors.textOnGreen)
                  .lineLimit(1)
                  .fixedSize()
                  .padding(.horizontal, 7).padding(.vertical, 2)
                  .background(Capsule().fill(BoldTheme.Colors.green))
              }
            }
          }
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.card))
  }
}

/// Compact Hoops / Pucks strip: "LAST 3 W L W 2-1".
struct FormStrip: View {
  let games: [FormGame]
  var body: some View {
    HStack(spacing: 3) {
      Text("LAST \(games.count)")
        .font(BoldTheme.Fonts.mono(9, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)
        .padding(.trailing, 2)
      ForEach(Array(games.enumerated()), id: \.offset) { _, g in
        Text(g.won ? "W" : g.tie ? "T" : "L")
          .font(BoldTheme.Fonts.mono(9.5, weight: .bold))
          .foregroundColor(g.won ? BoldTheme.Colors.green : SUPColors.liveRed)
          .padding(.horizontal, 3)
          .background(RoundedRectangle(cornerRadius: 3).fill(g.won ? SUPColors.winGreenBg : SUPColors.lossRedBg))
      }
      Text(RecentForm.record(games))
        .font(BoldTheme.Fonts.mono(9, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)
        .padding(.leading, 2)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(games.map { "\($0.won ? "Won" : "Lost") \($0.ourPts) to \($0.theirPts) \($0.away ? "at" : "versus") \($0.opponent)" }.joined(separator: ", "))
  }
}
