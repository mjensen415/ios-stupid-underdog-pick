import SwiftUI
import Supabase

struct ProfileView: View {
  @EnvironmentObject var appState: AppState
  @Environment(\.supabaseClient) private var client
  @State private var profile: Profile?
  @State private var displayName: String = ""
  @State private var isSaving = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        if let profile {
          Section("Account") {
            Text("Email: \(profile.email)")
            TextField("Display Name", text: $displayName)
            if let errorMessage {
              Text(errorMessage).foregroundColor(.red)
            }
            Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
              .disabled(isSaving)
          }
        } else {
          ProgressView()
        }

        Section {
          Button("Sign Out", role: .destructive) {
            Task {
              if let client { try? await AuthService(client: client).signOut() }
              await MainActor.run { appState.session = nil }
            }
          }
        }

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
          Section(footer: Text("v\(version) (\(build))")) { EmptyView() }
        }
      }
      .navigationTitle("Profile")
      .task { await load() }
    }
  }

  private func load() async {
    do {
      guard let client else { return }
      let p = try await ProfilesService(client: client).fetchMyProfile()
      await MainActor.run {
        if let p {
          profile = Profile(id: p.id, email: p.email ?? "", display_name: p.display_name)
          displayName = p.display_name ?? ""
        }
      }
    } catch {
      // ignore
    }
  }

  private func save() async {
    guard !displayName.isEmpty else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      guard let client else { return }
      // Minimal update via direct table update to match earlier repo behavior
      struct Update: Encodable { let display_name: String }
      if let uid = try? await client.auth.session.user.id {
        _ = try await client
          .from("profiles")
          .update(Update(display_name: displayName))
          .eq("id", value: uid)
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
