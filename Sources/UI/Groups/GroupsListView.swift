import SwiftUI
import Supabase

@MainActor
final class GroupsListViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published var myGroups: [MyGroup] = []
  @Published var discoverGroups: [DiscoverGroup] = []

  private var client: SupabaseClient?

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  func load() async {
    guard let client else { return }
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      let service = GroupsService(client: client)
      myGroups = try await service.fetchMyGroups()
      discoverGroups = try await service.fetchDiscoverGroups()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

struct GroupsListView: View {
  @Environment(\.supabaseClient) private var client
  @EnvironmentObject private var appState: AppState
  @StateObject private var viewModel = GroupsListViewModel()
  @State private var showCreate = false
  @State private var showJoin = false

  // CFB Underdog, Pro Ball Underdog, and Pickems are separate contests with
  // separate groups -- showing all of them in one flat list regardless of
  // which contest the user is currently in (the old behavior) fought the
  // "these are basically two different contests" framing everywhere else.
  // appState.currentGame is set by Home/Games' "Switch Game" sheet and
  // persists across tabs, so leaving for Pickems and coming back to Groups
  // shows Pickems groups until the user explicitly switches again.
  private func myGroupMatches(_ g: MyGroup) -> Bool {
    switch appState.currentGame {
    case .cfb: return g.game_type != .pickems && (g.sport == .cfb || g.sport == .both)
    case .nfl: return g.game_type != .pickems && (g.sport == .nfl || g.sport == .both)
    case .pickems: return g.game_type == .pickems || g.game_type == .both
    }
  }

  // DiscoverGroup has no game_type field (only MyGroup does), so NFL
  // Underdog and Pickems public groups can't be told apart here -- both
  // show together for either .nfl or .pickems. Acceptable for a "browse
  // public groups" list; My Groups above is exact.
  private func discoverGroupMatches(_ g: DiscoverGroup) -> Bool {
    switch appState.currentGame {
    case .cfb: return g.sport == .cfb || g.sport == .both
    case .nfl, .pickems: return g.sport == .nfl || g.sport == .both
    }
  }

  private var filteredMyGroups: [MyGroup] { viewModel.myGroups.filter(myGroupMatches) }
  // Groups you're already in belong under "yours", not Discover.
  private var filteredDiscoverGroups: [DiscoverGroup] {
    let mine = Set(viewModel.myGroups.map(\.group_id))
    return viewModel.discoverGroups.filter { discoverGroupMatches($0) && !mine.contains($0.id) }
  }

  private var contextDisplayName: String {
    switch appState.currentGame {
    case .cfb: return "CFB Underdog"
    case .nfl: return "Pro Ball Underdog"
    case .pickems: return "Pickems"
    }
  }

  // MARK: Layout -- mirrors My Picks: display header, shared switcher,
  // stat tiles, then grouped glass cards.

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: BoldTheme.Space.cardGap) {
            header
            GameSwitcher()
            // Everyone is already in the Global group: picks without a
            // group score on the global standings. Always listed first.
            GlobalGroupCard(game: appState.currentGame)

            if client == nil {
              Text("Client not available").foregroundColor(BoldTheme.Colors.textDim)
            } else if let e = viewModel.errorText {
              errorState(e)
            } else if viewModel.isLoading && viewModel.myGroups.isEmpty {
              ProgressView().tint(BoldTheme.Colors.text)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
              if let top = topGroup { heroCard(top) }
              if !filteredMyGroups.isEmpty { stats }
              if filteredMyGroups.isEmpty {
                sectionLabel("Your \(contextDisplayName) groups")
                emptyMyGroups
              } else if !otherGroups.isEmpty {
                // The top group already has the hero card above.
                sectionLabel(topGroup == nil ? "Your \(contextDisplayName) groups" : "Your other groups")
                cardList(otherGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    GroupRowView(group: group, pickems: isPickems)
                  }
                  .buttonStyle(.plain)
                }
              }

              if !filteredDiscoverGroups.isEmpty {
                sectionLabel("Public groups")
                cardList(filteredDiscoverGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    DiscoverRowView(group: group)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
          .padding(.horizontal, BoldTheme.Space.margin)
          .padding(.top, BoldTheme.Space.s2)
          .padding(.bottom, BoldTheme.Space.s6)
        }
        .refreshable { await viewModel.load() }
      }
      .navigationBarHidden(true)
      // No nav bar here: page-coloured strip behind the status bar so
      // content doesn't scroll up under the clock.
      .safeAreaInset(edge: .top, spacing: 0) {
        Color.clear.frame(height: 0)
          .background(BoldTheme.Colors.bgPage.opacity(0.94), ignoresSafeAreaEdges: .top)
      }
      .sheet(isPresented: $showCreate) {
        CreateGroupView(defaultGameType: appState.currentGame == .pickems ? .pickems : .underdog) {
          await viewModel.load()
        }
      }
      .sheet(isPresented: $showJoin) {
        JoinGroupView { await viewModel.load() }
      }
    }
    .task {
      if let client {
        viewModel.configure(client: client)
        await viewModel.load()
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: BoldTheme.Space.s2) {
      Text("Groups")
        .font(BoldTheme.Fonts.body(28, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)
      Spacer()
      Button("Join") { showJoin = true }
        .buttonStyle(SmallPill(primary: false))
      // The screen's one primary action.
      Button { showCreate = true } label: {
        Label("Create", systemImage: "plus")
      }
      .buttonStyle(SmallPill(primary: true))
    }
  }

  private var isPickems: Bool { appState.currentGame == .pickems }

  /// Your best-standing group (then most points) -- the hero, like My
  /// Picks' "this week" card.
  private var topGroup: MyGroup? {
    filteredMyGroups
      .filter { $0.rank != nil }
      .min { a, b in
        (a.rank ?? .max, -(a.my_points ?? 0)) < (b.rank ?? .max, -(b.my_points ?? 0))
      }
  }

  private var otherGroups: [MyGroup] {
    filteredMyGroups.filter { $0.group_id != topGroup?.group_id }
  }

  private func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
  }

  private func heroCard(_ g: MyGroup) -> some View {
    let rank = g.rank ?? 0
    let of = g.player_count ?? g.member_count
    let mine = g.my_points ?? 0
    let leader = max(g.leader_points ?? 0, mine)
    let unit = isPickems ? "correct" : "pts"
    return VStack(alignment: .leading, spacing: BoldTheme.Space.s3) {
      HStack {
        Text("Your top group")
          .font(BoldTheme.Fonts.body(13, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
        SupPill(text: rank == 1 ? "Leading" : "#\(rank) of \(of)", kind: rank == 1 ? .green : .gray)
      }

      HStack(spacing: BoldTheme.Space.s3) {
        AvatarInitials(name: g.name, size: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text(g.name)
            .font(BoldTheme.Fonts.body(20, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        Spacer(minLength: 0)
        Text(verbatim: "#\(rank)")
          .font(BoldTheme.Fonts.display(40))
          .foregroundColor(BoldTheme.Colors.text)
      }

      VStack(alignment: .leading, spacing: 6) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(BoldTheme.Colors.track)
            Capsule().fill(BoldTheme.Colors.text)
              .frame(width: leader > 0 ? geo.size.width * CGFloat(mine / leader) : 0)
          }
        }
        .frame(height: 6)
        HStack {
          Text(verbatim: "You: \(fmt(mine)) \(unit)")
            .foregroundColor(BoldTheme.Colors.text)
          Spacer()
          Text(verbatim: rank == 1 ? "Top of the table" : "\(fmt(leader - mine)) behind the leader")
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        .font(BoldTheme.Fonts.body(13, weight: .semibold))
      }

      NavigationLink(destination: GroupDetailView(slug: g.slug)) {
        Text("View leaderboard")
      }
      .buttonStyle(SupSecondaryButtonStyle())
    }
    .padding(BoldTheme.Space.cardPad)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private var stats: some View {
    let ranks = filteredMyGroups.compactMap(\.rank)
    let best = ranks.min().map { "#\($0)" } ?? "–"
    let leading = ranks.filter { $0 == 1 }.count
    return HStack(alignment: .top, spacing: BoldTheme.Space.s2) {
      statTile("\(filteredMyGroups.count)", "groups")
      statTile(best, "best rank")
      statTile("\(leading)", "leading")
    }
    .padding(BoldTheme.Space.cardPad)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private var emptyMyGroups: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.3.fill").font(.system(size: 30)).foregroundColor(BoldTheme.Colors.textFaint)
      Text("Play against friends")
        .font(BoldTheme.Fonts.body(16, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)
      Text(viewModel.myGroups.isEmpty
           ? "You're on the global board already. Create a group for your friends, office, or fantasy chat for a private board too."
           : "You're on the \(contextDisplayName) global board already. Want a private board too? Create a group or join with an invite code.")
        .font(BoldTheme.Fonts.body(13))
        .foregroundColor(BoldTheme.Colors.textDim)
        .multilineTextAlignment(.center)
      VStack(spacing: BoldTheme.Space.s2) {
        Button("Create a group") { showCreate = true }
          .buttonStyle(SupPrimaryButtonStyle())
        Button("Join with a code") { showJoin = true }
          .buttonStyle(SupSecondaryButtonStyle())
      }
      .padding(.top, BoldTheme.Space.s1)
    }
    .padding(BoldTheme.Space.cardPad)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private func cardList<T: Identifiable, Row: View>(_ items: [T], @ViewBuilder row: @escaping (T) -> Row) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
        row(item)
        if i < items.count - 1 {
          Rectangle().fill(BoldTheme.Colors.border).frame(height: 1)
        }
      }
    }
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private func statTile(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: value)
        .font(BoldTheme.Fonts.display(30))
        .foregroundColor(BoldTheme.Colors.text)
        .lineLimit(1)
      Text(verbatim: label)
        .font(BoldTheme.Fonts.body(13))
        .foregroundColor(BoldTheme.Colors.textDim)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(BoldTheme.Fonts.body(16, weight: .bold))
      .foregroundColor(BoldTheme.Colors.text)
      .padding(.top, BoldTheme.Space.s3)
      .padding(.bottom, -4)
  }

  private func errorState(_ message: String) -> some View {
    VStack(spacing: 8) {
      Text("Couldn't load groups").font(BoldTheme.Fonts.body(20, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
      Text(message).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
      Button("Try again") { Task { await viewModel.load() } }
        .buttonStyle(SupSecondaryButtonStyle(fullWidth: false))
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 40)
  }
}

// One row in the "your groups" card: who, how big, and where you stand.
private struct GroupRowView: View {
  let group: MyGroup
  var pickems: Bool = false

  private var roleLabel: String? {
    switch group.my_role {
    case .owner: return "Owner"
    case .admin: return "Admin"
    case .pending: return "Pending"
    case .member: return nil
    }
  }

  private var subline: String {
    var parts = ["\(group.member_count) member\(group.member_count == 1 ? "" : "s")"]
    if let roleLabel { parts.append(roleLabel) }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    HStack(spacing: 12) {
      AvatarInitials(name: group.name, size: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text(group.name)
          .font(BoldTheme.Fonts.body(15, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(subline)
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
      }
      Spacer(minLength: 6)
      if let rank = group.rank {
        VStack(alignment: .trailing, spacing: 0) {
          Text(verbatim: "#\(rank)")
            .font(BoldTheme.Fonts.display(24))
            .foregroundColor(BoldTheme.Colors.text)
          Text(verbatim: "of \(group.player_count ?? group.member_count)")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)
    }
    .padding(.horizontal, BoldTheme.Space.cardPad)
    .padding(.vertical, BoldTheme.Space.s3)
    .contentShape(Rectangle())
  }
}

private struct DiscoverRowView: View {
  let group: DiscoverGroup

  var body: some View {
    HStack(spacing: 12) {
      AvatarInitials(name: group.name, size: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text(group.name)
          .font(BoldTheme.Fonts.body(15, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: "\(group.member_count) member\(group.member_count == 1 ? "" : "s") · public")
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
      }
      Spacer(minLength: 6)
      SupPill(text: "View", kind: .outline)
    }
    .padding(.horizontal, BoldTheme.Space.cardPad)
    .padding(.vertical, BoldTheme.Space.s3)
    .contentShape(Rectangle())
  }
}
