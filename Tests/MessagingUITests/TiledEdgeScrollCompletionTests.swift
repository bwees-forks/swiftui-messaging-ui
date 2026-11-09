import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

@MainActor
final class TiledEdgeScrollCompletionTests: XCTestCase {

  private struct Msg: Identifiable, Equatable {
    let id: Int
  }

  private struct MsgCell: View {
    var body: some View {
      Color.clear.frame(height: Metrics.rowHeight)
    }
  }

  private enum Metrics {
    static let viewport = CGSize(width: 320, height: 600)
    static let rowHeight: CGFloat = 100
    static let rowCount = 40
    static let tolerance: CGFloat = 1
    static let timeout: TimeInterval = 2
    static let pumpInterval: TimeInterval = 0.02
  }

  private typealias HostView = TiledUIView<Msg, MsgCell, Never, Never, Never, Never, Void>

  private var windows: [UIWindow] = []
  private var position = TiledScrollPosition()
  private var events: [TiledEdgeScrollCompletion<Int>] = []

  override func tearDown() async throws {
    await MainActor.run {
      for window in windows { window.isHidden = true }
      windows.removeAll()
      events.removeAll()
    }
    try await super.tearDown()
  }

  func test_edgeScrollCompletesOnce_immediate() {
    assertEdgeScrollCompletesOnce(animated: false)
  }

  func test_edgeScrollCompletesOnce_animated() {
    assertEdgeScrollCompletesOnce(animated: true)
  }

  func test_supersedingEdgeCancelsTheConsumedCommand() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1200
    let first = beginAnimatedBottom(view)

    scroll(view, edge: .top, animated: false)

