//
//  SpotlightIndexerTests.swift
//  damusTests
//
//  Created by William Casarin on 2026-09-29.
//

import XCTest
import CoreSpotlight
@testable import damus

final class SpotlightIndexerTests: XCTestCase {

    /// A followed profile becomes a Spotlight item whose searchable fields cover
    /// every name a user might type, and whose identifier maps back to the pubkey.
    func testProfileItemFields() {
        let profile = make_test_profile()
        let item = spotlight_profile_item(pubkey: test_pubkey, profile: profile, thumbnail: nil)

        XCTAssertEqual(item.domainIdentifier, SpotlightIndexer.profiles_domain)
        XCTAssertEqual(item.attributeSet.title, "Will")
        XCTAssertEqual(item.attributeSet.contentDescription, "Its a me")
        XCTAssertEqual(item.attributeSet.alternateNames, ["jb55", "Will", "jb55@jb55.com"])
        XCTAssertEqual(item.attributeSet.keywords, ["jb55", "Will", "jb55@jb55.com", test_pubkey.npub])
        XCTAssertEqual(pubkey_from_spotlight_identifier(item.uniqueIdentifier), test_pubkey)
    }

    /// Long bios are truncated so we don't stuff whole essays into the index.
    func testProfileItemTruncatesAbout() {
        let profile = Profile(name: "jb55", display_name: nil, about: String(repeating: "a", count: 1000), picture: nil, banner: nil, website: nil, lud06: nil, lud16: nil, nip05: nil, damus_donation: nil)
        let item = spotlight_profile_item(pubkey: test_pubkey, profile: profile, thumbnail: nil)

        XCTAssertEqual(item.attributeSet.contentDescription?.count, 300)
    }

    /// Identifiers that aren't pubkey hex don't route anywhere.
    func testInvalidIdentifier() {
        XCTAssertNil(pubkey_from_spotlight_identifier("not a pubkey"))
    }
}
