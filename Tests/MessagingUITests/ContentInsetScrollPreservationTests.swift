import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

@MainActor
final class ContentInsetScrollPreservationTests: XCTestCase {

  private struct Msg: Identifiable, Equatable {
    let id: Int
  }

  private struct MsgCell: View {
    let height: CGFloat

    var body: some View {
      Color.clear.frame(height: height)
    }
  }

  private enum Metrics {
    static let viewport = CGSize(width: 320, height: 600)
    static let rowHeight: CGFloat = 100
    static let rowCount = 40
    static let historyRow = 10
    static let topInset: CGFloat = 40
    static let keyboardInset: CGFloat = 360
    static let composerInset: CGFloat = 80
    static let changedTopInset: CGFloat = 90
    static let scrollStep: CGFloat = 24
    static let bottomReadingGap: CGFloat = 36
    static let tolerance: CGFloat = 1
    static let insetSamples: [CGFloat] = [300, 240, 160, composerInset]
  }

  private typealias HostView = TiledUIView<Msg, MsgCell, Never, Never, Never, Never, Void>
  private var windows: [UIWindow] = []

  override func tearDown() async throws {
    await MainActor.run {
      for window in windows { window.isHidden = true }
      windows.removeAll()
    }
    try await super.tearDown()
  }

  func test_idleHistoryKeepsVisibleRowWhileKeyboardLowers() throws {
    let view = mount(targetID: Metrics.historyRow)
    let initialGap = try screenY(of: Metrics.historyRow, in: view)

    for inset in Metrics.insetSamples {
      setInsets(view, bottom: inset)
      XCTAssertEqual(
        try screenY(of: Metrics.historyRow, in: view), initialGap,
        accuracy: Metrics.tolerance,
        "Changing the keyboard reservation moved the reader's history row"
      )
    }
  }

  func test_idleHistoryKeepsVisibleRowWhileKeyboardRises() throws {
    let view = mount(targetID: Metrics.historyRow, bottomInset: Metrics.composerInset)
    let initialGap = try screenY(of: Metrics.historyRow, in: view)

    setInsets(view, bottom: Metrics.keyboardInset)

    XCTAssertEqual(
      try screenY(of: Metrics.historyRow, in: view), initialGap,
      accuracy: Metrics.tolerance
    )
  }

  func test_idleBottomKeepsDistanceWhileKeyboardLowers() {
    let view = mount(targetID: nil)
    view.test_collectionView.contentOffset.y -= Metrics.bottomReadingGap
    let initialDistance = view.test_pointsFromBottom
    XCTAssertEqual(initialDistance, Metrics.bottomReadingGap, accuracy: Metrics.tolerance)

    for inset in Metrics.insetSamples {
      setInsets(view, bottom: inset)
      XCTAssertEqual(view.test_pointsFromBottom, initialDistance, accuracy: Metrics.tolerance)
    }
  }

  func test_heldInitialAnchorTracksInsetsAndReportsActualGeometry() throws {
    let view = mount(targetID: Metrics.historyRow, holdAnchor: true)
    var latestGeometry: TiledScrollGeometry?
    view.onTiledScrollGeometryChange = { latestGeometry = $0 }

    for bottomInset in [Metrics.keyboardInset, Metrics.composerInset] {
      XCTAssertTrue(view.isInitialAnchorActive)
      setInsets(view, top: Metrics.changedTopInset, bottom: bottomInset)

      XCTAssertEqual(
        try screenY(of: Metrics.historyRow, in: view), Metrics.changedTopInset,
        accuracy: Metrics.tolerance
      )
      let geometry = try XCTUnwrap(latestGeometry)
      XCTAssertEqual(geometry.contentOffset.y, view.test_contentOffsetY, accuracy: Metrics.tolerance)
      XCTAssertEqual(geometry.contentInset, view.test_collectionView.adjustedContentInset)
    }
  }

  func test_draggingHistoryKeepsUserMotionWhileKeyboardLowers() throws {
    let view = mount(targetID: Metrics.historyRow, holdAnchor: true)
    view.scrollViewWillBeginDragging(view.test_collectionView)
    XCTAssertFalse(view.isInitialAnchorActive)

    try assertUserScrollSurvivesInsetChanges(view)
  }

