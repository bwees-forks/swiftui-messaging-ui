import XCTest
@testable import MessagingUI

/// Covers the content-offset compensation applied when a message bubble
/// self-sizes after async content (link preview, image) resolves. The bug this
/// guards against: without compensation the bubble grows top-fixed and pushes
/// the newest message past the bottom of the screen instead of staying pinned.
final class SelfSizingContentOffsetTests: XCTestCase {

  private func adjustment(
    heightDiff: CGFloat,
    resizedItemBottom: CGFloat,
    viewportTop: CGFloat,
    nearBottom: Bool
  ) -> CGFloat {
    TiledCollectionViewLayout.selfSizingContentOffsetAdjustment(
      heightDiff: heightDiff,
      resizedItemBottom: resizedItemBottom,
      viewportTop: viewportTop,
      nearBottom: nearBottom
    )
  }

  // MARK: - Pinned to the bottom

  func test_nearBottom_growing_followsGrowthToStayPinned() {
    // Last bubble grows by 120pt while pinned at the bottom: follow it so the
    // bottom stays put and older content flows up off the top.
    let result = adjustment(heightDiff: 120, resizedItemBottom: 900, viewportTop: 500, nearBottom: true)
    XCTAssertEqual(result, 120)
  }

  func test_nearBottom_shrinking_followsGrowthToStayPinned() {
    let result = adjustment(heightDiff: -80, resizedItemBottom: 900, viewportTop: 500, nearBottom: true)
    XCTAssertEqual(result, -80)
  }

  func test_nearBottom_takesPriorityOverViewportPosition() {
    // Even when the resized bubble is below the viewport top, being near the
    // bottom pins the bottom.
    let result = adjustment(heightDiff: 200, resizedItemBottom: 700, viewportTop: 400, nearBottom: true)
    XCTAssertEqual(result, 200)
  }

  // MARK: - Scrolled up in history

  func test_scrolledUp_resizeAboveViewport_shiftsToKeepReadingPositionStable() {
    // Bubble entirely above the viewport (bottom edge above viewportTop) grows:
    // shift by the delta so the reading position does not jump.
    let result = adjustment(heightDiff: 90, resizedItemBottom: 300, viewportTop: 500, nearBottom: false)
    XCTAssertEqual(result, 90)
  }

  func test_scrolledUp_resizeAtViewportTopEdge_shifts() {
    // Old bottom exactly at the viewport top counts as "above": still shift.
    let result = adjustment(heightDiff: 40, resizedItemBottom: 500, viewportTop: 500, nearBottom: false)
    XCTAssertEqual(result, 40)
  }

  func test_scrolledUp_resizeWithinViewport_growsInPlace() {
    // Bubble visible in the middle grows: keep the top anchored, let it push
    // content below it down. No offset change.
    let result = adjustment(heightDiff: 150, resizedItemBottom: 600, viewportTop: 500, nearBottom: false)
    XCTAssertEqual(result, 0)
  }

  func test_scrolledUp_resizeBelowViewport_growsInPlace() {
    let result = adjustment(heightDiff: 150, resizedItemBottom: 1200, viewportTop: 500, nearBottom: false)
    XCTAssertEqual(result, 0)
  }
}
