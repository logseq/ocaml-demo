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

public typealias BonsaiNativeEventCallback = @convention(c) (Int32, UnsafePointer<CChar>?) -> Void
public typealias BonsaiNativeLazyRowRenderCallback =
  @convention(c) (Int32, Int32) -> UnsafeMutableRawPointer?
public typealias BonsaiNativeLazyRowKeyCallback =
  @convention(c) (Int32, Int32) -> UnsafeMutablePointer<CChar>?
public typealias BonsaiNativeLazyRowReleaseCallback =
  @convention(c) (Int32, Int32) -> Void
public typealias BonsaiNativeHTTPCallback =
  @convention(c) (UnsafeMutableRawPointer?, Bool, UnsafePointer<CChar>?) -> Void
public typealias BonsaiNativeLaunchCallback =
  @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
public typealias BonsaiNativeMainCallback =
  @convention(c) (UnsafeMutableRawPointer?) -> Void

private let bonsaiDatePickerDebugLogger = Logger(
  subsystem: "com.logseq.simple-outliner",
  category: "DatePickerDebug"
)

private var bonsaiNativeLazyRowRenderCallback: BonsaiNativeLazyRowRenderCallback?
private var bonsaiNativeLazyRowKeyCallback: BonsaiNativeLazyRowKeyCallback?
private var bonsaiNativeLazyRowReleaseCallback: BonsaiNativeLazyRowReleaseCallback?
private let minDeferredLazyListAppendRowCount = 16
private let maxDeferredLazyListRowCountPublishDelay: CFTimeInterval = 0.25

private enum BonsaiNativeFrameAlignment: Int32 {
  case center = 0
  case leading = 1

  var swiftUIAlignment: Alignment {
    switch self {
    case .leading: return .leading
    case .center: return .center
    }
  }
}

private enum BonsaiNativeHorizontalStackAlignment: Int32 {
  case center = 0
  case top = 1

  var swiftUIVerticalAlignment: VerticalAlignment {
    switch self {
    case .top: return .top
    case .center: return .center
    }
  }
}

@_cdecl("bonsai_native_swiftui_run_on_main_when_scroll_idle")
public func bonsai_native_swiftui_run_on_main_when_scroll_idle(
  _ context: UnsafeMutableRawPointer?,
  _ perform: @escaping BonsaiNativeMainCallback
) {
  BonsaiNativeScrollIdleScheduler.shared.runWhenIdle(context: context, perform: perform)
}

@_cdecl("bonsai_native_swiftui_run_on_main_after_rendered_frame")
public func bonsai_native_swiftui_run_on_main_after_rendered_frame(
  _ context: UnsafeMutableRawPointer?,
  _ perform: @escaping BonsaiNativeMainCallback
) {
  BonsaiNativeRenderedFrameScheduler.shared.runAfterRenderedFrame {
    perform(context)
  }
}

@_cdecl("bonsai_native_swiftui_set_clipboard_text")
public func bonsai_native_swiftui_set_clipboard_text(_ textPointer: UnsafePointer<CChar>?) {
  guard let textPointer else { return }
  UIPasteboard.general.string = String(cString: textPointer)
}

@_cdecl("bonsai_native_swiftui_set_clipboard_image_file")
public func bonsai_native_swiftui_set_clipboard_image_file(_ pathPointer: UnsafePointer<CChar>?) {
  guard let pathPointer else { return }
  guard let image = UIImage(contentsOfFile: String(cString: pathPointer)) else { return }
  UIPasteboard.general.image = image
}

private var bonsaiNativeAudioPlayer: AVAudioPlayer?
private var bonsaiNativeAudioPath: String?
private var bonsaiNativeAudioRecorder: AVAudioRecorder?
private var bonsaiNativeAudioRecordingURL: URL?

@_cdecl("bonsai_native_swiftui_toggle_audio_file_playback")
public func bonsai_native_swiftui_toggle_audio_file_playback(_ pathPointer: UnsafePointer<CChar>?) {
  guard let pathPointer else { return }
  let path = String(cString: pathPointer)
  if bonsaiNativeAudioPath == path, bonsaiNativeAudioPlayer?.isPlaying == true {
    bonsaiNativeAudioPlayer?.pause()
    bonsaiNativeAudioPlayer = nil
    bonsaiNativeAudioPath = nil
    return
  }
  bonsaiNativeAudioPlayer?.stop()
  do {
    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.prepareToPlay()
    player.play()
    bonsaiNativeAudioPlayer = player
    bonsaiNativeAudioPath = path
  } catch {
    bonsaiNativeAudioPlayer = nil
    bonsaiNativeAudioPath = nil
  }
}

