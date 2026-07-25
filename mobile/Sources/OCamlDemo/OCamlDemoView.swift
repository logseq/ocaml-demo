import SwiftUI

public struct OCamlDemoView: View {
    @State private var store: OCamlDemoStore
    @State private var selectedScreen = OCamlDemoScreen.counter

    public init(call: @escaping (String) -> String) {
        store = OCamlDemoStore(call: call)
    }

    public var body: some View {
        TabView(selection: $selectedScreen) {
            NavigationStack {
                CounterScreen(store: store)
                    .navigationTitle("Counter")
            }
            .tabItem {
                Text("Counter")
                    .accessibilityIdentifier("tab.counter")
            }
            .tag(OCamlDemoScreen.counter)

            NavigationStack {
                TodoScreen(store: store)
                    .navigationTitle("Todo")
            }
            .tabItem {
                Text("Todo")
                    .accessibilityIdentifier("tab.todo")
            }
            .tag(OCamlDemoScreen.todo)

            NavigationStack {
                SearchScreen(store: store)
                    .navigationTitle("Search")
            }
            .tabItem {
                Text("Search")
                    .accessibilityIdentifier("tab.search")
            }
            .tag(OCamlDemoScreen.search)
        }
    }
}

private struct CounterScreen: View {
    let store: OCamlDemoStore

    var body: some View {
        VStack(spacing: 16) {
            CoreErrorView(error: store.lastError)
            Text("\(store.snapshot?.count ?? 0)")
                .font(.largeTitle)
                .accessibilityIdentifier("label.counter.value")
            HStack(spacing: 12) {
                Button("Decrement") {
                    store.dispatch(screen: .counter, action: "decrement")
                }
                .accessibilityIdentifier("button.counter.decrement")
                Button("Increment") {
                    store.dispatch(screen: .counter, action: "increment")
                }
                .accessibilityIdentifier("button.counter.increment")
            }
            Button("Reset") {
                store.dispatch(screen: .counter, action: "reset")
            }
            .accessibilityIdentifier("button.counter.reset")
        }
        .padding()
        .task {
            store.load(.counter)
        }
    }
}

private struct TodoScreen: View {
    let store: OCamlDemoStore

    var body: some View {
        VStack(spacing: 12) {
            CoreErrorView(error: store.lastError)
            HStack {
                TextField(
                    "New task",
                    text: Binding(
                        get: {
                            store.snapshot?.screen == .todo
                                ? store.snapshot?.draft ?? ""
                                : ""
                        },
                        set: { draft in
                            store.dispatch(
                                screen: .todo,
                                action: "setDraft",
                                payload: draft
                            )
                        }
                    )
                )
                .accessibilityIdentifier("field.todo.draft")
                Button("Add") {
                    store.dispatch(screen: .todo, action: "add")
                }
                .accessibilityIdentifier("button.todo.add")
            }
            .padding(.horizontal)

            List(store.snapshot?.screen == .todo ? store.snapshot?.items ?? [] : []) {
                todo in
                HStack {
                    Button(todo.completed ? "Completed" : "Active") {
                        store.dispatch(
                            screen: .todo,
                            action: "toggle",
                            payload: "\(todo.id)"
                        )
                    }
                    .accessibilityIdentifier("button.todo.toggle.\(todo.id)")
                    Text(todo.title)
                    Spacer()
                    Button("Delete") {
                        store.dispatch(
                            screen: .todo,
                            action: "delete",
                            payload: "\(todo.id)"
                        )
                    }
                    .accessibilityIdentifier("button.todo.delete.\(todo.id)")
                }
            }
        }
        .task {
            store.load(.todo)
        }
    }
}

private struct SearchScreen: View {
    let store: OCamlDemoStore

    var body: some View {
        VStack(spacing: 12) {
            CoreErrorView(error: store.lastError)
            TextField(
                "Search",
                text: Binding(
                    get: {
                        store.snapshot?.screen == .search
                            ? store.snapshot?.query ?? ""
                            : ""
                    },
                    set: { query in
                        store.dispatch(
                            screen: .search,
                            action: "setQuery",
                            payload: query
                        )
                    }
                )
            )
            .accessibilityIdentifier("field.search.query")
            .padding(.horizontal)

            List(store.snapshot?.screen == .search ? store.snapshot?.results ?? [] : [], id: \.self) {
                result in
                Text(result)
            }
        }
        .task {
            store.load(.search)
        }
    }
}

private struct CoreErrorView: View {
    let error: OCamlDemoCoreError?

    @ViewBuilder var body: some View {
        if let error {
            Text("\(error.code): \(error.message)")
                .foregroundStyle(.red)
                .padding(.horizontal)
        }
    }
}
