import Foundation

/// A transcript as its window edits it (docs/meeting-recorder-views.md,
/// phase 4, "a line selected"): its lines and its speakers' names, each
/// change kept to be undone (⌘Z) and done again (⇧⌘Z). Pure parts.
public struct TranscriptDraft: Equatable, Sendable {
    public var lines: [TranscriptLine]
    /// `meeting.json`'s `speakers`.
    public var names: [String: String]

    public init(lines: [TranscriptLine], names: [String: String]) {
        self.lines = lines
        self.names = names
    }

    /// One change by hand, with what it needs to be undone.
    public enum Edit: Equatable, Sendable {
        /// The line's words, before and after.
        case words(line: Int, before: [TranscriptWord], after: [TranscriptWord])
        /// The line given to another speaker.
        case speaker(line: Int, before: Voice, after: Voice)
        /// The line gone.
        case delete(line: Int, removed: TranscriptLine)
        /// A speaker renamed, or merged into another.
        case rename(MeetingVoices.Renamed)
    }

    /// The line's words as `text` (`TranscriptDraft.retimed`): nil when the
    /// text is the same; an empty text is a delete.
    public mutating func setText(_ text: String, at line: Int) -> Edit? {
        guard lines.indices.contains(line) else { return nil }
        let words = Self.retimed(lines[line].words, to: text, start: lines[line].start, end: lines[line].end)
        guard !words.isEmpty else { return delete(at: line) }
        guard MeetingTranscript.joined(words) != lines[line].text else { return nil }
        let edit = Edit.words(line: line, before: lines[line].words, after: words)
        apply(edit)
        return edit
    }

    /// The line given to the next speaker (`step` -1: the one before).
    public mutating func moveSpeaker(at line: Int, step: Int = 1) -> Edit? {
        guard lines.indices.contains(line) else { return nil }
        let before = lines[line].speaker
        let after = MeetingVoices.next(after: before, in: MeetingVoices.order(of: lines), step: step)
        guard after != before else { return nil }
        let edit = Edit.speaker(line: line, before: before, after: after)
        apply(edit)
        return edit
    }

    public mutating func delete(at line: Int) -> Edit? {
        guard lines.indices.contains(line) else { return nil }
        let edit = Edit.delete(line: line, removed: lines[line])
        apply(edit)
        return edit
    }

    /// `voice` given `name` (`MeetingVoices.rename`'s rules).
    public mutating func rename(_ voice: Voice, to name: String, ownName: String? = nil) -> Edit? {
        MeetingVoices.rename(voice, to: name, lines: &lines, names: &names, ownName: ownName).map(Edit.rename)
    }

    /// Does `edit` again (⇧⌘Z), or for the first time.
    public mutating func apply(_ edit: Edit) {
        switch edit {
        case .words(let line, _, let after):
            guard lines.indices.contains(line) else { return }
            lines[line] = TranscriptLine(speaker: lines[line].speaker, words: after)
        case .speaker(let line, _, let after):
            guard lines.indices.contains(line) else { return }
            lines[line].speaker = after
        case .delete(let line, _):
            guard lines.indices.contains(line) else { return }
            lines.remove(at: line)
        case .rename(let renamed):
            for index in renamed.moved.keys where lines.indices.contains(index) { lines[index].speaker = renamed.joined ?? lines[index].speaker }
            names = renamed.namesAfter
        }
    }

    /// Undoes `edit` (⌘Z).
    public mutating func revert(_ edit: Edit) {
        switch edit {
        case .words(let line, let before, _):
            guard lines.indices.contains(line) else { return }
            lines[line] = TranscriptLine(speaker: lines[line].speaker, words: before)
        case .speaker(let line, let before, _):
            guard lines.indices.contains(line) else { return }
            lines[line].speaker = before
        case .delete(let line, let removed):
            lines.insert(removed, at: min(max(0, line), lines.count))
        case .rename(let renamed):
            for (index, voice) in renamed.moved where lines.indices.contains(index) { lines[index].speaker = voice }
            names = renamed.namesBefore
        }
    }

