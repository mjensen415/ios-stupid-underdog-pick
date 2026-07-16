import SwiftUI
import Supabase
import PhotosUI

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

  var body: some View {
    NavigationStack {
      Form {
        if let profile {
          Section("Account") {
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
              .foregroundColor(BoldTheme.Colors.gold)

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
              .foregroundColor(BoldTheme.Colors.gold)
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

          Section("Career Stats") {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("ALL-TIME RECORD").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
                Text("\(careerTotals?.wins ?? 0)W – \(careerTotals?.losses ?? 0)L")
                  .font(BoldTheme.Fonts.display(22))
                  .foregroundColor(BoldTheme.Colors.text)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 2) {
                Text("POINTS").font(BoldTheme.Fonts.mono(10)).foregroundColor(BoldTheme.Colors.textFaint)
                Text(formatPoints(careerTotals?.totalPoints))
                  .font(BoldTheme.Fonts.display(22))
                  .foregroundColor(BoldTheme.Colors.gold)
              }
            }
            .padding(.vertical, 4)

            ForEach(seasonTotals) { row in
              HStack {
                Text("\(row.season ?? 0)").foregroundColor(BoldTheme.Colors.text)
                Spacer()
                Text("\(row.wins ?? 0)W-\(row.losses ?? 0)L")
                  .font(BoldTheme.Fonts.mono(12))
                  .foregroundColor(BoldTheme.Colors.textFaint)
                Text(formatPoints(row.totalPoints))
                  .font(BoldTheme.Fonts.display(16))
                  .foregroundColor(BoldTheme.Colors.gold)
                  .frame(minWidth: 50, alignment: .trailing)
              }
            }

            NavigationLink(destination: PickHistoryView()) {
              Text("View Full Pick History")
                .foregroundColor(BoldTheme.Colors.gold)
            }
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
        } else if let loadError {
          Section {
            Text(loadError).foregroundColor(.red)
            Button("Retry") { Task { await load() } }
              .foregroundColor(BoldTheme.Colors.gold)
          }
          .listRowBackground(BoldTheme.Colors.text.opacity(0.04))
        } else {
          ProgressView().tint(BoldTheme.Colors.gold)
            .listRowBackground(BoldTheme.Colors.bgPage)
        }

        Section {
          Button("Sign Out", role: .destructive) {
            Task {
              if let client { try? await AuthService(client: client).signOut() }
              await MainActor.run { appState.session = nil }
            }
          }
        }
        .listRowBackground(BoldTheme.Colors.text.opacity(0.04))

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
      .toolbarColorScheme(.dark, for: .navigationBar)
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
      let (careerResult, seasonsResult) = await (career, seasons)
      await MainActor.run {
        careerTotals = careerResult ?? nil
        seasonTotals = seasonsResult ?? []
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
          profile = ProfileRow(id: p.id, user_id: p.user_id, display_name: displayName, avatar_url: p.avatar_url, email: p.email)
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

  private func uploadAvatar(_ item: PhotosPickerItem?) async {
    guard let item, let client, let p = profile else { return }
    isUploadingAvatar = true
    defer { isUploadingAvatar = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      let url = try await ProfilesService(client: client).uploadAvatar(data: data, fileExtension: "jpg")
      try await ProfilesService(client: client).updateProfile(avatarUrl: url)
      await MainActor.run {
        profile = ProfileRow(id: p.id, user_id: p.user_id, display_name: p.display_name, avatar_url: url, email: p.email)
      }
    } catch {
      await MainActor.run { errorMessage = "Couldn't upload photo. Try again." }
    }
  }
}
