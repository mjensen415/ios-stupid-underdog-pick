import SwiftUI
import Supabase

fileprivate struct GroupRow: Decodable {
  let id: UUID
  let name: String
  let slug: String
  let avatar_url: String?
  let is_private: Bool
  let description: String?
  let sport: GroupSport
  let game_type: GroupGameType
}

fileprivate enum DetailTab: Hashable { case leaderboard, pickems, members, settings }
fileprivate enum LeaderboardScope: Hashable { case week, season }

@MainActor
final class GroupDetailViewModel: ObservableObject {
  @Published var isLoading = false
  @Published var errorText: String?
  @Published fileprivate var group: GroupRow?
  @Published var myRole: GroupRole?
  @Published var memberCount = 0
  @Published var members: [GroupMember] = []
  @Published var leaderboard: [GroupLeaderboardEntry] = []
  @Published var invites: [GroupInvite] = []
  @Published var season = 2025
  @Published var week = 1
  @Published var availableWeeks: [Int] = []
  @Published var toastMessage: String?
  // NFL season/week + this week's last game, only fetched for groups that
  // actually play Pickems -- feeds the embedded PickemsStandingsView's
  // tiebreaker line.
  @Published var pickemsSeason: Int?
  @Published var pickemsWeek: Int?
  @Published var pickemsLastGame: PickemsGameRow?
  @Published var pickemsAvailableWeeks: [Int] = []
  // Only meaningful (and only shown) when group.sport == .both -- a
  // single-sport group's board always uses its own sport regardless of
  // this value, see effectiveLeaderboardSport.
  @Published var leaderboardSport: GroupSport = .cfb

  fileprivate var effectiveLeaderboardSport: GroupSport {
    guard let group, group.sport != .both else { return leaderboardSport }
    return group.sport
  }

  private var client: SupabaseClient?
  let slug: String

  init(slug: String) { self.slug = slug }

  func configure(client: SupabaseClient) {
    if self.client == nil { self.client = client }
  }

  var isAdmin: Bool { myRole == .owner || myRole == .admin }
  var isOwner: Bool { myRole == .owner }

