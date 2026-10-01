import AppKit
import CMPV
import OpenGL.GL3
import SwiftUI

/// Resolves OpenGL entry points for libmpv's renderer.
private func mpvGetProcAddress(_ context: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}

/// Renders mpv frames via the libmpv render API into a CAOpenGLLayer (the approach IINA uses).
final class MPVVideoLayer: CAOpenGLLayer {
    private weak var player: MPVPlayer?
    private var renderContext: OpaquePointer?
    private var glContext: CGLContextObj?

    init(player: MPVPlayer) {
        self.player = player
        super.init()
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
    }

    override init(layer: Any) {
        let other = layer as? MPVVideoLayer
        player = other?.player
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attributes, &pixelFormat, &count)
        return pixelFormat ?? super.copyCGLPixelFormat(forDisplayMask: mask)
    }

    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        let context = super.copyCGLContext(forPixelFormat: pixelFormat)
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        releaseRenderContext()
        CGLSetCurrentContext(context)
        glContext = context
        createRenderContext()
        return context
    }

    override func canDraw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        true
    }

    override func draw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        guard let renderContext else { glFlush(); return }

        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &framebuffer)
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        var fbo = mpv_opengl_fbo(fbo: Int32(framebuffer), w: Int32(viewport[2]), h: Int32(viewport[3]), internal_format: 0)
        var flipY: Int32 = 1
        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
        glFlush()
    }

    private func createRenderContext() {
        let playerHandle: OpaquePointer? = MainActor.assumeIsolated { player?.handle }
        guard let handle = playerHandle else { return }
        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(get_proc_address: mpvGetProcAddress, get_proc_address_ctx: nil)
        var context: OpaquePointer?
        withUnsafeMutablePointer(to: &initParams) { initPointer in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                mpv_render_param(),
            ]
            _ = mpv_render_context_create(&context, handle, &params)
        }
        guard let context else { return }
        renderContext = context
        mpv_render_context_set_update_callback(context, { pointer in
            guard let pointer else { return }
            let layer = Unmanaged<MPVVideoLayer>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { layer.setNeedsDisplay() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Frees the render context with its GL context current, as libmpv requires.
    func releaseRenderContext() {
        guard let renderContext else { return }
        if let glContext { CGLSetCurrentContext(glContext) }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
    }
}

/// Layer-hosting view for the video surface. One instance lives for the app's lifetime so the
/// GL/mpv render context survives the player window closing and reopening.
final class MPVVideoView: NSView {
    let videoLayer: MPVVideoLayer

    init(player: MPVPlayer) {
        videoLayer = MPVVideoLayer(player: player)
        super.init(frame: .zero)
        layer = videoLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isOpaque: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
        videoLayer.setNeedsDisplay()
    }
}

struct VideoSurface: NSViewRepresentable {
    let view: MPVVideoView

    func makeNSView(context: Context) -> MPVVideoView { view }
    func updateNSView(_ nsView: MPVVideoView, context: Context) {}
}
