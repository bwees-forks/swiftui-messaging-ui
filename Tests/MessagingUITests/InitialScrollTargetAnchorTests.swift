import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

/// Hosted tests for the initial-scroll-target anchor window. Each test mounts a
/// real `TiledUIView` in a `UIWindow`, positions an initial target, and drives
/// the real self-sizing / append / release paths, asserting the anchored target
/// holds its on-screen position (`frame.minY - contentOffset.y`) through late
/// height reports that the pure `selfSizingContentOffsetAdjustment` heuristic
/// alone would drift.
@MainActor
final class InitialScrollTargetAnchorTests: XCTestCase {

  // MARK: - Fixtures

  private struct Msg: Identifiable, Equatable {
    let id: Int
    var height: CGFloat
  }

  private struct MsgCell: View {
    let height: CGFloat
    var body: some View {
      Color.clear.frame(height: height)
    }
  }

  private typealias HostView = TiledUIView<Msg, MsgCell, Never, Never, Never, Never, Void>

  private let viewport = CGSize(width: 320, height: 600)
  private let tolerance: CGFloat = 1.0

  /// Keeps windows alive for the duration of a test so the hosted view stays mounted.
  private var windows: [UIWindow] = []

  override func tearDown() {
    for window in windows { window.isHidden = true }
    windows.removeAll()
    super.tearDown()
  }

  private func makeMessages(count: Int, height: CGFloat = 100) -> [Msg] {
    (0..<count).map { Msg(id: $0, height: height) }
  }

  private func mount(
    items: [Msg],
    targetID: Int?,
    anchor: UnitPoint,
    holdUntilUserScroll: Bool = true,
    autoScrollsToBottomOnAppend: Bool = false
  ) -> HostView {
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { msg, _, _ in MsgCell(height: msg.height) }
    )
    let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
    view.frame = window.bounds
    window.addSubview(view)
    window.makeKeyAndVisible()
    windows.append(window)

