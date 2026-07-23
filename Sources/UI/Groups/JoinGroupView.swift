import SwiftUI

private enum JoinMode: Hashable {
  case code
  case groupId
}

struct JoinGroupView: View {
  @Environment(\.supabaseClient) private var client
  @Environment(\.dismiss) private var dismiss
  var onJoined: () async -> Void

  @State private var mode: JoinMode = .code
  @State private var inviteCode = ""
  @State private var groupIdText = ""
  @State private var isSubmitting = false
  @State private var errorText: String?
  @State private var successMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        BoldTheme.Colors.bgPage.ignoresSafeArea()
        BoldTheme.AmbientBlobs().ignoresSafeArea()

        VStack(alignment: .leading, spacing: 20) {
          PillToggle(
            options: [(label: "Invite Code", value: JoinMode.code), (label: "Group ID", value: JoinMode.groupId)],
            selection: $mode
          )

          BoldTheme.GlassCard(strong: true, radius: 16, padding: 16) {
            if mode == .code {
              VStack(alignment: .leading, spacing: 8) {
                Text("INVITE CODE").font(BoldTheme.Fonts.mono(11)).foregroundColor(BoldTheme.Colors.textFaint)
                TextField("e.g. Ab3xQ9zK", text: $inviteCode)
                  .font(BoldTheme.Fonts.mono(15))
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .padding(12)
                  .background(BoldTheme.Colors.surface)
                  .cornerRadius(10)
              }
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text("GROUP ID").font(BoldTheme.Fonts.mono(11)).foregroundColor(BoldTheme.Colors.textFaint)
                TextField("Paste a group ID", text: $groupIdText)
                  .font(BoldTheme.Fonts.mono(15))
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .padding(12)
                  .background(BoldTheme.Colors.surface)
                  .cornerRadius(10)
              }
            }
          }

          if let errorText {
            Text(errorText).foregroundColor(.red).font(BoldTheme.Fonts.body(13))
          }
          if let successMessage {
            // GREEN, not gold -- the submit button below is this screen's
            // one primary-action CTA; this is just decorative confirmation
            // feedback next to it.
            Text(successMessage).foregroundColor(BoldTheme.Colors.green).font(BoldTheme.Fonts.body(13, weight: .semibold))
          }

          Spacer()

          Button {
            Task { await submit() }
          } label: {
            if isSubmitting {
              ProgressView().frame(maxWidth: .infinity)
            } else {
              Text(mode == .code ? "Join with Code" : "Send Request").frame(maxWidth: .infinity)
            }
          }
          .font(BoldTheme.Fonts.display(20))
          .padding(.vertical, 14)
          .background(BoldTheme.Colors.gold)
          .foregroundColor(BoldTheme.Colors.text)
          .cornerRadius(14)
          .disabled(isSubmitting || (mode == .code ? inviteCode.isEmpty : groupIdText.isEmpty))
        }
        .padding(20)
      }
      .navigationTitle("Join Group")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(isSubmitting)
        }
      }
    }
  }

  private func submit() async {
    guard let client else { return }
    isSubmitting = true; errorText = nil; successMessage = nil
    defer { isSubmitting = false }
    do {
      if mode == .code {
        let result = try await GroupsService(client: client).joinByToken(inviteToken: inviteCode.trimmingCharacters(in: .whitespaces))
        await onJoined()
        dismiss()
        _ = result
      } else {
        guard let groupId = UUID(uuidString: groupIdText.trimmingCharacters(in: .whitespaces)) else {
          errorText = "That doesn't look like a valid group ID."
          return
        }
        let result = try await GroupsService(client: client).joinGroup(groupId: groupId)
        await onJoined()
        if result.status == "pending" {
          successMessage = result.message
        } else {
          dismiss()
        }
      }
    } catch {
      errorText = error.localizedDescription
    }
  }
}