    XCTAssertTrue(pump(view) { events.contains { $0.version == first } })
    let match = events.filter { $0.version == first }
    XCTAssertEqual(match.count, 1)
    XCTAssertEqual(match.first?.finished, false)
    XCTAssertNil(match.first?.itemID)
  }

  func test_missingItemCancelsTheConsumedCommand() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1200
    let first = beginAnimatedBottom(view)

    position.scrollTo(id: Metrics.rowCount + 10)
    view.applyScrollPosition(position)

    XCTAssertTrue(pump(view) { events.contains { $0.version == first } })
    let match = events.filter { $0.version == first }
    XCTAssertEqual(match.count, 1)
    XCTAssertEqual(match.first?.finished, false)
    XCTAssertNil(match.first?.itemID)
  }

  func test_completionCapturesItsCallback_andReentrantCommandSurvives() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1000
    var generations: [Int] = []
    var onCompletion: (() -> Void)?
    func install(_ generation: Int) {
      view.onTiledEdgeScrollCompletion = { completion in
        self.events.append(completion)
        generations.append(generation)
        let followUp = onCompletion
        onCompletion = nil
        followUp?()
      }
    }

    install(0)
    _ = beginAnimatedBottom(view)
    install(1)
    onCompletion = { _ = self.scroll(view, edge: .top, animated: false) }

    XCTAssertTrue(pump(view) { events.count == 2 })
    XCTAssertEqual(generations, [0, 1])
    XCTAssertEqual(events[0].finished, true)
    XCTAssertEqual(events[1].finished, true)
    XCTAssertEqual(events[1].itemID, 0)
    XCTAssertGreaterThan(events[1].version, events[0].version)
  }

  func test_dismantlingCancelsAnInFlightAnimation() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1200
    _ = beginAnimatedBottom(view)

    view.dismantle()

    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.finished, false)
    XCTAssertNil(events.first?.itemID)
    pump(view, iterations: 6)
    XCTAssertEqual(events.count, 1)
  }

  func test_dynamicBottomIncludesAnArrival() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1200
    _ = beginAnimatedBottom(view)
    let appendedCount = Metrics.rowCount + 12

    view.applyItems((0..<appendedCount).map { Msg(id: $0) })

    XCTAssertTrue(pump(view) { events.count == 1 })
    XCTAssertEqual(events.first?.finished, true)
    XCTAssertEqual(events.first?.itemID, appendedCount - 1)
    XCTAssertEqual(view.test_pointsFromBottom, 0, accuracy: Metrics.tolerance)
  }

  func test_automaticAppendFollowCancelsRatherThanImpersonatingAnExplicitCommand() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1200
    view.autoScrollsToBottomOnAppend = true
    let version = beginAnimatedBottom(view)

    view.applyItems((0..<Metrics.rowCount + 1).map { Msg(id: $0) })

    XCTAssertTrue(pump(view) { !events.isEmpty })
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.version, version)
    XCTAssertEqual(events.first?.finished, false)
  }

  func test_itemCommandWaitsForAppendedSnapshotGeometry() {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 1200
    let target = Msg(id: Metrics.rowCount + 20)
    view.applyItems((0..<Metrics.rowCount + 12).map { Msg(id: $0) } + [target])
    position.scrollTo(id: target.id, anchor: .bottom, animated: false)
    view.applyScrollPosition(position)

    XCTAssertTrue(pump(view) { view.test_pointsFromBottom < Metrics.tolerance })
    XCTAssertTrue(events.isEmpty)
  }

  func test_queuedItemPositioningDrainsOnce() {
    for outcome in DeferredOutcome.allCases {
      let view = mount(loadsItems: false)
      let rows = (0..<60).map { Msg(id: $0) }
      view.applyItems(rows)
      XCTAssertTrue(pump(view) { view.test_collectionView.contentSize.height > Metrics.viewport.height })

      let added = rows + [Msg(id: 60)]
      let target = Msg(id: 61)
      view.applyItems(added)
      view.applyItems(added + [target])
      XCTAssertTrue(view.test_isApplyingItemChanges)

      var command = TiledScrollPosition()
      command.scrollTo(id: target.id, anchor: .bottom, animated: false)
      view.applyScrollPosition(command)
      switch outcome {
      case .finish:
        break
      case .pan:
        view.scrollViewWillBeginDragging(view.test_collectionView)
      case .cancel:
        command.cancel()
        view.applyScrollPosition(command)
      case .supersede:
        command.scrollTo(edge: .top, animated: false)
        view.applyScrollPosition(command)
      case .dismantle:
        view.dismantle()
      }

      XCTAssertTrue(pump(view) { !view.test_isApplyingItemChanges }, "\(outcome) did not settle")
      view.window?.layoutIfNeeded()
      if outcome == .finish {
        XCTAssertEqual(view.test_pointsFromBottom, 0, accuracy: Metrics.tolerance, "\(outcome)")
      } else {
        XCTAssertGreaterThan(view.test_pointsFromBottom, Metrics.tolerance, "\(outcome)")
        if outcome == .pan {
          view.applyScrollPosition(command)
          XCTAssertGreaterThan(view.test_pointsFromBottom, Metrics.tolerance)
        }
      }
    }
  }

  private enum DeferredOutcome: CaseIterable {
    case finish, pan, cancel, supersede, dismantle
  }

  private func assertEdgeScrollCompletesOnce(animated: Bool) {
    let view = mount()
    view.test_collectionView.contentOffset.y -= 400
    let version = scroll(view, edge: .bottom, animated: animated)

    XCTAssertTrue(pump(view) { events.count == 1 })
    XCTAssertEqual(events.first?.version, version)
    XCTAssertEqual(events.first?.finished, true)
    XCTAssertEqual(events.first?.itemID, Metrics.rowCount - 1)
    XCTAssertEqual(view.test_pointsFromBottom, 0, accuracy: Metrics.tolerance)

    scroll(view, edge: .bottom, animated: animated)

    XCTAssertTrue(pump(view) { events.count == 2 })
    XCTAssertEqual(events.last?.finished, true)
    XCTAssertEqual(events.last?.itemID, Metrics.rowCount - 1)
  }

  @discardableResult
  private func beginAnimatedBottom(_ view: HostView) -> UInt {
    let before = view.test_contentOffsetY
    let version = scroll(view, edge: .bottom, animated: true)
    XCTAssertTrue(pump(view) {
      view.test_contentOffsetY > before + Metrics.tolerance
        && view.test_pointsFromBottom > Metrics.tolerance
    })
    return version
  }

  @discardableResult
  private func scroll(
    _ view: HostView,
    edge: TiledScrollPosition.Edge,
    animated: Bool,
    focusBottomAccessibilityElement: Bool = false
  ) -> UInt {
    position.scrollTo(
      edge: edge,
      animated: animated,
      focusBottomAccessibilityElement: focusBottomAccessibilityElement
    )
    view.applyScrollPosition(position)
    return position.version
  }

  private func mount(loadsItems: Bool = true) -> HostView {
    position = TiledScrollPosition()
    events = []
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { _, _, _ in MsgCell() }
    )
    let window = UIWindow(frame: CGRect(origin: .zero, size: Metrics.viewport))
    window.makeKeyAndVisible()
    windows.append(window)
    view.frame = window.bounds
    window.addSubview(view)
    view.scrollsToBottomOnReplace = true
    view.onTiledEdgeScrollCompletion = { [weak self] completion in
      self?.events.append(completion)
    }
    if loadsItems {
      view.applyItems((0..<Metrics.rowCount).map { Msg(id: $0) })
      pump(view, iterations: 4)
    }
    return view
  }

  @discardableResult
  private func pump(
    _ view: HostView,
    timeout: TimeInterval = Metrics.timeout,
    until condition: () -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
      view.window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(Metrics.pumpInterval))
    }
    return condition()
  }

  private func pump(_ view: HostView, iterations: Int) {
    for _ in 0..<iterations {
      view.window?.setNeedsLayout()
      view.window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(Metrics.pumpInterval))
    }
  }
}
