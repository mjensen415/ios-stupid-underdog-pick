import SwiftUI

struct LaunchBanner: View {
  var body: some View {
    VStack(spacing: 12) {
      Text("✅ Root Scene Mounted")
        .font(.title.bold())
      Text("If you see this, SwiftUI WindowGroup is alive.")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }
}


