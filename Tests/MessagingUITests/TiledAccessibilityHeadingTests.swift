import SwiftUI
import UIKit
import XCTest
@testable import MessagingUI

@MainActor
final class TiledAccessibilityHeadingTests: XCTestCase {

  private struct Msg: Identifiable, Equatable {
    let id: Int
    var isHeading: Bool

    init(id: Int) {
      self.id = id
      isHeading = id.isMultiple(of: Metrics.messagesPerDay)
    }
  }

  private struct MsgCell: View {
    let item: Msg

    var body: some View {
      VStack {
        if item.isHeading {
          Text("Day \(item.id / Metrics.messagesPerDay)")
            .accessibilityAddTraits(.isHeader)
        }
        Button("Message \(item.id)") {}
      }
      .frame(height: Metrics.rowHeight)
      .environment(\.accessibilityEnabled, true)
    }
  }

  private enum Metrics {
    static let messagesPerDay = 24
    static let rowHeight: CGFloat = 64
    static let viewport = CGSize(width: 390, height: 600)
    static let timeout: TimeInterval = 2
    static let pumpInterval: TimeInterval = 0.02
  }

  private typealias HostView = TiledUIView<Msg, MsgCell, Never, Never, Never, Never, Void>

  private var windows: [UIWindow] = []
  private var navigationCount = 0

  override func tearDown() async throws {
    await MainActor.run {
      for window in windows { window.isHidden = true }
      windows.removeAll()
      navigationCount = 0
    }
    try await super.tearDown()
  }

  func test_searchMaterializesOffscreenDates_andRespectsRowOrder() {
    let rows = (0..<72).map { Msg(id: $0) }
    let view = mount(rows, headings: [0, 24, 48], anchoredToTop: true)
    let owned = rotor(in: view)
    XCTAssertNotNil(owned)
    XCTAssertNil(heading(48, in: view))

    let first = heading(0, in: view)
    XCTAssertNotNil(first)
    XCTAssertNil(searchResult(owned!, from: first!, forward: false))

    var current = first!
    var currentID = 0
    for id in [24, 48, 24, 0, 24, 48, 24] {
      let found = search(owned!, from: current, forward: id > currentID)
      XCTAssertNotNil(found)
      current = found!
      currentID = id
      let label = "Day \(id / Metrics.messagesPerDay)"
      XCTAssertEqual(current.accessibilityLabel, label)
      XCTAssertTrue(current.accessibilityTraits.contains(.header))
      XCTAssertFalse(current.accessibilityFrame.isEmpty)
      XCTAssertTrue(onScreen(current, in: view))
      XCTAssertTrue(view.test_collectionView.visibleCells.contains { cell in
        let exposed = exposedElement(label, traits: .header, in: cell.contentView)
        return exposed === current || (
          exposed?.accessibilityLabel == label && exposed?.accessibilityFrame == current.accessibilityFrame
        )
      })
      if id == 48 {
        XCTAssertNil(searchResult(owned!, from: current, forward: true))
      }
    }

    let message = exposedElement("Message 24", traits: .button, in: view.test_collectionView)
    XCTAssertNotNil(message)
    let sameRow = search(owned!, from: message!, forward: false)
    XCTAssertEqual(sameRow?.accessibilityLabel, "Day 1")
    let nextRow = search(owned!, from: message!, forward: true)
    XCTAssertEqual(nextRow?.accessibilityLabel, "Day 2")
    XCTAssertEqual(navigationCount, 9)
  }

