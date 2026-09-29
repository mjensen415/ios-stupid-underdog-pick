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
              if !filteredMyGroups.isEmpty { stats }
              sectionLabel("YOUR \(contextDisplayName.uppercased()) GROUPS")
              if filteredMyGroups.isEmpty {
                emptyMyGroups
              } else {
                cardList(filteredMyGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    GroupRowView(group: group)
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
        .background(BoldTheme.Colors.gold)
        .clipShape(Capsule())
      }
    }
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
            .background(BoldTheme.Colors.gold)
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
        .foregroundColor(highlight ? BoldTheme.Colors.goldDeep : BoldTheme.Colors.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BoldTheme.Colors.glassBorder, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 16))
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
        VStack(alignment: .trailing, spacing: 1) {
          Text(verbatim: "#\(rank)")
            .font(BoldTheme.Fonts.mono(17, weight: .semibold))
            .foregroundColor(rank == 1 ? BoldTheme.Colors.goldDeep : BoldTheme.Colors.text)
          if let of = group.player_count ?? Optional(group.member_count), of > 0 {
            Text(verbatim: "of \(of)")
              .font(BoldTheme.Fonts.mono(10))
              .foregroundColor(BoldTheme.Colors.textFaint)
          }
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
