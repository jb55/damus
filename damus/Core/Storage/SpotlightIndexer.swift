//
//  SpotlightIndexer.swift
//  damus
//
//  Created by William Casarin on 2026-09-29.
//

import CoreSpotlight
import Kingfisher
import UniformTypeIdentifiers

/// Mirrors the profiles we follow into the on-device Spotlight index, so they
/// show up when searching from the home screen.
///
/// Spotlight never calls into the app while the user types; it only searches
/// what we donated ahead of time. The follow list is small and bounded, so we
/// simply replace the whole set whenever the contact list changes.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    /// Spotlight domain grouping every followed-profile item, so they can be
    /// replaced or removed together.
    nonisolated static let profiles_domain = "profiles"

    /// Largest cached avatar we'll hand to Spotlight as a thumbnail.
    nonisolated static let max_thumbnail_bytes = 512 * 1024

    /// Coalesces bursts of contact updates. The contact event is set before the
    /// friend set is rebuilt from it, so this also lets that settle first.
    private let debouncer = Debouncer(interval: 5)

    /// Schedules a re-index of the followed profiles after contact updates settle.
    func schedule_index(state: DamusState) {
        debouncer.debounce { [weak self, weak state] in
            guard let self, let state else { return }
            Task { await self.index_followed_profiles(state: state) }
        }
    }

    /// Replaces the Spotlight profile items with the profiles we currently follow.
    ///
    /// Followed pubkeys with no profile in nostrdb yet are skipped; they are
    /// picked up on the next re-index.
    func index_followed_profiles(state: DamusState) async {
        let pubkeys = state.contacts.get_friend_list()
        guard !pubkeys.isEmpty else { return }
        let profiles = state.profiles

        await Task.detached(priority: .utility) {
            await replace_indexed_profiles(pubkeys: pubkeys, profiles: profiles)
        }.value
    }

    /// Removes everything we donated to Spotlight, e.g. on logout.
    func clear() {
        debouncer.cancel()
        CSSearchableIndex.default().deleteAllSearchableItems()
    }
}

/// Looks up each followed profile in nostrdb and swaps them in as the
/// Spotlight profile items. Runs off the main actor.
private func replace_indexed_profiles(pubkeys: Set<Pubkey>, profiles: Profiles) async {
    let items = pubkeys.compactMap { pubkey -> CSSearchableItem? in
        guard let profile = try? profiles.lookup(id: pubkey) else { return nil }
        return spotlight_profile_item(pubkey: pubkey, profile: profile, thumbnail: cached_avatar_data(profile: profile))
    }

    let index = CSSearchableIndex.default()
    do {
        try await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndexer.profiles_domain])
        try await index.indexSearchableItems(items)
        Log.info("Spotlight: indexed %d followed profiles", for: .storage, items.count)
    } catch {
        Log.error("Spotlight: failed to index followed profiles: %{public}@", for: .storage, error.localizedDescription)
    }
}

/// Builds the Spotlight item for a followed profile.
///
/// The item's identifier is the pubkey hex, which ``pubkey_from_spotlight_identifier(_:)``
/// turns back into a pubkey when the user taps the result.
func spotlight_profile_item(pubkey: Pubkey, profile: Profile, thumbnail: Data?) -> CSSearchableItem {
    let display_name = DisplayName(profile: profile, pubkey: pubkey)

    let attrs = CSSearchableItemAttributeSet(contentType: .contact)
    attrs.title = display_name.displayName
    attrs.displayName = display_name.displayName
    attrs.contentDescription = profile.about.map { String($0.prefix(300)) }
    attrs.alternateNames = [profile.name, profile.display_name, profile.nip05].compactMap { $0 }
    attrs.keywords = [profile.name, profile.display_name, profile.nip05, pubkey.npub].compactMap { $0 }
    attrs.thumbnailData = thumbnail

    return CSSearchableItem(uniqueIdentifier: pubkey.hex(), domainIdentifier: SpotlightIndexer.profiles_domain, attributeSet: attrs)
}

/// The pubkey a tapped Spotlight profile item refers to.
func pubkey_from_spotlight_identifier(_ identifier: String) -> Pubkey? {
    Pubkey(hex: identifier)
}

/// The profile's avatar straight from the Kingfisher disk cache, if it is there
/// and small enough. Never touches the network.
private func cached_avatar_data(profile: Profile) -> Data? {
    guard let picture = profile.picture else { return nil }
    let cache = KingfisherManager.shared.cache
    guard cache.diskStorage.isCached(forKey: picture) else { return nil }
    let path = cache.cachePath(forKey: picture)
    guard let data = FileManager.default.contents(atPath: path),
          data.count <= SpotlightIndexer.max_thumbnail_bytes
    else { return nil }
    return data
}
