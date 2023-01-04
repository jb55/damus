//
//  EventView.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import SwiftUI

enum Highlight {
    case none
    case main
    case reply
    case custom(Color, Float)

    var is_main: Bool {
        if case .main = self {
            return true
        }
        return false
    }

    var is_none: Bool {
        if case .none = self {
            return true
        }
        return false
    }

    var is_replied_to: Bool {
        switch self {
        case .reply: return true
        default: return false
        }
    }
}

enum EventViewKind {
    case small
    case normal
    case big
    case selected
}

func eventviewsize_to_font(_ size: EventViewKind) -> Font {
    switch size {
    case .small:
        return .body
    case .normal:
        return .body
    case .big:
        return .headline
    case .selected:
        return .custom("selected", size: 21.0)
    }
}

struct BuilderEventView: View {
    let damus: DamusState
    let event_id: String
    @State var event: NostrEvent?
    @State var subscription_uuid: String = UUID().description
    
    func unsubscribe() {
        damus.pool.unsubscribe(sub_id: subscription_uuid)
    }
    
    func subscribe(filters: [NostrFilter]) {
        damus.pool.register_handler(sub_id: subscription_uuid, handler: handle_event)
        damus.pool.send(.subscribe(.init(filters: filters, sub_id: subscription_uuid)))
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nostr_response) = ev else {
            return
        }
        
        guard case .event(let id, let nostr_event) = nostr_response else {
            return
        }
        