  func test_deceleratingHistoryKeepsUserMotionWhileKeyboardLowers() throws {
    let view = mount(targetID: Metrics.historyRow, holdAnchor: true)
    view.scrollViewWillBeginDragging(view.test_collectionView)
    view.scrollViewDidEndDragging(view.test_collectionView, willDecelerate: true)

    try assertUserScrollSurvivesInsetChanges(view)
  }

  func test_nativeInteractionTakesPriorityOverHeldAnchorOnEitherInsetEdge() throws {
    let interactions = [
      (isTracking: true, isDragging: false, isDecelerating: false),
      (isTracking: false, isDragging: true, isDecelerating: false),
      (isTracking: false, isDragging: false, isDecelerating: true),
    ]
    for interaction in interactions {
      for changesTop in [true, false] {
        let view = mount(targetID: Metrics.historyRow, holdAnchor: true)
        view.test_scrollInteraction = interaction
        let expectedGap = try screenY(of: Metrics.historyRow, in: view)
        XCTAssertTrue(view.isInitialAnchorActive)

        setInsets(
          view,
          top: changesTop ? Metrics.changedTopInset : Metrics.topInset,
          bottom: changesTop ? Metrics.keyboardInset : Metrics.composerInset
        )

        XCTAssertEqual(
          try screenY(of: Metrics.historyRow, in: view), expectedGap,
          accuracy: Metrics.tolerance,
          "Native scroll interaction must take priority over the initial anchor: \(interaction)"
        )
      }
    }
  }

  private func assertUserScrollSurvivesInsetChanges(_ view: HostView) throws {
    let collection = view.test_collectionView
    collection.contentOffset.y -= Metrics.scrollStep
    let expectedGap = try screenY(of: Metrics.historyRow, in: view)
    setInsets(view, top: Metrics.changedTopInset, bottom: Metrics.keyboardInset)
    XCTAssertEqual(
      try screenY(of: Metrics.historyRow, in: view), expectedGap,
      accuracy: Metrics.tolerance,
      "A top-inset update added movement to the user's scroll"
    )

    for inset in Metrics.insetSamples {
      collection.contentOffset.y -= Metrics.scrollStep
      let expectedGap = try screenY(of: Metrics.historyRow, in: view)

      setInsets(view, bottom: inset)

      XCTAssertEqual(
        try screenY(of: Metrics.historyRow, in: view), expectedGap,
        accuracy: Metrics.tolerance,
        "An inset update added movement to the user's scroll"
      )
    }
  }

  private func mount(
    targetID: Int?,
    bottomInset: CGFloat = Metrics.keyboardInset,
    holdAnchor: Bool = false
  ) -> HostView {
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { _, _, _ in MsgCell(height: Metrics.rowHeight) }
    )
    let window = UIWindow(frame: CGRect(origin: .zero, size: Metrics.viewport))
    view.frame = window.bounds
    window.addSubview(view)
    window.makeKeyAndVisible()
    windows.append(window)
    view.scrollsToBottomOnReplace = true
    view.swiftUIWorldSafeAreaInset = EdgeInsets(
      top: Metrics.topInset, leading: 0, bottom: bottomInset, trailing: 0
    )
    if let targetID {
      view.initialScrollTarget = TiledInitialScrollTarget(
        id: AnyHashable(targetID), anchor: .top, holdUntilUserScroll: holdAnchor
      )
    }
    view.applyItems((0..<Metrics.rowCount).map { Msg(id: $0) })
    pump(view)
    return view
  }

  private func setInsets(_ view: HostView, top: CGFloat = Metrics.topInset, bottom: CGFloat) {
    view.swiftUIWorldSafeAreaInset = EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    pump(view)
  }

  private func screenY(of row: Int, in view: HostView) throws -> CGFloat {
    let frame = try XCTUnwrap(view.test_messageFrame(at: row))
    return frame.minY - view.test_contentOffsetY
  }

  private func pump(_ view: HostView) {
    for _ in 0..<6 {
      view.window?.setNeedsLayout()
      view.window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
  }
}