  func loadInitial() async {
    guard let client else { return }
    isLoading = true; errorText = nil
    defer { isLoading = false }
    do {
      if let ctx = try? await ContextService(client: client).getCurrentContext() {
        season = ctx.season
        week = ctx.week
      }

      // Mirror web's GroupDetail.tsx: try to find in my memberships first
      // (gives role); fall back to a direct public-group lookup otherwise.
      let mine = try await GroupsService(client: client).fetchMyGroups()
      if let match = mine.first(where: { $0.slug == slug }) {
        group = GroupRow(id: match.group_id, name: match.name, slug: match.slug, avatar_url: match.avatar_url, is_private: match.is_private, description: match.description, sport: match.sport, game_type: match.game_type)
        myRole = match.my_role
        memberCount = match.member_count
      } else {
        let res = try await client.from("groups").select("id, name, slug, avatar_url, is_private, description, sport, game_type").eq("slug", value: slug).single().execute()
        let row = try JSONDecoder().decode(GroupRow.self, from: res.data)
        if row.is_private {
          group = nil
        } else {
          group = row
          myRole = nil
          let countRes = try await client.from("group_members").select("user_id", head: false, count: .exact).eq("group_id", value: row.id).neq("role", value: "pending").execute()
          memberCount = countRes.count ?? 0
        }
      }

      if let group {
        await loadMembers()
        if group.game_type != .pickems {
          await loadAvailableWeeks()
          await loadLeaderboard(scope: .week)
        }
        if group.game_type != .underdog { await loadPickemsContext() }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  func loadMembers() async {
    guard let client, let group else { return }
    do {
      let result = try await GroupsService(client: client).fetchGroupMembers(slug: group.slug)
      members = result.members
    } catch {
      errorText = error.localizedDescription
    }
  }

  func loadPickemsContext() async {
    guard let client else { return }
    do {
      let ctx = try await ContextService(client: client).getCurrentContext(sport: "nfl")
      pickemsSeason = ctx.season
      pickemsWeek = ctx.week
      pickemsAvailableWeeks = try await PickemsService(client: client).fetchDistinctWeeks(season: ctx.season, sport: "nfl")
      await reloadPickemsLastGame()
    } catch {
      // Tiebreaker line just won't show -- non-fatal, standings still load.
    }
  }

  // Re-fetches just the tiebreaker's "last game" for the currently
  // selected pickemsWeek, without re-resolving season/week from context --
  // called when the week-pill row changes pickemsWeek directly.
  func reloadPickemsLastGame() async {
    guard let client, let pickemsSeason, let pickemsWeek else { return }
    do {
      let games = try await PickemsService(client: client).fetchGames(season: pickemsSeason, week: pickemsWeek)
      pickemsLastGame = games.max(by: { $0.startTime < $1.startTime })
    } catch {
      pickemsLastGame = nil
    }
  }

  // Same week-pill row as PickemsView -- lets a group's leaderboard week
  // picker match it visually instead of the generic +/- Stepper.
  func loadAvailableWeeks() async {
    guard let client else { return }
    do {
      availableWeeks = try await PickemsService(client: client).fetchDistinctWeeks(
        season: season, sport: effectiveLeaderboardSport == .nfl ? "nfl" : "cfb"
      )
    } catch {
      availableWeeks = []
    }
  }

  fileprivate func loadLeaderboard(scope: LeaderboardScope) async {
    guard let client, let group else { return }
    do {
      let result = try await GroupsService(client: client).fetchGroupLeaderboard(
        slug: group.slug, scope: scope == .week ? "week" : "season", season: season, week: scope == .week ? week : nil,
        sport: effectiveLeaderboardSport == .nfl ? "nfl" : "cfb"
      )
      leaderboard = result.leaderboard
    } catch {
      errorText = error.localizedDescription
    }
  }

  func loadInvites() async {
    guard let client, let group else { return }
    do {
      let result = try await GroupsService(client: client).fetchGroupInvites(groupId: group.id)
      invites = result.invites
    } catch {
      errorText = error.localizedDescription
    }
  }

  func join() async {
    guard let client, let group else { return }
    do {
      let result = try await GroupsService(client: client).joinGroup(groupId: group.id)
      toastMessage = result.message
      await loadInitial()
    } catch {
      errorText = error.localizedDescription
    }
  }

  func approve(userId: UUID) async {
    guard let client, let group else { return }
    do {
      _ = try await GroupsService(client: client).approveMember(groupId: group.id, userId: userId)
      await loadMembers()
    } catch { errorText = error.localizedDescription }
  }

  func kick(userId: UUID) async {
    guard let client, let group else { return }
    do {
      _ = try await GroupsService(client: client).kickMember(groupId: group.id, userId: userId)
      await loadMembers()
    } catch { errorText = error.localizedDescription }
  }

  func promote(userId: UUID) async {
    guard let client, let group else { return }
    do {
      _ = try await GroupsService(client: client).promoteToAdmin(groupId: group.id, userId: userId)
      await loadMembers()
    } catch { errorText = error.localizedDescription }
  }

  fileprivate func updateGroup(name: String, description: String?, isPrivate: Bool) async -> Bool {
    guard let client, let group else { return false }
    do {
      let result = try await GroupsService(client: client).updateGroup(groupId: group.id, name: name, description: description, avatarUrl: nil, isPrivate: isPrivate)
      self.group = GroupRow(id: group.id, name: name, slug: result.slug, avatar_url: group.avatar_url, is_private: isPrivate, description: description, sport: group.sport, game_type: group.game_type)
      return true
    } catch {
      errorText = error.localizedDescription
      return false
    }
  }
}

struct GroupDetailView: View {
  @Environment(\.supabaseClient) private var client
  @StateObject private var viewModel: GroupDetailViewModel
  @State private var tab: DetailTab = .leaderboard
  @State private var leaderboardScope: LeaderboardScope = .week
  @State private var showLeaveConfirm = false
  @State private var showDeleteConfirm = false
  @Environment(\.dismiss) private var dismiss

  init(slug: String) {
    _viewModel = StateObject(wrappedValue: GroupDetailViewModel(slug: slug))
  }

  // A pickems-only group has no underdog picks to show, so that tab is
  // hidden rather than left showing a permanently-empty leaderboard; a
  // both-mode group gets both. Mirrors web's GroupDetail.tsx.
  private var tabOptions: [(label: String, value: DetailTab)] {
    var opts: [(label: String, value: DetailTab)] = []
    if viewModel.group?.game_type != .pickems { opts.append(("Leaderboard", .leaderboard)) }
    if viewModel.group?.game_type == .pickems || viewModel.group?.game_type == .both { opts.append(("Pickems", .pickems)) }
    opts.append(("Members", .members))
    if viewModel.isAdmin { opts.append(("Settings", .settings)) }
    return opts
  }

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()

      Group {
        if let e = viewModel.errorText, viewModel.group == nil {
          VStack(spacing: 8) {
            Text("Couldn't load this group").font(BoldTheme.Fonts.body(20, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
            Text(e).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
            Button("Try again") { Task { await viewModel.loadInitial() } }
              .buttonStyle(SupSecondaryButtonStyle(fullWidth: false))
          }.padding()
        } else if viewModel.isLoading && viewModel.group == nil {
          ProgressView("Loading…").tint(BoldTheme.Colors.text)
        } else if viewModel.group == nil {
          VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundColor(BoldTheme.Colors.textFaint)
            Text("This group is private.").font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
            Text("Request to join to view it.").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
          }.padding()
        } else {
          content
        }
      }
    }
    .navigationTitle(viewModel.group?.name ?? "Group")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if let client {
        viewModel.configure(client: client)
        await viewModel.loadInitial()
      }
    }
    .onChange(of: viewModel.group?.game_type) { _, newValue in
      if newValue == .pickems && tab == .leaderboard { tab = .pickems }
    }
  }

  @ViewBuilder
  private var content: some View {
    let group = viewModel.group!
    ScrollView {
      VStack(alignment: .leading, spacing: BoldTheme.Space.s4) {
        HStack(spacing: BoldTheme.Space.s3) {
          AvatarInitials(name: group.name, size: 52)
          VStack(alignment: .leading, spacing: 6) {
            Text(group.name).font(BoldTheme.Fonts.body(22, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
              .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
              if let role = viewModel.myRole { RoleBadge(role: role) }
              PrivacyChip(isPrivate: group.is_private)
              Text(verbatim: "\(viewModel.memberCount) member\(viewModel.memberCount == 1 ? "" : "s")")
                .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
            }
          }
          Spacer()
        }
        if let description = group.description, !description.isEmpty {
          Text(description).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim)
        }

        if viewModel.myRole == .pending {
          bannerCard(icon: "clock.fill", title: "Waiting for approval", subtitle: "An admin needs to approve your request.")
        } else if viewModel.myRole == nil {
          BoldTheme.FlatCard {
            VStack(alignment: .leading, spacing: BoldTheme.Space.s3) {
              Text("Join this group").font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
              Button("Request to join") { Task { await viewModel.join() } }
                .buttonStyle(SupPrimaryButtonStyle())
            }
          }
        }

        PillToggle(options: tabOptions, selection: $tab, scrollable: true)

        switch tab {
        case .leaderboard: leaderboardTab
        case .pickems: pickemsTab
        case .members: membersTab
        case .settings: settingsTab
        }

        if viewModel.myRole != nil && viewModel.myRole != .pending {
          Button("Leave group") { showLeaveConfirm = true }
            .font(BoldTheme.Fonts.body(15, weight: .semibold))
            .foregroundColor(BoldTheme.Role.lost)
            .padding(.top, BoldTheme.Space.s2)
        }
      }
      .padding(.horizontal, BoldTheme.Space.margin)
      .padding(.top, BoldTheme.Space.s2)
      .padding(.bottom, BoldTheme.Space.s6)
    }
    .confirmationDialog("Leave this group?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
      Button("Leave group", role: .destructive) {
        Task {
          guard let client else { return }
          do {
            _ = try await GroupsService(client: client).leaveGroup(groupId: group.id)
            dismiss()
          } catch { viewModel.errorText = error.localizedDescription }
        }
      }
    }
  }

  private func bannerCard(icon: String, title: String, subtitle: String) -> some View {
    BoldTheme.FlatCard {
      HStack(spacing: 12) {
        // GREEN, not gold -- this is a status icon, not an action, so it
        // shouldn't compete with the screen's one primary-action CTA.
        Image(systemName: icon).foregroundColor(BoldTheme.Colors.green)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(BoldTheme.Fonts.body(14, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
          Text(subtitle).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
        }
        Spacer()
      }
    }
  }

  // MARK: - Leaderboard tab

  private var leaderboardTab: some View {
    VStack(alignment: .leading, spacing: 14) {
      if viewModel.group?.sport == .both {
        PillToggle(options: [(label: "CFB", value: GroupSport.cfb), (label: "Pro Ball", value: .nfl)], selection: $viewModel.leaderboardSport)
          .onChange(of: viewModel.leaderboardSport) { _, _ in
            Task {
              await viewModel.loadAvailableWeeks()
              await viewModel.loadLeaderboard(scope: leaderboardScope)
            }
          }
      }
      PillToggle(options: [(label: "This week", value: LeaderboardScope.week), (label: "Season", value: .season)], selection: $leaderboardScope)
        .onChange(of: leaderboardScope) { _, newValue in
          Task { await viewModel.loadLeaderboard(scope: newValue) }
        }
      if leaderboardScope == .week && viewModel.availableWeeks.count > 1 {
        // Shared week pills: scrolls the selected week into view.
        WeekPills(weeks: viewModel.availableWeeks, selected: $viewModel.week)
        .onChange(of: viewModel.week) { Task { await viewModel.loadLeaderboard(scope: leaderboardScope) } }
      }

      if viewModel.leaderboard.isEmpty {
        Text("No results for this week yet.").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.textDim).padding(.vertical, 16)
      } else {
        BoldTheme.FlatCard {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text("Rank").frame(width: 40, alignment: .leading)
              Text("Player")
              Spacer()
              Text("Points")
            }
            .font(BoldTheme.Fonts.body(12, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
            .padding(.bottom, 6)

            ForEach(viewModel.leaderboard) { entry in
              HStack(spacing: 12) {
                Text(verbatim: "\(entry.rank)")
                  .font(BoldTheme.TypeRole.tableNumber(14))
                  .foregroundColor(BoldTheme.Colors.text)
                  .frame(width: 28, alignment: .leading)
                // Only the avatar+name area is the NavigationLink -- the row
                // isn't in a List, so a link wrapping the whole HStack would
                // fight with sibling controls elsewhere in this tab (kick/
                // promote menus on the Members tab use this same row shape).
                NavigationLink(destination: PublicProfileView(userId: entry.user_id)) {
                  HStack(spacing: 12) {
                    AvatarInitials(name: entry.display_name ?? "?", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(entry.display_name ?? "Unknown").font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                      if entry.role == .owner || entry.role == .admin { RoleBadge(role: entry.role) }
                    }
                  }
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                  // Ink table numbers: points, then the W-L record.
                  Text(jsNumber(entry.points)).font(BoldTheme.TypeRole.tableNumber(15)).foregroundColor(BoldTheme.Colors.text)
                  Text(verbatim: "\(entry.wins)–\(entry.losses)").font(BoldTheme.TypeRole.tableNumber(12, weight: .regular)).foregroundColor(BoldTheme.Colors.textDim)
                }
              }
              .padding(.vertical, 8)
              if entry.id != viewModel.leaderboard.last?.id {
                Divider().background(BoldTheme.Colors.border)
              }
            }
          }
        }
      }
    }
  }

  // MARK: - Pickems tab

  private var pickemsTab: some View {
    // This tab used to show standings with no way to actually get to the
    // pick-making screen (PickemsView) -- same gap as the web app's group
    // page, and the concrete cause of "didn't know how to find where to
    // make their picks" from a real user's invite-link session.
    VStack(alignment: .leading, spacing: 16) {
      NavigationLink(destination: PickemsView()) {
        Text("Make your picks")
      }
      .buttonStyle(SupPrimaryButtonStyle())

      if viewModel.pickemsAvailableWeeks.count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(viewModel.pickemsAvailableWeeks, id: \.self) { w in
              let active = w == viewModel.pickemsWeek
              Button {
                viewModel.pickemsWeek = w
              } label: {
                Text("Week \(w)")
                  .font(BoldTheme.Fonts.body(12.5, weight: .bold))
                  .padding(.horizontal, 16).padding(.vertical, 7)
                  .background(active ? BoldTheme.Colors.text : BoldTheme.Colors.track)
                  .foregroundColor(active ? BoldTheme.Colors.card : BoldTheme.Colors.textDim)
                  .clipShape(Capsule())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .onChange(of: viewModel.pickemsWeek) { Task { await viewModel.reloadPickemsLastGame() } }
      }

      PickemsStandingsView(
        season: viewModel.pickemsSeason,
        week: viewModel.pickemsWeek,
        lastGame: viewModel.pickemsLastGame,
        fixedGroupId: viewModel.group?.id
      )
    }
  }

  // MARK: - Members tab

  private var membersTab: some View {
    let pending = viewModel.members.filter { $0.role == .pending }
    let active = viewModel.members.filter { $0.role != .pending }

    return VStack(alignment: .leading, spacing: 16) {
      if viewModel.isAdmin && !pending.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Waiting for approval").font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
          ForEach(pending) { member in
            BoldTheme.GlassCard(radius: BoldTheme.Radius.card, padding: 12) {
              HStack {
                NavigationLink(destination: PublicProfileView(userId: member.user_id)) {
                  HStack {
                    AvatarInitials(name: member.display_name ?? "?", size: 32)
                    Text(member.display_name ?? "Unknown").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.text)
                  }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await viewModel.approve(userId: member.user_id) } } label: {
                  // GREEN, not gold -- repeats once per pending member, so
                  // it's a list accent rather than the screen's one
                  // primary-action CTA.
                  Image(systemName: "checkmark.circle.fill").foregroundColor(BoldTheme.Colors.green)
                }
                Button { Task { await viewModel.kick(userId: member.user_id) } } label: {
                  Image(systemName: "xmark.circle.fill").foregroundColor(BoldTheme.Role.lost)
                }
              }
            }
          }
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Members").font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
        // One flat card with compact rows, not a card per member.
        VStack(spacing: 0) {
        ForEach(active) { member in
          VStack(spacing: 0) {
            if member.id != active.first?.id { Rectangle().fill(BoldTheme.Colors.border).frame(height: 1) }
            HStack {
              NavigationLink(destination: PublicProfileView(userId: member.user_id)) {
                HStack {
                  AvatarInitials(name: member.display_name ?? "?", size: 32)
                  Text(member.display_name ?? "Unknown").font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Colors.text)
                }
              }
              .buttonStyle(.plain)
              Spacer()
              RoleBadge(role: member.role)
              if canManage(member) {
                Menu {
                  if viewModel.isOwner && member.role == .member {
                    Button("Make admin") { Task { await viewModel.promote(userId: member.user_id) } }
                  }
                  Button("Remove from group", role: .destructive) { Task { await viewModel.kick(userId: member.user_id) } }
                } label: {
                  Image(systemName: "ellipsis.circle").foregroundColor(BoldTheme.Colors.textDim)
                }
              }
            }
            .padding(.horizontal, BoldTheme.Space.cardPad)
            .padding(.vertical, 10)
          }
        }
        }
        .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
      }
    }
  }

  private func canManage(_ member: GroupMember) -> Bool {
    guard viewModel.isAdmin else { return false }
    if member.role == .owner { return false }
    if member.role == .admin && !viewModel.isOwner { return false }
    return true
  }

  // MARK: - Settings tab

  private var settingsTab: some View {
    VStack(alignment: .leading, spacing: 20) {
      EditGroupSection(viewModel: viewModel)

      InviteManagementSection(viewModel: viewModel)

      if viewModel.isOwner {
        BoldTheme.FlatCard {
          VStack(alignment: .leading, spacing: 8) {
            Text("Delete this group").font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
            Text("Removes the group and its board for everyone. This can't be undone.")
              .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
            Button("Delete group") { showDeleteConfirm = true }
              .font(BoldTheme.Fonts.body(15, weight: .semibold))
              .foregroundColor(BoldTheme.Role.lost)
          }
        }
        .confirmationDialog("Delete this group? This can't be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
          Button("Delete group", role: .destructive) {
            Task {
              guard let client, let group = viewModel.group else { return }
              do {
                _ = try await GroupsService(client: client).deleteGroup(groupId: group.id)
                dismiss()
              } catch { viewModel.errorText = error.localizedDescription }
            }
          }
        }
      }
    }
  }
}

