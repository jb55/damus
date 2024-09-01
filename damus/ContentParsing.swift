//
//  ContentParsing.swift
//  damus
//
//  Created by William Casarin on 2023-07-22.
//

import Foundation

enum NoteContent {
    case note(NostrEvent)
    case content(String, TagsSequence?)

    init(note: NostrEvent, keypair: Keypair) {
        if note.known_kind == .dm {
            self = .content(note.get_content(keypair), note.tags)
        } else {
            self = .note(note)
        }
    }
}

// TODO: just make a blocks iterator over the compact data instead of using Blocks
func parsed_blocks_finish(bs: inout ndb_blocks, tags: TagsSequence?) -> Blocks {
    var out: [Block] = []

    var i = 0
    while (i < bs.num_blocks) {
        let block = bs.blocks[i]

        if let converted = Block(block: block, tags: tags) {
            out.append(converted)
        }

        i += 1
    }

    let words = Int(bs.words)

    return Blocks(words: words, blocks: out)

}


func parse_note_content(content: NoteContent) -> Blocks? {
    // Step 1: Prepare the data you need to pass to the C function.
    var buffer = [UInt8](repeating: 0, count: 1024*1024)  // Example buffer, replace size with what you need
    let buf_size = Int32(buffer.count)
    var ptr: OpaquePointer? = nil  // Pointer for the result

    switch content {
    case .note(let nostrEvent):
        let len = Int32(nostrEvent.content_len)
        let r = ndb_parse_content(&buffer, buf_size, nostrEvent.content_raw, len, &ptr)

        if r != 0 {
            let nil_tags: TagsSequence? = nil
            let size = ndb_blocks_total_size(ptr)
            let resized = buffer[0:size]
            return Blocks.init(buffer: buffer[0:], blocks: <#T##NdbBlocks#>)
        }

    case .content(let s, let tagsSequence):
        let content_len = Int32(s.utf8.count)
        let res = s.withCString { cptr in
            ndb_parse_content(&buffer, buf_size, cptr, content_len, &blocks)
        }

        if res != 0 {
            return parsed_blocks_finish(bs: blocks, tags: tagsSequence)
        } else {
            return nil
        }
    }
}


func interpret_event_refs(tags: TagsSequence) -> ThreadReply? {
    // migration is long over, lets just do this to fix tests
    return interpret_event_refs_ndb(tags: tags)
}

func interpret_event_refs_ndb(tags: TagsSequence) -> ThreadReply? {
    if tags.count == 0 {
        return nil
    }

    return interp_event_refs_without_mentions_ndb(References<NoteRef>(tags: tags))
}

func interp_event_refs_without_mentions_ndb(_ ev_tags: References<NoteRef>) -> ThreadReply? {
    var first: Bool = true
    var root_id: NoteRef? = nil
    var reply_id: NoteRef? = nil
    var mention: NoteRef? = nil
    var any_marker: Bool = false

    for ref in ev_tags {
        if let marker = ref.marker {
            any_marker = true
            switch marker {
            case .root: root_id = ref
            case .reply: reply_id = ref
            case .mention: mention = ref
            }
        // deprecated form, only activate if we don't have any markers set
        } else if !any_marker {
            if first {
                root_id = ref
                first = false
            } else {
                reply_id = ref
            }
        }
    }

    // If either reply or root_id is blank while the other is not, then this is
    // considered reply-to-root. We should always have a root and reply tag, if they
    // are equal this is reply-to-root
    if reply_id == nil && root_id != nil {
        reply_id = root_id
    } else if root_id == nil && reply_id != nil {
        root_id = reply_id
    }

    guard let reply_id, let root_id else {
        return nil
    }

    return ThreadReply(root: root_id, reply: reply_id, mention: mention.map { m in .noteref(m) })
}
