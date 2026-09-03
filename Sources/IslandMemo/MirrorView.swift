import AVFoundation
import AppKit
import SwiftUI

/// 镜子：摄像头实时预览。离开视图即释放摄像头（NEVER 让摄像头常驻）。
/// 对应 TO-DO-Panel 首页的镜子组件（WebGL 水波特效不移植，保留核心预览）。
final class MirrorCameraController: NSObject, ObservableObject, @unchecked Sendable {
    @Published var permissionDenied = false
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "islandmemo.mirror")
    private var isConfigured = false
    private var wantsActive = false

    func start() {
        guard !isActive, !isStarting else { return }
        wantsActive = true
        isStarting = true
        permissionDenied = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.wantsActive else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.wantsActive = false
                        self.isStarting = false
                        self.permissionDenied = true
                    }
                }
            }
        default:
            wantsActive = false
            isStarting = false
            permissionDenied = true
        }
    }

    func stop() {
        wantsActive = false
        isStarting = false
        isActive = false
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.wantsActive = false
                        self.isStarting = false
                        self.permissionDenied = true
                    }
                    return
                }
                self.session.addInput(input)
                self.session.commitConfiguration()
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                guard self.wantsActive else {
                    self.stop()
                    return
                }
                self.isStarting = false
                self.isActive = true
            }
        }
    }
}

struct MirrorPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.previewLayer.session = session
        // 完整保留摄像头画面并居中，避免宽卡片使用 aspectFill 时放大、裁掉人物。
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: MirrorPreviewView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.previewLayer.videoGravity = .resizeAspect
    }
}

final class MirrorPreviewView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            let preview = AVCaptureVideoPreviewLayer()
            self.layer = preview
            return preview
        }
        return layer
    }

    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }
}

struct MirrorView: View {
    @ObservedObject var panelMetrics: PanelMetrics
    @StateObject private var controller = MirrorCameraController()

    var body: some View {
        ZStack {
            MirrorPreviewRepresentable(session: controller.session)
                // 预览层常驻，只启停摄像头会话，避免再次开启时重建图层失效。
                .scaleEffect(x: -1, y: 1)
                .opacity(controller.isActive ? 1 : 0)
                .allowsHitTesting(false)

            if controller.permissionDenied {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("没有摄像头权限")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Button("去开启") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else if controller.isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { controller.stop() }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "camera.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(8)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                            .allowsHitTesting(false)
                    }
            } else {
                Button { controller.start() } label: {
                    VStack(spacing: 9) {
                        Image(systemName: controller.isStarting ? "camera.aperture" : "camera.fill")
                            .font(.system(size: 25))
                        Text(controller.isStarting ? "正在打开摄像头…" : "点击开启镜子")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(controller.isStarting ? 0.72 : 0.48))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(
                            colors: [IslandTheme.surface2, IslandTheme.surface1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(controller.isStarting)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDisappear { controller.stop() }
        .onChange(of: panelMetrics.collapseRequest) { _ in controller.stop() }
    }
}
