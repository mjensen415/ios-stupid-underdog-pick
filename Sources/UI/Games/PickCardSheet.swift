import SwiftUI
import Supabase

/// The pick card ("game card") for CFB and Pro Ball -- native port of the
/// web's BoldSheetContent in src/pages/IndexBold.tsx. Kickoff, the two teams
/// with logos level (favorite left, underdog right, VS between), the "you
/// bank +N" box and a big LOCK IN button. Pro members also get each team's
/// LAST 3 and where-to-watch chips. The pick itself still goes through
/// GamesViewModel.pickUnderdog / clearPickForWeek (same server calls).
struct PickCardSheet: View {
  /// The game as it was when the card opened. Everything on the card reads
  /// `shown`, which picks up a moved line once the player confirms it.
  let game: Game
  let logoFor: (UUID?) -> URL?
  /// This game is already the user's pick for the week.
  let isCurrentPick: Bool
  /// The user has a pick elsewhere this week (LOCK IN replaces it).
  let hasOtherPick: Bool
  let isPro: Bool
  /// watch_links is on (or admin) and the game has an ESPN id.
  let watchEnabled: Bool
  let watchLinks: [WatchLink]
  /// Re-reads the line just before locking (web parity: IndexBold's
  /// fetchCurrentDogSpread). Defaults to "unchanged" for previews/tests.
  var checkLine: (Game) async -> LineCheck = { _ in .unchanged }
  /// Locks the given game (with the confirmed line). True when it saved.
  let onLock: (Game) async -> Bool
  let onClear: () async -> Void

  @Environment(\.supabaseClient) private var client
  @Environment(\.dismiss) private var dismiss
  @State private var form: (fav: [FormGame], dog: [FormGame])?
  @State private var loadingForm = false
  @State private var working = false
  @State private var lockedTick = 0
  @State private var shown: Game
  /// Set when the re-check found a new number for the same underdog.
  @State private var movedSpread: Double?
  @State private var lineFlipped = false
  @State private var checkingLine = false

  init(game: Game, logoFor: @escaping (UUID?) -> URL?, isCurrentPick: Bool, hasOtherPick: Bool, isPro: Bool,
       watchEnabled: Bool, watchLinks: [WatchLink], checkLine: @escaping (Game) async -> LineCheck = { _ in .unchanged },
       onLock: @escaping (Game) async -> Bool, onClear: @escaping () async -> Void,
       initialMovedSpread: Double? = nil) {
    self.game = game
    self.logoFor = logoFor
    self.isCurrentPick = isCurrentPick
    self.hasOtherPick = hasOtherPick
    self.isPro = isPro
    self.watchEnabled = watchEnabled
    self.watchLinks = watchLinks
    self.checkLine = checkLine
    self.onLock = onLock
    self.onClear = onClear
    _shown = State(initialValue: game)
    // Lets the snapshot test render the "line moved" state without a tap.
    _movedSpread = State(initialValue: initialMovedSpread)
  }

  private var homeIsDog: Bool { shown.derivedUnderdogTeamId != nil && shown.derivedUnderdogTeamId == shown.homeTeamId }
  private var favName: String { homeIsDog ? (shown.awayTeam ?? "Away") : (shown.homeTeam ?? "Home") }
  private var dogName: String { homeIsDog ? (shown.homeTeam ?? "Home") : (shown.awayTeam ?? "Away") }
  private var favId: UUID? { homeIsDog ? shown.awayTeamId : shown.homeTeamId }
  private var dogId: UUID? { homeIsDog ? shown.homeTeamId : shown.awayTeamId }
  private var spread: String? { shown.underdogSpread.map(jsNumber) }

