import SwiftUI
import Supabase

struct DiscoverGroup: Decodable, Identifiable {
  let id: UUID
  let name: String
  let slug: String
  let avatar_url: String?
  let is_private: Bool
}

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
      myGroups = try await GroupsService(client: client).fetchMyGroups()
      let res = try await client
        .from("groups")
        .select("id, name, slug, avatar_url, is_private")
        .eq("is_private", value: false)
        .order("created_at", ascending: false)
        .limit(20)
        .execute()
      discoverGroups = try JSONDecoder().decode([DiscoverGroup].self, from: res.data)
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
              .foregroundColor(BoldTheme.Colors.gold)
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
                    GroupRowView(name: group.name, memberCount: group.member_count, isPrivate: group.is_private, role: group.my_role)
                  }
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
                      Text(group.name).font(BoldTheme.Fonts.body(15)).foregroundColor(BoldTheme.Colors.text)
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

private struct GroupRowView: View {
  let name: String
  let memberCount: Int
  let isPrivate: Bool
  let role: GroupRole

  var body: some View {
    HStack(spacing: 12) {
      AvatarInitials(name: name, size: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text(name).font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
        Text(verbatim: "\(memberCount) member\(memberCount == 1 ? "" : "s")")
          .font(BoldTheme.Fonts.body(12))
          .foregroundColor(BoldTheme.Colors.textDim)
      }
      Spacer()
      RoleBadge(role: role)
    }
    .padding(.vertical, 4)
  }
}
