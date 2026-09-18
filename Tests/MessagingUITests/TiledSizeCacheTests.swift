import Testing
@testable import MessagingUI

@MainActor
struct TiledSizeCacheTests {

  struct TestItem: Identifiable, Equatable {
    let id: Int
    var value: String
  }

  @Test
  func hit() {
    let cache = TiledSizeCache<TestItem>()
    let item = TestItem(id: 1, value: "A")
    cache.store(40, for: item, width: 320)

    #expect(cache.height(for: item, width: 320) == 40)
  }

  @Test
  func missWhenItemChanges() {
    let cache = TiledSizeCache<TestItem>()
    cache.store(40, for: TestItem(id: 1, value: "A"), width: 320)

    #expect(cache.height(for: TestItem(id: 1, value: "B"), width: 320) == nil)
  }

  @Test
  func widthsAreKeptApart() {
    let cache = TiledSizeCache<TestItem>()
    let item = TestItem(id: 1, value: "A")
    cache.store(40, for: item, width: 320)
    cache.store(60, for: item, width: 200)

    #expect(cache.height(for: item, width: 320) == 40)
    #expect(cache.height(for: item, width: 200) == 60)
    #expect(cache.height(for: item, width: 500) == nil)
  }

  @Test
  func contextChangeClears() {
    let cache = TiledSizeCache<TestItem>()
    let item = TestItem(id: 1, value: "A")
    cache.context = "light"
    cache.store(40, for: item, width: 320)

    cache.context = "light"
    #expect(cache.height(for: item, width: 320) == 40)

    cache.context = "dark"
    #expect(cache.height(for: item, width: 320) == nil)
  }

  @Test
  func evictsLeastRecentlyUsed() {
    let cache = TiledSizeCache<TestItem>(limit: 4)
    let items = (0..<4).map { TestItem(id: $0, value: "\($0)") }
    for item in items {
      cache.store(10, for: item, width: 320)
    }
    // Touch the oldest so the next oldest is evicted instead.
    _ = cache.height(for: items[0], width: 320)

    cache.store(10, for: TestItem(id: 4, value: "4"), width: 320)

    #expect(cache.count == 4)
    #expect(cache.height(for: items[0], width: 320) == 10)
    #expect(cache.height(for: items[1], width: 320) == nil)
  }
}
