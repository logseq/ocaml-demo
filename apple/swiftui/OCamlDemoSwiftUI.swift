import AVFoundation
import CryptoKit
import Foundation
import ObjectiveC
import OSLog
import PhotosUI
import QuartzCore
import Speech
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
import WebKit

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

private let ocaml_demoDatePickerDebugLogger = Logger(
  subsystem: "com.logseq.simple-outliner",
  category: "DatePickerDebug"
)

private let ocaml_demoNativeInteractionLogger = Logger(
  subsystem: "com.logseq.simple-outliner",
  category: "InteractionDebug"
)
private let ocaml_demoNativeInteractionDebugEnabled =
  ProcessInfo.processInfo.environment["OCAML_DEMO_INTERACTION_DEBUG"] == "1"

private func ocaml_demoNativeInteractionDebug(_ name: String, detail: String = "") {
  guard ocaml_demoNativeInteractionDebugEnabled else { return }
  let message = detail.isEmpty ? name : "\(name) \(detail)"
  fputs("[OCamlDemoInteraction] \(message)\n", stderr)
  fflush(stderr)
  ocaml_demoNativeInteractionLogger.info("\(message, privacy: .public)")
}

private var ocaml_demoNativeLazyRowRenderCallback: OCamlDemoLazyRowRenderCallback?
private var ocaml_demoNativeLazyRowKeyCallback: OCamlDemoLazyRowKeyCallback?
private var ocaml_demoNativeLazyRowReleaseCallback: OCamlDemoLazyRowReleaseCallback?
private let minDeferredLazyListAppendRowCount = 16

private enum OCamlDemoFrameAlignment: Int32 {
  case center = 0
  case leading = 1

  var swiftUIAlignment: Alignment {
    switch self {
    case .leading: return .leading
    case .center: return .center
    }
  }
}

private enum OCamlDemoHorizontalStackAlignment: Int32 {
  case center = 0
  case top = 1

  var swiftUIVerticalAlignment: VerticalAlignment {
    switch self {
    case .top: return .top
    case .center: return .center
    }
  }
}

@_cdecl("ocaml_demo_native_swiftui_run_on_main_when_scroll_idle")
public func ocaml_demo_native_swiftui_run_on_main_when_scroll_idle(
  _ context: UnsafeMutableRawPointer?,
  _ perform: @escaping OCamlDemoMainCallback
) {
  OCamlDemoScrollIdleScheduler.shared.runWhenIdle(context: context, perform: perform)
}

@_cdecl("ocaml_demo_native_swiftui_run_on_main_after_rendered_frame")
public func ocaml_demo_native_swiftui_run_on_main_after_rendered_frame(
  _ context: UnsafeMutableRawPointer?,
  _ perform: @escaping OCamlDemoMainCallback
) {
  OCamlDemoRenderedFrameScheduler.shared.runAfterRenderedFrame {
    perform(context)
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_clipboard_text")
public func ocaml_demo_native_swiftui_set_clipboard_text(_ textPointer: UnsafePointer<CChar>?) {
  guard let textPointer else { return }
  UIPasteboard.general.string = String(cString: textPointer)
}

@_cdecl("ocaml_demo_native_swiftui_set_clipboard_image_file")
public func ocaml_demo_native_swiftui_set_clipboard_image_file(_ pathPointer: UnsafePointer<CChar>?) {
  guard let pathPointer else { return }
  guard let image = UIImage(contentsOfFile: String(cString: pathPointer)) else { return }
  UIPasteboard.general.image = image
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
  func start() {
    do {
      let url = try ocaml_demoNativeNextAudioRecordingURL()
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
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

  switch AVAudioApplication.shared.recordPermission {
  case .granted:
    start()
  case .undetermined:
    AVAudioApplication.requestRecordPermission { granted in
      if granted {
        DispatchQueue.main.async { start() }
      }
    }
  case .denied:
    break
  @unknown default:
    break
  }
}

@_cdecl("ocaml_demo_native_swiftui_stop_audio_recording_and_transcribe")
public func ocaml_demo_native_swiftui_stop_audio_recording_and_transcribe() -> UnsafeMutablePointer<CChar>? {
  guard let recorder = ocaml_demoNativeAudioRecorder else {
    return strdup("")
  }
  recorder.stop()
  ocaml_demoNativeAudioRecorder = nil
  try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

  let url = recorder.url
  ocaml_demoNativeAudioRecordingURL = url
  let transcript = ocaml_demoNativeTranscribeAudioRecording(at: url)
  let byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
  return strdup([
    transcript.isEmpty ? "Audio recording" : transcript,
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

private func ocaml_demoNativeTranscribeAudioRecording(at url: URL) -> String {
  guard #available(iOS 26.0, *), SpeechTranscriber.isAvailable else {
    return ""
  }

  let semaphore = DispatchSemaphore(value: 0)
  var transcriptionResult = ""
  Task.detached {
    var result = ""
    do {
      let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale.current
      let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
      try await ocaml_demoNativeEnsureSpeechModelInstalled(for: transcriber)
      let audioFile = try AVAudioFile(forReading: url)
      let analyzer = SpeechAnalyzer(modules: [transcriber])
      async let transcription = transcriber.results.reduce("") { text, partial in
        text + String(partial.text.characters)
      }
      if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
        try await analyzer.finalizeAndFinish(through: lastSample)
      } else {
        await analyzer.cancelAndFinishNow()
      }
      result = try await transcription
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    } catch {
      result = ""
    }
    transcriptionResult = result
    semaphore.signal()
  }
  _ = semaphore.wait(timeout: .now() + 60)
  return transcriptionResult
}

@available(iOS 26.0, *)
private func ocaml_demoNativeEnsureSpeechModelInstalled(for transcriber: SpeechTranscriber) async throws {
  switch await AssetInventory.status(forModules: [transcriber]) {
  case .installed:
    return
  case .supported, .downloading:
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
  case .unsupported:
    throw NSError(domain: "OCamlDemoSpeech", code: 1)
  @unknown default:
    throw NSError(domain: "OCamlDemoSpeech", code: 2)
  }
}

@objc(OCamlDemoAppDelegate)
private final class OCamlDemoAppDelegate: NSObject, UIApplicationDelegate {
  static var launchCallback: OCamlDemoLaunchCallback?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    OCamlDemoAppDelegate.launchCallback?(
      Unmanaged.passUnretained(self).toOpaque(),
      Unmanaged.passUnretained(application).toOpaque(),
      nil
    ) ?? true
  }
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

private let ocaml_demoLightBackgroundComponent: CGFloat = 0.965

private struct OCamlDemoCompactSidebarToolbar {
  let title: String
  let openSidebar: () -> Void
}

private extension EnvironmentValues {
  @Entry var ocaml_demoCompactSidebarToolbar: OCamlDemoCompactSidebarToolbar?
}

private var ocaml_demoHomeBodyBackground: Color {
  Color(uiColor: UIColor { traits in
    ocaml_demoHomeBodyUIColor(for: traits)
  })
}

@ViewBuilder
private func ocaml_demoHomeBodyBackgroundLayer() -> some View {
  if #available(iOS 26.0, *) {
    ocaml_demoHomeBodyBackground.backgroundExtensionEffect()
  } else {
    ocaml_demoHomeBodyBackground
  }
}

private func ocaml_demoHomeBodyUIColor(for traits: UITraitCollection) -> UIColor {
  if traits.userInterfaceStyle == .dark {
    return .systemBackground
  }
  return UIColor(
    red: ocaml_demoLightBackgroundComponent,
    green: ocaml_demoLightBackgroundComponent,
    blue: ocaml_demoLightBackgroundComponent,
    alpha: 1
  )
}

private func ocaml_demoConfigureNavigationBarAppearance(for traits: UITraitCollection) {
  let appearance = UINavigationBarAppearance()
  appearance.configureWithTransparentBackground()
  appearance.shadowColor = .clear

  let navigationBar = UINavigationBar.appearance()
  navigationBar.standardAppearance = appearance
  navigationBar.scrollEdgeAppearance = appearance
  navigationBar.compactAppearance = appearance
  navigationBar.compactScrollEdgeAppearance = appearance
}

private func ocaml_demoDrawerSidebarTopInset(_ inset: CGFloat) -> CGFloat {
  max(inset + 5, 54)
}

private func ocaml_demoDrawerSidebarBottomInset(_ inset: CGFloat) -> CGFloat {
  inset > 100 ? 34 : max(inset, 34)
}

private func ocaml_demoDismissKeyboard() {
  UIApplication.shared.sendAction(
    #selector(UIResponder.resignFirstResponder),
    to: nil,
    from: nil,
    for: nil
  )
}

private final class OCamlDemoKeyboardHandoff {
  static let shared = OCamlDemoKeyboardHandoff()

  private weak var holdingField: UITextField?
  private weak var handoffSource: UIView?

  func retainKeyboard(from current: UIView) {
    guard current.isFirstResponder else { return }
    guard let window = current.window else { return }
    handoffSource = current
    ocaml_demoNativeInteractionDebug(
      "keyboard_handoff_retain",
      detail: "view=\(String(describing: type(of: current)))"
    )

    let field: UITextField
    if let existing = holdingField {
      field = existing
    } else {
      let next = UITextField(frame: CGRect(x: -4, y: -4, width: 1, height: 1))
      next.alpha = 0.01
      next.autocorrectionType = .no
      next.spellCheckingType = .no
      holdingField = next
      field = next
    }

    if field.window !== window {
      field.removeFromSuperview()
      window.addSubview(field)
    }
    field.becomeFirstResponder()
  }

  func completeHandoff() {
    guard let field = holdingField else { return }
    if !field.isFirstResponder {
      ocaml_demoNativeInteractionDebug("keyboard_handoff_complete")
      field.removeFromSuperview()
      holdingField = nil
      handoffSource = nil
    }
  }

  func cancelHandoff() {
    guard let field = holdingField else { return }
    ocaml_demoNativeInteractionDebug("keyboard_handoff_cancel")
    if field.isFirstResponder {
      field.resignFirstResponder()
    }
    field.removeFromSuperview()
    holdingField = nil
    handoffSource = nil
  }

  func shouldSuppressBlur(from view: UIView) -> Bool {
    handoffSource === view
  }
}

private func ocaml_demoPerformLightHapticFeedback() {
  let generator = UIImpactFeedbackGenerator(style: .light)
  generator.prepare()
  generator.impactOccurred(intensity: 0.65)
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

private let ocaml_demoNativePreferredFontFamily = "Inter"

private func ocaml_demoNativeTextStyleSize(_ textStyle: Font.TextStyle) -> CGFloat {
  switch textStyle {
  case .largeTitle: return 34
  case .title: return 28
  case .title2: return 22
  case .title3: return 20
  case .headline: return 17
  case .callout: return 16
  case .subheadline: return 15
  case .footnote: return 13
  case .caption: return 12
  case .caption2: return 11
  default: return 17
  }
}

private func ocaml_demoNativePreferredFont(
  _ textStyle: Font.TextStyle,
  weight: Font.Weight = .regular
) -> Font {
  ocaml_demoNativePreferredFont(
    size: ocaml_demoNativeTextStyleSize(textStyle),
    weight: weight,
    relativeTo: textStyle
  )
}

private func ocaml_demoNativePreferredFont(
  size: CGFloat,
  weight: Font.Weight = .regular,
  relativeTo textStyle: Font.TextStyle = .body
) -> Font {
  if UIFont(name: ocaml_demoNativePreferredFontFamily, size: size) != nil {
    return Font.custom(ocaml_demoNativePreferredFontFamily, size: size, relativeTo: textStyle)
      .weight(weight)
  }
  return .system(size: size, weight: weight)
}

private func ocaml_demoNativePreferredUIFont(
  size: CGFloat,
  weight: UIFont.Weight = .regular
) -> UIFont {
  if let font = UIFont(name: ocaml_demoNativePreferredFontFamily, size: size) {
    return font
  }
  return .systemFont(ofSize: size, weight: weight)
}

private func ocaml_demoNativePreferredUIFont(
  _ textStyle: Font.TextStyle,
  weight: UIFont.Weight = .regular
) -> UIFont {
  ocaml_demoNativePreferredUIFont(size: ocaml_demoNativeTextStyleSize(textStyle), weight: weight)
}

private struct SidebarBottomActionChrome: ViewModifier {
  let chrome: Int32

  func body(content: Content) -> some View {
    if chrome == 2 {
      content
        .ocaml_demoLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
    } else {
      content
        .background(Color.black, in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
  }
}

private struct OCamlDemoCompactSidebarToolbarModifier: ViewModifier {
  let toolbar: OCamlDemoCompactSidebarToolbar?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let toolbar {
      content
        .navigationTitle(toolbar.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              toolbar.openSidebar()
            } label: {
              VStack(alignment: .leading, spacing: 7) {
                Capsule()
                  .fill(Color.primary)
                  .frame(width: 22, height: 2.2)
                Capsule()
                  .fill(Color.primary)
                  .frame(width: 17, height: 2.2)
              }
              .frame(width: 34, height: 34)
              .contentShape(Circle())
            }
            .ocaml_demoLiquidGlassButtonStyle()
            .buttonBorderShape(.circle)
          }
        }
    } else {
      content
    }
  }
}
private extension View {
  func ocaml_demoBottomBarChrome() -> some View {
    self
      .toolbarBackground(ocaml_demoHomeBodyBackground, for: .navigationBar)
      .toolbarBackground(ocaml_demoHomeBodyBackground, for: .bottomBar)
  }

  @ViewBuilder
  func ocaml_demoContentUnderBottomBar() -> some View {
    if #available(iOS 26.0, *) {
      self.contentMargins(.bottom, 0, for: .scrollContent)
    } else {
      self
    }
  }

  func ocaml_demoNavigationChrome() -> some View {
    self
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background {
        ocaml_demoHomeBodyBackgroundLayer()
          .ignoresSafeArea(.container, edges: .all)
      }
      .ocaml_demoBottomBarChrome()
  }

  @ViewBuilder
  func ocaml_demoLiquidGlassButtonStyle() -> some View {
    if #available(iOS 26.0, *) {
      self
        .buttonStyle(.plain)
        .controlSize(.small)
    } else {
      self
        .buttonStyle(.plain)
        .background(Color.clear, in: Circle())
    }
  }

  @ViewBuilder
  func ocaml_demoLiquidGlassPanel(
    cornerRadius: CGFloat,
    isInteractive: Bool = false,
    isTransparent: Bool = false,
    tint: Color? = nil
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    if #available(iOS 26.0, *) {
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
    } else {
      if let tint {
        self.background(AnyShapeStyle(tint), in: shape)
      } else {
        self.background(isTransparent ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar), in: shape)
      }
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

  var swiftUIPlacement: ToolbarItemPlacement {
    switch self {
    case .automatic:
      return .automatic
    case .bottomBar:
      return .bottomBar
    }
  }
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

private struct OCamlDemoExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText, .data] }

  var content: String

  init(content: String = "") {
    self.content = content
  }

  init(configuration: ReadConfiguration) throws {
    if let data = configuration.file.regularFileContents {
      content = String(decoding: data, as: UTF8.self)
    } else {
      content = ""
    }
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(content.utf8))
  }
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

private final class OCamlDemoNode: ObservableObject, Identifiable {
  let id = UUID()
  let kind: NodeKind
  weak var hostModel: OCamlDemoHostModel?

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
  @Published var horizontalStackAlignment = OCamlDemoHorizontalStackAlignment.center
  @Published var gridColumns: Int = 2
  @Published var gridSpacing: CGFloat = 10
  @Published var children: [OCamlDemoNode] = []
  @Published var clickEventId: Int32?
  @Published var navigationActivateEventId: Int32?
  @Published var navigationDeactivateEventId: Int32?
  @Published var tapEventId: Int32?
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
  @Published var horizontalSwipeLeftEventId: Int32?
  @Published var horizontalSwipeRightEventId: Int32?
  @Published var padding: EdgeInsets?
  @Published var regularMaterialPanelCornerRadius: CGFloat?
  @Published var secondarySystemGroupedPanelCornerRadius: CGFloat?
  @Published var secondaryFillPanelCornerRadius: CGFloat?
  @Published var secondaryFillPanelOpacity: Double = 0.12
  @Published var liquidGlassPanelCornerRadius: CGFloat?
  @Published var liquidGlassPanelIsTransparent = false
  @Published var liquidGlassPanelTintColor: Int32 = -1
  @Published var liquidGlassPanelTintOpacity: Double = 0
  @Published var frameWidth: CGFloat?
  @Published var frameHeight: CGFloat?
  @Published var frameMaxWidth: CGFloat?
  @Published var frameAlignment = OCamlDemoFrameAlignment.center
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
  @Published var listFocusedRowDisappearEventId: Int32?
  @Published var isListEditMode = false
  @Published var listFocusedRowIndex: Int?
  @Published var lazyListProviderId: Int32?
  @Published var lazyListRowCount = 0
  @Published var lazyListVersion = 0
  var lazyListRowsPublishedEventId: Int32?
  var lazyListInvalidatedIndices: Set<Int> = []
  var lazyListIdentityKeysByIndex: [String] = []
  var lazyListIdentityKeyByIndex: [Int: String] = [:]
  var lazyListRowsByKey: [String: OCamlDemoNode] = [:]
  var lazyListRowsByIndex: [Int: OCamlDemoNode] = [:]
  var lazyListRowKeyByIndex: [Int: String] = [:]
  var lazyListRetainedOrder: [Int] = []
  var lazyListVisibleIndices: Set<Int> = []
  var lazyListVisibleIndexCounts: [Int: Int] = [:]
  weak var lazyListScrollView: UIScrollView?
  var pendingLazyListRowCount: Int?
  var pendingLazyListRowCountInvalidatedCount = 0
  var pendingLazyListRowCountWorkItem: DispatchWorkItem?
  var pendingLazyListRowCountGeneration = 0
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

private final class OCamlDemoFrameProbe: NSObject {
  static let shared = OCamlDemoFrameProbe()

  private let isEnabled =
    ProcessInfo.processInfo.environment["OCAML_DEMO_LIST_DEBUG"] == "1"
    || ProcessInfo.processInfo.environment["OCAML_DEMO_FRAME_DEBUG"] == "1"
  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?
  private var reportStartedAt = CACurrentMediaTime()
  private var frames = 0
  private var over16ms = 0
  private var over33ms = 0
  private var over50ms = 0
  private var maxDeltaMs = 0.0
  private var lazyRowBodies = 0
  private var lazyRowAppears = 0
  private var lazyRowDisappears = 0
  private var mediaCreates = 0
  private var mediaDestroys = 0
  private var lastScrollSampleLogAtByList: [UUID: CFTimeInterval] = [:]

  func start() {
    guard isEnabled else { return }
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  func markScrollSample(listID: UUID, index: Int, totalRows: Int) {
    guard isEnabled else { return }
    start()
    let now = CACurrentMediaTime()
    let lastLogAt = lastScrollSampleLogAtByList[listID] ?? 0
    guard now - lastLogAt >= 1 else { return }
    lastScrollSampleLogAtByList[listID] = now
    fputs(
      "[OCamlDemoScrollPerf] scroll_stress_sample list=\(listID.uuidString) index=\(index) total_rows=\(totalRows) past_first_ten_rows=\(index >= 10)\n",
      stderr
    )
    fflush(stderr)
  }

  func markLazyRowBody() {
    guard isEnabled else { return }
    lazyRowBodies += 1
  }

  func markLazyRowAppear() {
    guard isEnabled else { return }
    lazyRowAppears += 1
  }

  func markLazyRowDisappear() {
    guard isEnabled else { return }
    lazyRowDisappears += 1
  }

  func markLazyRowRender(
    listID: UUID,
    index: Int,
    key: String,
    elapsedMs: Double,
    totalRows: Int
  ) {
    guard isEnabled && elapsedMs >= 4 else { return }
    start()
    fputs(
      String(
        format:
          "[OCamlDemoScrollPerf] lazy_row_render_slow list=%@ index=%d key=%@ total_rows=%d elapsed_ms=%.2f\n",
        listID.uuidString,
        index,
        key,
        totalRows,
        elapsedMs
      ),
      stderr
    )
    fflush(stderr)
  }

  func logLazyRowCountEvent(
    name: String,
    listID: UUID,
    oldCount: Int,
    newCount: Int,
    invalidatedCount: Int
  ) {
    guard isEnabled else { return }
    start()
    fputs(
      "[OCamlDemoScrollPerf] \(name) list=\(listID.uuidString) old_count=\(oldCount) new_count=\(newCount) invalidated_count=\(invalidatedCount)\n",
      stderr
    )
    fflush(stderr)
  }

  func markMediaViewCreated(kind _: String) {
    guard isEnabled else { return }
    mediaCreates += 1
  }

  func markMediaViewDestroyed(kind _: String) {
    guard isEnabled else { return }
    mediaDestroys += 1
  }

  @objc private func tick(_ link: CADisplayLink) {
    defer { lastTimestamp = link.timestamp }
    guard let lastTimestamp else { return }
    let deltaMs = (link.timestamp - lastTimestamp) * 1000
    frames += 1
    maxDeltaMs = max(maxDeltaMs, deltaMs)
    if deltaMs > 16.8 { over16ms += 1 }
    if deltaMs > 33.4 { over33ms += 1 }
    if deltaMs > 50.0 { over50ms += 1 }
    let now = CACurrentMediaTime()
    guard now - reportStartedAt >= 1 else { return }
    fputs(
      String(
        format:
          "[OCamlDemoScrollPerf] frame_report seconds=%.2f frames=%d max_delta_ms=%.2f over_16ms=%d over_33ms=%d over_50ms=%d lazy_body=%d lazy_appear=%d lazy_disappear=%d media_create=%d media_destroy=%d\n",
        now - reportStartedAt,
        frames,
        maxDeltaMs,
        over16ms,
        over33ms,
        over50ms,
        lazyRowBodies,
        lazyRowAppears,
        lazyRowDisappears,
        mediaCreates,
        mediaDestroys
      ),
      stderr
    )
    fflush(stderr)
    reportStartedAt = now
    frames = 0
    over16ms = 0
    over33ms = 0
    over50ms = 0
    maxDeltaMs = 0
    lazyRowBodies = 0
    lazyRowAppears = 0
    lazyRowDisappears = 0
    mediaCreates = 0
    mediaDestroys = 0
  }
}

private final class OCamlDemoBodyProbe {
  static let shared = OCamlDemoBodyProbe()

  private let isEnabled =
    ProcessInfo.processInfo.environment["OCAML_DEMO_BODY_DEBUG"] == "1"
  private var reportStartedAt = CACurrentMediaTime()
  private var counts: [String: Int] = [:]

  func mark(_ name: String) {
    guard isEnabled else { return }
    counts[name, default: 0] += 1
    let now = CACurrentMediaTime()
    guard now - reportStartedAt >= 1 else { return }
    let summary =
      counts
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: " ")
    fputs(
      String(
        format: "[OCamlDemoBodyDebug] seconds=%.2f %@\n",
        now - reportStartedAt,
        summary
      ),
      stderr
    )
    fflush(stderr)
    reportStartedAt = now
    counts.removeAll(keepingCapacity: true)
  }
}

private final class OCamlDemoScrollStressProbe {
  static let shared = OCamlDemoScrollStressProbe()

  private let isEnabled =
    ProcessInfo.processInfo.environment["OCAML_DEMO_SCROLL_STRESS"] == "1"
  private let pointsPerTick =
    max(
      1,
      Double(ProcessInfo.processInfo.environment["OCAML_DEMO_SCROLL_STRESS_POINTS"] ?? "")
        ?? 80
    )
  private let step =
    max(1, Int(ProcessInfo.processInfo.environment["OCAML_DEMO_SCROLL_STRESS_STEP"] ?? "") ?? 3)
  private let delay =
    max(
      0.016,
      Double(ProcessInfo.processInfo.environment["OCAML_DEMO_SCROLL_STRESS_DELAY"] ?? "")
        ?? 0.05
    )
  private final class Run {
    var totalRows: Int
    let scrollToIndex: (Int) -> Void
    weak var scrollView: UIScrollView?
    var isPausedAtEnd = false
    var hasScheduledTick = false

    init(totalRows: Int, scrollToIndex: @escaping (Int) -> Void) {
      self.totalRows = totalRows
      self.scrollToIndex = scrollToIndex
    }
  }

  private var runningLists: [UUID: Run] = [:]
  private var pendingScrollViews: [UUID: UIScrollView] = [:]

  func registerScrollView(_ scrollView: UIScrollView, listID: UUID) {
    guard isEnabled else { return }
    pendingScrollViews[listID] = scrollView
    guard let run = runningLists[listID] else { return }
    guard run.scrollView !== scrollView else { return }
    run.scrollView = scrollView
    OCamlDemoListVirtualizationProbe.shared.debug(
      "scroll_stress_scroll_view_registered list=\(listID.uuidString) content_height=\(scrollView.contentSize.height) bounds_height=\(scrollView.bounds.height)"
    )
  }

  func isActivelyScrolling(listID: UUID) -> Bool {
    guard let run = runningLists[listID] else { return false }
    return !run.isPausedAtEnd || run.hasScheduledTick
  }

  func isAnyRunning() -> Bool {
    runningLists.values.contains { !$0.isPausedAtEnd || $0.hasScheduledTick }
  }

  func start(listID: UUID, totalRows: Int, scrollToIndex: @escaping (Int) -> Void) {
    guard isEnabled else { return }
    guard totalRows > 0 else { return }
    if let run = runningLists[listID] {
      run.totalRows = totalRows
      if run.isPausedAtEnd {
        resumeFromCurrentOffset(listID: listID, run: run)
      }
      return
    }
    let listRun = Run(totalRows: totalRows, scrollToIndex: scrollToIndex)
    listRun.scrollView = pendingScrollViews[listID]
    runningLists[listID] = listRun
    if let scrollView = listRun.scrollView {
      OCamlDemoListVirtualizationProbe.shared.debug(
        "scroll_stress_scroll_view_registered list=\(listID.uuidString) content_height=\(scrollView.contentSize.height) bounds_height=\(scrollView.bounds.height)"
      )
    }
    run(listID: listID, index: 0, direction: 1)
  }

  private func pauseAtEnd(listID: UUID) {
    guard let run = runningLists[listID] else { return }
    run.isPausedAtEnd = true
    run.hasScheduledTick = false
  }