        // Is current event
        if id == subscription_uuid {
            if event != nil {
                return
            }
            
            event = nostr_event
            
            unsubscribe()
        }
    }
    
    func load() {
        subscribe(filters: [
            NostrFilter(
                ids: [self.event_id],
                limit: 1
            )
        ])
    }
    
    var body: some View {
        VStack {
            if let event = event {
                let ev = event.inner_event ?? event
                NavigationLink(destination: BuildThreadV2View(damus: damus, event_id: ev.id)) {
                    EventView(damus: damus, event: event, show_friend_icon: true, size: .small)
                }.buttonStyle(.plain)
            } else {
                ProgressView().padding()
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .border(Color.gray.opacity(0.2), width: 1)
        .cornerRadius(2)
        .onAppear {
            self.load()
        }
    }
}

enum PollResultsDisplay {
    case none
    case friends
    case everyone
}

struct EventView: View {
    let event: NostrEvent
    let highlight: Highlight
    let has_action_bar: Bool
    let damus: DamusState
    let pubkey: String
    let show_friend_icon: Bool
    let size: EventViewKind

    @EnvironmentObject var action_bar: ActionBarModel
    
    @State var show_poll_results: Bool = false
    @State var subscription_poll_uuid: String = UUID().description
    
    // String = user pubkey and int is the choice
    @State var choices: [(String, Int)] = []
    
    @AppStorage("poll_results_everyone") var poll_results_everyone: Bool = false

    init(event: NostrEvent, highlight: Highlight, has_action_bar: Bool, damus: DamusState, show_friend_icon: Bool, size: EventViewKind = .normal) {
        self.event = event
        self.highlight = highlight
        self.has_action_bar = has_action_bar
        self.damus = damus
        self.pubkey = event.pubkey
        self.show_friend_icon = show_friend_icon
        self.size = size
    }

    init(damus: DamusState, event: NostrEvent, show_friend_icon: Bool, size: EventViewKind = .normal) {
        self.event = event
        self.highlight = .none
        self.has_action_bar = false
        self.damus = damus
        self.pubkey = event.pubkey
        self.show_friend_icon = show_friend_icon
        self.size = size
    }

    init(damus: DamusState, event: NostrEvent, pubkey: String, show_friend_icon: Bool, size: EventViewKind = .normal, embedded: Bool = false) {
        self.event = event
        self.highlight = .none
        self.has_action_bar = false
        self.damus = damus
        self.pubkey = pubkey
        self.show_friend_icon = show_friend_icon
        self.size = size
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nostr_response) = ev else {
            return
        }
        
        guard case .event(let id, let nostr_event) = nostr_response else {
            return
        }
        
        // Is current event
        if id == subscription_poll_uuid {
            if nostr_event.kind != 7 {
                return
            }
            
            // If the pubkey is our, display the results
            if nostr_event.pubkey == damus.pubkey {
                show_poll_results = true
            }
            
            // Check if the choice is already submitted by the pubkey
            if choices.contains(where: { $0.0 == nostr_event.pubkey }) {
                return
            }
            
            // Check the choice
            if let match = nostr_event.content.range(of: "^p:([0-9]+)$", options: .regularExpression) {
                let digit = Int(String(nostr_event.content[match]).replacingOccurrences(of: "p:", with: ""))!
                
                choices.append((nostr_event.pubkey, digit))
            }
        }
    }
    
    func unsubscribe_poll() {
        damus.pool.unsubscribe(sub_id: subscription_poll_uuid)
    }
    
    func subscribe_poll() {
        let filters: [NostrFilter] = [
            NostrFilter(
                kinds: [7],
                referenced_ids: [event.id]
            )
        ]
        
        damus.pool.register_handler(sub_id: subscription_poll_uuid, handler: handle_event)
        damus.pool.send(.subscribe(.init(filters: filters, sub_id: subscription_poll_uuid)))
    }

    var body: some View {
        return Group {
            if event.known_kind == .boost, let inner_ev = event.inner_event {
                VStack(alignment: .leading) {
                    let prof_model = ProfileModel(pubkey: event.pubkey, damus: damus)
                    let follow_model = FollowersModel(damus_state: damus, target: event.pubkey)
                    let prof = damus.profiles.lookup(id: event.pubkey)
                    let booster_profile = ProfileView(damus_state: damus, profile: prof_model, followers: follow_model)
                    
                    NavigationLink(destination: booster_profile) {
                        HStack {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.footnote.weight(.bold))
                                .foregroundColor(Color.gray)
                            ProfileName(pubkey: event.pubkey, profile: prof, contacts: damus.contacts, show_friend_confirmed: true)
                                    .font(.footnote.weight(.bold))
                                    .foregroundColor(Color.gray)
                            Text("Boosted")
                                .font(.footnote.weight(.bold))
                                .foregroundColor(Color.gray)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    TextEvent(inner_ev, pubkey: inner_ev.pubkey)
                        .padding([.top], 1)
                }
            } else {
                TextEvent(event, pubkey: pubkey)
                    .padding([.top], 6)
            }
        }
    }

    func TextEvent(_ event: NostrEvent, pubkey: String) -> some View {
        let content = event.get_content(damus.keypair.privkey)
        
        let poll_choices = event.tags.filter { value in
            return value.count >= 2 && value[0] == "poll" && !value[1].isEmpty
        }.prefix(4).map { value in
            return value[1]
        }
        
        return HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)
            
            if size != .selected {
                VStack {
                    let pmodel = ProfileModel(pubkey: pubkey, damus: damus)
                    let pv = ProfileView(damus_state: damus, profile: pmodel, followers: FollowersModel(damus_state: damus, target: pubkey))
                    
                    NavigationLink(destination: pv) {
                        ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: highlight, profiles: damus.profiles)
                    }
                    
                    Spacer()
                }
            }

            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    if size == .selected {
                        VStack {
                            let pmodel = ProfileModel(pubkey: pubkey, damus: damus)
                            let pv = ProfileView(damus_state: damus, profile: pmodel, followers: FollowersModel(damus_state: damus, target: pubkey))
                            
                            NavigationLink(destination: pv) {
                                ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: highlight, profiles: damus.profiles)
                            }
                        }
                    }
                    
                    EventProfileName(pubkey: pubkey, profile: profile, contacts: damus.contacts, show_friend_confirmed: show_friend_icon, size: size)
                    if size != .selected {
                        Text("\(format_relative_time(event.created_at))")
                            .font(eventviewsize_to_font(size))
                            .foregroundColor(.gray)
                    }
                }
                
                if event.is_reply(damus.keypair.privkey) {
                    Text("\(reply_desc(profiles: damus.profiles, event: event))")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let should_show_img = should_show_images(contacts: damus.contacts, ev: event, our_pubkey: damus.pubkey)
                
                NoteContentView(privkey: damus.keypair.privkey, event: event, profiles: damus.profiles, previews: damus.previews, show_images: should_show_img, artifacts: .just_content(content), size: self.size)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // MARK: - Poll
                if poll_choices.count >= 2 {
                    let filtered_choices = choices.filter({ poll_results_everyone ? true : damus.contacts.is_in_friendosphere($0.0) })
                    let total_count = filtered_choices.count == 0 ? 1 : filtered_choices.count
                    
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(0 ..< poll_choices.count, id: \.self) { index in
                            let this_choice_count = filtered_choices.filter({ $0.1 == index }).count
                            let percent = CGFloat(this_choice_count) / CGFloat(total_count)
                            
                            HStack {
                                if show_poll_results {
                                    /// Placeholder text for the size
                                    Text("100%")
                                        .font(.caption)
                                        .opacity(0)
                                        .overlay {
                                            Text("\(Int(floor(percent * 100)))%")
                                                .font(.caption)
                                        }
                                }
                                
                                HStack {
                                    Button {
                                        if !show_poll_results {
                                            send_poll_choice(index)
                                            show_poll_results = true
                                        }
                                    } label: {
                                        Text(poll_choices[index])
                                            .font(.caption)
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                                .padding(12)
                                    }
                                }
                                .background(alignment: .leading) {
                                    GeometryReader { geometry in
                                        withAnimation {
                                            Rectangle()
                                                .foregroundColor(.accentColor.opacity(0.2))
                                                .frame(
                                                    minWidth: 0,
                                                    maxWidth: show_poll_results
                                                        ? percent * geometry.size.width
                                                    : 0
                                                )
                                        }
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                                )
                                .cornerRadius(10)
                            }
                        }
                        
                        if !show_poll_results {
                            Button {
                                show_poll_results = true
                            } label: {
                                Label("Show result", systemImage: "number.circle")
                                    .font(.caption)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                        .padding(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                                        )
                                        .cornerRadius(10)
                            }
                        }
                        
                        Text("\(filtered_choices.count) vote\(filtered_choices.count >= 2 ? "s" : "")\(poll_results_everyone ? "" : " - close circle of friends votes only")")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                    )
                    .cornerRadius(10)
                    .onAppear {
                        subscribe_poll()
                    }
                    .onDisappear {
                        unsubscribe_poll()
                    }
                }
                
                // MARK: - Action bar
                if has_action_bar {
                    if size == .selected {
                        Text("\(format_date(event.created_at))")
                            .padding(.top, 10)
                            .font(.footnote)
                            .foregroundColor(.gray)
                        
                        Divider()
                            .padding([.bottom], 4)
                    } else {
                        Rectangle().frame(height: 2).opacity(0)
                    }
                    
                    let bar = make_actionbar_model(ev: event, damus: damus)
                    EventActionBar(damus_state: damus, event: event, bar: bar)
                }

                Divider()
                    .padding([.top], 4)
            }
            .padding([.leading], 2)
        }
        .contentShape(Rectangle())
        .background(event_validity_color(event.validity))
        .id(event.id)
        .frame(maxWidth: .infinity, minHeight: PFP_SIZE)
        .padding([.bottom], 2)
        .event_context_menu(event, privkey: damus.keypair.privkey)
    }
    
    func send_poll_choice(_ choice: Int) {
        guard let privkey = damus.keypair.privkey else {
            return
        }
        
        let choice_ev = make_poll_choice_event(pubkey: damus.pubkey, privkey: privkey, event: event, choice_index: choice)
        
        damus.pool.send(.event(choice_ev))
    }
}

