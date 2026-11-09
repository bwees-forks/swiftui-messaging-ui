import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

@MainActor
final class TiledAccessibilityFocusTests: XCTestCase {

  private struct Msg: Identifiable, Equatable {
    let id: Int
  }

  private struct MsgCell: View {
    let item: Msg

    var body: some View {
      Text("Message \(item.id)")
        .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Message \(item.id)")
        .accessibilityIdentifier(Metrics.identifier(item.id))
    }
  }

  private enum Metrics {
    static let viewport = CGSize(width: 320, height: 600)
    static let rowHeight: CGFloat = 80
    static let rowCount = 30
    static let tolerance: CGFloat = 1
    static let timeout: TimeInterval = 2
    static let pumpInterval: TimeInterval = 0.02

    static func identifier(_ id: Int) -> String { "message.\(id)" }
  }

  private typealias HostView = TiledUIView<Msg, MsgCell, Never, Never, Never, Never, Void>

  private var windows: [UIWindow] = []
  private var position = TiledScrollPosition()

  override func tearDown() async throws {
    await MainActor.run {
      for window in windows { window.isHidden = true }
      windows.removeAll()
    }
    try await super.tearDown()
  }

  func test_bottomFocusPostsLayoutChangedForTheBottomMessage() {
    let view = mount()
    view.test_accessibilityPosts = []
    view.test_collectionView.contentOffset.y -= 400

    position.scrollTo(edge: .bottom, animated: false, focusBottomAccessibilityElement: true)
    view.applyScrollPosition(position)

    XCTAssertTrue(pump(view) { view.test_accessibilityPosts?.count == 1 })
    XCTAssertEqual(view.test_accessibilityPosts?.first?.0, .layoutChanged)
    let element = view.test_accessibilityPosts?.first?.1 as? NSObject
    XCTAssertEqual(element?.accessibilityLabel, "Message \(Metrics.rowCount - 1)")
    XCTAssertEqual(accessibilityIdentifier(of: element), Metrics.identifier(Metrics.rowCount - 1))
  }

  func test_supersededFocusScrollDoesNotPost() {
    let view = mount()
    view.test_accessibilityPosts = []
    view.test_collectionView.contentOffset.y -= 800

    position.scrollTo(edge: .bottom, animated: true, focusBottomAccessibilityElement: true)
    view.applyScrollPosition(position)
    position.scrollTo(edge: .top, animated: false)
    view.applyScrollPosition(position)

    pump(view, iterations: 8)
    XCTAssertEqual(view.test_accessibilityPosts?.count, 0)
  }

  private func mount() -> HostView {
    position = TiledScrollPosition()
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { item, _, _ in MsgCell(item: item) }
    )
    let window = UIWindow(frame: CGRect(origin: .zero, size: Metrics.viewport))
    window.makeKeyAndVisible()
    windows.append(window)
    view.frame = window.bounds
    window.addSubview(view)
    view.scrollsToBottomOnReplace = true
    view.messageAccessibilityIdentifier = { Metrics.identifier($0) }
    view.applyItems((0..<Metrics.rowCount).map { Msg(id: $0) })
    pump(view, iterations: 4)
    return view
  }

  private func accessibilityIdentifier(of object: NSObject?) -> String? {
    guard let object else { return nil }
    let getter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
    guard object.responds(to: getter) else { return nil }
    return object.perform(getter)?.takeUnretainedValue() as? String
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
      view.window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(Metrics.pumpInterval))
    }
  }
}