  private func resumeFromCurrentOffset(listID: UUID, run: Run) {
    run.isPausedAtEnd = false
    let currentOffset = run.scrollView?.contentOffset.y ?? 0
    let approximateRow = max(0, Int(currentOffset / 44))
    self.run(
      listID: listID,
      index: approximateRow,
      direction: 1
    )
  }

  private func run(
    listID: UUID,
    index: Int,
    direction: Int
  ) {
    guard let scheduledRun = runningLists[listID] else { return }
    guard !scheduledRun.hasScheduledTick else { return }
    scheduledRun.hasScheduledTick = true
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      guard let run = self.runningLists[listID] else { return }
      run.hasScheduledTick = false
      guard !run.isPausedAtEnd else { return }
      let totalRows = run.totalRows
      guard totalRows > 0 else { return }
      let boundedIndex = min(max(0, index), max(0, totalRows - 1))
      OCamlDemoFrameProbe.shared.markScrollSample(
        listID: listID,
        index: boundedIndex,
        totalRows: totalRows
      )
      if let scrollView = run.scrollView,
         scrollView.bounds.height > 0,
         scrollView.contentSize.height > scrollView.bounds.height {
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let currentOffset = scrollView.contentOffset.y
        let offsetDirection: Int
        if currentOffset <= 0 {
          offsetDirection = 1
        } else {
          offsetDirection = direction
        }
        let nextOffset = min(
          max(0, currentOffset + (Double(offsetDirection) * self.pointsPerTick)),
          maxOffset
        )
        scrollView.setContentOffset(
          CGPoint(x: scrollView.contentOffset.x, y: nextOffset),
          animated: false
        )
        if nextOffset >= maxOffset && offsetDirection > 0 {
          OCamlDemoListVirtualizationProbe.shared.debug(
            "scroll_stress_idle_at_end list=\(listID.uuidString) total_rows=\(totalRows) max_offset=\(maxOffset)"
          )
          self.pauseAtEnd(listID: listID)
          return
        }
        let approximateRow = max(0, Int(nextOffset / 44))
        self.run(
          listID: listID,
          index: approximateRow,
          direction: offsetDirection
        )
        return
      }
      run.scrollToIndex(boundedIndex)
      let nextDirection: Int
      if boundedIndex >= totalRows - 1 {
        OCamlDemoListVirtualizationProbe.shared.debug(
          "scroll_stress_idle_at_end list=\(listID.uuidString) total_rows=\(totalRows) max_index=\(boundedIndex)"
        )
        self.pauseAtEnd(listID: listID)
        return
      } else if boundedIndex <= 0 {
        nextDirection = 1
      } else {
        nextDirection = direction
      }
      let nextIndex = boundedIndex + (nextDirection * self.step)
      self.run(
        listID: listID,
        index: nextIndex,
        direction: nextDirection
      )
    }
  }
}

private final class OCamlDemoScrollIdleScheduler {
  static let shared = OCamlDemoScrollIdleScheduler()
  private static let retryDelay: DispatchTimeInterval = .milliseconds(50)

  private final class WeakScrollView {
    weak var scrollView: UIScrollView?

    init(_ scrollView: UIScrollView) {
      self.scrollView = scrollView
    }
  }

  private var scrollViewsByID: [ObjectIdentifier: WeakScrollView] = [:]

  func register(scrollView: UIScrollView) {
    scrollViewsByID[ObjectIdentifier(scrollView)] = WeakScrollView(scrollView)
  }

  func runWhenIdle(
    context: UnsafeMutableRawPointer?,
    perform: @escaping OCamlDemoMainCallback
  ) {
    runWhenIdle {
      perform(context)
    }
  }

  func runWhenIdle(_ action: @escaping () -> Void) {
    DispatchQueue.main.async {
      self.runWhenIdleOnMain(action)
    }
  }

  private func runWhenIdleOnMain(_ action: @escaping () -> Void) {
    pruneReleasedScrollViews()
    if hasActiveScroll {
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) {
        self.runWhenIdleOnMain(action)
      }
    } else {
      action()
    }
  }

  private var hasActiveScroll: Bool {
    if OCamlDemoScrollStressProbe.shared.isAnyRunning() {
      return true
    }
    return scrollViewsByID.values.contains { weakScrollView in
      guard let scrollView = weakScrollView.scrollView else { return false }
      return scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
    }
  }

  private func pruneReleasedScrollViews() {
    scrollViewsByID = scrollViewsByID.filter { _, weakScrollView in
      weakScrollView.scrollView != nil
    }
  }
}

private final class OCamlDemoListVirtualizationProbe {
  static let shared = OCamlDemoListVirtualizationProbe()

  private let logger = Logger(subsystem: "com.logseq.ocaml-demo", category: "ListDebug")
  private let isEnabled =
    ProcessInfo.processInfo.environment["OCAML_DEMO_LIST_DEBUG"] == "1"
  private var visibleRowsByList: [UUID: Set<UUID>] = [:]
  private var visibleIndicesByList: [UUID: Set<Int>] = [:]
  private var scrollPastFirstTenRowsByList: Set<UUID> = []
  private var retainedRowsByList: [UUID: Set<UUID>] = [:]
  private var peakVisibleRowsByList: [UUID: Int] = [:]
  private var reportStartedAtByList: [UUID: CFTimeInterval] = [:]
  private var appearedByList: [UUID: Int] = [:]
  private var disappearedByList: [UUID: Int] = [:]
  private var cacheHitsByList: [UUID: Int] = [:]
  private var bodyEvaluationsByList: [UUID: Int] = [:]
  private var renderedByList: [UUID: Int] = [:]
  private var refreshedByList: [UUID: Int] = [:]
  private var releasedByList: [UUID: Int] = [:]
  private var renderTotalMsByList: [UUID: Double] = [:]
  private var renderMaxMsByList: [UUID: Double] = [:]
  private var releaseTotalMsByList: [UUID: Double] = [:]
  private var releaseMaxMsByList: [UUID: Double] = [:]
  private var keyCallbackByList: [UUID: Int] = [:]
  private var keyCacheHitByList: [UUID: Int] = [:]
  private var keyTotalMsByList: [UUID: Double] = [:]
  private var keyMaxMsByList: [UUID: Double] = [:]
  private var uiRowsCreatedByList: [UUID: Int] = [:]
  private var uiRowsDestroyedByList: [UUID: Int] = [:]
  private var uiRowsLiveByList: [UUID: Int] = [:]
  private var mediaViewsCreated = 0
  private var mediaViewsDestroyed = 0
  private var mediaViewsLive = 0

  var isDebugEnabled: Bool {
    isEnabled
  }

  var isLifecycleProbeEnabled: Bool {
    isEnabled && ProcessInfo.processInfo.environment["OCAML_DEMO_LIST_LIFECYCLE_PROBE"] == "1"
  }

  func listUpdated(listID: UUID, totalRows: Int, reason: String) {
    guard isEnabled else { return }
    OCamlDemoFrameProbe.shared.start()
    let visibleCount = visibleRowsByList[listID]?.count ?? 0
    let retainedCount = retainedRowsByList[listID]?.count ?? 0
    let peakVisibleCount = peakVisibleRowsByList[listID] ?? 0
    log(
      "list_update reason=\(reason) list=\(listID.uuidString) total_rows=\(totalRows) visible_rows=\(visibleCount) retained_rows=\(retainedCount) peak_visible_rows=\(peakVisibleCount)"
    )
  }

  func rowAppeared(listID: UUID, rowID: UUID, totalRows _: Int) {
    guard isEnabled else { return }
    appearedByList[listID, default: 0] += 1
    visibleRowsByList[listID, default: []].insert(rowID)
    let visibleCount = visibleRowsByList[listID]?.count ?? 0
    let peakVisibleRows = max(peakVisibleRowsByList[listID] ?? 0, visibleCount)
    peakVisibleRowsByList[listID] = peakVisibleRows
  }

  func rowAppearedAtIndex(listID: UUID, rowID: UUID, index: Int, totalRows: Int) {
    guard isEnabled else { return }
    rowAppeared(listID: listID, rowID: rowID, totalRows: totalRows)
    visibleIndicesByList[listID, default: []].insert(index)
    if index >= 10 {
      scrollPastFirstTenRows(listID: listID, index: index)
    }
  }

  func rowDisappeared(listID: UUID, rowID: UUID, totalRows _: Int) {
    guard isEnabled else { return }
    disappearedByList[listID, default: 0] += 1
    visibleRowsByList[listID, default: []].remove(rowID)
  }

  func rowDisappearedAtIndex(listID: UUID, rowID: UUID, index: Int, totalRows: Int) {
    guard isEnabled else { return }
    rowDisappeared(listID: listID, rowID: rowID, totalRows: totalRows)
    visibleIndicesByList[listID, default: []].remove(index)
  }

  func scrollPastFirstTenRows(listID: UUID, index: Int) {
    guard isEnabled else { return }
    guard !scrollPastFirstTenRowsByList.contains(listID) else { return }
    scrollPastFirstTenRowsByList.insert(listID)
    log("scroll_past_first_ten_rows list=\(listID.uuidString) index=\(index)")
  }

  func operationStarted(name: String, listID: UUID, detail: String = "") -> CFTimeInterval {
    let startedAt = CACurrentMediaTime()
    guard isEnabled else { return startedAt }
    log("operation_start name=\(name) list=\(listID.uuidString) \(detail)")
    return startedAt
  }

  func operationFinished(
    name: String,
    listID: UUID,
    startedAt: CFTimeInterval,
    detail: String = ""
  ) {
    guard isEnabled else { return }
    let elapsedMs = (CACurrentMediaTime() - startedAt) * 1000
    log(
      "operation_latency name=\(name) list=\(listID.uuidString) elapsed_ms=\(debugDouble(elapsedMs, digits: 2)) \(detail)"
    )
  }

  func rowCacheHit(listID: UUID) {
    guard isEnabled else { return }
    cacheHitsByList[listID, default: 0] += 1
  }

  func rowBodyEvaluated(listID: UUID) -> Int {
    guard isEnabled else { return 0 }
    bodyEvaluationsByList[listID, default: 0] += 1
    return 0
  }

  func rowRendered(listID: UUID, elapsedMs: Double) {
    guard isEnabled else { return }
    renderedByList[listID, default: 0] += 1
    renderTotalMsByList[listID, default: 0] += elapsedMs
    renderMaxMsByList[listID] = max(renderMaxMsByList[listID] ?? 0, elapsedMs)
  }

  func rowRefreshed(listID: UUID, elapsedMs: Double) {
    guard isEnabled else { return }
    refreshedByList[listID, default: 0] += 1
    renderTotalMsByList[listID, default: 0] += elapsedMs
    renderMaxMsByList[listID] = max(renderMaxMsByList[listID] ?? 0, elapsedMs)
  }

  func rowRetained(listID: UUID, rowID: UUID) {
    guard isEnabled else { return }
    retainedRowsByList[listID, default: []].insert(rowID)
  }

  func rowReleased(listID: UUID, rowID: UUID, elapsedMs: Double) {
    guard isEnabled else { return }
    releasedByList[listID, default: 0] += 1
    releaseTotalMsByList[listID, default: 0] += elapsedMs
    releaseMaxMsByList[listID] = max(releaseMaxMsByList[listID] ?? 0, elapsedMs)
    retainedRowsByList[listID, default: []].remove(rowID)
  }

  func rowKeyResolved(listID: UUID, elapsedMs: Double) {
    guard isEnabled else { return }
    keyCallbackByList[listID, default: 0] += 1
    keyTotalMsByList[listID, default: 0] += elapsedMs
    keyMaxMsByList[listID] = max(keyMaxMsByList[listID] ?? 0, elapsedMs)
  }

  func rowKeyCacheHit(listID: UUID) {
    guard isEnabled else { return }
    keyCacheHitByList[listID, default: 0] += 1
  }

  func uiRowCreated(listID: UUID) {
    guard isEnabled else { return }
    uiRowsCreatedByList[listID, default: 0] += 1
    uiRowsLiveByList[listID, default: 0] += 1
  }

  func uiRowDestroyed(listID: UUID) {
    guard isEnabled else { return }
    uiRowsDestroyedByList[listID, default: 0] += 1
    uiRowsLiveByList[listID, default: 0] = max(0, uiRowsLiveByList[listID, default: 0] - 1)
  }

  func mediaViewCreated(kind _: String) {
    guard isEnabled else { return }
    mediaViewsCreated += 1
    mediaViewsLive += 1
  }

  func mediaViewDestroyed(kind _: String) {
    guard isEnabled else { return }
    mediaViewsDestroyed += 1
    mediaViewsLive = max(0, mediaViewsLive - 1)
  }

  func maybeReport(
    listID: UUID,
    totalRows: Int,
    cachedRows: Int,
    retainedOrder: Int,
    visibleIndices: Int
  ) {
    guard isEnabled else { return }
    let now = CACurrentMediaTime()
    let startedAt = reportStartedAtByList[listID] ?? now
    reportStartedAtByList[listID] = startedAt
    guard now - startedAt >= 1 else { return }
    let rendered = renderedByList[listID] ?? 0
    let refreshed = refreshedByList[listID] ?? 0
    let releaseCount = releasedByList[listID] ?? 0
    let renderCount = rendered + refreshed
    let renderTotal = renderTotalMsByList[listID] ?? 0
    let releaseTotal = releaseTotalMsByList[listID] ?? 0
    let keyCallbackCount = keyCallbackByList[listID] ?? 0
    let keyCacheHitCount = keyCacheHitByList[listID] ?? 0
    let keyTotal = keyTotalMsByList[listID] ?? 0
    let visibleIndices = visibleIndicesByList[listID] ?? []
    let minVisibleIndex = visibleIndices.min() ?? -1
    let maxVisibleIndex = visibleIndices.max() ?? -1
    let pastFirstTenRows =
      scrollPastFirstTenRowsByList.contains(listID) || maxVisibleIndex >= 10
    log(
      "list_perf seconds=\(debugDouble(now - startedAt, digits: 2)) list=\(listID.uuidString) total_rows=\(totalRows) visible_rows=\(visibleRowsByList[listID]?.count ?? 0) visible_indices=\(visibleIndices.count) min_visible_index=\(minVisibleIndex) max_visible_index=\(maxVisibleIndex) past_first_ten_rows=\(pastFirstTenRows) retained_rows=\(retainedRowsByList[listID]?.count ?? 0) cached_rows=\(cachedRows) retained_order=\(retainedOrder) ui_row_live=\(uiRowsLiveByList[listID] ?? 0) ui_row_created=\(uiRowsCreatedByList[listID] ?? 0) ui_row_destroyed=\(uiRowsDestroyedByList[listID] ?? 0) media_view_live=\(mediaViewsLive) media_view_created=\(mediaViewsCreated) media_view_destroyed=\(mediaViewsDestroyed) peak_visible_rows=\(peakVisibleRowsByList[listID] ?? 0) body=\(bodyEvaluationsByList[listID] ?? 0) appear=\(appearedByList[listID] ?? 0) disappear=\(disappearedByList[listID] ?? 0) cache_hit=\(cacheHitsByList[listID] ?? 0) render=\(rendered) refresh=\(refreshed) release=\(releaseCount) render_total_ms=\(debugDouble(renderTotal, digits: 2)) render_avg_ms=\(debugDouble(renderCount == 0 ? 0 : renderTotal / Double(renderCount), digits: 3)) render_max_ms=\(debugDouble(renderMaxMsByList[listID] ?? 0, digits: 2)) release_total_ms=\(debugDouble(releaseTotal, digits: 2)) release_avg_ms=\(debugDouble(releaseCount == 0 ? 0 : releaseTotal / Double(releaseCount), digits: 3)) release_max_ms=\(debugDouble(releaseMaxMsByList[listID] ?? 0, digits: 2))"
      + " key_callback=\(keyCallbackCount) key_cache_hit=\(keyCacheHitCount) key_total_ms=\(debugDouble(keyTotal, digits: 2)) key_avg_ms=\(debugDouble(keyCallbackCount == 0 ? 0 : keyTotal / Double(keyCallbackCount), digits: 4)) key_max_ms=\(debugDouble(keyMaxMsByList[listID] ?? 0, digits: 2))"
    )
    reportStartedAtByList[listID] = now
    appearedByList[listID] = 0
    disappearedByList[listID] = 0
    cacheHitsByList[listID] = 0
    bodyEvaluationsByList[listID] = 0
    renderedByList[listID] = 0
    refreshedByList[listID] = 0
    releasedByList[listID] = 0
    renderTotalMsByList[listID] = 0
    renderMaxMsByList[listID] = 0
    releaseTotalMsByList[listID] = 0
    releaseMaxMsByList[listID] = 0
    keyCallbackByList[listID] = 0
    keyCacheHitByList[listID] = 0
    keyTotalMsByList[listID] = 0
    keyMaxMsByList[listID] = 0
  }

  func debug(_ message: String) {
    guard isEnabled else { return }
    log(message)
  }

  func debugAlways(_ message: String) {
    log(message)
  }

  private func log(_ message: String) {
    fputs("[OCamlDemoListDebug] \(message)\n", stderr)
    fflush(stderr)
    logger.info("\(message, privacy: .public)")
  }

  private func debugDouble(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
  }
}

private final class OCamlDemoRenderedFrameScheduler: NSObject {
  static let shared = OCamlDemoRenderedFrameScheduler()

  private var displayLink: CADisplayLink?
  private var pendingActions: [() -> Void] = []
  private var remainingTicks = 0

  func runAfterRenderedFrame(_ action: @escaping () -> Void) {
    pendingActions.append(action)
    remainingTicks = max(remainingTicks, 2)
    OCamlDemoListVirtualizationProbe.shared.debug(
      "rendered_frame_scheduler_schedule pending=\(pendingActions.count) remaining_ticks=\(remainingTicks)"
    )
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func tick(_: CADisplayLink) {
    remainingTicks -= 1
    OCamlDemoListVirtualizationProbe.shared.debug(
      "rendered_frame_scheduler_tick remaining_ticks=\(remainingTicks) pending=\(pendingActions.count)"
    )
    guard remainingTicks <= 0 else { return }
    displayLink?.invalidate()
    displayLink = nil
    let actions = pendingActions
    pendingActions.removeAll()
    for action in actions {
      action()
    }
    OCamlDemoListVirtualizationProbe.shared.debug(
      "rendered_frame_scheduler_flushed actions=\(actions.count)"
    )
  }
}

private final class OCamlDemoHostModel: ObservableObject {
  @Published var root: OCamlDemoNode
  let callback: OCamlDemoEventCallback?

  init(root: OCamlDemoNode, callback: OCamlDemoEventCallback?) {
    self.root = root
    self.callback = callback
  }

  func sendClick(
    _ eventId: Int32?,
    animation: Animation? = nil,
    deferOnMain: Bool = true
  ) {
    guard let eventId else {
      return
    }
    dispatchEvent(animation: animation, deferOnMain: deferOnMain) { [callback] in
      callback?(eventId, nil)
    }
  }

  func sendChange(
    _ eventId: Int32?,
    text: String,
    animation: Animation? = nil,
    deferOnMain: Bool = true
  ) {
    guard let eventId else {
      ocaml_demoDatePickerDebugLogger.notice(
        "sendChange skipped nil event text=\(text, privacy: .public)"
      )
      return
    }
    ocaml_demoDatePickerDebugLogger.notice(
      "sendChange queued event=\(eventId, privacy: .public) text=\(text, privacy: .public) defer=\(deferOnMain, privacy: .public)"
    )
    dispatchEvent(animation: animation, deferOnMain: deferOnMain) { [callback, text] in
      text.withCString { pointer in
        ocaml_demoDatePickerDebugLogger.notice(
          "sendChange emit event=\(eventId, privacy: .public) text=\(text, privacy: .public)"
        )
        callback?(eventId, pointer)
      }
    }
  }

  private func dispatchEvent(
    animation: Animation? = nil,
    deferOnMain: Bool = true,
    _ emit: @escaping () -> Void
  ) {
    let performEmit = {
      if let animation {
        withAnimation(animation, emit)
      } else {
        emit()
      }
    }
    if Thread.isMainThread && !deferOnMain {
      performEmit()
    } else {
      DispatchQueue.main.async(execute: performEmit)
    }
  }
}

private func bindHostModel(_ model: OCamlDemoHostModel?, to node: OCamlDemoNode) {
  node.hostModel = model
  for child in node.children {
    bindHostModel(model, to: child)
  }
  for child in node.lazyListRowsByIndex.values {
    bindHostModel(model, to: child)
  }
  if let sheetContent = node.sheetContent {
    bindHostModel(model, to: sheetContent)
  }
  if let bottomSafeAreaInsetContent = node.bottomSafeAreaInsetContent {
    bindHostModel(model, to: bottomSafeAreaInsetContent)
  }
  if let popoverContent = node.popoverContent {
    bindHostModel(model, to: popoverContent)
  }
}

private final class OCamlDemoListLifecycleUIView: UIView {
  let listID: UUID?
  let mediaKind: String?

  init(listID: UUID? = nil, mediaKind: String? = nil) {
    self.listID = listID
    self.mediaKind = mediaKind
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = .clear
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }
}

private struct OCamlDemoRowLifecycleProbeView: UIViewRepresentable {
  let listID: UUID

  func makeUIView(context _: Context) -> OCamlDemoListLifecycleUIView {
    OCamlDemoListVirtualizationProbe.shared.uiRowCreated(listID: listID)
    return OCamlDemoListLifecycleUIView(listID: listID)
  }

  func updateUIView(_ uiView: OCamlDemoListLifecycleUIView, context _: Context) {}

  static func dismantleUIView(_ uiView: OCamlDemoListLifecycleUIView, coordinator _: ()) {
    if let listID = uiView.listID {
      OCamlDemoListVirtualizationProbe.shared.uiRowDestroyed(listID: listID)
    }
  }
}

private struct OCamlDemoMediaLifecycleProbeView: UIViewRepresentable {
  let kind: String

  func makeUIView(context _: Context) -> OCamlDemoListLifecycleUIView {
    OCamlDemoFrameProbe.shared.markMediaViewCreated(kind: kind)
    OCamlDemoListVirtualizationProbe.shared.mediaViewCreated(kind: kind)
    return OCamlDemoListLifecycleUIView(mediaKind: kind)
  }

  func updateUIView(_ uiView: OCamlDemoListLifecycleUIView, context _: Context) {}

  static func dismantleUIView(_ uiView: OCamlDemoListLifecycleUIView, coordinator _: ()) {
    if let mediaKind = uiView.mediaKind {
      OCamlDemoFrameProbe.shared.markMediaViewDestroyed(kind: mediaKind)
      OCamlDemoListVirtualizationProbe.shared.mediaViewDestroyed(kind: mediaKind)
    }
  }
}

private struct OCamlDemoScrollViewRegistrationView: UIViewRepresentable {
  let listID: UUID
  let node: OCamlDemoNode

  func makeUIView(context _: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    DispatchQueue.main.async {
      registerScrollView(from: view)
    }
    return view
  }

  func updateUIView(_ uiView: UIView, context _: Context) {
    DispatchQueue.main.async {
      registerScrollView(from: uiView)
    }
  }

  private func registerScrollView(from view: UIView) {
    guard let scrollView = view.enclosingOrWindowScrollView() else { return }
    node.lazyListScrollView = scrollView
    OCamlDemoScrollIdleScheduler.shared.register(scrollView: scrollView)
    OCamlDemoScrollStressProbe.shared.registerScrollView(scrollView, listID: listID)
  }
}

private extension UIView {
  func enclosingOrWindowScrollView() -> UIScrollView? {
    var view: UIView? = self
    while let current = view {
      if let scrollView = current as? UIScrollView {
        return scrollView
      }
      view = current.superview
    }
    return window?.largestScrollView()
  }

  func largestScrollView() -> UIScrollView? {
    var best: UIScrollView?
    var bestArea: CGFloat = 0
    func visit(_ view: UIView) {
      if let scrollView = view as? UIScrollView {
        let area = scrollView.bounds.width * scrollView.bounds.height
        if area > bestArea {
          bestArea = area
          best = scrollView
        }
      }
      for subview in view.subviews {
        visit(subview)
      }
    }
    visit(self)
    return best
  }
}

@ViewBuilder
private func ocaml_demoNativeLifecycleProbeBackground<Content: View>(
  @ViewBuilder content: () -> Content
) -> some View {
  if OCamlDemoListVirtualizationProbe.shared.isLifecycleProbeEnabled {
    content()
      .frame(width: 0, height: 0)
  } else {
    EmptyView()
  }
}

private struct OCamlDemoImageView: View {
  @ObservedObject var node: OCamlDemoNode

