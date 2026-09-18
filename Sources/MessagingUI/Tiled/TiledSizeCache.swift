import CoreGraphics

/// Measured message heights that outlive a single `TiledView`, so reopening
/// a list skips measuring items whose value and width are unchanged.
///
/// An entry is valid only for the item value and width it was measured
/// with. Anything else that affects height, such as theme or dynamic type,
/// belongs in `context`; changing it clears the cache.
@MainActor
public final class TiledSizeCache<Item: Identifiable & Equatable> {

  private struct Key: Hashable {
    var id: Item.ID
    var width: CGFloat
  }

  private struct Entry {
    var item: Item
    var height: CGFloat
    var lastUsed: UInt64
  }

  /// Rendering inputs outside the item that the cached heights depend on.
  public var context: AnyHashable? {
    didSet {
      if context != oldValue { entries.removeAll() }
    }
  }

  /// Entry count above which the least recently used quarter is evicted.
  public let limit: Int

  private var entries: [Key: Entry] = [:]
  private var clock: UInt64 = 0

  public init(limit: Int = 3000) {
    self.limit = max(limit, 1)
  }

  var count: Int { entries.count }

  /// Returns the height measured at `width` when `item` equals the measured
  /// item.
  func height(for item: Item, width: CGFloat) -> CGFloat? {
    let key = Key(id: item.id, width: width)
    guard var entry = entries[key], entry.item == item else { return nil }
    entry.lastUsed = tick()
    entries[key] = entry
    return entry.height
  }

  func store(_ height: CGFloat, for item: Item, width: CGFloat) {
    let key = Key(id: item.id, width: width)
    entries[key] = Entry(item: item, height: height, lastUsed: tick())
    if entries.count > limit { evict() }
  }

  public func removeAll() {
    entries.removeAll()
  }

  private func tick() -> UInt64 {
    clock &+= 1
    return clock
  }

  /// Drops the least recently used quarter.
  private func evict() {
    let drop = max(entries.count / 4, entries.count - limit)
    let stale = entries.sorted { $0.value.lastUsed < $1.value.lastUsed }.prefix(drop)
    for (key, _) in stale {
      entries[key] = nil
    }
  }
}
