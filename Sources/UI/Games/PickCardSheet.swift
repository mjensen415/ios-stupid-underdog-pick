import SwiftUI
import Supabase

/// The pick card ("game card") for CFB and Pro Ball -- native port of the
/// web's BoldSheetContent in src/pages/IndexBold.tsx. Kickoff, the two teams
/// side by side (favorite left, underdog right), the "If X wins, you get N
/// points" line and the yellow "Lock in X · +N" button. The sheet is as
/// tall as its content (de-slop #23). Pro members also get each team's
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
  /// Full names -- used for the recent-form lookup's name fallback.
  private var favName: String { homeIsDog ? (shown.awayTeam ?? "Away") : (shown.homeTeam ?? "Home") }
  private var dogName: String { homeIsDog ? (shown.homeTeam ?? "Home") : (shown.awayTeam ?? "Away") }
  /// What the card shows: the short name when the long one would cut off.
  private var favLabel: String { homeIsDog ? (shown.awayDisplay ?? "Away") : (shown.homeDisplay ?? "Home") }
  private var dogLabel: String { homeIsDog ? (shown.homeDisplay ?? "Home") : (shown.awayDisplay ?? "Away") }
  private var favId: UUID? { homeIsDog ? shown.awayTeamId : shown.homeTeamId }
  private var dogId: UUID? { homeIsDog ? shown.homeTeamId : shown.awayTeamId }
  private var spread: String? { shown.underdogSpread.map(jsNumber) }

  private var kickoffText: String {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d · h:mm a"
    return f.string(from: shown.startTime)
  }

  @State private var contentHeight: CGFloat = 460

  private var shownLocked: Bool {
    shown.picksLocked == true || shown.startTime <= Date() || (shown.status != nil && shown.status != "scheduled")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: BoldTheme.Space.s4) {
        Text(kickoffText)
          .font(BoldTheme.Fonts.body(14, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.textDim)
          .frame(maxWidth: .infinity)

        // The two teams side by side, no "VS" (de-slop #25).
        HStack(alignment: .top, spacing: BoldTheme.Space.s3) {
          teamColumn(logo: logoFor(favId), label: "FAVORITE", name: (homeIsDog ? "" : "@\u{00A0}") + favLabel) {
            if let spread {
              Text(verbatim: "−\(spread)")
                .font(BoldTheme.TypeRole.line(30))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
          }
          teamColumn(logo: logoFor(dogId), label: "UNDERDOG", name: (homeIsDog ? "@\u{00A0}" : "") + dogLabel) {
            if let spread {
              Text(verbatim: "+\(spread)")
                .font(BoldTheme.TypeRole.line(40))
                .foregroundColor(BoldTheme.Role.line)
            }
          }
        }

        if isPro {
          HStack(alignment: .top, spacing: BoldTheme.Space.s2) {
            RecentFormBox(games: form?.fav, loading: loadingForm)
            RecentFormBox(games: form?.dog, loading: loadingForm)
          }
        }

        if let spread {
          (Text("If ") + Text(dogLabel).bold() + Text(" wins, you get ")
            + Text(verbatim: "\(spread) \(spread == "1" ? "point" : "points")").bold())
            .font(BoldTheme.Fonts.body(15))
            .foregroundColor(BoldTheme.Colors.text)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.card))
        }

        if shown.sport == "nfl" && !isCurrentPick {
          Text("Pro Ball lines move during the week. Your line locks in when you pick.")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        }

        if isCurrentPick {
          VStack(spacing: BoldTheme.Space.s2) {
            Text(shownLocked ? "This is your pick for the week. It's locked." : "This is your pick for the week.")
              .font(BoldTheme.Fonts.body(14, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.green)
            // Once the game kicks off the pick is final (the server rejects
            // a clear), so no button that can only fail.
            if !shownLocked {
            Button {
              Task {
                working = true
                await onClear()
                working = false
                dismiss()
              }
            } label: {
              Text(working ? "Clearing…" : "Clear pick")
            }
            .buttonStyle(SupSecondaryButtonStyle())
            .disabled(working)
            }
          }
        } else {
          VStack(spacing: BoldTheme.Space.s2) {
            if let movedSpread {
              movedLineConfirm(movedSpread)
            } else if lineFlipped {
              Text("The line flipped since you opened this game. \(dogLabel) isn't the underdog anymore. Close it and pick again.")
                .font(BoldTheme.Fonts.body(14))
                .foregroundColor(BoldTheme.Colors.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.card))
            } else {
              Button {
                Task { await lockIn() }
              } label: {
                if checkingLine {
                  Text("Checking the latest line…")
                } else if working {
                  Text("Locking in…")
                } else {
                  (Text("Lock in \(dogLabel)") + Text(spread.map { " · +\($0)" } ?? ""))
                }
              }
              .buttonStyle(SupPrimaryButtonStyle())
              .disabled(working || checkingLine)
              .accessibilityHint(hasOtherPick ? "Replaces your current pick for this week" : "")
            }
            if hasOtherPick {
              Text("This replaces your current pick for the week.")
                .font(BoldTheme.Fonts.body(12.5))
                .foregroundColor(BoldTheme.Colors.textDim)
            }
          }
        }
      }
      .padding(.horizontal, BoldTheme.Space.margin)
      .padding(.top, BoldTheme.Space.s6)
      .padding(.bottom, BoldTheme.Space.s5)
      .background(GeometryReader { geo in
        Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height)
      })
    }
    .scrollBounceBehavior(.basedOnSize)
    .onPreferenceChange(SheetHeightKey.self) { h in
      if h > 0 { contentHeight = h }
    }
    .background(BoldTheme.Colors.track.ignoresSafeArea())
    // Sized to the content (de-slop #23); scrolls if it ever outgrows the screen.
    .presentationDetents([.height(contentHeight)])
    .presentationDragIndicator(.visible)
    .presentationBackground(BoldTheme.Colors.track)
    .sensoryFeedback(.success, trigger: lockedTick)
    .task(id: shown.id) { await loadForm() }
  }

  @ViewBuilder
  private func teamColumn<Extra: View>(logo: URL?, label: String, name: String,
                                        @ViewBuilder extra: () -> Extra) -> some View {
    VStack(spacing: 6) {
      RetryingAsyncImage(url: logo) { img in
        img.resizable().scaledToFit()
      } placeholder: {
        Image(systemName: "football").resizable().scaledToFit().padding(10).opacity(0.3).foregroundColor(BoldTheme.Colors.textFaint)
      }
      .frame(width: 56, height: 56)
      Text(label)
        .font(BoldTheme.TypeRole.label(10))
        .tracking(1)
        .foregroundColor(BoldTheme.Colors.textDim)
      Text(verbatim: name)
        .font(BoldTheme.TypeRole.teamName(30))
        .foregroundColor(BoldTheme.Colors.text)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      extra()
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
    VStack(spacing: BoldTheme.Space.s3) {
      (Text("The spread moved. \(dogLabel) is now ")
        + Text(verbatim: "+\(jsNumber(spread))").bold()
        + Text(". Confirm at the new number?"))
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.text)
        .multilineTextAlignment(.center)
      Button {
        Task { await confirmMovedSpread() }
      } label: {
        Text(working ? "Locking in…" : "Confirm at +\(jsNumber(spread))")
      }
      .buttonStyle(SupPrimaryButtonStyle())
      .disabled(working)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.card))
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

private struct SheetHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
