import SwiftUI
import Supabase

struct ProfileView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  @State private var profile: Profile?
  @State private var displayName: String = ""
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var loadError: String?

  var body: some View {
    NavigationStack {
      Form {
        if let profile {
          Section("Account") {
            Text("Email: \(profile.email)")
              .foregroundColor(BoldTheme.Colors.textDim)
            TextField("Display Name", text: $displayName)
              .foregroundColor(BoldTheme.Colors.text)
            if let errorMessage {
              Text(errorMessage).foregroundColor(.red)
            }
            Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
              .disabled(isSaving)
              .foregroundColor(BoldTheme.Colors.gold)
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

  private func load() async {
    loadError = nil
    do {
      guard let client else { loadError = "Not signed in."; return }
      let p = try await ProfilesService(client: client).fetchMyProfile()
      await MainActor.run {
        if let p {
          profile = Profile(id: p.id, email: p.email ?? "", display_name: p.display_name)
          displayName = p.display_name ?? ""
        } else {
          loadError = "Couldn’t find your profile."
        }
      }
    } catch {
      await MainActor.run {
        loadError = "Couldn’t load your profile. Try again."
      }
    }
  }

  private func save() async {
    guard !displayName.isEmpty else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      guard let client else { return }
      // profiles is keyed by user_id, not id (id is an unrelated
      // auto-generated PK) -- filtering on "id" here matched zero rows and
      // silently no-op'd every save.
      struct Update: Encodable { let display_name: String }
      if let uid = try? await client.auth.session.user.id {
        _ = try await client
          .from("profiles")
          .update(Update(display_name: displayName))
          .eq("user_id", value: uid)
          .execute()
      }
      await MainActor.run {
        profile = profile.map { Profile(id: $0.id, email: $0.email, display_name: displayName) }
        errorMessage = nil
      }
    } catch {
      errorMessage = "Couldn’t save. Try again."
    }
  }
}
