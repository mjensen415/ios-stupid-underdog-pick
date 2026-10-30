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
      ScrollView {
        VStack(alignment: .leading, spacing: BoldTheme.Space.cardGap) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Pro tools")
              .font(BoldTheme.Fonts.body(28, weight: .bold))
              .foregroundColor(BoldTheme.Colors.text)
            Text("Info tools for underdog pickers. The game stays free, and Pro never changes entry, scoring, picks or prizes.")
              .font(BoldTheme.Fonts.body(14))
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
              toolRow(title: "Track record", blurb: "How the upset model has done, graded after every game. Free for everyone.", icon: "chart.bar.fill")
            }
            .buttonStyle(.plain)
          }

          Text("Not betting advice. SUP is free to play: no entry fees, no buy-ins, and SUP never holds or pays out money.")
            .font(BoldTheme.Fonts.body(12))
            .foregroundColor(BoldTheme.Colors.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BoldTheme.Space.margin)
        .padding(.vertical, BoldTheme.Space.s4)
      }
      .refreshable {
        if let client { await pro.refresh(client: client, userId: appState.session?.user.id) }
      }
    }
    .navigationTitle("SUP Pro")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var membersCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text("Your Pro tools")
            .font(BoldTheme.Fonts.body(18, weight: .bold))
            .foregroundColor(BoldTheme.Colors.text)
          SupPill(text: "On", kind: .green)
        }
        if featureFlags.isAdmin {
          Text("You're an admin, so you see Pro for testing.")
            .font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
        }
        if pro.optin.claimed {
          HStack(spacing: 4) {
            Text("Free for this season's players through \(pro.optin.untilText).")
            Button("Turn Pro off") { toggle(false) }
              .underline()
              .foregroundColor(BoldTheme.Colors.text)
              .disabled(pro.changing)
          }
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
          if let err = pro.changeError { Text(err).font(BoldTheme.Fonts.body(13, weight: .semibold)).foregroundColor(BoldTheme.Role.lost) }
        }
      }
      .padding(BoldTheme.Space.cardPad)
      NavigationLink { UnderdogBoardView() } label: {
        listToolRow(title: "Underdog Board", blurb: "This week's CFB dogs by line, with the market's win chance.")
      }
      .buttonStyle(.plain)
      listToolRow(title: "Last 3", blurb: "Each team's recent form, on every pick card.", chevron: false)
      if watchOn {
        listToolRow(title: "Where to watch", blurb: "Network links on every game. Tap to open the game.", chevron: false)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private func toggle(_ on: Bool) {
    guard let client, let uid = appState.session?.user.id else { return }
    Task { await pro.setOptin(on, client: client, userId: uid) }
  }

  private func toolRow(title: String, blurb: String, icon: String) -> some View {
    BoldTheme.FlatCard {
      HStack(spacing: 12) {
        Image(systemName: icon).foregroundColor(BoldTheme.Colors.text).font(.system(size: 18))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(BoldTheme.Fonts.body(16, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
          Text(blurb).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
  }

  /// A compact row inside the members card, hairline above.
  private func listToolRow(title: String, blurb: String, chevron: Bool = true) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(BoldTheme.Fonts.body(15, weight: .semibold)).foregroundColor(BoldTheme.Colors.text)
        Text(blurb).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      if chevron {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
    .padding(.horizontal, BoldTheme.Space.cardPad)
    .padding(.vertical, BoldTheme.Space.s3)
    .overlay(alignment: .top) { Rectangle().fill(BoldTheme.Colors.border).frame(height: 1) }
    .contentShape(Rectangle())
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
      Text("Thanks for playing this season")
        .font(BoldTheme.Fonts.body(13, weight: .semibold))
        .foregroundColor(BoldTheme.Colors.textDim)
      Text("Pro is free for you")
        .font(BoldTheme.Fonts.body(22, weight: .bold))
        .foregroundColor(BoldTheme.Colors.text)
      Text("You were already making picks before Pro launched, so every Pro tool is yours free through \(pro.optin.untilText). It stays off until you turn it on, and you can turn it off any time.")
        .font(BoldTheme.Fonts.body(14))
        .foregroundColor(BoldTheme.Colors.text)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        guard let client, let uid = appState.session?.user.id else { return }
        Task { await pro.setOptin(true, client: client, userId: uid) }
      } label: {
        Text(pro.changing ? "Turning it on…" : "Turn on Pro, free")
      }
      // The screen's one primary action.
      .buttonStyle(SupPrimaryButtonStyle())
      .disabled(pro.changing)
      .padding(.top, 6)
      if let err = pro.changeError {
        Text(err).font(BoldTheme.Fonts.body(13, weight: .semibold)).foregroundColor(BoldTheme.Role.lost)
      }
    }
    .padding(BoldTheme.Space.cardPad)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }
}

/// For players who aren't Pro and aren't on the opt-in list. No price, no
/// purchase, no link out.
struct ProToolsTeaser: View {
  var body: some View {
    BoldTheme.FlatCard {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
          Text("Pro tools").font(BoldTheme.Fonts.body(13, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
        }
        Text("Coming to more players on iOS")
          .font(BoldTheme.Fonts.body(20, weight: .bold))
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
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(offer ? "Pro is free for you this season" : isPro ? "Your Pro tools" : "SUP Pro")
          .font(BoldTheme.Fonts.body(15, weight: .semibold))
          .foregroundColor(BoldTheme.Colors.text)
        Text("Underdog Board, last 3 and where to watch")
          .font(BoldTheme.Fonts.body(13))
          .foregroundColor(BoldTheme.Colors.textDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 4)
      if offer {
        SupPill(text: "Turn on", kind: .green)
      } else {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(BoldTheme.Colors.textFaint)
      }
    }
    .padding(.horizontal, BoldTheme.Space.cardPad)
    .padding(.vertical, BoldTheme.Space.s3)
    .frame(minHeight: 52)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
    .contentShape(Rectangle())
  }
}
