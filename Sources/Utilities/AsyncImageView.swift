import SwiftUI

struct AsyncImageView: View {
  let urlString: String?
  let width: CGFloat?
  let height: CGFloat?

  var body: some View {
    if let urlString, let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .empty:
          ProgressView().frame(width: width, height: height)
        case .success(let image):
          image.resizable().scaledToFit().frame(width: width, height: height)
        case .failure:
          placeholder
        @unknown default:
          placeholder
        }
      }
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)).frame(width: width, height: height)
  }
}