  func test_prependAddsAnOlderHeading_andRemovalRelocatesTheExistingDate() {
    var rows = (24..<72).map { Msg(id: $0) }
    let view = mount(rows, headings: [24, 48], anchoredToTop: true)
    let owned = rotor(in: view)
    XCTAssertNotNil(owned)

    rows.insert(contentsOf: (0..<24).map { Msg(id: $0) }, at: 0)
    view.applyItems(rows)
    setHeadings([0, 24, 48], on: view)
    XCTAssertTrue(pump(view) {
      view.accessibilityHeadingConfiguration?.itemIDs == Set([0, 24, 48].map(AnyHashable.init))
        && view.test_collectionView.numberOfItems(
          inSection: TiledCollectionViewLayout.DisplaySection.messages.rawValue
        ) == rows.count
        && !view.test_isApplyingItemChanges
        && heading(24, in: view) != nil
    })

    let existing = heading(24, in: view)
    XCTAssertNotNil(existing)
    let older = search(owned!, from: existing!, forward: false)
    XCTAssertEqual(older?.accessibilityLabel, "Day 0")
    let restored = search(owned!, from: older!, forward: true)
    XCTAssertEqual(restored?.accessibilityLabel, "Day 1")

    rows.removeAll { $0.id == 24 }
    let relocatedIndex = rows.firstIndex { $0.id == 25 }!
    rows[relocatedIndex].isHeading = true
    view.applyItems(rows)
    setHeadings([0, 25, 48], on: view)
    var position = TiledScrollPosition()
    position.scrollTo(id: 0, anchor: .top, animated: false)
    view.applyScrollPosition(position)
    XCTAssertTrue(pump(view) {
      heading(0, in: view) != nil
        && view.accessibilityHeadingConfiguration?.itemIDs == Set([0, 25, 48].map(AnyHashable.init))
        && !view.test_isApplyingItemChanges
    })

    let first = heading(0, in: view)
    XCTAssertNotNil(first)
    let relocated = search(owned!, from: first!, forward: true)
    XCTAssertEqual(relocated?.accessibilityLabel, "Day 1")
    XCTAssertTrue(relocated?.accessibilityTraits.contains(.header) == true)
    XCTAssertFalse(relocated?.accessibilityFrame.isEmpty == true)
    XCTAssertTrue(relocated.map { onScreen($0, in: view) } == true)

    let cell = view.test_collectionView.cellForItem(at: IndexPath(
      item: relocatedIndex,
      section: TiledCollectionViewLayout.DisplaySection.messages.rawValue
    ))
    XCTAssertNotNil(cell)
    let liveHeading = exposedElement("Day 1", traits: .header, in: cell!.contentView)
    XCTAssertTrue(
      liveHeading === relocated || liveHeading?.accessibilityFrame == relocated?.accessibilityFrame
    )
    XCTAssertEqual(exposedElements(in: view.test_collectionView).filter {
      $0.accessibilityLabel == "Day 1" && $0.accessibilityTraits.contains(.header)
    }.count, 1)
  }

  func test_metadataChangesAndTeardownRetireOnlyTheOwnedRotor() {
    var rows = (0..<72).map { Msg(id: $0) }
    let view = mount(rows, headings: [0, 24, 48], anchoredToTop: true)
    let collection = view.test_collectionView
    let owned = rotor(in: view)
    XCTAssertNotNil(owned)

    let unrelated = UIAccessibilityCustomRotor(name: "Other navigation") { _ in nil }
    collection.accessibilityCustomRotors = (collection.accessibilityCustomRotors ?? []) + [unrelated]
    setHeadings([0, 48], on: view)
    XCTAssertTrue(pump(view) {
      view.accessibilityHeadingConfiguration?.itemIDs == Set([0, 48].map(AnyHashable.init))
    })

    let first = heading(0, in: view)
    XCTAssertEqual(search(owned!, from: first!, forward: true)?.accessibilityLabel, "Day 2")

    rows.removeAll { $0.id == 48 }
    view.applyItems(rows)
    var position = TiledScrollPosition()
    position.scrollTo(id: 0, anchor: .top, animated: false)
    view.applyScrollPosition(position)
    XCTAssertTrue(pump(view) {
      heading(0, in: view) != nil
        && collection.numberOfItems(inSection: TiledCollectionViewLayout.DisplaySection.messages.rawValue) == rows.count
        && !view.test_isApplyingItemChanges
    })
    let remaining = heading(0, in: view)
    XCTAssertNil(searchResult(owned!, from: remaining!, forward: true))

    setHeadings([], on: view)
    XCTAssertTrue(pump(view) { collection.accessibilityCustomRotors?.contains { $0 === owned } == false })
    XCTAssertTrue(collection.accessibilityCustomRotors?.contains { $0 === unrelated } == true)

    setHeadings([0], on: view)
    XCTAssertTrue(pump(view) { collection.accessibilityCustomRotors?.contains { $0.systemRotorType == .heading } == true })

    view.dismantle()
    XCTAssertTrue(pump(view) { collection.accessibilityCustomRotors?.contains { $0.systemRotorType == .heading } == false })
    XCTAssertTrue(collection.accessibilityCustomRotors?.contains { $0 === unrelated } == true)
    XCTAssertNil(searchResult(owned!, from: remaining!, forward: true))
  }