private struct InviteManagementSection: View {
  @Environment(\.supabaseClient) private var client
  @ObservedObject var viewModel: GroupDetailViewModel
  @State private var isCreating = false
  @State private var justCreatedLink: String?
  @State private var justCreatedEmailResults: [InviteEmailResult] = []
  @State private var emailsInput = ""

  var body: some View {
    BoldTheme.GlassCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("Invites").font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
          Spacer()
          // Outline: "Save changes" above is this tab's one primary action.
          Button("Make a link") { Task { await createInvite() } }
            .buttonStyle(SmallPill(primary: false))
            .disabled(isCreating)
        }

        // Optional -- leaving this blank still generates a plain shareable
        // link, same as before this existed.
        TextField("Email invites (optional, comma-separated)", text: $emailsInput)
          .font(BoldTheme.Fonts.body(13))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.emailAddress)
          .padding(12)
          .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))

        if let link = justCreatedLink {
          HStack {
            Text(link).font(BoldTheme.Fonts.code(12)).foregroundColor(BoldTheme.Colors.text).lineLimit(1)
            Spacer()
            Button {
              UIPasteboard.general.string = link
            } label: {
              Image(systemName: "doc.on.doc").foregroundColor(BoldTheme.Colors.text)
            }
          }
          .padding(12).background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
        }

        if !justCreatedEmailResults.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(justCreatedEmailResults) { result in
              HStack {
                Text(result.email).font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim).lineLimit(1)
                Spacer()
                Text(result.ok ? "Sent" : "Failed")
                  .font(BoldTheme.Fonts.body(11, weight: .semibold))
                  .foregroundColor(result.ok ? BoldTheme.Colors.green : BoldTheme.Role.lost)
              }
            }
          }
        }

        if viewModel.invites.isEmpty {
          Text("No invite links yet.").font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
        } else {
          ForEach(viewModel.invites) { invite in
            BoldTheme.GlassCard(radius: BoldTheme.Radius.inner, padding: 10) {
              HStack {
                Text(invite.invite_token).font(BoldTheme.Fonts.code(12)).foregroundColor(BoldTheme.Colors.text)
                Spacer()
                Text(status(for: invite)).font(BoldTheme.Fonts.body(11)).foregroundColor(BoldTheme.Colors.textDim)
                Button {
                  Task { await revoke(invite) }
                } label: {
                  Image(systemName: "xmark").foregroundColor(BoldTheme.Role.lost)
                }
              }
            }
          }
        }
      }
    }
    .task { await viewModel.loadInvites() }
  }

  private func status(for invite: GroupInvite) -> String {
    if invite.revoked { return "revoked" }
    if let expiresAt = invite.expires_at, let date = ISO8601DateFormatter().date(from: expiresAt), date < Date() { return "expired" }
    if let maxUses = invite.max_uses, invite.uses >= maxUses { return "maxed" }
    return "active"
  }

  private func createInvite() async {
    guard let client, let group = viewModel.group else { return }
    isCreating = true
    defer { isCreating = false }
    do {
      // Accept commas, newlines, or spaces -- people paste lists in
      // whatever shape they have them.
      let emails = emailsInput
        .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      let result = try await GroupsService(client: client).createInvite(
        groupId: group.id, maxUses: nil, expiresAt: nil, emails: emails.isEmpty ? nil : emails
      )
      // Built on the apex (see SiteLinks) -- the only host that serves the
      // AASA file without a redirect, so the link opens the app.
      justCreatedLink = SiteLinks.url(path: result.joinUrl)?.absoluteString
      justCreatedEmailResults = result.emailResults ?? []
      emailsInput = ""
      await viewModel.loadInvites()
    } catch {
      viewModel.errorText = error.localizedDescription
    }
  }

  private func revoke(_ invite: GroupInvite) async {
    guard let client else { return }
    do {
      _ = try await GroupsService(client: client).revokeInvite(inviteToken: invite.invite_token)
      await viewModel.loadInvites()
    } catch {
      viewModel.errorText = error.localizedDescription
    }
  }
}

