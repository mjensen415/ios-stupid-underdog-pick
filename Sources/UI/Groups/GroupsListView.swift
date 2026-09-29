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
        BoldTheme.AmbientBlobs().ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            header
            GameSwitcher()

            if client == nil {
              Text("Client not available").foregroundColor(BoldTheme.Colors.textDim)
            } else if let e = viewModel.errorText {
              errorState(e)
            } else if viewModel.isLoading && viewModel.myGroups.isEmpty {
              ProgressView().tint(BoldTheme.Colors.goldDeep)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
              if let top = topGroup { heroCard(top) }
              if !filteredMyGroups.isEmpty { stats }
              if filteredMyGroups.isEmpty {
                sectionLabel("YOUR \(contextDisplayName.uppercased()) GROUPS")
                emptyMyGroups
              } else if !otherGroups.isEmpty {
                // The top group already has the hero card above.
                sectionLabel(topGroup == nil ? "YOUR \(contextDisplayName.uppercased()) GROUPS" : "YOUR OTHER GROUPS")
                cardList(otherGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    GroupRowView(group: group, pickems: isPickems)
                  }
                  .buttonStyle(.plain)
                }
              }

              if !filteredDiscoverGroups.isEmpty {
                sectionLabel("DISCOVER")
                cardList(filteredDiscoverGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    DiscoverRowView(group: group)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
          .padding(.horizontal, 18)
          .padding(.top, 8)
          .padding(.bottom, 32)
        }
        .refreshable { await viewModel.load() }
      }
      .navigationBarHidden(true)
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
    HStack(alignment: .center) {
      Text("GROUPS")
        .font(BoldTheme.Fonts.display(26))
        .tracking(0.6)
        .foregroundColor(BoldTheme.Colors.text)
      Spacer()
      Button { showJoin = true } label: {
        Text("Join")
          .font(BoldTheme.Fonts.body(13, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
          .padding(.horizontal, 14).padding(.vertical, 7)
          .background(BoldTheme.Colors.glassStrong)
          .overlay(Capsule().strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
          .clipShape(Capsule())
      }
      Button { showCreate = true } label: {
        HStack(spacing: 4) {
          Image(systemName: "plus").font(.system(size: 11, weight: .bold))
          Text("Create")
        }
        .font(BoldTheme.Fonts.body(13, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.text)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(isPickems ? BoldTheme.Colors.pickemsAccent.opacity(0.22) : BoldTheme.Colors.gold)
        .clipShape(Capsule())
      }
    }
  }

  private var isPickems: Bool { appState.currentGame == .pickems }
  /// Highlight color: gold for Underdog, the Pickems accent on Pickems --
  /// same split My Picks uses for its stat tiles.
  private var accent: Color { isPickems ? BoldTheme.Colors.pickemsAccent : BoldTheme.Colors.goldDeep }

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
    let (chipText, chipFg, chipBg): (String, Color, Color) = rank == 1
      ? ("Leading", BoldTheme.Colors.text, isPickems ? BoldTheme.Colors.pickemsAccent.opacity(0.22) : BoldTheme.Colors.gold)
      : ("#\(rank) of \(of)", BoldTheme.Colors.green, BoldTheme.Colors.green.opacity(0.13))
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("YOUR TOP GROUP")
          .font(BoldTheme.Fonts.mono(11, weight: .semibold))
          .tracking(0.8)
          .foregroundColor(BoldTheme.Colors.textDim)
        Spacer()
        Text(chipText)
          .font(BoldTheme.Fonts.body(12, weight: .bold))
          .foregroundColor(chipFg)
          .padding(.horizontal, 10).padding(.vertical, 4)
          .background(chipBg)
          .clipShape(Capsule())
      }

      HStack(spacing: 14) {
        AvatarInitials(name: g.name, size: 52)
        VStack(alignment: .leading, spacing: 3) {
          Text(g.name)
            .font(BoldTheme.Fonts.body(20, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          Text(verbatim: "\(g.member_count) member\(g.member_count == 1 ? "" : "s")")
            .font(BoldTheme.Fonts.body(13))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        Spacer(minLength: 0)
      }

      VStack(alignment: .leading, spacing: 6) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(BoldTheme.Colors.track)
            Capsule().fill(isPickems ? BoldTheme.Colors.pickemsAccent : BoldTheme.Colors.gold)
              .frame(width: leader > 0 ? geo.size.width * CGFloat(mine / leader) : 0)
          }
        }
        .frame(height: 6)
        HStack {
          Text(verbatim: "You \(fmt(mine)) \(unit)")
            .foregroundColor(BoldTheme.Colors.text)
          Spacer()
          Text(verbatim: rank == 1 ? "Top of the table" : "\(fmt(leader - mine)) back of the leader")
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        .font(BoldTheme.Fonts.mono(11, weight: .semibold))
      }

      NavigationLink(destination: GroupDetailView(slug: g.slug)) {
        Text("View leaderboard →")
          .font(BoldTheme.Fonts.body(14, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(isPickems ? BoldTheme.Colors.pickemsAccent.opacity(0.22) : BoldTheme.Colors.gold)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
    .padding(18)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
  }

  private var stats: some View {
    let ranks = filteredMyGroups.compactMap(\.rank)
    let best = ranks.min().map { "#\($0)" } ?? "–"
    let leading = ranks.filter { $0 == 1 }.count
    return HStack(spacing: 10) {
      statTile("GROUPS", "\(filteredMyGroups.count)")
      statTile("BEST RANK", best, highlight: ranks.min() == 1)
      statTile("LEADING", "\(leading)", highlight: leading > 0)
    }
  }

  private var emptyMyGroups: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.3.fill").font(.system(size: 30)).foregroundColor(BoldTheme.Colors.textFaint)
      Text("Play against friends")
        .font(BoldTheme.Fonts.body(16, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)
      Text("Create a \(contextDisplayName) group or join one with an invite code.")
        .font(BoldTheme.Fonts.body(13))
        .foregroundColor(BoldTheme.Colors.textDim)
        .multilineTextAlignment(.center)
      HStack(spacing: 10) {
        Button { showCreate = true } label: {
          Text("Create a group")
            .font(BoldTheme.Fonts.body(14, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(isPickems ? BoldTheme.Colors.pickemsAccent.opacity(0.22) : BoldTheme.Colors.gold)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        Button { showJoin = true } label: {
          Text("Join with code")
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.text)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
        }
      }
      .padding(.top, 4)
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
  }

  private func cardList<T: Identifiable, Row: View>(_ items: [T], @ViewBuilder row: @escaping (T) -> Row) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
        row(item)
        if i < items.count - 1 {
          Rectangle().fill(BoldTheme.Colors.border).frame(height: 1).padding(.leading, 66)
        }
      }
    }
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
  }

  private func statTile(_ label: String, _ value: String, highlight: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(BoldTheme.Fonts.mono(10, weight: .semibold))
        .tracking(0.8)
        .foregroundColor(BoldTheme.Colors.textFaint)
      Text(value)
        .font(BoldTheme.Fonts.display(24))
        .foregroundColor(highlight ? accent : BoldTheme.Colors.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(BoldTheme.Fonts.mono(11, weight: .semibold))
      .tracking(0.9)
      .foregroundColor(BoldTheme.Colors.textFaint)
      .padding(.top, 4)
      .padding(.bottom, -8)
  }

  private func errorState(_ message: String) -> some View {
    VStack(spacing: 8) {
      Text("Couldn't load groups").font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.text)
      Text(message).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
      Button("Retry") { Task { await viewModel.load() } }
        .font(BoldTheme.Fonts.body(14, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.goldDeep)
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
          .lineLimit(1)
        Text(subline)
          .font(BoldTheme.Fonts.body(12))
          .foregroundColor(BoldTheme.Colors.textDim)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      if let rank = group.rank {
        // Same badge language as My Picks' history rows: gold capsule for
        // the win (leading), track capsule otherwise.
        VStack(alignment: .trailing, spacing: 3) {
          Text(verbatim: rank == 1 ? "1ST" : "#\(rank)")
            .font(BoldTheme.Fonts.mono(12, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(rank == 1 ? BoldTheme.Colors.text : BoldTheme.Colors.textDim)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(rank == 1 ? (pickems ? BoldTheme.Colors.pickemsAccent.opacity(0.22) : BoldTheme.Colors.gold) : BoldTheme.Colors.track)
            .clipShape(Capsule())
          Text(verbatim: "of \(group.player_count ?? group.member_count)")
            .font(BoldTheme.Fonts.mono(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textFaint)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
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
          .lineLimit(1)
        Text(verbatim: "\(group.member_count) member\(group.member_count == 1 ? "" : "s") · Public")
          .font(BoldTheme.Fonts.body(12))
          .foregroundColor(BoldTheme.Colors.textDim)
      }
      Spacer(minLength: 6)
      Text("View")
        .font(BoldTheme.Fonts.body(12, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.green)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .overlay(Capsule().strokeBorder(BoldTheme.Colors.green.opacity(0.5), lineWidth: 1))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}