// blame the porn bots for this code
func should_show_images(contacts: Contacts, ev: NostrEvent, our_pubkey: String) -> Bool {
    if ev.pubkey == our_pubkey {
        return true
    }
    if contacts.is_in_friendosphere(ev.pubkey) {
        return true
    }
    return false
}

func event_validity_color(_ validation: ValidationResult) -> some View {
    Group {
        switch validation {
        case .ok:
            EmptyView()
        case .bad_id:
            Color.orange.opacity(0.4)
        case .bad_sig:
            Color.red.opacity(0.4)
        }
    }
}

extension View {
    func pubkey_context_menu(bech32_pubkey: String) -> some View {
        return self.contextMenu {
            Button {
                    UIPasteboard.general.string = bech32_pubkey
            } label: {
                Label("Copy Account ID", systemImage: "doc.on.doc")
            }
        }
    }
    
    func event_context_menu(_ event: NostrEvent, privkey: String?) -> some View {
        return self.contextMenu {
            Button {
                UIPasteboard.general.string = event.get_content(privkey)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = bech32_pubkey(event.pubkey) ?? event.pubkey
            } label: {
                Label("Copy User ID", systemImage: "tag")
            }

            Button {
                UIPasteboard.general.string = bech32_note_id(event.id) ?? event.id
            } label: {
                Label("Copy Note ID", systemImage: "tag")
            }

            Button {
                UIPasteboard.general.string = event_to_json(ev: event)
            } label: {
                Label("Copy Note JSON", systemImage: "note")
            }

            Button {
                NotificationCenter.default.post(name: .broadcast_event, object: event)
            } label: {
                Label("Broadcast", systemImage: "globe")
            }
        }

    }
}

