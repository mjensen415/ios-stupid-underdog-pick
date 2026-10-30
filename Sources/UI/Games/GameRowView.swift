import SwiftUI

/// One CFB / Pro Ball game, layout A (matches the web's BoldRow on
/// winner-circle-dev): favorite on the left, underdog on the right, and a
/// centered middle column stacked as the big ink "+3", the kickoff time,
/// then a where-to-watch capsule (Pro). Once there's a score the middle
/// column becomes the scoreboard. Locked, live and finished games dim; the
/// picked game's row turns solid green. No FAV/DOG labels on the row: the
/// sticky "FAVORITE · day · UNDERDOG" header carries them (round 3). No
/// per-row PICK button (de-slop
/// #12): the whole row is the target -- tap for the pick card, swipe left
/// for the yellow Pick action.
struct GameRowView: View {
  let game: Game
  let logoFor: (UUID?) -> URL?
  let isSelected: Bool
  // Position within its day-group -- rounds only the outer corners so
  // consecutive rows for one day fuse into a single card.
  var isFirstInDay: Bool = false
  var isLastInDay: Bool = false
  /// Pro where-to-watch link for the middle column; nil hides it.
  var watch: WatchLink? = nil

  private var isHomeFavorite: Bool {
    guard let fav = game.derivedFavoriteTeamId else { return false }
    return fav == game.homeTeamId
  }
  private var hasLine: Bool { game.derivedFavoriteTeamId != nil }
  private var isLive: Bool { game.status == "in_progress" }
  private var isFinal: Bool { game.status == "final" }
  private var showScore: Bool { (isLive || isFinal) && game.homePoints != nil && game.awayPoints != nil }
  /// Same as the web's normalize().locked: final, not scheduled, or past kickoff.
  private var isLocked: Bool {
    isFinal || game.picksLocked == true || (game.status != nil && game.status != "scheduled") || game.startTime <= Date()
  }

  // Short names only where the long one would cut off (de-slop #13).
  private var favName: String { isHomeFavorite ? (game.homeDisplay ?? "Home") : (game.awayDisplay ?? "Away") }
  private var dogName: String { isHomeFavorite ? (game.awayDisplay ?? "Away") : (game.homeDisplay ?? "Home") }
  private var favId: UUID? { isHomeFavorite ? game.homeTeamId : game.awayTeamId }
  private var dogId: UUID? { isHomeFavorite ? game.awayTeamId : game.homeTeamId }
  private var favScore: Int? { isHomeFavorite ? game.homePoints : game.awayPoints }
  private var dogScore: Int? { isHomeFavorite ? game.awayPoints : game.homePoints }
  private var favAhead: Bool { showScore && (favScore ?? 0) > (dogScore ?? 0) }
  private var dogAhead: Bool { showScore && (dogScore ?? 0) > (favScore ?? 0) }
  /// Outright win only -- the real scoring rule.
  private var dogWonOutright: Bool { isFinal && dogAhead }

  private var spreadText: String? {
    game.underdogSpread.map { "+\(jsNumber($0))" }
  }

