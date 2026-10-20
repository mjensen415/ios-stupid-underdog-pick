import SwiftUI
import Supabase

// SUP Pro hub, free tier only. App Store rules for this app (owner decision,
// Oct 2026): no prices, no purchase or upgrade buttons, no links to buy on
// the web, no "$" anywhere about Pro. Pro comes only from what the server
// already grants (admin comps, the free opt-in for this season's players,
// sup_pro_open); this screen just shows the opt-in card and the tools.

struct ProView: View {
  @EnvironmentObject private var appState: AppState
  @EnvironmentObject private var featureFlags: FeatureFlagStore
  @EnvironmentObject private var pro: ProStore
  @Environment(\.supabaseClient) private var client

  private var isPro: Bool { pro.isPro(admin: featureFlags.isAdmin) }
  private var showOptin: Bool { pro.optin.eligible && !pro.optin.claimed && (!pro.hasPro || featureFlags.isAdmin) }
  private var trackRecordOn: Bool { featureFlags.isVisible(FeatureFlagKey.trackRecord) }
  private var watchOn: Bool { featureFlags.isVisible(FeatureFlagKey.watchLinks) }

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      BoldTheme.AmbientBlobs().ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text("SUP PRO")
              .font(BoldTheme.Fonts.mono(11, weight: .bold))
              .tracking(1.3)
              .foregroundColor(BoldTheme.Colors.green)
            Text("PRO TOOLS")
              .font(BoldTheme.Fonts.display(44))
              .foregroundColor(BoldTheme.Colors.text)
            Text("Info tools for underdog pickers. The game stays free, and Pro never changes entry, scoring, picks or prizes.")
              .font(BoldTheme.Fonts.body(13.5))
              .foregroundColor(BoldTheme.Colors.textDim)
              .fixedSize(horizontal: false, vertical: true)
          }

          if showOptin { ProOptinCard() }

          if isPro {
            membersCard
          } else if !showOptin {
            ProToolsTeaser()
          }

          if trackRecordOn {
            NavigationLink { TrackRecordView() } label: {
              toolRow(title: "TRACK RECORD", blurb: "How the upset model has done, graded after every game. Free for everyone.", icon: "chart.bar.fill")
            }
            .buttonStyle(.plain)
          }

          Text("Not betting advice. SUP is free to play: no entry fees, no buy-ins, and SUP never holds or pays out money.")
            .font(BoldTheme.Fonts.body(11))
            .foregroundColor(BoldTheme.Colors.textFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
      }
      .refreshable {
        if let client { await pro.refresh(client: client, userId: appState.session?.user.id) }
      }
    }
    .navigationTitle("SUP Pro")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var membersCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Text("PRO")
          .font(BoldTheme.Fonts.mono(10, weight: .bold))
          .foregroundColor(BoldTheme.Colors.text)
          .padding(.horizontal, 7).padding(.vertical, 2)
          .background(GoldHatchBackground(radius: 5))
        Text("YOUR PRO TOOLS")
          .font(BoldTheme.Fonts.display(28))
          .foregroundColor(BoldTheme.Colors.gold)
      }
      if featureFlags.isAdmin {
        Text("You're an admin, so you see Pro for testing.")
          .font(BoldTheme.Fonts.body(12)).foregroundColor(.white.opacity(0.6))
      }
      if pro.optin.claimed {
        HStack(spacing: 4) {
          Text("Free for this season's players through \(pro.optin.untilText).")
          Button("Turn Pro off") { toggle(false) }
            .underline()
            .foregroundColor(.white)
            .disabled(pro.changing)
        }
        .font(BoldTheme.Fonts.body(12))
        .foregroundColor(.white.opacity(0.7))
        if let err = pro.changeError { Text(err).font(BoldTheme.Fonts.body(12, weight: .bold)).foregroundColor(Color(hex: 0xFFB4A8)) }
      }
      NavigationLink { UnderdogBoardView() } label: {
        darkToolRow(title: "UNDERDOG BOARD", blurb: "This week's CFB dogs by line, with the market's win chance.")
      }
      .buttonStyle(.plain)
      darkToolRow(title: "LAST 3", blurb: "Each team's recent form, on every pick card.", chevron: false)
      if watchOn {
        darkToolRow(title: "WHERE TO WATCH", blurb: "Network links on every game. Tap to open the game.", chevron: false)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 22).fill(BoldTheme.Colors.text))
    .shadow(color: BoldTheme.Colors.text.opacity(0.25), radius: 18, y: 10)
  }

  private func toggle(_ on: Bool) {
    guard let client, let uid = appState.session?.user.id else { return }
    Task { await pro.setOptin(on, client: client, userId: uid) }
  }

  private func toolRow(title: String, blurb: String, icon: String) -> some View {
    BoldTheme.GlassCard(strong: true, radius: 16, padding: 14) {
      HStack(spacing: 12) {
        Image(systemName: icon).foregroundColor(BoldTheme.Colors.green).font(.system(size: 18))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(BoldTheme.Fonts.display(22)).foregroundColor(BoldTheme.Colors.text)
          Text(blurb).font(BoldTheme.Fonts.body(12.5)).foregroundColor(BoldTheme.Colors.textDim)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
  }

  private func darkToolRow(title: String, blurb: String, chevron: Bool = true) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(BoldTheme.Fonts.display(21)).foregroundColor(.white)
        Text(blurb).font(BoldTheme.Fonts.body(12)).foregroundColor(.white.opacity(0.65))
      }
      Spacer()
      if chevron { Text("OPEN →").font(BoldTheme.Fonts.display(18)).foregroundColor(BoldTheme.Colors.gold) }
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
  }
}