  private var kickoffText: String {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d · h:mm a"
    return f.string(from: shown.startTime).uppercased()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(kickoffText)
          .font(BoldTheme.Fonts.display(14))
          .tracking(2.6)
          .foregroundColor(BoldTheme.Colors.goldDeep)

        // Logos sit in fixed 64pt boxes so both teams line up at the same
        // height, with VS level with them.
        HStack(alignment: .top, spacing: 12) {
          teamColumn(logo: logoFor(favId), label: "FAVORITE", labelColor: BoldTheme.Colors.textDim,
                     name: (homeIsDog ? "" : "@ ") + favName, nameColor: BoldTheme.Colors.text) {
            if let spread {
              Text(verbatim: "-\(spread)")
                .font(BoldTheme.Fonts.body(14))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
          }
          Text("VS")
            .font(BoldTheme.Fonts.display(32))
            .tracking(1.9)
            .foregroundColor(BoldTheme.Colors.text.opacity(0.4))
            .frame(height: 64)
          teamColumn(logo: logoFor(dogId), label: "UNDERDOG", labelColor: BoldTheme.Colors.goldDeep,
                     name: (homeIsDog ? "@ " : "") + dogName, nameColor: BoldTheme.Colors.goldDeep) {
            if let spread {
              Text(verbatim: "+\(spread)")
                .font(BoldTheme.Fonts.display(34))
                .foregroundColor(BoldTheme.Colors.goldDeep)
            }
          }
        }
        .padding(.vertical, 20)

        if isPro {
          HStack(alignment: .top, spacing: 10) {
            RecentFormBox(games: form?.fav, loading: loadingForm)
            RecentFormBox(games: form?.dog, loading: loadingForm)
          }
          .padding(.bottom, 16)
        }

        if let spread {
          (Text("If ") + Text(dogName).bold() + Text(" wins outright, you bank ")
            + Text("+\(spread)").bold().foregroundColor(BoldTheme.Colors.goldDeep) + Text(" points."))
            .font(BoldTheme.Fonts.body(13.5))
            .foregroundColor(BoldTheme.Colors.text)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(BoldTheme.Colors.green.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BoldTheme.Colors.green.opacity(0.15), lineWidth: 1))
            .padding(.bottom, 14)
        }

        if shown.sport == "nfl" && !isCurrentPick {
          Text("Pro Ball lines move during the week. Your line locks in when you pick.")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
            .padding(.bottom, 12)
        }

        if watchEnabled {
          HStack {
            Spacer()
            if isPro {
              WatchChips(links: watchLinks, live: shown.status == "in_progress")
            } else {
              WatchProTeaser()
            }
            Spacer()
          }
          .padding(.bottom, 14)
        }

        if isCurrentPick {
          Text("This is your pick for the week.")
            .font(BoldTheme.Fonts.body(13, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.green)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
          Button {
            Task {
              working = true
              await onClear()
              working = false
              dismiss()
            }
          } label: {
            Text(working ? "CLEARING…" : "CLEAR PICK")
              .font(BoldTheme.Fonts.display(20))
              .tracking(1)
              .foregroundColor(BoldTheme.Colors.text)
              .frame(maxWidth: .infinity, minHeight: 54)
              .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1.5))
          }
          .buttonStyle(.plain)
          .disabled(working)
        } else {
          if let movedSpread {
            movedLineConfirm(movedSpread)
          } else if lineFlipped {
            Text("The line flipped since you opened this game. \(dogName) isn't the underdog anymore. Close it and pick again.")
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(BoldTheme.Colors.text)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 14).padding(.vertical, 12)
              .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BoldTheme.Colors.gold, lineWidth: 1))
          } else {
          Button {
            Task { await lockIn() }
          } label: {
            Text(checkingLine ? "CHECKING LATEST LINE…" : working ? "LOCKING IN…" : "LOCK IN \(dogName.uppercased())")
              .font(BoldTheme.Fonts.display(22))
              .tracking(1)
              .lineLimit(1)
              .minimumScaleFactor(0.6)
              .foregroundColor(BoldTheme.Colors.gold)
              .frame(maxWidth: .infinity, minHeight: 58)
              .padding(.horizontal, 12)
              .background(RoundedRectangle(cornerRadius: 14).fill(BoldTheme.Colors.green))
          }
          .buttonStyle(.plain)
          .disabled(working || checkingLine)
          .accessibilityHint(hasOtherPick ? "Replaces your current pick for this week" : "")
          }
          if hasOtherPick {
            Text("This replaces your current pick for the week.")
              .font(BoldTheme.Fonts.body(11.5))
              .foregroundColor(BoldTheme.Colors.textDim)
              .frame(maxWidth: .infinity)
              .padding(.top, 8)
          }
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 24)
      .padding(.bottom, 28)
    }
    .background(BoldTheme.Colors.track.ignoresSafeArea())
    .presentationDetents(isPro ? [.large] : [.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(BoldTheme.Colors.track)
    .sensoryFeedback(.success, trigger: lockedTick)
    .task(id: shown.id) { await loadForm() }
  }

  @ViewBuilder
  private func teamColumn<Extra: View>(logo: URL?, label: String, labelColor: Color, name: String, nameColor: Color,
                                        @ViewBuilder extra: () -> Extra) -> some View {
    VStack(spacing: 2) {
      RetryingAsyncImage(url: logo) { img in
        img.resizable().scaledToFit()
      } placeholder: {
        Image(systemName: "football").resizable().scaledToFit().padding(10).opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
      }
      .frame(width: 64, height: 64)
      Text(label)
        .font(BoldTheme.Fonts.body(10, weight: .semibold))
        .tracking(1.2)
        .foregroundColor(labelColor)
        .padding(.top, 8)
      Text(verbatim: name.uppercased())
        .font(BoldTheme.Fonts.display(22))
        .foregroundColor(nameColor)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
      extra()
        .padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
  }

  /// Web's lockIn(): re-check the line, pause on a change, else commit.
  private func lockIn() async {
    checkingLine = true
    let check = await checkLine(shown)
    checkingLine = false
    switch check {
    case .unchanged: await commit(shown)
    case .moved(let spread): movedSpread = spread
    case .flipped: lineFlipped = true
    }
  }

  /// Web's confirmMovedSpread(): take the new number (same underdog, so the
  /// home-relative sign is unchanged) and lock in at it.
  private func confirmMovedSpread() async {
    guard let spread = movedSpread else { return }
    let homeIsDogNow = homeIsDog
    shown = shown.withLatestSpread(homeIsDogNow ? spread : -spread)
    movedSpread = nil
    await commit(shown)
  }

  private func commit(_ g: Game) async {
    working = true
    let saved = await onLock(g)
    working = false
    if saved { lockedTick += 1 }
    dismiss()
  }

  /// Web's "The spread moved -- X is now +N. Confirm at the new number?" box.
  private func movedLineConfirm(_ spread: Double) -> some View {
    VStack(spacing: 10) {
      (Text("The spread moved. \(dogName) is now ")
        + Text(verbatim: "+\(jsNumber(spread))").font(BoldTheme.Fonts.display(17)).foregroundColor(BoldTheme.Colors.goldDeep)
        + Text(". Confirm at the new number?"))
        .font(BoldTheme.Fonts.body(13))
        .foregroundColor(BoldTheme.Colors.text)
        .multilineTextAlignment(.center)
      Button {
        Task { await confirmMovedSpread() }
      } label: {
        Text(working ? "LOCKING IN…" : "CONFIRM AT +\(jsNumber(spread))")
          .font(BoldTheme.Fonts.display(22))
          .tracking(1)
          .foregroundColor(BoldTheme.Colors.green)
          .frame(maxWidth: .infinity, minHeight: 54)
          .background(RoundedRectangle(cornerRadius: 12).fill(BoldTheme.Colors.gold))
      }
      .buttonStyle(.plain)
      .disabled(working)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BoldTheme.Colors.gold, lineWidth: 1))
  }

  private func loadForm() async {
    guard isPro, let client, form == nil else { return }
    loadingForm = true
    defer { loadingForm = false }
    let svc = ProDataService(client: client)
    async let fav = svc.recentForm(sport: shown.sport, teamId: favId, teamName: favName, before: shown.startTime)
    async let dog = svc.recentForm(sport: shown.sport, teamId: dogId, teamName: dogName, before: shown.startTime)
    form = await (fav, dog)
  }
}
