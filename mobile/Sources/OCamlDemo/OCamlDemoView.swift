import SwiftUI
#if os(iOS) || SKIP
import SkipWeb
#endif
#if SKIP
import androidx.activity.compose.BackHandler
#endif

public struct OCamlDemoView: View {
    @State private var store: OCamlDemoStore
    @State private var selectedScreen = OCamlDemoScreen.journal

    public init(
        call: @escaping (String) -> String,
        databasePath: String? = nil
    ) {
        let store = OCamlDemoStore(call: call)
        if let databasePath {
            store.open(path: databasePath)
        }
        self.store = store
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
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.bottom, 20)

            SidebarLink(
                title: "Journals",
                identifier: "link.sidebar.journal",
                isSelected: selectedScreen == .journal
            ) {
                selectScreen(.journal)
            }

            SidebarLink(
                title: "Tasks",
                identifier: "link.sidebar.tasks",
                isSelected: selectedScreen == .tasks
            ) {
                selectScreen(.tasks)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        #if SKIP
        .padding(.top, 12)
        #else
        .safeAreaPadding(.top)
        #endif
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.black.opacity(0.001)
            )
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
        case .journal:
            JournalScreen(store: store)
        case .tasks:
            TasksScreen(store: store)
        case .outliner:
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
                #if SKIP
                .padding(.top, 56)
                #endif
                .navigationTitle(selectedScreen.navigationTitle)
                #if os(iOS) || SKIP
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            isSidebarPresented.toggle()
                        } label: {
                            SidebarMenuIcon()
                        }
                        .tint(Color.primary)
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
        .frame(width: 44, height: 44)
        .background(Color.black.opacity(0.001))
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
                #if SKIP
                ComposeView { _ in
                    BackHandler(enabled: isSidebarPresented) {
                        isSidebarPresented = false
                    }
                }
                .frame(width: 0, height: 0)
                #endif

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

private struct TasksScreen: View {
    let store: OCamlDemoStore

    var body: some View {
        VStack(spacing: 12) {
            CoreErrorView(error: store.lastError)
            HStack {
                TextField(
                    "New task",
                    text: Binding(
                        get: {
                            store.snapshot?.screen == .tasks
                                ? store.snapshot?.draft ?? ""
                                : ""
                        },
                        set: { draft in
                            store.dispatch(
                                screen: .tasks,
                                action: "setDraft",
                                payload: draft
                            )
                        }
                    )
                )
                .accessibilityIdentifier("field.tasks.draft")
                Button("Add") {
                    store.dispatch(screen: .tasks, action: "add")
                }
                .accessibilityIdentifier("button.tasks.add")
            }
            .padding(.horizontal)

            List(store.snapshot?.screen == .tasks ? store.snapshot?.items ?? [] : []) {
                task in
                HStack {
                    Button(task.completed ? "Completed" : "Active") {
                        store.dispatch(
                            screen: .tasks,
                            action: "toggle",
                            payload: "\(task.id)"
                        )
                    }
                    .accessibilityIdentifier("button.tasks.toggle.\(task.id)")
                    Text(task.title)
                    Spacer()
                    Button("Delete") {
                        store.dispatch(
                            screen: .tasks,
                            action: "delete",
                            payload: "\(task.id)"
                        )
                    }
                    .accessibilityIdentifier("button.tasks.delete.\(task.id)")
                }
            }
        }
        .task {
            store.load(.tasks)
        }
    }
}

#if os(iOS) || SKIP
private struct JournalScreen: View {
    @State private var bridge: JournalWebBridge

    init(store: OCamlDemoStore) {
        _bridge = State(initialValue: JournalWebBridge(store: store))
    }

    var body: some View {
        WebView(
            configuration: bridge.configuration,
            navigator: bridge.navigator,
            url: URL(string: "ocaml-demo://bundle/index.html")!
        )
        .accessibilityIdentifier("webview.journal")
    }
}

@MainActor
private final class JournalWebBridge: WebViewScriptMessageDelegate {
    let configuration: WebEngineConfiguration
    let navigator: WebViewNavigator
    private let store: OCamlDemoStore

    init(store: OCamlDemoStore) {
        self.store = store
        self.navigator = WebViewNavigator()
        self.configuration = WebEngineConfiguration(
            allowsBackForwardNavigationGestures: false,
            allowsPullToRefresh: false,
            scriptMessageHandlerNames: ["native"],
            schemeHandlers: [
                "ocaml-demo": BundleURLSchemeHandler(
                    bundle: Bundle.module,
                    subdirectory: "JournalWeb"
                )
            ]
        )
        self.configuration.scriptMessageDelegate = self
    }

    func webEngine(
        _ webEngine: WebEngine,
        didReceiveScriptMessage message: WebViewScriptMessage
    ) {
        guard message.name == "native",
              let data = message.bodyJSON.data(using: .utf8),
              let command = try? JSONDecoder().decode(JournalWebCommand.self, from: data)
        else {
            return
        }

        switch command.action {
        case "ready":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            store.dispatch(
                screen: .journal,
                action: "ensureToday",
                payload: formatter.string(from: Date())
            )
        case "showJournals":
            store.load(.journal)
        case "openJournal":
            guard let id = command.id else { return }
            store.dispatch(screen: .journal, action: "open", payload: "\(id)")
            store.load(.outliner)
        case "setContent", "insertSibling", "indent", "outdent":
            guard let id = command.id,
                  let payload = try? JSONEncoder().encode(
                    OutlinerCommandPayload(id: id, content: command.content)
                  ),
                  let payloadJSON = String(data: payload, encoding: .utf8)
            else {
                return
            }
            store.dispatch(
                screen: .outliner,
                action: command.action,
                payload: payloadJSON
            )
        default:
            return
        }
        publishSnapshot(to: webEngine)
    }

    private func publishSnapshot(to webEngine: WebEngine) {
        guard let snapshot = store.snapshot,
              let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        let base64 = data.base64EncodedString()
        let script =
            """
            window.dispatchEvent(
              new CustomEvent("ocamlDemoSnapshot", {
                detail: window.ocamlDemoDecodeBase64Utf8("\(base64)")
              })
            );
            """
        Task { @MainActor in
            _ = try? await webEngine.evaluate(js: script)
        }
    }
}

private struct JournalWebCommand: Decodable {
    let action: String
    let id: Int?
    let content: String?
}

private struct OutlinerCommandPayload: Encodable {
    let id: Int
    let content: String?
}
#else
private struct JournalScreen: View {
    let store: OCamlDemoStore

    var body: some View {
        Text("Journals are available on iOS and Android")
    }
}
#endif

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
