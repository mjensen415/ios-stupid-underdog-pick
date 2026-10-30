import SwiftUI
import Supabase

// Hoops (pro basketball) and Pucks (pro hockey) weekly underdog groups --
// one screen with a sport parameter. Native port of the web's
// components/hoopsPucks/SportLeaguePage.tsx. Shown from the game switcher
// while the `hoops` / `pucks` flags are on (admins always).
//
// Teams show by city/location only (daily_games names are already
// city-only), with the self-hosted team logos and an initials-badge
// fallback. No league names, no "BETA". Free to play.

@MainActor
final class SportLeagueViewModel: ObservableObject {
  let sport: HpSport
  @Published var leagues: [HpLeague] = []
  /// This sport's Global league, readable by everyone (role nil).
  @Published var globalLeague: HpLeague?
  @Published var joiningGlobal = false
  @Published var leagueId: UUID?
  @Published var weekStart: String
  @Published var games: [HpGame] = []
  @Published var myPicks: [HpPick] = []
  @Published var weekBoard: [HpBoardRow] = []
  @Published var seasonBoard: [HpBoardRow] = []
  @Published var loading = true
  @Published var busyGame: UUID?
  @Published var toast: (title: String, detail: String?)?
  @Published var broadcasts: [String: [BroadcastNetwork]] = [:]
  @Published var form: [String: [FormGame]] = [:]
  @Published var now = Date()
  /// Bumped when a dog is tapped with no group, to scroll the group card into view.
  @Published var showGroupCardTick = 0

  private var toastTask: Task<Void, Never>?

  init(sport: HpSport) {
    self.sport = sport
    self.weekStart = HP.weekStartET(Date())
  }

  /// Global first, then your own groups. Global is listed even before you join it.
  var sportLeagues: [HpLeague] { GlobalGroups.buildHpLeagueList(mine: leagues, global: globalLeague, sport: sport) }
  var league: HpLeague? { GlobalGroups.pickDefaultHpLeague(sportLeagues, requested: leagueId) }
  /// Viewing Global without being in it yet: a dog tap joins and picks.
  var globalGuest: Bool { GlobalGroups.needsGlobalJoin(league) }
  var inAnyGroup: Bool { sportLeagues.contains(where: \.isMember) }
  var currentWeek: String { HP.weekStartET(now) }
  var isPast: Bool { weekStart < currentWeek }

