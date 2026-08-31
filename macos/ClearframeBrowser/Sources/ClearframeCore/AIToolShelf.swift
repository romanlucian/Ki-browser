import Foundation

/// The row of AI tools a reader sees on the AI home, and the rule that decides
/// what is in it.
///
/// A new tab that shows nothing until you click is the one new-tab design a
/// browser has shipped and withdrawn: Arc's own account of why people stopped
/// using it calls the pattern a novelty tax. The row exists so the page has
/// something on it the moment it opens.
///
/// **Positions are stable, and that is the whole point.** A tile that moves
/// under the reader's hand is slower than typing, because it has to be read
/// before it can be clicked. A tool keeps the slot it was given; the row changes
/// only when a tool leaves it, never because a count ticked up. Chrome reorders
/// its tiles by frequency and it is the most common complaint about them.
///
/// Nothing here leaves the Mac. It is a count of how often a catalogued tool was
/// opened from this browser, held in the app's own preferences, and it says
/// nothing about pages visited anywhere else.
public struct AIToolShelf: Codable, Equatable, Sendable {
    public static let defaultCapacity = 6

    /// One entry per slot, in the order the reader sees them. `nil` is a slot
    /// nothing has earned yet.
    private var slots: [String?]
    private var opens: [String: Int]
    private var pinned: Set<String>

    public init(capacity: Int = AIToolShelf.defaultCapacity) {
        slots = Array(repeating: nil, count: max(1, capacity))
        opens = [:]
        pinned = []
    }

    public var capacity: Int { slots.count }

    /// The tools to draw, in slot order, skipping slots nothing has earned.
    public var toolIDs: [String] { slots.compactMap { $0 } }

    public func isPinned(_ toolID: String) -> Bool { pinned.contains(toolID) }

    public func openCount(of toolID: String) -> Int { opens[toolID] ?? 0 }

    /// A tool earns its place the first time it is opened. Waiting for a second
    /// visit would leave the row empty through the first session, which is the
    /// session that decides whether anyone comes back.
    public mutating func recordOpen(_ toolID: String) {
        guard !toolID.isEmpty else { return }
        opens[toolID, default: 0] += 1
        guard !slots.contains(toolID) else { return }

        if let empty = slots.firstIndex(where: { $0 == nil }) {
            slots[empty] = toolID
            return
        }

        // The row is full. A newcomer takes a place only from the least-opened
        // tool that is not pinned, and only by having been opened more often —
        // so a tool the reader still uses is never displaced by a passing one.
        let candidates = slots.enumerated().compactMap { index, id -> (Int, String, Int)? in
            guard let id, !pinned.contains(id) else { return nil }
            return (index, id, opens[id] ?? 0)
        }
        guard let weakest = candidates.min(by: { $0.2 < $1.2 }),
              opens[toolID, default: 0] > weakest.2 else { return }
        slots[weakest.0] = toolID
    }

    /// A pinned tool keeps its slot whatever the counts do. Pinning a tool that
    /// is not on the row puts it there first.
    public mutating func pin(_ toolID: String) {
        guard !toolID.isEmpty else { return }
        if !slots.contains(toolID) {
            if let empty = slots.firstIndex(where: { $0 == nil }) {
                slots[empty] = toolID
            } else if let weakest = slots.enumerated().compactMap({ index, id -> (Int, Int)? in
                guard let id, !pinned.contains(id) else { return nil }
                return (index, opens[id] ?? 0)
            }).min(by: { $0.1 < $1.1 }) {
                slots[weakest.0] = toolID
            } else {
                return
            }
        }
        pinned.insert(toolID)
    }

    public mutating func unpin(_ toolID: String) { pinned.remove(toolID) }

    /// Removing a tool clears its slot and forgets that it was ever opened, so a
    /// tool the reader has taken off the row does not walk straight back on.
    public mutating func remove(_ toolID: String) {
        guard let index = slots.firstIndex(of: toolID) else { return }
        slots[index] = nil
        pinned.remove(toolID)
        opens[toolID] = nil
    }
}