  var body: some View {
    Group {
      if node.imageSource == 1 {
        if let url = remoteImageURL(node.text) {
          AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
              RoundedRectangle(cornerRadius: node.imageCornerRadius ?? 0, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .overlay {
                  ProgressView()
                }
                .frame(
                  maxWidth: .infinity,
                  minHeight: node.imageMaxHeight,
                  maxHeight: node.imageMaxHeight,
                  alignment: .leading
                )
            case let .success(image):
              styledFileImage(image.resizable().scaledToFit())
            case .failure:
              RoundedRectangle(cornerRadius: node.imageCornerRadius ?? 0, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .overlay {
                  Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                }
                .frame(
                  maxWidth: .infinity,
                  minHeight: node.imageMaxHeight,
                  maxHeight: node.imageMaxHeight,
                  alignment: .leading
                )
            @unknown default:
              EmptyView()
            }
          }
        } else if let image = UIImage(contentsOfFile: node.text) {
          styledFileImage(Image(uiImage: image).resizable().scaledToFit())
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
    .background {
      ocaml_demoNativeLifecycleProbeBackground {
        OCamlDemoMediaLifecycleProbeView(kind: "image")
      }
    }
  }

  @ViewBuilder
  private func styledFileImage<Content: View>(_ image: Content) -> some View {
    if node.imageMaxHeight != nil || node.imageCornerRadius != nil {
      image
        .frame(
          maxWidth: .infinity,
          minHeight: node.imageMaxHeight,
          maxHeight: node.imageMaxHeight,
          alignment: .center
        )
        .clipped()
        .clipShape(.rect(cornerRadius: node.imageCornerRadius ?? 0, style: .continuous))
    } else {
      image
    }
  }

  private func remoteImageURL(_ value: String) -> URL? {
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
      return nil
    }
    return scheme == "http" || scheme == "https" ? url : nil
  }
}

private struct OCamlDemoYouTubeIframeView: UIViewRepresentable {
  let payload: String

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> WKWebView {
    OCamlDemoFrameProbe.shared.markMediaViewCreated(kind: "youtube-webkit")
    OCamlDemoListVirtualizationProbe.shared.mediaViewCreated(kind: "youtube-webkit")
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.backgroundColor = .clear
    webView.isUserInteractionEnabled = false
    webView.isOpaque = false
    webView.backgroundColor = .clear
    load(webView, context: context)
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    if context.coordinator.lastPayload != payload {
      load(webView, context: context)
    }
  }

  static func dismantleUIView(_ webView: WKWebView, coordinator _: Coordinator) {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    OCamlDemoFrameProbe.shared.markMediaViewDestroyed(kind: "youtube-webkit")
    OCamlDemoListVirtualizationProbe.shared.mediaViewDestroyed(kind: "youtube-webkit")
  }

  private func load(_ webView: WKWebView, context: Context) {
    context.coordinator.lastPayload = payload
    webView.loadHTMLString(youtubeHTML(payload: payload), baseURL: nil)
  }

  final class Coordinator {
    var lastPayload: String?
  }
}

private struct OCamlDemoAppWebViewPayload: Decodable {
  let resource: String
  let navigationJavaScript: String?
  let responseJavaScript: String?
}

private struct OCamlDemoAppWebView: UIViewRepresentable {
  let payload: String
  let node: OCamlDemoNode
  let model: OCamlDemoHostModel

  func makeCoordinator() -> Coordinator {
    Coordinator(node: node, model: model)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(context.coordinator, name: "ocaml_demoNative")
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    context.coordinator.webView = webView
    update(webView, coordinator: context.coordinator)
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    update(webView, coordinator: context.coordinator)
  }

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.stopLoading()
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "ocaml_demoNative"
    )
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    coordinator.webView = nil
  }

  private func update(_ webView: WKWebView, coordinator: Coordinator) {
    guard let data = payload.data(using: .utf8),
          let configuration = try? JSONDecoder().decode(
            OCamlDemoAppWebViewPayload.self,
            from: data
          ) else {
      return
    }

    coordinator.navigationJavaScript = configuration.navigationJavaScript
    coordinator.responseJavaScript = configuration.responseJavaScript
    if coordinator.resource != configuration.resource {
      coordinator.resource = configuration.resource
      coordinator.isLoaded = false
      coordinator.lastNavigationJavaScript = nil
      coordinator.lastResponseJavaScript = nil
      guard let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL else { return }
      let resourceURL = bundleRoot
        .appendingPathComponent(configuration.resource)
        .standardizedFileURL
      let allowedPrefix = bundleRoot.path.hasSuffix("/") ? bundleRoot.path : bundleRoot.path + "/"
      guard resourceURL.path.hasPrefix(allowedPrefix),
            FileManager.default.fileExists(atPath: resourceURL.path) else {
        return
      }
      webView.loadFileURL(resourceURL, allowingReadAccessTo: bundleRoot)
    } else {
      coordinator.applyPendingJavaScript()
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let node: OCamlDemoNode
    let model: OCamlDemoHostModel
    weak var webView: WKWebView?
    var resource: String?
    var isLoaded = false
    var navigationJavaScript: String?
    var responseJavaScript: String?
    var lastNavigationJavaScript: String?
    var lastResponseJavaScript: String?

    init(node: OCamlDemoNode, model: OCamlDemoHostModel) {
      self.node = node
      self.model = model
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
      isLoaded = true
      self.webView = webView
      applyPendingJavaScript()
    }

    func userContentController(
      _: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      let text: String
      if let value = message.body as? String {
        text = value
      } else if JSONSerialization.isValidJSONObject(message.body),
                let data = try? JSONSerialization.data(withJSONObject: message.body),
                let value = String(data: data, encoding: .utf8) {
        text = value
      } else {
        text = String(describing: message.body)
      }
      model.sendChange(node.changeEventId, text: text)
    }

    func applyPendingJavaScript() {
      guard isLoaded, let webView else { return }
      if let navigationJavaScript,
         navigationJavaScript != lastNavigationJavaScript {
        lastNavigationJavaScript = navigationJavaScript
        webView.evaluateJavaScript(navigationJavaScript)
      }
      if let responseJavaScript,
         responseJavaScript != lastResponseJavaScript {
        lastResponseJavaScript = responseJavaScript
        webView.evaluateJavaScript(responseJavaScript)
      }
    }
  }
}

private struct OCamlDemoDeferredYouTubeIframeView: View {
  let payload: String
  @State private var isLoaded = false

  var body: some View {
    Group {
      if isLoaded {
        OCamlDemoYouTubeIframeView(payload: payload)
          .allowsHitTesting(false)
      } else {
        Button {
          isLoaded = true
        } label: {
          ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.secondary.opacity(0.12))
            VStack(spacing: 8) {
              Image(systemName: "play.circle.fill")
                .font(.system(size: 40, weight: .semibold))
              Text("YouTube")
                .font(ocaml_demoNativePreferredFont(.headline))
            }
            .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .background {
      ocaml_demoNativeLifecycleProbeBackground {
        OCamlDemoMediaLifecycleProbeView(kind: "youtube-preview")
      }
    }
  }
}

private func youtubePayload(from kind: String) -> String? {
  if kind.hasPrefix("youtube:") {
    return String(kind.dropFirst("youtube:".count))
  }
  if kind.hasPrefix("youtube-iframe:") {
    return String(kind.dropFirst("youtube-iframe:".count))
  }
  return nil
}

private func appWebViewPayload(from kind: String) -> String? {
  let prefix = "app-webview:"
  guard kind.hasPrefix(prefix) else { return nil }
  return String(kind.dropFirst(prefix.count))
}

private func youtubeHTML(payload: String) -> String {
  guard let embedURL = youtubeEmbedURL(payload: payload) else {
    return "<html><body></body></html>"
  }
  return """
  <html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
      html, body { margin: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
      iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; border-radius: 12px; }
    </style>
  </head>
  <body>
    <iframe src="\(embedURL.absoluteString)" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
  </body>
  </html>
  """
}

private func youtubeEmbedURL(payload: String) -> URL? {
  let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
  let videoID: String?
  if let url = URL(string: value), let host = url.host?.lowercased() {
    let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    if normalizedHost == "youtu.be" {
      videoID = url.pathComponents.dropFirst().first
    } else if normalizedHost == "youtube.com" || normalizedHost == "m.youtube.com" {
      if url.pathComponents.count >= 3, url.pathComponents[1] == "embed" {
        videoID = url.pathComponents[2]
      } else {
        videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?
          .first(where: { $0.name == "v" })?
          .value
      }
    } else {
      videoID = nil
    }
  } else {
    videoID = value
  }
  guard let videoID = videoID, isValidYouTubeVideoID(videoID) else {
    return nil
  }
  return URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0")
}

private func isValidYouTubeVideoID(_ value: String) -> Bool {
  !value.isEmpty
    && value.allSatisfy { character in
      character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}

private struct OCamlDemoLazyListPosition: Identifiable {
  let index: Int
  let id: String
}

private struct OCamlDemoLazyListPositions: RandomAccessCollection {
  typealias Index = Int
  typealias Element = OCamlDemoLazyListPosition

  let owner: OCamlDemoNode
  let startIndex = 0
  let endIndex: Int

  subscript(position: Int) -> OCamlDemoLazyListPosition {
    if position >= 0 && position < owner.lazyListIdentityKeysByIndex.count {
      return OCamlDemoLazyListPosition(
        index: position,
        id: owner.lazyListIdentityKeysByIndex[position]
      )
    }
    return OCamlDemoLazyListPosition(
      index: position,
      id: ocaml_demoNativePublishedLazyRowKey(owner: owner, index: position)
    )
  }
}

private struct OCamlDemoRootView: View {
  @ObservedObject var model: OCamlDemoHostModel

  var body: some View {
    ZStack(alignment: .top) {
      ocaml_demoHomeBodyBackgroundLayer()
        .ignoresSafeArea(.container, edges: .all)
      OCamlDemoNodeView(node: model.root, model: model)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

private final class OCamlDemoHostingController: UIHostingController<OCamlDemoRootView> {
  override var preferredStatusBarStyle: UIStatusBarStyle {
    .darkContent
  }
}

private func makeHostingController(
  root: OCamlDemoNode,
  callback: OCamlDemoEventCallback?
) -> UIHostingController<OCamlDemoRootView> {
  let model = OCamlDemoHostModel(root: root, callback: callback)
  bindHostModel(model, to: root)
  let controller = OCamlDemoHostingController(rootView: OCamlDemoRootView(model: model))
  ocaml_demoConfigureNavigationBarAppearance(for: controller.traitCollection)
  controller.view.backgroundColor = ocaml_demoHomeBodyUIColor(for: controller.traitCollection)
  controller.view.isOpaque = true
  objc_setAssociatedObject(controller, "OCamlDemoSwiftUIModel", model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  return controller
}

private struct OCamlDemoImagePayload {
  let id: String
  let localPath: String
  let mimeType: String
  let byteSize: Int
  let sha256: String
  let width: Int
  let height: Int
  let recognizedText: String?

  var eventText: String {
    var lines = [
      "ocaml_demo-image-payload",
      "id=\(id)",
      "local_path=\(localPath)",
      "mime_type=\(mimeType)",
      "byte_size=\(byteSize)",
      "sha256=\(sha256)",
      "width=\(width)",
      "height=\(height)"
    ]
    if let recognizedText, !recognizedText.isEmpty {
      lines.append("recognized_text=\(percentEncodePayloadField(recognizedText))")
    }
    return lines.joined(separator: "\n")
  }
}

private func percentEncodePayloadField(_ string: String) -> String {
  string.utf8.map { byte in
    let isDigit = byte >= 48 && byte <= 57
    let isUppercase = byte >= 65 && byte <= 90
    let isLowercase = byte >= 97 && byte <= 122
    if isDigit || isUppercase || isLowercase || byte == 45 || byte == 46 || byte == 95 || byte == 126 {
      return String(UnicodeScalar(byte))
    }
    return String(format: "%%%02X", byte)
  }.joined()
}

private func mimeType(for contentType: UTType?) -> String {
  if contentType?.conforms(to: .png) == true {
    return "image/png"
  }
  if contentType?.conforms(to: .heic) == true {
    return "image/heic"
  }
  return "image/jpeg"
}

private func fileExtension(for mimeType: String) -> String {
  switch mimeType {
  case "image/png":
    return "png"
  case "image/heic":
    return "heic"
  default:
    return "jpg"
  }
}

private func saveImagePayload(
  data: Data,
  mimeType: String,
  idPrefix: String,
  recognizedText: String? = nil
) throws -> OCamlDemoImagePayload {
  let id = "\(idPrefix)-\(UUID().uuidString)"
  let directory = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)
    .first?
    .appendingPathComponent("OCamlDemoImages", isDirectory: true)
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("OCamlDemoImages", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appendingPathComponent("\(id).\(fileExtension(for: mimeType))")
  try data.write(to: url, options: [.atomic])
  let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  let image = UIImage(data: data)
  let scale = image?.scale ?? 1
  let width = Int(((image?.size.width ?? 0) * scale).rounded())
  let height = Int(((image?.size.height ?? 0) * scale).rounded())
  return OCamlDemoImagePayload(
    id: id,
    localPath: url.path,
    mimeType: mimeType,
    byteSize: data.count,
    sha256: digest,
    width: width,
    height: height,
    recognizedText: recognizedText
  )
}

private func recognizeText(in data: Data) async -> String? {
  guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
  return await withCheckedContinuation { continuation in
    let request = VNRecognizeTextRequest { request, _ in
      let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
        .compactMap { observation in observation.topCandidates(1).first?.string }
      continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      continuation.resume(returning: nil)
    }
  }
}

private struct OCamlDemoKeyboardDismissControlsModifier: ViewModifier {
  let node: OCamlDemoNode
  let model: OCamlDemoHostModel

  @ViewBuilder
  func body(content: Content) -> some View {
#if os(iOS)
    if node.keyboardDismissControls || !node.keyboardToolbarItems.isEmpty {
      content
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            ForEach(node.keyboardToolbarItems) { item in
              Button {
                if let eventId = item.eventId {
                  model.sendClick(eventId)
                }
              } label: {
                keyboardToolbarLabel(item)
              }
              .disabled(!item.isEnabled)
            }
            Spacer()
            Button {
              ocaml_demoDismissKeyboard()
            } label: {
              if node.keyboardToolbarItems.isEmpty {
                Text("Done")
              } else {
                Image(systemName: "keyboard.chevron.compact.down")
                  .accessibilityLabel("Dismiss keyboard")
              }
            }
          }
        }
    } else {
      content
    }
#else
    content
#endif
  }

  @ViewBuilder
  private func keyboardToolbarLabel(_ item: OCamlDemoToolbarItem) -> some View {
    if let systemImage = item.systemImage {
      if item.isTitleVisible {
        Label(item.title, systemImage: systemImage)
      } else {
        Image(systemName: systemImage)
          .accessibilityLabel(item.title)
      }
    } else {
      Text(item.title)
    }
  }
}

private struct OCamlDemoScrollDismissesKeyboardModifier: ViewModifier {
  let node: OCamlDemoNode

  @ViewBuilder
  func body(content: Content) -> some View {
#if os(iOS)
    if node.scrollDismissesKeyboard {
      content.scrollDismissesKeyboard(.interactively)
    } else {
      content
    }
#else
    content
#endif
  }
}

private struct OCamlDemoListRowSeparatorModifier: ViewModifier {
  let node: OCamlDemoNode

  @ViewBuilder
  func body(content: Content) -> some View {
    if node.hideListRowSeparator {
      content.listRowSeparator(.hidden)
    } else {
      content
    }
  }
}

private struct OCamlDemoSearchModifier: ViewModifier {
  let node: OCamlDemoNode
  let model: OCamlDemoHostModel

  @ViewBuilder
  func body(content: Content) -> some View {
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
        content.searchable(text: text, isPresented: isPresented, prompt: Text(prompt))
      } else if node.hasSearchPresentation {
        content.searchable(text: text, isPresented: isPresented)
      } else if let prompt = node.searchPrompt {
        content.searchable(text: text, prompt: Text(prompt))
      } else {
        content.searchable(text: text)
      }
    } else {
      content
    }
  }
}

private struct OCamlDemoNavigationTitleModifier: ViewModifier {
  let node: OCamlDemoNode

  @ViewBuilder
  func body(content: Content) -> some View {
    if let title = node.navigationTitle {
      content
        .navigationTitle(title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .ocaml_demoBottomBarChrome()
#endif
    } else {
      content
    }
  }
}

private struct OCamlDemoHorizontalSwipeModifier: ViewModifier {
  let node: OCamlDemoNode
  let model: OCamlDemoHostModel
  @GestureState private var dragTranslation: CGSize = .zero

  private var horizontalOffset: CGFloat {
    horizontalSwipeOffset(for: dragTranslation)
  }

  private func horizontalSwipeActiveTranslation(for translation: CGSize) -> CGSize {
    let horizontal = translation.width
    let vertical = translation.height
    guard abs(horizontal) > abs(vertical) * 1.2 else { return .zero }
    if horizontal < 0 {
      guard node.horizontalSwipeLeftEventId != nil else { return .zero }
    } else if horizontal > 0 {
      guard node.horizontalSwipeRightEventId != nil else { return .zero }
    } else {
      return .zero
    }
    return translation
  }

  private func horizontalSwipeOffset(for translation: CGSize) -> CGFloat {
    let horizontal = horizontalSwipeActiveTranslation(for: translation).width
    guard horizontal != 0 else { return 0 }
    return max(-64, min(64, horizontal * 0.35))
  }

  private func horizontalSwipeEventId(for translation: CGSize) -> Int32? {
    let horizontal = translation.width
    return horizontal < 0 ? node.horizontalSwipeLeftEventId : node.horizontalSwipeRightEventId
  }

  func body(content: Content) -> some View {
    content
      .contentShape(.rect)
      .offset(x: horizontalOffset)
      .animation(.spring(response: 0.24, dampingFraction: 0.82), value: horizontalOffset)
      .simultaneousGesture(
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
          .updating($dragTranslation) { value, state, _ in
            state = horizontalSwipeActiveTranslation(for: value.translation)
          }
          .onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height
            guard horizontalSwipeActiveTranslation(for: value.translation) != .zero else {
              return
            }
            guard abs(horizontal) >= 44, abs(horizontal) > abs(vertical) * 1.4 else {
              return
            }
            guard let eventId = horizontalSwipeEventId(for: value.translation) else {
              return
            }
            ocaml_demoPerformLightHapticFeedback()
            model.sendClick(eventId)
          }
      )
  }
}

private struct OCamlDemoNodeModifiers: ViewModifier {
  let node: OCamlDemoNode
  let model: OCamlDemoHostModel

  func body(content: Content) -> some View {
    bottomSafeAreaInset(
      appearAction(
        horizontalSwipeAction(
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
                          alignment: node.frameAlignment.swiftUIAlignment
                        )
                        .frame(
                          maxWidth: node.frameMaxWidth,
                          alignment: node.frameAlignment.swiftUIAlignment
                        )
                      )
                    )
                  )
              )
            )
          )
        )
      )
    )
      .modifier(OCamlDemoKeyboardDismissControlsModifier(node: node, model: model))
      .modifier(OCamlDemoScrollDismissesKeyboardModifier(node: node))
      .modifier(OCamlDemoListRowSeparatorModifier(node: node))
      .modifier(OCamlDemoSearchModifier(node: node, model: model))
      .modifier(OCamlDemoNavigationTitleModifier(node: node))
      .alert(
        node.alertTitle,
        isPresented: Binding(
          get: { node.isAlertPresented },
          set: { presented in
            node.isAlertPresented = presented
            if !presented {
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
          set: { presented in
            node.isConfirmationDialogPresented = presented
            if !presented {
              model.sendClick(node.confirmationDialogDismissEventId)
            }
          }
        ),
        titleVisibility: .visible
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
          set: { presented in
            node.isPopoverPresented = presented
            if !presented {
              model.sendClick(node.popoverDismissEventId)
            }
          }
        )
      ) {
        if let popoverContent = node.popoverContent {
          OCamlDemoNodeView(node: popoverContent, model: model)
        }
      }
      .sheet(
        isPresented: Binding(
          get: { node.isSheetPresented },
          set: { presented in
            node.isSheetPresented = presented
            if !presented {
              model.sendClick(node.dismissEventId)
            }
          }
        )
      ) {
        if let sheetContent = node.sheetContent {
          ocaml_demoSheetContentHost {
            OCamlDemoNodeView(node: sheetContent, model: model)
          }
            .presentationDetents(sheetPresentationDetents)
        }
      }
  }

  @ViewBuilder
  private func horizontalSwipeAction<Content: View>(_ content: Content) -> some View {
    if node.horizontalSwipeLeftEventId == nil && node.horizontalSwipeRightEventId == nil {
      content
    } else {
      content
        .modifier(OCamlDemoHorizontalSwipeModifier(node: node, model: model))
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
      .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
  }

  private var sheetPresentationDetents: Set<PresentationDetent> {
    guard !node.sheetDetents.isEmpty else { return [.large] }
    return Set(node.sheetDetents.map { detent in
      switch detent.kind {
      case 0:
        return .medium
      case 2:
        return .fraction(detent.value)
      case 3:
        return .height(detent.value)
      default:
        return .large
      }
    })
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
        Color(uiColor: .secondarySystemGroupedBackground),
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
}

private func alertButtonRole(_ rawRole: Int32) -> ButtonRole? {
  switch rawRole {
  case 1: return .cancel
  case 2: return .destructive
  default: return nil
  }
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
    let uiColor = UIColor(self)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }
    return String(
      format: "#%02X%02X%02X",
      Int(round(red * 255)),
      Int(round(green * 255)),
      Int(round(blue * 255))
    )
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
          .font(ocaml_demoNativePreferredFont(.title2, weight: .semibold))
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

private struct OCamlDemoTextFieldView: View {
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    if node.textFieldStyle == 1 {
      textField
        .textFieldStyle(.plain)
        .font(ocaml_demoNativePreferredFont(size: 18, weight: .regular))
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .ocaml_demoLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
    } else if node.textFieldStyle == 2 {
      textField
        .textFieldStyle(.plain)
        .font(ocaml_demoNativePreferredFont(.body))
    } else {
      textField
        .textFieldStyle(.roundedBorder)
    }
  }

  private var textField: some View {
    Group {
      if node.isTextFieldSecure {
        SecureField(
          node.placeholder ?? "",
          text: Binding(
            get: { node.text },
            set: { value in
              node.text = value
              let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
                name: "text_change",
                listID: node.id
              )
              model.sendChange(node.changeEventId, text: value)
              OCamlDemoListVirtualizationProbe.shared.operationFinished(
                name: "text_change",
                listID: node.id,
                startedAt: startedAt
              )
            }
          )
        )
      } else if node.textFieldAxis == 0
        && (node.textFieldDeleteBackwardAtStartEventId != nil || node.textFieldClearButton != 0)
      {
        OCamlDemoDeleteAwareTextField(
          placeholder: node.placeholder ?? "",
          text: Binding(
            get: { node.text },
            set: { value in
              node.text = value
            }
          ),
          isFocused: node.isTextFieldFocused,
          clearButtonMode: node.textFieldClearButton,
          keyboardToolbarItems: node.keyboardToolbarItems,
          model: model,
          onChange: { value in
            node.text = value
            let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
              name: "text_change",
              listID: node.id
            )
            model.sendChange(node.changeEventId, text: value, deferOnMain: false)
            OCamlDemoListVirtualizationProbe.shared.operationFinished(
              name: "text_change",
              listID: node.id,
              startedAt: startedAt
            )
          },
          onSubmit: {
            model.sendClick(node.clickEventId)
          },
          onBlur: {
            model.sendClick(node.textFieldBlurEventId)
          },
          onDeleteBackwardAtStart: {
            model.sendClick(node.textFieldDeleteBackwardAtStartEventId)
          }
        )
      } else if node.textFieldAxis == 1 && node.textFieldDeleteBackwardAtStartEventId != nil {
        OCamlDemoDeleteAwareTextView(
          placeholder: node.placeholder ?? "",
          text: Binding(
            get: { node.text },
            set: { value in
              node.text = value
            }
          ),
          isFocused: node.isTextFieldFocused,
          keyboardToolbarItems: node.keyboardToolbarItems,
          model: model,
          onChange: { value in
            node.text = value
            let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
              name: "text_change",
              listID: node.id
            )
            model.sendChange(node.changeEventId, text: value, deferOnMain: false)
            OCamlDemoListVirtualizationProbe.shared.operationFinished(
              name: "text_change",
              listID: node.id,
              startedAt: startedAt
            )
          },
          onSubmit: {
            model.sendClick(node.clickEventId)
          },
          onBlur: {
            model.sendClick(node.textFieldBlurEventId)
          },
          onDeleteBackwardAtStart: {
            model.sendClick(node.textFieldDeleteBackwardAtStartEventId)
          }
        )
      } else {
        if node.textFieldAxis == 1 {
          TextField(
            node.placeholder ?? "",
            text: Binding(
              get: { node.text },
              set: { value in
                node.text = value
                let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
                  name: "text_change",
                  listID: node.id
                )
                model.sendChange(node.changeEventId, text: value)
                OCamlDemoListVirtualizationProbe.shared.operationFinished(
                  name: "text_change",
                  listID: node.id,
                  startedAt: startedAt
                )
              }
            ),
            axis: .vertical
          )
        } else {
          TextField(
            node.placeholder ?? "",
            text: Binding(
              get: { node.text },
              set: { value in
                node.text = value
                let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
                  name: "text_change",
                  listID: node.id
                )
                model.sendChange(node.changeEventId, text: value)
                OCamlDemoListVirtualizationProbe.shared.operationFinished(
                  name: "text_change",
                  listID: node.id,
                  startedAt: startedAt
                )
              }
            )
          )
        }
      }
    }
    .onSubmit {
      model.sendClick(node.clickEventId)
    }
    .focused($isTextFieldFocused)
    .onAppear {
      isTextFieldFocused = node.isTextFieldFocused
    }
    .onChange(of: node.isTextFieldFocused) { _, isFocused in
      isTextFieldFocused = isFocused
    }
    .onChange(of: isTextFieldFocused) { old, new in
      if old && !new && node.isTextFieldFocused {
        model.sendClick(node.textFieldBlurEventId)
      }
    }
  }
}

private final class OCamlDemoDeleteAwareUITextView: UITextView {
  var onDeleteBackwardAtStart: (() -> Void)?
  var keyboardAccessorySignature: String?
  private let placeholderLabel = UILabel()
  private var wantsFocus = false
  private var suppressNextBlur = false

  var placeholder: String = "" {
    didSet {
      placeholderLabel.text = placeholder
      updatePlaceholderVisibility()
    }
  }

  override var font: UIFont? {
    didSet {
      placeholderLabel.font = font
    }
  }

