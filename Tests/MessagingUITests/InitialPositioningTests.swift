import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

/// These tests check that initial positioning sets the resting offset before
/// cells lay out. The first snapshot then configures each resting cell once and
/// never configures a cell from the pre-scroll viewport.
@MainActor
final class InitialPositioningTests: XCTestCase {

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
  private let tolerance: CGFloat = 1.0

  /// Allow four cells above the resting viewport, covering prefetching and the
  /// cell that straddles the viewport top.
  private let slack = 4

  private var visibleCells: Int {
    Int((viewport.height / cellHeight).rounded(.up))
  }

  private var windows: [UIWindow] = []

  override func tearDown() {
    for window in windows { window.isHidden = true }
    windows.removeAll()
    super.tearDown()
  }

  private func mount(
    count: Int,
    target: TiledInitialScrollTarget? = nil,
    startsAtZeroWidth: Bool = false
  ) -> HostView {
    let height = cellHeight
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { _, _, _ in MsgCell(height: height) }
    )
    let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
    window.makeKeyAndVisible()
    windows.append(window)

    view.scrollsToBottomOnReplace = true
    view.initialScrollTarget = target

    let items = (0..<count).map { Msg(id: $0) }
    if startsAtZeroWidth {
      // Items reach the view at width 0 and before it joins the hierarchy, so
      // the layout stores height estimates and positioning waits for the first
      // layout pass. Adding the view to the window supplies that pass at the
      // real width, which is where the heights are recalculated.
      view.frame = CGRect(x: 0, y: 0, width: 0, height: viewport.height)
      view.applyItems(items)
      view.test_configuredIndexPaths = []
      view.frame = window.bounds
      window.addSubview(view)
    } else {
      view.frame = window.bounds
      window.addSubview(view)
      view.test_configuredIndexPaths = []
      view.applyItems(items)
    }
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

  private func configuredMessages(_ view: HostView) -> [Int] {
    let section = TiledCollectionViewLayout.DisplaySection.messages.rawValue
    return (view.test_configuredIndexPaths ?? []).filter { $0.section == section }.map(\.item)
  }

  /// Assert that the view configured each resting cell exactly once and
  /// configured no cell from outside the resting viewport. The minimum-index
  /// check alone would pass when a cell is configured twice at the same offset,
  /// so the uniqueness and count checks cover that case.
  private func assertLaidOutOnce(
    _ view: HostView,
    topItem: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let items = configuredMessages(view)
    XCTAssertFalse(items.isEmpty, "no cells were configured", file: file, line: line)
    XCTAssertEqual(
      items.count, Set(items).count,
      "some cells were configured more than once in \(items)", file: file, line: line
    )
    XCTAssertGreaterThanOrEqual(
      items.min() ?? 0, topItem - slack,
      "cells were configured above the resting viewport", file: file, line: line
    )
    XCTAssertLessThanOrEqual(
      items.count, visibleCells + slack,
      "more cells were configured than one resting viewport holds", file: file, line: line
    )
  }

  func test_bottomPin_laysOutRestingCellsOnce() {
    let count = 40
    let view = mount(count: count)

    XCTAssertEqual(view.test_pointsFromBottom, 0, accuracy: tolerance, "rests at the bottom")
    assertLaidOutOnce(view, topItem: count - visibleCells)
  }

  func test_initialTarget_laysOutRestingCellsOnce() {
    let count = 40
    let targetItem = 25
    let target = TiledInitialScrollTarget(
      id: AnyHashable(targetItem), anchor: .center, holdUntilUserScroll: true
    )
    let view = mount(count: count, target: target)

    let frame = view.test_messageFrame(at: targetItem)!
    let mid = view.test_contentOffsetY + viewport.height / 2
    XCTAssertEqual(frame.midY, mid, accuracy: tolerance, "target rests at the center")

    // A centered target leaves half a viewport above it.
    assertLaidOutOnce(view, topItem: targetItem - visibleCells / 2)
  }

  /// Drive the mount where items arrive before bounds do. Positioning then runs
  /// against height estimates recorded at width 0, which the pre-sized mounts
  /// above never produce.
  func test_bottomPin_fromZeroWidth_laysOutRestingCellsOnce() {
    let count = 40
    let view = mount(count: count, startsAtZeroWidth: true)

    XCTAssertEqual(view.test_pointsFromBottom, 0, accuracy: tolerance, "rests at the bottom")
    assertLaidOutOnce(view, topItem: count - visibleCells)
  }

  func test_initialTarget_fromZeroWidth_laysOutRestingCellsOnce() {
    let count = 40
    let targetItem = 25
    let target = TiledInitialScrollTarget(
      id: AnyHashable(targetItem), anchor: .center, holdUntilUserScroll: true
    )
    let view = mount(count: count, target: target, startsAtZeroWidth: true)

    let frame = view.test_messageFrame(at: targetItem)!
    let mid = view.test_contentOffsetY + viewport.height / 2
    XCTAssertEqual(frame.midY, mid, accuracy: tolerance, "target rests at the center")

    assertLaidOutOnce(view, topItem: targetItem - visibleCells / 2)
  }
}
