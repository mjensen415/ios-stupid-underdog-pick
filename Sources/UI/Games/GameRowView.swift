import SwiftUI

/// One CFB / Pro Ball game, layout A (matches the web's BoldRow on
/// winner-circle-dev): favorite on the left, underdog on the right, and a
/// centered middle column stacked as the big gold "+3", the kickoff time,
/// then a where-to-watch capsule (Pro). Once there's a score the middle
/// column becomes the scoreboard. Locked, live and finished games dim; the
/// picked game's row turns solid green.
struct GameRowView: View {
  let game: Game
  let logoFor: (UUID?) -> URL?
  let isSelected: Bool
  // Position within its day-group -- rounds only the outer corners so
  // consecutive rows for one day fuse into a single card.
  var isFirstInDay: Bool = false
  var isLastInDay: Bool = false
  /// Tapping the row would open the pick card right now (GamesViewModel.canPick
  /// and not already this game) -- drives the PICK / CHANGE capsule.
  var actionable: Bool = false
  /// The user already has a pick this week (PICK reads CHANGE elsewhere).
  var hasPickThisWeek: Bool = false
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

  private var favName: String { isHomeFavorite ? (game.homeTeam ?? "Home") : (game.awayTeam ?? "Away") }
  private var dogName: String { isHomeFavorite ? (game.awayTeam ?? "Away") : (game.homeTeam ?? "Home") }
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

  // Picked row floods green, so text flips light there.
  private var ink: Color { isSelected ? SUPColors.textOnGreen : BoldTheme.Colors.text }
  private var goldText: Color { isSelected ? BoldTheme.Colors.gold : BoldTheme.Colors.goldDeep }

  private var rowOpacity: Double {
    if isSelected { return 1 }
    let noLine = !hasLine && !isLocked && !isFinal
    return (isLocked || isLive || isFinal || noLine) ? 0.55 : 1
  }

