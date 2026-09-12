import SwiftUI

// Soft nudge only -- dismissible, never blocks the app. Dismissal is
// remembered per-version (UserDefaults), so saying "not now" doesn't nag
// again until the NEXT version bump actually ships.
private let dismissedVersionKey = "dismissedUpdateVersion"

struct UpdateBanner: View {
  let config: AppVersionConfig
  let onDismiss: () -> Void

  private static let appStoreURL = URL(string: "https://apps.apple.com/app/id6790921821")!

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "arrow.down.circle.fill")
        .font(.system(size: 20))
        .foregroundColor(BoldTheme.Colors.goldDeep)

      VStack(alignment: .leading, spacing: 1) {
        Text("Update Available")
          .font(BoldTheme.Fonts.body(13, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
        Text(config.updateMessage ?? "Version \(config.latestVersion) is ready on the App Store.")
          .font(BoldTheme.Fonts.body(11.5))
          .foregroundColor(BoldTheme.Colors.textDim)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      Button {
        UIApplication.shared.open(Self.appStoreURL)
      } label: {
        Text("Update")
          .font(BoldTheme.Fonts.body(12.5, weight: .bold))
          .foregroundColor(.white)
          .padding(.horizontal, 12).padding(.vertical, 7)
          .background(BoldTheme.Colors.green)
          .clipShape(Capsule())
      }

      Button {
        UserDefaults.standard.set(config.latestVersion, forKey: dismissedVersionKey)
        onDismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 10)
    .background(BoldTheme.Colors.glassStrong)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .padding(.horizontal, 14)
    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
  }

  static func shouldShow(_ config: AppVersionConfig) -> Bool {
    UserDefaults.standard.string(forKey: dismissedVersionKey) != config.latestVersion
  }
}