  override init(frame: CGRect, textContainer: NSTextContainer?) {
    super.init(frame: frame, textContainer: textContainer)
    placeholderLabel.textColor = .placeholderText
    placeholderLabel.numberOfLines = 1
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(placeholderLabel)
    NSLayoutConstraint.activate([
      placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
      placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func deleteBackward() {
    let caretAtStart: Bool
    if let selectedTextRange {
      caretAtStart =
        selectedTextRange.isEmpty
        && offset(from: beginningOfDocument, to: selectedTextRange.start) == 0
    } else {
      caretAtStart = text?.isEmpty ?? true
    }

    if caretAtStart {
      ocaml_demoNativeInteractionDebug("keyboard_structural_submit", detail: "kind=delete text_view")
      OCamlDemoKeyboardHandoff.shared.retainKeyboard(from: self)
      onDeleteBackwardAtStart?()
      return
    }
    super.deleteBackward()
    updatePlaceholderVisibility()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    focusIfRequested()
  }

  func requestFocus() {
    guard !wantsFocus || !isFirstResponder else { return }
    wantsFocus = true
    focusIfRequested()
    if !isFirstResponder {
      retryFocusOnNextMainTurns(remaining: 3)
    }
  }

  func clearFocusRequest() {
    wantsFocus = false
    if isFirstResponder {
      suppressNextBlur = true
      _ = resignFirstResponder()
    }
  }

  func dismissKeyboardForUser() {
    wantsFocus = false
    _ = resignFirstResponder()
  }

  func updatePlaceholderVisibility() {
    placeholderLabel.isHidden = !(text?.isEmpty ?? true)
  }

  func consumeBlurSuppression() -> Bool {
    if suppressNextBlur {
      suppressNextBlur = false
      return true
    }
    return false
  }

  private func retryFocusOnNextMainTurns(remaining: Int) {
    guard remaining > 0 else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      focusIfRequested()
      retryFocusOnNextMainTurns(remaining: remaining - 1)
    }
  }

  private func focusIfRequested() {
    guard wantsFocus else { return }
    guard window != nil else { return }
    guard !isFirstResponder else { return }
    becomeFirstResponder()
    OCamlDemoKeyboardHandoff.shared.completeHandoff()
    let end = endOfDocument
    selectedTextRange = textRange(from: end, to: end)
  }

  override func resignFirstResponder() -> Bool {
    wantsFocus = false
    return super.resignFirstResponder()
  }
}

private var ocaml_demoNativeKeyboardAccessoryHandlerKey: UInt8 = 0

private final class OCamlDemoKeyboardAccessoryHandler: NSObject {
  private let eventIds: [Int32?]
  private let onClick: (Int32) -> Void
  private let onDismiss: () -> Void

  init(eventIds: [Int32?], onClick: @escaping (Int32) -> Void, onDismiss: @escaping () -> Void) {
    self.eventIds = eventIds
    self.onClick = onClick
    self.onDismiss = onDismiss
  }

  @objc func activateItem(_ sender: UIBarButtonItem) {
    guard sender.tag >= 0 && sender.tag < eventIds.count else { return }
    if let eventId = eventIds[sender.tag] {
      onClick(eventId)
    }
  }

  @objc func dismissKeyboard(_ sender: UIBarButtonItem) {
    onDismiss()
  }
}

private func ocaml_demoNativeKeyboardAccessorySignature(_ items: [OCamlDemoToolbarItem]) -> String {
  items
    .map { item in
      [
        item.id,
        item.title,
        item.systemImage ?? "",
        String(item.isTitleVisible),
        String(item.isEnabled),
        String(describing: item.eventId),
      ].joined(separator: ":")
    }
    .joined(separator: "|")
}

private func ocaml_demoNativeKeyboardAccessoryToolbar(
  items: [OCamlDemoToolbarItem],
  onClick: @escaping (Int32) -> Void,
  onDismiss: @escaping () -> Void
) -> UIToolbar? {
  guard !items.isEmpty else {
    return nil
  }

  let toolbar = UIToolbar()
  let handler =
    OCamlDemoKeyboardAccessoryHandler(
      eventIds: items.map(\.eventId),
      onClick: onClick,
      onDismiss: onDismiss
    )
  toolbar.isTranslucent = true
  toolbar.items =
    items.enumerated().map { index, item in
      let button: UIBarButtonItem
      if let systemImage = item.systemImage, let image = UIImage(systemName: systemImage) {
        button =
          UIBarButtonItem(
            image: image,
            style: .plain,
            target: handler,
            action: #selector(OCamlDemoKeyboardAccessoryHandler.activateItem(_:))
          )
      } else {
        button =
          UIBarButtonItem(
            title: item.title,
            style: .plain,
            target: handler,
            action: #selector(OCamlDemoKeyboardAccessoryHandler.activateItem(_:))
          )
      }
      button.tag = index
      button.accessibilityLabel = item.title
      button.isEnabled = item.isEnabled
      return button
    }
    + [
      UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(
        image: UIImage(systemName: "keyboard.chevron.compact.down"),
        style: .plain,
        target: handler,
        action: #selector(OCamlDemoKeyboardAccessoryHandler.dismissKeyboard(_:))
      ),
    ]
  objc_setAssociatedObject(
    toolbar,
    &ocaml_demoNativeKeyboardAccessoryHandlerKey,
    handler,
    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
  )
  toolbar.sizeToFit()
  return toolbar
}

private struct OCamlDemoDeleteAwareTextView: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  let isFocused: Bool
  let keyboardToolbarItems: [OCamlDemoToolbarItem]
  let model: OCamlDemoHostModel
  let onChange: (String) -> Void
  let onSubmit: () -> Void
  let onBlur: () -> Void
  let onDeleteBackwardAtStart: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> OCamlDemoDeleteAwareUITextView {
    let textView = OCamlDemoDeleteAwareUITextView(frame: .zero)
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.isScrollEnabled = false
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.font = ocaml_demoNativePreferredUIFont(.body)
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textView.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    return textView
  }

  func updateUIView(_ textView: OCamlDemoDeleteAwareUITextView, context: Context) {
    context.coordinator.parent = self
    textView.placeholder = placeholder
    textView.font = ocaml_demoNativePreferredUIFont(.body)
    if textView.text != text {
      textView.text = text
      textView.updatePlaceholderVisibility()
    }
    textView.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    let keyboardAccessorySignature =
      ocaml_demoNativeKeyboardAccessorySignature(keyboardToolbarItems)
    if textView.keyboardAccessorySignature != keyboardAccessorySignature {
      textView.keyboardAccessorySignature = keyboardAccessorySignature
      textView.inputAccessoryView = ocaml_demoNativeKeyboardAccessoryToolbar(
        items: keyboardToolbarItems,
        onClick: { eventId in
          OCamlDemoKeyboardHandoff.shared.retainKeyboard(from: textView)
          context.coordinator.model.sendClick(eventId, deferOnMain: false)
        },
        onDismiss: {
          textView.dismissKeyboardForUser()
        }
      )
      if textView.isFirstResponder {
        textView.reloadInputViews()
      }
    }
    let shouldRequestFocus = isFocused && !context.coordinator.lastIsFocused
    if shouldRequestFocus {
      textView.requestFocus()
    } else if !isFocused {
      textView.clearFocusRequest()
    }
    context.coordinator.lastIsFocused = isFocused
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: OCamlDemoDeleteAwareTextView
    var lastIsFocused = false
    let model: OCamlDemoHostModel

    init(_ parent: OCamlDemoDeleteAwareTextView) {
      self.parent = parent
      self.model = parent.model
    }

    func textViewDidChange(_ textView: UITextView) {
      updateText(textView.text ?? "")
      (textView as? OCamlDemoDeleteAwareUITextView)?.updatePlaceholderVisibility()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      if let textView = textView as? OCamlDemoDeleteAwareUITextView,
         textView.consumeBlurSuppression() {
        return
      }
      if OCamlDemoKeyboardHandoff.shared.shouldSuppressBlur(from: textView) {
        return
      }
      parent.onBlur()
    }

    private func updateText(_ text: String) {
      if parent.text != text {
        parent.text = text
        parent.onChange(text)
      }
    }

    func textView(
      _ textView: UITextView,
      shouldChangeTextIn range: NSRange,
      replacementText text: String
    ) -> Bool {
      if text == "\n" {
        ocaml_demoNativeInteractionDebug("keyboard_structural_submit", detail: "kind=return text_view")
        OCamlDemoKeyboardHandoff.shared.retainKeyboard(from: textView)
        parent.onSubmit()
        return false
      }
      return true
    }
  }
}

private final class OCamlDemoDeleteAwareUITextField: UITextField {
  var onDeleteBackwardAtStart: (() -> Void)?
  var keyboardAccessorySignature: String?
  private var wantsFocus = false
  private var suppressNextBlur = false

  override func deleteBackward() {
    let caretAtStart: Bool
    if let selectedTextRange {
      caretAtStart =
        selectedTextRange.isEmpty
        && offset(from: beginningOfDocument, to: selectedTextRange.start) == 0
    } else {
      caretAtStart = text?.isEmpty ?? true
    }

    if caretAtStart {
      ocaml_demoNativeInteractionDebug("keyboard_structural_submit", detail: "kind=delete text_field")
      OCamlDemoKeyboardHandoff.shared.retainKeyboard(from: self)
      onDeleteBackwardAtStart?()
      return
    }
    super.deleteBackward()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    focusIfRequested()
  }

  func requestFocus() {
    guard !wantsFocus || !isFirstResponder else { return }
    wantsFocus = true
    focusIfRequested()
    if !isFirstResponder {
      retryFocusOnNextMainTurns(remaining: 3)
    }
  }

  func clearFocusRequest() {
    wantsFocus = false
    if isFirstResponder {
      suppressNextBlur = true
      _ = resignFirstResponder()
    }
  }

  func dismissKeyboardForUser() {
    wantsFocus = false
    _ = resignFirstResponder()
  }

  func consumeBlurSuppression() -> Bool {
    if suppressNextBlur {
      suppressNextBlur = false
      return true
    }
    return false
  }

  private func retryFocusOnNextMainTurns(remaining: Int) {
    guard remaining > 0 else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      focusIfRequested()
      retryFocusOnNextMainTurns(remaining: remaining - 1)
    }
  }

  private func focusIfRequested() {
    guard wantsFocus else { return }
    guard window != nil else { return }
    guard !isFirstResponder else { return }
    becomeFirstResponder()
    OCamlDemoKeyboardHandoff.shared.completeHandoff()
    let end = endOfDocument
    selectedTextRange = textRange(from: end, to: end)
  }

  override func resignFirstResponder() -> Bool {
    wantsFocus = false
    return super.resignFirstResponder()
  }
}

private struct OCamlDemoDeleteAwareTextField: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  let isFocused: Bool
  let clearButtonMode: Int32
  let keyboardToolbarItems: [OCamlDemoToolbarItem]
  let model: OCamlDemoHostModel
  let onChange: (String) -> Void
  let onSubmit: () -> Void
  let onBlur: () -> Void
  let onDeleteBackwardAtStart: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> OCamlDemoDeleteAwareUITextField {
    let textField = OCamlDemoDeleteAwareUITextField(frame: .zero)
    textField.borderStyle = .none
    textField.clearButtonMode = uiTextFieldClearButtonMode(clearButtonMode)
    textField.delegate = context.coordinator
    textField.addTarget(
      context.coordinator,
      action: #selector(Coordinator.textFieldEditingChanged(_:)),
      for: .editingChanged
    )
    textField.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    textField.font = ocaml_demoNativePreferredUIFont(.body)
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return textField
  }

  func updateUIView(_ textField: OCamlDemoDeleteAwareUITextField, context: Context) {
    context.coordinator.parent = self
    textField.placeholder = placeholder
    textField.clearButtonMode = uiTextFieldClearButtonMode(clearButtonMode)
    textField.font = ocaml_demoNativePreferredUIFont(.body)
    if textField.text != text {
      textField.text = text
    }
    textField.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    let keyboardAccessorySignature =
      ocaml_demoNativeKeyboardAccessorySignature(keyboardToolbarItems)
    if textField.keyboardAccessorySignature != keyboardAccessorySignature {
      textField.keyboardAccessorySignature = keyboardAccessorySignature
      textField.inputAccessoryView = ocaml_demoNativeKeyboardAccessoryToolbar(
        items: keyboardToolbarItems,
        onClick: { eventId in
          OCamlDemoKeyboardHandoff.shared.retainKeyboard(from: textField)
          context.coordinator.model.sendClick(eventId, deferOnMain: false)
        },
        onDismiss: {
          textField.dismissKeyboardForUser()
        }
      )
      if textField.isFirstResponder {
        textField.reloadInputViews()
      }
    }
    let shouldRequestFocus = isFocused && !context.coordinator.lastIsFocused
    if shouldRequestFocus {
      textField.requestFocus()
    } else if !isFocused {
      textField.clearFocusRequest()
    }
    context.coordinator.lastIsFocused = isFocused
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: OCamlDemoDeleteAwareTextField
    var lastIsFocused = false
    let model: OCamlDemoHostModel

    init(_ parent: OCamlDemoDeleteAwareTextField) {
      self.parent = parent
      self.model = parent.model
    }

    @objc func textFieldEditingChanged(_ textField: UITextField) {
      updateText(textField.text ?? "")
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
      updateText(textField.text ?? "")
    }

    private func updateText(_ text: String) {
      if parent.text != text {
        parent.text = text
        parent.onChange(text)
      }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
      if let textField = textField as? OCamlDemoDeleteAwareUITextField,
         textField.consumeBlurSuppression() {
        return
      }
      if OCamlDemoKeyboardHandoff.shared.shouldSuppressBlur(from: textField) {
        return
      }
      parent.onBlur()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      ocaml_demoNativeInteractionDebug("keyboard_structural_submit", detail: "kind=return text_field")
      OCamlDemoKeyboardHandoff.shared.retainKeyboard(from: textField)
      parent.onSubmit()
      return false
    }
  }
}

private func uiTextFieldClearButtonMode(_ mode: Int32) -> UITextField.ViewMode {
  switch mode {
  case 1:
    return .whileEditing
  default:
    return .never
  }
}

private struct OCamlDemoShareLinkView: View {
  @ObservedObject var node: OCamlDemoNode

  var body: some View {
    if let url = URL(string: node.shareURL) {
      ShareLink(item: url) {
        Label(node.text, systemImage: "square.and.arrow.up")
      }
    } else {
      Label(node.text, systemImage: "square.and.arrow.up")
        .foregroundStyle(.secondary)
    }
  }
}

private struct OCamlDemoCompactSidebarDrawerGestureModifier: ViewModifier {
  let isEnabled: Bool
  let drawerWidth: CGFloat
  let onChanged: (DragGesture.Value) -> Void
  let onEnded: (DragGesture.Value) -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      content.highPriorityGesture(
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
          .onChanged(onChanged)
          .onEnded(onEnded)
      )
    } else {
      content
    }
  }
}

private struct OCamlDemoCompactSidebarSplitView: View {
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  let sidebarTitle: String
  @State private var isCompactSidebarOpen = false
  @State private var compactSidebarDragOffset: CGFloat = 0
  @State private var compactSidebarDragAxis: DragAxis?
  @State private var isCompactSidebarDragging = false
  @State private var sidebarKeyboardBottomPadding: CGFloat = 0
  @State private var didRunCompactSidebarStress = false

  private enum DragAxis {
    case horizontal
    case vertical
  }

  private var compactSidebarSpringAnimation: Animation {
    .interactiveSpring(response: 0.16, dampingFraction: 0.96, blendDuration: 0.02)
  }

  private var selectedRouteIndex: Int? {
    node.tabs.firstIndex { tab in
      tab.id == node.selectedTabId
    }
  }

  private var selectedRouteTitle: String {
    node.tabs.first { tab in
      tab.id == node.selectedTabId
    }?.title ?? node.tabs.first?.title ?? sidebarTitle
  }