  private func mount(_ rows: [Msg], headings: [Int], anchoredToTop: Bool) -> HostView {
    navigationCount = 0
    let view = HostView(
      makeInitialState: { _ in () },
      cellBuilder: { item, _, _ in MsgCell(item: item) }
    )
    let window = UIWindow(frame: CGRect(origin: .zero, size: Metrics.viewport))
    window.makeKeyAndVisible()
    windows.append(window)
    view.frame = window.bounds
    window.addSubview(view)
    view.scrollsToBottomOnReplace = !anchoredToTop
    if anchoredToTop, let first = rows.first {
      view.initialScrollTarget = TiledInitialScrollTarget(
        id: AnyHashable(first.id), anchor: .top, holdUntilUserScroll: false
      )
    }
    setHeadings(headings, on: view)
    view.applyItems(rows)
    XCTAssertTrue(pump(view) { heading(headings[0], in: view) != nil && rotor(in: view) != nil })
    return view
  }

  private func setHeadings(_ ids: [Int], on view: HostView) {
    view.accessibilityHeadingConfiguration = TiledAccessibilityHeadingConfiguration(
      itemIDs: Set(ids.map(AnyHashable.init)),
      onNavigate: { [weak self] in self?.navigationCount += 1 }
    )
  }

  private func rotor(in view: HostView) -> UIAccessibilityCustomRotor? {
    view.test_collectionView.accessibilityCustomRotors?.first { $0.systemRotorType == .heading }
  }

  private func heading(_ id: Int, in view: HostView) -> NSObject? {
    exposedElement("Day \(id / Metrics.messagesPerDay)", traits: .header, in: view)
  }

  private func searchResult(
    _ rotor: UIAccessibilityCustomRotor, from element: NSObject, forward: Bool
  ) -> UIAccessibilityCustomRotorItemResult? {
    let predicate = UIAccessibilityCustomRotorSearchPredicate()
    predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: element, targetRange: nil)
    predicate.searchDirection = forward ? .next : .previous
    return rotor.itemSearchBlock(predicate)
  }

  private func search(
    _ rotor: UIAccessibilityCustomRotor, from element: NSObject, forward: Bool
  ) -> NSObject? {
    searchResult(rotor, from: element, forward: forward)?.targetElement as? NSObject
  }

  private func onScreen(_ element: NSObject, in view: HostView) -> Bool {
    guard let window = view.window else { return false }
    let frame = window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
    return frame.intersects(window.bounds)
  }

  private func exposedElement(_ label: String, traits: UIAccessibilityTraits, in root: NSObject) -> NSObject? {
    exposedElements(in: root).first {
      $0.accessibilityLabel == label && $0.accessibilityTraits.contains(traits)
    }
  }

  private func exposedElements(in root: NSObject) -> [NSObject] {
    var visited = Set<ObjectIdentifier>()
    func visit(_ object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted, !object.accessibilityElementsHidden else { return [] }
      if let view = object as? UIView, view.isHidden || view.alpha == 0 { return [] }
      if object.isAccessibilityElement { return [object] }
      var children = (object.accessibilityElements ?? []) + (object.automationElements ?? [])
      let count = object.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        children += (0..<count).compactMap { object.accessibilityElement(at: $0) }
      }
      if let view = object as? UIView { children += view.subviews }
      return children.compactMap { $0 as? NSObject }.flatMap(visit)
    }
    return visit(root)
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
}
