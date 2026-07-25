import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public typealias OCamlDemoEventCallback = @convention(c) (Int32, UnsafePointer<CChar>?) -> Void
public typealias OCamlDemoLazyRowRenderCallback =
  @convention(c) (Int32, Int32) -> UnsafeMutableRawPointer?
public typealias OCamlDemoLazyRowKeyCallback =
  @convention(c) (Int32, Int32) -> UnsafeMutablePointer<CChar>?
public typealias OCamlDemoLazyRowReleaseCallback =
  @convention(c) (Int32, Int32) -> Void
public typealias OCamlDemoHTTPCallback =
  @convention(c) (UnsafeMutableRawPointer?, Bool, UnsafePointer<CChar>?) -> Void
public typealias OCamlDemoLaunchCallback =
  @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
public typealias OCamlDemoMainCallback =
  @convention(c) (UnsafeMutableRawPointer?) -> Void

@_cdecl("ocaml_demo_native_swiftui_run_on_main_when_scroll_idle")
public func ocaml_demo_native_swiftui_run_on_main_when_scroll_idle(
  _ context: UnsafeMutableRawPointer?,
  _ callback: OCamlDemoMainCallback?
) {
  DispatchQueue.main.async {
    callback?(context)
  }
}

@_cdecl("ocaml_demo_native_swiftui_run_on_main_after_rendered_frame")
public func ocaml_demo_native_swiftui_run_on_main_after_rendered_frame(
  _ context: UnsafeMutableRawPointer?,
  _ callback: OCamlDemoMainCallback?
) {
  DispatchQueue.main.async {
    callback?(context)
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_clipboard_text")
public func ocaml_demo_native_swiftui_set_clipboard_text(_ textPointer: UnsafePointer<CChar>?) {
  guard let textPointer else { return }
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(String(cString: textPointer), forType: .string)
}

@_cdecl("ocaml_demo_native_swiftui_set_clipboard_image_file")
public func ocaml_demo_native_swiftui_set_clipboard_image_file(_ pathPointer: UnsafePointer<CChar>?) {
  guard let pathPointer else { return }
  guard let image = NSImage(contentsOfFile: String(cString: pathPointer)) else { return }
  NSPasteboard.general.clearContents()
  NSPasteboard.general.writeObjects([image])
}

private var ocaml_demoNativeAudioPlayer: AVAudioPlayer?
private var ocaml_demoNativeAudioPath: String?
private var ocaml_demoNativeAudioRecorder: AVAudioRecorder?
private var ocaml_demoNativeAudioRecordingURL: URL?

@_cdecl("ocaml_demo_native_swiftui_toggle_audio_file_playback")
public func ocaml_demo_native_swiftui_toggle_audio_file_playback(_ pathPointer: UnsafePointer<CChar>?) {
  guard let pathPointer else { return }
  let path = String(cString: pathPointer)
  if ocaml_demoNativeAudioPath == path, ocaml_demoNativeAudioPlayer?.isPlaying == true {
    ocaml_demoNativeAudioPlayer?.pause()
    ocaml_demoNativeAudioPlayer = nil
    ocaml_demoNativeAudioPath = nil
    return
  }
  ocaml_demoNativeAudioPlayer?.stop()
  do {
    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.prepareToPlay()
    player.play()
    ocaml_demoNativeAudioPlayer = player
    ocaml_demoNativeAudioPath = path
  } catch {
    ocaml_demoNativeAudioPlayer = nil
    ocaml_demoNativeAudioPath = nil
  }
}

@_cdecl("ocaml_demo_native_swiftui_start_audio_recording")
public func ocaml_demo_native_swiftui_start_audio_recording() {
  do {
    let url = try ocaml_demoNativeNextAudioRecordingURL()
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder.prepareToRecord()
    recorder.record()
    ocaml_demoNativeAudioRecorder = recorder
    ocaml_demoNativeAudioRecordingURL = url
  } catch {
    ocaml_demoNativeAudioRecorder = nil
    ocaml_demoNativeAudioRecordingURL = nil
  }
}

@_cdecl("ocaml_demo_native_swiftui_stop_audio_recording_and_transcribe")
public func ocaml_demo_native_swiftui_stop_audio_recording_and_transcribe() -> UnsafeMutablePointer<CChar>? {
  guard let recorder = ocaml_demoNativeAudioRecorder else {
    return strdup("")
  }
  recorder.stop()
  ocaml_demoNativeAudioRecorder = nil
  let url = recorder.url
  ocaml_demoNativeAudioRecordingURL = url
  let byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
  return strdup([
    "Audio recording",
    url.path,
    url.lastPathComponent,
    "audio/mp4",
    String(byteSize)
  ].joined(separator: "\t"))
}

private func ocaml_demoNativeNextAudioRecordingURL() throws -> URL {
  let base = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
  )
  let appDirectoryName = Bundle.main.bundleIdentifier ?? "OCamlDemo"
  let directory = base
    .appendingPathComponent(appDirectoryName, isDirectory: true)
    .appendingPathComponent("AudioRecordings", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let filename = "audio-recording-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).m4a"
  return directory.appendingPathComponent(filename)
}

private enum NodeKind: Int32 {
  case label = 0
  case button = 1
  case textField = 2
  case textEditor = 3
  case verticalStack = 4
  case horizontalStack = 5
  case scrollView = 6
  case list = 7
  case navigationStack = 8
  case tabView = 9
  case image = 10
  case listRow = 11
  case section = 12
  case picker = 13
  case customView = 14
  case photoPicker = 15
  case sidebarSplit = 16
  case fileExporter = 17
  case fileImporter = 18
  case cameraCapture = 19
  case navigationSplit = 20
  case adaptiveLayout = 21
  case toggle = 22
  case shareLink = 23
  case navigationLink = 24
  case progressView = 25
  case zStack = 26
  case spacer = 27
  case divider = 28
  case form = 29
  case navigationPathStack = 30
  case slider = 31
  case stepper = 32
  case datePicker = 33
  case colorPicker = 34
  case menu = 35
  case disclosureGroup = 36
  case movableRows = 37
  case grid = 38
}

private func ocaml_demoNativeSemanticColor(_ color: Int32) -> Color? {
  switch color {
  case 0: return .primary
  case 1: return .secondary
  case 2: return Color.secondary.opacity(0.65)
  case 3: return .red
  case 4: return .green
  case 5: return .orange
  case 6: return .blue
  case 7: return Color.accentColor
  default: return nil
  }
}

private extension View {
  @ViewBuilder
  func ocaml_demoLiquidGlassPanel(
    cornerRadius: CGFloat,
    isInteractive: Bool = false,
    isTransparent: Bool = false,
    tint: Color? = nil
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    if #available(macOS 26.0, *) {
      if let tint {
        self.glassEffect(
          isTransparent
            ? (isInteractive ? .clear.tint(tint).interactive() : .clear.tint(tint))
            : (isInteractive ? .regular.tint(tint).interactive() : .regular.tint(tint)),
          in: shape
        )
      } else {
        self.glassEffect(
          isTransparent
            ? (isInteractive ? .clear.interactive() : .clear)
            : (isInteractive ? .regular.interactive() : .regular),
          in: shape
        )
      }
    } else if let tint {
      self.background(AnyShapeStyle(tint), in: shape)
    } else {
      self.background(isTransparent ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar), in: shape)
    }
  }
}

private struct OCamlDemoRowAction: Identifiable {
  let id = UUID()
  let title: String
  let systemImage: String?
  let style: Int32
  let eventId: Int32?
  let startsSection: Bool
  let exportFilename: String?
  let exportContentType: String?
  let exportContent: String?
}

private struct OCamlDemoTab: Identifiable {
  let id: String
  let title: String
  let systemImage: String?
  let role: Int32
}

private struct OCamlDemoSidebarAction: Identifiable {
  let id: String
  let title: String
  let subtitle: String?
  let systemImage: String?
  let avatarImage: String?
  let avatarInitial: String?
  let selectsTab: String?
  let chrome: Int32
  let eventId: Int32?
  let closesSidebar: Bool
  var menuActions: [OCamlDemoRowAction]
}

private struct OCamlDemoPickerOption: Identifiable {
  let id: String
  let title: String
}

private struct OCamlDemoAlertAction: Identifiable {
  let id: String
  let title: String
  let role: Int32
  let isEnabled: Bool
  let eventId: Int32?
}

private struct OCamlDemoPresentationDetent: Identifiable {
  let id = UUID()
  let kind: Int32
  let value: Double
}

private struct OCamlDemoMenuAction: Identifiable {
  let id: String
  let title: String
  let systemImage: String?
  let style: Int32
  let isEnabled: Bool
  let eventId: Int32?
}

private struct OCamlDemoToolbarItem: Identifiable {
  let id: String
  let title: String
  let systemImage: String?
  let isTitleVisible: Bool
  let eventId: Int32?
  let isEnabled: Bool
  let shareURL: String?
  var menuActions: [OCamlDemoRowAction]
}

private enum OCamlDemoToolbarPlacement: Int32 {
  case automatic = 0
  case bottomBar = 1
}

private enum OCamlDemoToolbarContentKind: Int32 {
  case group = 0
  case spacer = 1
}

private struct OCamlDemoToolbarContent: Identifiable {
  let id: String
  let kind: OCamlDemoToolbarContentKind
  let placement: OCamlDemoToolbarPlacement
  let fixed: Bool
  var items: [OCamlDemoToolbarItem]
}

private final class OCamlDemoNode: ObservableObject, Identifiable {
  let id = UUID()
  let kind: NodeKind