  var body: some View {
    let _ = OCamlDemoBodyProbe.shared.mark("compact_split_body")
    ZStack {
      ocaml_demoHomeBodyBackground
        .ignoresSafeArea(.container, edges: .all)

      GeometryReader { proxy in
        let screenSize = proxy.size
        let drawerWidth = compactSidebarDrawerWidth(containerWidth: screenSize.width)
        let visibleWidth = compactSidebarVisibleWidth(drawerWidth: drawerWidth)
        let progress = drawerWidth > 0 ? visibleWidth / drawerWidth : 0
        let sidebarTopInset = ocaml_demoDrawerSidebarTopInset(proxy.safeAreaInsets.top)
        let sidebarBottomInset = ocaml_demoDrawerSidebarBottomInset(proxy.safeAreaInsets.bottom)

        ZStack(alignment: .leading) {
          ocaml_demoHomeBodyBackground
            .ignoresSafeArea(.container, edges: .all)

          compactSidebarContent
            .padding(.top, sidebarTopInset)
            .padding(.bottom, sidebarBottomInset)
            .frame(width: drawerWidth, height: screenSize.height, alignment: .topLeading)
            .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
            .opacity(progress)
            .scrollDisabled(isCompactSidebarDragging)

          compactSidebarMainPage
            .frame(width: screenSize.width, height: screenSize.height)
            .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
            .compositingGroup()
            .clipShape(
              RoundedRectangle(
                cornerRadius: compactSidebarMainCornerRadius(progress: progress),
                style: .continuous
              )
            )
            .shadow(
              color: .black.opacity(compactSidebarMainShadowOpacity(progress: progress)),
              radius: 24 * progress,
              x: -10 * progress,
              y: 0
            )
            .offset(x: visibleWidth)
            .allowsHitTesting(!isCompactSidebarOpen)

          if isCompactSidebarOpen {
            Color.clear
              .frame(
                width: max(0, screenSize.width - visibleWidth),
                height: screenSize.height
              )
              .contentShape(Rectangle())
              .offset(x: visibleWidth)
              .onTapGesture {
                setCompactSidebarOpen(false)
              }
          }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
        .contentShape(Rectangle())
        .modifier(
          OCamlDemoCompactSidebarDrawerGestureModifier(
            isEnabled: isCompactSidebarOpen,
            drawerWidth: drawerWidth,
            onChanged: { value in
              handleCompactSidebarDragChanged(value, drawerWidth: drawerWidth)
            },
            onEnded: { value in
              handleCompactSidebarDragEnded(value, drawerWidth: drawerWidth)
            }
          )
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
          sidebarKeyboardBottomPadding = compactSidebarKeyboardBottomPadding(
            notification: notification,
            containerMaxY: proxy.frame(in: .global).maxY,
            safeAreaBottom: proxy.safeAreaInsets.bottom
          )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
          sidebarKeyboardBottomPadding = 0
        }
      }
      .ignoresSafeArea(.container, edges: .all)
      .onAppear {
        runCompactSidebarStressIfNeeded()
      }
    }
  }

  @ViewBuilder
  private func selectedRouteDetail(suppressNativeToolbar: Bool) -> some View {
    if let selectedRouteIndex, selectedRouteIndex < node.children.count {
      OCamlDemoNodeView(
        node: node.children[selectedRouteIndex],
        model: model,
        suppressNativeToolbar: suppressNativeToolbar
      )
    } else if let firstChild = node.children.first {
      OCamlDemoNodeView(
        node: firstChild,
        model: model,
        suppressNativeToolbar: suppressNativeToolbar
      )
    } else {
      EmptyView()
    }
  }

  private var compactSidebarMainPage: some View {
    let _ = OCamlDemoBodyProbe.shared.mark("compact_main_page")
    return Group {
      if node.sidebarCompactTopBarVisible {
        selectedRouteDetail(suppressNativeToolbar: false)
          .id(node.selectedTabId)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .environment(
            \.ocaml_demoCompactSidebarToolbar,
            OCamlDemoCompactSidebarToolbar(
              title: selectedRouteTitle,
              openSidebar: {
                setCompactSidebarOpen(true)
              }
            )
          )
      } else {
        selectedRouteDetail(suppressNativeToolbar: false)
          .id(node.selectedTabId)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
    .navigationBarBackButtonHidden(true)
  }

  private var compactSidebarContent: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack(alignment: .center, spacing: 16) {
        Text(sidebarTitle)
          .font(ocaml_demoNativePreferredFont(size: 28, weight: .bold, relativeTo: .title))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .accessibilityAddTraits(.isHeader)

        Spacer(minLength: 12)

        sidebarHeaderActionButton
      }
      .padding(.horizontal, 12)

      VStack(alignment: .leading, spacing: 0) {
        sidebarRouteButtons
      }

      Spacer()
    }
    .padding(.horizontal, 12)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      sidebarBottomControls
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, sidebarKeyboardBottomPadding)
        .animation(.easeOut(duration: 0.2), value: sidebarKeyboardBottomPadding)
    }
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var sidebarRouteButtons: some View {
    if node.sidebarActions.isEmpty && node.sidebarHistoryActions.isEmpty {
      ForEach(node.tabs) { tab in
        Button {
          selectCompactSidebarTab(tab)
        } label: {
          sidebarRowLabel(
            title: tab.title,
            systemImage: tab.systemImage,
            isSelected: tab.id == node.selectedTabId
          )
        }
        .buttonStyle(.plain)
      }
    } else {
      ForEach(node.sidebarActions) { action in
        sidebarActionButton(action, isSelected: action.id == node.selectedTabId)
      }

      if !node.sidebarHistoryActions.isEmpty, let historyTitle = node.sidebarHistoryTitle {
        Text(historyTitle)
          .font(ocaml_demoNativePreferredFont(size: 18, weight: .semibold, relativeTo: .headline))
          .foregroundStyle(.primary)
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 14)
      }

      ForEach(node.sidebarHistoryActions) { action in
        sidebarActionButton(action, isSelected: false, usesContextMenu: true)
      }
    }
  }

  private func selectCompactSidebarTab(_ tab: OCamlDemoTab) {
    ocaml_demoDismissKeyboard()
    if isCompactSidebarOpen {
      ocaml_demoPerformLightHapticFeedback()
    }
    withAnimation(compactSidebarSpringAnimation) {
      node.selectedTabId = tab.id
      updateCompactSidebarOpenState(false)
    }
    model.sendChange(node.tabSelectEventId, text: tab.id)
  }

  @ViewBuilder
  private func sidebarActionButton(
    _ action: OCamlDemoSidebarAction,
    isSelected: Bool,
    usesContextMenu: Bool = false
  ) -> some View {
    if action.menuActions.isEmpty {
      Button {
        performSidebarAction(action)
      } label: {
        sidebarRowLabel(
          title: action.title,
          subtitle: action.subtitle,
          systemImage: action.systemImage,
          isSelected: isSelected
        )
      }
      .buttonStyle(.plain)
    } else {
      if usesContextMenu {
        Button {
          performSidebarAction(action)
        } label: {
          sidebarRowLabel(
            title: action.title,
            subtitle: action.subtitle,
            systemImage: action.systemImage,
            isSelected: isSelected
          )
        }
        .buttonStyle(.plain)
        .contextMenu {
          sidebarActionMenuItems(action)
        }
      } else {
        Menu {
          sidebarActionMenuItems(action)
        } label: {
          sidebarRowLabel(
            title: action.title,
            subtitle: action.subtitle,
            systemImage: action.systemImage,
            isSelected: isSelected
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func performSidebarAction(_ action: OCamlDemoSidebarAction) {
    let selectedTab = sidebarActionSelectedTab(action)
    if let selectedTab {
      selectSidebarActionRoute(selectedTab, closesSidebar: action.closesSidebar)
    } else {
      closeCompactSidebarIfNeeded(action)
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

  private func selectSidebarActionRoute(_ selectedTab: String, closesSidebar: Bool) {
    ocaml_demoDismissKeyboard()
    if closesSidebar {
      if isCompactSidebarOpen {
        ocaml_demoPerformLightHapticFeedback()
      }
      withAnimation(compactSidebarSpringAnimation) {
        node.selectedTabId = selectedTab
        updateCompactSidebarOpenState(false)
      }
    } else {
      node.selectedTabId = selectedTab
    }
  }

  private func closeCompactSidebarIfNeeded(_ action: OCamlDemoSidebarAction) {
    if action.closesSidebar {
      setCompactSidebarOpen(false)
    }
  }

  @ViewBuilder
  private func sidebarActionMenuItems(_ action: OCamlDemoSidebarAction) -> some View {
    ForEach(action.menuActions) { menuAction in
      Button(role: menuAction.style == 1 ? .destructive : nil) {
        if let eventId = menuAction.eventId {
          model.sendClick(eventId)
        }
        setCompactSidebarOpen(false)
      } label: {
        if let systemImage = menuAction.systemImage {
          Label(menuAction.title, systemImage: systemImage)
        } else {
          Text(menuAction.title)
        }
      }
    }
  }

  private func sidebarRowLabel(
    title: String,
    subtitle: String? = nil,
    systemImage: String?,
    isSelected: Bool
  ) -> some View {
    HStack(spacing: 12) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 24)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(
            ocaml_demoNativePreferredFont(
              size: subtitle == nil ? 16 : 17,
              weight: subtitle == nil ? .semibold : .regular,
              relativeTo: subtitle == nil ? .callout : .body
            )
          )
          .foregroundStyle(.primary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(ocaml_demoNativePreferredFont(.caption))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: subtitle == nil ? 52 : nil)
      .padding(.vertical, subtitle == nil ? 0 : 8)
      .padding(.horizontal, 12)
      .background(
        isSelected
          ? Color.primary.opacity(0.06)
          : Color.clear,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var sidebarHeaderActionButton: some View {
    if let action = node.sidebarHeaderAction {
      if action.avatarImage != nil || action.avatarInitial != nil {
        Button {
          performSidebarAction(action)
        } label: {
          sidebarHeaderAvatar(action)
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .accessibilityLabel(action.title)
      } else {
        Button {
          performSidebarAction(action)
        } label: {
          Image(systemName: action.systemImage ?? "person.crop.circle")
            .font(.headline.weight(.semibold))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .ocaml_demoLiquidGlassPanel(cornerRadius: 22, isInteractive: true, isTransparent: true)
        .accessibilityLabel(action.title)
      }
    } else {
      Button {
        setCompactSidebarOpen(false)
      } label: {
        Image(systemName: "xmark")
          .font(.headline.weight(.semibold))
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func sidebarHeaderAvatar(_ action: OCamlDemoSidebarAction) -> some View {
    if let avatarImage = action.avatarImage,
       let url = URL(string: avatarImage),
       url.scheme == "http" || url.scheme == "https" {
      AsyncImage(url: url) { phase in
        switch phase {
        case let .success(image):
          image
            .resizable()
            .scaledToFill()
        default:
          sidebarHeaderAvatarFallback(action)
        }
      }
    } else {
      sidebarHeaderAvatarFallback(action)
    }
  }

  private func sidebarHeaderAvatarFallback(_ action: OCamlDemoSidebarAction) -> some View {
    Circle()
      .fill(Color.pink.opacity(0.9))
      .overlay {
        Text(action.avatarInitial ?? "?")
          .font(ocaml_demoNativePreferredFont(size: 14, weight: .semibold, relativeTo: .caption))
          .foregroundStyle(.white)
      }
  }

  @ViewBuilder
  private var sidebarBottomControls: some View {
    if node.sidebarBottomSearchPlaceholder != nil || node.sidebarBottomAction != nil {
      HStack(spacing: 12) {
        if let placeholder = node.sidebarBottomSearchPlaceholder {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .font(.body.weight(.medium))
              .foregroundStyle(.secondary)
            TextField(
              placeholder,
              text: Binding(
                get: { node.sidebarBottomSearchText },
                set: { value in
                  node.sidebarBottomSearchText = value
                  model.sendChange(node.sidebarBottomSearchEventId, text: value)
                }
              )
            )
              .textFieldStyle(.plain)
          }
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .ocaml_demoLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
        }

        if let action = node.sidebarBottomAction {
          sidebarBottomActionButton(action)
        }
      }
    }
  }

  @ViewBuilder
  private func sidebarBottomActionButton(_ action: OCamlDemoSidebarAction) -> some View {
    Button {
      performSidebarAction(action)
    } label: {
      if action.chrome == 2 {
        Image(systemName: action.systemImage ?? "xmark")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 52, height: 52)
          .contentShape(Circle())
      } else {
        Label(action.title, systemImage: action.systemImage ?? "square.and.pencil")
          .font(ocaml_demoNativePreferredFont(size: 18, weight: .semibold, relativeTo: .headline))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(.white)
          .padding(.horizontal, 24)
          .frame(height: 58)
          .contentShape(Capsule())
      }
    }
    .buttonStyle(.plain)
    .modifier(SidebarBottomActionChrome(chrome: action.chrome))
    .accessibilityLabel(action.title)
  }

  private func compactSidebarKeyboardBottomPadding(
    notification: Notification,
    containerMaxY: CGFloat,
    safeAreaBottom: CGFloat
  ) -> CGFloat {
    guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    else { return 0 }
    let overlap = max(0, containerMaxY - keyboardFrame.minY)
    return max(0, overlap - safeAreaBottom)
  }

  private func compactSidebarPeekWidth(containerWidth: CGFloat) -> CGFloat {
    min(max(56, containerWidth * 0.16), 88)
  }

  private func compactSidebarDrawerWidth(containerWidth: CGFloat) -> CGFloat {
    max(0, containerWidth - compactSidebarPeekWidth(containerWidth: containerWidth))
  }

  private func compactSidebarVisibleWidth(drawerWidth: CGFloat) -> CGFloat {
    max(0, min(drawerWidth, (isCompactSidebarOpen ? drawerWidth : 0) + compactSidebarDragOffset))
  }

  private func compactSidebarMainCornerRadius(progress: CGFloat) -> CGFloat {
    48 * progress
  }

  private func compactSidebarMainShadowOpacity(progress: CGFloat) -> Double {
    0.18 * Double(progress)
  }

  private func setCompactSidebarOpen(_ isOpen: Bool) {
    ocaml_demoNativeInteractionDebug(
      "compact_sidebar_set_open",
      detail: "from=\(isCompactSidebarOpen) to=\(isOpen)"
    )
    ocaml_demoDismissKeyboard()
    if isOpen != isCompactSidebarOpen {
      ocaml_demoPerformLightHapticFeedback()
    }
    withAnimation(compactSidebarSpringAnimation) {
      updateCompactSidebarOpenState(isOpen)
    }
  }

  private func runCompactSidebarStressIfNeeded() {
    guard !didRunCompactSidebarStress else { return }
    let environment = ProcessInfo.processInfo.environment
    guard
      environment["OCAML_DEMO_SIDEBAR_STRESS"] == "1"
        || environment["OCAML_DEMO_SIDEBAR_STRESS"] == "true"
    else { return }
    didRunCompactSidebarStress = true
    let toggles = max(1, Int(environment["OCAML_DEMO_SIDEBAR_STRESS_TOGGLES"] ?? "") ?? 8)
    let delay = max(0.12, Double(environment["OCAML_DEMO_SIDEBAR_STRESS_DELAY"] ?? "") ?? 0.45)
    for index in 0..<toggles {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay * Double(index + 1)) {
        let nextOpen = index % 2 == 0
        setCompactSidebarOpen(nextOpen)
      }
    }
  }

  private func updateCompactSidebarOpenState(_ isOpen: Bool) {
    isCompactSidebarOpen = isOpen
    compactSidebarDragOffset = 0
    compactSidebarDragAxis = nil
    isCompactSidebarDragging = false
  }

  private func handleCompactSidebarDragChanged(
    _ value: DragGesture.Value,
    drawerWidth: CGFloat
  ) {
    guard node.sidebarCompactTopBarVisible || isCompactSidebarOpen else { return }
    let horizontal = value.translation.width
    let vertical = value.translation.height
    if compactSidebarDragAxis == nil, abs(horizontal) > 5 || abs(vertical) > 5 {
      compactSidebarDragAxis = abs(horizontal) >= abs(vertical) ? .horizontal : .vertical
    }
    guard compactSidebarDragAxis == .horizontal else { return }
    if !isCompactSidebarDragging {
      ocaml_demoNativeInteractionDebug(
        "compact_sidebar_drag_start",
        detail: "open=\(isCompactSidebarOpen) horizontal=\(horizontal) vertical=\(vertical)"
      )
      ocaml_demoDismissKeyboard()
    }
    isCompactSidebarDragging = true
    let baseWidth = isCompactSidebarOpen ? drawerWidth : 0
    compactSidebarDragOffset = max(-baseWidth, min(drawerWidth - baseWidth, horizontal))
  }

  private func handleCompactSidebarDragEnded(
    _ value: DragGesture.Value,
    drawerWidth: CGFloat
  ) {
    defer {
      compactSidebarDragAxis = nil
      isCompactSidebarDragging = false
    }
    guard node.sidebarCompactTopBarVisible || isCompactSidebarOpen else {
      compactSidebarDragOffset = 0
      return
    }
    let horizontal = value.translation.width
    let vertical = value.translation.height
    let resolvedAxis =
      compactSidebarDragAxis ?? (abs(horizontal) >= abs(vertical) ? DragAxis.horizontal : .vertical)
    guard resolvedAxis == .horizontal else {
      compactSidebarDragOffset = 0
      return
    }
    let visibleWidth: CGFloat
    if isCompactSidebarDragging {
      visibleWidth = compactSidebarVisibleWidth(drawerWidth: drawerWidth)
    } else {
      visibleWidth = max(0, min(drawerWidth, (isCompactSidebarOpen ? drawerWidth : 0) + horizontal))
    }
    let shouldOpen: Bool
    if isCompactSidebarOpen {
      let predictedCloseDistance = max(0, -value.predictedEndTranslation.width)
      let currentCloseDistance = max(0, -compactSidebarDragOffset)
      shouldOpen =
        predictedCloseDistance < max(56, drawerWidth * 0.18)
        && currentCloseDistance < max(72, drawerWidth * 0.24)
    } else {
      let predictedVisibleWidth = max(0, min(drawerWidth, value.predictedEndTranslation.width))
      shouldOpen =
        horizontal > 44 || predictedVisibleWidth > 56 || visibleWidth > drawerWidth * 0.28
    }
    ocaml_demoNativeInteractionDebug(
      "compact_sidebar_drag_end",
      detail: "open=\(isCompactSidebarOpen) horizontal=\(horizontal) predicted=\(value.predictedEndTranslation.width) should_open=\(shouldOpen)"
    )
    setCompactSidebarOpen(shouldOpen)
  }
}

private struct OCamlDemoNodeView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.ocaml_demoCompactSidebarToolbar) private var compactSidebarToolbar
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  var suppressListRowActions = false
  var suppressNativeToolbar = false
  @State private var toolbarExportFilename = "Export.txt"
  @State private var toolbarExportContentType = "public.plain-text"
  @State private var toolbarExportContent = ""
  @State private var isToolbarExportPresented = false
  @State private var listScrollBlurSentForFocusedIndex: Int?

  var body: some View {
    let _ = OCamlDemoBodyProbe.shared.mark("node_body")
    applyModifiers(to: base)
      .fileExporter(
        isPresented: $isToolbarExportPresented,
        document: OCamlDemoExportDocument(content: toolbarExportContent),
        contentType: toolbarExportUTType,
        defaultFilename: toolbarExportFilename
      ) { _ in }
  }

  @ViewBuilder
  private var base: some View {
    switch node.kind {
    case .label:
      Text(node.text)
        .font(textFont(node.textStyle, weight: node.textWeight))
        .foregroundStyle(textColor(node.textColor))

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
                .font(ocaml_demoNativePreferredFont(.caption2))
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
        .buttonStyle(.plain)
        .disabled(!node.isEnabled)
      }

    case .textField:
      OCamlDemoTextFieldView(node: node, model: model)

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
      ZStack(alignment: .topLeading) {
        if node.text.isEmpty, let placeholder = node.placeholder {
          Text(placeholder)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
        }
        TextEditor(
          text: Binding(
            get: { node.text },
            set: { value in
              node.text = value
              let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
                name: "text_change",
                listID: node.id
              )
              model.sendChange(node.changeEventId, text: value)
              OCamlDemoListVirtualizationProbe.shared.operationFinished(
                name: "text_change",
                listID: node.id,
                startedAt: startedAt
              )
            }
          )
        )
        .font(ocaml_demoNativePreferredFont(.body))
        .frame(minHeight: 96)
        .scrollContentBackground(.hidden)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))

    case .progressView:
      ProgressView(value: node.progressValue)
        .tint(.green)

    case .verticalStack:
      VStack(alignment: .leading, spacing: node.spacing) {
        childViews
      }

    case .horizontalStack:
      HStack(alignment: node.horizontalStackAlignment.swiftUIVerticalAlignment, spacing: node.spacing) {
        childViews
      }

    case .zStack:
      ZStack {
        childViews
      }

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
      Form {
        childViews
      }

    case .scrollView:
      ScrollView {
        childViews
      }
      .background(ocaml_demoHomeBodyBackground)
      .ocaml_demoContentUnderBottomBar()

    case .list:
      listView

    case .movableRows:
      movableRowsView

    case .navigationStack:
      NavigationStack {
        VStack(spacing: 0) {
          childViews
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
        .ocaml_demoBottomBarChrome()
        .modifier(OCamlDemoCompactSidebarToolbarModifier(toolbar: compactSidebarToolbar))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
      .ocaml_demoBottomBarChrome()

    case .navigationPathStack:
      navigationPathStack

    case .navigationLink:
      if let navigationValue = node.navigationLinkValue {
        NavigationLink(value: navigationValue) {
          navigationLinkLabel(suppressRowActions: true)
        }
        .buttonStyle(.plain)
      } else {
        NavigationLink {
          if node.children.indices.contains(1) {
            OCamlDemoNodeView(node: node.children[1], model: model)
              .onAppear {
                model.sendClick(node.navigationActivateEventId)
              }
              .onDisappear {
                model.sendClick(node.navigationDeactivateEventId)
              }
          } else {
            EmptyView()
          }
        } label: {
          navigationLinkLabel(suppressRowActions: true)
        }
        .simultaneousGesture(
          TapGesture().onEnded {
            model.sendClick(node.navigationActivateEventId)
          }
        )
        .buttonStyle(.plain)
      }

    case .navigationSplit:
      navigationSplitView

    case .adaptiveLayout:
      adaptiveLayoutView

    case .tabView:
      tabView

    case .sidebarSplit:
      sidebarSplitView

    case .image:
      OCamlDemoImageView(node: node)

    case .listRow:
      OCamlDemoListRowView(
        node: node,
        model: model,
        suppressRowActions: suppressListRowActions
      )

    case .section:
      section

    case .picker:
      picker

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
      OCamlDemoPhotoPickerView(node: node, model: model)
        .disabled(!node.isEnabled)

    case .fileExporter:
      OCamlDemoFileExporterView(node: node)
        .disabled(!node.isEnabled)

    case .shareLink:
      OCamlDemoShareLinkView(node: node)
        .disabled(!node.isEnabled)

    case .fileImporter:
      OCamlDemoFileImporterView(node: node, model: model)

    case .cameraCapture:
      OCamlDemoCameraCaptureView(node: node, model: model)

    case .customView:
      if node.text == "congrats-effect" {
        OCamlDemoCongratsEffectView()
      } else if node.text == "system-grouped-background" {
        ocaml_demoHomeBodyBackgroundLayer()
          .ignoresSafeArea(.container, edges: .all)
      } else if let payload = appWebViewPayload(from: node.text) {
        OCamlDemoAppWebView(payload: payload, node: node, model: model)
      } else if let payload = youtubePayload(from: node.text) {
        OCamlDemoDeferredYouTubeIframeView(payload: payload)
      } else {
        Text(node.text)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func customButtonLabelHitTarget<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .contentShape(Rectangle())
  }

  private var childViews: some View {
    ForEach(node.children) { child in
      OCamlDemoNodeView(node: child, model: model)
    }
  }

  private var listView: some View {
    ScrollViewReader { proxy in
      listContent(proxy)
    }
  }

  @ViewBuilder
  private func listContent(_ proxy: ScrollViewProxy) -> some View {
    if shouldUseNativeList {
      nativeList(proxy)
    } else {
      lazyScrollList(proxy)
    }
  }

  private func nativeList(_ proxy: ScrollViewProxy) -> some View {
    List {
      nativeListRows()
    }
    .environment(\.editMode, .constant(node.isListEditMode ? .active : .inactive))
    .environment(\.defaultMinListRowHeight, 1)
    .refreshable {
      model.sendClick(node.listRefreshEventId)
    }
    .transaction { transaction in
      transaction.animation = nil
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background {
      ocaml_demoHomeBodyBackground
      OCamlDemoScrollViewRegistrationView(listID: node.id, node: node)
        .frame(width: 0, height: 0)
    }
    .ocaml_demoContentUnderBottomBar()
    .onAppear {
      listAppeared(proxy)
    }
    .onChange(of: node.children.count + node.lazyListRowCount) { _, _ in
      listChildrenCountChanged()
    }
    .onChange(of: node.listFocusedRowIndex) { _, _ in
      listScrollBlurSentForFocusedIndex = nil
      scrollFocusedRow(proxy)
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 12)
        .onChanged { value in
          blurFocusedRowForUserScroll(value.translation)
        }
    )
  }

  private func lazyScrollList(_ proxy: ScrollViewProxy) -> some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        lazyScrollRows()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background {
      ocaml_demoHomeBodyBackground
      OCamlDemoScrollViewRegistrationView(listID: node.id, node: node)
        .frame(width: 0, height: 0)
    }
    .ocaml_demoContentUnderBottomBar()
    .onAppear {
      listAppeared(proxy)
    }
    .onChange(of: node.children.count + node.lazyListRowCount) { _, _ in
      listChildrenCountChanged()
    }
    .onChange(of: node.listFocusedRowIndex) { _, _ in
      listScrollBlurSentForFocusedIndex = nil
      scrollFocusedRow(proxy)
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 12)
        .onChanged { value in
          blurFocusedRowForUserScroll(value.translation)
        }
    )
  }

  @ViewBuilder
  private func lazyScrollRows() -> some View {
    if let providerId = node.lazyListProviderId {
      ForEach(lazyListPositions()) { position in
        lazyListRowPosition(
          providerId: providerId,
          position: position
        )
      }
    } else {
      nativeStaticListRows()
    }
  }

  @ViewBuilder
  private func nativeListRows() -> some View {
    if let providerId = node.lazyListProviderId {
      if node.listDeleteEventId == nil {
        if shouldEnableNativeListMove {
          ForEach(lazyListPositions()) { position in
            lazyListRowPosition(
              providerId: providerId,
              position: position
            )
          }
            .onMove { source, destination in
              moveLazyListRows(source: source, destination: destination)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(ocaml_demoHomeBodyBackground)
        } else {
          ForEach(lazyListPositions()) { position in
            lazyListRowPosition(
              providerId: providerId,
              position: position
            )
          }
            .listRowInsets(EdgeInsets())
            .listRowBackground(ocaml_demoHomeBodyBackground)
        }
      } else {
        if shouldEnableNativeListMove {
          ForEach(lazyListPositions()) { position in
            lazyListRowPosition(
              providerId: providerId,
              position: position
            )
          }
            .onDelete { offsets in
              deleteLazyListRows(offsets: offsets)
            }
            .onMove { source, destination in
              moveLazyListRows(source: source, destination: destination)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(ocaml_demoHomeBodyBackground)
        } else {
          ForEach(lazyListPositions()) { position in
            lazyListRowPosition(
              providerId: providerId,
              position: position
            )
          }
            .onDelete { offsets in
              deleteLazyListRows(offsets: offsets)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(ocaml_demoHomeBodyBackground)
        }
      }
    } else {
      if node.listDeleteEventId == nil {
        if shouldEnableNativeListMove {
          nativeStaticListRows()
            .onMove { source, destination in
              moveStaticListRows(source: source, destination: destination)
            }
        } else {
          nativeStaticListRows()
        }
      } else {
        if shouldEnableNativeListMove {
          nativeStaticListRows()
            .onDelete { offsets in
              deleteStaticListRows(offsets: offsets)
            }
            .onMove { source, destination in
              moveStaticListRows(source: source, destination: destination)
            }
        } else {
          nativeStaticListRows()
            .onDelete { offsets in
              deleteStaticListRows(offsets: offsets)
            }
        }
      }
    }
  }

  private var shouldEnableNativeListMove: Bool {
    node.isListEditMode && node.listMoveEventId != nil
  }

  private var shouldUseNativeList: Bool {
    node.listDeleteEventId != nil || shouldEnableNativeListMove || node.listRefreshEventId != nil
  }

  private func nativeStaticListRows() -> some DynamicViewContent {
    ForEach(node.children) { child in
      OCamlDemoNodeView(node: child, model: model)
          .listRowInsets(EdgeInsets())
        .listRowBackground(ocaml_demoHomeBodyBackground)
        .onAppear {
          OCamlDemoListVirtualizationProbe.shared.rowAppeared(
            listID: node.id,
            rowID: child.id,
            totalRows: node.children.count
          )
        }
        .onDisappear {
          OCamlDemoListVirtualizationProbe.shared.rowDisappeared(
            listID: node.id,
            rowID: child.id,
            totalRows: node.children.count
          )
        }
    }
  }

  private func deleteStaticListRows(offsets: IndexSet) {
    guard let index = offsets.first else { return }
    emitListChangeWithoutAnimation(
      name: "native_delete",
      listID: node.id,
      eventId: node.listDeleteEventId,
      text: String(index)
    )
  }

  private func moveStaticListRows(source: IndexSet, destination: Int) {
    guard let fromIndex = source.first else { return }
    emitListChangeWithoutAnimation(
      name: "native_move",
      listID: node.id,
      eventId: node.listMoveEventId,
      text: "\(fromIndex):\(destination)"
    )
  }

  private func deleteLazyListRows(offsets: IndexSet) {
    guard let index = offsets.first else { return }
    let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
      name: "lazy_delete",
      listID: node.id,
      detail: "index=\(index)"
    )
    emitListChangeWithoutAnimation(
      name: "lazy_delete",
      listID: node.id,
      eventId: node.listDeleteEventId,
      text: String(index)
    ) { [listID = node.id] in
      OCamlDemoListVirtualizationProbe.shared.operationFinished(
        name: "lazy_delete",
        listID: listID,
        startedAt: startedAt,
        detail: "index=\(index)"
      )
    }
  }

  private func lazyListRows(providerId: Int32) -> some View {
    ForEach(lazyListPositions()) { position in
      let index = position.index
      lazyListRow(
        providerId: providerId,
        index: index,
        key: position.id,
        refreshGeneration: node.lazyListInvalidatedIndices.contains(index)
          ? node.lazyListVersion
          : 0
      )
    }
  }

  private func lazyListPositions() -> OCamlDemoLazyListPositions {
    OCamlDemoLazyListPositions(
      owner: node,
      endIndex: node.lazyListRowCount
    )
  }

  private func moveLazyListRows(source: IndexSet, destination: Int) {
    guard node.lazyListProviderId != nil else { return }
    guard let fromPosition = source.first else { return }
    guard fromPosition >= 0 && fromPosition < node.lazyListRowCount else { return }
    let toOffset = min(max(0, destination), node.lazyListRowCount)
    OCamlDemoListVirtualizationProbe.shared.debugAlways(
      "lazy_move_native_drop list=\(node.id.uuidString) from_position=\(fromPosition) to_offset=\(toOffset) rows=\(node.lazyListRowCount) version=\(node.lazyListVersion)"
    )
    commitLazyListMove(fromIndex: fromPosition, toOffset: toOffset)
  }

  private func commitLazyListMove(fromIndex: Int, toOffset: Int) {
    let eventId = node.listMoveEventId
    let listID = node.id
    let version = node.lazyListVersion
    let startedAt = OCamlDemoListVirtualizationProbe.shared.operationStarted(
      name: "lazy_move",
      listID: listID,
      detail: "from_index=\(fromIndex) to_offset=\(toOffset)"
    )
    OCamlDemoListVirtualizationProbe.shared.debugAlways(
      "lazy_move_commit_scheduled list=\(listID.uuidString) from_index=\(fromIndex) to_offset=\(toOffset) version=\(version)"
    )
    emitListChangeWithoutAnimation(
      name: "lazy_move",
      listID: listID,
      eventId: eventId,
      text: "\(fromIndex):\(toOffset)"
    ) {
      OCamlDemoListVirtualizationProbe.shared.debugAlways(
        "lazy_move_commit_emit list=\(listID.uuidString) from_index=\(fromIndex) to_offset=\(toOffset)"
      )
      OCamlDemoListVirtualizationProbe.shared.operationFinished(
        name: "lazy_move",
        listID: listID,
        startedAt: startedAt,
        detail: "from_index=\(fromIndex) to_offset=\(toOffset)"
      )
    }
  }

  private func emitListChangeWithoutAnimation(
    name: String,
    listID: UUID,
    eventId: Int32?,
    text: String,
    afterEmit: (() -> Void)? = nil
  ) {
    let startedAt = CACurrentMediaTime()
    OCamlDemoListVirtualizationProbe.shared.debugAlways(
      "\(name)_event_queued list=\(listID.uuidString) text=\(text)"
    )
    let emit = { [model] in
      let delayMs = (CACurrentMediaTime() - startedAt) * 1000
      OCamlDemoListVirtualizationProbe.shared.debugAlways(
        "\(name)_event_emit_begin list=\(listID.uuidString) text=\(text) queue_delay_ms=\(String(format: "%.2f", delayMs))"
      )
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        model.sendChange(eventId, text: text, deferOnMain: false)
      }
      let elapsedMs = (CACurrentMediaTime() - startedAt) * 1000
      OCamlDemoListVirtualizationProbe.shared.debugAlways(
        "\(name)_event_emit_end list=\(listID.uuidString) text=\(text) elapsed_ms=\(String(format: "%.2f", elapsedMs))"
      )
      afterEmit?()
    }
    if Thread.isMainThread {
      emit()
    } else {
      DispatchQueue.main.async(execute: emit)
    }
  }

  private func lazyListRowPosition(
    providerId: Int32,
    position: OCamlDemoLazyListPosition
  ) -> some View {
    let sourceIndex = position.index
    return lazyListRow(
      providerId: providerId,
      index: sourceIndex,
      key: position.id,
      refreshGeneration: node.lazyListInvalidatedIndices.contains(sourceIndex)
        ? node.lazyListVersion
        : 0
    )
  }

  private func lazyListRow(
    providerId: Int32,
    index: Int,
    key: String,
    refreshGeneration: Int
  ) -> some View {
    OCamlDemoLazyListRowView(
      providerId: providerId,
      index: index,
      key: key,
      refreshGeneration: refreshGeneration,
      owner: node,
      listID: node.id,
      model: model
    )
    .equatable()
    .listRowSeparator(.hidden)
    .listRowBackground(ocaml_demoHomeBodyBackground)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func listAppeared(_ proxy: ScrollViewProxy) {
    OCamlDemoListVirtualizationProbe.shared.listUpdated(
      listID: node.id,
      totalRows: node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount,
      reason: "appear"
    )
    scrollFocusedRow(proxy)
    startScrollStress(proxy)
  }

  private func listChildrenCountChanged() {
    OCamlDemoListVirtualizationProbe.shared.listUpdated(
      listID: node.id,
      totalRows: node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount,
      reason: "children_count"
    )
    startScrollStressCurrentRows()
  }

  private func scrollFocusedRow(_ proxy: ScrollViewProxy) {
    guard let index = node.listFocusedRowIndex else { return }
    let targetID: AnyHashable
    if node.lazyListProviderId != nil {
      guard index >= 0 && index < node.lazyListRowCount else { return }
      if node.lazyListVisibleIndices.contains(index) {
        OCamlDemoListVirtualizationProbe.shared.debugAlways(
          "focused_row_scroll_skip_visible list=\(node.id.uuidString) index=\(index) rows=\(node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted())"
        )
        return
      }
      targetID = AnyHashable(ocaml_demoNativePublishedLazyRowKey(owner: node, index: index))
    } else {
      guard node.children.indices.contains(index) else { return }
      targetID = AnyHashable(node.children[index].id)
    }
    OCamlDemoListVirtualizationProbe.shared.debugAlways(
      "focused_row_scroll_queued list=\(node.id.uuidString) index=\(index) lazy=\(node.lazyListProviderId != nil) rows=\(node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted()) target=\(targetID)"
    )
    DispatchQueue.main.async {
      if node.lazyListProviderId != nil && node.lazyListVisibleIndices.contains(index) {
        OCamlDemoListVirtualizationProbe.shared.debugAlways(
          "focused_row_scroll_skip_visible_at_execute list=\(node.id.uuidString) index=\(index) rows=\(node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted())"
        )
        return
      }
      OCamlDemoListVirtualizationProbe.shared.debugAlways(
        "focused_row_scroll_execute list=\(node.id.uuidString) index=\(index) lazy=\(node.lazyListProviderId != nil) visible=\(node.lazyListVisibleIndices.sorted()) target=\(targetID)"
      )
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        proxy.scrollTo(targetID)
      }
    }
  }

  private func blurFocusedRowForUserScroll(_ translation: CGSize) {
    guard abs(translation.height) >= 12 else { return }
    guard abs(translation.height) > abs(translation.width) else { return }
    guard let focusedIndex = node.listFocusedRowIndex else { return }
    guard node.listFocusedRowDisappearEventId != nil else { return }
    guard !node.lazyListVisibleIndices.contains(focusedIndex) else {
      OCamlDemoListVirtualizationProbe.shared.debugAlways(
        "list_scroll_blur_skip_visible_focused_row list=\(node.id.uuidString) focused_index=\(focusedIndex) visible=\(node.lazyListVisibleIndices.sorted())"
      )
      return
    }
    guard listScrollBlurSentForFocusedIndex != focusedIndex else { return }
    listScrollBlurSentForFocusedIndex = focusedIndex
    OCamlDemoListVirtualizationProbe.shared.debugAlways(
      "list_scroll_blur_focused_row list=\(node.id.uuidString) focused_index=\(focusedIndex)"
    )
    model.sendClick(node.listFocusedRowDisappearEventId)
  }

  private func startScrollStress(_ proxy: ScrollViewProxy) {
    startScrollStressCurrentRows(proxy)
  }

  private func startScrollStressCurrentRows(_ proxy: ScrollViewProxy? = nil) {
    if node.pendingLazyListRowCount != nil { return }
    let totalRows = node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount
    OCamlDemoScrollStressProbe.shared.start(
      listID: node.id,
      totalRows: totalRows,
      scrollToIndex: { index in
        guard let proxy else { return }
        if node.lazyListProviderId != nil {
          proxy.scrollTo(ocaml_demoNativePublishedLazyRowKey(owner: node, index: index), anchor: .top)
        } else if node.children.indices.contains(index) {
          proxy.scrollTo(node.children[index].id, anchor: .top)
        }
      }
    )
  }

  private var movableRowsView: some View {
    ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
      OCamlDemoNodeView(node: child, model: model)
    }
    .onMove { source, destination in
      guard let fromIndex = source.first else { return }
      emitListChangeWithoutAnimation(
        name: "movable_rows_move",
        listID: node.id,
        eventId: node.listMoveEventId,
        text: "\(fromIndex):\(destination)"
      )
    }
    .environment(\.editMode, .constant(node.isListEditMode ? .active : .inactive))
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
      Group {
        if let root = node.children.first {
          OCamlDemoNodeView(node: root, model: model)
        } else {
          EmptyView()
        }
      }
      .modifier(OCamlDemoCompactSidebarToolbarModifier(toolbar: compactSidebarToolbar))
      .navigationDestination(for: String.self) { destinationId in
        if let index = node.navigationDestinationIds.firstIndex(of: destinationId),
           node.children.indices.contains(index + 1) {
          OCamlDemoNodeView(node: node.children[index + 1], model: model)
            .ocaml_demoNavigationChrome()
        } else {
          EmptyView()
            .ocaml_demoNavigationChrome()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
      .ocaml_demoBottomBarChrome()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(ocaml_demoHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
    .ocaml_demoBottomBarChrome()
  }

  @ViewBuilder
  private func navigationLinkLabel(suppressRowActions: Bool) -> some View {
    if node.children.indices.contains(0) {
      OCamlDemoNodeView(
        node: node.children[0],
        model: model,
        suppressListRowActions: suppressRowActions
      )
    } else {
      EmptyView()
    }
  }

  private var section: some View {
    Section {
      childViews
    } header: {
      if !node.sectionTitle.isEmpty {
        Text(node.sectionTitle)
      }
    }
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

  @ViewBuilder
  private var picker: some View {
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
  }

  private var slider: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(node.text)
        Spacer()
        Text(node.sliderValue, format: .number.precision(.fractionLength(2)))
          .foregroundStyle(.secondary)
      }
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
        ocaml_demoDatePickerDebugLogger.notice(
          "datePicker setter node=\(node.id.uuidString, privacy: .public) old=\(node.selectedDateText, privacy: .public) selected=\(selected, privacy: .public) event=\(String(describing: node.changeEventId), privacy: .public)"
        )
        node.selectedDateText = selected
        model.sendChange(node.changeEventId, text: selected)
      }
    )
  }

  private var datePicker: some View {
    DatePicker(node.text, selection: datePickerDate, displayedComponents: .date)
      .datePickerStyle(.graphical)
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

  private func textFont(_ style: Int32, weight: Int32) -> Font {
    let weight = textWeight(weight)
    switch style {
    case 0: return ocaml_demoNativePreferredFont(.largeTitle, weight: weight)
    case 1: return ocaml_demoNativePreferredFont(.title, weight: weight)
    case 2: return ocaml_demoNativePreferredFont(.title2, weight: weight)
    case 3: return ocaml_demoNativePreferredFont(.title3, weight: weight)
    case 4: return ocaml_demoNativePreferredFont(.headline, weight: weight)
    case 6: return ocaml_demoNativePreferredFont(.callout, weight: weight)
    case 7: return ocaml_demoNativePreferredFont(.subheadline, weight: weight)
    case 8: return ocaml_demoNativePreferredFont(.footnote, weight: weight)
    case 9: return ocaml_demoNativePreferredFont(.caption, weight: weight)
    case 10: return ocaml_demoNativePreferredFont(.caption2, weight: weight)
    default: return ocaml_demoNativePreferredFont(.body, weight: weight)
    }
  }

  private func textWeight(_ weight: Int32) -> Font.Weight {
    switch weight {
    case 1: return .medium
    case 2: return .semibold
    case 3: return .bold
    default: return .regular
    }
  }

  private func textColor(_ color: Int32) -> Color {
    ocaml_demoNativeSemanticColor(color) ?? .primary
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

  private var selectedRouteIndex: Int? {
    node.tabs.firstIndex { tab in
      tab.id == node.selectedTabId
    }
  }

  private var selectedRouteTitle: String {
    node.tabs.first { tab in
      tab.id == node.selectedTabId
    }?.title ?? node.tabs.first?.title ?? sidebarTitle
  }

  @ViewBuilder
  private var selectedRouteDetail: some View {
    selectedRouteDetail(suppressNativeToolbar: false)
  }

  @ViewBuilder
  private func selectedRouteDetail(suppressNativeToolbar: Bool) -> some View {
    if let selectedRouteIndex, selectedRouteIndex < node.children.count {
      OCamlDemoNodeView(
        node: node.children[selectedRouteIndex],
        model: model,
        suppressNativeToolbar: suppressNativeToolbar
      )
    } else if let firstChild = node.children.first {
      OCamlDemoNodeView(
        node: firstChild,
        model: model,
        suppressNativeToolbar: suppressNativeToolbar
      )
    } else {
      EmptyView()
    }
  }

  @ViewBuilder
  private var sidebarSplitView: some View {
    if horizontalSizeClass == .compact {
      compactSidebarSplitView
    } else {
      regularSidebarSplitView
    }
  }

  private var regularSidebarSplitView: some View {
    NavigationSplitView {
      List {
        sidebarRouteButtons
      }
      .navigationTitle(sidebarTitle)
    } detail: {
      selectedRouteDetail
    }
  }

  private var compactSidebarSplitView: some View {
    OCamlDemoCompactSidebarSplitView(
      node: node,
      model: model,
      sidebarTitle: sidebarTitle
    )
  }

  @ViewBuilder
  private func toolbarActionLabel(_ item: OCamlDemoToolbarItem) -> some View {
    if let systemImage = item.systemImage {
      if item.isTitleVisible {
        Label(item.title, systemImage: systemImage)
      } else {
        Image(systemName: systemImage)
          .accessibilityLabel(item.title)
      }
    } else {
      Text(item.title)
    }
  }

  @ViewBuilder
  private func toolbarMenuLabel(_ item: OCamlDemoToolbarItem) -> some View {
    if let systemImage = item.systemImage {
      if item.isTitleVisible {
        Label(item.title, systemImage: systemImage)
      } else {
        Image(systemName: systemImage)
          .accessibilityLabel(item.title)
      }
    } else {
      Text(item.title)
    }
  }

  @ViewBuilder
  private func toolbarMenuActionButton(_ action: OCamlDemoRowAction) -> some View {
    if action.startsSection {
      Divider()
    }
    Button(role: action.style == 1 ? .destructive : nil) {
      handleToolbarMenuAction(action)
    } label: {
      if let systemImage = action.systemImage {
        Label(action.title, systemImage: systemImage)
      } else {
        Text(action.title)
      }
    }
  }

  private var toolbarExportUTType: UTType {
    UTType(toolbarExportContentType) ?? .plainText
  }

  private func handleToolbarMenuAction(_ action: OCamlDemoRowAction) {
    if let filename = action.exportFilename,
       let contentType = action.exportContentType,
       let content = action.exportContent {
      toolbarExportFilename = filename
      toolbarExportContentType = contentType
      toolbarExportContent = content
      isToolbarExportPresented = true
    }
    model.sendClick(action.eventId)
  }

  @ViewBuilder
  private var sidebarRouteButtons: some View {
    if node.sidebarActions.isEmpty && node.sidebarHistoryActions.isEmpty {
      ForEach(node.tabs) { tab in
        Button {
          selectCompactSidebarTab(tab)
        } label: {
          sidebarRowLabel(
            title: tab.title,
            systemImage: tab.systemImage,
            isSelected: tab.id == node.selectedTabId
          )
        }
        .buttonStyle(.plain)
      }
    } else {
      ForEach(node.sidebarActions) { action in
        sidebarActionButton(action, isSelected: action.id == node.selectedTabId)
      }

      if !node.sidebarHistoryActions.isEmpty, let historyTitle = node.sidebarHistoryTitle {
        Text(historyTitle)
          .font(ocaml_demoNativePreferredFont(size: 18, weight: .semibold, relativeTo: .headline))
          .foregroundStyle(.primary)
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 14)
      }

      ForEach(node.sidebarHistoryActions) { action in
        sidebarActionButton(action, isSelected: false, usesContextMenu: true)
      }
    }
  }

  private func selectCompactSidebarTab(_ tab: OCamlDemoTab) {
    ocaml_demoDismissKeyboard()
    node.selectedTabId = tab.id
    model.sendChange(node.tabSelectEventId, text: tab.id)
  }

  @ViewBuilder
  private func sidebarActionButton(
    _ action: OCamlDemoSidebarAction,
    isSelected: Bool,
    usesContextMenu: Bool = false
  ) -> some View {
    if action.menuActions.isEmpty {
      Button {
        performSidebarAction(action)
      } label: {
        sidebarRowLabel(
          title: action.title,
          subtitle: action.subtitle,
          systemImage: action.systemImage,
          isSelected: isSelected
        )
      }
      .buttonStyle(.plain)
    } else {
      if usesContextMenu {
        Button {
          performSidebarAction(action)
        } label: {
          sidebarRowLabel(
            title: action.title,
            subtitle: action.subtitle,
            systemImage: action.systemImage,
            isSelected: isSelected
          )
        }
        .buttonStyle(.plain)
        .contextMenu {
          sidebarActionMenuItems(action)
        }
      } else {
        Menu {
          sidebarActionMenuItems(action)
        } label: {
          sidebarRowLabel(
            title: action.title,
            subtitle: action.subtitle,
            systemImage: action.systemImage,
            isSelected: isSelected
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func performSidebarAction(_ action: OCamlDemoSidebarAction) {
    let selectedTab = sidebarActionSelectedTab(action)
    if let selectedTab {
      selectSidebarActionRoute(selectedTab, closesSidebar: action.closesSidebar)
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

  private func selectSidebarActionRoute(_ selectedTab: String, closesSidebar: Bool) {
    _ = closesSidebar
    ocaml_demoDismissKeyboard()
    node.selectedTabId = selectedTab
  }

  @ViewBuilder
  private func sidebarActionMenuItems(_ action: OCamlDemoSidebarAction) -> some View {
    ForEach(action.menuActions) { menuAction in
      Button(role: menuAction.style == 1 ? .destructive : nil) {
        if let eventId = menuAction.eventId {
          model.sendClick(eventId)
        }
      } label: {
        if let systemImage = menuAction.systemImage {
          Label(menuAction.title, systemImage: systemImage)
        } else {
          Text(menuAction.title)
        }
      }
    }
  }

  private func sidebarRowLabel(title: String, subtitle: String? = nil, systemImage: String?, isSelected: Bool) -> some View {
    HStack(spacing: 12) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 24)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(
            ocaml_demoNativePreferredFont(
              size: subtitle == nil ? 16 : 17,
              weight: subtitle == nil ? .semibold : .regular,
              relativeTo: subtitle == nil ? .callout : .body
            )
          )
          .foregroundStyle(.primary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(ocaml_demoNativePreferredFont(.caption))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: subtitle == nil ? 52 : nil)
      .padding(.vertical, subtitle == nil ? 0 : 8)
      .padding(.horizontal, 12)
      .background(
        isSelected
          ? Color.primary.opacity(0.06)
          : Color.clear,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var sidebarHeaderActionButton: some View {
    if let action = node.sidebarHeaderAction {
      if action.avatarImage != nil || action.avatarInitial != nil {
        Button {
          clickSidebarHeaderAction(action)
        } label: {
          sidebarHeaderAvatar(action)
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .accessibilityLabel(action.title)
      } else {
        Button {
          clickSidebarHeaderAction(action)
        } label: {
          Image(systemName: action.systemImage ?? "person.crop.circle")
            .font(.headline.weight(.semibold))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .ocaml_demoLiquidGlassPanel(cornerRadius: 22, isInteractive: true, isTransparent: true)
        .accessibilityLabel(action.title)
      }
    } else {
      Button {} label: {
        Image(systemName: "xmark")
          .font(.headline.weight(.semibold))
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.plain)
    }
  }

  private func clickSidebarHeaderAction(_ action: OCamlDemoSidebarAction) {
    performSidebarAction(action)
  }

  @ViewBuilder
  private func sidebarHeaderAvatar(_ action: OCamlDemoSidebarAction) -> some View {
    if let avatarImage = action.avatarImage,
       let url = URL(string: avatarImage),
       url.scheme == "http" || url.scheme == "https" {
      AsyncImage(url: url) { phase in
        switch phase {
        case let .success(image):
          image
            .resizable()
            .scaledToFill()
        default:
          sidebarHeaderAvatarFallback(action)
        }
      }
    } else {
      sidebarHeaderAvatarFallback(action)
    }
  }

  private func sidebarHeaderAvatarFallback(_ action: OCamlDemoSidebarAction) -> some View {
    Circle()
      .fill(Color.pink.opacity(0.9))
      .overlay {
        Text(action.avatarInitial ?? "?")
          .font(ocaml_demoNativePreferredFont(size: 14, weight: .semibold, relativeTo: .caption))
          .foregroundStyle(.white)
      }
  }

  @ViewBuilder
  private var sidebarBottomControls: some View {
    if node.sidebarBottomSearchPlaceholder != nil || node.sidebarBottomAction != nil {
      HStack(spacing: 12) {
        if let placeholder = node.sidebarBottomSearchPlaceholder {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .font(.body.weight(.medium))
              .foregroundStyle(.secondary)
            TextField(
              placeholder,
              text: Binding(
                get: { node.sidebarBottomSearchText },
                set: { value in
                  node.sidebarBottomSearchText = value
                  model.sendChange(node.sidebarBottomSearchEventId, text: value)
                }
              )
            )
              .textFieldStyle(.plain)
          }
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .ocaml_demoLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
        }

        if let action = node.sidebarBottomAction {
          sidebarBottomActionButton(action)
        }
      }
    }
  }

  @ViewBuilder
  private func sidebarBottomActionButton(_ action: OCamlDemoSidebarAction) -> some View {
    Button {
      performSidebarAction(action)
    } label: {
      if action.chrome == 2 {
        Image(systemName: action.systemImage ?? "xmark")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 52, height: 52)
          .contentShape(Circle())
      } else {
        Label(action.title, systemImage: action.systemImage ?? "square.and.pencil")
          .font(ocaml_demoNativePreferredFont(size: 18, weight: .semibold, relativeTo: .headline))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(.white)
          .padding(.horizontal, 24)
          .frame(height: 58)
          .contentShape(Capsule())
      }
    }
    .buttonStyle(.plain)
    .modifier(SidebarBottomActionChrome(chrome: action.chrome))
    .accessibilityLabel(action.title)
  }

  private var sidebarTitle: String {
    node.sidebarTitle
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "Menu"
  }

  @ViewBuilder
  private var navigationSplitView: some View {
    NavigationSplitView {
      if node.children.indices.contains(0) {
        OCamlDemoNodeView(node: node.children[0], model: model)
      } else {
        EmptyView()
      }
    } content: {
      if node.children.indices.contains(1) {
        OCamlDemoNodeView(node: node.children[1], model: model)
      } else {
        EmptyView()
      }
    } detail: {
      if node.children.indices.contains(2) {
        OCamlDemoNodeView(node: node.children[2], model: model)
      } else {
        EmptyView()
      }
    }
  }

  @ViewBuilder
  private var adaptiveLayoutView: some View {
    let index = horizontalSizeClass == .compact ? 0 : 1
    if node.children.indices.contains(index) {
      OCamlDemoNodeView(node: node.children[index], model: model)
    } else {
      EmptyView()
    }
  }

  @ViewBuilder
  private var tabView: some View {
    if #available(iOS 18.0, *) {
      modernTabView
    } else {
      legacyTabView
    }
  }

  @ViewBuilder
  @available(iOS 18.0, *)
  private var modernTabView: some View {
    let content = TabView(selection: tabSelection) {
      ForEach(Array(node.tabs.enumerated()), id: \.element.id) { index, tab in
        if index < node.children.count {
          let systemImage = tab.systemImage ?? "circle"
          if tab.role == 1 {
            Tab(value: tab.id, role: .search) {
              searchTabContent(index: index)
            } label: {
              Label(tab.title, systemImage: systemImage)
            }
          } else {
            Tab(
              tab.title,
              systemImage: systemImage,
              value: tab.id,
              role: nil
            ) {
              OCamlDemoNodeView(node: node.children[index], model: model)
            }
          }
        }
      }
    }

    if #available(iOS 26.0, *), node.tabs.contains(where: { $0.role == 1 }) {
      content.tabViewSearchActivation(.searchTabSelection)
    } else {
      content
    }
  }

  @ViewBuilder
  @available(iOS 18.0, *)
  private func searchTabContent(index: Int) -> some View {
    if #available(iOS 26.0, *) {
      NavigationStack {
        OCamlDemoNodeView(node: node.children[index], model: model)
      }
      .tabViewSearchActivation(.searchTabSelection)
    } else {
      OCamlDemoNodeView(node: node.children[index], model: model)
    }
  }

  private var legacyTabView: some View {
    TabView(selection: tabSelection) {
      ForEach(Array(node.tabs.enumerated()), id: \.element.id) { index, tab in
        if index < node.children.count {
          OCamlDemoNodeView(node: node.children[index], model: model)
            .tabItem {
              if let systemImage = tab.systemImage {
                Image(systemName: systemImage)
              }
              Text(tab.title)
            }
            .tag(tab.id)
        }
      }
    }
  }

  private func applyModifiers<Content: View>(to content: Content) -> some View {
    let content = content
      .modifier(OCamlDemoNodeModifiers(node: node, model: model))
    return content
      .toolbar {
        if !suppressNativeToolbar {
          nativeToolbarItems
        }
      }
      .ocaml_demoBottomBarChrome()
  }

  @ToolbarContentBuilder
  private var nativeToolbarItems: some ToolbarContent {
    if !node.toolbarItems.isEmpty {
      ToolbarItemGroup(placement: .automatic) {
        ForEach(node.toolbarItems) { item in
          toolbarItemView(item)
        }
      }
    }
    if node.toolbarContents.indices.contains(0) {
      nativeToolbarContent(node.toolbarContents[0])
    }
    if node.toolbarContents.indices.contains(1) {
      nativeToolbarContent(node.toolbarContents[1])
    }
    if node.toolbarContents.indices.contains(2) {
      nativeToolbarContent(node.toolbarContents[2])
    }
    if node.toolbarContents.indices.contains(3) {
      nativeToolbarContent(node.toolbarContents[3])
    }
    if node.toolbarContents.indices.contains(4) {
      nativeToolbarContent(node.toolbarContents[4])
    }
    if node.toolbarContents.indices.contains(5) {
      nativeToolbarContent(node.toolbarContents[5])
    }
    if node.toolbarContents.indices.contains(6) {
      nativeToolbarContent(node.toolbarContents[6])
    }
    if node.toolbarContents.indices.contains(7) {
      nativeToolbarContent(node.toolbarContents[7])
    }
  }

  @ToolbarContentBuilder
  private func nativeToolbarContent(_ content: OCamlDemoToolbarContent) -> some ToolbarContent {
    switch content.kind {
    case .group:
      ToolbarItemGroup(placement: content.placement.swiftUIPlacement) {
        ForEach(content.items) { item in
          toolbarItemView(item)
        }
      }
    case .spacer:
      if #available(iOS 26.0, *) {
        if content.fixed {
          ToolbarSpacer(.fixed, placement: content.placement.swiftUIPlacement)
        } else {
          ToolbarSpacer(placement: content.placement.swiftUIPlacement)
        }
      }
    }
  }

  @ViewBuilder
  private func toolbarItemView(_ item: OCamlDemoToolbarItem) -> some View {
    if let shareURL = item.shareURL, let url = URL(string: shareURL) {
      ShareLink(item: url) {
        toolbarActionLabel(item)
      }
      .disabled(!item.isEnabled)
    } else if item.menuActions.isEmpty {
      Button {
        if let eventId = item.eventId {
          model.sendClick(eventId)
        }
      } label: {
        toolbarActionLabel(item)
      }
      .disabled(!item.isEnabled)
    } else {
      Menu {
        ForEach(item.menuActions) { action in
          toolbarMenuActionButton(action)
        }
      } label: {
        toolbarMenuLabel(item)
      }
      .disabled(!item.isEnabled)
    }
  }
}

private struct OCamlDemoListRowView: View {
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  var suppressRowActions = false

  var body: some View {
    if suppressRowActions {
      rowContent
    } else {
      rowContent
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          rowSwipeButtons
        }
      }
  }

  @ViewBuilder
  private var rowContent: some View {
    if node.rowMenuActions.isEmpty {
      if node.clickEventId == nil {
        rowBody
      } else {
        rowBody
          .contentShape(.rect)
          .onTapGesture {
            model.sendClick(node.clickEventId)
          }
      }
    } else {
      Menu {
        rowMenuButtons
      } label: {
        rowBody
      }
      .buttonStyle(.plain)
    }
  }

  private var rowBody: some View {
    HStack(spacing: 14) {
      if let leadingImage = node.rowLeadingSystemImage {
        Button {
          withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
            model.sendClick(node.rowLeadingEventId)
          }
        } label: {
          Image(
            systemName: node.rowLeadingSelected
              ? (node.rowLeadingSelectedSystemImage ?? leadingImage)
              : leadingImage
          )
          .font(.system(size: 25, weight: .regular))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(
            node.rowLeadingSelected
              ? Color.green
              : Color.secondary.opacity(0.35)
          )
          .frame(width: 32, height: 32)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.rowLeadingAccessibilityLabel)
      } else if let leadingImage = node.rowStaticLeadingSystemImage {
        Image(systemName: leadingImage)
          .font(.system(size: 21, weight: .regular))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(Color.accentColor)
          .frame(width: 32, height: 32)
      }

      rowMainContent
    }
    .padding(.vertical, node.rowContentStyle == 2 ? 4 : 0)
  }

  @ViewBuilder
  private var rowSwipeButtons: some View {
    ForEach(node.rowActions) { action in
      Button(role: action.style == 1 ? .destructive : nil) {
        let eventId = action.eventId
        DispatchQueue.main.async {
          model.sendClick(eventId)
        }
      } label: {
        if let systemImage = action.systemImage {
          Label(action.title, systemImage: systemImage)
        } else {
          Text(action.title)
        }
      }
      .tint(action.style == 1 ? .red : .blue)
    }
  }

  @ViewBuilder
  private var rowMenuButtons: some View {
    ForEach(node.rowMenuActions) { action in
      Button(role: action.style == 1 ? .destructive : nil) {
        model.sendClick(action.eventId)
      } label: {
        if let systemImage = action.systemImage {
          Label(action.title, systemImage: systemImage)
        } else {
          Text(action.title)
        }
      }
    }
  }

  private var rowMainContent: some View {
    Group {
      if node.rowContentStyle == 1 {
        summaryRowMainContent
      } else if node.rowContentStyle == 2 {
        detailRowMainContent
      } else {
        standardRowMainContent
      }
    }
  }

  private var summaryRowMainContent: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(node.text)
          .font(ocaml_demoNativePreferredFont(.headline))
          .foregroundStyle(node.rowTitleStrikethrough ? .secondary : .primary)
          .strikethrough(node.rowTitleStrikethrough, color: .secondary)
        if !node.rowSubtitle.isEmpty {
          Text(node.rowSubtitle)
            .font(ocaml_demoNativePreferredFont(.caption))
            .foregroundStyle(.secondary)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 12)

      rowAccessoryView
    }
  }

  private var detailRowMainContent: some View {
    VStack(alignment: .leading, spacing: 6) {
      rowPreviewImage(maxHeight: 160)
      Text(node.text)
        .font(ocaml_demoNativePreferredFont(.headline))
        .foregroundStyle(node.rowTitleStrikethrough ? .secondary : .primary)
        .strikethrough(node.rowTitleStrikethrough, color: .secondary)
      if !node.rowSubtitle.isEmpty {
        Text(node.rowSubtitle)
          .font(ocaml_demoNativePreferredFont(.caption))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func rowPreviewImage(maxHeight: CGFloat) -> some View {
    if let path = node.rowPreviewImagePath,
       !path.hasPrefix("r2://"),
       FileManager.default.fileExists(atPath: path),
       let image = UIImage(contentsOfFile: path) {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
    }
  }

  private var standardRowMainContent: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text(node.text)
          .font(ocaml_demoNativePreferredFont(.subheadline))
          .foregroundStyle(node.rowTitleStrikethrough ? .secondary : .primary)
          .strikethrough(node.rowTitleStrikethrough, color: .secondary)
          .lineLimit(1)
        if !node.rowSubtitle.isEmpty {
          Text(node.rowSubtitle)
            .font(ocaml_demoNativePreferredFont(.subheadline))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 12)

      if !node.rowTrailingText.isEmpty {
        Text(node.rowTrailingText)
          .font(ocaml_demoNativePreferredFont(.caption))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .layoutPriority(2)
      }

      rowAccessoryView
    }
  }

  @ViewBuilder
  private var rowAccessoryView: some View {
    if node.rowAccessory == 1 {
      Image(systemName: "chevron.right")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
  }
}

private struct OCamlDemoPhotoPickerView: View {
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  @State private var selectedItem: PhotosPickerItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      PhotosPicker(selection: $selectedItem, matching: .images) {
        if node.isTitleVisible {
          Label(node.text, systemImage: node.systemImage ?? "photo")
        } else {
          Image(systemName: node.systemImage ?? "photo")
            .accessibilityLabel(node.text)
        }
      }
      if let selected = node.placeholder, !selected.isEmpty {
        Label("Image attached", systemImage: "checkmark.circle.fill")
          .font(ocaml_demoNativePreferredFont(.caption))
          .foregroundStyle(.secondary)
      }
    }
    .onChange(of: selectedItem) { _, item in
      guard let item else { return }
      if node.wantsImagePayload {
        Task {
          guard let data = try? await item.loadTransferable(type: Data.self) else { return }
          let preferredType = item.supportedContentTypes.first
          let recognizedText = await recognizeText(in: data)
          guard
            let payload = try? saveImagePayload(
              data: data,
              mimeType: mimeType(for: preferredType),
              idPrefix: "image",
              recognizedText: recognizedText
            )
          else { return }
          await MainActor.run {
            node.placeholder = payload.id
            model.sendChange(node.changeEventId, text: payload.eventText)
          }
        }
      } else {
        let imageId = item.itemIdentifier ?? UUID().uuidString
        node.placeholder = imageId
        model.sendChange(node.changeEventId, text: imageId)
      }
    }
  }
}

private struct OCamlDemoFileExporterView: View {
  @ObservedObject var node: OCamlDemoNode

  var body: some View {
    if let url = exportURL {
      ShareLink(item: url) {
        Label(node.text, systemImage: "square.and.arrow.up")
      }
    } else {
      Label(node.text, systemImage: "square.and.arrow.up")
        .foregroundStyle(.secondary)
    }
  }

  private var exportURL: URL? {
    guard !node.exportFilename.isEmpty else { return nil }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OCamlDemoExports", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let url = directory.appendingPathComponent(node.exportFilename)
      try Data(node.exportContent.utf8).write(to: url, options: [.atomic])
      return url
    } catch {
      return nil
    }
  }
}

private struct OCamlDemoFileImporterView: View {
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Label(node.text, systemImage: "square.and.arrow.down")
    }
    .fileImporter(
      isPresented: $isPresented,
      allowedContentTypes: contentTypes,
      allowsMultipleSelection: false
    ) { result in
      guard
        let url = try? result.get().first,
        let content = readText(from: url)
      else { return }
      model.sendChange(node.changeEventId, text: content)
    }
  }

  private var contentTypes: [UTType] {
    let types = node.allowedContentTypes.compactMap { identifier in
      UTType(identifier) ?? UTType(filenameExtension: identifier)
    }
    return types.isEmpty ? [.data] : types
  }

  private func readText(from url: URL) -> String? {
    let shouldStopAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if shouldStopAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(data: data, encoding: .utf8) ?? ""
  }
}

private struct OCamlDemoCameraCaptureView: View {
  @ObservedObject var node: OCamlDemoNode
  let model: OCamlDemoHostModel
  @State private var isPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        isPresented = true
      } label: {
        Label(node.text, systemImage: "camera")
      }
      .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

      if let captured = node.placeholder, !captured.isEmpty {
        Label("Image attached", systemImage: "checkmark.circle.fill")
          .font(ocaml_demoNativePreferredFont(.caption))
          .foregroundStyle(.secondary)
      }
    }
    .sheet(isPresented: $isPresented) {
      OCamlDemoCameraPicker { image in
        if node.wantsImagePayload, let data = image.jpegData(compressionQuality: 0.92) {
          Task {
            let recognizedText = await recognizeText(in: data)
            if let payload = try? saveImagePayload(
              data: data,
              mimeType: "image/jpeg",
              idPrefix: "image",
              recognizedText: recognizedText
            ) {
              await MainActor.run {
                node.placeholder = payload.id
                model.sendChange(node.changeEventId, text: payload.eventText)
              }
            }
          }
        } else {
          let imageId = "camera://" + UUID().uuidString
          node.placeholder = imageId
          model.sendChange(node.changeEventId, text: imageId)
        }
        isPresented = false
      } onCancel: {
        isPresented = false
      }
    }
  }
}

private struct OCamlDemoCameraPicker: UIViewControllerRepresentable {
  let onCapture: (UIImage) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture, onCancel: onCancel)
  }

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
      self.onCapture = onCapture
      self.onCancel = onCancel
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      guard let image = info[.originalImage] as? UIImage else {
        onCancel()
        return
      }
      onCapture(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
    }
  }
}

