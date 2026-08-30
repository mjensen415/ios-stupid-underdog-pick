import SwiftUI

struct GameRowView: View {
  let game: Game
  let logoFor: (UUID?) -> URL?
  let isSelected: Bool
  // Position within its day-group -- rounds only the outer corners so
  // consecutive rows for one day fuse into a single card, matching the
  // rounded day-group container web's IndexBold.tsx now wraps games in.
  var isFirstInDay: Bool = false
  var isLastInDay: Bool = false

  private var isHomeFavorite: Bool {
    guard let fav = game.derivedFavoriteTeamId else { return false }
    return fav == game.homeTeamId
  }

  // Same condition GamesViewModel.canPick gates on -- CFB lines mostly
  // don't post until close to kickoff, so most of a week's games sit in
  // this state for days. Previously the row looked identical to a
  // pickable one and only revealed "actually can't pick this" once you
  // swiped and saw the action button greyed out.
  private var hasLine: Bool {
    game.derivedFavoriteTeamId != nil
  }

  // Distinct from "locked" (canPick also blocks postponed/other non-live
  // states) -- previously nothing on this row signaled a game is live
  // *right now* versus just not-yet-startable, since refresh-scores never
  // actually ran to update status in real time until today.
  private var isLive: Bool { game.status == "in_progress" }
  private var isFinal: Bool { game.status == "final" }
  private var showScore: Bool { (isLive || isFinal) && game.homePoints != nil && game.awayPoints != nil }

  // Favorite/underdog decides left-vs-right; home/away is a separate axis
  // (the home team can land on either side depending on who's favored) --
  // whichever slot is showing the home team gets the "@" prefix, standard
  // sports notation for "Away @ Home".
  private var leftTeamName: String {
    let name = isHomeFavorite ? (game.homeTeam ?? "Home") : (game.awayTeam ?? "Away")
    return isHomeFavorite ? "@ \(name)" : name
  }
  private var rightTeamName: String {
    let name = isHomeFavorite ? (game.awayTeam ?? "Away") : (game.homeTeam ?? "Home")
    return isHomeFavorite ? name : "@ \(name)"
  }
  private var leftTeamId: UUID? {
    isHomeFavorite ? game.homeTeamId : game.awayTeamId
  }
  private var rightTeamId: UUID? {
    isHomeFavorite ? game.awayTeamId : game.homeTeamId
  }
  private var leftScore: Int? {
    isHomeFavorite ? game.homePoints : game.awayPoints
  }
  private var rightScore: Int? {
    isHomeFavorite ? game.awayPoints : game.homePoints
  }

  // Games span multiple days within a single week, so time alone isn't
  // enough to tell them apart at a glance -- weekday + date on one line,
  // kickoff time on the next.
  private var kickoffText: String {
    let day = DateFormatter()
    day.dateFormat = "EEE M/d"
    let time = DateFormatter()
    time.timeStyle = .short
    time.dateStyle = .none
    return "\(day.string(from: game.startTime))\n\(time.string(from: game.startTime))"
  }

  var body: some View {
    HStack(spacing: 12) {
      teamBlock(name: leftTeamName, logo: logoFor(leftTeamId), score: leftScore)

      VStack(spacing: 4) {
        if isLive {
          LivePulseBadge()
        } else if isFinal {
          Text("FINAL").font(BoldTheme.Fonts.mono(11, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
        } else {
          Text(kickoffText).font(BoldTheme.Fonts.mono(12)).foregroundColor(BoldTheme.Colors.textFaint).multilineTextAlignment(.center)
        }
        if let bl = game.bettingLine, !bl.isEmpty {
          Text(bl).font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.goldDeep)
        } else if let sp = game.underdogSpread {
          Text(String(format: "%.1f", sp)).font(BoldTheme.Fonts.mono(13)).foregroundColor(BoldTheme.Colors.goldDeep)
        } else {
          Text("LINE\nTBD").font(BoldTheme.Fonts.mono(10, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint).multilineTextAlignment(.center)
        }
      }
      .frame(maxWidth: .infinity)

      ZStack(alignment: .topTrailing) {
        teamBlock(name: rightTeamName, logo: logoFor(rightTeamId), score: rightScore)
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .imageScale(.medium)
            .foregroundColor(BoldTheme.Colors.gold)
            .padding(2)
        }
      }
    }
    .opacity(hasLine || isSelected ? 1 : 0.55)
    .padding(.vertical, 14)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparatorTint(BoldTheme.Colors.border)
    // A fixed-position bottom overlay here previously caused a "Picked" pill
    // to land at different relative heights depending on whether team names
    // wrapped to one or two lines, sometimes overlapping the spread/kickoff
    // column -- a full-row tint can't overlap anything since it isn't
    // positioned relative to variable content height. The checkmark badge on
    // the picked team's logo (below) is the primary "you picked this"
    // signal; the tint just reinforces it at a glance while scrolling.
    .listRowBackground(cardRowBackground)
  }

  // Frost glass card fill (same recipe as BoldTheme.GlassCard) with only the
  // day-group's outer corners rounded, so every row for one day reads as a
  // single card rather than each row floating separately -- the native
  // equivalent of the rounded day-group container on web.
  private var cardRowBackground: some View {
    UnevenRoundedRectangle(
      topLeadingRadius: isFirstInDay ? 16 : 0,
      bottomLeadingRadius: isLastInDay ? 16 : 0,
      bottomTrailingRadius: isLastInDay ? 16 : 0,
      topTrailingRadius: isFirstInDay ? 16 : 0
    )
    .fill(isSelected ? BoldTheme.Colors.gold.opacity(0.10) : BoldTheme.Colors.glassStrong)
  }

  @ViewBuilder
  private func teamBlock(name: String, logo: URL?, score: Int? = nil) -> some View {
    VStack(spacing: 6) {
      AsyncImage(url: logo) { phase in
        switch phase {
        case .success(let img): img.resizable().scaledToFit()
        default: Image(systemName: "football").resizable().scaledToFit().opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      .frame(width: 28, height: 28)
      Text(name)
        .font(BoldTheme.Fonts.body(12))
        .foregroundColor(BoldTheme.Colors.text)
        .lineLimit(2)
        .multilineTextAlignment(.center)
      if let score {
        Text(verbatim: "\(score)")
          .font(BoldTheme.Fonts.mono(12))
          .foregroundColor(BoldTheme.Colors.textDim)
      }
    }
    .frame(width: 96)
  }
}

// Small red pulsing dot + "LIVE" label -- distinct from the plain gray
// "LOCKED"/"FINAL" states so a game in progress reads as urgent/current
// at a glance, matching the same treatment added to web.
private struct LivePulseBadge: View {
  @State private var pulsing = false

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color(hex: 0xC6402A))
        .frame(width: 6, height: 6)
        .opacity(pulsing ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
      Text("LIVE")
        .font(BoldTheme.Fonts.mono(11, weight: .bold))
        .foregroundColor(Color(hex: 0xC6402A))
        .tracking(0.5)
    }
    .onAppear { pulsing = true }
  }
}

