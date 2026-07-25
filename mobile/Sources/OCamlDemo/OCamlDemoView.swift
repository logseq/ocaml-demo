import SwiftUI

public struct OCamlDemoView: View {
    @State private var store: OCamlDemoStore
    @State private var selectedScreen = OCamlDemoScreen.counter

    public init(call: @escaping (String) -> String) {
        store = OCamlDemoStore(call: call)
    }

    public var body: some View {
        SidebarContainerView(store: store, selectedScreen: $selectedScreen)
            #if !SKIP
            .ignoresSafeArea()
            #endif
    }
}

struct SidebarContent: View {
    let selectedScreen: OCamlDemoScreen
    let selectScreen: (OCamlDemoScreen) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OCaml Demo")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)

            SidebarLink(
                title: "Counter",
                identifier: "link.sidebar.counter",
                isSelected: selectedScreen == .counter
            ) {
                selectScreen(.counter)
            }

            SidebarLink(
                title: "Todos",
                identifier: "link.sidebar.todo",
                isSelected: selectedScreen == .todo
            ) {
                selectScreen(.todo)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        #if !SKIP
        .safeAreaPadding(.top)
        #endif
        .padding(.top, 32)
    }
}

private struct SidebarLink: View {
    let title: String
    let identifier: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct ScreenContent: View {
    let screen: OCamlDemoScreen
    let store: OCamlDemoStore

    @ViewBuilder var body: some View {
        switch screen {
        case .counter:
            CounterScreen(store: store)
        case .todo:
            TodoScreen(store: store)
        case .search:
            EmptyView()
        }
    }
}

private struct SidebarMainPage: View {
    let store: OCamlDemoStore
    @Binding var selectedScreen: OCamlDemoScreen
    @Binding var isSidebarPresented: Bool

    var body: some View {
        NavigationStack {
            ScreenContent(screen: selectedScreen, store: store)
                .navigationTitle(selectedScreen == .counter ? "Counter" : "Todos")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            isSidebarPresented.toggle()
                        } label: {
                            SidebarMenuIcon()
                        }
                        .accessibilityLabel("Open sidebar")
                        .accessibilityIdentifier("button.sidebar")
                    }
                }
        }
        .overlay {
            if isSidebarPresented {
                Button {
                    isSidebarPresented = false
                } label: {
                    Color.black.opacity(0.001)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close sidebar")
                .accessibilityIdentifier("button.sidebar.dismiss")
            }
        }
    }
}

private struct SidebarMenuIcon: View {
    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .frame(width: 20, height: 2)
            Capsule()
                .frame(width: 20, height: 2)
            Capsule()
                .frame(width: 20, height: 2)
        }
        .frame(width: 24, height: 24)
        .foregroundStyle(.primary)
    }
}

private struct SidebarContainerView: View {
    let store: OCamlDemoStore
    @Binding var selectedScreen: OCamlDemoScreen
    @State private var isSidebarPresented = false
    #if SKIP
    @State private var dragOffset: CGFloat = 0
    #else
    @GestureState private var dragOffset: CGFloat = 0
    #endif

    var body: some View {
        GeometryReader { geometry in
            let zero: CGFloat = 0.0
            let maximumSidebarWidth: CGFloat = 360
            let proposedSidebarWidth: CGFloat = geometry.size.width * 0.84
            let sidebarWidth: CGFloat =
                proposedSidebarWidth < maximumSidebarWidth
                ? proposedSidebarWidth : maximumSidebarWidth
            let baseOffset: CGFloat =
                isSidebarPresented ? sidebarWidth : zero
            let proposedContentOffset: CGFloat = baseOffset + dragOffset
            let lowerBoundedOffset: CGFloat =
                proposedContentOffset > zero ? proposedContentOffset : zero
            let contentOffset: CGFloat =
                lowerBoundedOffset < sidebarWidth
                ? lowerBoundedOffset : sidebarWidth
            let progress: CGFloat =
                sidebarWidth > zero ? contentOffset / sidebarWidth : zero

            ZStack(alignment: .leading) {
                SidebarContent(
                    selectedScreen: selectedScreen,
                    selectScreen: { screen in
                        selectedScreen = screen
                        isSidebarPresented = false
                    }
                )
                .frame(width: sidebarWidth)
                .background(Color.black.opacity(0.001))
                .opacity(0.35 + (0.65 * progress))
                .scaleEffect(0.96 + (0.04 * progress))
                .offset(x: -20 * (1 - progress), y: 0)
                #if SKIP
                .simultaneousGesture(
                    sidebarDragGesture(
                        baseOffset: baseOffset,
                        sidebarWidth: sidebarWidth
                    )
                )
                #else
                .highPriorityGesture(
                    sidebarDragGesture(
                        baseOffset: baseOffset,
                        sidebarWidth: sidebarWidth
                    )
                )
                #endif

                SidebarMainPage(
                    store: store,
                    selectedScreen: $selectedScreen,
                    isSidebarPresented: $isSidebarPresented
                )
                .clipShape(RoundedRectangle(cornerRadius: 40 * progress))
                .shadow(
                    color: Color.black.opacity(0.18),
                    radius: 16,
                    x: -6,
                    y: 0
                )
                .offset(x: contentOffset, y: 0)
            }
            #if SKIP
            .simultaneousGesture(
                sidebarDragGesture(
                    baseOffset: baseOffset,
                    sidebarWidth: sidebarWidth
                )
            )
            #else
            .highPriorityGesture(
                sidebarDragGesture(
                    baseOffset: baseOffset,
                    sidebarWidth: sidebarWidth
                )
            )
            #endif
            .animation(
                .spring(response: 0.28, dampingFraction: 0.9),
                value: isSidebarPresented
            )
            .sensoryFeedback(
                .impact(weight: .light),
                trigger: isSidebarPresented
            )
        }
    }

    #if SKIP
    private func sidebarDragGesture(
        baseOffset: CGFloat,
        sidebarWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let projectedOffset =
                    baseOffset + value.predictedEndTranslation.width
                isSidebarPresented = projectedOffset > sidebarWidth * 0.5
                dragOffset = 0
            }
    }
    #else
    private func sidebarDragGesture(
        baseOffset: CGFloat,
        sidebarWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .updating($dragOffset) { value, state, transaction in
                if abs(value.translation.width) > abs(value.translation.height) {
                    transaction.animation = nil
                    state = value.translation.width
                }
            }
            .onEnded { value in
                let projectedOffset =
                    baseOffset + value.predictedEndTranslation.width
                isSidebarPresented = projectedOffset > sidebarWidth * 0.5
            }
    }
    #endif
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