func format_relative_time(_ created_at: Int64) -> String
{
    return time_ago_since(Date(timeIntervalSince1970: Double(created_at)))
}

func format_date(_ created_at: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(created_at))
    let dateFormatter = DateFormatter()
    dateFormatter.timeStyle = .short
    dateFormatter.dateStyle = .short
    return dateFormatter.string(from: date)
}


func reply_desc(profiles: Profiles, event: NostrEvent) -> String {
    let desc = make_reply_description(event.tags)
    let pubkeys = desc.pubkeys
    let n = desc.others

    if desc.pubkeys.count == 0 {
        return NSLocalizedString("Reply to self", comment: "Label to indicate that the user is replying to themself.")
    }

    let names: [String] = pubkeys.map {
        let prof = profiles.lookup(id: $0)
        return Profile.displayName(profile: prof, pubkey: $0)
    }

    if names.count == 2 {
        if n > 2 {
            let othersCount = n - pubkeys.count
            return String(format: NSLocalizedString("replying_to_two_and_others", comment: "Label to indicate that the user is replying to 2 users and others."), othersCount, names[0], names[1])
        }
        return String.localizedStringWithFormat("Replying to %@ & %@", names[0], names[1])
    }

    let othersCount = n - pubkeys.count
    return String(format: NSLocalizedString("replying_to_one_and_others", comment: "Label to indicate that the user is replying to 1 user and others."), othersCount, names[0])
}



func make_actionbar_model(ev: NostrEvent, damus: DamusState) -> ActionBarModel {
    let likes = damus.likes.counts[ev.id]
    let boosts = damus.boosts.counts[ev.id]
    let tips = damus.tips.tips[ev.id]
    let our_like = damus.likes.our_events[ev.id]
    let our_boost = damus.boosts.our_events[ev.id]
    let our_tip = damus.tips.our_tips[ev.id]

    return ActionBarModel(likes: likes ?? 0,
                          boosts: boosts ?? 0,
                          tips: tips ?? 0,
                          our_like: our_like,
                          our_boost: our_boost,
                          our_tip: our_tip
    )
}


struct EventView_Previews: PreviewProvider {
    static var previews: some View {
        EventView(
            event: NostrEvent(
                content: "jb55.com/red-me.jb55 cool",
                pubkey: "pk",
                tags: [["random", "kind"], ["poll", "yes"], ["poll", "no"]],
                createdAt: Int64(Date().timeIntervalSince1970 - 100)
            ),
            highlight: .none,
            has_action_bar: true,
            damus: test_damus_state(),
            show_friend_icon: true,
            size: .selected
        )
        
        VStack {
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .small)
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .normal)
            EventView(damus: test_damus_state(), event: NostrEvent(content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool", pubkey: "pk"), show_friend_icon: true, size: .big)
            
            EventView(
                event: NostrEvent(
                    content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool",
                    pubkey: "pk",
                    createdAt: Int64(Date().timeIntervalSince1970 - 100)
                ),
                highlight: .none,
                has_action_bar: true,
                damus: test_damus_state(),
                show_friend_icon: true,
                size: .selected
            )
        }
    }
}