    view.scrollsToBottomOnReplace = true
    view.autoScrollsToBottomOnAppend = autoScrollsToBottomOnAppend
    if let targetID {
      view.initialScrollTarget = TiledInitialScrollTarget(
        id: AnyHashable(targetID),
        anchor: anchor,
        holdUntilUserScroll: holdUntilUserScroll
      )
    }
    view.applyItems(items)
    pump(view)
    return view
  }

  /// Spins the run loop and forces layout so deferred positioning and async
  /// batch-update completions settle.
  private func pump(_ view: HostView, iterations: Int = 6, interval: TimeInterval = 0.02) {
    for _ in 0..<iterations {
      view.window?.setNeedsLayout()
      view.window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }
  }

  /// Spins the run loop until `condition` holds, exiting as soon as the animated
  /// settle is observed rather than after a fixed wall-clock iteration count. The
  /// generous timeout is a ceiling so a stalled animation fails instead of hangs.
  @discardableResult
  private func pump(
    _ view: HostView,
    until condition: () -> Bool,
    timeout: TimeInterval = 5
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      view.window?.setNeedsLayout()
      view.window?.layoutIfNeeded()
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
  }

  /// On-screen distance from the viewport top to the message's top edge.
  private func gap(_ view: HostView, messageAt index: Int) -> CGFloat {
    guard let frame = view.test_messageFrame(at: index) else {
      XCTFail("no frame for message \(index)")
      return .nan
    }
    return frame.minY - view.test_contentOffsetY
  }

  // MARK: - Straddling-cell growth above the target

  func test_straddlingCellGrowthAboveTarget_targetHoldsPosition() {
    let view = mount(items: makeMessages(count: 20), targetID: 10, anchor: .center)
    XCTAssertTrue(view.isInitialAnchorActive, "anchor window should arm after positioning")

    // The cell at index 7 straddles the viewport top: its top edge is above the
    // top edge and its bottom edge is below it. This is the branch the pure
    // heuristic leaves uncompensated (resizedItemBottom > viewportTop, not near
    // bottom), which drifts the one-shot target.
    let viewportTop = view.test_contentOffsetY
    let straddler = view.test_messageFrame(at: 7)!
    XCTAssertGreaterThan(straddler.maxY, viewportTop, "straddler bottom is below the viewport top")
    XCTAssertLessThan(straddler.minY, viewportTop, "straddler top is above the viewport top")

    let gapBefore = gap(view, messageAt: 10)
    let adjustment = view.test_growMessage(at: 7, by: 120)
    let gapAfter = gap(view, messageAt: 10)

    XCTAssertEqual(adjustment, 120, accuracy: tolerance, "above-target growth shifts the offset by the full delta")
    XCTAssertEqual(gapAfter, gapBefore, accuracy: tolerance, "target holds its on-screen position")
  }

  // MARK: - Cumulative above-target growth

  func test_cumulativeAboveTargetGrowth_noNetDrift() {
    let view = mount(items: makeMessages(count: 20), targetID: 10, anchor: .center)
    let gapBefore = gap(view, messageAt: 10)

    view.test_growMessage(at: 7, by: 40)
    view.test_growMessage(at: 8, by: 60)
    let gapAfter = gap(view, messageAt: 10)

    XCTAssertEqual(gapAfter, gapBefore, accuracy: tolerance, "cumulative above-target growth does not compound drift")
  }

  // MARK: - Shallow backlog clamp + below-target growth

  func test_shallowBacklogClamp_belowTargetGrowth_targetStaysVisible() {
    // Target near the tail with little content below it, so the top-anchored
    // offset clamps to the bottom pin and the resting position reads as at-bottom.
    let view = mount(items: makeMessages(count: 20), targetID: 17, anchor: .top)
    XCTAssertTrue(view.isInitialAnchorActive)
    XCTAssertLessThan(view.test_pointsFromBottom, 100, "clamped resting position reads near-bottom")

    let gapBefore = gap(view, messageAt: 17)
    XCTAssertGreaterThan(gapBefore, 0, "target sits below the viewport top after the clamp")
    XCTAssertLessThan(gapBefore, viewport.height, "target is visible")

    // A below-target cell grows large. The near-bottom heuristic would ride the
    // offset to the bottom and scroll the target off the top; the anchor window
    // ignores below-target growth instead.
    let adjustment = view.test_growMessage(at: 19, by: 600)
    let gapAfter = gap(view, messageAt: 17)

    XCTAssertEqual(adjustment, 0, accuracy: tolerance, "below-target growth does not move the offset")
    XCTAssertEqual(gapAfter, gapBefore, accuracy: tolerance, "target stays stationary")
    XCTAssertLessThan(gapAfter, viewport.height, "target remains visible")
  }

  // MARK: - Append auto-follow gate

  func test_appendWhileAnchored_doesNotFollowToBottom_thenFollowsAfterRelease() {
    let view = mount(
      items: makeMessages(count: 20),
      targetID: 10,
      anchor: .center,
      autoScrollsToBottomOnAppend: true
    )
    XCTAssertTrue(view.isInitialAnchorActive)

    let gapBefore = gap(view, messageAt: 10)

    var items = makeMessages(count: 20)
    items.append(Msg(id: 20, height: 100))
    view.applyItems(items)
    pump(view)

    XCTAssertEqual(gap(view, messageAt: 10), gapBefore, accuracy: tolerance, "append must not yank the anchored target")
    XCTAssertGreaterThan(view.test_pointsFromBottom, 100, "still held at the divider, not scrolled to the bottom")

    // A user drag releases the window; the next append follows to the bottom.
    view.test_beginUserDrag()
    XCTAssertFalse(view.isInitialAnchorActive, "user drag releases the anchor window")

    items.append(Msg(id: 21, height: 100))
    view.applyItems(items)

    XCTAssertTrue(
      pump(view, until: { view.test_pointsFromBottom < 40 }),
      "append after release follows to the bottom"
    )
  }

  // MARK: - Release on programmatic scroll

  func test_programmaticScrollReleasesWindow_noRepinAfterward() {
    let view = mount(items: makeMessages(count: 20), targetID: 10, anchor: .center)
    XCTAssertTrue(view.isInitialAnchorActive)

    var position = TiledScrollPosition()
    position.scrollTo(edge: .bottom, animated: false)
    view.applyScrollPosition(position)
    pump(view)

    XCTAssertFalse(view.isInitialAnchorActive, "an explicit scroll command releases the window")

    // With the window released and the list pinned at the bottom, a growing tail
    // cell (below the former target) follows the growth via the settled-list
    // near-bottom heuristic — the anchored path (which would return 0) is gone.
    let adjustment = view.test_growMessage(at: 19, by: 100)
    XCTAssertEqual(adjustment, 100, accuracy: tolerance, "settled heuristic follows near-bottom growth after release")
  }

  // MARK: - Kill switch

  func test_killSwitchOff_revertsToOneShotDrift() {
    let view = mount(
      items: makeMessages(count: 20),
      targetID: 10,
      anchor: .center,
      holdUntilUserScroll: false
    )
    XCTAssertFalse(view.isInitialAnchorActive, "anchoring disabled: window never arms")

    let viewportTop = view.test_contentOffsetY
    let straddler = view.test_messageFrame(at: 7)!
    XCTAssertGreaterThan(straddler.maxY, viewportTop)
    XCTAssertLessThan(straddler.minY, viewportTop)

    let gapBefore = gap(view, messageAt: 10)
    let adjustment = view.test_growMessage(at: 7, by: 120)
    let gapAfter = gap(view, messageAt: 10)

    XCTAssertEqual(adjustment, 0, accuracy: tolerance, "one-shot heuristic does not compensate straddling growth")
    XCTAssertEqual(gapAfter - gapBefore, 120, accuracy: tolerance, "target drifts by the full delta when anchoring is off")
  }

  // MARK: - Edge cases

  func test_targetIDReResolvesAfterPrependShiftsIndices() {
    let view = mount(items: makeMessages(count: 20), targetID: 10, anchor: .center)
    XCTAssertTrue(view.isInitialAnchorActive)

    let gapBefore = gap(view, messageAt: 10)

    // Prepend five older messages: id 10 moves from index 10 to index 15, and old
    // id 9 moves to index 14 (still above the target).
    var items = (100..<105).map { Msg(id: $0, height: 100) }
    items.append(contentsOf: makeMessages(count: 20))
    view.applyItems(items)
    pump(view)

    XCTAssertTrue(view.isInitialAnchorActive, "prepend does not release the window")
    let gapAfterPrepend = gap(view, messageAt: 15)
    XCTAssertEqual(gapAfterPrepend, gapBefore, accuracy: tolerance, "prepend preserves the target's on-screen position")

    // Grow the cell now at index 14 (old id 9, above the re-resolved target).
    view.test_growMessage(at: 14, by: 120)
    XCTAssertEqual(gap(view, messageAt: 15), gapBefore, accuracy: tolerance, "re-resolved target holds after prepend + growth")
  }

  func test_targetOwnGrowth_scalesByAnchorFraction() {
    let cases: [(UnitPoint, CGFloat)] = [(.top, 0), (.center, 50), (.bottom, 100)]
    for (anchor, expected) in cases {
      let view = mount(items: makeMessages(count: 20), targetID: 10, anchor: anchor)
      let adjustment = view.test_growMessage(at: 10, by: 100)
      XCTAssertEqual(adjustment, expected, accuracy: tolerance, "target's own growth shifts by anchor.y * delta (\(anchor))")
    }
  }

  func test_belowTargetGrowth_isIgnoredWhileAnchored() {
    let view = mount(items: makeMessages(count: 20), targetID: 10, anchor: .center)
    let gapBefore = gap(view, messageAt: 10)
    let adjustment = view.test_growMessage(at: 15, by: 200)
    XCTAssertEqual(adjustment, 0, accuracy: tolerance, "below-target growth is ignored")
    XCTAssertEqual(gap(view, messageAt: 10), gapBefore, accuracy: tolerance, "target unaffected by below-target growth")
  }
}
