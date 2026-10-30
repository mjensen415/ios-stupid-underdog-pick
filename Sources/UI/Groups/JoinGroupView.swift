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

        VStack(alignment: .leading, spacing: BoldTheme.Space.s4) {
          PillToggle(
            options: [(label: "Invite code", value: JoinMode.code), (label: "Group ID", value: JoinMode.groupId)],
            selection: $mode
          )

          BoldTheme.FlatCard {
            if mode == .code {
              VStack(alignment: .leading, spacing: 8) {
                Text("Invite code").font(BoldTheme.Fonts.body(14, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
                TextField("e.g. Ab3xQ9zK", text: $inviteCode)
                  .font(BoldTheme.Fonts.mono(15))
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .padding(12)
                  .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
              }
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text("Group ID").font(BoldTheme.Fonts.body(14, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
                TextField("Paste a group ID", text: $groupIdText)
                  .font(BoldTheme.Fonts.mono(15))
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .padding(12)
                  .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.inner, style: .continuous).fill(BoldTheme.Colors.track))
              }
            }
          }

          if let errorText {
            Text(errorText).foregroundColor(BoldTheme.Role.lost).font(BoldTheme.Fonts.body(14))
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
              Text(mode == .code ? "Join with code" : "Send request").frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(SupPrimaryButtonStyle())
          .disabled(isSubmitting || (mode == .code ? inviteCode.isEmpty : groupIdText.isEmpty))
        }
        .padding(BoldTheme.Space.margin)
      }
      .navigationTitle("Join a group")
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
        // Accept a pasted full invite link (https://stupidunderdogpick.com/
        // groups/join/<token>), not just a bare token -- someone who saved
        // or was sent the link itself would otherwise paste the whole URL
        // here and get a confusing "invite not found" instead of joining.
        let raw = inviteCode.trimmingCharacters(in: .whitespaces)
        let token = URL(string: raw).flatMap(DeepLinkHandler.groupJoinToken(from:)) ?? raw
        let result = try await GroupsService(client: client).joinByToken(inviteToken: token)
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
