import XCTest
import OCamlDemo

@MainActor
final class OCamlDemoTests: XCTestCase {
    func testStoreLoadsSnapshotThroughSingleCall() {
        let transport = FakeTransport(
            responses: [
                """
                {
                  "apiVersion": 1,
                  "ok": true,
                  "result": {
                    "revision": 0,
                    "screen": "counter",
                    "count": 0
                  },
                  "error": null
                }
                """
            ]
        )
        let store = OCamlDemoStore(call: transport.call)

        store.load(.counter)

        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual(0, store.snapshot?.count)
        XCTAssertEqual(1, transport.requests.count)
        XCTAssertTrue(transport.requests[0].contains(#""method":"snapshot""#))
        XCTAssertTrue(transport.requests[0].contains(#""screen":"counter""#))
    }

    func testStoreDispatchesTypedActionAndAcceptsUpdatedSnapshot() {
        let transport = FakeTransport(
            responses: [
                """
                {
                  "apiVersion": 1,
                  "ok": true,
                  "result": {
                    "revision": 1,
                    "screen": "counter",
                    "count": 1
                  },
                  "error": null
                }
                """
            ]
        )
        let store = OCamlDemoStore(call: transport.call)

        store.dispatch(screen: .counter, action: "increment")

        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual(1, store.snapshot?.count)
        XCTAssertTrue(transport.requests[0].contains(#""method":"dispatch""#))
        XCTAssertTrue(transport.requests[0].contains(#""action":"increment""#))
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

        store.dispatch(screen: .counter, action: "explode")

        XCTAssertEqual("unknown_action", store.lastError?.code)
        XCTAssertNil(store.snapshot)
    }

    func testStoreDecodesTodoAndSearchBusinessData() {
        let todoJSON =
            """
            {
              "apiVersion": 1,
              "ok": true,
              "result": {
                "revision": 2,
                "screen": "todo",
                "draft": "",
                "items": [
                  {"id": 1, "title": "Shared OCaml", "completed": false}
                ]
              },
              "error": null
            }
            """
        let searchJSON =
            """
            {
              "apiVersion": 1,
              "ok": true,
              "result": {
                "revision": 3,
                "screen": "search",
                "query": "t",
                "results": ["Today", "Tasks", "Settings", "Projects"]
              },
              "error": null
            }
            """
        let transport = FakeTransport(responses: [todoJSON, searchJSON])
        let store = OCamlDemoStore(call: transport.call)

        store.load(.todo)
        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual("Shared OCaml", store.snapshot?.items?[0].title)
        store.load(.search)
        XCTAssertNil(store.lastError, store.lastError?.message ?? "")
        XCTAssertEqual(["Today", "Tasks", "Settings", "Projects"], store.snapshot?.results)
    }

    func testSharedSwiftUIRootCanBeConstructed() {
        _ = OCamlDemoView { _ in
            """
            {
              "apiVersion": 1,
              "ok": true,
              "result": {
                "revision": 0,
                "screen": "counter",
                "count": 0
              },
              "error": null
            }
            """
        }
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