  @Published var text = ""
  @Published var systemImage: String?
  @Published var buttonSubtitle: String?
  @Published var buttonStyle: Int32 = 0
  @Published var isTitleVisible = true
  @Published var textStyle: Int32 = 5
  @Published var textWeight: Int32 = 0
  @Published var textColor: Int32 = 0
  @Published var textFieldStyle: Int32 = 0
  @Published var textFieldAxis: Int32 = 0
  @Published var textFieldClearButton: Int32 = 0
  @Published var isTextFieldSecure = false
  @Published var isTextFieldFocused = false
  @Published var textFieldBlurEventId: Int32?
  @Published var textFieldDeleteBackwardAtStartEventId: Int32?
  @Published var isToggleOn = false
  @Published var progressValue: Double = 0
  @Published var isEnabled = true
  @Published var imageSource: Int32 = 0
  @Published var imageColor: Int32 = -1
  @Published var imageMaxHeight: CGFloat?
  @Published var imageCornerRadius: CGFloat?
  @Published var keyboardDismissControls = false
  @Published var scrollDismissesKeyboard = false
  @Published var hideListRowSeparator = false
  @Published var placeholder: String?
  @Published var spacing: CGFloat?
  @Published var horizontalStackAlignment = VerticalAlignment.center
  @Published var children: [OCamlDemoNode] = []
  @Published var clickEventId: Int32?
  @Published var navigationActivateEventId: Int32?
  @Published var navigationDeactivateEventId: Int32?
  @Published var tapEventId: Int32?
  @Published var horizontalSwipeLeftEventId: Int32?
  @Published var horizontalSwipeRightEventId: Int32?
  @Published var appearEventId: Int32?
  @Published var changeEventId: Int32?
  @Published var isSearchable = false
  @Published var searchText = ""
  @Published var searchPrompt: String?
  @Published var searchEventId: Int32?
  @Published var hasSearchPresentation = false
  @Published var isSearchPresented = false
  @Published var searchPresentationEventId: Int32?
  @Published var sheetContent: OCamlDemoNode?
  @Published var bottomSafeAreaInsetContent: OCamlDemoNode?
  @Published var isSheetPresented = false
  @Published var sheetDetents: [OCamlDemoPresentationDetent] = []
  @Published var dismissEventId: Int32?
  @Published var popoverContent: OCamlDemoNode?
  @Published var isPopoverPresented = false
  @Published var popoverDismissEventId: Int32?
  @Published var isAlertPresented = false
  @Published var alertTitle = ""
  @Published var alertMessage: String?
  @Published var alertText: String?
  @Published var alertPlaceholder: String?
  @Published var alertTextEventId: Int32?
  @Published var alertDismissEventId: Int32?
  @Published var alertActions: [OCamlDemoAlertAction] = []
  @Published var isConfirmationDialogPresented = false
  @Published var confirmationDialogTitle = ""
  @Published var confirmationDialogMessage: String?
  @Published var confirmationDialogDismissEventId: Int32?
  @Published var confirmationDialogActions: [OCamlDemoAlertAction] = []
  @Published var navigationTitle: String?
  @Published var toolbarItems: [OCamlDemoToolbarItem] = []
  @Published var toolbarContents: [OCamlDemoToolbarContent] = []
  @Published var keyboardToolbarItems: [OCamlDemoToolbarItem] = []
  @Published var padding: EdgeInsets?
  @Published var regularMaterialPanelCornerRadius: CGFloat?
  @Published var secondarySystemGroupedPanelCornerRadius: CGFloat?
  @Published var secondaryFillPanelCornerRadius: CGFloat?
  @Published var secondaryFillPanelOpacity: Double = 0.12
  @Published var liquidGlassPanelCornerRadius: CGFloat?
  @Published var liquidGlassPanelIsTransparent = false
  @Published var liquidGlassPanelTintColor: Int32 = -1
  @Published var liquidGlassPanelTintOpacity: Double = 0
  @Published var gridColumns: Int = 2
  @Published var gridSpacing: CGFloat = 10
  @Published var frameWidth: CGFloat?
  @Published var frameHeight: CGFloat?
  @Published var frameMaxWidth: CGFloat?
  @Published var frameAlignment = Alignment.topLeading
  @Published var tabs: [OCamlDemoTab] = []
  @Published var selectedTabId = ""
  @Published var tabSelectEventId: Int32?
  @Published var sidebarTitle: String?
  @Published var sidebarCompactTopBarVisible = true
  @Published var sidebarHeaderAction: OCamlDemoSidebarAction?
  @Published var sidebarActions: [OCamlDemoSidebarAction] = []
  @Published var sidebarHistoryTitle: String?
  @Published var sidebarHistoryActions: [OCamlDemoSidebarAction] = []
  @Published var sidebarBottomSearchPlaceholder: String?
  @Published var sidebarBottomSearchText = ""
  @Published var sidebarBottomSearchEventId: Int32?
  @Published var sidebarBottomAction: OCamlDemoSidebarAction?
  @Published var rowSubtitle = ""
  @Published var rowTrailingText = ""
  @Published var rowContentStyle: Int32 = 0
  @Published var rowAccessory: Int32 = 0
  @Published var rowTitleStrikethrough = false
  @Published var rowStaticLeadingSystemImage: String?
  @Published var rowPreviewImagePath: String?
  @Published var rowLeadingSystemImage: String?
  @Published var rowLeadingSelectedSystemImage: String?
  @Published var rowLeadingSelected = false
  @Published var rowLeadingAccessibilityLabel = ""
  @Published var rowLeadingEventId: Int32?
  @Published var rowActions: [OCamlDemoRowAction] = []
  @Published var rowMenuActions: [OCamlDemoRowAction] = []
  @Published var contextMenuActions: [OCamlDemoRowAction] = []
  @Published var sectionTitle = ""
  @Published var pickerSelected = ""
  @Published var pickerStyle: Int32 = 0
  @Published var pickerEventId: Int32?
  @Published var pickerOptions: [OCamlDemoPickerOption] = []
  @Published var sliderValue: Double = 0
  @Published var sliderMin: Double = 0
  @Published var sliderMax: Double = 1
  @Published var stepperValue: Int32 = 0
  @Published var stepperMin: Int32 = 0
  @Published var stepperMax: Int32 = 100
  @Published var stepperStep: Int32 = 1
  @Published var selectedDateText = ""
  @Published var selectedColorText = "#007AFF"
  @Published var menuActions: [OCamlDemoMenuAction] = []
  @Published var isDisclosureExpanded = false
  @Published var navigationPath: [String] = []
  @Published var navigationPathEventId: Int32?
  @Published var navigationDestinationIds: [String] = []
  @Published var navigationLinkValue: String?
  @Published var listRefreshEventId: Int32?
  @Published var listDeleteEventId: Int32?
  @Published var listMoveEventId: Int32?
  @Published var isListEditMode = false
  @Published var listFocusedRowIndex: Int?
  @Published var listFocusedRowDisappearEventId: Int32?
  @Published var exportFilename = ""
  @Published var exportContentType = ""
  @Published var exportContent = ""
  @Published var shareURL = ""
  @Published var allowedContentTypes: [String] = []
  @Published var wantsImagePayload = false

  init(kind: NodeKind) {
    self.kind = kind
  }
}

private func sameNodeSequence(_ lhs: [OCamlDemoNode], _ rhs: [OCamlDemoNode]) -> Bool {
  lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
}

private final class OCamlDemoHostModel: ObservableObject {
  @Published var root: OCamlDemoNode
  let callback: OCamlDemoEventCallback?

  init(root: OCamlDemoNode, callback: OCamlDemoEventCallback?) {
    self.root = root
    self.callback = callback
  }

  func sendClick(_ eventId: Int32?) {
    guard let eventId else { return }
    DispatchQueue.main.async { [callback] in
      callback?(eventId, nil)
    }
  }

  func sendChange(_ eventId: Int32?, text: String) {
    guard let eventId else { return }
    DispatchQueue.main.async { [callback, text] in
      text.withCString { pointer in
        callback?(eventId, pointer)
      }
    }
  }
}

private struct OCamlDemoImageView: View {
  @ObservedObject var node: OCamlDemoNode

  var body: some View {
    if node.imageSource == 1, let image = NSImage(contentsOfFile: node.text) {
      let fileImage = Image(nsImage: image)
        .resizable()
        .scaledToFit()
      if node.imageMaxHeight != nil || node.imageCornerRadius != nil {
        fileImage
          .frame(maxWidth: .infinity, maxHeight: node.imageMaxHeight, alignment: .leading)
          .clipShape(.rect(cornerRadius: node.imageCornerRadius ?? 0, style: .continuous))
      } else {
        fileImage
      }
    } else {
      let image = Image(systemName: node.text)
      if let color = ocaml_demoNativeSemanticColor(node.imageColor) {
        image.foregroundStyle(color)
      } else {
        image
      }
    }
  }
}

private struct OCamlDemoRootView: View {
  @ObservedObject var model: OCamlDemoHostModel