private struct EditGroupSection: View {
  @ObservedObject var viewModel: GroupDetailViewModel
  @State private var name = ""
  @State private var description = ""
  @State private var isPrivate = true
  @State private var isSaving = false
  @State private var savedRecently = false

  var body: some View {
    BoldTheme.GlassCard {
    VStack(alignment: .leading, spacing: 10) {
      Text("Group settings").font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)

      VStack(alignment: .leading, spacing: 6) {
        Text("Name").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
        TextField("Group name", text: $name)
          .font(BoldTheme.Fonts.body(14))
          .padding(12)
          .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Description").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
        TextField("Description (optional)", text: $description, axis: .vertical)
          .font(BoldTheme.Fonts.body(14))
          .lineLimit(2...4)
          .padding(12)
          .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
      }

      Toggle("Private group", isOn: $isPrivate)
        .font(BoldTheme.Fonts.body(14))

      HStack {
        Button {
          Task { await save() }
        } label: {
          if isSaving {
            ProgressView()
          } else {
            Text("Save changes")
          }
        }
        .buttonStyle(SupPrimaryButtonStyle(fullWidth: false))
        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)

        if savedRecently {
          // GREEN, not gold -- this confirmation text sits right next to
          // the gold Save Changes button; keeping gold on both would double
          // up the screen's one primary-action color as decoration.
          Text("Saved").font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.green)
        }
      }
    }
    .onAppear {
      name = viewModel.group?.name ?? ""
      description = viewModel.group?.description ?? ""
      isPrivate = viewModel.group?.is_private ?? true
    }
    }
  }

  private func save() async {
    isSaving = true; savedRecently = false
    defer { isSaving = false }
    let ok = await viewModel.updateGroup(
      name: name.trimmingCharacters(in: .whitespaces),
      description: description.isEmpty ? nil : description,
      isPrivate: isPrivate
    )
    if ok { savedRecently = true }
  }
}
