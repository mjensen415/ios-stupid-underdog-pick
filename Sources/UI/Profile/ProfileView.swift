import SwiftUI
import Supabase
import PhotosUI
import UserNotifications

struct ProfileView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  // Uses ProfilesService's ProfileRow directly (id/user_id/display_name/
  // avatar_url/email) instead of mapping into a separate local type -- the
  // previous version depended on a top-level `Profile` struct that only
  // existed in the dead ProfilesRepository.swift, an easy-to-miss hidden
  // coupling to unused code.
  @State private var profile: ProfileRow?
  @State private var displayName: String = ""
  @State private var email: String = ""
  @State private var isSavingName = false
  @State private var isSavingEmail = false
  @State private var errorMessage: String?
  @State private var emailMessage: String?
  @State private var loadError: String?

  @State private var avatarItem: PhotosPickerItem?
  @State private var isUploadingAvatar = false

  @State private var careerTotals: CareerTotals?
  @State private var seasonTotals: [TotalsLeaderboardRow] = []
  @State private var streak: Int = 0

  @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
  @State private var notificationPrefs: NotificationPreferencesRow = .allEnabled
  @State private var isRequestingPushPermission = false

  @State private var showDeleteConfirm = false
  @State private var isDeletingAccount = false
  @State private var deleteError: String?

  var body: some View {
    NavigationStack {
      Form {
        if let profile {
          Section {
            HStack {
              Spacer()
              VStack(spacing: 10) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                  ZStack {
                    if let urlString = profile.avatar_url, let url = URL(string: urlString) {
                      AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: avatarPlaceholder
                        }
                      }
                    } else {
                      avatarPlaceholder
                    }
                    if isUploadingAvatar {
                      Circle().fill(Color.black.opacity(0.5))
                      ProgressView().tint(BoldTheme.Colors.gold)
                    }
                  }
                  .frame(width: 72, height: 72)
                  .clipShape(Circle())
                }
                .disabled(isUploadingAvatar)
                Text("Tap to change photo")
                  .font(BoldTheme.Fonts.mono(11))
                  .foregroundColor(BoldTheme.Colors.textFaint)
              }
              Spacer()
            }
            .listRowBackground(BoldTheme.Colors.bgPage)
            .onChange(of: avatarItem) { _, newItem in
              Task { await uploadAvatar(newItem) }
            }

            TextField("Display Name", text: $displayName)
              .foregroundColor(BoldTheme.Colors.text)
            if let errorMessage {
              Text(errorMessage).foregroundColor(.red)
            }
            Button(isSavingName ? "Saving…" : "Save Name") { Task { await saveName() } }
              .disabled(isSavingName || displayName == (profile.display_name ?? ""))
              .foregroundColor(BoldTheme.Colors.goldDeep)

            TextField("Email", text: $email)
              .keyboardType(.emailAddress)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled(true)
              .foregroundColor(BoldTheme.Colors.text)
            if let emailMessage {
              Text(emailMessage).foregroundColor(BoldTheme.Colors.textDim).font(.footnote)
            }
            Button(isSavingEmail ? "Updating…" : "Update Email") { Task { await saveEmail() } }
              .disabled(isSavingEmail || email == (profile.email ?? ""))
              .foregroundColor(BoldTheme.Colors.goldDeep)
          } header: {
            Label("Account", systemImage: "person.crop.circle")
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

          Section {
            if streak > 0 {
              HStack(spacing: 6) {
                Text("🔥").font(.system(size: 13))
                Text(verbatim: "\(streak)-week streak")
                  .font(BoldTheme.Fonts.mono(12, weight: .semibold))
                  .foregroundColor(BoldTheme.Colors.goldDeep)
              }
              .padding(.horizontal, 10).padding(.vertical, 5)
              .background(BoldTheme.Colors.goldDeep.opacity(0.1))
              .clipShape(Capsule())
              .listRowInsets(EdgeInsets())
              .padding(.horizontal, 16).padding(.top, 4)
            }

            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("ALL-TIME RECORD").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
                Text(verbatim: "\(careerTotals?.wins ?? 0)W – \(careerTotals?.losses ?? 0)L")
                  .font(BoldTheme.Fonts.display(22))
                  .foregroundColor(BoldTheme.Colors.text)
              }
              Spacer()
              if let w = careerTotals?.wins, let l = careerTotals?.losses, w + l > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                  Text("COVER RATE").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
                  Text(verbatim: "\(Int((Double(w) / Double(w + l) * 100).rounded()))%")
                    .font(BoldTheme.Fonts.display(22))
                    .foregroundColor(BoldTheme.Colors.green)
                }
                Spacer()
              }
              VStack(alignment: .trailing, spacing: 2) {
                Text("POINTS").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
                Text(formatPoints(careerTotals?.totalPoints))
                  .font(BoldTheme.Fonts.display(22))
                  .foregroundColor(BoldTheme.Colors.goldDeep)
              }
            }
            .padding(.vertical, 4)

            ForEach(seasonTotals) { row in
              HStack {
                Text(verbatim: "\(row.season ?? 0)").foregroundColor(BoldTheme.Colors.text)
                Spacer()
                Text(verbatim: "\(row.wins ?? 0)W-\(row.losses ?? 0)L")
                  .font(BoldTheme.Fonts.mono(12))
                  .foregroundColor(BoldTheme.Colors.textFaint)
                Text(formatPoints(row.totalPoints))
                  .font(BoldTheme.Fonts.display(16))
                  // Per-season point totals down a list are GREEN, not gold --
                  // gold stays reserved for the single all-time career total
                  // above. Matches web's AccountInfoTab.tsx "By Season" list.
                  .foregroundColor(BoldTheme.Colors.green)
                  .frame(minWidth: 50, alignment: .trailing)
              }
            }

            NavigationLink(destination: PickHistoryView()) {
              Text("View Full Pick History")
                .foregroundColor(BoldTheme.Colors.goldDeep)
            }
          } header: {
            Label("Trophy Case", systemImage: "trophy.fill")
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

          Section {
            switch notificationAuthStatus {
            case .denied:
              Text("Notifications are off for SUP. Turn them on in iOS Settings to get pick reminders and score alerts.")
                .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
              Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
              }
              .foregroundColor(BoldTheme.Colors.goldDeep)
            case .authorized, .provisional, .ephemeral:
              Toggle("Pick reminders", isOn: $notificationPrefs.pick_reminder)
              Toggle("Game kickoff", isOn: $notificationPrefs.game_live)
              Toggle("Game results", isOn: $notificationPrefs.game_result)
              Toggle("Weekly recap", isOn: $notificationPrefs.weekly_recap)
            default:
              // .notDetermined -- covers existing users who upgraded past
              // this build and never saw the onboarding-flow prompt.
              Button(isRequestingPushPermission ? "Requesting…" : "Turn on notifications") {
                Task { await enablePush() }
              }
              .disabled(isRequestingPushPermission)
              .foregroundColor(BoldTheme.Colors.goldDeep)
            }
          } header: {
            Label("Notifications", systemImage: "bell.badge")
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
          .onChange(of: notificationPrefs) { _, newValue in
            guard let client else { return }
            Task { try? await PushService(client: client).updatePreferences(newValue) }
          }
        } else if let loadError {
          Section {
            Text(loadError).foregroundColor(.red)
            Button("Retry") { Task { await load() } }
              .foregroundColor(BoldTheme.Colors.goldDeep)
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
        } else {
          ProgressView().tint(BoldTheme.Colors.gold)
            .listRowBackground(BoldTheme.Colors.bgPage)
        }

        Section {
          Button("Sign Out", role: .destructive) {
            Task {
              if let client { await AuthService(client: client).signOut() }
              await MainActor.run { appState.session = nil }
            }
          }
        } header: {
          Label("Session", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

        Section {
          Button(isDeletingAccount ? "Deleting…" : "Delete Account", role: .destructive) {
            showDeleteConfirm = true
          }
          .disabled(isDeletingAccount)
        } header: {
          Label("Danger Zone", systemImage: "exclamationmark.triangle")
        } footer: {
          deleteError.map { Text($0).foregroundColor(.red) }
        }
        .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
        .confirmationDialog(
          "Delete your account?",
          isPresented: $showDeleteConfirm,
          titleVisibility: .visible
        ) {
          Button("Delete Account", role: .destructive) {
            Task { await deleteAccount() }
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("This permanently deletes your profile and removes you from every group. This can't be undone.")
        }

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
          Section(footer: Text("v\(version) (\(build))").foregroundColor(BoldTheme.Colors.textFaint)) { EmptyView() }
        }
      }
      .scrollContentBackground(.hidden)
      .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
      .navigationTitle("Profile")
      .toolbarBackground(BoldTheme.Colors.bgPage, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      // Frost's bgPage is light now (was dark under Bold) -- see
      // LeaderboardView.swift for the same fix and rationale.
      .toolbarColorScheme(.light, for: .navigationBar)
      .task { await load() }
    }
    .tint(BoldTheme.Colors.gold)
  }

  private var avatarPlaceholder: some View {
    ZStack {
      BoldTheme.Colors.text.opacity(0.08)
      Text(initials)
        .font(BoldTheme.Fonts.body(22, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.text)
    }
  }

  private var initials: String {
    let name = profile?.display_name?.isEmpty == false ? profile!.display_name! : (profile?.email ?? "?")
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap { $0.first }
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }

  private func formatPoints(_ x: Double?) -> String {
    guard let x else { return "0" }
    return x.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(x)) : String(format: "%.1f", x)
  }

  private func load() async {
    loadError = nil
    do {
      guard let client else { loadError = "Not signed in."; return }
      let p = try await ProfilesService(client: client).fetchMyProfile()
      guard let p else {
        await MainActor.run { loadError = "Couldn't find your profile." }
        return
      }
      await MainActor.run {
        profile = p
        displayName = p.display_name ?? ""
        email = p.email ?? ""
      }

      async let career = try? LeaderboardService(client: client).fetchMyCareerTotals(userId: p.user_id)
      async let seasons = try? LeaderboardService(client: client).fetchMySeasonTotals(userId: p.user_id)
      async let streakResult: Int? = {
        guard let ctx = try? await ContextService(client: client).getCurrentContext() else { return nil }
        return try? await LeaderboardService(client: client).fetchStreak(userId: p.user_id, season: ctx.season)
      }()
      async let authStatus = PushService(client: client).currentAuthorizationStatus()
      async let prefs = try? PushService(client: client).fetchPreferences()
      let (careerResult, seasonsResult, streakValue, authStatusValue, prefsValue) = await (career, seasons, streakResult, authStatus, prefs)
      await MainActor.run {
        careerTotals = careerResult ?? nil
        seasonTotals = seasonsResult ?? []
        streak = streakValue ?? 0
        notificationAuthStatus = authStatusValue
        notificationPrefs = prefsValue ?? .allEnabled
      }
    } catch {
      await MainActor.run {
        loadError = "Couldn't load your profile. Try again."
      }
    }
  }

  private func saveName() async {
    guard !displayName.isEmpty, let client else { return }
    isSavingName = true
    defer { isSavingName = false }
    do {
      try await ProfilesService(client: client).updateProfile(displayName: displayName)
      await MainActor.run {
        errorMessage = nil
        if let p = profile {
          profile = ProfileRow(id: p.id, user_id: p.user_id, display_name: displayName, avatar_url: p.avatar_url, has_onboarded: p.has_onboarded, favorite_team_id: p.favorite_team_id, game_interests: p.game_interests, pickems_intro_dismissed: p.pickems_intro_dismissed, email: p.email)
        }
      }
    } catch {
      await MainActor.run { errorMessage = "Couldn't save. Try again." }
    }
  }

  private func saveEmail() async {
    guard !email.isEmpty, let client else { return }
    isSavingEmail = true
    defer { isSavingEmail = false }
    do {
      try await client.auth.update(user: UserAttributes(email: email))
      await MainActor.run {
        emailMessage = "Check your new email address for a confirmation link to complete the change."
      }
    } catch {
      await MainActor.run { emailMessage = "Couldn't update email. Try again." }
    }
  }

  private func enablePush() async {
    guard let client else { return }
    isRequestingPushPermission = true
    defer { isRequestingPushPermission = false }
    let granted = await PushService(client: client).requestPermission()
    await MainActor.run {
      notificationAuthStatus = granted ? .authorized : .denied
    }
  }

  private func deleteAccount() async {
    guard let client else { return }
    isDeletingAccount = true
    deleteError = nil
    defer { isDeletingAccount = false }
    do {
      try await ProfilesService(client: client).deleteAccount()
      // Account is gone server-side; the local session is no longer valid
      // either way, so just drop it and let RootView route back to Auth.
      await MainActor.run { appState.session = nil }
    } catch {
      await MainActor.run { deleteError = error.localizedDescription }
    }
  }

  private func uploadAvatar(_ item: PhotosPickerItem?) async {
    guard let item, let client, let p = profile else { return }
    isUploadingAvatar = true
    defer { isUploadingAvatar = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      let url = try await ProfilesService(client: client).uploadAvatar(data: data, fileExtension: "jpg")
      try await ProfilesService(client: client).updateProfile(avatarUrl: url)
      await MainActor.run {
        profile = ProfileRow(id: p.id, user_id: p.user_id, display_name: p.display_name, avatar_url: url, has_onboarded: p.has_onboarded, favorite_team_id: p.favorite_team_id, game_interests: p.game_interests, pickems_intro_dismissed: p.pickems_intro_dismissed, email: p.email)
      }
    } catch {
      await MainActor.run { errorMessage = "Couldn't upload photo. Try again." }
    }
  }
}
