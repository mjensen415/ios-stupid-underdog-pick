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
  @StateObject private var viewModel = GroupsListViewModel()
  @State private var showCreate = false
  @State private var showJoin = false

  var body: some View {
    NavigationStack {
      Group {
        if client == nil {
          Text("Client not available").foregroundColor(BoldTheme.Colors.textDim)
        } else if let e = viewModel.errorText {
          VStack(spacing: 8) {
            Text("Error loading groups").font(BoldTheme.Fonts.display(24)).foregroundColor(BoldTheme.Colors.text)
            Text(e).foregroundColor(BoldTheme.Colors.textDim).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load() } }
              .foregroundColor(BoldTheme.Colors.goldDeep)
          }.padding()
        } else if viewModel.isLoading && viewModel.myGroups.isEmpty {
          ProgressView("Loading groups…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
        } else {
          List {
            Section {
              if viewModel.myGroups.isEmpty {
                VStack(spacing: 10) {
                  Image(systemName: "person.3").font(.system(size: 32)).foregroundColor(BoldTheme.Colors.textFaint)
                  Text("Play against friends").font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
                  Text("Create a group or join one with an invite code.")
                    .font(BoldTheme.Fonts.body(13))
                    .foregroundColor(BoldTheme.Colors.textDim)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(BoldTheme.Colors.bgPage)
              } else {
                ForEach(viewModel.myGroups) { group in
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
              Text("My Groups").foregroundColor(BoldTheme.Colors.textDim)
            }

            if !viewModel.discoverGroups.isEmpty {
              Section {
                ForEach(viewModel.discoverGroups) { group in
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
        CreateGroupView { await viewModel.load() }
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
