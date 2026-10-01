import AppKit
import CMPV
import OpenGL.GL3
import os
import SwiftUI

/// Resolves OpenGL entry points for libmpv's renderer.
private func mpvGetProcAddress(_ context: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}

/// Renders mpv frames via the libmpv render API into a CAOpenGLLayer.
///
/// The layer is asynchronous: Core Animation calls `canDraw`/`draw` on its own render thread every
/// display refresh, so video work never touches the main thread, and mpv may block that thread until
/// each frame's target time for smooth pacing. `lock` serialises the render context between that
/// thread and the main thread (which can release it at shutdown).
final class MPVVideoLayer: CAOpenGLLayer {
    private let handle: OpaquePointer?
    private let lock = NSLock()
    // Guarded by `lock`.
    private var renderContext: OpaquePointer?
    private var glContext: CGLContextObj?
    /// Separate from `lock` so a main-thread resize never waits behind a render blocked on frame timing.
    private let needsRedraw = OSAllocatedUnfairLock(initialState: true)

    init(handle: OpaquePointer?) {
        self.handle = handle
        super.init()
        isAsynchronous = true
        needsDisplayOnBoundsChange = true
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
    }

    override init(layer: Any) {
        handle = (layer as? MPVVideoLayer)?.handle
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A resize or scale change needs a re-render even when mpv has no new frame (e.g. while paused).
    override var bounds: CGRect {
        didSet { requestRedraw() }
    }

    func requestRedraw() {
        needsRedraw.withLock { $0 = true }
    }

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
        lock.withLock {
            freeRenderContextLocked()
            CGLSetCurrentContext(context)
            glContext = context
            createRenderContextLocked()
        }
        requestRedraw()
        return context
    }

    /// Core Animation may drop the GL context (display/GPU change); the mpv render context must go first,
    /// freed while that context is still valid and current.
    override func releaseCGLContext(_ context: CGLContextObj) {
        lock.withLock {
            if context == glContext {
                freeRenderContextLocked()
                glContext = nil
            }
        }
        super.releaseCGLContext(context)
    }

    /// Polled every refresh on the render thread; only draw when mpv has a new frame or a redraw is due.
    override func canDraw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        let forced = needsRedraw.withLock { $0 }
        return lock.withLock {
            guard let renderContext else { return forced }
            let flags = mpv_render_context_update(renderContext)
            return forced || flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
        }
    }

    override func draw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        needsRedraw.withLock { $0 = false }
        lock.withLock {
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
            mpv_render_context_report_swap(renderContext)
        }
    }

    /// Frees the render context; called from the main thread at shutdown.
    func releaseRenderContext() {
        lock.withLock { freeRenderContextLocked() }
    }

    // MARK: Lock held

    private func createRenderContextLocked() {
        guard let handle else { return }
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
        // No update callback: the asynchronous layer polls `mpv_render_context_update` each refresh.
        renderContext = context
    }

    /// libmpv requires the owning GL context to be current while freeing.
    private func freeRenderContextLocked() {
        guard let renderContext else { return }
        if let glContext { CGLSetCurrentContext(glContext) }
        mpv_render_context_free(renderContext)
        self.renderContext = nil
    }
}

/// Layer-hosting view for the video surface. One instance lives for the app's lifetime so the
/// GL/mpv render context survives the player window closing and reopening.
final class MPVVideoView: NSView {
    let videoLayer: MPVVideoLayer

    @MainActor
    init(player: MPVPlayer) {
        videoLayer = MPVVideoLayer(handle: player.handle)
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
        videoLayer.requestRedraw()
    }
}

struct VideoSurface: NSViewRepresentable {
    let view: MPVVideoView

    func makeNSView(context: Context) -> MPVVideoView { view }
    func updateNSView(_ nsView: MPVVideoView, context: Context) {}
}
