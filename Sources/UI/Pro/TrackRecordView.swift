import SwiftUI
import Supabase

// Track record of the outright-upset model -- free and public (the
// `track_record` flag; admins always). Read-only port of the web's
// src/pages/TrackRecord.tsx, from the track_record(p_season, 'cfb') RPC.
// Skipped on iOS: the charts (shown as tables here) and the experimental
// "cover model, tested" table, which the web grades in the browser.

struct TrackWeek: Decodable, Identifiable, Equatable {
  let week: Int
  let games: Int
  let upsets: Int
  let expected: Double
  let expected_tier: Double
  let log_loss_sum: Double
  let upset_points: Double?
  let top_n: Int
  let top_hits: Int
  let top_points: Double
  let top_expected_points: Double
  var id: Int { week }
}

struct CalBucket: Decodable, Equatable, Identifiable {
  let lo: Double
  let hi: Double
  let n: Int
  let predicted: Double
  let actual: Double
  var id: Double { lo }
}

struct TrackRecordData: Decodable, Equatable {
  let season: Int?
  let current_week: Int?
  let weeks: [TrackWeek]
  let calibration: [CalBucket]
}

struct TrackRecordTotals: Equatable {
  let games: Int, upsets: Int, expected: Double, expectedTier: Double
  let logLoss: Double?, topN: Int, topHits: Int, topPts: Double, topExp: Double

  init(_ weeks: [TrackWeek]) {
    games = weeks.reduce(0) { $0 + $1.games }
    upsets = weeks.reduce(0) { $0 + $1.upsets }
    expected = weeks.reduce(0) { $0 + $1.expected }
    expectedTier = weeks.reduce(0) { $0 + $1.expected_tier }
    logLoss = games > 0 ? weeks.reduce(0) { $0 + $1.log_loss_sum } / Double(games) : nil
    topN = weeks.reduce(0) { $0 + $1.top_n }
    topHits = weeks.reduce(0) { $0 + $1.top_hits }
    topPts = weeks.reduce(0) { $0 + $1.top_points }
    topExp = weeks.reduce(0) { $0 + $1.top_expected_points }
  }
}

struct TrackRecordView: View {
  @Environment(\.supabaseClient) private var client
  @State private var data: TrackRecordData?
  @State private var error: String?

  private let coinFlip = log(2.0)