/// "Thanks for playing this season" card for players on the frozen opt-in
/// list. Copy from the web's Pro.tsx. The claim only happens on the
/// player's own tap.
struct ProOptinCard: View {
  @EnvironmentObject private var appState: AppState
  @EnvironmentObject private var pro: ProStore
  @Environment(\.supabaseClient) private var client

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("THANKS FOR PLAYING THIS SEASON")
        .font(BoldTheme.Fonts.mono(10.5, weight: .bold))
        .tracking(1.2)
        .foregroundColor(BoldTheme.Colors.goldDeep)
      Text("PRO IS FREE FOR YOU")
        .font(BoldTheme.Fonts.display(32))
        .foregroundColor(BoldTheme.Colors.text)
      Text("You were already making picks before Pro launched, so every Pro tool is yours free through \(pro.optin.untilText). It stays off until you turn it on, and you can turn it off any time.")
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.text)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        guard let client, let uid = appState.session?.user.id else { return }
        Task { await pro.setOptin(true, client: client, userId: uid) }
      } label: {
        Text(pro.changing ? "Turning it on…" : "Turn on Pro, free →")
          .font(BoldTheme.Fonts.body(15, weight: .bold))
          .foregroundColor(BoldTheme.Colors.gold)
          .padding(.horizontal, 18).padding(.vertical, 12)
          .background(RoundedRectangle(cornerRadius: 12).fill(BoldTheme.Colors.text))
      }
      .buttonStyle(.plain)
      .disabled(pro.changing)
      .padding(.top, 6)
      if let err = pro.changeError {
        Text(err).font(BoldTheme.Fonts.body(13, weight: .bold)).foregroundColor(Color(hex: 0x8A1C1C))
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(GoldHatchBackground(radius: 22))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(BoldTheme.Colors.goldDeep.opacity(0.35), lineWidth: 2))
    .shadow(color: BoldTheme.Colors.goldDeep.opacity(0.22), radius: 20, y: 12)
  }
}

/// For players who aren't Pro and aren't on the opt-in list. No price, no
/// purchase, no link out.
struct ProToolsTeaser: View {
  var body: some View {
    BoldTheme.GlassCard(strong: true, radius: 18, padding: 18) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundColor(BoldTheme.Colors.goldDeep)
          Text("PRO TOOLS").font(BoldTheme.Fonts.mono(10.5, weight: .bold)).tracking(1).foregroundColor(BoldTheme.Colors.goldDeep)
        }
        Text("COMING TO MORE PLAYERS ON iOS")
          .font(BoldTheme.Fonts.display(26))
          .foregroundColor(BoldTheme.Colors.text)
        Text("The Underdog Board, each team's last 3 games on the pick card, and where to watch every game. Right now they're on for players who were already picking this season.")
          .font(BoldTheme.Fonts.body(13.5))
          .foregroundColor(BoldTheme.Colors.textDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Home / Settings entry to the Pro screen.
struct ProEntryCard: View {
  @EnvironmentObject private var pro: ProStore
  @EnvironmentObject private var featureFlags: FeatureFlagStore

  var body: some View {
    let isPro = pro.isPro(admin: featureFlags.isAdmin)
    let offer = pro.optin.eligible && !pro.optin.claimed
    HStack(spacing: 12) {
      Text("PRO")
        .font(BoldTheme.Fonts.mono(11, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(GoldHatchBackground(radius: 6))
      VStack(alignment: .leading, spacing: 2) {
        Text(offer ? "PRO IS FREE FOR YOU" : isPro ? "YOUR PRO TOOLS" : "SUP PRO")
          .font(BoldTheme.Fonts.display(20))
          .foregroundColor(BoldTheme.Colors.text)
        Text(offer ? "Thanks for playing this season. Turn it on when you want." : "Underdog Board, last 3 and where to watch.")
          .font(BoldTheme.Fonts.body(12))
          .foregroundColor(BoldTheme.Colors.textDim)
          .lineLimit(2)
      }
      Spacer(minLength: 4)
      Image(systemName: "chevron.right").foregroundColor(BoldTheme.Colors.textFaint)
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 16).fill(BoldTheme.Colors.glassStrong))
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(offer ? BoldTheme.Colors.goldDeep.opacity(0.5) : BoldTheme.Colors.border, lineWidth: 1))
  }
}
