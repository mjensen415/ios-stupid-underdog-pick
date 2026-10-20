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
          Text("WATCH")
            .font(BoldTheme.Fonts.mono(9.5, weight: .bold))
            .tracking(0.9)
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
      Text("· PRO").foregroundColor(BoldTheme.Colors.goldDeep)
    }
    .font(BoldTheme.Fonts.body(11.5, weight: .bold))
    .foregroundColor(BoldTheme.Colors.text)
    .padding(.horizontal, 10).padding(.vertical, 4)
    .background(GoldHatchBackground(radius: 999))
    .overlay(Capsule().strokeBorder(BoldTheme.Colors.goldDeep.opacity(0.3), lineWidth: 1))
    .clipShape(Capsule())
    .accessibilityLabel("Where to watch is a Pro tool")
  }
}

/// W / L / T chip.
struct FormResultChip: View {
  let game: FormGame
  var body: some View {
    Text(game.won ? "W" : game.tie ? "T" : "L")
      .font(BoldTheme.Fonts.mono(10.5, weight: .bold))
      .foregroundColor(game.won ? BoldTheme.Colors.green : SUPColors.liveRed)
      .frame(minWidth: 17, minHeight: 17)
      .background(RoundedRectangle(cornerRadius: 4).fill(game.won ? SUPColors.winGreenBg : SUPColors.lossRedBg))
  }
}

/// "LAST 3" box for one team (pick card, Pro): date, W/L, score, @/vs
/// opponent, and the team's own line with a gold DOG WIN tag.
struct RecentFormBox: View {
  let games: [FormGame]?
  var loading: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("LAST \(games.map { $0.isEmpty ? 3 : $0.count } ?? 3)")
        Spacer()
        if let games, !games.isEmpty { Text(RecentForm.record(games)) }
      }
      .font(BoldTheme.Fonts.mono(9.5, weight: .bold))
      .tracking(0.7)
      .foregroundColor(BoldTheme.Colors.textDim)

      if loading {
        Text("Loading…").font(BoldTheme.Fonts.body(11.5)).foregroundColor(BoldTheme.Colors.textDim)
      } else if games?.isEmpty ?? true {
        Text("No finished games yet.").font(BoldTheme.Fonts.body(11.5)).foregroundColor(BoldTheme.Colors.textDim)
      } else if let games {
        ForEach(Array(games.enumerated()), id: \.offset) { _, g in
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
              Text(RecentForm.fmtDate(g.date))
                .font(BoldTheme.Fonts.mono(9.5))
                .foregroundColor(BoldTheme.Colors.textDim)
                .frame(minWidth: 30, alignment: .leading)
              FormResultChip(game: g)
              Text("\(g.ourPts)-\(g.theirPts)")
                .font(BoldTheme.Fonts.body(11.5, weight: .semibold))
                .foregroundColor(BoldTheme.Colors.text)
                .lineLimit(1)
                .fixedSize()
              Spacer(minLength: 0)
              if g.dogWin {
                Text("DOG WIN \(RecentForm.fmtLine(g.line))")
                  .font(BoldTheme.Fonts.mono(8.5, weight: .bold))
                  .foregroundColor(BoldTheme.Colors.text)
                  .padding(.horizontal, 4).padding(.vertical, 1)
                  .background(GoldHatchBackground())
                  .lineLimit(1)
                  .minimumScaleFactor(0.8)
              } else if g.line != nil {
                Text(RecentForm.fmtLine(g.line))
                  .font(BoldTheme.Fonts.mono(9.5))
                  .foregroundColor(BoldTheme.Colors.textDim)
              }
            }
            Text("\(g.away ? "@" : "vs") \(g.opponent)")
              .font(BoldTheme.Fonts.body(11))
              .foregroundColor(BoldTheme.Colors.textDim)
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.leading, 35)
          }
        }
      }
    }
    .padding(.horizontal, 9).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
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