  var body: some View {
    ZStack {
      BoldTheme.Colors.bgPage.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Model track record\(data?.season.map { " · \($0) CFB" } ?? "")")
              .font(BoldTheme.Fonts.body(13, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
            Text("Track record").font(BoldTheme.Fonts.body(28, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
            Text("How our outright-upset model has actually done, graded after every game. The bigger the line, the less likely the dog wins outright, using the spread-to-win curve P(dog) = 1 − Φ(line / 13).")
              .font(BoldTheme.Fonts.body(13.5)).foregroundColor(BoldTheme.Colors.textDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let error {
            Text(error).font(BoldTheme.Fonts.body(14)).foregroundColor(BoldTheme.Role.lost)
          } else if let data {
            content(data)
          } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
          }
        }
        .padding(.horizontal, BoldTheme.Space.margin)
        .padding(.vertical, BoldTheme.Space.s4)
      }
    }
    .navigationTitle("Track record")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private func load() async {
    guard let client else { return }
    do {
      let season = (try? await ContextService(client: client).getCurrentContext(sport: "cfb").season) ?? Calendar.current.component(.year, from: Date())
      struct P: Encodable { let p_season: Int; let p_sport: String }
      let res = try await client.rpc("track_record", params: P(p_season: season, p_sport: "cfb")).execute()
      data = try JSONDecoder().decode(TrackRecordData.self, from: res.data)
    } catch {
      self.error = "Couldn't load the track record. Pull to try again later."
    }
  }

  @ViewBuilder private func content(_ d: TrackRecordData) -> some View {
    let t = TrackRecordTotals(d.weeks)
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
      kpi("Games graded", "\(t.games)", "Weeks 1–\(d.weeks.last.map { String($0.week) } ?? "–"), lined & final")
      kpi("Upsets vs expected", "\(t.upsets) / \(num(t.expected, 0))", "\(signed(Double(t.upsets) - t.expected)) vs model")
      kpi("Log loss per game", t.logLoss.map { num($0, 3) } ?? "–", "coin flip \(num(coinFlip, 3)) · lower is better")
      kpi("Top-12 dogs", "\(t.topHits)/\(t.topN)",
          "\(t.topN > 0 ? num(t.topPts / Double(t.topN), 2) : "–") pts/pick vs \(t.topN > 0 ? num(t.topExp / Double(t.topN), 2) : "–") expected", gold: true)
    }

    section("Upsets by week", sub: "Actual outright upsets vs the number the model expected before kickoff.") {
      table(headers: ["Wk", "Games", "Upsets", "Exp", "Diff", "Top 12"],
            rows: d.weeks.map { w in
              ["\(w.week)", "\(w.games)", "\(w.upsets)", num(w.expected, 1), signed(Double(w.upsets) - w.expected), "\(w.top_hits)/\(w.top_n)"]
            })
      Text("Top 12 = each week's 12 dogs with the most expected points (win chance × line). With the tier-adjusted curve the season's expected upsets would be \(num(t.expectedTier, 1)) instead of \(num(t.expected, 1)).")
        .font(BoldTheme.Fonts.body(11.5)).foregroundColor(BoldTheme.Colors.textDim)
        .fixedSize(horizontal: false, vertical: true)
    }

    section("Is the model calibrated?", sub: "Every graded game, bucketed by the dog's pre-game win chance. Calibrated means predicted and actual match.") {
      table(headers: ["Win chance", "Games", "Predicted", "Actual"],
            rows: d.calibration.map { b in
              ["\(jsNumber(b.lo))–\(jsNumber(b.hi))%", "\(b.n)", pct(b.predicted), pct(b.actual)]
            })
      Text("Fewer than ~100 games in a bucket is a small sample, so expect a few points of noise either way.")
        .font(BoldTheme.Fonts.body(11.5)).foregroundColor(BoldTheme.Colors.textDim)
    }

    section("What these numbers mean", sub: nil) {
      VStack(alignment: .leading, spacing: 6) {
        bullet("Graded, not back-fit. Win chances come straight from the line before kickoff.")
        bullet("Lines: closing line where we have it, else the latest we saw.")
        bullet("Small samples. One week is 50–150 games and a dozen upsets; weekly swings of ±4 are normal.")
        bullet("Completed weeks only. Week \(d.current_week.map(String.init) ?? "–") is in progress and isn't graded yet.")
      }
    }

    Text("Not betting advice. The game stays free; Pro is tools and info only.")
      .font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim)
  }

  // MARK: Bits

  private func num(_ v: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", v) }
  private func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + String(format: "%.1f", v) }
  private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }

  private func kpi(_ label: String, _ value: String, _ sub: String, gold: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(BoldTheme.Fonts.body(12, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
      Text(value).font(BoldTheme.Fonts.display(28)).foregroundColor(BoldTheme.Colors.text)
      Text(sub).font(BoldTheme.Fonts.body(12)).foregroundColor(BoldTheme.Colors.textDim).fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private func section<C: View>(_ title: String, sub: String?, @ViewBuilder content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(BoldTheme.Fonts.body(17, weight: .bold)).foregroundColor(BoldTheme.Colors.text)
      if let sub { Text(sub).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.textDim).fixedSize(horizontal: false, vertical: true) }
      content()
    }
    .padding(BoldTheme.Space.cardPad)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: BoldTheme.Radius.card, style: .continuous).fill(BoldTheme.Colors.card))
  }

  private func table(headers: [String], rows: [[String]]) -> some View {
    VStack(spacing: 0) {
      HStack {
        ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
          Text(h).frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
        }
      }
      .font(BoldTheme.Fonts.body(12, weight: .semibold)).foregroundColor(BoldTheme.Colors.textDim)
      .padding(.vertical, 6)
      ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
        Divider().overlay(BoldTheme.Colors.border)
        HStack {
          ForEach(Array(r.enumerated()), id: \.offset) { i, c in
            Text(c).frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
          }
        }
        .font(BoldTheme.Fonts.mono(11.5)).foregroundColor(BoldTheme.Colors.text)
        .padding(.vertical, 6)
      }
    }
  }

  private func bullet(_ s: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text("•").foregroundColor(BoldTheme.Colors.textDim)
      Text(s).font(BoldTheme.Fonts.body(13)).foregroundColor(BoldTheme.Colors.text).fixedSize(horizontal: false, vertical: true)
    }
  }
}
