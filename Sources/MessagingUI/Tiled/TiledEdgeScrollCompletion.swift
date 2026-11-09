/// Terminal result of one explicit edge scroll, delivered on the next main turn.
/// `itemID` is the row at `edge` when the command finishes, and nil when it is cancelled.
public struct TiledEdgeScrollCompletion<ID: Hashable>: Equatable {

  /// Version of the `TiledScrollPosition` command this result belongs to.
  public var version: UInt

  /// The edge the command scrolled toward.
  public var edge: TiledScrollPosition.Edge

  /// The row at `edge` when `finished` is true. Nil when the command is cancelled.
  public var itemID: ID?

  /// True when the command reached its edge. False when it was cancelled.
  public var finished: Bool

  public init(version: UInt, edge: TiledScrollPosition.Edge, itemID: ID?, finished: Bool) {
    self.version = version
    self.edge = edge
    self.itemID = itemID
    self.finished = finished
  }
}