private final class OCamlDemoLazyListRowState {
  var isVisible = false
  var visibleIndex: Int?
  var visibleKey: String?
  var focusedDisappearToken: UUID?
  var refreshToken = 0
}

private struct OCamlDemoLazyListRowView: View, Equatable {
  let providerId: Int32
  let index: Int
  let key: String
  let refreshGeneration: Int
  let owner: OCamlDemoNode
  let listID: UUID
  let model: OCamlDemoHostModel
  @State private var loadGeneration = 0
  @State private var renderedChild: OCamlDemoNode?
  @State private var renderedChildKey: String?
  @State private var renderedChildRefreshGeneration = 0
  @State private var rowState = OCamlDemoLazyListRowState()

  static func == (lhs: OCamlDemoLazyListRowView, rhs: OCamlDemoLazyListRowView) -> Bool {
    lhs.providerId == rhs.providerId
      && lhs.index == rhs.index
      && lhs.key == rhs.key
      && lhs.refreshGeneration == rhs.refreshGeneration
      && lhs.owner === rhs.owner
      && lhs.listID == rhs.listID
      && lhs.model === rhs.model
  }

  var body: some View {
    let _ = loadGeneration
    let _ = OCamlDemoBodyProbe.shared.mark("lazy_row_body")
    let _ = OCamlDemoFrameProbe.shared.markLazyRowBody()
    let _ = OCamlDemoListVirtualizationProbe.shared.rowBodyEvaluated(listID: listID)
    Group {
      if let child = displayedChild {
        OCamlDemoNodeView(node: child, model: model)
      } else {
        Color.clear
          .frame(height: 44)
      }
    }
    .background {
      ocaml_demoNativeLifecycleProbeBackground {
        OCamlDemoRowLifecycleProbeView(listID: listID)
      }
    }
    .onAppear {
      OCamlDemoFrameProbe.shared.markLazyRowAppear()
      rowState.isVisible = true
      rowState.focusedDisappearToken = nil
      trackVisibleIndexAppear()
      loadRowIfNeeded()
      if let child = displayedChild {
        markRowAppeared(child)
      }
      reportListPerf()
    }
    .onChange(of: refreshGeneration) { _, generation in
      if generation != 0 {
        scheduleRefreshRow()
      }
    }
    .onChange(of: key) { _, _ in
      if rowState.isVisible {
        trackVisibleIndexAppear()
      }
      DispatchQueue.main.async {
        setRenderedChild(cachedRenderedChild)
        loadRowIfNeeded()
      }
    }
    .onChange(of: index) { _, _ in
      if rowState.isVisible {
        trackVisibleIndexAppear()
      }
    }
    .onDisappear {
      OCamlDemoFrameProbe.shared.markLazyRowDisappear()
      rowState.isVisible = false
      trackVisibleIndexDisappear()
      if let child = cachedRenderedChild {
        OCamlDemoListVirtualizationProbe.shared.rowDisappearedAtIndex(
          listID: listID,
          rowID: child.id,
          index: index,
          totalRows: owner.lazyListRowCount
        )
      }
      scheduleFocusedRowDisappear()
      reportListPerf()
    }
  }