@_cdecl("bonsai_native_swiftui_start_audio_recording")
public func bonsai_native_swiftui_start_audio_recording() {
  func start() {
    do {
      let url = try bonsaiNativeNextAudioRecordingURL()
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
      bonsaiNativeAudioRecorder = recorder
      bonsaiNativeAudioRecordingURL = url
    } catch {
      bonsaiNativeAudioRecorder = nil
      bonsaiNativeAudioRecordingURL = nil
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

@_cdecl("bonsai_native_swiftui_stop_audio_recording_and_transcribe")
public func bonsai_native_swiftui_stop_audio_recording_and_transcribe() -> UnsafeMutablePointer<CChar>? {
  guard let recorder = bonsaiNativeAudioRecorder else {
    return strdup("")
  }
  recorder.stop()
  bonsaiNativeAudioRecorder = nil
  try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

  let url = recorder.url
  bonsaiNativeAudioRecordingURL = url
  let transcript = bonsaiNativeTranscribeAudioRecording(at: url)
  let byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
  return strdup([
    transcript.isEmpty ? "Audio recording" : transcript,
    url.path,
    url.lastPathComponent,
    "audio/mp4",
    String(byteSize)
  ].joined(separator: "\t"))
}

private func bonsaiNativeNextAudioRecordingURL() throws -> URL {
  let base = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
  )
  let appDirectoryName = Bundle.main.bundleIdentifier ?? "BonsaiNative"
  let directory = base
    .appendingPathComponent(appDirectoryName, isDirectory: true)
    .appendingPathComponent("AudioRecordings", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let filename = "audio-recording-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).m4a"
  return directory.appendingPathComponent(filename)
}

private func bonsaiNativeTranscribeAudioRecording(at url: URL) -> String {
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
      try await bonsaiNativeEnsureSpeechModelInstalled(for: transcriber)
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
private func bonsaiNativeEnsureSpeechModelInstalled(for transcriber: SpeechTranscriber) async throws {
  switch await AssetInventory.status(forModules: [transcriber]) {
  case .installed:
    return
  case .supported, .downloading:
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
  case .unsupported:
    throw NSError(domain: "BonsaiNativeSpeech", code: 1)
  @unknown default:
    throw NSError(domain: "BonsaiNativeSpeech", code: 2)
  }
}

@objc(BonsaiNativeAppDelegate)
private final class BonsaiNativeAppDelegate: NSObject, UIApplicationDelegate {
  static var launchCallback: BonsaiNativeLaunchCallback?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    BonsaiNativeAppDelegate.launchCallback?(
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

private let bonsaiLightBackgroundComponent: CGFloat = 0.965

private struct BonsaiCompactSidebarToolbar {
  let title: String
  let openSidebar: () -> Void
}

private extension EnvironmentValues {
  @Entry var bonsaiSuppressNativeToolbar = false
  @Entry var bonsaiCompactSidebarToolbar: BonsaiCompactSidebarToolbar?
}

private var bonsaiHomeBodyBackground: Color {
  Color(uiColor: UIColor { traits in
    bonsaiHomeBodyUIColor(for: traits)
  })
}

@ViewBuilder
private func bonsaiHomeBodyBackgroundLayer() -> some View {
  if #available(iOS 26.0, *) {
    bonsaiHomeBodyBackground.backgroundExtensionEffect()
  } else {
    bonsaiHomeBodyBackground
  }
}

private func bonsaiHomeBodyUIColor(for traits: UITraitCollection) -> UIColor {
  if traits.userInterfaceStyle == .dark {
    return .systemBackground
  }
  return UIColor(
    red: bonsaiLightBackgroundComponent,
    green: bonsaiLightBackgroundComponent,
    blue: bonsaiLightBackgroundComponent,
    alpha: 1
  )
}

private func bonsaiConfigureNavigationBarAppearance(for traits: UITraitCollection) {
  let appearance = UINavigationBarAppearance()
  appearance.configureWithTransparentBackground()
  appearance.shadowColor = .clear

  let navigationBar = UINavigationBar.appearance()
  navigationBar.standardAppearance = appearance
  navigationBar.scrollEdgeAppearance = appearance
  navigationBar.compactAppearance = appearance
  navigationBar.compactScrollEdgeAppearance = appearance
}

private func bonsaiDrawerSidebarTopInset(_ inset: CGFloat) -> CGFloat {
  max(inset + 5, 54)
}

private func bonsaiDrawerSidebarBottomInset(_ inset: CGFloat) -> CGFloat {
  inset > 100 ? 34 : max(inset, 34)
}

private func bonsaiDismissKeyboard() {
  UIApplication.shared.sendAction(
    #selector(UIResponder.resignFirstResponder),
    to: nil,
    from: nil,
    for: nil
  )
}

private final class BonsaiNativeKeyboardHandoff {
  static let shared = BonsaiNativeKeyboardHandoff()

  private weak var holdingField: UITextField?

  func retainKeyboard(from current: UIView) {
    guard current.isFirstResponder else { return }
    guard let window = current.window else { return }

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
      field.removeFromSuperview()
      holdingField = nil
    }
  }

  func cancelHandoff() {
    guard let field = holdingField else { return }
    if field.isFirstResponder {
      field.resignFirstResponder()
    }
    field.removeFromSuperview()
    holdingField = nil
  }
}

private func bonsaiPerformLightHapticFeedback() {
  let generator = UIImpactFeedbackGenerator(style: .light)
  generator.prepare()
  generator.impactOccurred(intensity: 0.65)
}

private func bonsaiNativeSemanticColor(_ color: Int32) -> Color? {
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

private let bonsaiNativePreferredFontFamily = "Inter"

private func bonsaiNativeTextStyleSize(_ textStyle: Font.TextStyle) -> CGFloat {
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

private func bonsaiNativePreferredFont(
  _ textStyle: Font.TextStyle,
  weight: Font.Weight = .regular
) -> Font {
  bonsaiNativePreferredFont(
    size: bonsaiNativeTextStyleSize(textStyle),
    weight: weight,
    relativeTo: textStyle
  )
}

private func bonsaiNativePreferredFont(
  size: CGFloat,
  weight: Font.Weight = .regular,
  relativeTo textStyle: Font.TextStyle = .body
) -> Font {
  if UIFont(name: bonsaiNativePreferredFontFamily, size: size) != nil {
    return Font.custom(bonsaiNativePreferredFontFamily, size: size, relativeTo: textStyle)
      .weight(weight)
  }
  return .system(size: size, weight: weight)
}

private func bonsaiNativePreferredUIFont(
  size: CGFloat,
  weight: UIFont.Weight = .regular
) -> UIFont {
  if let font = UIFont(name: bonsaiNativePreferredFontFamily, size: size) {
    return font
  }
  return .systemFont(ofSize: size, weight: weight)
}

private func bonsaiNativePreferredUIFont(
  _ textStyle: Font.TextStyle,
  weight: UIFont.Weight = .regular
) -> UIFont {
  bonsaiNativePreferredUIFont(size: bonsaiNativeTextStyleSize(textStyle), weight: weight)
}

private struct SidebarBottomActionChrome: ViewModifier {
  let chrome: Int32

  func body(content: Content) -> some View {
    if chrome == 2 {
      content
        .bonsaiLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
    } else {
      content
        .background(Color.black, in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
  }
}

private struct BonsaiCompactSidebarToolbarModifier: ViewModifier {
  let toolbar: BonsaiCompactSidebarToolbar?

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
            .bonsaiLiquidGlassButtonStyle()
            .buttonBorderShape(.circle)
          }
        }
    } else {
      content
    }
  }
}

private extension View {
  func bonsaiBottomBarChrome() -> some View {
    self.toolbarBackground(bonsaiHomeBodyBackground, for: .bottomBar)
  }

  @ViewBuilder
  func bonsaiContentUnderBottomBar() -> some View {
    if #available(iOS 26.0, *) {
      self.contentMargins(.bottom, 0, for: .scrollContent)
    } else {
      self
    }
  }

  func bonsaiNavigationChrome() -> some View {
    self
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .toolbarBackground(bonsaiHomeBodyBackground, for: .navigationBar)
      .background {
        bonsaiHomeBodyBackgroundLayer()
          .ignoresSafeArea(.container, edges: .all)
      }
      .bonsaiBottomBarChrome()
  }

  @ViewBuilder
  func bonsaiLiquidGlassButtonStyle() -> some View {
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
  func bonsaiLiquidGlassPanel(
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

private struct BonsaiNativeRowAction: Identifiable {
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

private struct BonsaiNativeTab: Identifiable {
  let id: String
  let title: String
  let systemImage: String?
  let role: Int32
}

private struct BonsaiNativeSidebarAction: Identifiable {
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
  var menuActions: [BonsaiNativeRowAction]
}

private struct BonsaiNativeToolbarItem: Identifiable {
  let id: String
  let title: String
  let systemImage: String?
  let isTitleVisible: Bool
  let eventId: Int32?
  let isEnabled: Bool
  let shareURL: String?
  var menuActions: [BonsaiNativeRowAction]
}

private enum BonsaiNativeToolbarPlacement: Int32 {
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

private enum BonsaiNativeToolbarContentKind: Int32 {
  case group = 0
  case spacer = 1
}

private struct BonsaiNativeToolbarContent: Identifiable {
  let id: String
  let kind: BonsaiNativeToolbarContentKind
  let placement: BonsaiNativeToolbarPlacement
  let fixed: Bool
  var items: [BonsaiNativeToolbarItem]
}

private struct BonsaiNativeExportDocument: FileDocument {
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

private struct BonsaiNativePickerOption: Identifiable {
  let id: String
  let title: String
}

private struct BonsaiNativeAlertAction: Identifiable {
  let id: String
  let title: String
  let role: Int32
  let isEnabled: Bool
  let eventId: Int32?
}

private struct BonsaiNativePresentationDetent: Identifiable {
  let id = UUID()
  let kind: Int32
  let value: Double
}

private struct BonsaiNativeMenuAction: Identifiable {
  let id: String
  let title: String
  let systemImage: String?
  let style: Int32
  let isEnabled: Bool
  let eventId: Int32?
}

private final class BonsaiNativeNode: ObservableObject, Identifiable {
  let id = UUID()
  let kind: NodeKind
  weak var hostModel: BonsaiNativeHostModel?

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
  @Published var horizontalStackAlignment = BonsaiNativeHorizontalStackAlignment.center
  @Published var gridColumns: Int = 2
  @Published var gridSpacing: CGFloat = 10
  @Published var children: [BonsaiNativeNode] = []
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
  @Published var sheetContent: BonsaiNativeNode?
  @Published var bottomSafeAreaInsetContent: BonsaiNativeNode?
  @Published var isSheetPresented = false
  @Published var sheetDetents: [BonsaiNativePresentationDetent] = []
  @Published var dismissEventId: Int32?
  @Published var popoverContent: BonsaiNativeNode?
  @Published var isPopoverPresented = false
  @Published var popoverDismissEventId: Int32?
  @Published var isAlertPresented = false
  @Published var alertTitle = ""
  @Published var alertMessage: String?
  @Published var alertText: String?
  @Published var alertPlaceholder: String?
  @Published var alertTextEventId: Int32?
  @Published var alertDismissEventId: Int32?
  @Published var alertActions: [BonsaiNativeAlertAction] = []
  @Published var isConfirmationDialogPresented = false
  @Published var confirmationDialogTitle = ""
  @Published var confirmationDialogMessage: String?
  @Published var confirmationDialogDismissEventId: Int32?
  @Published var confirmationDialogActions: [BonsaiNativeAlertAction] = []
  @Published var navigationTitle: String?
  @Published var toolbarItems: [BonsaiNativeToolbarItem] = []
  @Published var toolbarContents: [BonsaiNativeToolbarContent] = []
  @Published var keyboardToolbarItems: [BonsaiNativeToolbarItem] = []
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
  @Published var frameAlignment = BonsaiNativeFrameAlignment.center
  @Published var tabs: [BonsaiNativeTab] = []
  @Published var selectedTabId = ""
  @Published var tabSelectEventId: Int32?
  @Published var sidebarTitle: String?
  @Published var sidebarCompactTopBarVisible = true
  @Published var sidebarHeaderAction: BonsaiNativeSidebarAction?
  @Published var sidebarActions: [BonsaiNativeSidebarAction] = []
  @Published var sidebarHistoryTitle: String?
  @Published var sidebarHistoryActions: [BonsaiNativeSidebarAction] = []
  @Published var sidebarBottomSearchPlaceholder: String?
  @Published var sidebarBottomSearchText = ""
  @Published var sidebarBottomSearchEventId: Int32?
  @Published var sidebarBottomAction: BonsaiNativeSidebarAction?
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
  @Published var rowActions: [BonsaiNativeRowAction] = []
  @Published var rowMenuActions: [BonsaiNativeRowAction] = []
  @Published var contextMenuActions: [BonsaiNativeRowAction] = []
  @Published var sectionTitle = ""
  @Published var pickerSelected = ""
  @Published var pickerStyle: Int32 = 0
  @Published var pickerEventId: Int32?
  @Published var pickerOptions: [BonsaiNativePickerOption] = []
  @Published var sliderValue: Double = 0
  @Published var sliderMin: Double = 0
  @Published var sliderMax: Double = 1
  @Published var stepperValue: Int32 = 0
  @Published var stepperMin: Int32 = 0
  @Published var stepperMax: Int32 = 100
  @Published var stepperStep: Int32 = 1
  @Published var selectedDateText = ""
  @Published var selectedColorText = "#007AFF"
  @Published var menuActions: [BonsaiNativeMenuAction] = []
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
  var lazyListRowsByKey: [String: BonsaiNativeNode] = [:]
  var lazyListRowsByIndex: [Int: BonsaiNativeNode] = [:]
  var lazyListRowKeyByIndex: [Int: String] = [:]
  var lazyListRetainedOrder: [Int] = []
  var lazyListVisibleIndices: Set<Int> = []
  var lazyListVisibleIndexCounts: [Int: Int] = [:]
  weak var lazyListScrollView: UIScrollView?
  var pendingLazyListRowCount: Int?
  var pendingLazyListRowCountInvalidatedCount = 0
  var pendingLazyListRowCountDeadline: CFTimeInterval?
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

private func sameNodeSequence(_ lhs: [BonsaiNativeNode], _ rhs: [BonsaiNativeNode]) -> Bool {
  lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
}

private final class BonsaiNativeFrameProbe: NSObject {
  static let shared = BonsaiNativeFrameProbe()

  private let isEnabled =
    ProcessInfo.processInfo.environment["BONSAI_NATIVE_LIST_DEBUG"] == "1"
    || ProcessInfo.processInfo.environment["BONSAI_NATIVE_FRAME_DEBUG"] == "1"
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
      "[BonsaiNativeScrollPerf] scroll_stress_sample list=\(listID.uuidString) index=\(index) total_rows=\(totalRows) past_first_ten_rows=\(index >= 10)\n",
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

  func markLazyRowRender(listID: UUID, index: Int, elapsedMs: Double, totalRows: Int) {
    guard isEnabled && elapsedMs >= 4 else { return }
    start()
    fputs(
      String(
        format:
          "[BonsaiNativeScrollPerf] lazy_row_render_slow list=%@ index=%d total_rows=%d elapsed_ms=%.2f\n",
        listID.uuidString,
        index,
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
      "[BonsaiNativeScrollPerf] \(name) list=\(listID.uuidString) old_count=\(oldCount) new_count=\(newCount) invalidated_count=\(invalidatedCount)\n",
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
          "[BonsaiNativeScrollPerf] frame_report seconds=%.2f frames=%d max_delta_ms=%.2f over_16ms=%d over_33ms=%d over_50ms=%d lazy_body=%d lazy_appear=%d lazy_disappear=%d media_create=%d media_destroy=%d\n",
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

private final class BonsaiNativeScrollStressProbe {
  static let shared = BonsaiNativeScrollStressProbe()

  private let isEnabled =
    ProcessInfo.processInfo.environment["BONSAI_NATIVE_SCROLL_STRESS"] == "1"
  private let pointsPerTick =
    max(
      1,
      Double(ProcessInfo.processInfo.environment["BONSAI_NATIVE_SCROLL_STRESS_POINTS"] ?? "")
        ?? 80
    )
  private let step =
    max(1, Int(ProcessInfo.processInfo.environment["BONSAI_NATIVE_SCROLL_STRESS_STEP"] ?? "") ?? 3)
  private let delay =
    max(
      0.016,
      Double(ProcessInfo.processInfo.environment["BONSAI_NATIVE_SCROLL_STRESS_DELAY"] ?? "")
        ?? 0.05
    )
  private final class Run {
    var totalRows: Int
    let scrollToIndex: (Int) -> Void
    weak var scrollView: UIScrollView?

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
    BonsaiNativeListVirtualizationProbe.shared.debug(
      "scroll_stress_scroll_view_registered list=\(listID.uuidString) content_height=\(scrollView.contentSize.height) bounds_height=\(scrollView.bounds.height)"
    )
  }

  func isRunning(listID: UUID) -> Bool {
    runningLists[listID] != nil
  }

  func isAnyRunning() -> Bool {
    !runningLists.isEmpty
  }

  func start(listID: UUID, totalRows: Int, scrollToIndex: @escaping (Int) -> Void) {
    guard isEnabled else { return }
    guard totalRows > 0 else { return }
    if let run = runningLists[listID] {
      run.totalRows = totalRows
      return
    }
    let listRun = Run(totalRows: totalRows, scrollToIndex: scrollToIndex)
    listRun.scrollView = pendingScrollViews[listID]
    runningLists[listID] = listRun
    if let scrollView = listRun.scrollView {
      BonsaiNativeListVirtualizationProbe.shared.debug(
        "scroll_stress_scroll_view_registered list=\(listID.uuidString) content_height=\(scrollView.contentSize.height) bounds_height=\(scrollView.bounds.height)"
      )
    }
    run(listID: listID, index: 0, direction: 1)
  }

  private func stop(listID: UUID) {
    runningLists[listID] = nil
  }

  private func run(
    listID: UUID,
    index: Int,
    direction: Int
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      guard let run = self.runningLists[listID] else { return }
      let totalRows = run.totalRows
      guard totalRows > 0 else { return }
      let boundedIndex = min(max(0, index), max(0, totalRows - 1))
      BonsaiNativeFrameProbe.shared.markScrollSample(
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
          BonsaiNativeListVirtualizationProbe.shared.debug(
            "scroll_stress_idle_at_end list=\(listID.uuidString) total_rows=\(totalRows) max_offset=\(maxOffset)"
          )
          self.stop(listID: listID)
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
        BonsaiNativeListVirtualizationProbe.shared.debug(
          "scroll_stress_idle_at_end list=\(listID.uuidString) total_rows=\(totalRows) max_index=\(boundedIndex)"
        )
        self.stop(listID: listID)
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

private final class BonsaiNativeScrollIdleScheduler {
  static let shared = BonsaiNativeScrollIdleScheduler()
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
    perform: @escaping BonsaiNativeMainCallback
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
    if BonsaiNativeScrollStressProbe.shared.isAnyRunning() {
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

private final class BonsaiNativeListVirtualizationProbe {
  static let shared = BonsaiNativeListVirtualizationProbe()

  private let logger = Logger(subsystem: "com.logseq.bonsai-native", category: "ListDebug")
  private let isEnabled =
    ProcessInfo.processInfo.environment["BONSAI_NATIVE_LIST_DEBUG"] == "1"
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
    isEnabled && ProcessInfo.processInfo.environment["BONSAI_NATIVE_LIST_LIFECYCLE_PROBE"] == "1"
  }

  func listUpdated(listID: UUID, totalRows: Int, reason: String) {
    guard isEnabled else { return }
    BonsaiNativeFrameProbe.shared.start()
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
    fputs("[BonsaiNativeListDebug] \(message)\n", stderr)
    fflush(stderr)
    logger.info("\(message, privacy: .public)")
  }

  private func debugDouble(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
  }
}

private final class BonsaiNativeRenderedFrameScheduler: NSObject {
  static let shared = BonsaiNativeRenderedFrameScheduler()

  private var displayLink: CADisplayLink?
  private var pendingActions: [() -> Void] = []
  private var remainingTicks = 0

  func runAfterRenderedFrame(_ action: @escaping () -> Void) {
    pendingActions.append(action)
    remainingTicks = max(remainingTicks, 2)
    BonsaiNativeListVirtualizationProbe.shared.debug(
      "rendered_frame_scheduler_schedule pending=\(pendingActions.count) remaining_ticks=\(remainingTicks)"
    )
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func tick(_: CADisplayLink) {
    remainingTicks -= 1
    BonsaiNativeListVirtualizationProbe.shared.debug(
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
    BonsaiNativeListVirtualizationProbe.shared.debug(
      "rendered_frame_scheduler_flushed actions=\(actions.count)"
    )
  }
}

private final class BonsaiNativeHostModel: ObservableObject {
  @Published var root: BonsaiNativeNode
  let callback: BonsaiNativeEventCallback?

  init(root: BonsaiNativeNode, callback: BonsaiNativeEventCallback?) {
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
      bonsaiDatePickerDebugLogger.notice(
        "sendChange skipped nil event text=\(text, privacy: .public)"
      )
      return
    }
    bonsaiDatePickerDebugLogger.notice(
      "sendChange queued event=\(eventId, privacy: .public) text=\(text, privacy: .public) defer=\(deferOnMain, privacy: .public)"
    )
    dispatchEvent(animation: animation, deferOnMain: deferOnMain) { [callback, text] in
      text.withCString { pointer in
        bonsaiDatePickerDebugLogger.notice(
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

private func bindHostModel(_ model: BonsaiNativeHostModel?, to node: BonsaiNativeNode) {
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

private final class BonsaiNativeListLifecycleUIView: UIView {
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

private struct BonsaiNativeRowLifecycleProbeView: UIViewRepresentable {
  let listID: UUID

  func makeUIView(context _: Context) -> BonsaiNativeListLifecycleUIView {
    BonsaiNativeListVirtualizationProbe.shared.uiRowCreated(listID: listID)
    return BonsaiNativeListLifecycleUIView(listID: listID)
  }

  func updateUIView(_ uiView: BonsaiNativeListLifecycleUIView, context _: Context) {}

  static func dismantleUIView(_ uiView: BonsaiNativeListLifecycleUIView, coordinator _: ()) {
    if let listID = uiView.listID {
      BonsaiNativeListVirtualizationProbe.shared.uiRowDestroyed(listID: listID)
    }
  }
}

private struct BonsaiNativeMediaLifecycleProbeView: UIViewRepresentable {
  let kind: String

  func makeUIView(context _: Context) -> BonsaiNativeListLifecycleUIView {
    BonsaiNativeFrameProbe.shared.markMediaViewCreated(kind: kind)
    BonsaiNativeListVirtualizationProbe.shared.mediaViewCreated(kind: kind)
    return BonsaiNativeListLifecycleUIView(mediaKind: kind)
  }

  func updateUIView(_ uiView: BonsaiNativeListLifecycleUIView, context _: Context) {}

  static func dismantleUIView(_ uiView: BonsaiNativeListLifecycleUIView, coordinator _: ()) {
    if let mediaKind = uiView.mediaKind {
      BonsaiNativeFrameProbe.shared.markMediaViewDestroyed(kind: mediaKind)
      BonsaiNativeListVirtualizationProbe.shared.mediaViewDestroyed(kind: mediaKind)
    }
  }
}

private struct BonsaiNativeScrollViewRegistrationView: UIViewRepresentable {
  let listID: UUID
  let node: BonsaiNativeNode

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
    BonsaiNativeScrollIdleScheduler.shared.register(scrollView: scrollView)
    BonsaiNativeScrollStressProbe.shared.registerScrollView(scrollView, listID: listID)
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
private func bonsaiNativeLifecycleProbeBackground<Content: View>(
  @ViewBuilder content: () -> Content
) -> some View {
  if BonsaiNativeListVirtualizationProbe.shared.isLifecycleProbeEnabled {
    content()
      .frame(width: 0, height: 0)
  } else {
    EmptyView()
  }
}

private struct BonsaiNativeImageView: View {
  @ObservedObject var node: BonsaiNativeNode

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
        if let color = bonsaiNativeSemanticColor(node.imageColor) {
          image.foregroundStyle(color)
        } else {
          image
        }
      }
    }
    .background {
      bonsaiNativeLifecycleProbeBackground {
        BonsaiNativeMediaLifecycleProbeView(kind: "image")
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

private struct BonsaiNativeYouTubeIframeView: UIViewRepresentable {
  let payload: String

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> WKWebView {
    BonsaiNativeFrameProbe.shared.markMediaViewCreated(kind: "youtube-webkit")
    BonsaiNativeListVirtualizationProbe.shared.mediaViewCreated(kind: "youtube-webkit")
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
    BonsaiNativeFrameProbe.shared.markMediaViewDestroyed(kind: "youtube-webkit")
    BonsaiNativeListVirtualizationProbe.shared.mediaViewDestroyed(kind: "youtube-webkit")
  }

  private func load(_ webView: WKWebView, context: Context) {
    context.coordinator.lastPayload = payload
    webView.loadHTMLString(youtubeHTML(payload: payload), baseURL: nil)
  }

  final class Coordinator {
    var lastPayload: String?
  }
}

private struct BonsaiNativeAppWebViewPayload: Decodable {
  let resource: String
  let navigationJavaScript: String?
  let responseJavaScript: String?
}

private struct BonsaiNativeSingleWebViewRoute: Decodable {
  let id: String
  let title: String
  let navigationJavaScript: String
}

private struct BonsaiNativeSingleWebViewNavigationPayload: Decodable {
  let resource: String
  let routes: [BonsaiNativeSingleWebViewRoute]
  let responseJavaScript: String?
}

private final class BonsaiNativeBundleSchemeHandler: NSObject, WKURLSchemeHandler {
  func webView(_: WKWebView, start task: WKURLSchemeTask) {
    guard let url = task.request.url,
          url.scheme == "bonsai-app",
          let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL else {
      task.didFailWithError(NSError(domain: "BonsaiNativeBundle", code: 1))
      return
    }
    let relativePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let resourceURL = bundleRoot.appendingPathComponent(relativePath).standardizedFileURL
    let allowedPrefix = bundleRoot.path.hasSuffix("/") ? bundleRoot.path : bundleRoot.path + "/"
    guard resourceURL.path.hasPrefix(allowedPrefix),
          let data = try? Data(contentsOf: resourceURL) else {
      task.didFailWithError(NSError(domain: "BonsaiNativeBundle", code: 2))
      return
    }
    let ext = resourceURL.pathExtension.lowercased()
    let mimeType: String = switch ext {
    case "html": "text/html"
    case "css": "text/css"
    case "js", "mjs": "text/javascript"
    case "json", "map": "application/json"
    case "wasm": "application/wasm"
    case "svg": "image/svg+xml"
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "webp": "image/webp"
    default: "application/octet-stream"
    }
    let textEncoding = ["html", "css", "js", "mjs", "json", "map", "svg"]
      .contains(ext) ? "utf-8" : nil
    task.didReceive(
      URLResponse(
        url: url,
        mimeType: mimeType,
        expectedContentLength: data.count,
        textEncodingName: textEncoding
      )
    )
    task.didReceive(data)
    task.didFinish()
  }

  func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}

private final class BonsaiNativeSnapshotViewController: UIViewController {
  let route: BonsaiNativeSingleWebViewRoute
  private let imageView = UIImageView()

  init(route: BonsaiNativeSingleWebViewRoute, image: UIImage?) {
    self.route = route
    super.init(nibName: nil, bundle: nil)
    edgesForExtendedLayout = []
    navigationItem.title = route.title
    imageView.image = image
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    imageView.frame = view.bounds
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    imageView.contentMode = .scaleToFill
    view.addSubview(imageView)
  }

  func updateSnapshot(_ image: UIImage?) {
    imageView.image = image
  }
}

private final class BonsaiNativeSingleWebViewNavigationController: UIViewController,
  UINavigationControllerDelegate, WKNavigationDelegate, WKScriptMessageHandler {
  private let schemeHandler = BonsaiNativeBundleSchemeHandler()
  private let webView: WKWebView
  private let routeNavigationController = UINavigationController()
  private let node: BonsaiNativeNode
  private let model: BonsaiNativeHostModel
  private var payload: BonsaiNativeSingleWebViewNavigationPayload?
  private var currentRouteID: String?
  private var loadedResource: String?
  private var pendingPayload: BonsaiNativeSingleWebViewNavigationPayload?
  private var isApplyingTransition = false
  private var isVisible = false
  private var isPageReady = false

  init(node: BonsaiNativeNode, model: BonsaiNativeHostModel) {
    self.node = node
    self.model = model
    let configuration = WKWebViewConfiguration()
    configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "bonsai-app")
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isOpaque = false
    webView.backgroundColor = .systemBackground
    webView.scrollView.backgroundColor = .systemBackground
    webView.underPageBackgroundColor = .systemBackground
    super.init(nibName: nil, bundle: nil)
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
      (controller: BonsaiNativeSingleWebViewNavigationController, _) in
      controller.handleAppearanceChange()
    }
    configuration.userContentController.add(self, name: "bonsaiNative")
    webView.navigationDelegate = self
    routeNavigationController.delegate = self
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    routeNavigationController.view.backgroundColor = .systemBackground
    addChild(routeNavigationController)
    routeNavigationController.view.frame = view.bounds
    routeNavigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(routeNavigationController.view)
    routeNavigationController.didMove(toParent: self)
    routeNavigationController.view.insertSubview(
      webView,
      belowSubview: routeNavigationController.navigationBar
    )
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bodyTop = routeNavigationController.navigationBar.frame.maxY
    webView.frame = CGRect(
      x: 0,
      y: bodyTop,
      width: routeNavigationController.view.bounds.width,
      height: max(0, routeNavigationController.view.bounds.height - bodyTop)
    )
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    isVisible = true
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    isVisible = true
    showLiveWebViewIfReady()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    isVisible = false
    concealWebViewBehindSnapshots()
  }

  private func concealWebViewBehindSnapshots() {
    routeNavigationController.view.sendSubviewToBack(webView)
  }

  private func revealWebViewAboveSnapshots() {
    routeNavigationController.view.insertSubview(
      webView,
      belowSubview: routeNavigationController.navigationBar
    )
  }

  private func showLiveWebViewIfReady() {
    guard isVisible, isPageReady else {
      concealWebViewBehindSnapshots()
      return
    }
    revealWebViewAboveSnapshots()
  }

  private func handleAppearanceChange() {
    view.backgroundColor = .systemBackground
    routeNavigationController.view.backgroundColor = .systemBackground
    webView.backgroundColor = .systemBackground
    webView.scrollView.backgroundColor = .systemBackground
    webView.underPageBackgroundColor = .systemBackground
    captureTopSnapshot()
  }

  deinit {
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "bonsaiNative"
    )
  }

  func apply(_ next: BonsaiNativeSingleWebViewNavigationPayload) {
    guard !next.routes.isEmpty else { return }
    if loadedResource != next.resource {
      pendingPayload = next
      if payload == nil {
        installRouteControllers(next)
      }
      loadedResource = next.resource
      var url = URLComponents()
      url.scheme = "bonsai-app"
      url.host = "bundle"
      url.path = "/" + next.resource
      if let resourceURL = url.url {
        webView.load(URLRequest(url: resourceURL))
      }
      return
    }
    guard !isApplyingTransition else {
      pendingPayload = next
      return
    }
    reconcile(next)
  }

  func webView(_: WKWebView, didFinish _: WKNavigation!) {
    guard let next = pendingPayload else { return }
    pendingPayload = nil
    activateTopRoute(next)
  }

  private func installRouteControllers(
    _ next: BonsaiNativeSingleWebViewNavigationPayload
  ) {
    payload = next
    let controllers = next.routes.map { route in
      BonsaiNativeSnapshotViewController(route: route, image: nil)
    }
    routeNavigationController.setViewControllers(controllers, animated: false)
  }

  private func activateTopRoute(
    _ next: BonsaiNativeSingleWebViewNavigationPayload
  ) {
    payload = next
    applyRoute(next.routes.last!, responseJavaScript: next.responseJavaScript) { [weak self] in
      self?.isPageReady = true
      self?.captureTopSnapshot()
      self?.showLiveWebViewIfReady()
    }
  }

  private func installInitialStack(_ next: BonsaiNativeSingleWebViewNavigationPayload) {
    installRouteControllers(next)
    activateTopRoute(next)
  }

  private func reconcile(_ next: BonsaiNativeSingleWebViewNavigationPayload) {
    let previousCount = payload?.routes.count ?? 0
    let nextCount = next.routes.count
    let previousRouteIDs = payload?.routes.map(\.id) ?? []
    let nextRouteIDs = next.routes.map(\.id)
    if nextRouteIDs == previousRouteIDs, let route = next.routes.last {
      payload = next
      applyRoute(route, responseJavaScript: next.responseJavaScript) { [weak self] in
        self?.captureTopSnapshot()
      }
    } else if nextCount == previousCount + 1, let route = next.routes.last {
      push(route, payload: next)
    } else if nextCount < previousCount {
      pop(to: next)
    } else {
      installInitialStack(next)
    }
  }

  private func push(
    _ route: BonsaiNativeSingleWebViewRoute,
    payload next: BonsaiNativeSingleWebViewNavigationPayload
  ) {
    isApplyingTransition = true
    captureTopSnapshot { [weak self] in
      guard let self else { return }
      concealWebViewBehindSnapshots()
      applyRoute(route, responseJavaScript: next.responseJavaScript) { [weak self] in
        guard let self else { return }
        captureSnapshot { [weak self] image in
          guard let self else { return }
          let controller = BonsaiNativeSnapshotViewController(route: route, image: image)
          payload = next
          currentRouteID = route.id
          routeNavigationController.pushViewController(controller, animated: true)
          finishUsingTransitionCoordinator(of: controller)
        }
      }
    }
  }

  private func pop(to next: BonsaiNativeSingleWebViewNavigationPayload) {
    isApplyingTransition = true
    captureTopSnapshot { [weak self] in
      guard let self, let route = next.routes.last else { return }
      concealWebViewBehindSnapshots()
      payload = next
      let targetCount = next.routes.count
      if targetCount < routeNavigationController.viewControllers.count {
        let target = routeNavigationController.viewControllers[targetCount - 1]
        routeNavigationController.popToViewController(target, animated: true)
        finishUsingTransitionCoordinator(of: target, routeAfterSuccess: route)
      }
    }
  }

  private func finishUsingTransitionCoordinator(
    of controller: UIViewController,
    routeAfterSuccess: BonsaiNativeSingleWebViewRoute? = nil,
    notifyPop: Bool = false
  ) {
    guard let transitionCoordinator = controller.transitionCoordinator
      ?? routeNavigationController.transitionCoordinator else {
      finishTransition(routeAfterSuccess: routeAfterSuccess, notifyPop: notifyPop)
      return
    }
    transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
      guard let self else { return }
      if context.isCancelled {
        showLiveWebViewIfReady()
        isApplyingTransition = false
      } else {
        finishTransition(routeAfterSuccess: routeAfterSuccess, notifyPop: notifyPop)
      }
    }
  }

  private func finishTransition(
    routeAfterSuccess: BonsaiNativeSingleWebViewRoute?,
    notifyPop: Bool = false
  ) {
    let finish = { [weak self] in
      guard let self else { return }
      showLiveWebViewIfReady()
      isApplyingTransition = false
      if notifyPop, let routeAfterSuccess {
        model.sendChange(
          node.changeEventId,
          text: "navigation\tpop\t" + routeAfterSuccess.id
        )
      }
      if let pending = pendingPayload {
        pendingPayload = nil
        reconcile(pending)
      }
    }
    if let routeAfterSuccess {
      currentRouteID = routeAfterSuccess.id
      applyRoute(routeAfterSuccess, responseJavaScript: payload?.responseJavaScript, completion: finish)
    } else {
      finish()
    }
  }

  private func applyRoute(
    _ route: BonsaiNativeSingleWebViewRoute,
    responseJavaScript: String?,
    completion: @escaping () -> Void
  ) {
    currentRouteID = route.id
    let script = """
    (() => {
      (route.navigationJavaScript)
      (responseJavaScript ?? "")
      return new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    })()
    """
    webView.evaluateJavaScript(script) { _, _ in completion() }
  }

  private func captureTopSnapshot(completion: (() -> Void)? = nil) {
    captureSnapshot { [weak self] image in
      (self?.routeNavigationController.topViewController as? BonsaiNativeSnapshotViewController)?
        .updateSnapshot(image)
      completion?()
    }
  }

  private func captureSnapshot(completion: @escaping (UIImage?) -> Void) {
    webView.takeSnapshot(with: nil) { image, _ in completion(image) }
  }

  func navigationController(
    _: UINavigationController,
    willShow viewController: UIViewController,
    animated: Bool
  ) {
    guard animated,
          !isApplyingTransition,
          let routeController = viewController as? BonsaiNativeSnapshotViewController else {
      return
    }
    isApplyingTransition = true
    if let current = payload,
       let targetIndex = current.routes.firstIndex(where: { $0.id == routeController.route.id }) {
      payload = BonsaiNativeSingleWebViewNavigationPayload(
        resource: current.resource,
        routes: Array(current.routes.prefix(targetIndex + 1)),
        responseJavaScript: current.responseJavaScript
      )
    }
    concealWebViewBehindSnapshots()
    finishUsingTransitionCoordinator(
      of: viewController,
      routeAfterSuccess: routeController.route,
      notifyPop: true
    )
  }

  func userContentController(
    _: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    let text = message.body as? String ?? String(describing: message.body)
    model.sendChange(node.changeEventId, text: text)
  }
}

private struct BonsaiNativeSingleWebViewNavigation: UIViewControllerRepresentable {
  let payload: String
  let node: BonsaiNativeNode
  let model: BonsaiNativeHostModel

  func makeUIViewController(context _: Context)
    -> BonsaiNativeSingleWebViewNavigationController {
    let controller = BonsaiNativeSingleWebViewNavigationController(node: node, model: model)
    update(controller)
    return controller
  }

  func updateUIViewController(
    _ controller: BonsaiNativeSingleWebViewNavigationController,
    context _: Context
  ) {
    update(controller)
  }

  private func update(_ controller: BonsaiNativeSingleWebViewNavigationController) {
    guard let data = payload.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(
            BonsaiNativeSingleWebViewNavigationPayload.self,
            from: data
          ) else { return }
    controller.apply(decoded)
  }
}

private struct BonsaiNativeAppWebView: UIViewRepresentable {
  let payload: String
  let node: BonsaiNativeNode
  let model: BonsaiNativeHostModel

  func makeCoordinator() -> Coordinator {
    Coordinator(node: node, model: model)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(context.coordinator, name: "bonsaiNative")
    configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "bonsai-app")
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
      forName: "bonsaiNative"
    )
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    coordinator.webView = nil
  }

  private func update(_ webView: WKWebView, coordinator: Coordinator) {
    guard let data = payload.data(using: .utf8),
          let configuration = try? JSONDecoder().decode(
            BonsaiNativeAppWebViewPayload.self,
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
      var url = URLComponents()
      url.scheme = "bonsai-app"
      url.host = "bundle"
      url.path = "/" + configuration.resource
      guard let resourceURL = url.url else { return }
      webView.load(URLRequest(url: resourceURL))
    } else {
      coordinator.applyPendingJavaScript()
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler,
    WKURLSchemeHandler {
    let node: BonsaiNativeNode
    let model: BonsaiNativeHostModel
    weak var webView: WKWebView?
    var resource: String?
    var isLoaded = false
    var navigationJavaScript: String?
    var responseJavaScript: String?
    var lastNavigationJavaScript: String?
    var lastResponseJavaScript: String?

    init(node: BonsaiNativeNode, model: BonsaiNativeHostModel) {
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

    func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
      guard let url = urlSchemeTask.request.url,
            url.scheme == "bonsai-app",
            let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL else {
        fail(urlSchemeTask, code: 1)
        return
      }
      let relativePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      let resourceURL = bundleRoot.appendingPathComponent(relativePath).standardizedFileURL
      let allowedPrefix = bundleRoot.path.hasSuffix("/") ? bundleRoot.path : bundleRoot.path + "/"
      guard resourceURL.path.hasPrefix(allowedPrefix),
            let data = try? Data(contentsOf: resourceURL) else {
        fail(urlSchemeTask, code: 2)
        return
      }
      let response = URLResponse(
        url: url,
        mimeType: mimeType(for: resourceURL.pathExtension),
        expectedContentLength: data.count,
        textEncodingName: isTextResource(resourceURL.pathExtension) ? "utf-8" : nil
      )
      urlSchemeTask.didReceive(response)
      urlSchemeTask.didReceive(data)
      urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask, code: Int) {
      task.didFailWithError(
        NSError(domain: "BonsaiNativeAppWebView", code: code)
      )
    }

    private func mimeType(for pathExtension: String) -> String {
      switch pathExtension.lowercased() {
      case "html": "text/html"
      case "css": "text/css"
      case "js", "mjs": "text/javascript"
      case "json", "map": "application/json"
      case "wasm": "application/wasm"
      case "svg": "image/svg+xml"
      case "png": "image/png"
      case "jpg", "jpeg": "image/jpeg"
      case "webp": "image/webp"
      default: "application/octet-stream"
      }
    }

    private func isTextResource(_ pathExtension: String) -> Bool {
      ["html", "css", "js", "mjs", "json", "map", "svg"]
        .contains(pathExtension.lowercased())
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

private struct BonsaiNativeDeferredYouTubeIframeView: View {
  let payload: String
  @State private var isLoaded = false

  var body: some View {
    Group {
      if isLoaded {
        BonsaiNativeYouTubeIframeView(payload: payload)
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
                .font(bonsaiNativePreferredFont(.headline))
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
      bonsaiNativeLifecycleProbeBackground {
        BonsaiNativeMediaLifecycleProbeView(kind: "youtube-preview")
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

private func singleWebViewNavigationPayload(from kind: String) -> String? {
  let prefix = "app-webview-navigation:"
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

private struct BonsaiNativeLazyListPosition: Identifiable {
  let index: Int
  let id: String
}

private struct BonsaiNativeLazyListPositions: RandomAccessCollection {
  typealias Index = Int
  typealias Element = BonsaiNativeLazyListPosition

  let owner: BonsaiNativeNode
  let startIndex = 0
  let endIndex: Int

  subscript(position: Int) -> BonsaiNativeLazyListPosition {
    if position >= 0 && position < owner.lazyListIdentityKeysByIndex.count {
      return BonsaiNativeLazyListPosition(
        index: position,
        id: owner.lazyListIdentityKeysByIndex[position]
      )
    }
    return BonsaiNativeLazyListPosition(
      index: position,
      id: bonsaiNativePublishedLazyRowKey(owner: owner, index: position)
    )
  }
}

private struct BonsaiNativeRootView: View {
  @ObservedObject var model: BonsaiNativeHostModel

  var body: some View {
    ZStack(alignment: .top) {
      bonsaiHomeBodyBackgroundLayer()
        .ignoresSafeArea(.container, edges: .all)
      BonsaiNativeNodeView(node: model.root, model: model)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

private final class BonsaiNativeHostingController: UIHostingController<BonsaiNativeRootView> {
  override var preferredStatusBarStyle: UIStatusBarStyle {
    .darkContent
  }
}

private func makeHostingController(
  root: BonsaiNativeNode,
  callback: BonsaiNativeEventCallback?
) -> UIHostingController<BonsaiNativeRootView> {
  let model = BonsaiNativeHostModel(root: root, callback: callback)
  bindHostModel(model, to: root)
  let controller = BonsaiNativeHostingController(rootView: BonsaiNativeRootView(model: model))
  bonsaiConfigureNavigationBarAppearance(for: controller.traitCollection)
  controller.view.backgroundColor = bonsaiHomeBodyUIColor(for: controller.traitCollection)
  controller.view.isOpaque = true
  objc_setAssociatedObject(controller, "BonsaiNativeSwiftUIModel", model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  return controller
}

private struct BonsaiNativeImagePayload {
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
      "bonsai-image-payload",
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
) throws -> BonsaiNativeImagePayload {
  let id = "\(idPrefix)-\(UUID().uuidString)"
  let directory = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)
    .first?
    .appendingPathComponent("BonsaiNativeImages", isDirectory: true)
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("BonsaiNativeImages", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appendingPathComponent("\(id).\(fileExtension(for: mimeType))")
  try data.write(to: url, options: [.atomic])
  let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  let image = UIImage(data: data)
  let scale = image?.scale ?? 1
  let width = Int(((image?.size.width ?? 0) * scale).rounded())
  let height = Int(((image?.size.height ?? 0) * scale).rounded())
  return BonsaiNativeImagePayload(
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

private struct BonsaiNativeKeyboardDismissControlsModifier: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel

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
              bonsaiDismissKeyboard()
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
  private func keyboardToolbarLabel(_ item: BonsaiNativeToolbarItem) -> some View {
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

private struct BonsaiNativeScrollDismissesKeyboardModifier: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode

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

private struct BonsaiNativeListRowSeparatorModifier: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode

  @ViewBuilder
  func body(content: Content) -> some View {
    if node.hideListRowSeparator {
      content.listRowSeparator(.hidden)
    } else {
      content
    }
  }
}

private struct BonsaiNativeSearchModifier: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel

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

private struct BonsaiNativeNavigationTitleModifier: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode

  @ViewBuilder
  func body(content: Content) -> some View {
    if let title = node.navigationTitle {
      content
        .navigationTitle(title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .bonsaiBottomBarChrome()
#endif
    } else {
      content
    }
  }
}

private struct BonsaiNativeHorizontalSwipeModifier: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
  @GestureState private var dragTranslation: CGSize = .zero

  private var horizontalOffset: CGFloat {
    horizontalSwipeOffset(for: dragTranslation)
  }

  private func horizontalSwipeOffset(for translation: CGSize) -> CGFloat {
    let horizontal = translation.width
    let vertical = translation.height
    guard abs(horizontal) > abs(vertical) * 1.2 else { return 0 }
    if horizontal < 0 {
      guard node.horizontalSwipeLeftEventId != nil else { return 0 }
    } else if horizontal > 0 {
      guard node.horizontalSwipeRightEventId != nil else { return 0 }
    }
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
            state = value.translation
          }
          .onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height
            guard abs(horizontal) >= 44, abs(horizontal) > abs(vertical) * 1.4 else {
              return
            }
            guard let eventId = horizontalSwipeEventId(for: value.translation) else {
              return
            }
            bonsaiPerformLightHapticFeedback()
            model.sendClick(eventId)
          }
      )
  }
}

private struct BonsaiNativeNodeModifiers: ViewModifier {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel

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
      .modifier(BonsaiNativeKeyboardDismissControlsModifier(node: node, model: model))
      .modifier(BonsaiNativeScrollDismissesKeyboardModifier(node: node))
      .modifier(BonsaiNativeListRowSeparatorModifier(node: node))
      .modifier(BonsaiNativeSearchModifier(node: node, model: model))
      .modifier(BonsaiNativeNavigationTitleModifier(node: node))
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
          BonsaiNativeNodeView(node: popoverContent, model: model)
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
          bonsaiSheetContentHost {
            BonsaiNativeNodeView(node: sheetContent, model: model)
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
        .modifier(BonsaiNativeHorizontalSwipeModifier(node: node, model: model))
    }
  }

  private func bonsaiSheetContentHost<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ZStack(alignment: .topLeading) {
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
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
        BonsaiNativeNodeView(node: bottomSafeAreaInsetContent, model: model)
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
      let tint = bonsaiNativeSemanticColor(node.liquidGlassPanelTintColor)?
        .opacity(node.liquidGlassPanelTintOpacity)
      content.bonsaiLiquidGlassPanel(
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

private struct BonsaiNativeCongratsEffectView: View {
  var body: some View {
    ZStack {
      ForEach(0..<28, id: \.self) { index in
        BonsaiNativeCongratsParticle(index: index)
      }
      VStack(spacing: 8) {
        Image(systemName: "sparkles")
          .font(.system(size: 44, weight: .semibold))
        Text("Complete")
          .font(bonsaiNativePreferredFont(.title2, weight: .semibold))
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 22)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .shadow(radius: 18)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct BonsaiNativeCongratsParticle: View {
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

private struct BonsaiNativeTextFieldView: View {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    if node.textFieldStyle == 1 {
      textField
        .textFieldStyle(.plain)
        .font(bonsaiNativePreferredFont(size: 18, weight: .regular))
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .bonsaiLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
    } else if node.textFieldStyle == 2 {
      textField
        .textFieldStyle(.plain)
        .font(bonsaiNativePreferredFont(.body))
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
              let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
                name: "text_change",
                listID: node.id
              )
              model.sendChange(node.changeEventId, text: value)
              BonsaiNativeListVirtualizationProbe.shared.operationFinished(
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
        BonsaiNativeDeleteAwareTextField(
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
            let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
              name: "text_change",
              listID: node.id
            )
            model.sendChange(node.changeEventId, text: value, deferOnMain: false)
            BonsaiNativeListVirtualizationProbe.shared.operationFinished(
              name: "text_change",
              listID: node.id,
              startedAt: startedAt
            )
          },
          onSubmit: {
            model.sendClick(node.clickEventId)
          },
          onDeleteBackwardAtStart: {
            model.sendClick(node.textFieldDeleteBackwardAtStartEventId)
          }
        )
      } else if node.textFieldAxis == 1 && node.textFieldDeleteBackwardAtStartEventId != nil {
        BonsaiNativeDeleteAwareTextView(
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
            let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
              name: "text_change",
              listID: node.id
            )
            model.sendChange(node.changeEventId, text: value, deferOnMain: false)
            BonsaiNativeListVirtualizationProbe.shared.operationFinished(
              name: "text_change",
              listID: node.id,
              startedAt: startedAt
            )
          },
          onSubmit: {
            model.sendClick(node.clickEventId)
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
                let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
                  name: "text_change",
                  listID: node.id
                )
                model.sendChange(node.changeEventId, text: value)
                BonsaiNativeListVirtualizationProbe.shared.operationFinished(
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
                let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
                  name: "text_change",
                  listID: node.id
                )
                model.sendChange(node.changeEventId, text: value)
                BonsaiNativeListVirtualizationProbe.shared.operationFinished(
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
  }
}

private final class BonsaiNativeDeleteAwareUITextView: UITextView {
  var onDeleteBackwardAtStart: (() -> Void)?
  var keyboardAccessorySignature: String?
  private let placeholderLabel = UILabel()
  private var wantsFocus = false

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
      BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: self)
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
      _ = resignFirstResponder()
    }
  }

  func updatePlaceholderVisibility() {
    placeholderLabel.isHidden = !(text?.isEmpty ?? true)
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
    BonsaiNativeKeyboardHandoff.shared.completeHandoff()
    let end = endOfDocument
    selectedTextRange = textRange(from: end, to: end)
  }

  override func resignFirstResponder() -> Bool {
    wantsFocus = false
    return super.resignFirstResponder()
  }
}

private var bonsaiNativeKeyboardAccessoryHandlerKey: UInt8 = 0

private final class BonsaiNativeKeyboardAccessoryHandler: NSObject {
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

private func bonsaiNativeKeyboardAccessorySignature(_ items: [BonsaiNativeToolbarItem]) -> String {
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

private func bonsaiNativeKeyboardAccessoryToolbar(
  items: [BonsaiNativeToolbarItem],
  onClick: @escaping (Int32) -> Void,
  onDismiss: @escaping () -> Void
) -> UIToolbar? {
  guard !items.isEmpty else {
    return nil
  }

  let toolbar = UIToolbar()
  let handler =
    BonsaiNativeKeyboardAccessoryHandler(
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
            action: #selector(BonsaiNativeKeyboardAccessoryHandler.activateItem(_:))
          )
      } else {
        button =
          UIBarButtonItem(
            title: item.title,
            style: .plain,
            target: handler,
            action: #selector(BonsaiNativeKeyboardAccessoryHandler.activateItem(_:))
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
        action: #selector(BonsaiNativeKeyboardAccessoryHandler.dismissKeyboard(_:))
      ),
    ]
  objc_setAssociatedObject(
    toolbar,
    &bonsaiNativeKeyboardAccessoryHandlerKey,
    handler,
    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
  )
  toolbar.sizeToFit()
  return toolbar
}

private struct BonsaiNativeDeleteAwareTextView: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  let isFocused: Bool
  let keyboardToolbarItems: [BonsaiNativeToolbarItem]
  let model: BonsaiNativeHostModel
  let onChange: (String) -> Void
  let onSubmit: () -> Void
  let onDeleteBackwardAtStart: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> BonsaiNativeDeleteAwareUITextView {
    let textView = BonsaiNativeDeleteAwareUITextView(frame: .zero)
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.isScrollEnabled = false
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.font = bonsaiNativePreferredUIFont(.body)
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textView.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    return textView
  }

  func updateUIView(_ textView: BonsaiNativeDeleteAwareUITextView, context: Context) {
    context.coordinator.parent = self
    textView.placeholder = placeholder
    textView.font = bonsaiNativePreferredUIFont(.body)
    if textView.text != text {
      textView.text = text
      textView.updatePlaceholderVisibility()
    }
    textView.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    let keyboardAccessorySignature =
      bonsaiNativeKeyboardAccessorySignature(keyboardToolbarItems)
    if textView.keyboardAccessorySignature != keyboardAccessorySignature {
      textView.keyboardAccessorySignature = keyboardAccessorySignature
      textView.inputAccessoryView = bonsaiNativeKeyboardAccessoryToolbar(
        items: keyboardToolbarItems,
        onClick: { eventId in
          BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: textView)
          context.coordinator.model.sendClick(eventId, deferOnMain: false)
        },
        onDismiss: {
          textView.clearFocusRequest()
          bonsaiDismissKeyboard()
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
    var parent: BonsaiNativeDeleteAwareTextView
    var lastIsFocused = false
    let model: BonsaiNativeHostModel

    init(_ parent: BonsaiNativeDeleteAwareTextView) {
      self.parent = parent
      self.model = parent.model
    }

    func textViewDidChange(_ textView: UITextView) {
      updateText(textView.text ?? "")
      (textView as? BonsaiNativeDeleteAwareUITextView)?.updatePlaceholderVisibility()
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
        BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: textView)
        parent.onSubmit()
        return false
      }
      return true
    }
  }
}

private final class BonsaiNativeDeleteAwareUITextField: UITextField {
  var onDeleteBackwardAtStart: (() -> Void)?
  var keyboardAccessorySignature: String?
  private var wantsFocus = false

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
      BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: self)
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
      _ = resignFirstResponder()
    }
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
    BonsaiNativeKeyboardHandoff.shared.completeHandoff()
    let end = endOfDocument
    selectedTextRange = textRange(from: end, to: end)
  }

  override func resignFirstResponder() -> Bool {
    wantsFocus = false
    return super.resignFirstResponder()
  }
}

private struct BonsaiNativeDeleteAwareTextField: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  let isFocused: Bool
  let clearButtonMode: Int32
  let keyboardToolbarItems: [BonsaiNativeToolbarItem]
  let model: BonsaiNativeHostModel
  let onChange: (String) -> Void
  let onSubmit: () -> Void
  let onDeleteBackwardAtStart: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> BonsaiNativeDeleteAwareUITextField {
    let textField = BonsaiNativeDeleteAwareUITextField(frame: .zero)
    textField.borderStyle = .none
    textField.clearButtonMode = uiTextFieldClearButtonMode(clearButtonMode)
    textField.delegate = context.coordinator
    textField.addTarget(
      context.coordinator,
      action: #selector(Coordinator.textFieldEditingChanged(_:)),
      for: .editingChanged
    )
    textField.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    textField.font = bonsaiNativePreferredUIFont(.body)
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return textField
  }

  func updateUIView(_ textField: BonsaiNativeDeleteAwareUITextField, context: Context) {
    context.coordinator.parent = self
    textField.placeholder = placeholder
    textField.clearButtonMode = uiTextFieldClearButtonMode(clearButtonMode)
    textField.font = bonsaiNativePreferredUIFont(.body)
    if textField.text != text {
      textField.text = text
    }
    textField.onDeleteBackwardAtStart = onDeleteBackwardAtStart
    let keyboardAccessorySignature =
      bonsaiNativeKeyboardAccessorySignature(keyboardToolbarItems)
    if textField.keyboardAccessorySignature != keyboardAccessorySignature {
      textField.keyboardAccessorySignature = keyboardAccessorySignature
      textField.inputAccessoryView = bonsaiNativeKeyboardAccessoryToolbar(
        items: keyboardToolbarItems,
        onClick: { eventId in
          BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: textField)
          context.coordinator.model.sendClick(eventId, deferOnMain: false)
        },
        onDismiss: {
          textField.clearFocusRequest()
          bonsaiDismissKeyboard()
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
    var parent: BonsaiNativeDeleteAwareTextField
    var lastIsFocused = false
    let model: BonsaiNativeHostModel

    init(_ parent: BonsaiNativeDeleteAwareTextField) {
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

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: textField)
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

private struct BonsaiNativeShareLinkView: View {
  @ObservedObject var node: BonsaiNativeNode

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

private struct BonsaiNativeNodeView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.bonsaiSuppressNativeToolbar) private var suppressNativeToolbar
  @Environment(\.bonsaiCompactSidebarToolbar) private var compactSidebarToolbar
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
  var suppressListRowActions = false
  @State private var isCompactSidebarOpen = false
  @State private var compactSidebarDragOffset: CGFloat = 0
  @State private var compactSidebarDragAxis: DragAxis?
  @State private var isCompactSidebarDragging = false
  @State private var sidebarKeyboardBottomPadding: CGFloat = 0
  @State private var toolbarExportFilename = "Export.txt"
  @State private var toolbarExportContentType = "public.plain-text"
  @State private var toolbarExportContent = ""
  @State private var isToolbarExportPresented = false
  @State private var listScrollBlurSentForFocusedIndex: Int?

  private enum DragAxis {
    case horizontal
    case vertical
  }

  private var compactSidebarSpringAnimation: Animation {
    .interactiveSpring(response: 0.24, dampingFraction: 0.92, blendDuration: 0.08)
  }

  var body: some View {
    applyModifiers(to: base)
      .fileExporter(
        isPresented: $isToolbarExportPresented,
        document: BonsaiNativeExportDocument(content: toolbarExportContent),
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
                .font(bonsaiNativePreferredFont(.caption2))
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
              BonsaiNativeNodeView(node: child, model: model)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!node.isEnabled)
      }

    case .textField:
      BonsaiNativeTextFieldView(node: node, model: model)

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
              let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
                name: "text_change",
                listID: node.id
              )
              model.sendChange(node.changeEventId, text: value)
              BonsaiNativeListVirtualizationProbe.shared.operationFinished(
                name: "text_change",
                listID: node.id,
                startedAt: startedAt
              )
            }
          )
        )
        .font(bonsaiNativePreferredFont(.body))
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
      .background(bonsaiHomeBodyBackground)
      .bonsaiContentUnderBottomBar()

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
        .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
        .bonsaiBottomBarChrome()
        .modifier(BonsaiCompactSidebarToolbarModifier(toolbar: compactSidebarToolbar))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
      .bonsaiBottomBarChrome()

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
            BonsaiNativeNodeView(node: node.children[1], model: model)
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
      BonsaiNativeImageView(node: node)

    case .listRow:
      BonsaiNativeListRowView(
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
      BonsaiNativePhotoPickerView(node: node, model: model)
        .disabled(!node.isEnabled)

    case .fileExporter:
      BonsaiNativeFileExporterView(node: node)
        .disabled(!node.isEnabled)

    case .shareLink:
      BonsaiNativeShareLinkView(node: node)
        .disabled(!node.isEnabled)

    case .fileImporter:
      BonsaiNativeFileImporterView(node: node, model: model)

    case .cameraCapture:
      BonsaiNativeCameraCaptureView(node: node, model: model)

    case .customView:
      if node.text == "congrats-effect" {
        BonsaiNativeCongratsEffectView()
      } else if node.text == "system-grouped-background" {
        bonsaiHomeBodyBackgroundLayer()
          .ignoresSafeArea(.container, edges: .all)
      } else if let payload = singleWebViewNavigationPayload(from: node.text) {
        BonsaiNativeSingleWebViewNavigation(payload: payload, node: node, model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let payload = appWebViewPayload(from: node.text) {
        BonsaiNativeAppWebView(payload: payload, node: node, model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let payload = youtubePayload(from: node.text) {
        BonsaiNativeDeferredYouTubeIframeView(payload: payload)
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
      BonsaiNativeNodeView(node: child, model: model)
    }
  }

  private var listView: some View {
    ScrollViewReader { proxy in
      listContent(proxy)
    }
  }

  @ViewBuilder
  private func listContent(_ proxy: ScrollViewProxy) -> some View {
    nativeList(proxy)
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
      bonsaiHomeBodyBackground
      BonsaiNativeScrollViewRegistrationView(listID: node.id, node: node)
        .frame(width: 0, height: 0)
    }
    .bonsaiContentUnderBottomBar()
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
  private func nativeListRows() -> some View {
    if let providerId = node.lazyListProviderId {
      if node.listDeleteEventId == nil {
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
          .listRowBackground(bonsaiHomeBodyBackground)
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
          .onMove { source, destination in
            moveLazyListRows(source: source, destination: destination)
          }
          .listRowInsets(EdgeInsets())
          .listRowBackground(bonsaiHomeBodyBackground)
      }
    } else {
      if node.listDeleteEventId == nil {
        nativeStaticListRows()
          .onMove { source, destination in
            moveStaticListRows(source: source, destination: destination)
          }
      } else {
        nativeStaticListRows()
          .onDelete { offsets in
            deleteStaticListRows(offsets: offsets)
          }
          .onMove { source, destination in
            moveStaticListRows(source: source, destination: destination)
          }
      }
    }
  }

  private func nativeStaticListRows() -> some DynamicViewContent {
    ForEach(node.children) { child in
      BonsaiNativeNodeView(node: child, model: model)
          .listRowInsets(EdgeInsets())
        .listRowBackground(bonsaiHomeBodyBackground)
        .onAppear {
          BonsaiNativeListVirtualizationProbe.shared.rowAppeared(
            listID: node.id,
            rowID: child.id,
            totalRows: node.children.count
          )
        }
        .onDisappear {
          BonsaiNativeListVirtualizationProbe.shared.rowDisappeared(
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
    let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
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
      BonsaiNativeListVirtualizationProbe.shared.operationFinished(
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

  private func lazyListPositions() -> BonsaiNativeLazyListPositions {
    BonsaiNativeLazyListPositions(
      owner: node,
      endIndex: node.lazyListRowCount
    )
  }

  private func moveLazyListRows(source: IndexSet, destination: Int) {
    guard node.lazyListProviderId != nil else { return }
    guard let fromPosition = source.first else { return }
    guard fromPosition >= 0 && fromPosition < node.lazyListRowCount else { return }
    let toOffset = min(max(0, destination), node.lazyListRowCount)
    BonsaiNativeListVirtualizationProbe.shared.debugAlways(
      "lazy_move_native_drop list=\(node.id.uuidString) from_position=\(fromPosition) to_offset=\(toOffset) rows=\(node.lazyListRowCount) version=\(node.lazyListVersion)"
    )
    commitLazyListMove(fromIndex: fromPosition, toOffset: toOffset)
  }

  private func commitLazyListMove(fromIndex: Int, toOffset: Int) {
    let eventId = node.listMoveEventId
    let listID = node.id
    let version = node.lazyListVersion
    let startedAt = BonsaiNativeListVirtualizationProbe.shared.operationStarted(
      name: "lazy_move",
      listID: listID,
      detail: "from_index=\(fromIndex) to_offset=\(toOffset)"
    )
    BonsaiNativeListVirtualizationProbe.shared.debugAlways(
      "lazy_move_commit_scheduled list=\(listID.uuidString) from_index=\(fromIndex) to_offset=\(toOffset) version=\(version)"
    )
    emitListChangeWithoutAnimation(
      name: "lazy_move",
      listID: listID,
      eventId: eventId,
      text: "\(fromIndex):\(toOffset)"
    ) {
      BonsaiNativeListVirtualizationProbe.shared.debugAlways(
        "lazy_move_commit_emit list=\(listID.uuidString) from_index=\(fromIndex) to_offset=\(toOffset)"
      )
      BonsaiNativeListVirtualizationProbe.shared.operationFinished(
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
    BonsaiNativeListVirtualizationProbe.shared.debugAlways(
      "\(name)_event_queued list=\(listID.uuidString) text=\(text)"
    )
    let emit = { [model] in
      let delayMs = (CACurrentMediaTime() - startedAt) * 1000
      BonsaiNativeListVirtualizationProbe.shared.debugAlways(
        "\(name)_event_emit_begin list=\(listID.uuidString) text=\(text) queue_delay_ms=\(String(format: "%.2f", delayMs))"
      )
      var transaction = Transaction()
      transaction.animation = nil
      withTransaction(transaction) {
        model.sendChange(eventId, text: text, deferOnMain: false)
      }
      let elapsedMs = (CACurrentMediaTime() - startedAt) * 1000
      BonsaiNativeListVirtualizationProbe.shared.debugAlways(
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
    position: BonsaiNativeLazyListPosition
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
    BonsaiNativeLazyListRowView(
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
    .listRowBackground(bonsaiHomeBodyBackground)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func listAppeared(_ proxy: ScrollViewProxy) {
    BonsaiNativeListVirtualizationProbe.shared.listUpdated(
      listID: node.id,
      totalRows: node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount,
      reason: "appear"
    )
    scrollFocusedRow(proxy)
    startScrollStress(proxy)
  }

  private func listChildrenCountChanged() {
    BonsaiNativeListVirtualizationProbe.shared.listUpdated(
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
        BonsaiNativeListVirtualizationProbe.shared.debugAlways(
          "focused_row_scroll_skip_visible list=\(node.id.uuidString) index=\(index) rows=\(node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted())"
        )
        return
      }
      targetID = AnyHashable(bonsaiNativePublishedLazyRowKey(owner: node, index: index))
    } else {
      guard node.children.indices.contains(index) else { return }
      targetID = AnyHashable(node.children[index].id)
    }
    BonsaiNativeListVirtualizationProbe.shared.debugAlways(
      "focused_row_scroll_queued list=\(node.id.uuidString) index=\(index) lazy=\(node.lazyListProviderId != nil) rows=\(node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted()) target=\(targetID)"
    )
    DispatchQueue.main.async {
      if node.lazyListProviderId != nil && node.lazyListVisibleIndices.contains(index) {
        BonsaiNativeListVirtualizationProbe.shared.debugAlways(
          "focused_row_scroll_skip_visible_at_execute list=\(node.id.uuidString) index=\(index) rows=\(node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted())"
        )
        return
      }
      BonsaiNativeListVirtualizationProbe.shared.debugAlways(
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
      BonsaiNativeListVirtualizationProbe.shared.debugAlways(
        "list_scroll_blur_skip_visible_focused_row list=\(node.id.uuidString) focused_index=\(focusedIndex) visible=\(node.lazyListVisibleIndices.sorted())"
      )
      return
    }
    guard listScrollBlurSentForFocusedIndex != focusedIndex else { return }
    listScrollBlurSentForFocusedIndex = focusedIndex
    BonsaiNativeListVirtualizationProbe.shared.debugAlways(
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
    BonsaiNativeScrollStressProbe.shared.start(
      listID: node.id,
      totalRows: totalRows,
      scrollToIndex: { index in
        guard let proxy else { return }
        if node.lazyListProviderId != nil {
          proxy.scrollTo(bonsaiNativePublishedLazyRowKey(owner: node, index: index), anchor: .top)
        } else if node.children.indices.contains(index) {
          proxy.scrollTo(node.children[index].id, anchor: .top)
        }
      }
    )
  }

  private var movableRowsView: some View {
    ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
      BonsaiNativeNodeView(node: child, model: model)
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
          BonsaiNativeNodeView(node: root, model: model)
        } else {
          EmptyView()
        }
      }
      .modifier(BonsaiCompactSidebarToolbarModifier(toolbar: compactSidebarToolbar))
      .navigationDestination(for: String.self) { destinationId in
        if let index = node.navigationDestinationIds.firstIndex(of: destinationId),
           node.children.indices.contains(index + 1) {
          BonsaiNativeNodeView(node: node.children[index + 1], model: model)
            .bonsaiNavigationChrome()
        } else {
          EmptyView()
            .bonsaiNavigationChrome()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
      .bonsaiBottomBarChrome()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
    .bonsaiBottomBarChrome()
  }

  @ViewBuilder
  private func navigationLinkLabel(suppressRowActions: Bool) -> some View {
    if node.children.indices.contains(0) {
      BonsaiNativeNodeView(
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
        bonsaiDatePickerDebugLogger.notice(
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
    case 0: return bonsaiNativePreferredFont(.largeTitle, weight: weight)
    case 1: return bonsaiNativePreferredFont(.title, weight: weight)
    case 2: return bonsaiNativePreferredFont(.title2, weight: weight)
    case 3: return bonsaiNativePreferredFont(.title3, weight: weight)
    case 4: return bonsaiNativePreferredFont(.headline, weight: weight)
    case 6: return bonsaiNativePreferredFont(.callout, weight: weight)
    case 7: return bonsaiNativePreferredFont(.subheadline, weight: weight)
    case 8: return bonsaiNativePreferredFont(.footnote, weight: weight)
    case 9: return bonsaiNativePreferredFont(.caption, weight: weight)
    case 10: return bonsaiNativePreferredFont(.caption2, weight: weight)
    default: return bonsaiNativePreferredFont(.body, weight: weight)
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
    bonsaiNativeSemanticColor(color) ?? .primary
  }

  private var tabSelection: Binding<String> {
    Binding(
      get: { node.selectedTabId },
      set: { value in
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          node.selectedTabId = value
        }
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
    if let selectedRouteIndex, selectedRouteIndex < node.children.count {
      BonsaiNativeNodeView(node: node.children[selectedRouteIndex], model: model)
    } else if let firstChild = node.children.first {
      BonsaiNativeNodeView(node: firstChild, model: model)
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
    ZStack {
      bonsaiHomeBodyBackground
        .ignoresSafeArea(.container, edges: .all)

      GeometryReader { proxy in
        let screenSize = proxy.size
        let drawerWidth = compactSidebarDrawerWidth(containerWidth: screenSize.width)
        let visibleWidth = compactSidebarVisibleWidth(drawerWidth: drawerWidth)
        let progress = drawerWidth > 0 ? visibleWidth / drawerWidth : 0
        let sidebarTopInset = bonsaiDrawerSidebarTopInset(proxy.safeAreaInsets.top)
        let sidebarBottomInset = bonsaiDrawerSidebarBottomInset(proxy.safeAreaInsets.bottom)

        ZStack(alignment: .leading) {
          bonsaiHomeBodyBackground
            .ignoresSafeArea(.container, edges: .all)

          compactSidebarContent
            .padding(.top, sidebarTopInset)
            .padding(.bottom, sidebarBottomInset)
            .frame(width: drawerWidth, height: screenSize.height, alignment: .topLeading)
            .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
            .opacity(progress)
            .scrollDisabled(isCompactSidebarDragging)

          compactSidebarMainPage
            .frame(width: screenSize.width, height: screenSize.height)
            .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
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
            .scrollDisabled(isCompactSidebarOpen || isCompactSidebarDragging)

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
        .highPriorityGesture(
          DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
              handleCompactSidebarDragChanged(value, drawerWidth: drawerWidth)
            }
            .onEnded { value in
              handleCompactSidebarDragEnded(value, drawerWidth: drawerWidth)
            }
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
    }
  }

  private var compactSidebarMainPage: some View {
    Group {
      if node.sidebarCompactTopBarVisible {
        selectedRouteDetail
          .id(node.selectedTabId)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .environment(\.bonsaiSuppressNativeToolbar, isCompactSidebarOpen || isCompactSidebarDragging)
          .environment(
            \.bonsaiCompactSidebarToolbar,
            BonsaiCompactSidebarToolbar(
              title: selectedRouteTitle,
              openSidebar: {
                setCompactSidebarOpen(true)
              }
            )
          )
      } else {
        selectedRouteDetail
          .id(node.selectedTabId)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .environment(\.bonsaiSuppressNativeToolbar, isCompactSidebarOpen || isCompactSidebarDragging)
      }
    }
    .background(bonsaiHomeBodyBackground.ignoresSafeArea(.container, edges: .all))
    .navigationBarBackButtonHidden(true)
  }

  private var compactSidebarContent: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack(alignment: .center, spacing: 16) {
        Text(sidebarTitle)
          .font(bonsaiNativePreferredFont(size: 28, weight: .bold, relativeTo: .title))
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
    bonsaiDismissKeyboard()
    if isOpen != isCompactSidebarOpen {
      bonsaiPerformLightHapticFeedback()
    }
    withAnimation(compactSidebarSpringAnimation) {
      updateCompactSidebarOpenState(isOpen)
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
      bonsaiDismissKeyboard()
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
    setCompactSidebarOpen(shouldOpen)
  }

  @ViewBuilder
  private func toolbarActionLabel(_ item: BonsaiNativeToolbarItem) -> some View {
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
  private func toolbarMenuLabel(_ item: BonsaiNativeToolbarItem) -> some View {
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
  private func toolbarMenuActionButton(_ action: BonsaiNativeRowAction) -> some View {
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

  private func handleToolbarMenuAction(_ action: BonsaiNativeRowAction) {
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
          .font(bonsaiNativePreferredFont(size: 18, weight: .semibold, relativeTo: .headline))
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

  private func selectCompactSidebarTab(_ tab: BonsaiNativeTab) {
    bonsaiDismissKeyboard()
    if isCompactSidebarOpen {
      bonsaiPerformLightHapticFeedback()
    }
    withAnimation(compactSidebarSpringAnimation) {
      node.selectedTabId = tab.id
      updateCompactSidebarOpenState(false)
    }
    model.sendChange(node.tabSelectEventId, text: tab.id)
  }

  @ViewBuilder
  private func sidebarActionButton(
    _ action: BonsaiNativeSidebarAction,
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

  private func performSidebarAction(_ action: BonsaiNativeSidebarAction) {
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

  private func sidebarActionSelectedTab(_ action: BonsaiNativeSidebarAction) -> String? {
    if let selectsTab = action.selectsTab {
      return selectsTab
    }
    return node.tabs.contains { $0.id == action.id } ? action.id : nil
  }

  private func selectSidebarActionRoute(_ selectedTab: String, closesSidebar: Bool) {
    bonsaiDismissKeyboard()
    if closesSidebar {
      if isCompactSidebarOpen {
        bonsaiPerformLightHapticFeedback()
      }
      withAnimation(compactSidebarSpringAnimation) {
        node.selectedTabId = selectedTab
        updateCompactSidebarOpenState(false)
      }
    } else {
      node.selectedTabId = selectedTab
    }
  }

  private func closeCompactSidebarIfNeeded(_ action: BonsaiNativeSidebarAction) {
    if action.closesSidebar {
      setCompactSidebarOpen(false)
    }
  }

  @ViewBuilder
  private func sidebarActionMenuItems(_ action: BonsaiNativeSidebarAction) -> some View {
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
            bonsaiNativePreferredFont(
              size: subtitle == nil ? 16 : 17,
              weight: subtitle == nil ? .semibold : .regular,
              relativeTo: subtitle == nil ? .callout : .body
            )
          )
          .foregroundStyle(.primary)
          .lineLimit(1)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(bonsaiNativePreferredFont(.caption))
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
        .bonsaiLiquidGlassPanel(cornerRadius: 22, isInteractive: true, isTransparent: true)
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

  private func clickSidebarHeaderAction(_ action: BonsaiNativeSidebarAction) {
    performSidebarAction(action)
  }

  @ViewBuilder
  private func sidebarHeaderAvatar(_ action: BonsaiNativeSidebarAction) -> some View {
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

  private func sidebarHeaderAvatarFallback(_ action: BonsaiNativeSidebarAction) -> some View {
    Circle()
      .fill(Color.pink.opacity(0.9))
      .overlay {
        Text(action.avatarInitial ?? "?")
          .font(bonsaiNativePreferredFont(size: 14, weight: .semibold, relativeTo: .caption))
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
          .bonsaiLiquidGlassPanel(cornerRadius: 26, isInteractive: true)
        }

        if let action = node.sidebarBottomAction {
          sidebarBottomActionButton(action)
        }
      }
    }
  }

  @ViewBuilder
  private func sidebarBottomActionButton(_ action: BonsaiNativeSidebarAction) -> some View {
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
          .font(bonsaiNativePreferredFont(size: 18, weight: .semibold, relativeTo: .headline))
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
        BonsaiNativeNodeView(node: node.children[0], model: model)
      } else {
        EmptyView()
      }
    } content: {
      if node.children.indices.contains(1) {
        BonsaiNativeNodeView(node: node.children[1], model: model)
      } else {
        EmptyView()
      }
    } detail: {
      if node.children.indices.contains(2) {
        BonsaiNativeNodeView(node: node.children[2], model: model)
      } else {
        EmptyView()
      }
    }
  }

  @ViewBuilder
  private var adaptiveLayoutView: some View {
    let index = horizontalSizeClass == .compact ? 0 : 1
    if node.children.indices.contains(index) {
      BonsaiNativeNodeView(node: node.children[index], model: model)
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
              BonsaiNativeNodeView(node: node.children[index], model: model)
            }
          }
        }
      }
    }
    let stableContent = content.transaction { transaction in
      transaction.animation = nil
      transaction.disablesAnimations = true
    }

    if #available(iOS 26.0, *), node.tabs.contains(where: { $0.role == 1 }) {
      stableContent.tabViewSearchActivation(.searchTabSelection)
    } else {
      stableContent
    }
  }

  @ViewBuilder
  @available(iOS 18.0, *)
  private func searchTabContent(index: Int) -> some View {
    if #available(iOS 26.0, *) {
      NavigationStack {
        BonsaiNativeNodeView(node: node.children[index], model: model)
      }
      .tabViewSearchActivation(.searchTabSelection)
    } else {
      BonsaiNativeNodeView(node: node.children[index], model: model)
    }
  }

  private var legacyTabView: some View {
    TabView(selection: tabSelection) {
      ForEach(Array(node.tabs.enumerated()), id: \.element.id) { index, tab in
        if index < node.children.count {
          BonsaiNativeNodeView(node: node.children[index], model: model)
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
    content
        .modifier(BonsaiNativeNodeModifiers(node: node, model: model))
      .toolbar {
        if !suppressNativeToolbar {
          nativeToolbarItems
        }
      }
      .bonsaiBottomBarChrome()
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
  private func nativeToolbarContent(_ content: BonsaiNativeToolbarContent) -> some ToolbarContent {
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
  private func toolbarItemView(_ item: BonsaiNativeToolbarItem) -> some View {
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

private struct BonsaiNativeListRowView: View {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
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
          .font(bonsaiNativePreferredFont(.headline))
          .foregroundStyle(node.rowTitleStrikethrough ? .secondary : .primary)
          .strikethrough(node.rowTitleStrikethrough, color: .secondary)
        if !node.rowSubtitle.isEmpty {
          Text(node.rowSubtitle)
            .font(bonsaiNativePreferredFont(.caption))
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
        .font(bonsaiNativePreferredFont(.headline))
        .foregroundStyle(node.rowTitleStrikethrough ? .secondary : .primary)
        .strikethrough(node.rowTitleStrikethrough, color: .secondary)
      if !node.rowSubtitle.isEmpty {
        Text(node.rowSubtitle)
          .font(bonsaiNativePreferredFont(.caption))
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
          .font(bonsaiNativePreferredFont(.subheadline))
          .foregroundStyle(node.rowTitleStrikethrough ? .secondary : .primary)
          .strikethrough(node.rowTitleStrikethrough, color: .secondary)
          .lineLimit(1)
        if !node.rowSubtitle.isEmpty {
          Text(node.rowSubtitle)
            .font(bonsaiNativePreferredFont(.subheadline))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 12)

      if !node.rowTrailingText.isEmpty {
        Text(node.rowTrailingText)
          .font(bonsaiNativePreferredFont(.caption))
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

private struct BonsaiNativePhotoPickerView: View {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
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
          .font(bonsaiNativePreferredFont(.caption))
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

private struct BonsaiNativeFileExporterView: View {
  @ObservedObject var node: BonsaiNativeNode

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
      .appendingPathComponent("BonsaiNativeExports", isDirectory: true)
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

private struct BonsaiNativeFileImporterView: View {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
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

private struct BonsaiNativeCameraCaptureView: View {
  @ObservedObject var node: BonsaiNativeNode
  let model: BonsaiNativeHostModel
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
          .font(bonsaiNativePreferredFont(.caption))
          .foregroundStyle(.secondary)
      }
    }
    .sheet(isPresented: $isPresented) {
      BonsaiNativeCameraPicker { image in
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

private struct BonsaiNativeCameraPicker: UIViewControllerRepresentable {
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

private final class BonsaiNativeLazyListRowState {
  var isVisible = false
  var visibleIndex: Int?
  var visibleKey: String?
  var focusedDisappearToken: UUID?
  var refreshToken = 0
}

private struct BonsaiNativeLazyListRowView: View, Equatable {
  let providerId: Int32
  let index: Int
  let key: String
  let refreshGeneration: Int
  let owner: BonsaiNativeNode
  let listID: UUID
  let model: BonsaiNativeHostModel
  @State private var loadGeneration = 0
  @State private var renderedChild: BonsaiNativeNode?
  @State private var renderedChildKey: String?
  @State private var renderedChildRefreshGeneration = 0
  @State private var rowState = BonsaiNativeLazyListRowState()

  static func == (lhs: BonsaiNativeLazyListRowView, rhs: BonsaiNativeLazyListRowView) -> Bool {
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
    let _ = BonsaiNativeFrameProbe.shared.markLazyRowBody()
    let _ = BonsaiNativeListVirtualizationProbe.shared.rowBodyEvaluated(listID: listID)
    Group {
      if let child = displayedChild {
        BonsaiNativeNodeView(node: child, model: model)
      } else {
        Color.clear
          .frame(height: 44)
      }
    }
    .background {
      bonsaiNativeLifecycleProbeBackground {
        BonsaiNativeRowLifecycleProbeView(listID: listID)
      }
    }
    .onAppear {
      BonsaiNativeFrameProbe.shared.markLazyRowAppear()
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
      BonsaiNativeFrameProbe.shared.markLazyRowDisappear()
      rowState.isVisible = false
      trackVisibleIndexDisappear()
      if let child = cachedRenderedChild {
        BonsaiNativeListVirtualizationProbe.shared.rowDisappearedAtIndex(
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

  private var cachedRenderedChild: BonsaiNativeNode? {
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

  private var displayedChild: BonsaiNativeNode? {
    guard renderedChildKey == key else { return cachedRenderedChild }
    guard renderedChildRefreshGeneration == refreshGeneration else {
      return cachedRenderedChild
    }
    return renderedChild ?? cachedRenderedChild
  }

  private func setRenderedChild(_ child: BonsaiNativeNode?) {
    renderedChild = child
    renderedChildKey = child == nil ? nil : key
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

  private func renderRowIfNeeded() -> BonsaiNativeNode? {
    if let cached = cachedRenderedChild {
      touchRetainedIndex(index)
      BonsaiNativeListVirtualizationProbe.shared.rowCacheHit(listID: listID)
      return cached
    }
    let resolvedKey = bonsaiNativeLazyRowKey(
      owner: owner,
      providerId: providerId,
      index: index
    )
    guard let renderCallback = bonsaiNativeLazyRowRenderCallback else {
      BonsaiNativeListVirtualizationProbe.shared.debug(
        "lazy_row_render_missing_callback provider=\(providerId) index=\(index)"
      )
      return nil
    }
    let renderStartedAt = CACurrentMediaTime()
    guard let pointer = renderCallback(providerId, Int32(index)) else {
      BonsaiNativeListVirtualizationProbe.shared.debug(
        "lazy_row_render_nil_pointer provider=\(providerId) index=\(index)"
      )
      return nil
    }
    let renderElapsedMs = (CACurrentMediaTime() - renderStartedAt) * 1000
    BonsaiNativeFrameProbe.shared.markLazyRowRender(
      listID: listID,
      index: index,
      elapsedMs: renderElapsedMs,
      totalRows: owner.lazyListRowCount
    )
    guard let rendered = nativeNode(from: pointer) else {
      BonsaiNativeListVirtualizationProbe.shared.debug(
        "lazy_row_render_missing_node provider=\(providerId) index=\(index)"
      )
      return nil
    }
    bindHostModel(owner.hostModel, to: rendered)
    owner.lazyListRowsByIndex[index] = rendered
    owner.lazyListRowKeyByIndex[index] = resolvedKey
    owner.lazyListRowsByKey[resolvedKey] = rendered
    touchRetainedIndex(index)
    BonsaiNativeListVirtualizationProbe.shared.rowRendered(
      listID: listID,
      elapsedMs: renderElapsedMs
    )
    BonsaiNativeListVirtualizationProbe.shared.rowRetained(listID: listID, rowID: rendered.id)
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

  private func markRowAppeared(_ child: BonsaiNativeNode) {
    BonsaiNativeListVirtualizationProbe.shared.rowAppearedAtIndex(
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
    BonsaiNativeListVirtualizationProbe.shared.rowRefreshed(
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
        BonsaiNativeListVirtualizationProbe.shared.debugAlways(
          "focused_row_disappear_blur_skip_visible_index list=\(owner.id.uuidString) index=\(index) visible=\(owner.lazyListVisibleIndices.sorted())"
        )
        return
      }
      guard owner.listFocusedRowIndex == index else { return }
      BonsaiNativeListVirtualizationProbe.shared.debugAlways(
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

  private func releaseCachedRow(index: Int, rendered: BonsaiNativeNode) {
    guard owner.lazyListRowsByIndex[index] === rendered else { return }
    let key = owner.lazyListRowKeyByIndex[index]
    owner.lazyListRowsByIndex[index] = nil
    owner.lazyListRowKeyByIndex[index] = nil
    removeLazyRowKeyCacheIfUnused(node: owner, index: index, key: key, rendered: rendered)
    owner.lazyListRetainedOrder.removeAll { $0 == index }
    let releaseStartedAt = CACurrentMediaTime()
    bonsaiNativeLazyRowReleaseCallback?(providerId, Int32(index))
    let releaseElapsedMs = (CACurrentMediaTime() - releaseStartedAt) * 1000
    BonsaiNativeListVirtualizationProbe.shared.rowReleased(
      listID: listID,
      rowID: rendered.id,
      elapsedMs: releaseElapsedMs
    )
    reportListPerf()
  }

  private func reportListPerf() {
    BonsaiNativeListVirtualizationProbe.shared.maybeReport(
      listID: listID,
      totalRows: owner.lazyListRowCount,
      cachedRows: owner.lazyListRowsByIndex.count,
      retainedOrder: owner.lazyListRetainedOrder.count,
      visibleIndices: owner.lazyListVisibleIndices.count
    )
  }
}

private func nativeNode(from pointer: UnsafeMutableRawPointer?) -> BonsaiNativeNode? {
  guard let pointer else { return nil }
  return Unmanaged<BonsaiNativeNode>.fromOpaque(pointer).takeUnretainedValue()
}

private func bonsaiNativeLazyRowKey(
  owner: BonsaiNativeNode,
  providerId: Int32,
  index: Int
) -> String {
  if let cached = owner.lazyListIdentityKeyByIndex[index] {
    BonsaiNativeListVirtualizationProbe.shared.rowKeyCacheHit(listID: owner.id)
    return cached
  }
  let startedAt = CACurrentMediaTime()
  let key = bonsaiNativeUncachedLazyRowKey(providerId: providerId, index: index)
  owner.lazyListIdentityKeyByIndex[index] = key
  BonsaiNativeListVirtualizationProbe.shared.rowKeyResolved(
    listID: owner.id,
    elapsedMs: (CACurrentMediaTime() - startedAt) * 1000
  )
  return key
}

private func bonsaiNativePublishedLazyRowKey(owner: BonsaiNativeNode, index: Int) -> String {
  if let cached = owner.lazyListIdentityKeyByIndex[index] {
    BonsaiNativeListVirtualizationProbe.shared.rowKeyCacheHit(listID: owner.id)
    return cached
  }
  fatalError("Missing published lazy row key for index \(index)")
}

private func setLazyListCachedRows(
  node: BonsaiNativeNode,
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
  node: BonsaiNativeNode,
  index: Int,
  key: String?,
  rendered: BonsaiNativeNode
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

private func bonsaiNativeUncachedLazyRowKey(providerId: Int32, index: Int) -> String {
  guard let keyCallback = bonsaiNativeLazyRowKeyCallback else {
    return "\(index)"
  }
  guard let keyPointer = keyCallback(providerId, Int32(index)) else {
    return "\(index)"
  }
  defer { free(UnsafeMutableRawPointer(keyPointer)) }
  return String(cString: keyPointer)
}

@_cdecl("bonsai_native_swiftui_run_application")
public func bonsai_native_swiftui_run_application(_ callback: BonsaiNativeLaunchCallback?) {
  BonsaiNativeAppDelegate.launchCallback = callback
  UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(BonsaiNativeAppDelegate.self)
  )
}

@_cdecl("bonsai_native_swiftui_http_send_json")
public func bonsai_native_swiftui_http_send_json(
  _ methodPointer: UnsafePointer<CChar>?,
  _ urlPointer: UnsafePointer<CChar>?,
  _ authorizationPointer: UnsafePointer<CChar>?,
  _ bodyPointer: UnsafePointer<CChar>?,
  _ timeoutSeconds: Double,
  _ context: UnsafeMutableRawPointer?,
  _ callback: BonsaiNativeHTTPCallback?
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

@_cdecl("bonsai_native_swiftui_set_padding")
public func bonsai_native_swiftui_set_padding(
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

@_cdecl("bonsai_native_swiftui_set_frame")
public func bonsai_native_swiftui_set_frame(
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
  node.frameAlignment = BonsaiNativeFrameAlignment(rawValue: alignment) ?? .center
}

@_cdecl("bonsai_native_swiftui_set_regular_material_panel")
public func bonsai_native_swiftui_set_regular_material_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.regularMaterialPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("bonsai_native_swiftui_set_secondary_system_grouped_panel")
public func bonsai_native_swiftui_set_secondary_system_grouped_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.secondarySystemGroupedPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("bonsai_native_swiftui_set_secondary_fill_panel")
public func bonsai_native_swiftui_set_secondary_fill_panel(
  _ pointer: UnsafeMutableRawPointer?,
  _ cornerRadius: Double,
  _ opacity: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.secondaryFillPanelCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
  node.secondaryFillPanelOpacity = opacity
}

@_cdecl("bonsai_native_swiftui_set_liquid_glass_panel")
public func bonsai_native_swiftui_set_liquid_glass_panel(
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

@_cdecl("bonsai_native_swiftui_create_node")
public func bonsai_native_swiftui_create_node(_ rawKind: Int32) -> UnsafeMutableRawPointer? {
  guard let kind = NodeKind(rawValue: rawKind) else { return nil }
  return Unmanaged.passRetained(BonsaiNativeNode(kind: kind)).toOpaque()
}

@_cdecl("bonsai_native_swiftui_release_node")
public func bonsai_native_swiftui_release_node(_ pointer: UnsafeMutableRawPointer?) {
  guard let pointer else { return }
  Unmanaged<BonsaiNativeNode>.fromOpaque(pointer).release()
}

@_cdecl("bonsai_native_swiftui_set_text")
public func bonsai_native_swiftui_set_text(
  _ pointer: UnsafeMutableRawPointer?,
  _ textPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = textPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("bonsai_native_swiftui_set_system_image")
public func bonsai_native_swiftui_set_system_image(
  _ pointer: UnsafeMutableRawPointer?,
  _ systemImagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.systemImage = systemImagePointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_set_button_subtitle")
public func bonsai_native_swiftui_set_button_subtitle(
  _ pointer: UnsafeMutableRawPointer?,
  _ subtitlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.buttonSubtitle = subtitlePointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_set_button_style")
public func bonsai_native_swiftui_set_button_style(_ pointer: UnsafeMutableRawPointer?, _ style: Int32) {
  nativeNode(from: pointer)?.buttonStyle = style
}

@_cdecl("bonsai_native_swiftui_set_title_visible")
public func bonsai_native_swiftui_set_title_visible(_ pointer: UnsafeMutableRawPointer?, _ isVisible: Bool) {
  nativeNode(from: pointer)?.isTitleVisible = isVisible
}

@_cdecl("bonsai_native_swiftui_set_keyboard_dismiss_controls")
public func bonsai_native_swiftui_set_keyboard_dismiss_controls(
  _ pointer: UnsafeMutableRawPointer?,
  _ isEnabled: Bool
) {
  nativeNode(from: pointer)?.keyboardDismissControls = isEnabled
}

@_cdecl("bonsai_native_swiftui_set_scroll_dismisses_keyboard")
public func bonsai_native_swiftui_set_scroll_dismisses_keyboard(
  _ pointer: UnsafeMutableRawPointer?,
  _ isEnabled: Bool
) {
  nativeNode(from: pointer)?.scrollDismissesKeyboard = isEnabled
}

@_cdecl("bonsai_native_swiftui_set_hide_list_row_separator")
public func bonsai_native_swiftui_set_hide_list_row_separator(
  _ pointer: UnsafeMutableRawPointer?,
  _ isHidden: Bool
) {
  nativeNode(from: pointer)?.hideListRowSeparator = isHidden
}

@_cdecl("bonsai_native_swiftui_set_image_source")
public func bonsai_native_swiftui_set_image_source(
  _ pointer: UnsafeMutableRawPointer?,
  _ source: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.imageSource = source
}

@_cdecl("bonsai_native_swiftui_set_image_color")
public func bonsai_native_swiftui_set_image_color(
  _ pointer: UnsafeMutableRawPointer?,
  _ color: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.imageColor = color
}

@_cdecl("bonsai_native_swiftui_set_image_style")
public func bonsai_native_swiftui_set_image_style(
  _ pointer: UnsafeMutableRawPointer?,
  _ maxHeight: Double,
  _ cornerRadius: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.imageMaxHeight = maxHeight < 0 ? nil : CGFloat(maxHeight)
  node.imageCornerRadius = cornerRadius < 0 ? nil : CGFloat(cornerRadius)
}

@_cdecl("bonsai_native_swiftui_set_text_attributes")
public func bonsai_native_swiftui_set_text_attributes(
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

@_cdecl("bonsai_native_swiftui_set_enabled")
public func bonsai_native_swiftui_set_enabled(
  _ pointer: UnsafeMutableRawPointer?,
  _ isEnabled: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isEnabled = isEnabled
}

@_cdecl("bonsai_native_swiftui_set_progress")
public func bonsai_native_swiftui_set_progress(
  _ pointer: UnsafeMutableRawPointer?,
  _ value: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.progressValue = min(max(value, 0), 1)
}

@_cdecl("bonsai_native_swiftui_set_image_payload_mode")
public func bonsai_native_swiftui_set_image_payload_mode(
  _ pointer: UnsafeMutableRawPointer?,
  _ wantsPayload: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.wantsImagePayload = wantsPayload
}

@_cdecl("bonsai_native_swiftui_set_placeholder")
public func bonsai_native_swiftui_set_placeholder(
  _ pointer: UnsafeMutableRawPointer?,
  _ textPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.placeholder = textPointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_set_text_field_style")
public func bonsai_native_swiftui_set_text_field_style(
  _ pointer: UnsafeMutableRawPointer?,
  _ style: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldStyle = style
}

@_cdecl("bonsai_native_swiftui_set_text_field_axis")
public func bonsai_native_swiftui_set_text_field_axis(
  _ pointer: UnsafeMutableRawPointer?,
  _ axis: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldAxis = axis
}

@_cdecl("bonsai_native_swiftui_set_text_field_clear_button")
public func bonsai_native_swiftui_set_text_field_clear_button(
  _ pointer: UnsafeMutableRawPointer?,
  _ clearButton: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldClearButton = clearButton
}

@_cdecl("bonsai_native_swiftui_set_text_field_secure")
public func bonsai_native_swiftui_set_text_field_secure(
  _ pointer: UnsafeMutableRawPointer?,
  _ isSecure: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isTextFieldSecure = isSecure
}

@_cdecl("bonsai_native_swiftui_set_text_field_focus")
public func bonsai_native_swiftui_set_text_field_focus(
  _ pointer: UnsafeMutableRawPointer?,
  _ isFocused: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  if node.isTextFieldFocused != isFocused {
    node.isTextFieldFocused = isFocused
  }
}

@_cdecl("bonsai_native_swiftui_set_text_field_delete_backward_at_start")
public func bonsai_native_swiftui_set_text_field_delete_backward_at_start(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.textFieldDeleteBackwardAtStartEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_toggle")
public func bonsai_native_swiftui_set_toggle(
  _ pointer: UnsafeMutableRawPointer?,
  _ isOn: Bool,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.isToggleOn = isOn
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_spacing")
public func bonsai_native_swiftui_set_spacing(
  _ pointer: UnsafeMutableRawPointer?,
  _ spacing: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.spacing = spacing < 0 ? nil : CGFloat(spacing)
}

@_cdecl("bonsai_native_swiftui_set_horizontal_stack_alignment")
public func bonsai_native_swiftui_set_horizontal_stack_alignment(
  _ pointer: UnsafeMutableRawPointer?,
  _ alignment: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.horizontalStackAlignment =
    BonsaiNativeHorizontalStackAlignment(rawValue: alignment) ?? .center
}

@_cdecl("bonsai_native_swiftui_set_grid")
public func bonsai_native_swiftui_set_grid(
  _ pointer: UnsafeMutableRawPointer?,
  _ columns: Int32,
  _ spacing: Double
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.gridColumns = max(1, Int(columns))
  node.gridSpacing = CGFloat(spacing)
}

@_cdecl("bonsai_native_swiftui_set_children")
public func bonsai_native_swiftui_set_children(
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
  let children: [BonsaiNativeNode]
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

@_cdecl("bonsai_native_swiftui_set_lazy_list_rows")
public func bonsai_native_swiftui_set_lazy_list_rows(
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
  BonsaiNativeFrameProbe.shared.logLazyRowCountEvent(
    name: "lazy_row_count_update",
    listID: node.id,
    oldCount: node.lazyListRowCount,
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
    BonsaiNativeFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_deferred",
      listID: node.id,
      oldCount: node.lazyListRowCount,
      newCount: rowCount,
      invalidatedCount: providerInvalidatedIndices.count
    )
    scheduleDeferredLazyListRowCountPublish(node, rowCount)
  } else if node.lazyListRowCount > 0,
            node.lazyListRowCount != rowCount,
            !providerInvalidatedIndices.isEmpty {
    BonsaiNativeFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_coalesced",
      listID: node.id,
      oldCount: node.lazyListRowCount,
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
  _ node: BonsaiNativeNode,
  _ rowCount: Int,
  invalidatedCount: Int
) {
  node.pendingLazyListRowCountWorkItem?.cancel()
  node.pendingLazyListRowCount = rowCount
  node.pendingLazyListRowCountInvalidatedCount = invalidatedCount
  node.pendingLazyListRowCountDeadline = nil
  node.pendingLazyListRowCountGeneration += 1
  let generation = node.pendingLazyListRowCountGeneration
  let workItem = DispatchWorkItem { [weak node] in
    guard let node else { return }
    guard node.pendingLazyListRowCountGeneration == generation else { return }
    guard let pendingRowCount = node.pendingLazyListRowCount else { return }
    let pendingInvalidatedCount = node.pendingLazyListRowCountInvalidatedCount
    BonsaiNativeFrameProbe.shared.logLazyRowCountEvent(
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
  node: BonsaiNativeNode,
  rowCount: Int,
  providerInvalidatedIndices: Set<Int>,
  includeMountedLargeAppend: Bool
) -> Bool {
  let appendDelta = rowCount - node.lazyListRowCount
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
  return scrollViewIsActive || BonsaiNativeScrollStressProbe.shared.isRunning(listID: node.id)
}

private func scheduleDeferredLazyListRowCountPublish(
  _ node: BonsaiNativeNode,
  _ rowCount: Int
) {
  let shouldScheduleMaxLatencyTimer = node.pendingLazyListRowCount == nil
  if shouldScheduleMaxLatencyTimer {
    node.pendingLazyListRowCountDeadline =
      CACurrentMediaTime() + maxDeferredLazyListRowCountPublishDelay
  }
  node.pendingLazyListRowCount = rowCount
  node.pendingLazyListRowCountInvalidatedCount = 0
  node.pendingLazyListRowCountGeneration += 1
  let generation = node.pendingLazyListRowCountGeneration
  if shouldScheduleMaxLatencyTimer {
    DispatchQueue.main.asyncAfter(deadline: .now() + maxDeferredLazyListRowCountPublishDelay) { [weak node] in
      guard let node else { return }
      publishDeferredLazyListRowCountIfReady(node, generation: generation)
    }
  }
  node.pendingLazyListRowCountWorkItem?.cancel()
  var workItem: DispatchWorkItem!
  workItem = DispatchWorkItem { [weak node] in
    guard let node else { return }
    BonsaiNativeScrollIdleScheduler.shared.runWhenIdle {
      guard !workItem.isCancelled else { return }
      publishDeferredLazyListRowCountIfReady(node, generation: generation)
    }
  }
  node.pendingLazyListRowCountWorkItem = workItem
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
}

private func publishDeferredLazyListRowCountIfReady(
  _ node: BonsaiNativeNode,
  generation: Int
) {
  guard node.pendingLazyListRowCountGeneration == generation else { return }
  guard let pendingRowCount = node.pendingLazyListRowCount else { return }
  let exceededMaxDelay =
    node.pendingLazyListRowCountDeadline
      .map { CACurrentMediaTime() >= $0 }
      ?? true
  if shouldDeferLazyListRowCountPublish(
    node: node,
    rowCount: pendingRowCount,
    providerInvalidatedIndices: [],
    includeMountedLargeAppend: false
  ) && !exceededMaxDelay {
    scheduleDeferredLazyListRowCountPublish(node, pendingRowCount)
  } else {
    BonsaiNativeFrameProbe.shared.logLazyRowCountEvent(
      name: "lazy_row_count_deferred_publish",
      listID: node.id,
      oldCount: node.lazyListRowCount,
      newCount: pendingRowCount,
      invalidatedCount: 0
    )
    applyLazyListRowCount(node, pendingRowCount, invalidatedCount: 0)
    node.pendingLazyListRowCount = nil
    node.pendingLazyListRowCountInvalidatedCount = 0
    node.pendingLazyListRowCountDeadline = nil
    node.pendingLazyListRowCountWorkItem = nil
  }
}

private func publishLazyListRowCount(
  _ node: BonsaiNativeNode,
  _ rowCount: Int,
  invalidatedCount: Int = 0
) {
  node.pendingLazyListRowCountWorkItem?.cancel()
  node.pendingLazyListRowCountWorkItem = nil
  node.pendingLazyListRowCountGeneration += 1
  if node.lazyListRowCount == rowCount {
    node.pendingLazyListRowCount = nil
    node.pendingLazyListRowCountInvalidatedCount = 0
    node.pendingLazyListRowCountDeadline = nil
    return
  }
  applyLazyListRowCount(node, rowCount, invalidatedCount: invalidatedCount)
  node.pendingLazyListRowCount = nil
  node.pendingLazyListRowCountInvalidatedCount = 0
  node.pendingLazyListRowCountDeadline = nil
}

private func applyLazyListRowCount(
  _ node: BonsaiNativeNode,
  _ rowCount: Int,
  invalidatedCount: Int
) {
  let oldCount = node.lazyListRowCount
  BonsaiNativeFrameProbe.shared.logLazyRowCountEvent(
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

@_cdecl("bonsai_native_swiftui_clear_lazy_list_rows")
public func bonsai_native_swiftui_clear_lazy_list_rows(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  if node.lazyListProviderId != nil {
    node.lazyListProviderId = nil
  }
  node.lazyListRowsPublishedEventId = nil
  node.pendingLazyListRowCountDeadline = nil
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

@_cdecl("bonsai_native_swiftui_set_lazy_list_rows_published_event")
public func bonsai_native_swiftui_set_lazy_list_rows_published_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextEventId = eventId < 0 ? nil : eventId
  if node.lazyListRowsPublishedEventId != nextEventId {
    node.lazyListRowsPublishedEventId = nextEventId
  }
}

@_cdecl("bonsai_native_swiftui_register_lazy_list_callbacks")
public func bonsai_native_swiftui_register_lazy_list_callbacks(
  _ keyCallback: BonsaiNativeLazyRowKeyCallback?,
  _ renderCallback: BonsaiNativeLazyRowRenderCallback?,
  _ releaseCallback: BonsaiNativeLazyRowReleaseCallback?
) {
  bonsaiNativeLazyRowKeyCallback = keyCallback
  bonsaiNativeLazyRowRenderCallback = renderCallback
  bonsaiNativeLazyRowReleaseCallback = releaseCallback
}

@_cdecl("bonsai_native_swiftui_set_list_behavior")
public func bonsai_native_swiftui_set_list_behavior(
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

@_cdecl("bonsai_native_swiftui_set_list_focused_row_disappear_event")
public func bonsai_native_swiftui_set_list_focused_row_disappear_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextEventId = eventId < 0 ? nil : eventId
  if node.listFocusedRowDisappearEventId != nextEventId {
    node.listFocusedRowDisappearEventId = nextEventId
  }
}

@_cdecl("bonsai_native_swiftui_set_list_focused_row_index")
public func bonsai_native_swiftui_set_list_focused_row_index(
  _ pointer: UnsafeMutableRawPointer?,
  _ focusedRowIndex: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  let nextFocusedRowIndex = focusedRowIndex < 0 ? nil : Int(focusedRowIndex)
  if node.listFocusedRowIndex != nextFocusedRowIndex {
    BonsaiNativeListVirtualizationProbe.shared.debugAlways(
      "focused_row_index_set list=\(node.id.uuidString) old=\(String(describing: node.listFocusedRowIndex)) new=\(String(describing: nextFocusedRowIndex)) lazy=\(node.lazyListProviderId != nil) rows=\(node.lazyListProviderId == nil ? node.children.count : node.lazyListRowCount) visible=\(node.lazyListVisibleIndices.sorted())"
    )
    node.listFocusedRowIndex = nextFocusedRowIndex
  }
  if nextFocusedRowIndex == nil {
    BonsaiNativeKeyboardHandoff.shared.cancelHandoff()
  }
}

@_cdecl("bonsai_native_swiftui_set_on_click")
public func bonsai_native_swiftui_set_on_click(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.clickEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_navigation_link_callbacks")
public func bonsai_native_swiftui_set_navigation_link_callbacks(
  _ pointer: UnsafeMutableRawPointer?,
  _ activateEventId: Int32,
  _ deactivateEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.navigationActivateEventId = activateEventId < 0 ? nil : activateEventId
  node.navigationDeactivateEventId = deactivateEventId < 0 ? nil : deactivateEventId
}

@_cdecl("bonsai_native_swiftui_set_navigation_link_value")
public func bonsai_native_swiftui_set_navigation_link_value(
  _ pointer: UnsafeMutableRawPointer?,
  _ value: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.navigationLinkValue = value.map { String(cString: $0) }
}

@_cdecl("bonsai_native_swiftui_set_tap_action")
public func bonsai_native_swiftui_set_tap_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.tapEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_horizontal_swipe")
public func bonsai_native_swiftui_set_horizontal_swipe(
  _ pointer: UnsafeMutableRawPointer?,
  _ leftEventId: Int32,
  _ rightEventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.horizontalSwipeLeftEventId = leftEventId < 0 ? nil : leftEventId
  node.horizontalSwipeRightEventId = rightEventId < 0 ? nil : rightEventId
}

@_cdecl("bonsai_native_swiftui_set_on_appear")
public func bonsai_native_swiftui_set_on_appear(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.appearEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_on_change")
public func bonsai_native_swiftui_set_on_change(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.changeEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_list_row_subtitle")
public func bonsai_native_swiftui_set_list_row_subtitle(
  _ pointer: UnsafeMutableRawPointer?,
  _ subtitlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowSubtitle = subtitlePointer.map(String.init(cString:)) ?? ""
}

@_cdecl("bonsai_native_swiftui_set_list_row_trailing_text")
public func bonsai_native_swiftui_set_list_row_trailing_text(
  _ pointer: UnsafeMutableRawPointer?,
  _ trailingTextPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowTrailingText = trailingTextPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("bonsai_native_swiftui_set_list_row_content_style")
public func bonsai_native_swiftui_set_list_row_content_style(
  _ pointer: UnsafeMutableRawPointer?,
  _ contentStyle: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowContentStyle = contentStyle
}

@_cdecl("bonsai_native_swiftui_set_list_row_accessory")
public func bonsai_native_swiftui_set_list_row_accessory(
  _ pointer: UnsafeMutableRawPointer?,
  _ accessory: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowAccessory = accessory
}

@_cdecl("bonsai_native_swiftui_set_list_row_title_strikethrough")
public func bonsai_native_swiftui_set_list_row_title_strikethrough(
  _ pointer: UnsafeMutableRawPointer?,
  _ titleStrikethrough: Bool
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowTitleStrikethrough = titleStrikethrough
}

@_cdecl("bonsai_native_swiftui_set_list_row_leading_system_image")
public func bonsai_native_swiftui_set_list_row_leading_system_image(
  _ pointer: UnsafeMutableRawPointer?,
  _ systemImagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowStaticLeadingSystemImage = systemImagePointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_set_list_row_preview_image_path")
public func bonsai_native_swiftui_set_list_row_preview_image_path(
  _ pointer: UnsafeMutableRawPointer?,
  _ imagePathPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowPreviewImagePath = imagePathPointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_set_list_row_leading")
public func bonsai_native_swiftui_set_list_row_leading(
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

@_cdecl("bonsai_native_swiftui_set_list_row_leading_accessibility")
public func bonsai_native_swiftui_set_list_row_leading_accessibility(
  _ pointer: UnsafeMutableRawPointer?,
  _ labelPointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowLeadingAccessibilityLabel = labelPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("bonsai_native_swiftui_set_list_row_leading_event")
public func bonsai_native_swiftui_set_list_row_leading_event(
  _ pointer: UnsafeMutableRawPointer?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowLeadingEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_set_section")
public func bonsai_native_swiftui_set_section(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.sectionTitle = titlePointer.map(String.init(cString:)) ?? ""
}

@_cdecl("bonsai_native_swiftui_clear_picker")
public func bonsai_native_swiftui_clear_picker(
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

@_cdecl("bonsai_native_swiftui_append_picker_option")
public func bonsai_native_swiftui_append_picker_option(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.pickerOptions.append(
    BonsaiNativePickerOption(id: String(cString: idPointer), title: String(cString: titlePointer))
  )
}

@_cdecl("bonsai_native_swiftui_set_file_exporter")
public func bonsai_native_swiftui_set_file_exporter(
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

@_cdecl("bonsai_native_swiftui_set_share_link")
public func bonsai_native_swiftui_set_share_link(
  _ pointer: UnsafeMutableRawPointer?,
  _ urlPointer: UnsafePointer<CChar>?
) {
  nativeNode(from: pointer)?.shareURL = urlPointer.map(String.init(cString:)) ?? ""
}

@_cdecl("bonsai_native_swiftui_set_file_importer")
public func bonsai_native_swiftui_set_file_importer(
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

@_cdecl("bonsai_native_swiftui_set_slider")
public func bonsai_native_swiftui_set_slider(
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

@_cdecl("bonsai_native_swiftui_set_stepper")
public func bonsai_native_swiftui_set_stepper(
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

@_cdecl("bonsai_native_swiftui_set_date_picker")
public func bonsai_native_swiftui_set_date_picker(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ selectedPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.selectedDateText = selectedPointer.map(String.init(cString:)) ?? ""
  node.changeEventId = eventId < 0 ? nil : eventId
  bonsaiDatePickerDebugLogger.notice(
    "setDatePicker node=\(node.id.uuidString, privacy: .public) title=\(node.text, privacy: .public) selected=\(node.selectedDateText, privacy: .public) event=\(eventId, privacy: .public)"
  )
}

@_cdecl("bonsai_native_swiftui_set_color_picker")
public func bonsai_native_swiftui_set_color_picker(
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

@_cdecl("bonsai_native_swiftui_clear_menu")
public func bonsai_native_swiftui_clear_menu(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.text = titlePointer.map(String.init(cString:)) ?? ""
  node.systemImage = systemImagePointer.map(String.init(cString:))
  node.menuActions = []
}

@_cdecl("bonsai_native_swiftui_append_menu_action")
public func bonsai_native_swiftui_append_menu_action(
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
    BonsaiNativeMenuAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      style: style,
      isEnabled: isEnabled,
      eventId: eventId < 0 ? nil : eventId
    )
  )
}

@_cdecl("bonsai_native_swiftui_set_disclosure_group")
public func bonsai_native_swiftui_set_disclosure_group(
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

@_cdecl("bonsai_native_swiftui_set_navigation_path_stack")
public func bonsai_native_swiftui_set_navigation_path_stack(
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

@_cdecl("bonsai_native_swiftui_clear_list_row_actions")
public func bonsai_native_swiftui_clear_list_row_actions(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowActions = []
}

@_cdecl("bonsai_native_swiftui_append_list_row_action")
public func bonsai_native_swiftui_append_list_row_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let titlePointer else { return }
  node.rowActions.append(
    BonsaiNativeRowAction(
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

@_cdecl("bonsai_native_swiftui_clear_list_row_menu_actions")
public func bonsai_native_swiftui_clear_list_row_menu_actions(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.rowMenuActions = []
}

@_cdecl("bonsai_native_swiftui_append_list_row_menu_action")
public func bonsai_native_swiftui_append_list_row_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let titlePointer else { return }
  node.rowMenuActions.append(
    BonsaiNativeRowAction(
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

@_cdecl("bonsai_native_swiftui_clear_context_menu_actions")
public func bonsai_native_swiftui_clear_context_menu_actions(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.contextMenuActions = []
}

@_cdecl("bonsai_native_swiftui_append_context_menu_action")
public func bonsai_native_swiftui_append_context_menu_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ style: Int32,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let titlePointer else { return }
  node.contextMenuActions.append(
    BonsaiNativeRowAction(
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

@_cdecl("bonsai_native_swiftui_set_searchable")
public func bonsai_native_swiftui_set_searchable(
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

@_cdecl("bonsai_native_swiftui_set_sheet")
public func bonsai_native_swiftui_set_sheet(
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

@_cdecl("bonsai_native_swiftui_set_sheet_detents")
public func bonsai_native_swiftui_set_sheet_detents(
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
    BonsaiNativePresentationDetent(
      kind: kindsPointer[index],
      value: valuesPointer[index]
    )
  }
}

@_cdecl("bonsai_native_swiftui_set_safe_area_inset_bottom")
public func bonsai_native_swiftui_set_safe_area_inset_bottom(
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

@_cdecl("bonsai_native_swiftui_set_popover")
public func bonsai_native_swiftui_set_popover(
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

@_cdecl("bonsai_native_swiftui_set_alert")
public func bonsai_native_swiftui_set_alert(
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

@_cdecl("bonsai_native_swiftui_set_alert_text_field")
public func bonsai_native_swiftui_set_alert_text_field(
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

@_cdecl("bonsai_native_swiftui_clear_alert_actions")
public func bonsai_native_swiftui_clear_alert_actions(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.alertActions = []
}

@_cdecl("bonsai_native_swiftui_append_alert_action")
public func bonsai_native_swiftui_append_alert_action(
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
    BonsaiNativeAlertAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      role: role,
      isEnabled: isEnabled,
      eventId: eventId < 0 ? nil : eventId
    )
  )
}

@_cdecl("bonsai_native_swiftui_set_confirmation_dialog")
public func bonsai_native_swiftui_set_confirmation_dialog(
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

@_cdecl("bonsai_native_swiftui_clear_confirmation_dialog_actions")
public func bonsai_native_swiftui_clear_confirmation_dialog_actions(
  _ pointer: UnsafeMutableRawPointer?
) {
  nativeNode(from: pointer)?.confirmationDialogActions = []
}

@_cdecl("bonsai_native_swiftui_append_confirmation_dialog_action")
public func bonsai_native_swiftui_append_confirmation_dialog_action(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ role: Int32,
  _ isEnabled: Bool,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.confirmationDialogActions.append(
    BonsaiNativeAlertAction(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      role: role,
      isEnabled: isEnabled,
      eventId: eventId < 0 ? nil : eventId
    )
  )
}

@_cdecl("bonsai_native_swiftui_set_navigation_title")
public func bonsai_native_swiftui_set_navigation_title(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.navigationTitle = titlePointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_clear_toolbar")
public func bonsai_native_swiftui_clear_toolbar(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.toolbarItems = []
  node.toolbarContents = []
}

@_cdecl("bonsai_native_swiftui_append_toolbar_group")
public func bonsai_native_swiftui_append_toolbar_group(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ placement: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer else { return }
  node.toolbarContents.append(
    BonsaiNativeToolbarContent(
      id: String(cString: idPointer),
      kind: .group,
      placement: BonsaiNativeToolbarPlacement(rawValue: placement) ?? .automatic,
      fixed: false,
      items: []
    )
  )
}

@_cdecl("bonsai_native_swiftui_append_toolbar_spacer")
public func bonsai_native_swiftui_append_toolbar_spacer(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ placement: Int32,
  _ fixed: Bool
) {
  guard let node = nativeNode(from: pointer), let idPointer else { return }
  node.toolbarContents.append(
    BonsaiNativeToolbarContent(
      id: String(cString: idPointer),
      kind: .spacer,
      placement: BonsaiNativeToolbarPlacement(rawValue: placement) ?? .automatic,
      fixed: fixed,
      items: []
    )
  )
}

@_cdecl("bonsai_native_swiftui_clear_keyboard_toolbar")
public func bonsai_native_swiftui_clear_keyboard_toolbar(_ pointer: UnsafeMutableRawPointer?) {
  guard let node = nativeNode(from: pointer) else { return }
  node.keyboardToolbarItems = []
}

@_cdecl("bonsai_native_swiftui_append_toolbar_item")
public func bonsai_native_swiftui_append_toolbar_item(
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
    BonsaiNativeToolbarItem(
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

@_cdecl("bonsai_native_swiftui_append_toolbar_group_item")
public func bonsai_native_swiftui_append_toolbar_group_item(
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
    BonsaiNativeToolbarItem(
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

@_cdecl("bonsai_native_swiftui_append_keyboard_toolbar_item")
public func bonsai_native_swiftui_append_keyboard_toolbar_item(
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
    BonsaiNativeToolbarItem(
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

@_cdecl("bonsai_native_swiftui_append_toolbar_menu_action")
public func bonsai_native_swiftui_append_toolbar_menu_action(
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
  let action = BonsaiNativeRowAction(
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

@_cdecl("bonsai_native_swiftui_clear_tabs")
public func bonsai_native_swiftui_clear_tabs(
  _ pointer: UnsafeMutableRawPointer?,
  _ selectedPointer: UnsafePointer<CChar>?,
  _ eventId: Int32
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.tabs = []
  node.selectedTabId = selectedPointer.map(String.init(cString:)) ?? ""
  node.tabSelectEventId = eventId < 0 ? nil : eventId
}

@_cdecl("bonsai_native_swiftui_append_tab")
public func bonsai_native_swiftui_append_tab(
  _ pointer: UnsafeMutableRawPointer?,
  _ idPointer: UnsafePointer<CChar>?,
  _ titlePointer: UnsafePointer<CChar>?,
  _ systemImagePointer: UnsafePointer<CChar>?,
  _ role: Int32
) {
  guard let node = nativeNode(from: pointer), let idPointer, let titlePointer else { return }
  node.tabs.append(
    BonsaiNativeTab(
      id: String(cString: idPointer),
      title: String(cString: titlePointer),
      systemImage: systemImagePointer.map(String.init(cString:)),
      role: role
    )
  )
}

@_cdecl("bonsai_native_swiftui_clear_sidebar_shell")
public func bonsai_native_swiftui_clear_sidebar_shell(
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

@_cdecl("bonsai_native_swiftui_set_sidebar_header_action")
public func bonsai_native_swiftui_set_sidebar_header_action(
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
    node.sidebarHeaderAction = BonsaiNativeSidebarAction(
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

@_cdecl("bonsai_native_swiftui_append_sidebar_action")
public func bonsai_native_swiftui_append_sidebar_action(
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
    BonsaiNativeSidebarAction(
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

@_cdecl("bonsai_native_swiftui_append_sidebar_action_menu_action")
public func bonsai_native_swiftui_append_sidebar_action_menu_action(
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
    BonsaiNativeRowAction(
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

@_cdecl("bonsai_native_swiftui_set_sidebar_history_title")
public func bonsai_native_swiftui_set_sidebar_history_title(
  _ pointer: UnsafeMutableRawPointer?,
  _ titlePointer: UnsafePointer<CChar>?
) {
  guard let node = nativeNode(from: pointer) else { return }
  node.sidebarHistoryTitle = titlePointer.map(String.init(cString:))
}

@_cdecl("bonsai_native_swiftui_append_sidebar_history_action")
public func bonsai_native_swiftui_append_sidebar_history_action(
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
    BonsaiNativeSidebarAction(
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

@_cdecl("bonsai_native_swiftui_append_sidebar_history_action_menu_action")
public func bonsai_native_swiftui_append_sidebar_history_action_menu_action(
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
    BonsaiNativeRowAction(
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

@_cdecl("bonsai_native_swiftui_set_sidebar_bottom_action")
public func bonsai_native_swiftui_set_sidebar_bottom_action(
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
  node.sidebarBottomAction = BonsaiNativeSidebarAction(
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

@_cdecl("bonsai_native_swiftui_make_controller")
public func bonsai_native_swiftui_make_controller(
  _ rootPointer: UnsafeMutableRawPointer?,
  _ callback: BonsaiNativeEventCallback?
) -> UnsafeMutableRawPointer? {
  guard let root = nativeNode(from: rootPointer) else { return nil }
  let controller = makeHostingController(root: root, callback: callback)
  return Unmanaged.passRetained(controller).toOpaque()
}

@_cdecl("bonsai_native_swiftui_update_controller")
public func bonsai_native_swiftui_update_controller(
  _ controllerPointer: UnsafeMutableRawPointer?,
  _ rootPointer: UnsafeMutableRawPointer?
) {
  guard let controllerPointer, let root = nativeNode(from: rootPointer) else { return }
  let controller = Unmanaged<UIViewController>.fromOpaque(controllerPointer).takeUnretainedValue()
  if let model = objc_getAssociatedObject(controller, "BonsaiNativeSwiftUIModel") as? BonsaiNativeHostModel {
    model.root = root
    bindHostModel(model, to: root)
  }
}

@_cdecl("bonsai_native_swiftui_release_controller")
public func bonsai_native_swiftui_release_controller(_ controllerPointer: UnsafeMutableRawPointer?) {
  guard let controllerPointer else { return }
  Unmanaged<UIViewController>.fromOpaque(controllerPointer).release()
}

@_cdecl("bonsai_native_swiftui_make_window")
public func bonsai_native_swiftui_make_window(
  _ rootPointer: UnsafeMutableRawPointer?,
  _ callback: BonsaiNativeEventCallback?
) -> UnsafeMutableRawPointer? {
  guard let root = nativeNode(from: rootPointer) else { return nil }
  let window = UIWindow(frame: UIScreen.main.bounds)
  window.backgroundColor = bonsaiHomeBodyUIColor(for: window.traitCollection)
  window.rootViewController = makeHostingController(root: root, callback: callback)
  window.makeKeyAndVisible()
  return Unmanaged.passRetained(window).toOpaque()
}

@_cdecl("bonsai_native_swiftui_release_window")
public func bonsai_native_swiftui_release_window(_ windowPointer: UnsafeMutableRawPointer?) {
  guard let windowPointer else { return }
  Unmanaged<UIWindow>.fromOpaque(windowPointer).release()
}
