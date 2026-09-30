import SwiftUI

extension View {
  /// iOS 26 blurs/fades content at a scroll view's top edge ("scroll edge
  /// effect"). On lists with opaque pinned section headers (Games' day
  /// headers) that makes the pinned header itself fade out mid-scroll.
  /// Hide it there; no-op before iOS 26.
  @ViewBuilder
  func hardTopScrollEdge() -> some View {
    if #available(iOS 26.0, *) {
      self.scrollEdgeEffectHidden(true, for: .top)
    } else {
      self
    }
  }
}