  private var cachedRenderedChild: OCamlDemoNode? {
    if let rendered = owner.lazyListRowsByIndex[index],
       let renderedKey = owner.lazyListRowKeyByIndex[index],
       renderedKey == key {
      return rendered
    }
    if let rendered = owner.lazyListRowsByKey[key] {
      return rendered
    }
    return nil
  }

  private var displayedChild: OCamlDemoNode? {
    guard renderedChildKey == key else { return cachedRenderedChild }
    guard renderedChildRefreshGeneration == refreshGeneration else {
      return cachedRenderedChild
    }
    return renderedChild ?? cachedRenderedChild
  }

  private func setRenderedChild(_ child: OCamlDemoNode?) {
    let nextRenderedChildKey = child == nil ? nil : key
    if renderedChild === child
      && renderedChildKey == nextRenderedChildKey
      && renderedChildRefreshGeneration == refreshGeneration {
      return
    }
    renderedChild = child
    renderedChildKey = nextRenderedChildKey
    renderedChildRefreshGeneration = refreshGeneration
  }

  private func trackVisibleIndexAppear() {
    if rowState.visibleIndex == index && rowState.visibleKey == key {
      return
    }
    if rowState.visibleIndex != nil || rowState.visibleKey != nil {
      trackVisibleIndexDisappear()
    }
    owner.lazyListVisibleIndexCounts[index, default: 0] += 1
    owner.lazyListVisibleIndices.insert(index)
    rowState.visibleIndex = index
    rowState.visibleKey = key
  }

  private func trackVisibleIndexDisappear() {
    guard let visibleIndex = rowState.visibleIndex else { return }
    let nextCount = (owner.lazyListVisibleIndexCounts[visibleIndex] ?? 0) - 1
    if nextCount > 0 {
      owner.lazyListVisibleIndexCounts[visibleIndex] = nextCount
    } else {
      owner.lazyListVisibleIndexCounts[visibleIndex] = nil
      owner.lazyListVisibleIndices.remove(visibleIndex)
    }
    rowState.visibleIndex = nil
    rowState.visibleKey = nil
  }

  private func renderRowIfNeeded() -> OCamlDemoNode? {
    if let cached = cachedRenderedChild {
      touchRetainedIndex(index)
      OCamlDemoListVirtualizationProbe.shared.rowCacheHit(listID: listID)
      return cached
    }
    let resolvedKey = ocaml_demoNativeLazyRowKey(
      owner: owner,
      providerId: providerId,
      index: index
    )
    guard let renderCallback = ocaml_demoNativeLazyRowRenderCallback else {
      OCamlDemoListVirtualizationProbe.shared.debug(
        "lazy_row_render_missing_callback provider=\(providerId) index=\(index)"
      )
      return nil
    }
    let renderStartedAt = CACurrentMediaTime()
    guard let pointer = renderCallback(providerId, Int32(index)) else {
      OCamlDemoListVirtualizationProbe.shared.debug(
        "lazy_row_render_nil_pointer provider=\(providerId) index=\(index)"
      )
      return nil
    }
    let renderElapsedMs = (CACurrentMediaTime() - renderStartedAt) * 1000
    OCamlDemoFrameProbe.shared.markLazyRowRender(
      listID: listID,
      index: index,
      key: resolvedKey,
      elapsedMs: renderElapsedMs,
      totalRows: owner.lazyListRowCount
    )
    guard let rendered = nativeNode(from: pointer) else {
      OCamlDemoListVirtualizationProbe.shared.debug(
        "lazy_row_render_missing_node provider=\(providerId) index=\(index)"
      )
      return nil
    }
    bindHostModel(owner.hostModel, to: rendered)
    owner.lazyListRowsByIndex[index] = rendered
    owner.lazyListRowKeyByIndex[index] = resolvedKey
    owner.lazyListRowsByKey[resolvedKey] = rendered
    touchRetainedIndex(index)
    OCamlDemoListVirtualizationProbe.shared.rowRendered(
      listID: listID,
      elapsedMs: renderElapsedMs
    )
    OCamlDemoListVirtualizationProbe.shared.rowRetained(listID: listID, rowID: rendered.id)
    trimRetainedRows()
    reportListPerf()
    return rendered
  }

  private func loadRowIfNeeded() {
    if let cached = cachedRenderedChild {
      setRenderedChild(cached)
      return
    }
    DispatchQueue.main.async {
      guard rowState.isVisible else { return }
      guard displayedChild == nil else { return }
      if let child = renderRowIfNeeded() {
        setRenderedChild(child)
        markRowAppeared(child)
      }
    }
  }

  private func markRowAppeared(_ child: OCamlDemoNode) {
    OCamlDemoListVirtualizationProbe.shared.rowAppearedAtIndex(
      listID: listID,
      rowID: child.id,
      index: index,
      totalRows: owner.lazyListRowCount
    )
  }

  private func refreshRow() {
    guard rowState.isVisible else { return }
    guard let rendered = cachedRenderedChild else {
      setRenderedChild(nil)
      return
    }
    setRenderedChild(rendered)
    touchRetainedIndex(index)
    loadGeneration &+= 1
    OCamlDemoListVirtualizationProbe.shared.rowRefreshed(
      listID: listID,
      elapsedMs: 0
    )
    reportListPerf()
  }

  private func scheduleRefreshRow() {
    rowState.refreshToken &+= 1
    let token = rowState.refreshToken
    let rowState = rowState
    DispatchQueue.main.async {
      guard rowState.refreshToken == token else { return }
      refreshRow()
    }
  }

  private func scheduleFocusedRowDisappear() {
    guard owner.listFocusedRowIndex == index else { return }
    guard owner.listFocusedRowDisappearEventId != nil else { return }
    let token = UUID()
    rowState.focusedDisappearToken = token
    let rowState = rowState
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      guard rowState.focusedDisappearToken == token else { return }
      guard !rowState.isVisible else { return }
      guard !owner.lazyListVisibleIndices.contains(index) else {
        rowState.focusedDisappearToken = nil
        OCamlDemoListVirtualizationProbe.shared.debugAlways(
          "focused_row_disappear_blur_skip_visible_index list=\(owner.id.uuidString) index=\(index) visible=\(owner.lazyListVisibleIndices.sorted())"
        )
        return
      }
      guard owner.listFocusedRowIndex == index else { return }
      OCamlDemoListVirtualizationProbe.shared.debugAlways(
        "focused_row_disappear_blur_send list=\(owner.id.uuidString) index=\(index) visible=\(owner.lazyListVisibleIndices.sorted())"
      )
      model.sendClick(owner.listFocusedRowDisappearEventId)
      rowState.focusedDisappearToken = nil
    }
  }

  private func touchRetainedIndex(_ index: Int) {
    owner.lazyListRetainedOrder.removeAll { $0 == index }
    owner.lazyListRetainedOrder.append(index)
  }

  private func trimRetainedRows() {
    let visibleBudget = max(24, owner.lazyListVisibleIndices.count)
    let maxRetainedRows = min(384, max(128, visibleBudget * 8))
    var scanned = 0
    while owner.lazyListRetainedOrder.count > maxRetainedRows
      && scanned < owner.lazyListRetainedOrder.count {
      let candidate = owner.lazyListRetainedOrder.removeFirst()
      if candidate == index || owner.lazyListVisibleIndices.contains(candidate) {
        owner.lazyListRetainedOrder.append(candidate)
        scanned += 1
        continue
      }
      if let retained = owner.lazyListRowsByIndex[candidate] {
        releaseCachedRow(index: candidate, rendered: retained)
      }
      scanned = 0
    }
  }

  private func releaseCachedRow(index: Int, rendered: OCamlDemoNode) {
    guard owner.lazyListRowsByIndex[index] === rendered else { return }
    let key = owner.lazyListRowKeyByIndex[index]
    owner.lazyListRowsByIndex[index] = nil
    owner.lazyListRowKeyByIndex[index] = nil
    removeLazyRowKeyCacheIfUnused(node: owner, index: index, key: key, rendered: rendered)
    owner.lazyListRetainedOrder.removeAll { $0 == index }
    let releaseStartedAt = CACurrentMediaTime()
    ocaml_demoNativeLazyRowReleaseCallback?(providerId, Int32(index))
    let releaseElapsedMs = (CACurrentMediaTime() - releaseStartedAt) * 1000
    OCamlDemoListVirtualizationProbe.shared.rowReleased(
      listID: listID,
      rowID: rendered.id,
      elapsedMs: releaseElapsedMs
    )
    reportListPerf()
  }

  private func reportListPerf() {
    OCamlDemoListVirtualizationProbe.shared.maybeReport(
      listID: listID,
      totalRows: owner.lazyListRowCount,
      cachedRows: owner.lazyListRowsByIndex.count,
      retainedOrder: owner.lazyListRetainedOrder.count,
      visibleIndices: owner.lazyListVisibleIndices.count
    )
  }
}

private func nativeNode(from pointer: UnsafeMutableRawPointer?) -> OCamlDemoNode? {
  guard let pointer else { return nil }
  return Unmanaged<OCamlDemoNode>.fromOpaque(pointer).takeUnretainedValue()
}

private func ocaml_demoNativeLazyRowKey(
  owner: OCamlDemoNode,
  providerId: Int32,
  index: Int
) -> String {
  if let cached = owner.lazyListIdentityKeyByIndex[index] {
    OCamlDemoListVirtualizationProbe.shared.rowKeyCacheHit(listID: owner.id)
    return cached
  }
  let startedAt = CACurrentMediaTime()
  let key = ocaml_demoNativeUncachedLazyRowKey(providerId: providerId, index: index)
  owner.lazyListIdentityKeyByIndex[index] = key
  OCamlDemoListVirtualizationProbe.shared.rowKeyResolved(
    listID: owner.id,
    elapsedMs: (CACurrentMediaTime() - startedAt) * 1000
  )
  return key
}

private func ocaml_demoNativePublishedLazyRowKey(owner: OCamlDemoNode, index: Int) -> String {
  if let cached = owner.lazyListIdentityKeyByIndex[index] {
    OCamlDemoListVirtualizationProbe.shared.rowKeyCacheHit(listID: owner.id)
    return cached
  }
  fatalError("Missing published lazy row key for index \(index)")
}

private func setLazyListCachedRows(
  node: OCamlDemoNode,
  rowCount: Int,
  cachedIndexPointer: UnsafePointer<Int32>?,
  cachedKeyPointer: UnsafePointer<UnsafePointer<CChar>?>?,
  cachedRowPointer: UnsafePointer<UnsafeMutableRawPointer?>?,
  cachedRowCount: Int32
) {
  guard let cachedIndexPointer, let cachedKeyPointer, let cachedRowPointer else { return }
  for offset in 0..<Int(cachedRowCount) {
    let index = Int(cachedIndexPointer[offset])
    guard index >= 0 && index < rowCount else { continue }
    guard let keyPointer = cachedKeyPointer[offset] else { continue }
    guard let row = nativeNode(from: cachedRowPointer[offset]) else { continue }
    let key = String(cString: keyPointer)
    bindHostModel(node.hostModel, to: row)
    node.lazyListRowsByIndex[index] = row
    node.lazyListRowKeyByIndex[index] = key
    node.lazyListRowsByKey[key] = row
    node.lazyListIdentityKeyByIndex[index] = key
    node.lazyListRetainedOrder.removeAll { $0 == index }
    node.lazyListRetainedOrder.append(index)
  }
}

private func removeLazyRowKeyCacheIfUnused(
  node: OCamlDemoNode,
  index: Int,
  key: String?,
  rendered: OCamlDemoNode
) {
  guard let key else { return }
  guard node.lazyListRowsByKey[key] === rendered else { return }
  guard let currentIndex = node.lazyListIdentityKeysByIndex.firstIndex(of: key) else {
    node.lazyListRowsByKey[key] = nil
    return
  }
  if currentIndex == index || node.lazyListRowsByIndex[currentIndex] === rendered {
    node.lazyListRowsByKey[key] = nil
  }
}

private func ocaml_demoNativeUncachedLazyRowKey(providerId: Int32, index: Int) -> String {
  guard let keyCallback = ocaml_demoNativeLazyRowKeyCallback else {
    return "\(index)"
  }
  guard let keyPointer = keyCallback(providerId, Int32(index)) else {
    return "\(index)"
  }
  defer { free(UnsafeMutableRawPointer(keyPointer)) }
  return String(cString: keyPointer)
}

