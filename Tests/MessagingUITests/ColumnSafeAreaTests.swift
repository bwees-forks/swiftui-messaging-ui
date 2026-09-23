import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

/// Cells track the collection view's horizontal safe-area column. The content
/// width stays the collection bounds, and a later horizontal inset leaves the
/// vertical offset where the reader left it.
@MainActor
final class ColumnSafeAreaTests: XCTestCase {

  private struct Msg: Identifiable, Equatable {
    let id: Int
  }

  private struct MsgCell: View {
    let height: CGFloat
    var body: some View {
      Color.clear.frame(height: height)
    }
  }

  private typealias HostView = TiledUIView<Msg, MsgCell, Never, Never, Never, Never, Void>

  private let viewport = CGSize(width: 320, height: 600)
  private let cellHeight: CGFloat = 100
  private let itemCount = 40
  private let tolerance: CGFloat = 1
  private let leftInset: CGFloat = 72
  private let rightInset: CGFloat = 40
  private let scrollAway: CGFloat = 400

  private var windows: [UIWindow] = []

  override func tearDown() {
    for window in windows { window.isHidden = true }
    windows.removeAll()
    super.tearDown()
  }

  func test_horizontalInsets_cellTracksSafeAreaLayoutFrame() {
    let view = mount(left: leftInset, right: rightInset)

    assertColumn(view, left: leftInset, right: rightInset)
  }

  func test_zeroHorizontalInset_cellUsesFullBoundsWidth() {
    let view = mount(left: 0, right: 0)

    assertColumn(view, left: 0, right: 0)
    let collection = view.test_collectionView
    let cell = view.test_messageFrame(at: 0)!
    XCTAssertEqual(
      cell.width, collection.bounds.width, accuracy: tolerance,
      "zero inset shrank the cell below the bounds"
    )
  }

  func test_horizontalInsetChange_keepsContentOffsetY() {
    let controller = UIViewController()
    let view = mount(left: 0, right: 0, controller: controller)
    assertColumn(view, left: 0, right: 0)

    let collection = view.test_collectionView
    collection.setContentOffset(
      CGPoint(x: collection.contentOffset.x, y: collection.contentOffset.y - scrollAway),
      animated: false
    )
    pump(view)

    let offsetBefore = view.test_contentOffsetY
    let rowBefore = view.test_messageFrame(at: itemCount / 2)!.minY

    controller.additionalSafeAreaInsets.left = leftInset
    pump(view)

    XCTAssertEqual(
      view.test_contentOffsetY, offsetBefore, accuracy: tolerance,
      "offset moved from \(offsetBefore) to \(view.test_contentOffsetY)"
    )
    XCTAssertEqual(
      view.test_messageFrame(at: itemCount / 2)!.minY, rowBefore, accuracy: tolerance,
      "row y moved when the horizontal inset changed"
    )
    assertColumn(view, left: leftInset, right: 0)
  }

  // MARK: - Host

  @discardableResult
  private func mount(
    left: CGFloat,
    right: CGFloat,
    controller: UIViewController = UIViewController()
  ) -> HostView {
    let height = cellHeight
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { _, _, _ in MsgCell(height: height) }
    )
    view.scrollsToBottomOnReplace = true
    view.translatesAutoresizingMaskIntoConstraints = false

    controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
    controller.view.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: controller.view.topAnchor),
      view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      view.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
    ])

    let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    windows.append(window)
    window.layoutIfNeeded()

    view.applyItems((0..<itemCount).map { Msg(id: $0) })
    pump(view)
    return view
  }

  private func pump(_ view: HostView, iterations: Int = 4, interval: TimeInterval = 0.02) {
    for _ in 0..<iterations {
      view.window?.setNeedsLayout()
      view.window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
  }

  private func assertColumn(
    _ view: HostView,
    left: CGFloat,
    right: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let collection = view.test_collectionView
    let guide = collection.safeAreaLayoutGuide.layoutFrame
    let bounds = collection.bounds
    let cell = view.test_messageFrame(at: 0)
    let detail = "cell=\(String(describing: cell)) guide=\(guide) bounds=\(bounds) insets=\(collection.safeAreaInsets)"

    XCTAssertNotNil(cell, "missing cell frame. \(detail)", file: file, line: line)
    guard let cell else { return }

    XCTAssertEqual(guide.minX, left, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(bounds.width - guide.maxX, right, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(cell.minX, guide.minX, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(cell.maxX, guide.maxX, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(cell.width, guide.width, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(cell.height, cellHeight, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(
      collection.contentSize.width, bounds.width, accuracy: tolerance,
      "content width \(detail)", file: file, line: line
    )
    XCTAssertEqual(collection.contentOffset.x, 0, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(collection.contentInset.left, 0, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(collection.contentInset.right, 0, accuracy: tolerance, detail, file: file, line: line)
    XCTAssertEqual(
      collection.contentInsetAdjustmentBehavior, .never,
      detail, file: file, line: line
    )
  }
}
