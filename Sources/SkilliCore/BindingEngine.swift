/// Resolves key presses against single-chord bindings and multi-chord
/// sequences (leader style: `hyper+k` then `u`).
///
/// Pure state machine: the caller feeds chords and a clock; the engine says
/// whether to let the key through, swallow it, show sequence hints, or fire.
public struct BindingEngine<Action: Hashable & Sendable>: Sendable {
    public struct Hint: Hashable, Sendable {
        public let chord: Chord
        public let label: String
        public let isGroup: Bool
    }

    public enum Outcome: Hashable, Sendable {
        /// Not bound: deliver the key to the focused app untouched.
        case passThrough
        /// A binding completed: swallow the key and run the action.
        case fire(Action)
        /// Entered or advanced a sequence: swallow the key and show the hints
        /// under the group's title (from `labelGroup`, if any).
        case pending(prefix: [Chord], title: String?, hints: [Hint])
        /// A key broke the pending sequence: swallow it and reset.
        case cancelled
    }

    public enum BindingError: Error, Equatable {
        case emptySequence
        /// The sequence collides with an existing binding: one would be a
        /// strict prefix of the other, or both bind the same chords.
        case conflict([Chord])
        case unknownGroup([Chord])
    }

    private struct Node: Sendable {
        var action: Action?
        var label: String?
        var children: [Chord: Node] = [:]
        /// Declaration order, so hints list bindings the way config groups them.
        var order = 0
    }

    /// How long a pending sequence waits for its next chord.
    public var timeout: Duration

    private var root = Node()
    private var nextOrder = 0
    private var pending: [Chord] = []
    private var pendingSince: ContinuousClock.Instant?

    public init(timeout: Duration = .seconds(3)) {
        self.timeout = timeout
    }

    public var isPending: Bool { !pending.isEmpty }

    /// Binds `sequence` as `Chord.chain` reads it: modifiers of its first
    /// chord on the later ones do not count.
    public mutating func bind(_ sequence: [Chord], label: String, to action: Action) throws {
        guard !sequence.isEmpty else { throw BindingError.emptySequence }
        try Self.insert(Chord.chain(sequence)[...], into: &root, path: [], label: label, action: action, order: &nextOrder)
    }

    /// Names an intermediate node, e.g. `hyper+k` → "Leader". The group must
    /// already exist (bind its children first).
    public mutating func labelGroup(_ prefix: [Chord], _ label: String) throws {
        guard !prefix.isEmpty else { throw BindingError.emptySequence }
        try Self.label(prefix[...], in: &root, full: prefix, label: label)
    }

    /// Inside a pending sequence, the modifiers still held from its first
    /// chord (and Hyper) do not count: ⌘Space then Space matches whether ⌘
    /// was let go before the second Space or kept down.
    public mutating func handle(_ chord: Chord, at now: ContinuousClock.Instant) -> Outcome {
        expireIfNeeded(at: now)
        let chord = pending.first.map { chord.inChain(after: $0) } ?? chord

        guard let next = node(at: pending).children[chord] else {
            if pending.isEmpty { return .passThrough }
            reset()
            return .cancelled
        }

        if let action = next.action {
            reset()
            return .fire(action)
        }

        pending.append(chord)
        pendingSince = now
        return .pending(prefix: pending, title: next.label, hints: Self.hints(for: next))
    }

    /// Drops a pending sequence whose timeout has elapsed. Returns `true`
    /// when something was dropped (so the caller can hide its hints).
    @discardableResult
    public mutating func expireIfNeeded(at now: ContinuousClock.Instant) -> Bool {
        guard let pendingSince, now - pendingSince >= timeout else { return false }
        reset()
        return true
    }

    public mutating func cancel() {
        reset()
    }

    private mutating func reset() {
        pending.removeAll()
        pendingSince = nil
    }

    private func node(at path: [Chord]) -> Node {
        // `pending` only ever holds a path that exists in the trie.
        path.reduce(root) { node, chord in node.children[chord]! }
    }

    private static func hints(for node: Node) -> [Hint] {
        node.children
            .sorted { $0.value.order < $1.value.order }
            .map { chord, child in
                Hint(chord: chord, label: child.label ?? "…", isGroup: child.action == nil)
            }
    }

    private static func insert(
        _ rest: ArraySlice<Chord>,
        into node: inout Node,
        path: [Chord],
        label: String,
        action: Action,
        order: inout Int
    ) throws {
        guard let chord = rest.first else { return }
        let path = path + [chord]
        var child: Node
        if let existing = node.children[chord] {
            child = existing
        } else {
            child = Node()
            child.order = order
            order += 1
        }
        let tail = rest.dropFirst()

        if tail.isEmpty {
            guard child.action == nil, child.children.isEmpty else { throw BindingError.conflict(path) }
            child.action = action
            child.label = label
        } else {
            guard child.action == nil else { throw BindingError.conflict(path) }
            try insert(tail, into: &child, path: path, label: label, action: action, order: &order)
        }
        node.children[chord] = child
    }

    private static func label(
        _ rest: ArraySlice<Chord>,
        in node: inout Node,
        full: [Chord],
        label: String
    ) throws {
        guard let chord = rest.first, var child = node.children[chord], child.action == nil else {
            throw BindingError.unknownGroup(full)
        }
        if rest.count == 1 {
            child.label = label
        } else {
            try Self.label(rest.dropFirst(), in: &child, full: full, label: label)
        }
        node.children[chord] = child
    }
}
