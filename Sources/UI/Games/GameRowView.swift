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

  // Mirrors GamesViewModel.canPick's own three checks exactly (picksLocked,
  // startTime, hasLine) -- previously only the no-line case dimmed the row,
  // so a game that had a real line but was simply locked or over still
  // looked fully "live" until you swiped and found a disabled, unlabeled
  // button. Selected rows stay full-opacity regardless (that's the pick).
  private var isPickable: Bool {
    hasLine && game.picksLocked != true && game.startTime >= Date()
  }
  // picksLocked can go true shortly before kickoff, before status has
  // caught up to "in_progress" -- without this, a locked-but-not-yet-live
  // game still showed a plain kickoff time, giving no on-row signal (short
  // of swiping) that picking has actually closed.
  private var isLockedNotYetLive: Bool {
    game.picksLocked == true && !isLive && !isFinal
  }

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
  // Left is always FAV, right is always DOG (see leftTeamName/rightTeamName
  // above) -- bold/dim whichever side is actually ahead so live and final
  // scores read at a glance instead of needing the subtraction done by eye.
  private var favAhead: Bool {
    guard showScore, let l = leftScore, let r = rightScore else { return false }
    return l > r
  }
  private var dogAhead: Bool {
    guard showScore, let l = leftScore, let r = rightScore else { return false }
    return r > l
  }
  // Outright win only, matching the real scoring rule -- covering the
  // spread doesn't count, so this is exactly "did the underdog win the
  // game," no spread math needed.
  private var dogWonOutright: Bool { isFinal && dogAhead }

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
    HStack(spacing: 8) {
      teamBlock(name: leftTeamName, logo: logoFor(leftTeamId))

      if showScore {
        scoreText(leftScore, isAhead: favAhead)
      }

      VStack(spacing: 4) {
        if isLive {
          LivePulseBadge()
        } else if isFinal {
          if dogWonOutright {
            Text("UPSET").font(BoldTheme.Fonts.mono(11, weight: .bold)).foregroundColor(BoldTheme.Colors.goldDeep)
          } else {
            Text("FINAL").font(BoldTheme.Fonts.mono(11, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
          }
        } else if isLockedNotYetLive {
          Text("LOCKED").font(BoldTheme.Fonts.mono(11, weight: .semibold)).foregroundColor(BoldTheme.Colors.textFaint)
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

      if showScore {
        scoreText(rightScore, isAhead: dogAhead)
      }

      ZStack(alignment: .topTrailing) {
        teamBlock(name: rightTeamName, logo: logoFor(rightTeamId))
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .imageScale(.medium)
            .foregroundColor(BoldTheme.Colors.gold)
            .padding(2)
        }
      }
    }
    .opacity(isPickable || isSelected ? 1 : 0.55)
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
  private func teamBlock(name: String, logo: URL?) -> some View {
    VStack(spacing: 6) {
      RetryingAsyncImage(url: logo) { img in
        img.resizable().scaledToFit()
      } placeholder: {
        Image(systemName: "football").resizable().scaledToFit().opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
      }
      .frame(width: 28, height: 28)
      Text(name)
        .font(BoldTheme.Fonts.body(12))
        .foregroundColor(BoldTheme.Colors.text)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .frame(width: 84)
  }

  // <favorite><score><line><score><underdog> -- scores sit between each
  // team and the spread instead of under the team name, so the row reads
  // left-to-right as one continuous line score rather than two separate
  // team-plus-number groupings either side of an unrelated middle column.
  @ViewBuilder
  private func scoreText(_ score: Int?, isAhead: Bool) -> some View {
    Text(score.map(String.init) ?? "–")
      .font(BoldTheme.Fonts.display(20))
      .foregroundColor(isAhead ? BoldTheme.Colors.goldDeep : BoldTheme.Colors.textDim)
      .opacity(isAhead ? 1 : 0.6)
      .frame(width: 28)
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