  var body: some View {
    HStack(spacing: 8) {
      // Favorite (left)
      HStack(spacing: 8) {
        logo(favId)
        VStack(alignment: .leading, spacing: 1) {
          Text("FAV")
            .font(BoldTheme.Fonts.body(9.5, weight: .semibold))
            .tracking(1.1)
            .foregroundColor(ink.opacity(0.55))
          Text(verbatim: (isHomeFavorite ? "@ " : "") + favName.uppercased())
            .font(BoldTheme.Fonts.body(12, weight: .semibold))
            .foregroundColor(ink)
            .lineLimit(2)
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
          Text("DOG")
            .font(BoldTheme.Fonts.body(9.5, weight: .semibold))
            .tracking(1.1)
            .foregroundColor(goldText.opacity(0.85))
          Text(verbatim: (isHomeFavorite ? "" : "@ ") + dogName.uppercased())
            .font(BoldTheme.Fonts.body(12, weight: .semibold))
            .foregroundColor(ink)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .minimumScaleFactor(0.85)
          actionChip
        }
        logo(dogId)
      }
      .frame(maxWidth: .infinity)
      .padding(showScore && dogAhead && !isSelected ? 5 : 0)
      .background(RoundedRectangle(cornerRadius: 10).fill(showScore && dogAhead && !isSelected ? BoldTheme.Colors.gold.opacity(0.18) : .clear))
    }
    .opacity(rowOpacity)
    .padding(.vertical, 14)
    .padding(.horizontal, 6)
    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparatorTint(BoldTheme.Colors.border)
    .listRowSeparator(isLastInDay ? .hidden : .visible, edges: .bottom)
    .listRowSeparator(.hidden, edges: .top)
    .listRowBackground(cardRowBackground)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var middleColumn: some View {
    VStack(spacing: 3) {
      if showScore {
        HStack(spacing: 1) {
          Text("\(favScore ?? 0)").foregroundColor(favAhead ? (isSelected ? ink : BoldTheme.Colors.green) : ink.opacity(0.4))
          Text("–").foregroundColor(ink.opacity(0.35))
          Text("\(dogScore ?? 0)").foregroundColor(dogAhead ? goldText : ink.opacity(0.4))
        }
        .font(BoldTheme.Fonts.display(28))
        Text(dogWonOutright ? "UPSET \(spreadText ?? "")".trimmingCharacters(in: .whitespaces) : (spreadText ?? "—"))
          .font(BoldTheme.Fonts.mono(10, weight: dogWonOutright ? .bold : .regular))
          .foregroundColor(dogWonOutright ? goldText : BoldTheme.Colors.textFaint)
        if isLive { LiveDot(color: isSelected ? SUPColors.textOnGreen : Color(hex: 0xC6402A)) }
      } else {
        Text(spreadText ?? "—")
          .font(BoldTheme.Fonts.display(26))
          .foregroundColor(hasLine ? goldText : BoldTheme.Colors.textFaint)
        Text(timeText)
          .font(BoldTheme.Fonts.mono(10.5, weight: .semibold))
          .foregroundColor(ink.opacity(0.7))
      }
      if let watch, !isFinal {
        WatchPill(link: watch, live: isLive || (isLocked && !isFinal))
          .padding(.top, 2)
      }
    }
    .frame(minWidth: 64)
  }

  /// PICK / CHANGE while pickable; ✓ PICK / WON / NO WIN on the picked row;
  /// "line not posted" when there's no line yet.
  @ViewBuilder private var actionChip: some View {
    if isSelected {
      if isFinal {
        Text(dogWonOutright ? "✓ WON \(spreadText ?? "")" : "NO WIN")
          .font(BoldTheme.Fonts.body(9.5, weight: .bold))
          .tracking(1)
          .foregroundColor(dogWonOutright ? BoldTheme.Colors.gold : SUPColors.textOnGreen.opacity(0.6))
          .padding(.top, 3)
      } else {
        Text("✓ PICK")
          .font(BoldTheme.Fonts.body(9.5, weight: .bold))
          .tracking(1)
          .foregroundColor(BoldTheme.Colors.gold)
          .padding(.top, 3)
      }
    } else if !hasLine && !isLocked {
      Text("LINE NOT POSTED")
        .font(BoldTheme.Fonts.body(8.5, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)
        .padding(.top, 3)
    } else if actionable {
      Text(hasPickThisWeek ? "CHANGE" : "PICK")
        .font(BoldTheme.Fonts.body(9.5, weight: .bold))
        .tracking(1)
        .foregroundColor(BoldTheme.Colors.goldDeep)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(BoldTheme.Colors.goldDeep, lineWidth: 1))
        .padding(.top, 3)
    }
  }

  private var cardRowBackground: some View {
    UnevenRoundedRectangle(
      topLeadingRadius: isFirstInDay ? 16 : 0,
      bottomLeadingRadius: isLastInDay ? 16 : 0,
      bottomTrailingRadius: isLastInDay ? 16 : 0,
      topTrailingRadius: isFirstInDay ? 16 : 0
    )
    .fill(isSelected ? BoldTheme.Colors.green : BoldTheme.Colors.glassStrong)
    .padding(.horizontal, 12)
  }

  @ViewBuilder private func logo(_ id: UUID?) -> some View {
    RetryingAsyncImage(url: logoFor(id)) { img in
      img.resizable().scaledToFit()
    } placeholder: {
      Image(systemName: "football").resizable().scaledToFit().opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
    }
    .frame(width: 30, height: 30)
  }
}

/// Small pulsing dot + "LIVE".
private struct LiveDot: View {
  var color: Color
  @State private var pulsing = false
  var body: some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 6, height: 6)
        .opacity(pulsing ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
      Text("LIVE").font(BoldTheme.Fonts.mono(9.5, weight: .bold)).foregroundColor(color)
    }
    .onAppear { pulsing = true }
  }
}
