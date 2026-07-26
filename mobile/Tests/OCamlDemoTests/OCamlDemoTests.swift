import XCTest
import OCamlDemo

@MainActor
final class OCamlDemoTests: XCTestCase {
    func testScreenNavigationTitles() {
        XCTAssertEqual("Journals", OCamlDemoScreen.journal.navigationTitle)
        XCTAssertEqual("Tasks", OCamlDemoScreen.tasks.navigationTitle)
    }

    func testStoreLoadsJournalListThroughSingleCall() {
        let transport = FakeTransport(
            responses: [
                """
                {
                  "apiVersion": 1,
                  "ok": true,
                  "result": {
                    "revision": 0,
                    "screen": "journal",
                    "selectedJournalId": 1,
                    "journals": [{"id": 1, "title": "2026-07-26"}]
                  },
                  "error": null
                }
                """
            ]
        )
        let store = OCamlDemoStore(call: transport.call)

        store.load(.journal)

        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual("2026-07-26", store.snapshot?.journals?[0].title)
        XCTAssertEqual(1, transport.requests.count)
        XCTAssertTrue(transport.requests[0].contains(#""method":"snapshot""#))
        XCTAssertTrue(transport.requests[0].contains(#""screen":"journal""#))
    }

    func testStoreDecodesOutlinerBlocks() {
        let transport = FakeTransport(
            responses: [
                """
                {
                  "apiVersion": 1,
                  "ok": true,
                  "result": {
                    "revision": 2,
                    "screen": "outliner",
                    "blocks": [
                      {"id": 1, "content": "Parent", "depth": 0},
                      {"id": 2, "content": "Child", "depth": 1}
                    ]
                  },
                  "error": null
                }
                """
            ]
        )
        let store = OCamlDemoStore(call: transport.call)

        store.load(.outliner)

        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual("Child", store.snapshot?.blocks?[1].content)
        XCTAssertEqual(1, store.snapshot?.blocks?[1].depth)
    }

    func testStoreDispatchesStructuredOutlinerPayload() {
        let transport = FakeTransport(
            responses: [
                """
                {
                  "apiVersion": 1,
                  "ok": true,
                  "result": {
                    "revision": 3,
                    "screen": "outliner",
                    "blocks": [{"id": 1, "content": "中文 block 🚀", "depth": 0}]
                  },
                  "error": null
                }
                """
            ]
        )
        let store = OCamlDemoStore(call: transport.call)

        store.dispatch(
            screen: .outliner,
            action: "setContent",
            payload: #"{"id":1,"content":"中文 block 🚀"}"#
        )

        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual("中文 block 🚀", store.snapshot?.blocks?[0].content)
        XCTAssertTrue(transport.requests[0].contains(#""action":"setContent""#))
    }

    func testStoreDispatchesIndentAndOutdentWithBlockID() {
        let response =
            """
            {
              "apiVersion": 1,
              "ok": true,
              "result": {
                "revision": 4,
                "screen": "outliner",
                "blocks": [{"id": 7, "content": "Block", "depth": 1}]
              },
              "error": null
            }
            """
        let transport = FakeTransport(responses: [response, response])
        let store = OCamlDemoStore(call: transport.call)
        let payload = #"{"id":7}"#

        store.dispatch(screen: .outliner, action: "indent", payload: payload)
        store.dispatch(screen: .outliner, action: "outdent", payload: payload)

        XCTAssertEqual(2, transport.requests.count)
        XCTAssertTrue(transport.requests[0].contains(#""action":"indent""#))
        XCTAssertTrue(transport.requests[0].contains(#"\"id\":7"#))
        XCTAssertTrue(transport.requests[1].contains(#""action":"outdent""#))
        XCTAssertTrue(transport.requests[1].contains(#"\"id\":7"#))
    }

    func testStorePublishesStructuredCoreError() {
        let transport = FakeTransport(
            responses: [
                """
                {
                  "apiVersion": 1,
                  "ok": false,
                  "result": null,
                  "error": {
                    "code": "unknown_action",
                    "message": "unknown action: explode"
                  }
                }
                """
            ]
        )
        let store = OCamlDemoStore(call: transport.call)

        store.dispatch(screen: .tasks, action: "explode")

        XCTAssertEqual("unknown_action", store.lastError?.code)
        XCTAssertNil(store.snapshot)
    }

    func testSharedSwiftUIRootCanBeConstructed() {
        let call: (String) -> String = { _ in
            """
            {
              "apiVersion": 1,
              "ok": true,
              "result": {
                "revision": 0,
                "screen": "tasks",
                "draft": "",
                "items": []
              },
              "error": null
            }
            """
        }
        _ = OCamlDemoView(call: call, databasePath: nil)
    }
}

private final class FakeTransport {
    private var responses: [String]
    private(set) var requests: [String] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func call(_ request: String) -> String {
        requests.append(request)
        return responses.removeFirst()
    }
}
