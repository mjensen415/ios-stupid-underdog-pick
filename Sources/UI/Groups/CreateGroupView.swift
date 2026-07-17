import SwiftUI

struct CreateGroupView: View {
  @Environment(\.supabaseClient) private var client
  @Environment(\.dismiss) private var dismiss
  var onCreated: () async -> Void

  @State private var name = ""
  @State private var description = ""
  @State private var isPrivate = true
  @State private var isSubmitting = false
  @State private var errorText: String?

  private var nameValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 40 }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Group name", text: $name)
          Text(verbatim: "\(name.count)/40 characters")
            .font(BoldTheme.Fonts.mono(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
        }
        Section {
          TextField("Description (optional)", text: $description, axis: .vertical)
            .lineLimit(3...6)
        }
        Section {
          Toggle("Private Group", isOn: $isPrivate)
          Text("Members need approval to join")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        if let errorText {
          Text(errorText).foregroundColor(.red).font(BoldTheme.Fonts.body(13))
        }
      }
      .navigationTitle("Create Group")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSubmitting {
            ProgressView()
          } else {
            Button("Create") { Task { await submit() } }.disabled(!nameValid)
          }
        }
      }
    }
  }

  private func submit() async {
    guard let client, nameValid else { return }
    isSubmitting = true; errorText = nil
    defer { isSubmitting = false }
    do {
      _ = try await GroupsService(client: client).createGroup(
        name: name.trimmingCharacters(in: .whitespaces),
        description: description.isEmpty ? nil : description,
        isPrivate: isPrivate
      )
      await onCreated()
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
