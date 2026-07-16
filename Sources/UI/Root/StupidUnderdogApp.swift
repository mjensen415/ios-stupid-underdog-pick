import SwiftUI

@main
struct StupidUnderdogApp: App {
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      Group {
        if let e = appState.startupError {
          VStack(spacing: 12) {
            Text("STARTUP ERROR").font(BoldTheme.Fonts.display(28)).foregroundColor(BoldTheme.Colors.text)
            Text(e.localizedDescription).multilineTextAlignment(.center).foregroundColor(BoldTheme.Colors.textDim)
            Text("Check SUPABASE_URL / SUPABASE_ANON_KEY in Info.plist.").font(BoldTheme.Fonts.mono(11)).foregroundColor(BoldTheme.Colors.textFaint)
          }
          .padding()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(BoldTheme.Colors.bgPage.ignoresSafeArea())
        } else if let client = appState.client {
          RootView()
            .environmentObject(appState)
            .environment(\.supabaseClient, client)
        } else {
          ZStack {
            BoldTheme.Colors.bgPage.ignoresSafeArea()
            ProgressView("Starting…").tint(BoldTheme.Colors.gold).foregroundColor(BoldTheme.Colors.textDim)
          }
        }
      }
      .task {
        // Create client and attempt session restore
        do {
#if DEBUG
          let env = ProcessInfo.processInfo.environment
          let supKeys = env.keys.filter { $0.uppercased().contains("SUPABASE") }.sorted()
          print("[Config][ENV] SUP keys visible at runtime:", supKeys)
          for k in supKeys {
            let val = env[k] ?? ""
            let redacted = val.count > 12 ? String(val.prefix(6)) + "…" + String(val.suffix(4)) : val
            print("[Config][ENV] \(k) = \(redacted)")
          }
#endif
          let c = try SupabaseClientProvider.makeClient()
          appState.client = c
          #if DEBUG
          if let urlStr = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String {
            let redacted = urlStr.replacingOccurrences(of: "https://", with: "https://…")
            print("[Config] SUPABASE_URL =", redacted)
          } else {
            print("[Config][WARN] SUPABASE_URL missing")
          }
          if let keyStr = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String {
            print("[Config] SUPABASE_ANON_KEY present =", !keyStr.isEmpty)
          } else {
            print("[Config][WARN] SUPABASE_ANON_KEY missing")
          }
          print("[Config] client OK")
          #endif
          // Try to fetch existing session
          do {
            let current = try await c.auth.session
            appState.session = current
            #if DEBUG
            print("[Auth] session restored =", current.user.id.uuidString)
            #endif
          } catch {
            #if DEBUG
            print("[Auth] no existing session:", error.localizedDescription)
            #endif
          }
        } catch {
          appState.startupError = error
        }
      }
      .onOpenURL { url in
        #if DEBUG
        print("[DeepLink] received URL:", url.absoluteString)
        #endif
        Task { [weak appState] in
          guard let client = appState?.client else {
            #if DEBUG
            print("[DeepLink][ERR] no client when handling URL")
            #endif
            return
          }
          do {
            try await client.auth.session(from: url)
            let s = try await client.auth.session
            appState?.session = s
            #if DEBUG
            print("[DeepLink] session restored. user:", s.user.id.uuidString)
            #endif
          } catch {
            #if DEBUG
            print("[DeepLink][ERR] session(from:) failed:", error.localizedDescription)
            #endif
          }
        }
      }
    }
  }
}