  var body: some View {
    OCamlDemoNodeView(node: model.root, model: model)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private final class OCamlDemoHostingController: NSHostingController<OCamlDemoRootView> {}

private func makeHostingController(
  root: OCamlDemoNode,
  callback: OCamlDemoEventCallback?
) -> OCamlDemoHostingController {
  let model = OCamlDemoHostModel(root: root, callback: callback)
  let controller = OCamlDemoHostingController(rootView: OCamlDemoRootView(model: model))
  objc_setAssociatedObject(controller, "OCamlDemoSwiftUIModel", model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  return controller
}

private func nativeNode(from pointer: UnsafeMutableRawPointer?) -> OCamlDemoNode? {
  guard let pointer else { return nil }
  return Unmanaged<OCamlDemoNode>.fromOpaque(pointer).takeUnretainedValue()
}

private extension Color {
  init?(hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6, let raw = Int(value, radix: 16) else { return nil }
    self.init(
      red: Double((raw >> 16) & 0xff) / 255.0,
      green: Double((raw >> 8) & 0xff) / 255.0,
      blue: Double(raw & 0xff) / 255.0
    )
  }

  func hexString() -> String? {
    #if os(macOS)
    let nsColor = NSColor(self).usingColorSpace(.sRGB)
    guard let nsColor else { return nil }
    return String(
      format: "#%02X%02X%02X",
      Int(round(nsColor.redComponent * 255)),
      Int(round(nsColor.greenComponent * 255)),
      Int(round(nsColor.blueComponent * 255))
    )
    #else
    return nil
    #endif
  }
}

private struct OCamlDemoNavigationTitleModifier: ViewModifier {
  @ObservedObject var node: OCamlDemoNode

  @ViewBuilder
  func body(content: Content) -> some View {
    if let title = node.navigationTitle {
      content.navigationTitle(title)
    } else {
      content
    }
  }
}

private struct OCamlDemoListRowSeparatorModifier: ViewModifier {
  @ObservedObject var node: OCamlDemoNode

  @ViewBuilder
  func body(content: Content) -> some View {
    if node.hideListRowSeparator {
      content.listRowSeparator(.hidden)
    } else {
      content
    }
  }
}

private struct OCamlDemoNodeView: View {
  @ObservedObject var node: OCamlDemoNode
  @ObservedObject var model: OCamlDemoHostModel
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    applyModifiers(to: content)
  }

  @ViewBuilder
  private var content: some View {
    switch node.kind {
    case .label:
      Text(node.text)
        .font(font)
        .fontWeight(weight)
        .foregroundStyle(color)
    case .button:
      if node.children.isEmpty {
        let button = Button {
          model.sendClick(node.clickEventId)
        } label: {
          if let subtitle = node.buttonSubtitle {
            VStack(spacing: 4) {
              if let systemImage = node.systemImage {
                Label(node.text, systemImage: systemImage)
              } else {
                Text(node.text)
              }
              Text(subtitle)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
          } else if let systemImage = node.systemImage {
            if node.text.isEmpty || !node.isTitleVisible {
              Image(systemName: systemImage)
                .accessibilityLabel(node.text)
            } else {
              Label(node.text, systemImage: systemImage)
            }
          } else {
            Text(node.text)
          }
        }
          .disabled(!node.isEnabled)

        if node.buttonStyle == 1 {
          button.buttonStyle(.borderedProminent)
        } else if node.buttonStyle == 2 {
          button.buttonStyle(.plain)
        } else {
          button.buttonStyle(.bordered)
        }
      } else {
        Button {
          model.sendClick(node.clickEventId)
        } label: {
          customButtonLabelHitTarget {
            ForEach(node.children) { child in
              OCamlDemoNodeView(node: child, model: model)
            }
          }
        }
          .disabled(!node.isEnabled)
          .buttonStyle(.plain)
      }
    case .textField:
      let textField = Group {
        if node.isTextFieldSecure {
          SecureField(
            node.placeholder ?? "",
            text: Binding(
              get: { node.text },
              set: { value in
                node.text = value
                model.sendChange(node.changeEventId, text: value)
              }
            )
          )
        } else if node.textFieldDeleteBackwardAtStartEventId != nil {
          OCamlDemoDeleteAwareTextField(
            placeholder: node.placeholder ?? "",
            text: Binding(
              get: { node.text },
              set: { value in
                node.text = value
              }
            ),
            isFocused: node.isTextFieldFocused,
            onChange: { value in
              node.text = value
              model.sendChange(node.changeEventId, text: value)
            },
            onSubmit: {
              model.sendClick(node.clickEventId)
            },
            onDeleteBackwardAtStart: {
              model.sendClick(node.textFieldDeleteBackwardAtStartEventId)
            }
          )
        } else {
          TextField(
            node.placeholder ?? "",
            text: Binding(
              get: { node.text },
              set: { value in
                node.text = value
                model.sendChange(node.changeEventId, text: value)
              }
            )
          )
        }
      }
      .onSubmit { model.sendClick(node.clickEventId) }
      .focused($isTextFieldFocused)
      .onAppear {
        if node.isTextFieldFocused {
          isTextFieldFocused = true
        }
      }
      .onChange(of: node.isTextFieldFocused) { _, isFocused in
        if isFocused {
          isTextFieldFocused = true
        }
      }

      if node.textFieldStyle == 1 {
        textField
          .textFieldStyle(.plain)
          .font(.system(size: 18, weight: .regular))
          .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
          .padding(.horizontal, 16)
          .ocaml_demoLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
      } else if node.textFieldStyle == 2 {
        textField
          .textFieldStyle(.plain)
      } else {
        textField
          .textFieldStyle(.roundedBorder)
      }
    case .toggle:
      Toggle(
        node.text,
        isOn: Binding(
          get: { node.isToggleOn },
          set: { value in
            node.isToggleOn = value
            model.sendChange(node.changeEventId, text: value ? "true" : "false")
          }
        )
      )
      .disabled(!node.isEnabled)
    case .textEditor:
      TextEditor(
        text: Binding(
          get: { node.text },
          set: { value in
            node.text = value
            model.sendChange(node.changeEventId, text: value)
          }
        )
      )
    case .progressView:
      ProgressView(value: node.progressValue)
    case .verticalStack:
      VStack(alignment: .leading, spacing: node.spacing) { childViews }
    case .horizontalStack:
      HStack(alignment: node.horizontalStackAlignment, spacing: node.spacing) { childViews }
    case .zStack:
      ZStack { childViews }
    case .grid:
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: node.gridSpacing),
          count: max(1, node.gridColumns)
        ),
        alignment: .leading,
        spacing: node.gridSpacing
      ) {
        childViews
      }
    case .spacer:
      Spacer()
    case .divider:
      Divider()
    case .form:
      Form { childViews }
    case .scrollView:
      ScrollView { childViews }
    case .list:
      listView
    case .movableRows:
      movableRowsView
    case .navigationStack:
      NavigationStack { childViews }
    case .navigationPathStack:
      navigationPathStack
    case .navigationLink:
      if let navigationValue = node.navigationLinkValue {
        NavigationLink(value: navigationValue) {
          child(at: 0)
        }
        .buttonStyle(.plain)
      } else {
        NavigationLink {
          child(at: 1)
            .onAppear {
              model.sendClick(node.navigationActivateEventId)
            }
            .onDisappear {
              model.sendClick(node.navigationDeactivateEventId)
            }
        } label: {
          child(at: 0)
        }
        .buttonStyle(.plain)
      }
    case .navigationSplit:
      NavigationSplitView {
        child(at: 0)
          .navigationTitle("Todos")
      } content: {
        child(at: 1)
          .navigationTitle("Tasks")
      } detail: {
        child(at: 2)
      }
    case .adaptiveLayout:
      child(at: 1)
    case .tabView:
      TabView(selection: tabSelection) {
        ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
          OCamlDemoNodeView(node: child, model: model)
            .tabItem {
              if index < node.tabs.count, let image = node.tabs[index].systemImage {
                Image(systemName: image)
              }
              Text(index < node.tabs.count ? node.tabs[index].title : "")
            }
            .tag(index < node.tabs.count ? node.tabs[index].id : "")
        }
      }
    case .sidebarSplit:
      NavigationSplitView {
        List {
          if node.sidebarActions.isEmpty && node.sidebarHistoryActions.isEmpty {
            ForEach(node.tabs) { tab in
              Button {
                node.selectedTabId = tab.id
                model.sendChange(node.tabSelectEventId, text: tab.id)
              } label: {
                Label(tab.title, systemImage: tab.systemImage ?? "circle")
              }
              .buttonStyle(.plain)
            }
          } else {
            ForEach(node.sidebarActions) { action in
              sidebarActionButton(action)
            }
            if !node.sidebarHistoryActions.isEmpty, let title = node.sidebarHistoryTitle {
              Text(title)
                .font(.headline)
            }
            ForEach(node.sidebarHistoryActions) { action in
              sidebarActionButton(action, usesContextMenu: true)
            }
          }
        }
        .navigationTitle(node.sidebarTitle ?? "")
      } detail: {
        selectedTabDetail
      }
    case .image:
      OCamlDemoImageView(node: node)
    case .listRow:
      listRow
    case .section:
      Section(node.sectionTitle) { childViews }
    case .picker:
      if node.pickerStyle == 1 {
        Picker(node.text, selection: pickerSelection) {
          ForEach(node.pickerOptions) { option in
            Text(option.title).tag(option.id)
          }
        }
        .pickerStyle(.segmented)
      } else {
        Picker(node.text, selection: pickerSelection) {
          ForEach(node.pickerOptions) { option in
            Text(option.title).tag(option.id)
          }
        }
        .pickerStyle(.menu)
      }
    case .slider:
      slider
    case .stepper:
      stepper
    case .datePicker:
      datePicker
    case .colorPicker:
      colorPicker
    case .menu:
      menu
    case .disclosureGroup:
      disclosureGroup
    case .photoPicker:
      Group {
        if node.isTitleVisible {
          Label(node.text, systemImage: node.systemImage ?? "photo")
        } else {
          Image(systemName: node.systemImage ?? "photo")
            .accessibilityLabel(node.text)
        }
      }
        .foregroundStyle(.secondary)
    case .fileExporter:
      Label(node.text, systemImage: "square.and.arrow.up")
        .foregroundStyle(.secondary)
    case .shareLink:
      if let url = URL(string: node.shareURL) {
        ShareLink(item: url) {
          Label(node.text, systemImage: "square.and.arrow.up")
        }
        .disabled(!node.isEnabled)
      } else {
        Label(node.text, systemImage: "square.and.arrow.up")
          .foregroundStyle(.secondary)
      }
    case .fileImporter:
      Label(node.text, systemImage: "square.and.arrow.down")
        .foregroundStyle(.secondary)
    case .cameraCapture:
      Label(node.text, systemImage: "camera")
        .foregroundStyle(.secondary)
    case .customView:
      if node.text == "congrats-effect" {
        OCamlDemoCongratsEffectView()
      } else if node.text == "system-grouped-background" {
        Color(nsColor: .windowBackgroundColor)
          .ignoresSafeArea(.container, edges: .all)
      } else {
        Text(node.text)
      }
    }
  }

  private var childViews: some View {
    ForEach(node.children) { child in
      OCamlDemoNodeView(node: child, model: model)
    }
  }

  private var listView: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(node.children) { child in
          OCamlDemoNodeView(node: child, model: model)
        }
        .onDelete { offsets in
          guard let index = offsets.first else { return }
          model.sendChange(node.listDeleteEventId, text: String(index))
        }
        .onMove { source, destination in
          guard let fromIndex = source.first else { return }
          model.sendChange(node.listMoveEventId, text: "\(fromIndex):\(destination)")
        }
      }
      .refreshable {
        model.sendClick(node.listRefreshEventId)
      }
      .onAppear {
        scrollFocusedRow(proxy)
      }
      .onChange(of: node.listFocusedRowIndex) { _, _ in
        scrollFocusedRow(proxy)
      }
    }
  }

  private func scrollFocusedRow(_ proxy: ScrollViewProxy) {
    guard let index = node.listFocusedRowIndex else { return }
    guard node.children.indices.contains(index) else { return }
    let focusedNode = node.children[index]
    DispatchQueue.main.async {
      withAnimation(.easeInOut(duration: 0.18)) {
        proxy.scrollTo(focusedNode.id)
      }
    }
  }

  private var movableRowsView: some View {
    ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
      OCamlDemoNodeView(node: child, model: model)
    }
    .onMove { source, destination in
      guard let fromIndex = source.first else { return }
      model.sendChange(node.listMoveEventId, text: "\(fromIndex):\(destination)")
    }
  }

  private var navigationPathBinding: Binding<[String]> {
    Binding(
      get: { node.navigationPath },
      set: { value in
        node.navigationPath = value
        model.sendChange(node.navigationPathEventId, text: value.joined(separator: "\n"))
      }
    )
  }

  private var navigationPathStack: some View {
    NavigationStack(path: navigationPathBinding) {
      child(at: 0)
        .navigationDestination(for: String.self) { destinationId in
          if let index = node.navigationDestinationIds.firstIndex(of: destinationId),
             node.children.indices.contains(index + 1) {
            OCamlDemoNodeView(node: node.children[index + 1], model: model)
          } else {
            EmptyView()
          }
        }
    }
  }

  @ViewBuilder
  private func child(at index: Int) -> some View {
    if node.children.indices.contains(index) {
      OCamlDemoNodeView(node: node.children[index], model: model)
    } else {
      EmptyView()
    }
  }

  @ViewBuilder
  private var selectedTabDetail: some View {
    if let index = node.tabs.firstIndex(where: { $0.id == node.selectedTabId }),
       node.children.indices.contains(index) {
      OCamlDemoNodeView(node: node.children[index], model: model)
    } else if let first = node.children.first {
      OCamlDemoNodeView(node: first, model: model)
    } else {
      EmptyView()
    }
  }

  private var listRow: some View {
    HStack(spacing: 10) {
      if let leading = node.rowLeadingSystemImage {
        Button {
          model.sendClick(node.rowLeadingEventId)
        } label: {
          Image(systemName: node.rowLeadingSelected ? (node.rowLeadingSelectedSystemImage ?? leading) : leading)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.rowLeadingAccessibilityLabel)
      } else if let leading = node.rowStaticLeadingSystemImage {
        Image(systemName: leading)
          .frame(width: 24, height: 24)
      }
      listRowMainContent
    }
    .contextMenu {
      ForEach(node.rowActions) { action in
        Button(role: action.style == 1 ? .destructive : nil) {
          model.sendClick(action.eventId)
        } label: {
          if let image = action.systemImage {
            Label(action.title, systemImage: image)
          } else {
            Text(action.title)
          }
        }
      }
      ForEach(node.rowMenuActions) { action in
        Button(role: action.style == 1 ? .destructive : nil) {
          model.sendClick(action.eventId)
        } label: {
          if let image = action.systemImage {
            Label(action.title, systemImage: image)
          } else {
            Text(action.title)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func sidebarActionButton(_ action: OCamlDemoSidebarAction, usesContextMenu: Bool = false) -> some View {
    if action.menuActions.isEmpty {
      Button {
        performSidebarAction(action)
      } label: {
        sidebarActionLabel(action)
      }
      .buttonStyle(.plain)
    } else {
      if usesContextMenu {
        Button {
          performSidebarAction(action)
        } label: {
          sidebarActionLabel(action)
        }
        .buttonStyle(.plain)
        .contextMenu {
          sidebarActionMenuItems(action)
        }
      } else {
        Menu {
          sidebarActionMenuItems(action)
        } label: {
          sidebarActionLabel(action)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func performSidebarAction(_ action: OCamlDemoSidebarAction) {
    if let selectedTab = sidebarActionSelectedTab(action) {
      node.selectedTabId = selectedTab
    }
    if let eventId = action.eventId {
      model.sendClick(eventId)
    }
  }

  private func sidebarActionSelectedTab(_ action: OCamlDemoSidebarAction) -> String? {
    if let selectsTab = action.selectsTab {
      return selectsTab
    }
    return node.tabs.contains { $0.id == action.id } ? action.id : nil
  }

  @ViewBuilder
  private func sidebarActionMenuItems(_ action: OCamlDemoSidebarAction) -> some View {
    ForEach(action.menuActions) { menuAction in
      Button(role: menuAction.style == 1 ? .destructive : nil) {
        if let eventId = menuAction.eventId {
          model.sendClick(eventId)
        }
      } label: {
        if let image = menuAction.systemImage {
          Label(menuAction.title, systemImage: image)
        } else {
          Text(menuAction.title)
        }
      }
    }
  }

  @ViewBuilder
  private func sidebarActionLabel(_ action: OCamlDemoSidebarAction) -> some View {
    if let subtitle = action.subtitle, !subtitle.isEmpty {
      if let systemImage = action.systemImage {
        Label {
          sidebarActionText(title: action.title, subtitle: subtitle)
        } icon: {
          Image(systemName: systemImage)
        }
      } else {
        sidebarActionText(title: action.title, subtitle: subtitle)
      }
    } else {
      if let systemImage = action.systemImage {
        Label(action.title, systemImage: systemImage)
      } else {
        Text(action.title)
      }
    }
  }

  private func sidebarActionText(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .lineLimit(1)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private var listRowMainContent: some View {
    let content = Group {
      if node.rowContentStyle == 1 {
        summaryRowMainContent
      } else if node.rowContentStyle == 2 {
        detailRowMainContent
      } else {
        standardRowMainContent
      }
    }

    content
      .contentShape(Rectangle())
      .onTapGesture {
        model.sendClick(node.clickEventId)
      }
  }

  private var summaryRowMainContent: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(node.text)
          .font(.headline)
          .strikethrough(node.rowTitleStrikethrough)
        if !node.rowSubtitle.isEmpty {
          Text(node.rowSubtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if node.rowAccessory == 1 {
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
      }
    }
  }

  private var detailRowMainContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(node.text)
        .font(.headline)
        .strikethrough(node.rowTitleStrikethrough)
      if !node.rowSubtitle.isEmpty {
        Text(node.rowSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var standardRowMainContent: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(node.text)
          .strikethrough(node.rowTitleStrikethrough)
        if !node.rowSubtitle.isEmpty {
          Text(node.rowSubtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if !node.rowTrailingText.isEmpty {
        Text(node.rowTrailingText)
          .foregroundStyle(.secondary)
      }
      if node.rowAccessory == 1 {
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
      }
    }
  }

  private var tabSelection: Binding<String> {
    Binding(
      get: { node.selectedTabId },
      set: { value in
        node.selectedTabId = value
        model.sendChange(node.tabSelectEventId, text: value)
      }
    )
  }

  private var pickerSelection: Binding<String> {
    Binding(
      get: { node.pickerSelected },
      set: { value in
        node.pickerSelected = value
        model.sendChange(node.pickerEventId, text: value)
      }
    )
  }

  private var slider: some View {
    VStack(alignment: .leading) {
      Text(node.text)
      Slider(
        value: Binding(
          get: { node.sliderValue },
          set: { value in
            node.sliderValue = value
            model.sendChange(node.changeEventId, text: String(value))
          }
        ),
        in: node.sliderMin...node.sliderMax
      )
    }
  }

  private var stepper: some View {
    Stepper(
      value: Binding(
        get: { Int(node.stepperValue) },
        set: { value in
          node.stepperValue = Int32(value)
          model.sendChange(node.changeEventId, text: String(value))
        }
      ),
      in: Int(node.stepperMin)...Int(node.stepperMax),
      step: Int(node.stepperStep)
    ) {
      Text("\(node.text): \(node.stepperValue)")
    }
  }

  private var datePickerDate: Binding<Date> {
    Binding(
      get: { Self.dateFormatter.date(from: node.selectedDateText) ?? Date() },
      set: { date in
        let selected = Self.dateFormatter.string(from: date)
        node.selectedDateText = selected
        model.sendChange(node.changeEventId, text: selected)
      }
    )
  }

  private var datePicker: some View {
    DatePicker(node.text, selection: datePickerDate, displayedComponents: .date)
  }

  private var colorPickerColor: Binding<Color> {
    Binding(
      get: { Color(hex: node.selectedColorText) ?? .accentColor },
      set: { color in
        let selected = color.hexString() ?? node.selectedColorText
        node.selectedColorText = selected
        model.sendChange(node.changeEventId, text: selected)
      }
    )
  }

  private var colorPicker: some View {
    ColorPicker(node.text, selection: colorPickerColor)
  }

  private var menu: some View {
    Menu {
      ForEach(node.menuActions) { action in
        Button(role: action.style == 1 ? .destructive : nil) {
          model.sendClick(action.eventId)
        } label: {
          if let systemImage = action.systemImage {
            Label(action.title, systemImage: systemImage)
          } else {
            Text(action.title)
          }
        }
        .disabled(!action.isEnabled)
      }
    } label: {
      if let systemImage = node.systemImage {
        Label(node.text, systemImage: systemImage)
      } else {
        Text(node.text)
      }
    }
  }

  private var disclosureGroup: some View {
    DisclosureGroup(
      isExpanded: Binding(
        get: { node.isDisclosureExpanded },
        set: { isExpanded in
          node.isDisclosureExpanded = isExpanded
          model.sendChange(node.changeEventId, text: isExpanded ? "true" : "false")
        }
      )
    ) {
      childViews
    } label: {
      Text(node.text)
    }
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private var font: Font {
    switch node.textStyle {
    case 0: return .largeTitle
    case 1: return .title
    case 2: return .title2
    case 3: return .title3
    case 4: return .headline
    case 6: return .callout
    case 7: return .subheadline
    case 8: return .footnote
    case 9: return .caption
    case 10: return .caption2
    default: return .body
    }
  }

  private var weight: Font.Weight {
    switch node.textWeight {
    case 1: return .semibold
    case 2: return .bold
    default: return .regular
    }
  }

  private var color: Color {
    ocaml_demoNativeSemanticColor(node.textColor) ?? .primary
  }

  @ViewBuilder
  private func applyModifiers<Content: View>(to content: Content) -> some View {
    let base = bottomSafeAreaInset(
      appearAction(
        tapAction(
          contextMenu(
            regularMaterialPanel(
              secondarySystemGroupedPanel(
                secondaryFillPanel(
                  liquidGlassPanel(
                    content
                    .padding(node.padding ?? EdgeInsets())
                    .frame(
                      width: node.frameWidth,
                      height: node.frameHeight,
                      alignment: node.frameAlignment
                    )
                    .frame(maxWidth: node.frameMaxWidth, alignment: node.frameAlignment)
                  )
                )
              )
            )
          )
        )
      )
    )
      .modifier(OCamlDemoNavigationTitleModifier(node: node))
      .modifier(OCamlDemoListRowSeparatorModifier(node: node))
      .alert(
        node.alertTitle,
        isPresented: Binding(
          get: { node.isAlertPresented },
          set: { value in
            node.isAlertPresented = value
            if !value {
              model.sendClick(node.alertDismissEventId)
            }
          }
        )
      ) {
        if node.alertText != nil {
          TextField(
            node.alertPlaceholder ?? "",
            text: Binding(
              get: { node.alertText ?? "" },
              set: { value in
                node.alertText = value
                model.sendChange(node.alertTextEventId, text: value)
              }
            )
          )
        }
        ForEach(node.alertActions) { action in
          Button(role: alertButtonRole(action.role)) {
            model.sendClick(action.eventId)
          } label: {
            Text(action.title)
          }
          .disabled(!action.isEnabled)
        }
      } message: {
        if let message = node.alertMessage {
          Text(message)
        }
      }
      .confirmationDialog(
        node.confirmationDialogTitle,
        isPresented: Binding(
          get: { node.isConfirmationDialogPresented },
          set: { value in
            node.isConfirmationDialogPresented = value
            if !value {
              model.sendClick(node.confirmationDialogDismissEventId)
            }
          }
        )
      ) {
        ForEach(node.confirmationDialogActions) { action in
          Button(role: alertButtonRole(action.role)) {
            model.sendClick(action.eventId)
          } label: {
            Text(action.title)
          }
          .disabled(!action.isEnabled)
        }
      } message: {
        if let message = node.confirmationDialogMessage {
          Text(message)
        }
      }
      .popover(
        isPresented: Binding(
          get: { node.isPopoverPresented },
          set: { value in
            node.isPopoverPresented = value
            if !value {
              model.sendClick(node.popoverDismissEventId)
            }
          }
        )
      ) {
        if let popoverContent = node.popoverContent {
          OCamlDemoNodeView(node: popoverContent, model: model)
        }
      }

    if node.isSearchable {
      let text = Binding(
        get: { node.searchText },
        set: { value in
          node.searchText = value
          model.sendChange(node.searchEventId, text: value)
        }
      )
      let isPresented = Binding(
        get: { node.isSearchPresented },
        set: { value in
          node.isSearchPresented = value
          model.sendChange(node.searchPresentationEventId, text: value ? "true" : "false")
        }
      )
      if node.hasSearchPresentation, let prompt = node.searchPrompt {
        base
          .searchable(text: text, isPresented: isPresented, placement: .toolbar, prompt: Text(prompt))
          .sheet(isPresented: sheetBinding) {
            if let sheetContent = node.sheetContent {
              ocaml_demoSheetContentHost {
                OCamlDemoNodeView(node: sheetContent, model: model)
              }
            }
          }
      } else if node.hasSearchPresentation {
        base
          .searchable(text: text, isPresented: isPresented, placement: .toolbar)
          .sheet(isPresented: sheetBinding) {
          if let sheetContent = node.sheetContent {
            ocaml_demoSheetContentHost {
              OCamlDemoNodeView(node: sheetContent, model: model)
            }
          }
        }
      } else if let prompt = node.searchPrompt {
        base
          .searchable(text: text, placement: .toolbar, prompt: Text(prompt))
          .sheet(isPresented: sheetBinding) {
            if let sheetContent = node.sheetContent {
              ocaml_demoSheetContentHost {
                OCamlDemoNodeView(node: sheetContent, model: model)
              }
            }
          }
      } else {
        base
          .searchable(text: text, placement: .toolbar)
          .sheet(isPresented: sheetBinding) {
          if let sheetContent = node.sheetContent {
            ocaml_demoSheetContentHost {
              OCamlDemoNodeView(node: sheetContent, model: model)
            }
          }
        }
      }
    } else {
      base
        .sheet(isPresented: sheetBinding) {
          if let sheetContent = node.sheetContent {
            ocaml_demoSheetContentHost {
              OCamlDemoNodeView(node: sheetContent, model: model)
            }
          }
      }
    }
  }

  private func ocaml_demoSheetContentHost<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ZStack(alignment: .topLeading) {
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
  }

  private func customButtonLabelHitTarget<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .contentShape(Rectangle())
  }

  @ViewBuilder
  private func bottomSafeAreaInset<InsetContent: View>(_ content: InsetContent) -> some View {
    if let bottomSafeAreaInsetContent = node.bottomSafeAreaInsetContent {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        OCamlDemoNodeView(node: bottomSafeAreaInsetContent, model: model)
      }
    } else {
      content
    }
  }

  @ViewBuilder
  private func regularMaterialPanel<PanelContent: View>(_ content: PanelContent) -> some View {
    if let cornerRadius = node.regularMaterialPanelCornerRadius {
      content.background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      content
    }
  }

  @ViewBuilder
  private func secondarySystemGroupedPanel<PanelContent: View>(_ content: PanelContent) -> some View {
    if let cornerRadius = node.secondarySystemGroupedPanelCornerRadius {
      content.background(
        Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      content
    }
  }

  @ViewBuilder
  private func secondaryFillPanel<PanelContent: View>(_ content: PanelContent) -> some View {
    if let cornerRadius = node.secondaryFillPanelCornerRadius {
      content.background(
        Color.secondary.opacity(node.secondaryFillPanelOpacity),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
    } else {
      content
    }
  }

  @ViewBuilder
  private func liquidGlassPanel<PanelContent: View>(_ content: PanelContent) -> some View {
    if let cornerRadius = node.liquidGlassPanelCornerRadius {
      let tint = ocaml_demoNativeSemanticColor(node.liquidGlassPanelTintColor)?
        .opacity(node.liquidGlassPanelTintOpacity)
      content.ocaml_demoLiquidGlassPanel(
        cornerRadius: cornerRadius,
        isTransparent: node.liquidGlassPanelIsTransparent,
        tint: tint
      )
    } else {
      content
    }
  }

  @ViewBuilder
  private func contextMenu<MenuContent: View>(_ content: MenuContent) -> some View {
    if node.contextMenuActions.isEmpty {
      content
    } else {
      content.contextMenu {
        ForEach(node.contextMenuActions) { action in
          Button(role: action.style == 1 ? .destructive : nil) {
            if let eventId = action.eventId {
              model.sendClick(eventId)
            }
          } label: {
            if let systemImage = action.systemImage {
              Label(action.title, systemImage: systemImage)
            } else {
              Text(action.title)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func tapAction<TapContent: View>(_ content: TapContent) -> some View {
    if let tapEventId = node.tapEventId {
      content
        .contentShape(.rect)
        .onTapGesture {
          model.sendClick(tapEventId)
        }
    } else {
      content
    }
  }

  @ViewBuilder
  private func appearAction<AppearContent: View>(_ content: AppearContent) -> some View {
    if let appearEventId = node.appearEventId {
      content
        .onAppear {
          model.sendClick(appearEventId)
        }
    } else {
      content
    }
  }

  private var sheetBinding: Binding<Bool> {
    Binding(
      get: { node.isSheetPresented },
      set: { value in
        node.isSheetPresented = value
        if !value {
          model.sendClick(node.dismissEventId)
        }
      }
    )
  }
}

private struct OCamlDemoDeleteAwareTextField: NSViewRepresentable {
  let placeholder: String
  @Binding var text: String
  let isFocused: Bool
  let onChange: (String) -> Void
  let onSubmit: () -> Void
  let onDeleteBackwardAtStart: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSTextField {
    let textField = NSTextField()
    textField.delegate = context.coordinator
    textField.placeholderString = placeholder
    textField.stringValue = text
    textField.isBordered = false
    textField.isBezeled = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return textField
  }

  func updateNSView(_ textField: NSTextField, context: Context) {
    context.coordinator.parent = self
    textField.placeholderString = placeholder
    if textField.stringValue != text {
      textField.stringValue = text
    }
    if isFocused && textField.window?.firstResponder !== textField.currentEditor() {
      DispatchQueue.main.async {
        textField.window?.makeFirstResponder(textField)
        if let editor = textField.currentEditor() {
          editor.selectedRange = NSRange(location: textField.stringValue.count, length: 0)
        }
      }
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: OCamlDemoDeleteAwareTextField

    init(_ parent: OCamlDemoDeleteAwareTextField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let textField = notification.object as? NSTextField else { return }
      if parent.text != textField.stringValue {
        parent.text = textField.stringValue
        parent.onChange(textField.stringValue)
      }
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
        let selectedRange = textView.selectedRange()
        if selectedRange.location == 0 && selectedRange.length == 0 {
          parent.onDeleteBackwardAtStart()
          return true
        }
      }

      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        parent.onSubmit()
        return true
      }

      return false
    }
  }
}

private struct OCamlDemoCongratsEffectView: View {
  var body: some View {
    ZStack {
      ForEach(0..<28, id: \.self) { index in
        OCamlDemoCongratsParticle(index: index)
      }
      VStack(spacing: 8) {
        Image(systemName: "sparkles")
          .font(.system(size: 44, weight: .semibold))
        Text("Complete")
          .font(.title2.weight(.semibold))
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 22)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .shadow(radius: 18)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct OCamlDemoCongratsParticle: View {
  let index: Int
  @State private var isExpanded = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
      .offset(isExpanded ? endOffset : .zero)
      .opacity(isExpanded ? 0 : 1)
      .scaleEffect(isExpanded ? 0.6 : 1.2)
      .onAppear {
        withAnimation(.easeOut(duration: duration).delay(delay)) {
          isExpanded = true
        }
      }
  }

  private var color: Color {
    [Color.blue, .green, .orange, .pink, .purple][index % 5]
  }

  private var size: CGFloat {
    CGFloat(7 + (index % 4) * 3)
  }

  private var delay: Double {
    Double(index % 6) * 0.025
  }

  private var duration: Double {
    0.85 + Double(index % 5) * 0.08
  }

  private var endOffset: CGSize {
    let angle = Double(index) / 28.0 * Double.pi * 2.0
    let radius = CGFloat(92 + (index % 6) * 18)
    return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
  }
}

private func alertButtonRole(_ rawRole: Int32) -> ButtonRole? {
  switch rawRole {
  case 1: return .cancel
  case 2: return .destructive
  default: return nil
  }
}

@_cdecl("ocaml_demo_native_swiftui_run_application")
public func ocaml_demo_native_swiftui_run_application(_ callback: OCamlDemoLaunchCallback?) {
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)
  _ = callback?(nil, Unmanaged.passUnretained(app).toOpaque(), nil)
  app.activate(ignoringOtherApps: true)
  app.run()
}

@_cdecl("ocaml_demo_native_swiftui_create_node")
public func ocaml_demo_native_swiftui_create_node(_ rawKind: Int32) -> UnsafeMutableRawPointer? {
  guard let kind = NodeKind(rawValue: rawKind) else { return nil }
  return Unmanaged.passRetained(OCamlDemoNode(kind: kind)).toOpaque()
}

@_cdecl("ocaml_demo_native_swiftui_release_node")
public func ocaml_demo_native_swiftui_release_node(_ pointer: UnsafeMutableRawPointer?) {
  guard let pointer else { return }
  Unmanaged<OCamlDemoNode>.fromOpaque(pointer).release()
}

@_cdecl("ocaml_demo_native_swiftui_set_text")
public func ocaml_demo_native_swiftui_set_text(_ pointer: UnsafeMutableRawPointer?, _ textPointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.text = textPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_system_image")
public func ocaml_demo_native_swiftui_set_system_image(_ pointer: UnsafeMutableRawPointer?, _ systemImagePointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.systemImage = systemImagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_button_subtitle")
public func ocaml_demo_native_swiftui_set_button_subtitle(_ pointer: UnsafeMutableRawPointer?, _ subtitlePointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.buttonSubtitle = subtitlePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_button_style")
public func ocaml_demo_native_swiftui_set_button_style(_ pointer: UnsafeMutableRawPointer?, _ style: Int32) {
  nativeNode(from: pointer)?.buttonStyle = style
}

@_cdecl("ocaml_demo_native_swiftui_set_title_visible")
public func ocaml_demo_native_swiftui_set_title_visible(_ pointer: UnsafeMutableRawPointer?, _ isVisible: Bool) {
  nativeNode(from: pointer)?.isTitleVisible = isVisible
}

@_cdecl("ocaml_demo_native_swiftui_set_keyboard_dismiss_controls")
public func ocaml_demo_native_swiftui_set_keyboard_dismiss_controls(
  _ pointer: UnsafeMutableRawPointer?,
  _ isEnabled: Bool
) {
  nativeNode(from: pointer)?.keyboardDismissControls = isEnabled
}

@_cdecl("ocaml_demo_native_swiftui_set_scroll_dismisses_keyboard")
public func ocaml_demo_native_swiftui_set_scroll_dismisses_keyboard(
  _ pointer: UnsafeMutableRawPointer?,
  _ isEnabled: Bool
) {
  nativeNode(from: pointer)?.scrollDismissesKeyboard = isEnabled
}

@_cdecl("ocaml_demo_native_swiftui_set_hide_list_row_separator")
public func ocaml_demo_native_swiftui_set_hide_list_row_separator(
  _ pointer: UnsafeMutableRawPointer?,
  _ isHidden: Bool
) {
  nativeNode(from: pointer)?.hideListRowSeparator = isHidden
}

@_cdecl("ocaml_demo_native_swiftui_set_image_source")
public func ocaml_demo_native_swiftui_set_image_source(_ pointer: UnsafeMutableRawPointer?, _ source: Int32) {
  nativeNode(from: pointer)?.imageSource = source
}

@_cdecl("ocaml_demo_native_swiftui_set_image_color")
public func ocaml_demo_native_swiftui_set_image_color(_ pointer: UnsafeMutableRawPointer?, _ color: Int32) {
  nativeNode(from: pointer)?.imageColor = color
}

@_cdecl("ocaml_demo_native_swiftui_set_image_style")
public func ocaml_demo_native_swiftui_set_image_style(
  _ pointer: UnsafeMutableRawPointer?,
  _ maxHeight: Double,
  _ cornerRadius: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.imageMaxHeight = maxHeight < 0 ? nil : CGFloat(maxHeight)
  node.imageCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("ocaml_demo_native_swiftui_set_text_attributes")
public func ocaml_demo_native_swiftui_set_text_attributes(
  _ pointer: UnsafeMutableRawPointer?,
  _ style: Int32,
  _ weight: Int32,
  _ color: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textStyle = style
  node.textWeight = weight
  node.textColor = color
}

@_cdecl("ocaml_demo_native_swiftui_set_enabled")
public func ocaml_demo_native_swiftui_set_enabled(_ pointer: UnsafeMutableRawPointer?, _ isEnabled: Bool) {
  nativeNode(from: pointer)?.isEnabled = isEnabled
}

@_cdecl("ocaml_demo_native_swiftui_set_progress")
public func ocaml_demo_native_swiftui_set_progress(_ pointer: UnsafeMutableRawPointer?, _ value: Double) {
  nativeNode(from: pointer)?.progressValue = min(max(value, 0), 1)
}

@_cdecl("ocaml_demo_native_swiftui_set_placeholder")
public func ocaml_demo_native_swiftui_set_placeholder(_ pointer: UnsafeMutableRawPointer?, _ textPointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.placeholder = textPointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_style")
public func ocaml_demo_native_swiftui_set_text_field_style(_ pointer: UnsafeMutableRawPointer?, _ style: Int32) {
  nativeNode(from: pointer)?.textFieldStyle = style
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_axis")
public func ocaml_demo_native_swiftui_set_text_field_axis(_ pointer: UnsafeMutableRawPointer?, _ axis: Int32) {
  nativeNode(from: pointer)?.textFieldAxis = axis
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_clear_button")
public func ocaml_demo_native_swiftui_set_text_field_clear_button(
  _ pointer: UnsafeMutableRawPointer?,
  _ clearButton: Int32
) {
  nativeNode(from: pointer)?.textFieldClearButton = clearButton
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_secure")
public func ocaml_demo_native_swiftui_set_text_field_secure(_ pointer: UnsafeMutableRawPointer?, _ isSecure: Bool) {
  nativeNode(from: pointer)?.isTextFieldSecure = isSecure
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_focus")
public func ocaml_demo_native_swiftui_set_text_field_focus(_ pointer: UnsafeMutableRawPointer?, _ isFocused: Bool) {
  guard let node = nativeNode(from: pointer) else { return }
  if node.isTextFieldFocused != isFocused {
    node.isTextFieldFocused = isFocused
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_blur")
public func ocaml_demo_native_swiftui_set_text_field_blur(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  nativeNode(from: pointer)?.textFieldBlurEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_delete_backward_at_start")
public func ocaml_demo_native_swiftui_set_text_field_delete_backward_at_start(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  nativeNode(from: pointer)?.textFieldDeleteBackwardAtStartEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_toggle")
public func ocaml_demo_native_swiftui_set_toggle(_ pointer: UnsafeMutableRawPointer?, _ isOn: Bool, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isToggleOn = isOn
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_spacing")
public func ocaml_demo_native_swiftui_set_spacing(_ pointer: UnsafeMutableRawPointer?, _ spacing: Double) {
  nativeNode(from: pointer)?.spacing = spacing < 0 ? nil : CGFloat(spacing)
}

@_cdecl("ocaml_demo_native_swiftui_set_horizontal_stack_alignment")
public func ocaml_demo_native_swiftui_set_horizontal_stack_alignment(_ pointer: UnsafeMutableRawPointer?, _ alignment: Int32) {
  nativeNode(from: pointer)?.horizontalStackAlignment = alignment == 1 ? .top : .center
}

@_cdecl("ocaml_demo_native_swiftui_set_grid")
public func ocaml_demo_native_swiftui_set_grid(
  _ pointer: UnsafeMutableRawPointer?,
  _ columns: Int32,
  _ spacing: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.gridColumns = max(1, Int(columns))
  node.gridSpacing = CGFloat(spacing)
}

@_cdecl("ocaml_demo_native_swiftui_set_children")
public func ocaml_demo_native_swiftui_set_children(
  _ pointer: UnsafeMutableRawPointer?,
  _ childPointers: UnsafePointer<UnsafeMutableRawPointer?>?,
  _ count: Int32
) {
  guard let node = nativeNode(from: pointer), let childPointers else { return }
  let children = (0..<Int(count)).compactMap { nativeNode(from: childPointers[$0]) }
  if !sameNodeSequence(node.children, children) {
    node.children = children
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_lazy_list_rows")
public func ocaml_demo_native_swiftui_set_lazy_list_rows(
  _ pointer: UnsafeMutableRawPointer?,
  _ providerId: Int32,
  _ count: Int32,
  _ version: Int32,
  _ invalidatedIndexPointer: UnsafePointer<Int32>?,
  _ invalidatedIndexCount: Int32,
  _ identityIndexPointer: UnsafePointer<Int32>?,
  _ identityKeyPointer: UnsafePointer<UnsafePointer<CChar>?>?,
  _ identityKeyCount: Int32,
  _ cachedIndexPointer: UnsafePointer<Int32>?,
  _ cachedKeyPointer: UnsafePointer<UnsafePointer<CChar>?>?,
  _ cachedRowPointer: UnsafePointer<UnsafeMutableRawPointer?>?,
  _ cachedRowCount: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  if count <= 0 && !node.children.isEmpty {
    node.children = []
  }
}

@_cdecl("ocaml_demo_native_swiftui_clear_lazy_list_rows")
public func ocaml_demo_native_swiftui_clear_lazy_list_rows(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  if !node.children.isEmpty {
    node.children = []
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_lazy_list_rows_published_event")
public func ocaml_demo_native_swiftui_set_lazy_list_rows_published_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
}

@_cdecl("ocaml_demo_native_swiftui_register_lazy_list_callbacks")
public func ocaml_demo_native_swiftui_register_lazy_list_callbacks(
  _ keyCallback: OCamlDemoLazyRowKeyCallback?,
  _ renderCallback: OCamlDemoLazyRowRenderCallback?,
  _ releaseCallback: OCamlDemoLazyRowReleaseCallback?
) {
}

@_cdecl("ocaml_demo_native_swiftui_set_list_behavior")
public func ocaml_demo_native_swiftui_set_list_behavior(
  _ pointer: UnsafeMutableRawPointer?,
  _ refreshEventId: Int32,
  _ deleteEventId: Int32,
  _ moveEventId: Int32,
  _ editMode: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextRefreshEventId = refreshEventId < 0 ? nil : refreshEventId
  let nextDeleteEventId = deleteEventId < 0 ? nil : deleteEventId
  let nextMoveEventId = moveEventId < 0 ? nil : moveEventId
  if node.listRefreshEventId != nextRefreshEventId {
    node.listRefreshEventId = nextRefreshEventId
  }
  if node.listDeleteEventId != nextDeleteEventId {
    node.listDeleteEventId = nextDeleteEventId
  }
  if node.listMoveEventId != nextMoveEventId {
    node.listMoveEventId = nextMoveEventId
  }
  if node.isListEditMode != editMode {
    node.isListEditMode = editMode
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_list_focused_row_index")
public func ocaml_demo_native_swiftui_set_list_focused_row_index(
  _ pointer: UnsafeMutableRawPointer?,
  _ focusedRowIndex: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextFocusedRowIndex = focusedRowIndex < 0 ? nil : Int(focusedRowIndex)
  if node.listFocusedRowIndex != nextFocusedRowIndex {
    node.listFocusedRowIndex = nextFocusedRowIndex
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_list_focused_row_disappear_event")
public func ocaml_demo_native_swiftui_set_list_focused_row_disappear_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextEventId = eventId < 0 ? nil : eventId
  if node.listFocusedRowDisappearEventId != nextEventId {
    node.listFocusedRowDisappearEventId = nextEventId
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_on_click")
public func ocaml_demo_native_swiftui_set_on_click(_ pointer: UnsafeMutableRawPointer?, _ eventId: Int32) {
  nativeNode(from: pointer)?.clickEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_navigation_link_callbacks")
public func ocaml_demo_native_swiftui_set_navigation_link_callbacks(
  _ pointer: UnsafeMutableRawPointer?,
  _ activateEventId: Int32,
  _ deactivateEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.navigationActivateEventId = activateEventId < 0 ? nil : activateEventId
  node.navigationDeactivateEventId = deactivateEventId < 0 ? nil : deactivateEventId
}

@_cdecl("ocaml_demo_native_swiftui_set_navigation_link_value")
public func ocaml_demo_native_swiftui_set_navigation_link_value(
  _ pointer: UnsafeMutableRawPointer?,
  _ value: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.navigationLinkValue = value.map { String(cString: $0) }
}

@_cdecl("ocaml_demo_native_swiftui_set_tap_action")
public func ocaml_demo_native_swiftui_set_tap_action(_ pointer: UnsafeMutableRawPointer?, _ eventId: Int32) {
  nativeNode(from: pointer)?.tapEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_horizontal_swipe")
public func ocaml_demo_native_swiftui_set_horizontal_swipe(
  _ pointer: UnsafeMutableRawPointer?,
  _ leftEventId: Int32,
  _ rightEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.horizontalSwipeLeftEventId = leftEventId < 0 ? nil : leftEventId
  node.horizontalSwipeRightEventId = rightEventId < 0 ? nil : rightEventId
}

@_cdecl("ocaml_demo_native_swiftui_set_on_appear")
public func ocaml_demo_native_swiftui_set_on_appear(_ pointer: UnsafeMutableRawPointer?, _ eventId: Int32) {
  nativeNode(from: pointer)?.appearEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_on_change")
public func ocaml_demo_native_swiftui_set_on_change(_ pointer: UnsafeMutableRawPointer?, _ eventId: Int32) {
  nativeNode(from: pointer)?.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_subtitle")
public func ocaml_demo_native_swiftui_set_list_row_subtitle(_ pointer: UnsafeMutableRawPointer?, _ subtitlePointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.rowSubtitle = subtitlePointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_trailing_text")
public func ocaml_demo_native_swiftui_set_list_row_trailing_text(_ pointer: UnsafeMutableRawPointer?, _ trailingTextPointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.rowTrailingText = trailingTextPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_content_style")
public func ocaml_demo_native_swiftui_set_list_row_content_style(_ pointer: UnsafeMutableRawPointer?, _ contentStyle: Int32) {
  nativeNode(from: pointer)?.rowContentStyle = contentStyle
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_accessory")
public func ocaml_demo_native_swiftui_set_list_row_accessory(_ pointer: UnsafeMutableRawPointer?, _ accessory: Int32) {
  nativeNode(from: pointer)?.rowAccessory = accessory
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_title_strikethrough")
public func ocaml_demo_native_swiftui_set_list_row_title_strikethrough(_ pointer: UnsafeMutableRawPointer?, _ value: Bool) {
  nativeNode(from: pointer)?.rowTitleStrikethrough = value
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_leading_system_image")
public func ocaml_demo_native_swiftui_set_list_row_leading_system_image(_ pointer: UnsafeMutableRawPointer?, _ systemImagePointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.rowStaticLeadingSystemImage = systemImagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_preview_image_path")
public func ocaml_demo_native_swiftui_set_list_row_preview_image_path(_ pointer: UnsafeMutableRawPointer?, _ imagePathPointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.rowPreviewImagePath = imagePathPointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_leading")
public func ocaml_demo_native_swiftui_set_list_row_leading(
  _ pointer: UnsafeMutableRawPointer?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ selectedSystemImagePointer: UnsafePointer<CChar>?,
  _ selected: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowLeadingSystemImage = systemImagePointer.map(String.init(cString:))
  node.rowLeadingSelectedSystemImage = selectedSystemImagePointer.map(String.init(cString:))
  node.rowLeadingSelected = selected
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_leading_accessibility")
public func ocaml_demo_native_swiftui_set_list_row_leading_accessibility(_ pointer: UnsafeMutableRawPointer?, _ labelPointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.rowLeadingAccessibilityLabel = labelPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_leading_event")
public func ocaml_demo_native_swiftui_set_list_row_leading_event(_ pointer: UnsafeMutableRawPointer?, _ eventId: Int32) {
  nativeNode(from: pointer)?.rowLeadingEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_clear_list_row_actions")
public func ocaml_demo_native_swiftui_clear_list_row_actions(_ pointer: UnsafeMutableRawPointer?) {
  nativeNode(from: pointer)?.rowActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_list_row_action")
public func ocaml_demo_native_swiftui_append_list_row_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let titlePointer else { return }
  node.rowActions.append(
    OCamlDemoRowAction(
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      eventId: eventId < 0 ? nil : eventId,
      startsSection: false,
      exportFilename: nil,
      exportContentType: nil,
      exportContent: nil
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_clear_list_row_menu_actions")
public func ocaml_demo_native_swiftui_clear_list_row_menu_actions(_ pointer: UnsafeMutableRawPointer?) {
  nativeNode(from: pointer)?.rowMenuActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_list_row_menu_action")
public func ocaml_demo_native_swiftui_append_list_row_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let titlePointer else { return }
  node.rowMenuActions.append(
    OCamlDemoRowAction(
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      eventId: eventId < 0 ? nil : eventId,
      startsSection: false,
      exportFilename: nil,
      exportContentType: nil,
      exportContent: nil
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_clear_context_menu_actions")
public func ocaml_demo_native_swiftui_clear_context_menu_actions(_ pointer: UnsafeMutableRawPointer?) {
  nativeNode(from: pointer)?.contextMenuActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_context_menu_action")
public func ocaml_demo_native_swiftui_append_context_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let titlePointer else { return }
  node.contextMenuActions.append(
    OCamlDemoRowAction(
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      eventId: eventId < 0 ? nil : eventId,
      startsSection: false,
      exportFilename: nil,
      exportContentType: nil,
      exportContent: nil
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_searchable")
public func ocaml_demo_native_swiftui_set_searchable(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32,
  _ textPointer: UnsafePointer<CChar>?,
  _ promptPointer: UnsafePointer<CChar>?,
  _ hasPresentation: Bool,
  _ isPresented: Bool,
  _ presentationEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isSearchable = eventId >= 0
  node.searchEventId = eventId < 0 ? nil : eventId
  node.searchText = textPointer.map(String.init(cString:)) ?? ""
  node.searchPrompt = promptPointer.map(String.init(cString:))
  node.hasSearchPresentation = hasPresentation
  node.isSearchPresented = isPresented
  node.searchPresentationEventId = presentationEventId < 0 ? nil : presentationEventId
}

@_cdecl("ocaml_demo_native_swiftui_set_sheet")
public func ocaml_demo_native_swiftui_set_sheet(
  _ pointer: UnsafeMutableRawPointer?,
  _ contentPointer: UnsafeMutableRawPointer?,
  _ isPresented: Bool,
  _ dismissEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.sheetContent = nativeNode(from: contentPointer)
  node.isSheetPresented = isPresented
  node.dismissEventId = dismissEventId < 0 ? nil : dismissEventId
}

@_cdecl("ocaml_demo_native_swiftui_set_sheet_detents")
public func ocaml_demo_native_swiftui_set_sheet_detents(_ pointer: UnsafeMutableRawPointer?, _ kindsPointer: UnsafeMutablePointer<Int32>?, _ valuesPointer: UnsafeMutablePointer<Double>?, _ count: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  guard count > 0, let kindsPointer, let valuesPointer else {
    node.sheetDetents = []
    return
  }
  node.sheetDetents = (0..<Int(count)).map { index in
    OCamlDemoPresentationDetent(kind: kindsPointer[index], value: valuesPointer[index])
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_safe_area_inset_bottom")
public func ocaml_demo_native_swiftui_set_safe_area_inset_bottom(
  _ pointer: UnsafeMutableRawPointer?,
  _ contentPointer: UnsafeMutableRawPointer?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.bottomSafeAreaInsetContent = nativeNode(from: contentPointer)
}

@_cdecl("ocaml_demo_native_swiftui_set_popover")
public func ocaml_demo_native_swiftui_set_popover(_ pointer: UnsafeMutableRawPointer?, _ contentPointer: UnsafeMutableRawPointer?, _ isPresented: Bool, _ dismissEventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.popoverContent = nativeNode(from: contentPointer)
  node.isPopoverPresented = isPresented
  node.popoverDismissEventId = dismissEventId < 0 ? nil : dismissEventId
}

@_cdecl("ocaml_demo_native_swiftui_set_alert")
public func ocaml_demo_native_swiftui_set_alert(
  _ pointer: UnsafeMutableRawPointer?,
  _ isPresented: Bool,
  _ dismissEventId: Int32,
  _ titlePointer: UnsafePointer<CChar>?,
  _ messagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isAlertPresented = isPresented
  node.alertDismissEventId = dismissEventId < 0 ? nil : dismissEventId
  node.alertTitle = titlePointer.map(String.init(cString:)) ?? ""
  node.alertMessage = messagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_alert_text_field")
public func ocaml_demo_native_swiftui_set_alert_text_field(
  _ pointer: UnsafeMutableRawPointer?,
  _ textPointer: UnsafePointer<CChar>?,
  _ placeholderPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.alertText = textPointer.map(String.init(cString:))
  node.alertPlaceholder = placeholderPointer.map(String.init(cString:))
  node.alertTextEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_clear_alert_actions")
public func ocaml_demo_native_swiftui_clear_alert_actions(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.alertActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_alert_action")
public func ocaml_demo_native_swiftui_append_alert_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ role: Int32,
  _ isEnabled: Bool,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer),
        let idPointer,
        let titlePointer else { return }
  node.alertActions.append(
    OCamlDemoAlertAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      role: role,
      isEnabled: isEnabled,
      eventId: eventId < 0 ? nil : eventId
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_confirmation_dialog")
public func ocaml_demo_native_swiftui_set_confirmation_dialog(_ pointer: UnsafeMutableRawPointer?, _ isPresented: Bool, _ dismissEventId: Int32, _ titlePointer: UnsafePointer<CChar>?, _ messagePointer: UnsafePointer<CChar>?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isConfirmationDialogPresented = isPresented
  node.confirmationDialogDismissEventId = dismissEventId < 0 ? nil : dismissEventId
  node.confirmationDialogTitle = titlePointer.map(String.init(cString:)) ?? ""
  node.confirmationDialogMessage = messagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_clear_confirmation_dialog_actions")
public func ocaml_demo_native_swiftui_clear_confirmation_dialog_actions(_ pointer: UnsafeMutableRawPointer?) {
  nativeNode(from: pointer)?.confirmationDialogActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_confirmation_dialog_action")
public func ocaml_demo_native_swiftui_append_confirmation_dialog_action(_ pointer: UnsafeMutableRawPointer?, _ idPointer: UnsafePointer<CChar>?, _ titlePointer: UnsafePointer<CChar>?, _ role: Int32, _ isEnabled: Bool, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.confirmationDialogActions.append(
    OCamlDemoAlertAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      role: role,
      isEnabled: isEnabled,
      eventId: eventId < 0 ? nil : eventId
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_navigation_title")
public func ocaml_demo_native_swiftui_set_navigation_title(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.navigationTitle = titlePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_clear_toolbar")
public func ocaml_demo_native_swiftui_clear_toolbar(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.toolbarItems = []
  node.toolbarContents = []
}

@_cdecl("ocaml_demo_native_swiftui_append_toolbar_group")
public func ocaml_demo_native_swiftui_append_toolbar_group(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ placement: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer else { return }
  node.toolbarContents.append(
    OCamlDemoToolbarContent(
      id: String(cString: idPointer),
      kind: .group,
      placement: OCamlDemoToolbarPlacement(rawValue: placement) ?? .automatic,
      fixed: false,
      items: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_append_toolbar_spacer")
public func ocaml_demo_native_swiftui_append_toolbar_spacer(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ placement: Int32,
  _ fixed: Bool
) {
  guard let node = nativeNode(from: pointer), let idPointer else { return }
  node.toolbarContents.append(
    OCamlDemoToolbarContent(
      id: String(cString: idPointer),
      kind: .spacer,
      placement: OCamlDemoToolbarPlacement(rawValue: placement) ?? .automatic,
      fixed: fixed,
      items: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_clear_keyboard_toolbar")
public func ocaml_demo_native_swiftui_clear_keyboard_toolbar(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.keyboardToolbarItems = []
}

@_cdecl("ocaml_demo_native_swiftui_append_toolbar_item")
public func ocaml_demo_native_swiftui_append_toolbar_item(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ isTitleVisible: Bool,
  _ isEnabled: Bool,
  _ shareURLPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.toolbarItems.append(
    OCamlDemoToolbarItem(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      isTitleVisible: isTitleVisible,
      eventId: eventId < 0 ? nil : eventId,
      isEnabled: isEnabled,
      shareURL: shareURLPointer.map(String.init(cString:)),
      menuActions: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_append_toolbar_group_item")
public func ocaml_demo_native_swiftui_append_toolbar_group_item(
  _ pointer: UnsafeMutableRawPointer?,
  _ groupIdPointer: UnsafePointer<CChar>?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ isTitleVisible: Bool,
  _ isEnabled: Bool,
  _ shareURLPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer),
        let groupIdPointer,
        let idPointer,
        let titlePointer else { return }
  let groupId = String(cString: groupIdPointer)
  guard let groupIndex = node.toolbarContents.firstIndex(where: {
    $0.id == groupId && $0.kind == .group
  }) else { return }
  node.toolbarContents[groupIndex].items.append(
    OCamlDemoToolbarItem(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      isTitleVisible: isTitleVisible,
      eventId: eventId < 0 ? nil : eventId,
      isEnabled: isEnabled,
      shareURL: shareURLPointer.map(String.init(cString:)),
      menuActions: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_append_keyboard_toolbar_item")
public func ocaml_demo_native_swiftui_append_keyboard_toolbar_item(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ isTitleVisible: Bool,
  _ isEnabled: Bool,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer),
        let idPointer,
        let titlePointer else { return }
  node.keyboardToolbarItems.append(
    OCamlDemoToolbarItem(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      isTitleVisible: isTitleVisible,
      eventId: eventId < 0 ? nil : eventId,
      isEnabled: isEnabled,
      shareURL: nil,
      menuActions: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_append_toolbar_menu_action")
public func ocaml_demo_native_swiftui_append_toolbar_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ itemIdPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32,
  _ startsSection: Bool,
  _ exportFilenamePointer: UnsafePointer<CChar>?,
  _ exportContentTypePointer: UnsafePointer<CChar>?,
  _ exportContentPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer), let itemIdPointer, let titlePointer else { return }
  let itemId = String(cString: itemIdPointer)
  let action = OCamlDemoRowAction(
    title: String(cString: titlePointer),
    systemImage: systemImagePointer.map(String.init(cString:)),
    style: style,
    eventId: eventId < 0 ? nil : eventId,
    startsSection: startsSection,
    exportFilename: exportFilenamePointer.map(String.init(cString:)),
    exportContentType: exportContentTypePointer.map(String.init(cString:)),
    exportContent: exportContentPointer.map(String.init(cString:))
  )
  if let index = node.toolbarItems.firstIndex(where: { $0.id == itemId }) {
    node.toolbarItems[index].menuActions.append(action)
    return
  }
  for contentIndex in node.toolbarContents.indices {
    guard node.toolbarContents[contentIndex].kind == .group else { continue }
    if let itemIndex = node.toolbarContents[contentIndex].items.firstIndex(where: {
      $0.id == itemId
    }) {
      node.toolbarContents[contentIndex].items[itemIndex].menuActions.append(action)
      return
    }
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_padding")
public func ocaml_demo_native_swiftui_set_padding(_ pointer: UnsafeMutableRawPointer?, _ top: Double, _ leading: Double, _ bottom: Double, _ trailing: Double) {
  nativeNode(from: pointer)?.padding =
    top < 0 || leading < 0 || bottom < 0 || trailing < 0
    ? nil
    : EdgeInsets(top: CGFloat(top), leading: CGFloat(leading), bottom: CGFloat(bottom), trailing: CGFloat(trailing))
}

@_cdecl("ocaml_demo_native_swiftui_set_frame")
public func ocaml_demo_native_swiftui_set_frame(
  _ pointer: UnsafeMutableRawPointer?,
  _ width: Double,
  _ height: Double,
  _ maxWidth: Double,
  _ alignment: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.frameWidth = width < 0 ? nil : CGFloat(width)
  node.frameHeight = height < 0 ? nil : CGFloat(height)
  node.frameMaxWidth = maxWidth < 0 ? nil : CGFloat(maxWidth)
  node.frameAlignment = alignment == 1 ? .leading : .topLeading
}

@_cdecl("ocaml_demo_native_swiftui_set_regular_material_panel")
public func ocaml_demo_native_swiftui_set_regular_material_panel(_ pointer: UnsafeMutableRawPointer?, _ cornerRadius: Double) {
  nativeNode(from: pointer)?.regularMaterialPanelCornerRadius =
    cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("ocaml_demo_native_swiftui_set_secondary_system_grouped_panel")
public func ocaml_demo_native_swiftui_set_secondary_system_grouped_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double
) {
  nativeNode(from: pointer)?.secondarySystemGroupedPanelCornerRadius =
    cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("ocaml_demo_native_swiftui_set_secondary_fill_panel")
public func ocaml_demo_native_swiftui_set_secondary_fill_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double,
  _ opacity: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.secondaryFillPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
  node.secondaryFillPanelOpacity = opacity
}

@_cdecl("ocaml_demo_native_swiftui_set_liquid_glass_panel")
public func ocaml_demo_native_swiftui_set_liquid_glass_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double,
  _ isTransparent: Bool,
  _ tintColor: Int32,
  _ tintOpacity: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.liquidGlassPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
  node.liquidGlassPanelIsTransparent = isTransparent
  node.liquidGlassPanelTintColor = tintColor
  node.liquidGlassPanelTintOpacity = tintOpacity
}

@_cdecl("ocaml_demo_native_swiftui_clear_tabs")
public func ocaml_demo_native_swiftui_clear_tabs(_ pointer: UnsafeMutableRawPointer?, _ selectedPointer: UnsafePointer<CChar>?, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.tabs = []
  node.selectedTabId = selectedPointer.map(String.init(cString:)) ?? ""
  node.tabSelectEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_append_tab")
public func ocaml_demo_native_swiftui_append_tab(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ role: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.tabs.append(
    OCamlDemoTab(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      role: role
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_clear_sidebar_shell")
public func ocaml_demo_native_swiftui_clear_sidebar_shell(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ compactTopBarVisible: Bool,
  _ bottomSearchPlaceholderPointer: UnsafePointer<CChar>?,
  _ bottomSearchTextPointer: UnsafePointer<CChar>?,
  _ bottomSearchEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.sidebarTitle = titlePointer.map(String.init(cString:))
  node.sidebarCompactTopBarVisible = compactTopBarVisible
  node.sidebarHeaderAction = nil
  node.sidebarActions = []
  node.sidebarHistoryTitle = nil
  node.sidebarHistoryActions = []
  node.sidebarBottomSearchPlaceholder = bottomSearchPlaceholderPointer.map(String.init(cString:))
  node.sidebarBottomSearchText = bottomSearchTextPointer.map(String.init(cString:)) ?? ""
  node.sidebarBottomSearchEventId = bottomSearchEventId >= 0 ? bottomSearchEventId : nil
  node.sidebarBottomAction = nil
}

@_cdecl("ocaml_demo_native_swiftui_set_sidebar_header_action")
public func ocaml_demo_native_swiftui_set_sidebar_header_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ headerActionIdPointer: UnsafePointer<CChar>?,
  _ headerActionTitlePointer: UnsafePointer<CChar>?,
  _ headerActionSystemImagePointer: UnsafePointer<CChar>?,
  _ headerActionAvatarImagePointer: UnsafePointer<CChar>?,
  _ headerActionAvatarInitialPointer: UnsafePointer<CChar>?,
  _ headerActionSelectsTabPointer: UnsafePointer<CChar>?,
  _ headerActionEventId: Int32,
  _ headerActionClosesSidebar: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  if let headerActionIdPointer, let headerActionTitlePointer {
    node.sidebarHeaderAction = OCamlDemoSidebarAction(
      id: String(cString: headerActionIdPointer),
      title: String(cString: headerActionTitlePointer),
      subtitle: nil,
      systemImage: headerActionSystemImagePointer.map(String.init(cString:)),
      avatarImage: headerActionAvatarImagePointer.map(String.init(cString:)),
      avatarInitial: headerActionAvatarInitialPointer.map(String.init(cString:)),
      selectsTab: headerActionSelectsTabPointer.map(String.init(cString:)),
      chrome: 0,
      eventId: headerActionEventId < 0 ? nil : headerActionEventId,
      closesSidebar: headerActionClosesSidebar != 0,
      menuActions: []
    )
  } else {
    node.sidebarHeaderAction = nil
  }
}

@_cdecl("ocaml_demo_native_swiftui_append_sidebar_action")
public func ocaml_demo_native_swiftui_append_sidebar_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ subtitlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ selectsTabPointer: UnsafePointer<CChar>?,
  _ eventId: Int32,
  _ closesSidebar: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.sidebarActions.append(
    OCamlDemoSidebarAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      subtitle: subtitlePointer.map(String.init(cString:)),
      systemImage: systemImagePointer.map(String.init(cString:)),
      avatarImage: nil,
      avatarInitial: nil,
      selectsTab: selectsTabPointer.map(String.init(cString:)),
      chrome: 0,
      eventId: eventId < 0 ? nil : eventId,
      closesSidebar: closesSidebar != 0,
      menuActions: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_append_sidebar_action_menu_action")
public func ocaml_demo_native_swiftui_append_sidebar_action_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer),
        let titlePointer,
        let lastIndex = node.sidebarActions.indices.last
  else { return }
  node.sidebarActions[lastIndex].menuActions.append(
    OCamlDemoRowAction(
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      eventId: eventId < 0 ? nil : eventId,
      startsSection: false,
      exportFilename: nil,
      exportContentType: nil,
      exportContent: nil
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_sidebar_history_title")
public func ocaml_demo_native_swiftui_set_sidebar_history_title(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.sidebarHistoryTitle = titlePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_append_sidebar_history_action")
public func ocaml_demo_native_swiftui_append_sidebar_history_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ subtitlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ selectsTabPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.sidebarHistoryActions.append(
    OCamlDemoSidebarAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      subtitle: subtitlePointer.map(String.init(cString:)),
      systemImage: systemImagePointer.map(String.init(cString:)),
      avatarImage: nil,
      avatarInitial: nil,
      selectsTab: selectsTabPointer.map(String.init(cString:)),
      chrome: 0,
      eventId: eventId < 0 ? nil : eventId,
      closesSidebar: true,
      menuActions: []
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_append_sidebar_history_action_menu_action")
public func ocaml_demo_native_swiftui_append_sidebar_history_action_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer),
        let titlePointer,
        let lastIndex = node.sidebarHistoryActions.indices.last
  else { return }
  node.sidebarHistoryActions[lastIndex].menuActions.append(
    OCamlDemoRowAction(
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      eventId: eventId < 0 ? nil : eventId,
      startsSection: false,
      exportFilename: nil,
      exportContentType: nil,
      exportContent: nil
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_sidebar_bottom_action")
public func ocaml_demo_native_swiftui_set_sidebar_bottom_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ eventId: Int32,
  _ chrome: Int32,
  _ selectsTabPointer: UnsafePointer<CChar>?,
  _ closesSidebar: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  guard let idPointer, let titlePointer else {
    node.sidebarBottomAction = nil
    return
  }
  node.sidebarBottomAction = OCamlDemoSidebarAction(
    id: String(cString: idPointer),
    title: String(cString: titlePointer),
    subtitle: nil,
    systemImage: systemImagePointer.map(String.init(cString:)),
    avatarImage: nil,
    avatarInitial: nil,
    selectsTab: selectsTabPointer.map(String.init(cString:)),
    chrome: chrome,
    eventId: eventId < 0 ? nil : eventId,
    closesSidebar: closesSidebar != 0,
    menuActions: []
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_section")
public func ocaml_demo_native_swiftui_set_section(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.sectionTitle = titlePointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_clear_picker")
public func ocaml_demo_native_swiftui_clear_picker(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ selectedPointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.pickerSelected = selectedPointer.map(String.init(cString:)) ?? ""
  node.pickerStyle = style
  node.pickerEventId = eventId < 0 ? nil : eventId
  node.pickerOptions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_picker_option")
public func ocaml_demo_native_swiftui_append_picker_option(_ pointer: UnsafeMutableRawPointer?, _ idPointer: UnsafePointer<CChar>?, _ titlePointer: UnsafePointer<CChar>?) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.pickerOptions.append(OCamlDemoPickerOption(id: String(cString: idPointer), title: String(cString: titlePointer)))
}

@_cdecl("ocaml_demo_native_swiftui_set_file_exporter")
public func ocaml_demo_native_swiftui_set_file_exporter(_ pointer: UnsafeMutableRawPointer?, _ filenamePointer: UnsafePointer<CChar>?, _ contentTypePointer: UnsafePointer<CChar>?, _ contentPointer: UnsafePointer<CChar>?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.exportFilename = filenamePointer.map(String.init(cString:)) ?? ""
  node.exportContentType = contentTypePointer.map(String.init(cString:)) ?? ""
  node.exportContent = contentPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_share_link")
public func ocaml_demo_native_swiftui_set_share_link(_ pointer: UnsafeMutableRawPointer?, _ urlPointer: UnsafePointer<CChar>?) {
  nativeNode(from: pointer)?.shareURL = urlPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_file_importer")
public func ocaml_demo_native_swiftui_set_file_importer(_ pointer: UnsafeMutableRawPointer?, _ allowedTypesPointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?, _ count: Int32, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.allowedContentTypes = (0..<Int(count)).compactMap { index in
    guard let typePointer = allowedTypesPointer?[index] else { return nil }
    return String(cString: typePointer)
  }
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_slider")
public func ocaml_demo_native_swiftui_set_slider(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?, _ value: Double, _ min: Double, _ max: Double, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.sliderValue = value
  node.sliderMin = min
  node.sliderMax = max
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_stepper")
public func ocaml_demo_native_swiftui_set_stepper(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?, _ value: Int32, _ min: Int32, _ max: Int32, _ step: Int32, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.stepperValue = value
  node.stepperMin = min
  node.stepperMax = max
  node.stepperStep = Swift.max(1, step)
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_date_picker")
public func ocaml_demo_native_swiftui_set_date_picker(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?, _ selectedPointer: UnsafePointer<CChar>?, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.selectedDateText = selectedPointer.map(String.init(cString:)) ?? ""
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_color_picker")
public func ocaml_demo_native_swiftui_set_color_picker(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?, _ selectedPointer: UnsafePointer<CChar>?, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.selectedColorText = selectedPointer.map(String.init(cString:)) ?? "#007AFF"
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_clear_menu")
public func ocaml_demo_native_swiftui_clear_menu(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?, _ systemImagePointer: UnsafePointer<CChar>?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.systemImage = systemImagePointer.map(String.init(cString:))
  node.menuActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_menu_action")
public func ocaml_demo_native_swiftui_append_menu_action(_ pointer: UnsafeMutableRawPointer?, _ idPointer: UnsafePointer<CChar>?, _ titlePointer: UnsafePointer<CChar>?, _ systemImagePointer: UnsafePointer<CChar>?, _ style: Int32, _ isEnabled: Bool, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.menuActions.append(
    OCamlDemoMenuAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      isEnabled: isEnabled,
      eventId: eventId < 0 ? nil : eventId
    )
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_disclosure_group")
public func ocaml_demo_native_swiftui_set_disclosure_group(_ pointer: UnsafeMutableRawPointer?, _ titlePointer: UnsafePointer<CChar>?, _ isExpanded: Bool, _ eventId: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.isDisclosureExpanded = isExpanded
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_navigation_path_stack")
public func ocaml_demo_native_swiftui_set_navigation_path_stack(_ pointer: UnsafeMutableRawPointer?, _ pathPointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?, _ pathCount: Int32, _ eventId: Int32, _ destinationsPointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?, _ destinationsCount: Int32) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextPath: [String] = (0..<Int(pathCount)).compactMap { index in
    guard let value = pathPointer?[index] else { return nil }
    return String(cString: value)
  }
  if node.navigationPath != nextPath {
    node.navigationPath = nextPath
  }
  let nextEventId = eventId < 0 ? nil : eventId
  if node.navigationPathEventId != nextEventId {
    node.navigationPathEventId = nextEventId
  }
  let nextDestinationIds: [String] = (0..<Int(destinationsCount)).compactMap { index in
    guard let value = destinationsPointer?[index] else { return nil }
    return String(cString: value)
  }
  if node.navigationDestinationIds != nextDestinationIds {
    node.navigationDestinationIds = nextDestinationIds
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_image_payload_mode")
public func ocaml_demo_native_swiftui_set_image_payload_mode(_ pointer: UnsafeMutableRawPointer?, _ wantsPayload: Bool) {
  nativeNode(from: pointer)?.wantsImagePayload = wantsPayload
}

@_cdecl("ocaml_demo_native_swiftui_make_controller")
public func ocaml_demo_native_swiftui_make_controller(_ rootPointer: UnsafeMutableRawPointer?, _ callback: OCamlDemoEventCallback?) -> UnsafeMutableRawPointer? {
  guard let root = nativeNode(from: rootPointer) else { return nil }
  return Unmanaged.passRetained(makeHostingController(root: root, callback: callback)).toOpaque()
}

@_cdecl("ocaml_demo_native_swiftui_update_controller")
public func ocaml_demo_native_swiftui_update_controller(_ controllerPointer: UnsafeMutableRawPointer?, _ rootPointer: UnsafeMutableRawPointer?) {
  guard let controllerPointer, let root = nativeNode(from: rootPointer) else { return }
  let controller = Unmanaged<NSViewController>.fromOpaque(controllerPointer).takeUnretainedValue()
  if let model = objc_getAssociatedObject(controller, "OCamlDemoSwiftUIModel") as? OCamlDemoHostModel {
    model.root = root
  }
}

@_cdecl("ocaml_demo_native_swiftui_release_controller")
public func ocaml_demo_native_swiftui_release_controller(_ controllerPointer: UnsafeMutableRawPointer?) {
  guard let controllerPointer else { return }
  Unmanaged<NSViewController>.fromOpaque(controllerPointer).release()
}

@_cdecl("ocaml_demo_native_swiftui_make_window")
public func ocaml_demo_native_swiftui_make_window(_ rootPointer: UnsafeMutableRawPointer?, _ callback: OCamlDemoEventCallback?) -> UnsafeMutableRawPointer? {
  guard let root = nativeNode(from: rootPointer) else { return nil }
  let defaultSize = NSSize(width: 1280, height: 820)
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: defaultSize),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
  )
  window.title = "OCaml Demo Todos"
  window.minSize = NSSize(width: 960, height: 640)
  window.setContentSize(defaultSize)
  window.contentViewController = makeHostingController(root: root, callback: callback)
  window.center()
  window.makeKeyAndOrderFront(nil)
  return Unmanaged.passRetained(window).toOpaque()
}

@_cdecl("ocaml_demo_native_swiftui_release_window")
public func ocaml_demo_native_swiftui_release_window(_ windowPointer: UnsafeMutableRawPointer?) {
  guard let windowPointer else { return }
  Unmanaged<NSWindow>.fromOpaque(windowPointer).release()
}

@_cdecl("ocaml_demo_native_swiftui_http_send_json")
public func ocaml_demo_native_swiftui_http_send_json(
  _ methodPointer: UnsafePointer<CChar>?,
  _ urlPointer: UnsafePointer<CChar>?,
  _ authorizationPointer: UnsafePointer<CChar>?,
  _ bodyPointer: UnsafePointer<CChar>?,
  _ timeoutSeconds: Double,
  _ context: UnsafeMutableRawPointer?,
  _ callback: OCamlDemoHTTPCallback?
) {
  let message = "HTTP is not implemented in the macOS SwiftUI host"
  message.withCString { pointer in
    callback?(context, false, pointer)
  }
}
