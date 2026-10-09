import UIKit

final class TiledCollectionView: UICollectionView {
  var onBoundsSizeWillChange: (() -> Void)?

  override var bounds: CGRect {
    willSet {
      guard bounds.size != newValue.size else { return }
      onBoundsSizeWillChange?()
    }
  }
}