@_cdecl("ocaml_demo_native_swiftui_run_application")
public func ocaml_demo_native_swiftui_run_application(_ callback: OCamlDemoLaunchCallback?) {
  OCamlDemoAppDelegate.launchCallback = callback
  UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(OCamlDemoAppDelegate.self)
  )
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
  let method = methodPointer.map { String(cString: $0) } ?? "GET"
  let urlString = urlPointer.map { String(cString: $0) } ?? ""
  let authorization = authorizationPointer.map { String(cString: $0) }
  let body = bodyPointer.map { String(cString: $0) } ?? ""

  guard let url = URL(string: urlString) else {
    "Invalid URL: \(urlString)".withCString { pointer in
      callback?(context, false, pointer)
    }
    return
  }

  var request = URLRequest(url: url)
  request.httpMethod = method
  request.timeoutInterval = timeoutSeconds > 0 ? timeoutSeconds : 30
  request.setValue("application/json", forHTTPHeaderField: "Accept")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let authorization, !authorization.isEmpty {
    request.setValue(authorization, forHTTPHeaderField: "Authorization")
  }
  if !body.isEmpty {
    request.httpBody = Data(body.utf8)
  }

  let semaphore = DispatchSemaphore(value: 0)
  var result: (Bool, String) = (false, "request did not complete")

  URLSession.shared.dataTask(with: request) { data, response, error in
    let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    if let error {
      result = (false, error.localizedDescription)
    } else if let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode) {
      let message = responseBody.isEmpty
        ? "HTTP \(httpResponse.statusCode)"
        : "HTTP \(httpResponse.statusCode): \(responseBody)"
      result = (false, message)
    } else {
      result = (true, responseBody)
    }

    semaphore.signal()
  }.resume()

  let timeout = timeoutSeconds > 0 ? timeoutSeconds : 30
  if semaphore.wait(timeout: .now() + timeout) == .timedOut {
    result = (false, "Request timed out")
  }

  result.1.withCString { pointer in
    callback?(context, result.0, pointer)
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_padding")
public func ocaml_demo_native_swiftui_set_padding(
  _ pointer: UnsafeMutableRawPointer?,
  _ top: Double,
  _ leading: Double,
  _ bottom: Double,
  _ trailing: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  if top < 0 || leading < 0 || bottom < 0 || trailing < 0 {
    node.padding = nil
  } else {
    node.padding = EdgeInsets(
      top: CGFloat(top),
      leading: CGFloat(leading),
      bottom: CGFloat(bottom),
      trailing: CGFloat(trailing)
    )
  }
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
  node.frameAlignment = OCamlDemoFrameAlignment(rawValue: alignment) ?? .center
}

@_cdecl("ocaml_demo_native_swiftui_set_regular_material_panel")
public func ocaml_demo_native_swiftui_set_regular_material_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.regularMaterialPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("ocaml_demo_native_swiftui_set_secondary_system_grouped_panel")
public func ocaml_demo_native_swiftui_set_secondary_system_grouped_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.secondarySystemGroupedPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
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
public func ocaml_demo_native_swiftui_set_text(
  _ pointer: UnsafeMutableRawPointer?,
  _ textPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextText = textPointer.map(String.init(cString:)) ?? ""
  if node.text != nextText {
    node.text = nextText
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_system_image")
public func ocaml_demo_native_swiftui_set_system_image(
  _ pointer: UnsafeMutableRawPointer?,
  _ systemImagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.systemImage = systemImagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_button_subtitle")
public func ocaml_demo_native_swiftui_set_button_subtitle(
  _ pointer: UnsafeMutableRawPointer?,
  _ subtitlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.buttonSubtitle = subtitlePointer.map(String.init(cString:))
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
public func ocaml_demo_native_swiftui_set_image_source(
  _ pointer: UnsafeMutableRawPointer?,
  _ source: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.imageSource = source
}

@_cdecl("ocaml_demo_native_swiftui_set_image_color")
public func ocaml_demo_native_swiftui_set_image_color(
  _ pointer: UnsafeMutableRawPointer?,
  _ color: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.imageColor = color
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
public func ocaml_demo_native_swiftui_set_enabled(
  _ pointer: UnsafeMutableRawPointer?,
  _ isEnabled: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isEnabled = isEnabled
}

@_cdecl("ocaml_demo_native_swiftui_set_progress")
public func ocaml_demo_native_swiftui_set_progress(
  _ pointer: UnsafeMutableRawPointer?,
  _ value: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.progressValue = min(max(value, 0), 1)
}

@_cdecl("ocaml_demo_native_swiftui_set_image_payload_mode")
public func ocaml_demo_native_swiftui_set_image_payload_mode(
  _ pointer: UnsafeMutableRawPointer?,
  _ wantsPayload: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.wantsImagePayload = wantsPayload
}

@_cdecl("ocaml_demo_native_swiftui_set_placeholder")
public func ocaml_demo_native_swiftui_set_placeholder(
  _ pointer: UnsafeMutableRawPointer?,
  _ textPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.placeholder = textPointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_style")
public func ocaml_demo_native_swiftui_set_text_field_style(
  _ pointer: UnsafeMutableRawPointer?,
  _ style: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldStyle = style
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_axis")
public func ocaml_demo_native_swiftui_set_text_field_axis(
  _ pointer: UnsafeMutableRawPointer?,
  _ axis: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldAxis = axis
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_clear_button")
public func ocaml_demo_native_swiftui_set_text_field_clear_button(
  _ pointer: UnsafeMutableRawPointer?,
  _ clearButton: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldClearButton = clearButton
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_secure")
public func ocaml_demo_native_swiftui_set_text_field_secure(
  _ pointer: UnsafeMutableRawPointer?,
  _ isSecure: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isTextFieldSecure = isSecure
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_focus")
public func ocaml_demo_native_swiftui_set_text_field_focus(
  _ pointer: UnsafeMutableRawPointer?,
  _ isFocused: Bool
) {
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
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldBlurEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_text_field_delete_backward_at_start")
public func ocaml_demo_native_swiftui_set_text_field_delete_backward_at_start(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldDeleteBackwardAtStartEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_toggle")
public func ocaml_demo_native_swiftui_set_toggle(
  _ pointer: UnsafeMutableRawPointer?,
  _ isOn: Bool,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isToggleOn = isOn
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_spacing")
public func ocaml_demo_native_swiftui_set_spacing(
  _ pointer: UnsafeMutableRawPointer?,
  _ spacing: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.spacing = spacing < 0 ? nil : CGFloat(spacing)
}

@_cdecl("ocaml_demo_native_swiftui_set_horizontal_stack_alignment")
public func ocaml_demo_native_swiftui_set_horizontal_stack_alignment(
  _ pointer: UnsafeMutableRawPointer?,
  _ alignment: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.horizontalStackAlignment =
    OCamlDemoHorizontalStackAlignment(rawValue: alignment) ?? .center
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
  guard let node = nativeNode(from: pointer) else { return }
  if node.lazyListProviderId != nil {
    node.lazyListProviderId = nil
  }
  if node.lazyListRowCount != 0 {
    node.lazyListRowCount = 0
  }
  node.lazyListInvalidatedIndices.removeAll()
  let children: [OCamlDemoNode]
  if let childPointers {
    children = (0..<Int(count)).compactMap { index in
      nativeNode(from: childPointers[index])
    }
  } else {
    children = []
  }
  if !sameNodeSequence(node.children, children) {
    for child in children {
      bindHostModel(node.hostModel, to: child)
    }
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
  if !node.children.isEmpty {
    node.children = []
  }
  if node.lazyListProviderId != providerId {
    node.lazyListProviderId = providerId
  }
  let rowCount = Int(count)
  let providerInvalidatedIndices: Set<Int>
  if let invalidatedIndexPointer {
    providerInvalidatedIndices = Set(
      (0..<Int(invalidatedIndexCount)).map { index in
        Int(invalidatedIndexPointer[index])
      }
    )
  } else {
    providerInvalidatedIndices = []
  }
  OCamlDemoFrameProbe.shared.logLazyRowCountEvent(
    name: "lazy_row_count_update",
    listID: node.id,
    oldCount: effectiveLazyListRowCount(node),
    newCount: rowCount,
    invalidatedCount: providerInvalidatedIndices.count
  )
  node.lazyListInvalidatedIndices = providerInvalidatedIndices
  let nextVersion = Int(version)
  if node.lazyListVersion != nextVersion {
    node.lazyListVersion = nextVersion
  }
  var nextIdentityKeyByIndex = node.lazyListIdentityKeyByIndex
  var nextIdentityKeysByIndex = node.lazyListIdentityKeysByIndex
  if let identityIndexPointer, let identityKeyPointer {
    nextIdentityKeyByIndex.reserveCapacity(max(nextIdentityKeyByIndex.count, Int(identityKeyCount)))
    nextIdentityKeysByIndex = Array(repeating: "", count: rowCount)
    for offset in 0..<Int(identityKeyCount) {
      let index = Int(identityIndexPointer[offset])
      guard index >= 0 && index < rowCount else { continue }
      guard let keyPointer = identityKeyPointer[offset] else { continue }
      let key = String(cString: keyPointer)
      nextIdentityKeyByIndex[index] = key
      nextIdentityKeysByIndex[index] = key
    }
  }
  let knownIndices =
    Set(node.lazyListRowsByIndex.keys)
      .union(nextIdentityKeyByIndex.keys)
      .union(node.lazyListVisibleIndices)
  let outOfRangeIndices = Set(knownIndices.filter { index in
    index < 0 || index >= rowCount
  })
  let staleIndices = outOfRangeIndices.union(providerInvalidatedIndices)
  node.lazyListIdentityKeyByIndex = nextIdentityKeyByIndex
  node.lazyListIdentityKeysByIndex = nextIdentityKeysByIndex
  for index in staleIndices {
    let rendered = node.lazyListRowsByIndex[index]
    let key = node.lazyListRowKeyByIndex[index]
    node.lazyListRowsByIndex[index] = nil
    node.lazyListRowKeyByIndex[index] = nil
    if let rendered {
      removeLazyRowKeyCacheIfUnused(node: node, index: index, key: key, rendered: rendered)
    }
  }
  node.lazyListRetainedOrder.removeAll { staleIndices.contains($0) }
  setLazyListCachedRows(
    node: node,
    rowCount: rowCount,
    cachedIndexPointer: cachedIndexPointer,
    cachedKeyPointer: cachedKeyPointer,
    cachedRowPointer: cachedRowPointer,
    cachedRowCount: cachedRowCount
  )
  for index in outOfRangeIndices {
    node.lazyListVisibleIndexCounts[index] = nil
  }
  node.lazyListVisibleIndices.subtract(outOfRangeIndices)
  if shouldDeferLazyListRowCountPublish(
    node: node,
    rowCount: rowCount,
    providerInvalidatedIndices: providerInvalidatedIndices,
    includeMountedLargeAppend: true
  ) {
    OCamlDemoFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_deferred",
      listID: node.id,
      oldCount: effectiveLazyListRowCount(node),
      newCount: rowCount,
      invalidatedCount: providerInvalidatedIndices.count
    )
    scheduleDeferredLazyListRowCountPublish(node, rowCount)
  } else if node.lazyListRowCount > 0,
            effectiveLazyListRowCount(node) != rowCount,
            !providerInvalidatedIndices.isEmpty {
    OCamlDemoFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_coalesced",
      listID: node.id,
      oldCount: effectiveLazyListRowCount(node),
      newCount: rowCount,
      invalidatedCount: providerInvalidatedIndices.count
    )
    scheduleCoalescedStructuralLazyListRowCountPublish(
      node,
      rowCount,
      invalidatedCount: providerInvalidatedIndices.count
    )
  } else {
    publishLazyListRowCount(
      node,
      rowCount,
      invalidatedCount: providerInvalidatedIndices.count
    )
  }
}

private func scheduleCoalescedStructuralLazyListRowCountPublish(
  _ node: OCamlDemoNode,
  _ rowCount: Int,
  invalidatedCount: Int
) {
  node.pendingLazyListRowCountWorkItem?.cancel()
  node.pendingLazyListRowCount = rowCount
  node.pendingLazyListRowCountInvalidatedCount = invalidatedCount
  node.pendingLazyListRowCountGeneration += 1
  let generation = node.pendingLazyListRowCountGeneration
  let workItem = DispatchWorkItem { [weak node] in
    guard let node else { return }
    guard node.pendingLazyListRowCountGeneration == generation else { return }
    guard let pendingRowCount = node.pendingLazyListRowCount else { return }
    let pendingInvalidatedCount = node.pendingLazyListRowCountInvalidatedCount
    guard node.lazyListRowCount != pendingRowCount else {
      node.pendingLazyListRowCount = nil
      node.pendingLazyListRowCountInvalidatedCount = 0
      node.pendingLazyListRowCountWorkItem = nil
      return
    }
    OCamlDemoFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_coalesced_publish",
      listID: node.id,
      oldCount: node.lazyListRowCount,
      newCount: pendingRowCount,
      invalidatedCount: pendingInvalidatedCount
    )
    applyLazyListRowCount(
      node,
      pendingRowCount,
      invalidatedCount: pendingInvalidatedCount
    )
    node.pendingLazyListRowCount = nil
    node.pendingLazyListRowCountInvalidatedCount = 0
    node.pendingLazyListRowCountWorkItem = nil
  }
  node.pendingLazyListRowCountWorkItem = workItem
  DispatchQueue.main.async(execute: workItem)
}

private func shouldDeferLazyListRowCountPublish(
  node: OCamlDemoNode,
  rowCount: Int,
  providerInvalidatedIndices: Set<Int>,
  includeMountedLargeAppend: Bool
) -> Bool {
  let currentRowCount = effectiveLazyListRowCount(node)
  let appendDelta = rowCount - currentRowCount
  guard appendDelta > 0 else { return false }
  let isLargeAppend = appendDelta >= minDeferredLazyListAppendRowCount
  guard isLargeAppend else { return false }
  let scrollViewIsActive: Bool
  if let scrollView = node.lazyListScrollView {
    scrollViewIsActive = scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
  } else {
    scrollViewIsActive = false
  }
  if includeMountedLargeAppend && isLargeAppend && node.lazyListScrollView != nil {
    return true
  }
  return scrollViewIsActive || OCamlDemoScrollStressProbe.shared.isActivelyScrolling(listID: node.id)
}

private func scheduleDeferredLazyListRowCountPublish(
  _ node: OCamlDemoNode,
  _ rowCount: Int
) {
  node.pendingLazyListRowCount = rowCount
  node.pendingLazyListRowCountInvalidatedCount = 0
  node.pendingLazyListRowCountGeneration += 1
  let generation = node.pendingLazyListRowCountGeneration
  node.pendingLazyListRowCountWorkItem?.cancel()
  var workItem: DispatchWorkItem!
  workItem = DispatchWorkItem { [weak node] in
    guard let node else { return }
    OCamlDemoScrollIdleScheduler.shared.runWhenIdle {
      guard !workItem.isCancelled else { return }
      publishDeferredLazyListRowCountIfReady(node, generation: generation)
    }
  }
  node.pendingLazyListRowCountWorkItem = workItem
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
}

private func publishDeferredLazyListRowCountIfReady(
  _ node: OCamlDemoNode,
  generation: Int
) {
  guard node.pendingLazyListRowCountGeneration == generation else { return }
  guard let pendingRowCount = node.pendingLazyListRowCount else { return }
  if shouldDeferLazyListRowCountPublish(
    node: node,
    rowCount: pendingRowCount,
    providerInvalidatedIndices: [],
    includeMountedLargeAppend: false
  ) {
    scheduleDeferredLazyListRowCountPublish(node, pendingRowCount)
  } else {
    OCamlDemoFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_deferred_publish",
      listID: node.id,
      oldCount: node.lazyListRowCount,
      newCount: pendingRowCount,
      invalidatedCount: 0
    )
    applyLazyListRowCount(node, pendingRowCount, invalidatedCount: 0)
    node.pendingLazyListRowCount = nil
    node.pendingLazyListRowCountInvalidatedCount = 0
    node.pendingLazyListRowCountWorkItem = nil
  }
}

private func publishLazyListRowCount(
  _ node: OCamlDemoNode,
  _ rowCount: Int,
  invalidatedCount: Int = 0
) {
  node.pendingLazyListRowCountWorkItem?.cancel()
  node.pendingLazyListRowCountWorkItem = nil
  node.pendingLazyListRowCountGeneration += 1
  if effectiveLazyListRowCount(node) == rowCount {
    node.pendingLazyListRowCount = nil
    node.pendingLazyListRowCountInvalidatedCount = 0
    return
  }
  applyLazyListRowCount(node, rowCount, invalidatedCount: invalidatedCount)
  node.pendingLazyListRowCount = nil
  node.pendingLazyListRowCountInvalidatedCount = 0
}

private func effectiveLazyListRowCount(_ node: OCamlDemoNode) -> Int {
  node.pendingLazyListRowCount ?? node.lazyListRowCount
}

private func applyLazyListRowCount(
  _ node: OCamlDemoNode,
  _ rowCount: Int,
  invalidatedCount: Int
) {
  let oldCount = node.lazyListRowCount
  OCamlDemoFrameProbe.shared.logLazyRowCountEvent(
    name: "lazy_row_count_published",
    listID: node.id,
    oldCount: oldCount,
    newCount: rowCount,
    invalidatedCount: invalidatedCount
  )
  var transaction = Transaction()
  transaction.animation = nil
  withTransaction(transaction) {
    node.lazyListRowCount = rowCount
  }
  if oldCount > 0,
     rowCount > oldCount,
     invalidatedCount == 0,
     let eventId = node.lazyListRowsPublishedEventId {
    node.hostModel?.sendChange(eventId, text: "")
  }
}

@_cdecl("ocaml_demo_native_swiftui_clear_lazy_list_rows")
public func ocaml_demo_native_swiftui_clear_lazy_list_rows(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  if node.lazyListProviderId != nil {
    node.lazyListProviderId = nil
  }
  node.lazyListRowsPublishedEventId = nil
  node.pendingLazyListRowCountInvalidatedCount = 0
  publishLazyListRowCount(node, 0)
  node.lazyListRowsByIndex.removeAll()
  node.lazyListRowKeyByIndex.removeAll()
  node.lazyListRowsByKey.removeAll()
  node.lazyListIdentityKeysByIndex.removeAll()
  node.lazyListIdentityKeyByIndex.removeAll()
  node.lazyListRetainedOrder.removeAll()
  node.lazyListVisibleIndices.removeAll()
  node.lazyListVisibleIndexCounts.removeAll()
  node.lazyListInvalidatedIndices.removeAll()
}

@_cdecl("ocaml_demo_native_swiftui_set_lazy_list_rows_published_event")
public func ocaml_demo_native_swiftui_set_lazy_list_rows_published_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextEventId = eventId < 0 ? nil : eventId
  if node.lazyListRowsPublishedEventId != nextEventId {
    node.lazyListRowsPublishedEventId = nextEventId
  }
}

@_cdecl("ocaml_demo_native_swiftui_register_lazy_list_callbacks")
public func ocaml_demo_native_swiftui_register_lazy_list_callbacks(
  _ keyCallback: OCamlDemoLazyRowKeyCallback?,
  _ renderCallback: OCamlDemoLazyRowRenderCallback?,
  _ releaseCallback: OCamlDemoLazyRowReleaseCallback?
) {
  ocaml_demoNativeLazyRowKeyCallback = keyCallback
  ocaml_demoNativeLazyRowRenderCallback = renderCallback
  ocaml_demoNativeLazyRowReleaseCallback = releaseCallback
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

@_cdecl("ocaml_demo_native_swiftui_set_list_focused_row_index")
public func ocaml_demo_native_swiftui_set_list_focused_row_index(
  _ pointer: UnsafeMutableRawPointer?,
  _ focusedRowIndex: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextFocusedRowIndex = focusedRowIndex < 0 ? nil : Int(focusedRowIndex)
  if node.listFocusedRowIndex != nextFocusedRowIndex {
    OCamlDemoListVirtualizationProbe.shared.debugAlways(
      "focused_row_index_set list=\(node.id.uuidString) old=\(String(describing: node.listFocusedRowIndex)) new=\(String(describing: nextFocusedRowIndex)) lazy=\(node.lazyListProviderId != nil) rows=\(node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted())"
    )
    node.listFocusedRowIndex = nextFocusedRowIndex
  }
  if nextFocusedRowIndex == nil {
    OCamlDemoKeyboardHandoff.shared.cancelHandoff()
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_on_click")
public func ocaml_demo_native_swiftui_set_on_click(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextEventId = eventId < 0 ? nil : eventId
  if node.clickEventId != nextEventId {
    node.clickEventId = nextEventId
  }
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
public func ocaml_demo_native_swiftui_set_tap_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.tapEventId = eventId < 0 ? nil : eventId
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
public func ocaml_demo_native_swiftui_set_on_appear(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.appearEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_on_change")
public func ocaml_demo_native_swiftui_set_on_change(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_subtitle")
public func ocaml_demo_native_swiftui_set_list_row_subtitle(
  _ pointer: UnsafeMutableRawPointer?,
  _ subtitlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowSubtitle = subtitlePointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_trailing_text")
public func ocaml_demo_native_swiftui_set_list_row_trailing_text(
  _ pointer: UnsafeMutableRawPointer?,
  _ trailingTextPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowTrailingText = trailingTextPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_content_style")
public func ocaml_demo_native_swiftui_set_list_row_content_style(
  _ pointer: UnsafeMutableRawPointer?,
  _ contentStyle: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowContentStyle = contentStyle
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_accessory")
public func ocaml_demo_native_swiftui_set_list_row_accessory(
  _ pointer: UnsafeMutableRawPointer?,
  _ accessory: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowAccessory = accessory
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_title_strikethrough")
public func ocaml_demo_native_swiftui_set_list_row_title_strikethrough(
  _ pointer: UnsafeMutableRawPointer?,
  _ titleStrikethrough: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowTitleStrikethrough = titleStrikethrough
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_leading_system_image")
public func ocaml_demo_native_swiftui_set_list_row_leading_system_image(
  _ pointer: UnsafeMutableRawPointer?,
  _ systemImagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowStaticLeadingSystemImage = systemImagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_preview_image_path")
public func ocaml_demo_native_swiftui_set_list_row_preview_image_path(
  _ pointer: UnsafeMutableRawPointer?,
  _ imagePathPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowPreviewImagePath = imagePathPointer.map(String.init(cString:))
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
public func ocaml_demo_native_swiftui_set_list_row_leading_accessibility(
  _ pointer: UnsafeMutableRawPointer?,
  _ labelPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowLeadingAccessibilityLabel = labelPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_list_row_leading_event")
public func ocaml_demo_native_swiftui_set_list_row_leading_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowLeadingEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_section")
public func ocaml_demo_native_swiftui_set_section(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.sectionTitle = titlePointer.map(String.init(cString:)) ?? ""
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
public func ocaml_demo_native_swiftui_append_picker_option(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.pickerOptions.append(
    OCamlDemoPickerOption(id: String(cString: idPointer), title: String(cString: titlePointer))
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_file_exporter")
public func ocaml_demo_native_swiftui_set_file_exporter(
  _ pointer: UnsafeMutableRawPointer?,
  _ filenamePointer: UnsafePointer<CChar>?,
  _ contentTypePointer: UnsafePointer<CChar>?,
  _ contentPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.exportFilename = filenamePointer.map(String.init(cString:)) ?? ""
  node.exportContentType = contentTypePointer.map(String.init(cString:)) ?? ""
  node.exportContent = contentPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_share_link")
public func ocaml_demo_native_swiftui_set_share_link(
  _ pointer: UnsafeMutableRawPointer?,
  _ urlPointer: UnsafePointer<CChar>?
) {
  nativeNode(from: pointer)?.shareURL = urlPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("ocaml_demo_native_swiftui_set_file_importer")
public func ocaml_demo_native_swiftui_set_file_importer(
  _ pointer: UnsafeMutableRawPointer?,
  _ allowedTypesPointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
  _ count: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.allowedContentTypes = (0..<Int(count)).compactMap { index in
    guard let typePointer = allowedTypesPointer?[index] else { return nil }
    return String(cString: typePointer)
  }
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_slider")
public func ocaml_demo_native_swiftui_set_slider(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ value: Double,
  _ min: Double,
  _ max: Double,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.sliderValue = value
  node.sliderMin = min
  node.sliderMax = max
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_stepper")
public func ocaml_demo_native_swiftui_set_stepper(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ value: Int32,
  _ min: Int32,
  _ max: Int32,
  _ step: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.stepperValue = value
  node.stepperMin = min
  node.stepperMax = max
  node.stepperStep = Swift.max(1, step)
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_date_picker")
public func ocaml_demo_native_swiftui_set_date_picker(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ selectedPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.selectedDateText = selectedPointer.map(String.init(cString:)) ?? ""
  node.changeEventId = eventId < 0 ? nil : eventId
  ocaml_demoDatePickerDebugLogger.notice(
    "setDatePicker node=\(node.id.uuidString, privacy: .public) title=\(node.text, privacy: .public) selected=\(node.selectedDateText, privacy: .public) event=\(eventId, privacy: .public)"
  )
}

@_cdecl("ocaml_demo_native_swiftui_set_color_picker")
public func ocaml_demo_native_swiftui_set_color_picker(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ selectedPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.selectedColorText = selectedPointer.map(String.init(cString:)) ?? "#007AFF"
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_clear_menu")
public func ocaml_demo_native_swiftui_clear_menu(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.systemImage = systemImagePointer.map(String.init(cString:))
  node.menuActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_menu_action")
public func ocaml_demo_native_swiftui_append_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ isEnabled: Bool,
  _ eventId: Int32
) {
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
public func ocaml_demo_native_swiftui_set_disclosure_group(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ isExpanded: Bool,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.isDisclosureExpanded = isExpanded
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("ocaml_demo_native_swiftui_set_navigation_path_stack")
public func ocaml_demo_native_swiftui_set_navigation_path_stack(
  _ pointer: UnsafeMutableRawPointer?,
  _ pathPointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
  _ pathCount: Int32,
  _ eventId: Int32,
  _ destinationsPointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
  _ destinationsCount: Int32
) {
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

@_cdecl("ocaml_demo_native_swiftui_clear_list_row_actions")
public func ocaml_demo_native_swiftui_clear_list_row_actions(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowActions = []
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
  guard let node = nativeNode(from: pointer) else { return }
  node.rowMenuActions = []
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
  guard let node = nativeNode(from: pointer) else { return }
  node.contextMenuActions = []
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
  let content = nativeNode(from: contentPointer)
  if let content {
    bindHostModel(node.hostModel, to: content)
  }
  node.sheetContent = content
  node.isSheetPresented = isPresented
  node.dismissEventId = dismissEventId < 0 ? nil : dismissEventId
}

@_cdecl("ocaml_demo_native_swiftui_set_sheet_detents")
public func ocaml_demo_native_swiftui_set_sheet_detents(
  _ pointer: UnsafeMutableRawPointer?,
  _ kindsPointer: UnsafeMutablePointer<Int32>?,
  _ valuesPointer: UnsafeMutablePointer<Double>?,
  _ count: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  guard count > 0, let kindsPointer, let valuesPointer else {
    node.sheetDetents = []
    return
  }
  node.sheetDetents = (0..<Int(count)).map { index in
    OCamlDemoPresentationDetent(
      kind: kindsPointer[index],
      value: valuesPointer[index]
    )
  }
}

@_cdecl("ocaml_demo_native_swiftui_set_safe_area_inset_bottom")
public func ocaml_demo_native_swiftui_set_safe_area_inset_bottom(
  _ pointer: UnsafeMutableRawPointer?,
  _ contentPointer: UnsafeMutableRawPointer?
) {
  guard let node = nativeNode(from: pointer) else { return }
  let content = nativeNode(from: contentPointer)
  if let content {
    bindHostModel(node.hostModel, to: content)
  }
  node.bottomSafeAreaInsetContent = content
}

@_cdecl("ocaml_demo_native_swiftui_set_popover")
public func ocaml_demo_native_swiftui_set_popover(
  _ pointer: UnsafeMutableRawPointer?,
  _ contentPointer: UnsafeMutableRawPointer?,
  _ isPresented: Bool,
  _ dismissEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let content = nativeNode(from: contentPointer)
  if let content {
    bindHostModel(node.hostModel, to: content)
  }
  node.popoverContent = content
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
public func ocaml_demo_native_swiftui_set_confirmation_dialog(
  _ pointer: UnsafeMutableRawPointer?,
  _ isPresented: Bool,
  _ dismissEventId: Int32,
  _ titlePointer: UnsafePointer<CChar>?,
  _ messagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isConfirmationDialogPresented = isPresented
  node.confirmationDialogDismissEventId = dismissEventId < 0 ? nil : dismissEventId
  node.confirmationDialogTitle = titlePointer.map(String.init(cString:)) ?? ""
  node.confirmationDialogMessage = messagePointer.map(String.init(cString:))
}

@_cdecl("ocaml_demo_native_swiftui_clear_confirmation_dialog_actions")
public func ocaml_demo_native_swiftui_clear_confirmation_dialog_actions(
  _ pointer: UnsafeMutableRawPointer?
) {
  nativeNode(from: pointer)?.confirmationDialogActions = []
}

@_cdecl("ocaml_demo_native_swiftui_append_confirmation_dialog_action")
public func ocaml_demo_native_swiftui_append_confirmation_dialog_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ role: Int32,
  _ isEnabled: Bool,
  _ eventId: Int32
) {
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
  guard let node = nativeNode(from: pointer),
        let idPointer,
        let titlePointer else { return }
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
  guard let node = nativeNode(from: pointer),
        let itemIdPointer,
        let titlePointer else { return }
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

@_cdecl("ocaml_demo_native_swiftui_clear_tabs")
public func ocaml_demo_native_swiftui_clear_tabs(
  _ pointer: UnsafeMutableRawPointer?,
  _ selectedPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
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

@_cdecl("ocaml_demo_native_swiftui_make_controller")
public func ocaml_demo_native_swiftui_make_controller(
  _ rootPointer: UnsafeMutableRawPointer?,
  _ callback: OCamlDemoEventCallback?
) -> UnsafeMutableRawPointer? {
  guard let root = nativeNode(from: rootPointer) else { return nil }
  let controller = makeHostingController(root: root, callback: callback)
  return Unmanaged.passRetained(controller).toOpaque()
}

@_cdecl("ocaml_demo_native_swiftui_update_controller")
public func ocaml_demo_native_swiftui_update_controller(
  _ controllerPointer: UnsafeMutableRawPointer?,
  _ rootPointer: UnsafeMutableRawPointer?
) {
  guard let controllerPointer, let root = nativeNode(from: rootPointer) else { return }
  let controller = Unmanaged<UIViewController>.fromOpaque(controllerPointer).takeUnretainedValue()
  if let model = objc_getAssociatedObject(controller, "OCamlDemoSwiftUIModel") as? OCamlDemoHostModel {
    model.root = root
    bindHostModel(model, to: root)
  }
}

@_cdecl("ocaml_demo_native_swiftui_release_controller")
public func ocaml_demo_native_swiftui_release_controller(_ controllerPointer: UnsafeMutableRawPointer?) {
  guard let controllerPointer else { return }
  Unmanaged<UIViewController>.fromOpaque(controllerPointer).release()
}

@_cdecl("ocaml_demo_native_swiftui_make_window")
public func ocaml_demo_native_swiftui_make_window(
  _ rootPointer: UnsafeMutableRawPointer?,
  _ callback: OCamlDemoEventCallback?
) -> UnsafeMutableRawPointer? {
  guard let root = nativeNode(from: rootPointer) else { return nil }
  let window = UIWindow(frame: UIScreen.main.bounds)
  window.backgroundColor = ocaml_demoHomeBodyUIColor(for: window.traitCollection)
  window.rootViewController = makeHostingController(root: root, callback: callback)
  window.makeKeyAndVisible()
  return Unmanaged.passRetained(window).toOpaque()
}

@_cdecl("ocaml_demo_native_swiftui_release_window")
public func ocaml_demo_native_swiftui_release_window(_ windowPointer: UnsafeMutableRawPointer?) {
  guard let windowPointer else { return }
  Unmanaged<UIWindow>.fromOpaque(windowPointer).release()
}
