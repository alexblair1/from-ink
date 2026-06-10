import XCTest
@testable import FromInk

/// Pins the `RichTextDocument` Codable contract, the forward-compat
/// decoder behavior, and the traversal helpers that NoteRegion text
/// anchors and the editor flatten path depend on.
///
/// The load-bearing claims:
///
///   - Every block kind round-trips losslessly via `JSONEncoder` /
///     `JSONDecoder`. A v1 document encoded today decodes identically
///     in a v1 client tomorrow.
///   - Unknown `Mark` cases (a v2 mark in a v1 client) drop the mark
///     but preserve the inline text. Users never lose their words.
///   - Unknown `Block.Kind` cases collapse to an empty `.paragraph`,
///     preserving the surrounding document structure.
///   - Block IDs survive encode/decode so NoteRegion anchors keep
///     resolving across persistence.
///   - `block(at: [UUID])` walks the path correctly through nested
///     lists and blockquotes.
final class RichTextDocumentTests: XCTestCase {

    // MARK: - Round-trip — every block kind

    func test_emptyDocument_roundTrips() throws {
        let doc = RichTextDocument.empty
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
        XCTAssertEqual(recovered.version, RichTextDocument.currentVersion)
        XCTAssertEqual(recovered.blocks, [])
    }

    func test_paragraph_roundTrips_withPlainAndMarkedRuns() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "Plain "),
                Inline(text: "bold", marks: [.bold]),
                Inline(text: " and "),
                Inline(text: "italic-link", marks: [.italic, .link(URL(string: "https://example.com")!)])
            ]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
    }

    func test_heading_roundTrips_atEveryLevel() throws {
        for level in 1...3 {
            let doc = RichTextDocument(blocks: [
                Block(kind: .heading(level: level, inline: [Inline(text: "H\(level)")]))
            ])
            let recovered = try Self.roundTrip(doc)
            XCTAssertEqual(recovered, doc, "Heading level \(level) failed")
        }
    }

    func test_codeBlock_roundTrips_withAndWithoutLanguageHint() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .codeBlock(text: "let x = 1\nprint(x)", languageHint: "swift")),
            Block(kind: .codeBlock(text: "no hint", languageHint: nil))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
    }

    func test_bulletList_roundTrips_withMultipleItems() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .bulletList(items: [
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "First")]))
                ]),
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Second")]))
                ]),
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Third")]))
                ])
            ]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
    }

    func test_orderedList_roundTrips_withNestedBulletList() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .orderedList(items: [
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Step 1")])),
                    Block(kind: .bulletList(items: [
                        ListItem(content: [
                            Block(kind: .paragraph(inline: [Inline(text: "Sub a")]))
                        ]),
                        ListItem(content: [
                            Block(kind: .paragraph(inline: [Inline(text: "Sub b")]))
                        ])
                    ]))
                ]),
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Step 2")]))
                ])
            ]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc, "Nested list structure must survive encode/decode")
    }

    func test_blockquote_roundTrips_withInnerHeadingAndParagraph() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .blockquote(children: [
                Block(kind: .heading(level: 2, inline: [Inline(text: "Quoted heading")])),
                Block(kind: .paragraph(inline: [Inline(text: "Quoted body.")]))
            ]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
    }

    func test_divider_roundTrips_asLeaf() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "Above")])),
            Block(kind: .divider),
            Block(kind: .paragraph(inline: [Inline(text: "Below")]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
    }

    func test_blockIDsSurviveEncodeDecode() throws {
        // NoteRegion text-anchor stability depends on this — IDs must
        // be preserved verbatim so a stored region path keeps
        // resolving after the document round-trips through CloudKit.
        let para1ID = UUID()
        let para2ID = UUID()
        let listItemID = UUID()
        let listBlockID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: para1ID, kind: .paragraph(inline: [Inline(text: "1st")])),
            Block(id: listBlockID, kind: .bulletList(items: [
                ListItem(id: listItemID, content: [
                    Block(id: leafID, kind: .paragraph(inline: [Inline(text: "Leaf")]))
                ])
            ])),
            Block(id: para2ID, kind: .paragraph(inline: [Inline(text: "2nd")]))
        ])

        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered.blocks[0].id, para1ID)
        XCTAssertEqual(recovered.blocks[1].id, listBlockID)
        XCTAssertEqual(recovered.blocks[2].id, para2ID)

        guard case .bulletList(let items) = recovered.blocks[1].kind else {
            XCTFail("Expected bulletList")
            return
        }
        XCTAssertEqual(items.first?.id, listItemID)
        XCTAssertEqual(items.first?.content.first?.id, leafID)
    }

    // MARK: - Mark coverage

    func test_everyMarkKind_roundTrips() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "B", marks: [.bold]),
                Inline(text: "I", marks: [.italic]),
                Inline(text: "U", marks: [.underline]),
                Inline(text: "S", marks: [.strikethrough]),
                Inline(text: "C", marks: [.code]),
                Inline(text: "Y", marks: [.highlight(.yellow)]),
                Inline(text: "R", marks: [.highlight(.red)]),
                Inline(text: "L", marks: [.link(URL(string: "https://example.com/x")!)])
            ]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
    }

    func test_multipleMarksOnSingleRun_preserveOrderAndComposition() throws {
        // A single inline run can carry bold + italic + highlight all
        // at once (e.g. an emphasized yellow callout).
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [
                Inline(text: "Important", marks: [.bold, .italic, .highlight(.yellow)])
            ]))
        ])
        let recovered = try Self.roundTrip(doc)
        XCTAssertEqual(recovered, doc)
        guard case .paragraph(let inline) = recovered.blocks.first?.kind else {
            XCTFail("Expected paragraph")
            return
        }
        XCTAssertEqual(inline.first?.marks, [.bold, .italic, .highlight(.yellow)])
    }

    // MARK: - Forward compatibility — unknown Mark dropped

    func test_unknownMarkCase_isDroppedFromInlineRun_textPreserved() throws {
        // Simulate a v2 client persisting an unknown mark type. The
        // v1 client decoding this JSON must preserve the inline text
        // and the known mark, dropping only the unknown.
        let json = #"""
        {
          "version": 1,
          "blocks": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "type": "paragraph",
              "inline": [
                {
                  "text": "Future-marked text",
                  "marks": [
                    { "type": "bold" },
                    { "type": "unobtanium", "exotic_payload": 42 },
                    { "type": "italic" }
                  ]
                }
              ]
            }
          ]
        }
        """#

        let doc = try JSONDecoder().decode(
            RichTextDocument.self,
            from: Data(json.utf8)
        )

        guard case .paragraph(let inline) = doc.blocks.first?.kind else {
            XCTFail("Expected paragraph")
            return
        }
        XCTAssertEqual(inline.first?.text, "Future-marked text", "Text must survive unknown mark")
        XCTAssertEqual(inline.first?.marks, [.bold, .italic], "Known marks preserved; unknown dropped")
    }

    // MARK: - Forward compatibility — unknown Block kind degrades

    func test_unknownBlockKind_withoutInlineField_collapsesToEmptyParagraph() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            { "id": "00000000-0000-0000-0000-000000000001", "type": "paragraph", "inline": [ { "text": "Before", "marks": [] } ] },
            { "id": "00000000-0000-0000-0000-000000000002", "type": "futureWidget", "config": { "anything": true } },
            { "id": "00000000-0000-0000-0000-000000000003", "type": "paragraph", "inline": [ { "text": "After", "marks": [] } ] }
          ]
        }
        """#

        let doc = try JSONDecoder().decode(
            RichTextDocument.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(doc.blocks.count, 3, "Tree structure survives the unknown block")
        guard case .paragraph(let inline) = doc.blocks[1].kind else {
            XCTFail("Unknown block must collapse to .paragraph")
            return
        }
        XCTAssertEqual(inline, [], "Unknown block with no `inline` field decodes as empty paragraph")
        guard case .paragraph(let before) = doc.blocks[0].kind,
              case .paragraph(let after) = doc.blocks[2].kind else {
            XCTFail("Surrounding paragraphs must survive")
            return
        }
        XCTAssertEqual(before.first?.text, "Before")
        XCTAssertEqual(after.first?.text, "After")
    }

    func test_unknownBlockKind_withInlineField_salvagesInlineRuns() throws {
        // Forward-compat fix C1: a v2 future block kind that happens
        // to carry an `inline` array (e.g. a callout, an admonition)
        // must hand its text to the v1 decoder so the user's words
        // survive the version downgrade.
        let json = #"""
        {
          "version": 1,
          "blocks": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "type": "calloutBlock",
              "style": "warning",
              "inline": [
                { "text": "Important ", "marks": [] },
                { "text": "warning", "marks": [ { "type": "bold" } ] }
              ]
            }
          ]
        }
        """#

        let doc = try JSONDecoder().decode(
            RichTextDocument.self,
            from: Data(json.utf8)
        )
        guard case .paragraph(let inline) = doc.blocks.first?.kind else {
            XCTFail("Unknown block with `inline` field must degrade to paragraph carrying that inline")
            return
        }
        XCTAssertEqual(inline.count, 2, "Both inline runs salvaged")
        XCTAssertEqual(inline[0].text, "Important ")
        XCTAssertEqual(inline[1].text, "warning")
        XCTAssertEqual(inline[1].marks, [.bold], "Marks on salvaged inline survive too")
    }

    func test_unknownMarkAtStartOfRun_dropped_remainderPreserved() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "type": "paragraph",
              "inline": [
                { "text": "start", "marks": [ { "type": "unobtanium" }, { "type": "bold" } ] }
              ]
            }
          ]
        }
        """#
        let doc = try JSONDecoder().decode(RichTextDocument.self, from: Data(json.utf8))
        guard case .paragraph(let inline) = doc.blocks[0].kind else { XCTFail(); return }
        XCTAssertEqual(inline.first?.text, "start")
        XCTAssertEqual(inline.first?.marks, [.bold])
    }

    func test_unknownMarkAtEndOfRun_dropped_remainderPreserved() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "type": "paragraph",
              "inline": [
                { "text": "end", "marks": [ { "type": "bold" }, { "type": "unobtanium" } ] }
              ]
            }
          ]
        }
        """#
        let doc = try JSONDecoder().decode(RichTextDocument.self, from: Data(json.utf8))
        guard case .paragraph(let inline) = doc.blocks[0].kind else { XCTFail(); return }
        XCTAssertEqual(inline.first?.text, "end")
        XCTAssertEqual(inline.first?.marks, [.bold])
    }

    func test_consecutiveUnknownMarks_bothDropped_remainderPreserved() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "type": "paragraph",
              "inline": [
                { "text": "x", "marks": [ { "type": "bold" }, { "type": "u1" }, { "type": "u2" }, { "type": "italic" } ] }
              ]
            }
          ]
        }
        """#
        let doc = try JSONDecoder().decode(RichTextDocument.self, from: Data(json.utf8))
        guard case .paragraph(let inline) = doc.blocks[0].kind else { XCTFail(); return }
        XCTAssertEqual(inline.first?.marks, [.bold, .italic])
    }

    func test_allUnknownMarks_yieldsEmptyMarksArray_textPreserved() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "type": "paragraph",
              "inline": [
                { "text": "only text survives", "marks": [ { "type": "u1" }, { "type": "u2" } ] }
              ]
            }
          ]
        }
        """#
        let doc = try JSONDecoder().decode(RichTextDocument.self, from: Data(json.utf8))
        guard case .paragraph(let inline) = doc.blocks[0].kind else { XCTFail(); return }
        XCTAssertEqual(inline.first?.text, "only text survives")
        XCTAssertEqual(inline.first?.marks, [])
    }

    // MARK: - Required field enforcement (fix C3 + missing-type)

    func test_decodingBlockWithoutID_throws() throws {
        // Forward-compat fix C3: a block without an id MUST fail to
        // decode rather than silently regenerate. Anchor stability
        // depends on it.
        let json = #"""
        {
          "version": 1,
          "blocks": [
            { "type": "paragraph", "inline": [ { "text": "no id", "marks": [] } ] }
          ]
        }
        """#
        XCTAssertThrowsError(
            try JSONDecoder().decode(RichTextDocument.self, from: Data(json.utf8)),
            "Missing block id must throw — anchor stability depends on id presence"
        )
    }

    func test_decodingBlockWithoutType_throws() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            { "id": "00000000-0000-0000-0000-000000000001", "inline": [] }
          ]
        }
        """#
        XCTAssertThrowsError(
            try JSONDecoder().decode(RichTextDocument.self, from: Data(json.utf8)),
            "Missing block type must throw — we don't know how to decode without it"
        )
    }

    // MARK: - Idempotent round-trip (canonical form check)

    func test_encodeDecodeEncode_producesByteStableOutput_underSortedKeys() throws {
        // Content hashes (PageBlock.contentHash, NotePage.extractedTextHash)
        // depend on stable encoded bytes — otherwise an idempotent
        // re-save would change the hash and trip ML cache
        // invalidation pointlessly. Verify under `.sortedKeys` so
        // dictionary ordering is deterministic.
        let original = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Title")])),
            Block(kind: .paragraph(inline: [
                Inline(text: "Plain "),
                Inline(text: "bold", marks: [.bold])
            ])),
            Block(kind: .bulletList(items: [
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "One")]))
                ]),
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Two")]))
                ])
            ])),
            Block(kind: .divider),
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quote")]))
            ]))
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let firstPass = try encoder.encode(original)
        let recovered = try JSONDecoder().decode(RichTextDocument.self, from: firstPass)
        let secondPass = try encoder.encode(recovered)

        XCTAssertEqual(
            firstPass,
            secondPass,
            "encode → decode → encode must produce byte-identical output under .sortedKeys"
        )
    }

    // MARK: - Heading level clamping

    func test_outOfRangeHeadingLevel_clampsRatherThanThrows() throws {
        let json = #"""
        {
          "version": 1,
          "blocks": [
            { "id": "00000000-0000-0000-0000-000000000001", "type": "heading", "level": 99, "inline": [ { "text": "Over", "marks": [] } ] },
            { "id": "00000000-0000-0000-0000-000000000002", "type": "heading", "level": 0, "inline": [ { "text": "Under", "marks": [] } ] }
          ]
        }
        """#

        let doc = try JSONDecoder().decode(
            RichTextDocument.self,
            from: Data(json.utf8)
        )
        guard case .heading(let highLevel, _) = doc.blocks[0].kind,
              case .heading(let lowLevel, _) = doc.blocks[1].kind else {
            XCTFail("Both should still decode as headings")
            return
        }
        XCTAssertEqual(highLevel, 3, "Over-range heading clamps to max (3)")
        XCTAssertEqual(lowLevel, 1, "Under-range heading clamps to min (1)")
    }

    // MARK: - Traversal — block(at:)

    func test_blockAt_walksTopLevelByID() throws {
        let para1ID = UUID()
        let para2ID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: para1ID, kind: .paragraph(inline: [Inline(text: "1")])),
            Block(id: para2ID, kind: .paragraph(inline: [Inline(text: "2")]))
        ])

        let found = doc.block(at: [para2ID])
        XCTAssertEqual(found?.id, para2ID)
    }

    func test_blockAt_descendsIntoBulletListItems() throws {
        let listID = UUID()
        let leafID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: listID, kind: .bulletList(items: [
                ListItem(content: [
                    Block(id: leafID, kind: .paragraph(inline: [Inline(text: "Leaf")]))
                ])
            ]))
        ])

        let found = doc.block(at: [listID, leafID])
        XCTAssertEqual(found?.id, leafID, "Path descends through bulletList to the leaf paragraph")
    }

    func test_blockAt_descendsIntoBlockquote() throws {
        let bqID = UUID()
        let innerID = UUID()
        let doc = RichTextDocument(blocks: [
            Block(id: bqID, kind: .blockquote(children: [
                Block(id: innerID, kind: .paragraph(inline: [Inline(text: "Quoted")]))
            ]))
        ])

        let found = doc.block(at: [bqID, innerID])
        XCTAssertEqual(found?.id, innerID)
    }

    func test_blockAt_returnsNil_forMissingPath() throws {
        let doc = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "x")]))
        ])
        XCTAssertNil(doc.block(at: [UUID()]), "Non-existent ID returns nil")
        XCTAssertNil(doc.block(at: []), "Empty path returns nil")
    }

    // MARK: - joinedInlineText

    func test_joinedInlineText_concatenatesParagraphRuns() {
        let block = Block(kind: .paragraph(inline: [
            Inline(text: "Hello "),
            Inline(text: "world"),
            Inline(text: "!")
        ]))
        XCTAssertEqual(block.joinedInlineText, "Hello world!")
    }

    func test_joinedInlineText_returnsCodeBlockTextDirectly() {
        let block = Block(kind: .codeBlock(text: "let x = 1", languageHint: "swift"))
        XCTAssertEqual(block.joinedInlineText, "let x = 1")
    }

    func test_joinedInlineText_returnsNilForContainerAndDivider() {
        let bulletList = Block(kind: .bulletList(items: []))
        let orderedList = Block(kind: .orderedList(items: []))
        let blockquote = Block(kind: .blockquote(children: []))
        let divider = Block(kind: .divider)
        XCTAssertNil(bulletList.joinedInlineText)
        XCTAssertNil(orderedList.joinedInlineText)
        XCTAssertNil(blockquote.joinedInlineText)
        XCTAssertNil(divider.joinedInlineText)
    }

    // MARK: - plainText composition

    func test_plainText_flattensDocument_inReadingOrder() {
        let doc = RichTextDocument(blocks: [
            Block(kind: .heading(level: 1, inline: [Inline(text: "Title")])),
            Block(kind: .paragraph(inline: [
                Inline(text: "Para "),
                Inline(text: "bold", marks: [.bold])
            ])),
            Block(kind: .bulletList(items: [
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Item 1")]))
                ]),
                ListItem(content: [
                    Block(kind: .paragraph(inline: [Inline(text: "Item 2")]))
                ])
            ])),
            Block(kind: .blockquote(children: [
                Block(kind: .paragraph(inline: [Inline(text: "Quote")]))
            ])),
            Block(kind: .codeBlock(text: "let x = 1", languageHint: nil))
        ])

        let expected = """
            Title
            Para bold
            Item 1
            Item 2
            Quote
            let x = 1
            """
        XCTAssertEqual(doc.plainText, expected)
    }

    // MARK: - Helpers

    private static func roundTrip(_ doc: RichTextDocument) throws -> RichTextDocument {
        let data = try JSONEncoder().encode(doc)
        return try JSONDecoder().decode(RichTextDocument.self, from: data)
    }
}