  var weekPicks: [HpPick] { myPicks.filter { $0.week_start == weekStart } }
  private var gameById: [UUID: HpGame] { Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

  /// Picks that still count against the weekly limit (a void pick gives the slot back).
  var used: Int {
    weekPicks.filter { p in gameById[p.game_id].map { HP.gradePick(p, $0).result != .void } ?? true }.count
  }
  var picksPerWeek: Int { league?.picks_per_week ?? 0 }
  var remaining: Int { max(0, picksPerWeek - used) }
  var myWeekPoints: Double { weekPicks.reduce(0) { s, p in s + (gameById[p.game_id].map { HP.gradePick(p, $0).points } ?? 0) } }
  var canPickWeek: Bool { league != nil && remaining > 0 && !isPast }

  /// ET days, in order.
  var days: [(day: String, games: [HpGame])] {
    var order: [String] = []
    var map: [String: [HpGame]] = [:]
    for g in games {
      let k = HP.etDay(g.start_time)
      if map[k] == nil { order.append(k) }
      map[k, default: []].append(g)
    }
    return order.sorted().map { ($0, map[$0] ?? []) }
  }

  func flash(_ title: String, _ detail: String? = nil) {
    toastTask?.cancel()
    toast = (title, detail)
    toastTask = Task {
      try? await Task.sleep(nanoseconds: 3_200_000_000)
      guard !Task.isCancelled else { return }
      toast = nil
    }
  }

  func loadLeagues(client: SupabaseClient, userId: UUID?) async {
    guard let userId else { return }
    let svc = HoopsPucksService(client: client)
    do {
      leagues = try await svc.myLeagues(userId: userId)
    } catch {
      flash("Couldn't load groups", HoopsPucksService.friendly(error))
    }
    globalLeague = await svc.globalLeague(sport: sport)
  }

  func loadWeek(client: SupabaseClient, userId: UUID?) async {
    now = Date()
    let svc = HoopsPucksService(client: client)
    do {
      games = try await svc.games(sport: sport, weekStart: weekStart)
    } catch {
      flash("Couldn't load games", HoopsPucksService.friendly(error))
    }
    if let league, let userId {
      let guest = globalGuest
      async let picks: [HpPick]? = guest ? [] : (try? svc.myPicks(leagueId: league.id, userId: userId))
      async let wb = try? svc.weeklyBoard(leagueId: league.id, weekStart: weekStart)
      async let sb = try? svc.seasonBoard(leagueId: league.id)
      let (p, w, s) = await (picks, wb, sb)
      myPicks = p ?? []
      weekBoard = w ?? []
      seasonBoard = s ?? []
    } else {
      myPicks = []; weekBoard = []; seasonBoard = []
    }
    loading = false
  }

  func loadPro(client: SupabaseClient, isPro: Bool, watchEnabled: Bool) async {
    let ids = games.compactMap(\.espn_event_id)
    broadcasts = watchEnabled && isPro ? await ProDataService(client: client).broadcasts(eventIds: ids) : [:]
    if isPro && form.isEmpty {
      form = await HoopsPucksService(client: client).recentForm(sport: sport)
    }
  }

  func pick(_ g: HpGame, side: HpSide, client: SupabaseClient, userId: UUID?) async -> Bool {
    // Picks live inside a group: point at starting or joining one first.
    guard let league else {
      showGroupCardTick += 1
      flash("Start or join a group first", "\(sport.name) picks count inside a group. Start one in a few taps, or join with a code.")
      return false
    }
    busyGame = g.id
    defer { busyGame = nil }
    let svc = HoopsPucksService(client: client)
    // Not in the global group yet and looking at it: one tap joins it and picks.
    let joining = globalGuest
    if joining {
      do {
        _ = try await svc.joinGlobal(sport: sport)
      } catch {
        flash("Couldn't join the global group", HoopsPucksService.friendly(error))
        return false
      }
    }
    var pickError: Error?
    do {
      try await svc.makePick(leagueId: league.id, gameId: g.id, side: side)
    } catch {
      pickError = error
    }
    if joining {
      leagueId = league.id
      await loadLeagues(client: client, userId: userId)
    }
    if let pickError {
      flash(joining ? "You're in \(league.name), but the pick didn't save" : "Pick not saved", HoopsPucksService.friendly(pickError))
      if joining { await loadWeek(client: client, userId: userId) }
      return false
    }
    let ml = g.ml(side)
    let pts = HP.pickPoints(sport: g.sport, lockedMl: ml, lockedSpread: g.spread)
    let at = g.sport == .nba ? "\(HP.sideLine(g.spread, side: side)) (\(HP.fmtMl(ml)))" : HP.fmtMl(ml)
    flash("Locked \(g.name(side)) at \(at)", "\(joining ? "You're in \(league.name). " : "")If they win: +\(HP.fmtPts(pts)) pts")
    await loadWeek(client: client, userId: userId)
    return true
  }

  func unpick(_ g: HpGame, client: SupabaseClient, userId: UUID?) async {
    guard let league else { return }
    busyGame = g.id
    defer { busyGame = nil }
    do {
      try await HoopsPucksService(client: client).unpick(leagueId: league.id, gameId: g.id)
      flash("Pick removed")
    } catch {
      flash("Couldn't remove pick", HoopsPucksService.friendly(error))
      return
    }
    await loadWeek(client: client, userId: userId)
  }

  func joinGlobal(client: SupabaseClient, userId: UUID?) async {
    joiningGlobal = true
    defer { joiningGlobal = false }
    do {
      let id = try await HoopsPucksService(client: client).joinGlobal(sport: sport)
      leagueId = id
      await loadLeagues(client: client, userId: userId)
      await loadWeek(client: client, userId: userId)
      flash("You're in \(globalLeague?.name ?? "the global group").", "Pick up to \(globalLeague?.picks_per_week ?? GlobalGroups.picksPerWeek) underdogs this week.")
    } catch {
      flash("Couldn't join the global group", HoopsPucksService.friendly(error))
    }
  }

  func create(name: String, picksPerWeek: Int, client: SupabaseClient, userId: UUID?) async -> Bool {
    do {
      let l = try await HoopsPucksService(client: client).createLeague(name: name, sport: sport, picksPerWeek: picksPerWeek)
      flash("Group started: \(l.name)", "Join code \(l.join_code). Share it with your friends.")
      leagueId = l.id
      await loadLeagues(client: client, userId: userId)
      await loadWeek(client: client, userId: userId)
      return true
    } catch {
      flash("Couldn't start the group", HoopsPucksService.friendly(error))
      return false
    }
  }

  /// Returns the other sport when the code was for that product's group.
  func join(code: String, client: SupabaseClient, userId: UUID?) async -> (ok: Bool, otherSport: HpSport?) {
    let svc = HoopsPucksService(client: client)
    do {
      let id = try await svc.joinLeague(code: code.trimmingCharacters(in: .whitespaces).uppercased())
      if let s = await svc.leagueSport(id: id), s != sport {
        flash("You're in. That's a \(s.name) group.")
        return (true, s)
      }
      leagueId = id
      await loadLeagues(client: client, userId: userId)
      await loadWeek(client: client, userId: userId)
      flash("You're in.")
      return (true, nil)
    } catch {
      flash("Couldn't join", HoopsPucksService.friendly(error))
      return (false, nil)
    }
  }

  func savePicksPerWeek(_ n: Int, client: SupabaseClient, userId: UUID?) async -> Bool {
    guard let league else { return false }
    do {
      try await HoopsPucksService(client: client).updatePicksPerWeek(leagueId: league.id, picksPerWeek: n)
      await loadLeagues(client: client, userId: userId)
      return true
    } catch {
      flash("Not changed", HoopsPucksService.friendly(error))
      return false
    }
  }

  func leave(client: SupabaseClient, userId: UUID?) async {
    guard let league else { return }
    do {
      try await HoopsPucksService(client: client).leaveLeague(id: league.id)
      flash("You left \(league.name).")
      leagueId = nil
      await loadLeagues(client: client, userId: userId)
      await loadWeek(client: client, userId: userId)
    } catch {
      flash("Couldn't leave", HoopsPucksService.friendly(error))
    }
  }
}

struct SportLeagueView: View {
  let sport: HpSport
  @StateObject private var vm: SportLeagueViewModel
  @EnvironmentObject private var appState: AppState
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  @EnvironmentObject private var pro: ProStore
  @Environment(\.supabaseClient) private var client

  private enum Tab: Hashable { case slate, week, season }
  private enum Panel { case create, join }
  @State private var tab: Tab = .slate
  @State private var panel: Panel?
  @State private var newName = ""
  @State private var newPpw = 5.0
  @State private var joinCode = ""
  @State private var editPpw: Double?
  @State private var confirmLeave = false
  @State private var pickedTick = 0
  @FocusState private var focused: Bool

  init(sport: HpSport) {
    self.sport = sport
    _vm = StateObject(wrappedValue: SportLeagueViewModel(sport: sport))
  }

  private var userId: UUID? { appState.session?.user.id }
  private var isPro: Bool { pro.isPro(admin: featureFlags.isAdmin) }
  private var watchEnabled: Bool { featureFlags.isVisible(FeatureFlagKey.watchLinks) }
  private var enabled: Bool { featureFlags.isVisible(sport.flag) }

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GameSwitcher(activeHp: sport)
          header
          if enabled {
            groupCard
              .id("group-card")
            weekRow
            PillToggle(options: [(label: "Slate", value: Tab.slate), (label: "Weekly board", value: .week), (label: "Season", value: .season)],
                       selection: $tab)
            switch tab {
            case .slate: slate
            case .week: boardCard(vm.weekBoard, season: false)
            case .season: boardCard(vm.seasonBoard, season: true)
            }
            finePrint
          } else {
            BoldTheme.GlassCard(strong: true, radius: 18, padding: 18) {
              Text("Weekly \(sport.noun) underdog groups are coming soon.")
                .font(BoldTheme.Fonts.body(14))
                .foregroundColor(BoldTheme.Colors.textDim)
                .frame(maxWidth: .infinity)
            }
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 40)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable { await reload() }
      // Opaque strip behind the status bar so cards don't scroll under the clock.
      .safeAreaInset(edge: .top, spacing: 0) {
        Color.clear.frame(height: 0).background(BoldTheme.Colors.bgPage)
      }
      .onChange(of: vm.showGroupCardTick) { _, _ in
        withAnimation { proxy.scrollTo("group-card", anchor: .top) }
      }
      }

      if let t = vm.toast {
        VStack {
          Spacer()
          VStack(spacing: 2) {
            Text(t.title).font(BoldTheme.Fonts.body(13.5, weight: .bold))
            if let d = t.detail { Text(d).font(BoldTheme.Fonts.body(12)).opacity(0.85) }
          }
          .multilineTextAlignment(.center)
          .foregroundColor(SUPColors.textOnGreen)
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(RoundedRectangle(cornerRadius: 14).fill(BoldTheme.Colors.green))
          .padding(.horizontal, 24)
          .padding(.bottom, 14)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: vm.toast?.title)
      }
    }
    .sensoryFeedback(.success, trigger: pickedTick)
    .task {
      guard let client else { return }
      await vm.loadLeagues(client: client, userId: userId)
      await vm.loadWeek(client: client, userId: userId)
      await vm.loadPro(client: client, isPro: isPro, watchEnabled: watchEnabled)
    }
    // Live scores: refresh while the page is open, faster with games live.
    .task(id: vm.games.contains { $0.status == "in_progress" }) {
      let live = vm.games.contains { $0.status == "in_progress" }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64((live ? 30 : 120) * 1_000_000_000))
        guard !Task.isCancelled, let client else { return }
        await vm.loadWeek(client: client, userId: userId)
      }
    }
    .onChange(of: vm.weekStart) { _, _ in Task { await reload() } }
    .onChange(of: vm.leagueId) { _, _ in Task { await reload() } }
    .onChange(of: isPro) { _, _ in Task { await reload() } }
    .confirmationDialog("Leave \(vm.league?.name ?? "this group")?", isPresented: $confirmLeave, titleVisibility: .visible) {
      Button("Leave group", role: .destructive) {
        Task { if let client { await vm.leave(client: client, userId: userId) } }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(vm.league?.is_global == true
           ? "Your picks aren't deleted. You can rejoin any time with one tap, and your picks come back with you."
           : "Your picks in this group stay on its boards.")
    }
  }

  private func reload() async {
    guard let client else { return }
    await vm.loadWeek(client: client, userId: userId)
    await vm.loadPro(client: client, isPro: isPro, watchEnabled: watchEnabled)
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(sport.noun.prefix(1).uppercased() + sport.noun.dropFirst()) · weekly underdogs\(featureFlags.isOn(sport.flag) ? "" : " · admin preview")")
        .font(BoldTheme.Fonts.body(13, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textDim)
      Text(sport.name)
        .font(BoldTheme.Fonts.body(30, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)
      Text("Join the global group (\(GlobalGroups.picksPerWeek) dogs a week), or start your own. Pick underdogs from any \(sport.noun) game, Monday to Sunday, and climb the weekly board. "
           + (sport == .nba
              ? "If a dog wins outright, you get the points it was getting: +3.5 = 3.5 pts. Covering isn't enough."
              : "A dog that wins outright pays its moneyline: +150 = 1.50 pts.")
           + " Your line locks when you pick. Free to play.")
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.textDim)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: Group card

  /// Global: site admins only. Your own group: its admins.
  private var canEdit: Bool { GlobalGroups.canEdit(vm.league, isSiteAdmin: featureFlags.isAdmin) }

  private var groupCard: some View {
    BoldTheme.FlatCard {
      VStack(alignment: .leading, spacing: 12) {
        if let league = vm.league {
          HStack(spacing: 8) {
            Image(systemName: league.is_global ? "globe" : "person.3.fill").foregroundColor(BoldTheme.Colors.text).font(.system(size: 14))
            if vm.sportLeagues.count > 1 {
              Menu {
                ForEach(vm.sportLeagues) { l in
                  Button(l.is_global ? "\(l.name) · everyone" : l.name) { vm.leagueId = l.id }
                }
              } label: {
                HStack(spacing: 4) {
                  Text(league.name).font(BoldTheme.Fonts.body(18, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
                  Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundColor(BoldTheme.Colors.textDim)
                }
              }
            } else {
              Text(league.name).font(BoldTheme.Fonts.body(18, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
            }
            Spacer(minLength: 4)
            if !league.is_global || canEdit || league.isMember {
              Menu {
                if !league.is_global {
                  Button { UIPasteboard.general.string = league.join_code; vm.flash("Copied join code \(league.join_code)") } label: {
                    Label("Copy join code", systemImage: "doc.on.doc")
                  }
                  ShareLink(item: "Join my \(sport.name) group on Stupid Underdog Pick. Code: \(league.join_code)") {
                    Label("Share join code", systemImage: "square.and.arrow.up")
                  }
                }
                if canEdit {
                  Button { editPpw = Double(league.picks_per_week) } label: { Label("Edit underdogs per week", systemImage: "slider.horizontal.3") }
                }
                if league.isMember {
                  Button(role: .destructive) { confirmLeave = true } label: { Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right") }
                }
              } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundColor(BoldTheme.Colors.textDim)
              }
              .accessibilityLabel("Group options")
            }
          }
          HStack(spacing: 8) {
            if league.is_global {
              SupPill(text: "Everyone", kind: .gray)
            } else {
              Button {
                UIPasteboard.general.string = league.join_code
                vm.flash("Copied join code \(league.join_code)")
              } label: {
                Label(league.join_code, systemImage: "doc.on.doc")
                  .font(BoldTheme.Fonts.code(12, weight: .semibold))
                  .foregroundColor(BoldTheme.Colors.text)
                  .padding(.horizontal, 10).padding(.vertical, 5)
                  .overlay(Capsule().strokeBorder(BoldTheme.Colors.text, lineWidth: 1.5))
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Copy join code \(league.join_code)")
            }
            Spacer()
            chip("\(league.picks_per_week) \(league.picks_per_week == 1 ? "dog" : "dogs") a week")
          }
          if let n = editPpw {
            VStack(alignment: .leading, spacing: 8) {
              Text("Underdogs per week: \(Int(n))").font(BoldTheme.Fonts.body(13, weight: .semibold))
              Slider(value: Binding(get: { editPpw ?? n }, set: { editPpw = $0 }), in: 1...10, step: 1)
                .tint(BoldTheme.Colors.text)
              HStack {
                primaryButton("Save") {
                  Task {
                    guard let client else { return }
                    if await vm.savePicksPerWeek(Int(n), client: client, userId: userId) { editPpw = nil }
                  }
                }
                secondaryButton("Cancel") { editPpw = nil }
              }
              Text("Can only change before anyone in the group picks this week." + (league.is_global ? " This is the global group: the change applies to everyone." : ""))
                .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
            }
          }
          if league.is_global {
            Text("\(GlobalGroups.tagline) \(league.picks_per_week) underdogs a week, Monday to Sunday ET. Free to play.")
              .font(BoldTheme.Fonts.body(13))
              .foregroundColor(BoldTheme.Colors.textDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          if vm.globalGuest {
            VStack(spacing: 6) {
              Button {
                Task { if let client { await vm.joinGlobal(client: client, userId: userId) } }
              } label: {
                HStack(spacing: 8) {
                  if vm.joiningGlobal { ProgressView().tint(BoldTheme.Colors.text) } else { Image(systemName: "person.3.fill") }
                  Text(GlobalGroups.joinCTA)
                }
              }
              // The page's one primary action while you're a guest.
              .buttonStyle(SupPrimaryButtonStyle())
              .disabled(vm.joiningGlobal)
              .accessibilityIdentifier("joinGlobalButton")
              Text("Or just tap a dog below: that joins you and makes the pick.")
                .font(BoldTheme.Fonts.body(13))
                .foregroundColor(BoldTheme.Colors.textDim)
                .frame(maxWidth: .infinity)
            }
          }
        } else {
          Text("Start or join a \(sport.name) group")
            .font(BoldTheme.Fonts.body(18, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
          Text("Start a group for your friends and choose how many underdogs everyone picks each week (1 to 10), or join one with a code. You can browse this week's slate below either way.")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }

        if vm.league != nil && !vm.inAnyGroup {
          Text("Want your own? Pick how many dogs your friends play (1 to 10).")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        HStack(spacing: 8) {
          togglePanelButton("Start a group", systemImage: "plus", panel: .create)
          togglePanelButton("Join with a code", systemImage: nil, panel: .join)
        }

        if panel == .create { createPanel }
        if panel == .join { joinPanel }
      }
    }
  }

  private var createPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("Group name", text: $newName)
        .font(BoldTheme.Fonts.body(14))
        .focused($focused)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
        .onChange(of: newName) { _, v in if v.count > 60 { newName = String(v.prefix(60)) } }
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text("Pick how many underdogs per week").font(BoldTheme.Fonts.body(14, weight: .bold))
          Spacer()
          Text("\(Int(newPpw))").font(BoldTheme.Fonts.display(30)).foregroundColor(BoldTheme.Colors.text)
        }
        Slider(value: $newPpw, in: 1...10, step: 1)
          .tint(BoldTheme.Colors.text)
          .accessibilityLabel("Underdogs per week")
          .accessibilityValue("\(Int(newPpw))")
        HStack {
          Text("1 · one big swing")
          Spacer()
          Text("10 · a full card")
        }
        .font(BoldTheme.Fonts.body(12))
        .foregroundColor(BoldTheme.Colors.textDim)
      }
      Text("Everyone in your group picks \(Int(newPpw)) \(Int(newPpw) == 1 ? "underdog" : "underdogs") each week from any \(sport.noun) game. Free to play.")
        .font(BoldTheme.Fonts.body(12))
        .foregroundColor(BoldTheme.Colors.textDim)
      primaryButton("Start the group", full: true) {
        Task {
          guard let client else { return }
          focused = false
          if await vm.create(name: newName.trimmingCharacters(in: .whitespaces), picksPerWeek: Int(newPpw), client: client, userId: userId) {
            panel = nil; newName = ""
          }
        }
      }
      .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
      .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
    }
  }

  private var joinPanel: some View {
    HStack(spacing: 8) {
      TextField("Join code", text: $joinCode)
        .font(BoldTheme.Fonts.code(15, weight: .semibold))
        .tracking(1.8)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .focused($focused)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
        .onChange(of: joinCode) { _, v in
          let up = String(v.uppercased().prefix(6))
          if up != v { joinCode = up }
        }
      primaryButton("Join") {
        Task {
          guard let client else { return }
          focused = false
          let r = await vm.join(code: joinCode, client: client, userId: userId)
          if r.ok { panel = nil; joinCode = "" }
          if let other = r.otherSport { appState.goToHoopsPucks(other) }
        }
      }
      .disabled(joinCode.trimmingCharacters(in: .whitespaces).count < 6)
      .opacity(joinCode.trimmingCharacters(in: .whitespaces).count < 6 ? 0.5 : 1)
    }
  }

  // MARK: Week row

  private var weekRow: some View {
    HStack(alignment: .center, spacing: 8) {
      Button { vm.weekStart = HP.shiftWeek(vm.weekStart, by: -1) } label: { Image(systemName: "chevron.left") }
        .buttonStyle(.bordered).tint(BoldTheme.Colors.text)
        .accessibilityLabel("Previous week")
      VStack(alignment: .leading, spacing: 0) {
        Text("\(vm.weekStart == vm.currentWeek ? "This week" : vm.isPast ? "Past week" : "Upcoming") · Mon–Sun ET")
          .font(BoldTheme.Fonts.body(12, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
          .lineLimit(1).minimumScaleFactor(0.8)
        Text(weekLabel(vm.weekStart)).font(BoldTheme.Fonts.body(17, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
      }
      Button { vm.weekStart = HP.shiftWeek(vm.weekStart, by: 1) } label: { Image(systemName: "chevron.right") }
        .buttonStyle(.bordered).tint(BoldTheme.Colors.text)
        .accessibilityLabel("Next week")
      Spacer(minLength: 4)
      if vm.league != nil {
        VStack(alignment: .trailing, spacing: 3) {
          (Text("\(vm.used) of \(vm.picksPerWeek) used ") + Text("· \(HP.fmtPts(vm.myWeekPoints)) pts"))
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
          HStack(spacing: 3) {
            ForEach(0..<max(vm.picksPerWeek, 0), id: \.self) { i in
              RoundedRectangle(cornerRadius: 3)
                .fill(i < vm.used ? BoldTheme.Colors.text : BoldTheme.Colors.track)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
                .frame(width: 12, height: 6)
            }
          }
          .accessibilityHidden(true)
        }
      }
    }
  }

  private func weekLabel(_ ws: String) -> String {
    let b = HP.weekBoundsUtc(ws)
    let f = DateFormatter()
    f.timeZone = HP.eastern
    f.dateFormat = "MMM d"
    return "\(f.string(from: b.start)) – \(f.string(from: b.end.addingTimeInterval(-1)))"
  }

  // MARK: Slate

  @ViewBuilder private var slate: some View {
    if vm.loading {
      HStack { ProgressView(); Text("Loading games…").foregroundColor(BoldTheme.Colors.textDim) }
    } else if vm.days.isEmpty {
      BoldTheme.FlatCard {
        Text("No \(sport.noun) games synced for this week yet.")
          .font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      VStack(alignment: .leading, spacing: 18) {
        if watchEnabled && !isPro {
          HStack { Spacer(); WatchProTeaser() }
        }
        ForEach(vm.days, id: \.day) { day in
          VStack(alignment: .leading, spacing: 8) {
            Text("\(dayLabel(day.games[0].start_time)) · \(day.games.count) game\(day.games.count == 1 ? "" : "s")")
              .font(BoldTheme.Fonts.body(14, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.text)
            ForEach(day.games) { g in
              HpGameCard(
                game: g,
                pick: vm.weekPicks.first { $0.game_id == g.id },
                canPick: vm.canPickWeek || vm.league == nil,
                busy: vm.busyGame == g.id,
                now: vm.now,
                watchLinks: isPro && watchEnabled ? g.espn_event_id.flatMap { eid in vm.broadcasts[eid].map { WatchLinks.links(sport: sport.watchSport, eventId: eid, networks: $0) } } : nil,
                form: isPro ? vm.form : nil,
                onPick: { side in
                  Task {
                    guard let client else { return }
                    if await vm.pick(g, side: side, client: client, userId: userId) { pickedTick += 1 }
                  }
                },
                onUnpick: {
                  Task { if let client { await vm.unpick(g, client: client, userId: userId) } }
                }
              )
            }
          }
        }
        if vm.league == nil {
          Text("Start or join a group to start picking.")
            .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
        }
      }
    }
  }

  private func dayLabel(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeZone = HP.eastern
    f.dateFormat = "EEEE, MMM d"
    return f.string(from: d)
  }

  // MARK: Boards

  private func boardCard(_ rows: [HpBoardRow], season: Bool) -> some View {
    BoldTheme.FlatCard {
      if vm.league == nil {
        Text("Join a group to see its board.").foregroundColor(BoldTheme.Colors.textDim).frame(maxWidth: .infinity, alignment: .leading)
      } else if rows.isEmpty {
        Text("No one's on the board yet.").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim).frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          HStack(spacing: 6) {
            Text("#").frame(width: 24, alignment: .leading)
            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
            Text("Pts").frame(width: 48, alignment: .trailing)
            Text("Hit").frame(width: 30, alignment: .trailing)
            Text("Best").frame(width: 44, alignment: .trailing)
            if season { Text("Wks").frame(width: 32, alignment: .trailing) }
          }
          .font(BoldTheme.Fonts.body(12, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
          .padding(.vertical, 6)
          ForEach(rows) { r in
            Divider().overlay(BoldTheme.Colors.border)
            HStack(spacing: 6) {
              Text("\(r.rank)").font(BoldTheme.Fonts.mono(14, weight: .semibold))
                .foregroundColor(BoldTheme.Colors.text)
                .frame(width: 24, alignment: .leading)
              VStack(alignment: .leading, spacing: 1) {
                Text(r.display_name).font(BoldTheme.Fonts.body(14, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.85)
                Text("\(r.picks_used) picks\(r.pending > 0 ? " · \(r.pending) live/pending" : "")")
                  .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              Text(HP.fmtPts(r.points)).font(BoldTheme.Fonts.mono(13, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
                .frame(width: 48, alignment: .trailing)
              Text("\(r.correct)").font(BoldTheme.Fonts.mono(12)).frame(width: 30, alignment: .trailing)
              Text(r.best_hit > 0 ? "+\(HP.fmtPts(r.best_hit))" : "–").font(BoldTheme.Fonts.mono(11)).frame(width: 44, alignment: .trailing)
              if season { Text("\(r.weeks_won ?? 0)").font(BoldTheme.Fonts.mono(12)).frame(width: 32, alignment: .trailing) }
            }
            .foregroundColor(BoldTheme.Colors.text)
            .padding(.vertical, 8)
            .background(r.user_id == userId ? BoldTheme.Colors.track : .clear)
          }
          Text("Ties: most dogs hit, then biggest single hit.")
            .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
      }
    }
  }

  private var finePrint: some View {
    Text("Free to play: no entry fees, no buy-ins, and SUP never holds or pays out money. Lines come from a public odds feed and are used only for scoring. Postponed games void the pick and give the slot back. \(sport.overtime) Teams are listed by city. Not betting advice.")
      .font(BoldTheme.Fonts.body(12))
      .foregroundColor(BoldTheme.Colors.textDim)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 6)
  }

  // MARK: Small styled bits

  private func togglePanelButton(_ title: String, systemImage: String?, panel p: Panel) -> some View {
    let on = panel == p
    return Button {
      withAnimation(.easeInOut(duration: 0.2)) { panel = on ? nil : p }
    } label: {
      HStack(spacing: 5) {
        if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
        Text(title)
      }
      .font(BoldTheme.Fonts.body(14, weight: .bold))
      .foregroundColor(on ? BoldTheme.Colors.card : BoldTheme.Colors.text)
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(Capsule().fill(on ? BoldTheme.Colors.text : .clear))
      .overlay(Capsule().strokeBorder(BoldTheme.Colors.text, lineWidth: 1.5))
    }
    .buttonStyle(.plain)
  }

  private func primaryButton(_ title: String, full: Bool = false, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(SupPrimaryButtonStyle(fullWidth: full))
  }

  private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(SupSecondaryButtonStyle(fullWidth: false))
  }

  private func chip(_ text: String) -> some View {
    SupPill(text: text, kind: .gray)
  }
}

// MARK: - Game card

/// One Hoops / Pucks game: time + status chips, then away and home rows with
/// the team logo (initials badge fallback), city name, lines and a Pick
/// button on the dog. Hoops shows the spread big and the moneyline small;
/// Pucks shows the moneyline.
struct HpGameCard: View {
  let game: HpGame
  let pick: HpPick?
  let canPick: Bool
  let busy: Bool
  let now: Date
  /// Pro: where-to-watch links; nil hides them.
  let watchLinks: [WatchLink]?
  /// Pro: "Last 3" by ESPN team id; nil hides it.
  let form: [String: [FormGame]]?
  let onPick: (HpSide) -> Void
  let onUnpick: () -> Void

  private var nba: Bool { game.sport == .nba }
  private var dog: HpSide? { HP.dogSide(game) }
  private var locked: Bool { HP.isLocked(game, now: now) }
  private var hasLine: Bool { nba ? game.spread != nil : game.home_ml != nil }
  private var showScore: Bool { game.status == "in_progress" || game.status == "final" }
  private var grade: (result: HpPickResult, points: Double)? { pick.map { HP.gradePick($0, game) } }

  private var dogLine: String {
    if nba {
      return HP.fmtSpread(pick.map { HP.pickPoints(sport: .nba, lockedMl: $0.locked_ml, lockedSpread: $0.locked_spread) }
                          ?? HP.pickPoints(sport: .nba, lockedMl: nil, lockedSpread: game.spread))
    }
    return HP.fmtMl(pick?.locked_ml ?? dog.flatMap { game.ml($0) })
  }

  private var timeText: String {
    let f = DateFormatter()
    f.dateFormat = "h:mm a zzz"
    return f.string(from: game.start_time)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(timeText).font(BoldTheme.Fonts.body(13, weight: .medium)).foregroundColor(BoldTheme.Colors.textDim)
        Spacer(minLength: 4)
        statusChips
      }
      .padding(.bottom, 2)
      row(.away)
      row(.home)
      if let watchLinks, !watchLinks.isEmpty, game.status != "final" {
        HStack { Spacer(); WatchChips(links: watchLinks, live: game.status == "in_progress") }
          .padding(.top, 4)
      }
    }
    .padding(.horizontal, BoldTheme.Space.cardPad).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
    // Your pick: green outline (picked / locked), not gold.
    .overlay(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).strokeBorder(pick != nil ? BoldTheme.Colors.green : .clear, lineWidth: 2))
  }

  @ViewBuilder private var statusChips: some View {
    HStack(spacing: 4) {
      if game.status == "in_progress" { chip("● Live\(game.status_detail.map { " · \($0)" } ?? "")", tone: .red) }
      if game.status == "final" { chip(game.status_detail ?? "Final") }
      if game.status == "postponed" { chip("Postponed", tone: .red) }
      if locked && game.status != "final" && game.status != "postponed" { chip("Locked") }
      if !locked && dog != nil { chip("Dog \(dogLine)", tone: .dark) }
      if !locked && dog == nil && hasLine { chip("Pick'em · no dog") }
      if !locked && !hasLine { chip("No line yet") }
      if let grade {
        switch grade.result {
        case .win: chip("Won +\(HP.fmtPts(grade.points))", tone: .green)
        case .loss: chip("Lost")
        case .void: chip("Void · slot back")
        case .pending: EmptyView()
        }
      }
    }
  }

  private func row(_ side: HpSide) -> some View {
    let name = game.name(side)
    let ml = game.ml(side)
    let isDog = dog == side
    let isPicked = pick?.side == side
    let won = game.status == "final" && game.winner == side
    let teamForm = form.flatMap { f in game.espnTeamId(side).flatMap { f[$0] } }
    return HStack(spacing: 10) {
      HpTeamBadge(name: name, abbr: game.abbr(side), sport: game.sport, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(name).font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text).lineLimit(2).minimumScaleFactor(0.85)
          if side == .home { Text("home").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim) }
        }
        if let teamForm, !teamForm.isEmpty { FormStrip(games: teamForm) }
        if isDog && game.status != "final" && game.status != "postponed" {
          let pts = isPicked
            ? HP.pickPoints(sport: game.sport, lockedMl: pick?.locked_ml, lockedSpread: pick?.locked_spread)
            : HP.pickPoints(sport: game.sport, lockedMl: ml, lockedSpread: game.spread)
          Text("If they win: +\(HP.fmtPts(pts)) pts")
            .font(BoldTheme.Fonts.body(13, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
        }
      }
      Spacer(minLength: 4)
      if nba {
        // hp_picks.locked_spread is stored from the picked dog's side (+3.5 =
        // getting 3.5), not home-relative like daily_games.spread.
        Text(isPicked && pick?.locked_spread != nil ? HP.fmtSpread(pick?.locked_spread) : HP.sideLine(game.spread, side: side))
          .font(BoldTheme.Fonts.mono(14, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
          .frame(minWidth: 40, alignment: .trailing)
      }
      Text(isPicked && pick?.locked_ml != ml ? HP.fmtMl(pick?.locked_ml) : HP.fmtMl(ml))
        .font(BoldTheme.Fonts.mono(nba ? 10.5 : 13, weight: .bold))
        .foregroundColor(isDog && !nba ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
        .frame(minWidth: 38, alignment: .trailing)
      if showScore {
        Text(game.score(side).map(String.init) ?? "–")
          .font(BoldTheme.Fonts.display(24))
          .foregroundColor(won ? BoldTheme.Colors.green : BoldTheme.Colors.text)
          .frame(minWidth: 30, alignment: .trailing)
      }
      if isDog && !locked {
        if isPicked {
          Button(action: onUnpick) {
            HStack(spacing: 4) {
              if busy { ProgressView().controlSize(.mini).tint(.white) } else { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
              Text("Picked")
            }
            .font(BoldTheme.Fonts.body(13, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(BoldTheme.Colors.green))
          }
          .buttonStyle(.plain)
          .disabled(busy)
          .accessibilityLabel("Remove pick \(name)")
        } else {
          Button { onPick(side) } label: {
            HStack(spacing: 4) {
              if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
              Text("Pick")
            }
            .font(BoldTheme.Fonts.body(13, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(BoldTheme.Colors.text, lineWidth: 1.5))
            .opacity(canPick ? 1 : 0.45)
          }
          .buttonStyle(.plain)
          .disabled(busy || !canPick)
          .accessibilityLabel("Pick \(name)")
        }
      }
      if isPicked && locked { chip("✓ Your dog", tone: .green) }
    }
    .padding(.vertical, 5)
    .opacity(game.status == "final" && !won ? 0.6 : 1)
  }

  private enum Tone { case neutral, green, gold, red, dark }

  private func chip(_ text: String, tone: Tone = .neutral) -> some View {
    let (bg, fg): (Color, Color) = {
      switch tone {
      case .neutral: return (BoldTheme.Colors.track, BoldTheme.Colors.textDim)
      case .green: return (BoldTheme.Colors.green.opacity(0.12), BoldTheme.Colors.green)
      case .gold: return (BoldTheme.Colors.track, BoldTheme.Colors.text)
      case .red: return (BoldTheme.Role.lostTint, BoldTheme.Role.lost)
      case .dark: return (BoldTheme.Colors.track, BoldTheme.Colors.text)
      }
    }()
    return Text(text)
      .font(BoldTheme.Fonts.body(12, weight: .semibold))
      .lineLimit(1)
      .fixedSize()
      .foregroundColor(fg)
      .padding(.horizontal, 7).padding(.vertical, 3)
      .background(Capsule().fill(bg))
  }
}

/// Team logo from the website's self-hosted copies, falling back to an
/// initials badge when the file is missing or fails to load.
struct HpTeamBadge: View {
  let name: String
  let abbr: String?
  let sport: HpSport
  var size: CGFloat = 30

  var body: some View {
    RetryingAsyncImage(url: HP.logoURL(sport: sport, abbr: abbr)) { img in
      img.resizable().scaledToFit()
    } placeholder: {
      let text = HP.teamInitials(name: name, abbr: abbr)
      Circle()
        .fill(BoldTheme.Colors.track)
        .overlay(
          Text(text)
            .font(BoldTheme.Fonts.body(text.count > 3 ? size * 0.28 : size * 0.34, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
        )
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