    /// A line's words written again as `text`: the words kept at its start
    /// and at its end (case and punctuation aside) keep their times; the
    /// words between share the time of those they replace (none replaced:
    /// the gap between their neighbours), in equal parts. Empty: none.
    public static func retimed(_ words: [TranscriptWord], to text: String, start: Double, end: Double) -> [TranscriptWord] {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !pieces.isEmpty else { return [] }
        let same = { (word: TranscriptWord, piece: String) in
            word.text == piece || (!MeetingTranscript.folded(piece).isEmpty && MeetingTranscript.folded(word.text) == MeetingTranscript.folded(piece))
        }
        var head = 0
        while head < min(words.count, pieces.count), same(words[head], pieces[head]) { head += 1 }
        var tail = 0
        while tail < min(words.count, pieces.count) - head, same(words[words.count - 1 - tail], pieces[pieces.count - 1 - tail]) { tail += 1 }
        var result: [TranscriptWord] = []
        for index in 0..<head { result.append(TranscriptWord(pieces[index], start: words[index].start, end: words[index].end)) }
        let fresh = Array(pieces[head..<(pieces.count - tail)])
        if !fresh.isEmpty {
            let replaced = words[head..<(words.count - tail)]
            let from = replaced.first?.start ?? (head > 0 ? words[head - 1].end : start)
            let to = replaced.last?.end ?? (tail > 0 ? words[words.count - tail].start : end)
            let span = max(0, to - from) / Double(fresh.count)
            for (index, piece) in fresh.enumerated() {
                result.append(TranscriptWord(piece, start: from + span * Double(index), end: from + span * Double(index + 1)))
            }
        }
        for index in (words.count - tail)..<words.count {
            result.append(TranscriptWord(pieces[pieces.count - (words.count - index)], start: words[index].start, end: words[index].end))
        }
        return result
    }
}

/// The window's changes, to undo and do again (⌘Z, ⇧⌘Z) while it is open.
/// A delete's undo card brings back that delete even when other changes
/// came after it (`revert(id:)`): the places of those after it move with
/// it.
public struct TranscriptHistory: Sendable {
    public struct Entry: Equatable, Sendable {
        public let id: Int
        public var edit: TranscriptDraft.Edit
    }

    public private(set) var done: [Entry] = []
    public private(set) var undone: [Entry] = []
    private var counter = 0

    public init() {}

    /// A change made: kept; what was undone before it cannot be done
    /// again. Its id, for an undo card.
    @discardableResult
    public mutating func record(_ edit: TranscriptDraft.Edit) -> Int {
        counter += 1
        done.append(Entry(id: counter, edit: edit))
        undone = []
        return counter
    }

    public var canUndo: Bool { !done.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    /// ⌘Z: the last change undone in `draft`.
    @discardableResult
    public mutating func undo(_ draft: inout TranscriptDraft) -> TranscriptDraft.Edit? {
        guard let last = done.popLast() else { return nil }
        draft.revert(last.edit)
        undone.append(last)
        return last.edit
    }

    /// ⇧⌘Z: the last change undone done again.
    @discardableResult
    public mutating func redo(_ draft: inout TranscriptDraft) -> TranscriptDraft.Edit? {
        guard let last = undone.popLast() else { return nil }
        draft.apply(last.edit)
        done.append(last)
        return last.edit
    }

    /// The change `id` undone wherever it is (a delete's undo card): the
    /// changes after it are undone, it is, they are done again with the
    /// line it brings back counted in their places. False when it is gone
    /// (already undone).
    @discardableResult
    public mutating func revert(id: Int, in draft: inout TranscriptDraft) -> Bool {
        guard let index = done.firstIndex(where: { $0.id == id }) else { return false }
        let after = Array(done[(index + 1)...])
        for entry in after.reversed() { draft.revert(entry.edit) }
        let entry = done[index]
        draft.revert(entry.edit)
        done.removeSubrange(index...)
        let inserted: Int? = if case .delete(let line, _) = entry.edit { line } else { nil }
        for var later in after {
            if let inserted { later.edit = Self.shifted(later.edit, insertedAt: inserted) }
            draft.apply(later.edit)
            done.append(later)
        }
        undone = []
        return true
    }

    /// `edit`'s places once a line came back at `inserted` before it was
    /// made.
    private static func shifted(_ edit: TranscriptDraft.Edit, insertedAt inserted: Int) -> TranscriptDraft.Edit {
        let move = { (line: Int) in line >= inserted ? line + 1 : line }
        switch edit {
        case .words(let line, let before, let after): return .words(line: move(line), before: before, after: after)
        case .speaker(let line, let before, let after): return .speaker(line: move(line), before: before, after: after)
        case .delete(let line, let removed): return .delete(line: move(line), removed: removed)
        case .rename(var renamed):
            renamed.moved = Dictionary(uniqueKeysWithValues: renamed.moved.map { (move($0.key), $0.value) })
            return .rename(renamed)
        }
    }
}
