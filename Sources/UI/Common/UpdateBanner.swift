import SwiftUI

// Soft nudge only -- dismissible, never blocks the app. Dismissal is
// remembered per-version (UserDefaults), so saying "not now" doesn't nag
// again until the NEXT version bump actually ships.
private let dismissedVersionKey = "dismissedUpdateVersion"

struct UpdateBanner: View {
  let config: AppVersionConfig
  let onDismiss: () -> Void

  static let appStoreURL = URL(string: "https://apps.apple.com/app/id6790921821")!

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
    // Solid page color under the glass -- it floats over screen content,
    // which otherwise shows through the translucent glass.
    .background(BoldTheme.Colors.glassStrong)
    .background(BoldTheme.Colors.bgPage)
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BoldTheme.Colors.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .padding(.horizontal, 14)
    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
  }

  static func shouldShow(_ config: AppVersionConfig) -> Bool {
    UserDefaults.standard.string(forKey: dismissedVersionKey) != config.latestVersion
  }
}

/// Blocking screen for builds below app_version_config.min_supported_version.
/// No dismiss -- the only ways out are updating, or the floor being lowered
/// server-side (re-checked on "Check again" and every foreground).
struct UpdateRequiredView: View {
  let config: AppVersionConfig
  let recheck: () async -> Void
  @State private var checking = false

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      BoldTheme.AmbientBlobs().ignoresSafeArea()
      VStack(spacing: 18) {
        SupIcon(variant: .monogram)
          .frame(width: 72, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: 18))
        Text("TIME TO UPDATE")
          .font(BoldTheme.Fonts.display(30))
          .foregroundColor(BoldTheme.Colors.text)
        Text(config.updateMessage ?? "This version of Stupid Underdog Pick is out of date. Update to \(config.latestVersion) to keep making picks.")
          .font(BoldTheme.Fonts.body(15))
          .foregroundColor(BoldTheme.Colors.textDim)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 12)
        Button { UIApplication.shared.open(UpdateBanner.appStoreURL) } label: {
          Text("Update on the App Store")
            .font(BoldTheme.Fonts.body(15, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(BoldTheme.Colors.gold)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        Button {
          checking = true
          Task { await recheck(); checking = false }
        } label: {
          Text(checking ? "Checking…" : "Check again")
            .font(BoldTheme.Fonts.body(14, weight: .semibold))
            .foregroundColor(BoldTheme.Colors.textDim)
        }
        .disabled(checking)
      }
      .padding(28)
    }
    .interactiveDismissDisabled(true)
  }
}