  private var timeText: String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: game.startTime)
  }

  /// Locked, live, finished or unlined rows read quieter -- by switching
  /// text to the dim gray (still >= 4.5:1) and fading only the logos, not by
  /// fading the whole row (that took text below WCAG contrast).
  private var dimmed: Bool {
    if isSelected { return false }
    let noLine = !hasLine && !isLocked && !isFinal
    return isLocked || isLive || isFinal || noLine
  }

  // Picked row floods green, so text flips light there.
  private var ink: Color { isSelected ? SUPColors.textOnGreen : dimmed ? BoldTheme.Colors.textDim : BoldTheme.Colors.text }
  /// The +line is bold ink (de-slop #5); light on the green picked row.
  private var goldText: Color { isSelected ? SUPColors.textOnGreen : dimmed ? BoldTheme.Colors.textDim : BoldTheme.Role.line }
  /// Secondary text in the row (kickoff time, losing score).
  private var quiet: Color { isSelected ? SUPColors.textOnGreen.opacity(0.8) : BoldTheme.Colors.textDim }

  var body: some View {
    HStack(spacing: 8) {
      // Favorite (left)
      HStack(spacing: 8) {
        logo(favId)
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: (isHomeFavorite ? "@\u{00A0}" : "") + favName)
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(ink)
            .lineLimit(3)
            .minimumScaleFactor(0.85)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity)
      .padding(showScore && favAhead && !isSelected ? 5 : 0)
      .background(RoundedRectangle(cornerRadius: 10).fill(showScore && favAhead && !isSelected ? BoldTheme.Colors.green.opacity(0.1) : .clear))

      middleColumn
        .fixedSize()

      // Underdog (right)
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 1) {
          Text(verbatim: (isHomeFavorite ? "" : "@\u{00A0}") + dogName)
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(ink)
            .lineLimit(3)
            .multilineTextAlignment(.trailing)
            .minimumScaleFactor(0.85)
          actionChip
        }
        logo(dogId)
      }
      .frame(maxWidth: .infinity)
      .padding(showScore && dogAhead && !isSelected ? 5 : 0)
      .background(RoundedRectangle(cornerRadius: 10).fill(showScore && dogAhead && !isSelected ? BoldTheme.Role.wonTint : .clear))
    }
    .padding(.vertical, 14)
    // 12pt inside the day card; the row carries its own card background so
    // the swipe-to-pick slide moves the whole row (GamesView.SwipeToPickRow).
    .padding(.horizontal, 12)
    .background(cardRowBackground)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var middleColumn: some View {
    VStack(spacing: 3) {
      if showScore {
        HStack(spacing: 1) {
          Text("\(favScore ?? 0)").foregroundColor(favAhead ? (isSelected ? ink : BoldTheme.Colors.green) : quiet)
          Text("–").foregroundColor(quiet)
          Text("\(dogScore ?? 0)").foregroundColor(dogAhead ? (isSelected ? ink : BoldTheme.Colors.text) : quiet)
        }
        .font(BoldTheme.Fonts.display(28))
        Text(dogWonOutright ? "Upset \(spreadText ?? "")".trimmingCharacters(in: .whitespaces) : (spreadText ?? "—"))
          .font(BoldTheme.Fonts.body(12, weight: dogWonOutright ? .bold : .medium))
          .foregroundColor(dogWonOutright ? goldText : BoldTheme.Colors.textFaint)
        if isLive { LiveDot(color: isSelected ? SUPColors.textOnGreen : Color(hex: 0xC6402A)) }
      } else {
        Text(spreadText ?? "—")
          .font(BoldTheme.TypeRole.line(30))
          .foregroundColor(hasLine ? goldText : BoldTheme.Colors.textFaint)
        Text(timeText)
          .font(BoldTheme.Fonts.body(12, weight: .medium))
          .foregroundColor(quiet)
      }
      if let watch, !isFinal {
        WatchPill(link: watch, live: isLive || (isLocked && !isFinal))
          .padding(.top, 2)
      }
    }
    .frame(minWidth: 74)
  }

  /// "Your pick" / "Won +3" / "No win" on the picked row; "Line not
  /// posted" when there's no line yet. No PICK button (de-slop #12).
  @ViewBuilder private var actionChip: some View {
    if isSelected {
      Text(isFinal ? (dogWonOutright ? "✓ Won \(spreadText ?? "")" : "No win") : "✓ Your pick")
        .font(BoldTheme.Fonts.body(11, weight: .bold))
        .foregroundColor(SUPColors.textOnGreen.opacity(isFinal && !dogWonOutright ? 0.8 : 1))
        .padding(.top, 3)
    } else if !hasLine && !isLocked {
      Text("Line not posted")
        .font(BoldTheme.Fonts.body(10.5, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)
        .padding(.top, 3)
    }
  }

  /// Part of the day's flat card: the day header row sits above, so only
  /// the last game rounds its bottom corners. Hairline between games.
  private var cardRowBackground: some View {
    let r = BoldTheme.Radius.card
    return UnevenRoundedRectangle(
      topLeadingRadius: isFirstInDay ? r : 0,
      bottomLeadingRadius: isLastInDay ? r : 0,
      bottomTrailingRadius: isLastInDay ? r : 0,
      topTrailingRadius: isFirstInDay ? r : 0,
      style: .continuous
    )
    .fill(isSelected ? BoldTheme.Colors.green : BoldTheme.Colors.card)
    .overlay(alignment: .top) {
      if !isFirstInDay { Rectangle().fill(BoldTheme.Colors.border).frame(height: 1) }
    }
  }

  /// The row's outline, for clipping the swipe action to the card.
  static func cardShape(isLastInDay: Bool) -> UnevenRoundedRectangle {
    let r = isLastInDay ? BoldTheme.Radius.card : 0
    return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
  }

  @ViewBuilder private func logo(_ id: UUID?) -> some View {
    RetryingAsyncImage(url: logoFor(id)) { img in
      img.resizable().scaledToFit()
    } placeholder: {
      Image(systemName: "football").resizable().scaledToFit().opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
    }
    .frame(width: 30, height: 30)
    .opacity(dimmed ? 0.55 : 1)
  }
}

/// Small pulsing dot + "LIVE".
private struct LiveDot: View {
  var color: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false
  var body: some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 6, height: 6)
        .opacity(pulsing ? 0.35 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
      Text("Live").font(BoldTheme.Fonts.body(12, weight: .bold)).foregroundColor(color)
    }
    .onAppear { if !reduceMotion { pulsing = true } }
  }
}
