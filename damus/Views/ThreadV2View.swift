//
//  ThreadV2View.swift
//  damus
//
//  Created by Thomas Tastet on 25/12/2022.
//

import SwiftUI

struct ThreadV2 {
    var parentEvents: [NostrEvent]
    var current: NostrEvent
    var childEvents: [NostrEvent]
}

//class ThreadV2: ObservableObject {
//    @Published var initial_event: NostrEvent
//    @Published var parentEvents: [NostrEvent]
//    @Published var current: NostrEvent
//    @Published var childEvents: [NostrEvent]
//    @Published var loading: Bool = false
//
//    let damus_state: DamusState
//
//    init(initial_event: NostrEvent, damus_state: DamusState) {
//        self.damus_state = damus_state
//        self.initial_event = initial_event
//    }
//}

struct BuildThreadV2View: View {
    let damus: DamusState
    
    @State var parents_ids: [String]
    let event_id: String
    
    @State var current_event: NostrEvent? = nil
    
    @State var thread: ThreadV2?
    
    init(damus: DamusState, event_id: String, thread: ThreadV2? = nil) {
        self.damus = damus
        self.event_id = event_id
        self.thread = thread
        self.parents_ids = []
    }
    
    let current_events_uuid = UUID().description
    let parents_events_uuid = UUID().description
    let childs_events_uuid = UUID().description
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nostr_response) = ev else {
            return
        }
        
        guard case .event(_, let nostr_event) = nostr_response else {
            return
        }
        
        // Is current event
        if nostr_event.id == event_id {
            if current_event != nil {
                return
            }
            
            current_event = nostr_event
            
            thread = ThreadV2(
                parentEvents: [],
                current: current_event!,
                childEvents: []
            )
            
            // Get parents
            parents_ids = current_event!.tags.filter { tag in
              return tag.count == 2 && tag[0] == "e"
            }.map { tag in
              return tag[1]
            }
            
            // Ask for parents
            var parents_events = NostrFilter(
                ids: parents_ids,
                limit: UInt32(parents_ids.count)
            )
            damus.pool.send(.subscribe(.init(filters: [parents_events], sub_id: parents_events_uuid)))
            
            // Ask for children
            var childs_events = NostrFilter(
                referenced_ids: [self.event_id],
                limit: 50
            )
            damus.pool.send(.subscribe(.init(filters: [childs_events], sub_id: childs_events_uuid)))
            
            return
        }
        
        print("event!")
        print(nostr_event.description)
    }

    
    func reload() {
        damus.pool.register_handler(sub_id: current_events_uuid, handler: handle_event)
        
        // Get the current event
        print("subscribing to threadV2 \(event_id) with sub_id \(current_events_uuid)")
        let current_events = NostrFilter(
            ids: [self.event_id],
            limit: 1
        )
        damus.pool.send(.subscribe(.init(filters: [current_events], sub_id: current_events_uuid)))
    }
    
    var body: some View {
        if thread == nil {
            ProgressView()
                .onAppear {
                    if self.thread == nil {
                        self.reload()
                    }
                }
        } else {
            ThreadV2View(damus: damus, thread: thread!)
        }
    }
}

struct ThreadV2View: View {
    let damus: DamusState
    let thread: ThreadV2
    
    var body: some View {
        ScrollView {
            VStack {
                // MARK: - Parents events view
                VStack {
                    ForEach(thread.parentEvents, id: \.id) { event in
                        EventView(
                            event: event,
                            highlight: .none,
                            has_action_bar: true,
                            damus: damus,
                            show_friend_icon: true, // TODO: change it
                            size: .small
                        )
                    }
                }.background(GeometryReader { geometry in
                    // get the height and width of the EventView view
                    let eventHeight = geometry.frame(in: .global).height
//                    let eventWidth = geometry.frame(in: .global).width

                    // vertical gray line in the background
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 2, height: eventHeight)
                        .offset(x: 25, y: 40)
                })
                
                // MARK: - Actual event view
                EventView(
                    event: thread.current,
                    highlight: .none,
                    has_action_bar: true,
                    damus: damus,
                    show_friend_icon: true, // TODO: change it
                    size: .selected
                )
                
                // MARK: - Responses of the actual event view
                ForEach(thread.childEvents, id: \.id) { event in
                    EventView(
                        event: event,
                        highlight: .none,
                        has_action_bar: true,
                        damus: damus,
                        show_friend_icon: true, // TODO: change it
                        size: .small
                    )
                }
            }
        }.padding().navigationBarTitle("Thread")
    }
}

struct ThreadV2View_Previews: PreviewProvider {
    static var previews: some View {
        BuildThreadV2View(damus: test_damus_state(), event_id: "ac9fd97b53b0c1d22b3aea2a3d62e11ae393960f5f91ee1791987d60151339a7")
        ThreadV2View(
            damus: test_damus_state(),
            thread: ThreadV2(
                parentEvents: [
                    NostrEvent(id: "1", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                    NostrEvent(id: "2", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                    NostrEvent(id: "3", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                ],
                current: NostrEvent(id: "4", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                childEvents: [
                    NostrEvent(id: "5", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                    NostrEvent(id: "6", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                ]
            )
        )
    }
}
