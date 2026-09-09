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
  private var filteredDiscoverGroups: [DiscoverGroup] { viewModel.discoverGroups.filter(discoverGroupMatches) }

  private var contextDisplayName: String {
    switch appState.currentGame {
    case .cfb: return "CFB Underdog"
    case .nfl: return "Pro Ball Underdog"
    case .pickems: return "Pickems"
    }
  }

  private var contextSwitcher: some View {
    HStack(spacing: 4) {
      ForEach([CurrentGame.cfb, .nfl, .pickems], id: \.self) { game in
        let active = game == appState.currentGame
        let label = game == .cfb ? "CFB" : (game == .nfl ? "PRO BALL" : "PICKEMS")
        let accent = game == .pickems ? BoldTheme.Colors.pickemsAccentDeep : BoldTheme.Colors.goldDeep
        Button {
          appState.currentGame = game
        } label: {
          Text(label)
            .font(BoldTheme.Fonts.body(12, weight: .bold))
            .foregroundColor(active ? accent : BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(active ? Color.white : Color.clear)
            .cornerRadius(9)
            .shadow(color: active ? Color.black.opacity(0.1) : .clear, radius: 4, y: 2)
        }
      }
    }
    .padding(3)
    .background(Color.black.opacity(0.05))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .cornerRadius(12)
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        contextSwitcher

      Group {
        if client == nil {
          Text("Client not available").foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let e = viewModel.errorText {
          VStack(spacing: 8) {
            Text("Error loading groups").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
            Text(e).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load() } }
              .foregroundColor(BoldTheme.Colors.goldDeep)
          }.padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isLoading && viewModel.myGroups.isEmpty {
          ProgressView("Loading groups…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List {
            Section {
              if filteredMyGroups.isEmpty {
                VStack(spacing: 10) {
                  Image(systemName: "person.3").font(.system(size: 32)).foregroundColor(BoldTheme.Colors.textFaint)
                  Text("Play against friends").font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
                  Text("Create a \(contextDisplayName) group or join one with an invite code.")
                    .font(BoldTheme.Fonts.body(13))
                    .foregroundColor(BoldTheme.Colors.textDim)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(BoldTheme.Colors.bgPage)
              } else {
                ForEach(filteredMyGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    GroupRowView(group: group)
                  }
                  .buttonStyle(.plain)
                  .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                  .listRowSeparator(.hidden)
                  .listRowBackground(BoldTheme.Colors.bgPage)
                }
              }
            } header: {
              Text("My \(contextDisplayName) Groups").foregroundColor(BoldTheme.Colors.textDim)
            }

            if !filteredDiscoverGroups.isEmpty {
              Section {
                ForEach(filteredDiscoverGroups) { group in
                  NavigationLink(destination: GroupDetailView(slug: group.slug)) {
                    HStack(spacing: 12) {
                      AvatarInitials(name: group.name, size: 36)
                      VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(BoldTheme.Fonts.body(15)).foregroundColor(BoldTheme.Colors.text)
                        Text(verbatim: "\(group.member_count) member\(group.member_count == 1 ? "" : "s")")
                          .font(BoldTheme.Fonts.body(12))
                          .foregroundColor(BoldTheme.Colors.textDim)
                      }
                    }
                  }
                  .listRowBackground(BoldTheme.Colors.bgPage)
                }
              } header: {
                Text("Discover").foregroundColor(BoldTheme.Colors.textDim)
              }
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .background(BoldTheme.Colors.bgPage)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
      .navigationTitle("Groups")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Menu {
            Button("Create Group") { showCreate = true }
            Button("Join Group") { showJoin = true }
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(isPresented: $showCreate) {
        CreateGroupView(defaultGameType: appState.currentGame == .pickems ? .pickems : .underdog) {
          await viewModel.load()
        }
      }
      .sheet(isPresented: $showJoin) {
        JoinGroupView { await viewModel.load() }
      }
      .task {
        if let client {
          viewModel.configure(client: client)
          await viewModel.load()
        }
      }
      .refreshable { await viewModel.load() }
      }
    }
  }
}

// Cards, not plain rows -- reads as tappable at a glance, and the
// standings line surfaces "how am I doing" without opening the group.
private struct GroupRowView: View {
  let group: MyGroup

  private var sportLabel: String {
    switch group.sport {
    case .cfb: return "CFB"
    case .nfl: return "PRO BALL"
    case .both: return "CFB + PRO"
    }
  }

  var body: some View {
    BoldTheme.GlassCard(radius: 14, padding: 16) {
      HStack(spacing: 12) {
        AvatarInitials(name: group.name, size: 40)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(group.name).font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
            Text(sportLabel)
              .font(BoldTheme.Fonts.mono(9, weight: .semibold))
              .tracking(0.4)
              .foregroundColor(BoldTheme.Colors.textFaint)
              .padding(.horizontal, 6).padding(.vertical, 2)
              .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
          }
          Text(verbatim: "\(group.member_count) member\(group.member_count == 1 ? "" : "s")")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
          if let line = group.standingsLine {
            Text(line)
              .font(BoldTheme.Fonts.body(12, weight: .semibold))
              .foregroundColor(BoldTheme.Colors.goldDeep)
          }
        }
        Spacer()
        RoleBadge(role: group.my_role)
      }
    }
  }
}
