import AppKit
import MetalKit
import SwiftUI

/// GPU hourglass for the live overlay. Dock snapshots stay on SwiftUI Canvas
/// because `NSHostingView.cacheDisplay` does not capture Metal.
enum MetalHourglass {
    static var isAvailable: Bool { GPU.pipeline != nil }
}

private enum GPU {
    static let device = MTLCreateSystemDefaultDevice()
    static let queue = device?.makeCommandQueue()
    static let pipeline: MTLRenderPipelineState? = makePipeline()

    private static func makePipeline() -> MTLRenderPipelineState? {
        guard let device else { return nil }
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: options)
        } catch {
            NSLog("[Tokenrash] Metal shader: \(error)")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "tokenrash_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "tokenrash_glass")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let attach = descriptor.colorAttachments[0]!
        attach.isBlendingEnabled = true
        attach.sourceRGBBlendFactor = .one
        attach.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attach.sourceAlphaBlendFactor = .one
        attach.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("[Tokenrash] Metal pipeline: \(error)")
            return nil
        }
    }
}

struct MetalHourglassView: NSViewRepresentable {
    var remaining: Double
    var used: Double
    var siren: Bool
    var look: WidgetLook
    var running: Bool
    var reduceMotion: Bool

    func makeCoordinator() -> MetalHourglassRenderer {
        MetalHourglassRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        context.coordinator.makeView()
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.apply(
            view: view,
            remaining: remaining,
            used: used,
            siren: siren,
            look: look,
            running: running,
            reduceMotion: reduceMotion
        )
    }
}

final class MetalHourglassRenderer: NSObject, MTKViewDelegate {
    private var uniforms = HourglassUniforms()
    private let start = CACurrentMediaTime()

    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: GPU.device)
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 12
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        (view.layer as? CAMetalLayer)?.isOpaque = false
        return view
    }

    func apply(
        view: MTKView,
        remaining: Double,
        used: Double,
        siren: Bool,
        look: WidgetLook,
        running: Bool,
        reduceMotion: Bool
    ) {
        let flowing = remaining > 0.015 && remaining < 0.995 && used > 0.01
        let live = running && (siren || (!reduceMotion && flowing))
        view.isPaused = !live
        view.enableSetNeedsDisplay = !live
        view.preferredFramesPerSecond = siren ? 12 : 10
        fillUniforms(remaining: remaining, used: used, siren: siren, look: look, running: live, view: view)
        if view.isPaused {
            view.draw()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 2, view.drawableSize.height > 2 else { return }
        fillTime(view: view)
        guard let pipeline = GPU.pipeline,
              let queue = GPU.queue,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HourglassUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func fillTime(view: MTKView) {
        uniforms.b.w = Float(CACurrentMediaTime() - start)
        let scale = Float(view.window?.backingScaleFactor ?? max(view.layer?.contentsScale ?? 2, 1))
        let dw = Float(view.drawableSize.width)
        let dh = Float(view.drawableSize.height)
        uniforms.a.x = dw
        uniforms.a.y = dh
        let logical = CGSize(width: CGFloat(dw / scale), height: CGFloat(dh / scale))
        let glass = HourglassChrome.glassRect(in: logical, chrome: .instrument)
        uniforms.a.z = Float(glass.minX) * scale
        uniforms.a.w = Float(glass.minY) * scale
        uniforms.b.x = Float(glass.width) * scale
        uniforms.b.y = Float(glass.height) * scale
        if uniforms.e.x > 0.5 {
            uniforms.c.x = 0.5 + 0.5 * sin(uniforms.b.w * 8)
        } else {
            uniforms.c.x = 0
        }
    }

    private func fillUniforms(
        remaining: Double,
        used: Double,
        siren: Bool,
        look: WidgetLook,
        running: Bool,
        view: MTKView
    ) {
        let pulse = siren ? Double(uniforms.c.x) : 0
        uniforms.b.z = Float(remaining)
        uniforms.c.y = look.silhouette.metalID
        uniforms.c.z = Float(look.neck)
        uniforms.c.w = Float(look.bulb)
        uniforms.d.x = Float(look.streamWidth)
        uniforms.d.y = look.showTicks ? 1 : 0
        uniforms.d.z = Float(look.wobble)
        uniforms.d.w = running ? 1 : 0
        uniforms.e.x = siren ? 1 : 0
        uniforms.e.y = look.metalIndex
        uniforms.e.z = Float(used)
        uniforms.sand = Self.rgba(look.sand(remaining: remaining, siren: siren, pulse: pulse))
        uniforms.cavity = Self.rgba(look.cavityFill(siren: false, pulse: 0))
        uniforms.sirenTint = Self.rgba(look.cavityFill(siren: true, pulse: pulse))
        uniforms.highlight = Self.rgba(look.highlight)
        uniforms.metalLite = Self.rgba(look.metalLite)
        uniforms.metal = Self.rgba(look.metal)
        uniforms.metalDark = Self.rgba(look.metalDark)
        fillTime(view: view)
    }

    private static func rgba(_ color: Color) -> SIMD4<Float> {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return SIMD4(0, 0, 0, 1) }
        return SIMD4(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent)
        )
    }
}

/// Packed float4s only, so Swift and Metal agree on layout.
private struct HourglassUniforms {
    var a = SIMD4<Float>() // size.xy, glass.xy (pixels)
    var b = SIMD4<Float>() // glass.wh, remaining, time
    var c = SIMD4<Float>() // pulse, silhouette, neck, bulb
    var d = SIMD4<Float>() // streamWidth, showTicks, wobble, running
    var e = SIMD4<Float>() // siren, lookIndex, used
    var sand = SIMD4<Float>()
    var cavity = SIMD4<Float>()
    var sirenTint = SIMD4<Float>()
    var highlight = SIMD4<Float>()
    var metalLite = SIMD4<Float>()
    var metal = SIMD4<Float>()
    var metalDark = SIMD4<Float>()
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 a, b, c, d, e;
    float4 sand, cavity, sirenTint, highlight, metalLite, metal, metalDark;
};

struct VertOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertOut tokenrash_vertex(uint vid [[vertex_id]]) {
    float2 corners[4] = { float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0) };
    float2 c = corners[vid];
    VertOut out;
    out.position = float4(c, 0.0, 1.0);
    // Clip Y is up; UV Y is down so it matches SwiftUI glassRect.
    out.uv = float2((c.x + 1.0) * 0.5, (1.0 - c.y) * 0.5);
    return out;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.21));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float2 hash22(float2 p) {
    float n = hash21(p);
    return float2(n, hash21(p + n + 19.19));
}

float voronoi(float2 p) {
    float2 n = floor(p);
    float2 f = fract(p);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 g = float2(i, j);
            float2 o = hash22(n + g);
            float2 r = g + o - f;
            md = min(md, dot(r, r));
        }
    }
    return sqrt(md);
}

float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-4));
    return length(pa - ba * h) - r;
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.07 + 1.3;
        a *= 0.5;
    }
    return v;
}

float halfWidth(float y, float2 glassXY, float2 glassWH, float neckN, float bulbN, float sil) {
    float t = clamp((y - glassXY.y) / max(glassWH.y, 1.0), 0.0, 1.0);
    float d = abs(t - 0.5) * 2.0;
    float blend = d * d * (3.0 - 2.0 * d);
    if (sil > 0.5 && sil < 1.5) blend = pow(max(d, 1e-4), 2.35);
    else if (sil > 2.5 && sil < 3.5) blend = d;
    else if (sil > 3.5) blend = d * d;
    float neck = glassWH.x * neckN;
    float bulb = glassWH.x * bulbN;
    return neck + (bulb - neck) * blend;
}

float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

fragment float4 tokenrash_glass(VertOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = in.uv * float2(u.a.x, u.a.y);
    float2 glassXY = float2(u.a.z, u.a.w);
    float2 glassWH = float2(u.b.x, u.b.y);
    float px = max(length(fwidth(p)), 1.0);
    float cx = glassXY.x + glassWH.x * 0.5;
    float topY = glassXY.y;
    float botY = glassXY.y + glassWH.y;
    float neckY = glassXY.y + glassWH.y * 0.5;
    float hw = halfWidth(p.y, glassXY, glassWH, u.c.z, u.c.w, u.c.y);
    float sd = abs(p.x - cx) - hw;
    float look = u.e.y;
    float remaining = u.b.z;
    float used = u.e.z;
    float time = u.b.w;
    float wobble = max(u.d.z, 0.12);
    float siren = u.e.x;
    float jelly = look > 3.5 ? 1.0 : 0.0;
    float telemetry = (look > 2.5 && look < 3.5) ? 1.0 : 0.0;
    float aa = mix(1.8, 3.4, jelly) * px;

    float3 sandHi = u.sand.rgb;
    float3 sandLo = u.sand.rgb * float3(0.38, 0.34, 0.28);

    float glowRad = (siren > 0.5 || (remaining < 0.22 && remaining + used > 0.05)) ? 42.0 : 22.0;
    float glow = pow(saturate(1.0 - sd / glowRad), mix(2.8, 1.8, jelly));
    float3 glowCol = mix(sandHi, u.sirenTint.rgb, siren);
    float4 color = float4(glowCol * glow * mix(0.22, 0.62, siren), glow * mix(0.16, 0.5, siren));

    float wall = mix(3.2, 5.5, jelly) * px;
    float glass = 1.0 - smoothstep(0.0, aa, sd);
    float inner = 1.0 - smoothstep(0.0, aa, sd + wall);
    if (glass < 0.002 && sd > glowRad * 0.45) {
        return float4(color.rgb, color.a);
    }

    float g1 = voronoi(p / (2.8 * px));
    float g2 = voronoi(p / (1.25 * px) + 6.1);
    float n = fbm(p * 0.25);
    float grit = mix(0.08, 1.0, n);
    grit = mix(grit, 1.0, smoothstep(0.5, 0.02, g1) * 0.85);
    grit *= 0.45 + 0.55 * smoothstep(0.6, 0.0, g2);
    float3 sandCol = mix(sandLo, sandHi, saturate(grit));
    sandCol *= 0.85 + 0.15 * saturate((-sd - wall) / (16.0 * px));
    if (u.d.y > 0.5) {
        sandCol *= 0.82 + 0.18 * sin(p.y * 0.55 + n * 4.0);
    }
    if (telemetry > 0.5) {
        sandCol *= 0.78 + 0.22 * step(0.4, fract(p.y * 0.09));
    }

    float vig = saturate((-sd - wall * 0.3) / max(hw, 1.0));
    float fres = pow(1.0 - saturate((-sd) / max(hw * 0.55, 2.0)), 2.8);
    float3 cav = u.cavity.rgb * (0.28 + 0.72 * vig);
    cav += u.highlight.rgb * fres * mix(0.55, 0.9, jelly);
    float2 q = (p - float2(cx, neckY)) / max(glassWH.y, 1.0);
    cav += u.highlight.rgb * 0.12 * pow(saturate(1.0 - length(q * float2(1.8, 1.0))), 3.0);
    float4 inside = float4(cav, max(u.cavity.a, 0.72));

    // UV Y grows downward. Remaining sits in the top bulb, on the neck.
    // Spent sits in the bottom bulb, on the floor.
    float topChamber = max(neckY - topY - 12.0 * px, 8.0);
    float topH = max(remaining > 0.01 ? 8.0 : 0.0, topChamber * remaining);
    float topSurface = neckY - topH + (fbm(float2(p.x * 0.05, 2.1)) - 0.5) * 5.0 * wobble * px;
    float inTop = 0.0;
    if (remaining > 0.01) {
        inTop = saturate(smoothstep(topSurface - 2.0 * px, topSurface + 2.0 * px, p.y)
              * (1.0 - smoothstep(neckY - 2.0 * px, neckY + 1.0 * px, p.y)));
    }

    float botChamber = max(botY - neckY - 12.0 * px, 8.0);
    float botH = max(used > 0.01 ? 8.0 : 0.0, botChamber * used);
    float botSurface = botY - botH + (fbm(float2(p.x * 0.045, 9.4)) - 0.5) * 5.0 * wobble * px;
    float inBot = 0.0;
    if (used > 0.01) {
        inBot = saturate(smoothstep(botSurface - 2.0 * px, botSurface + 2.0 * px, p.y)
              * (1.0 - smoothstep(botY - 4.0 * px, botY - 0.5 * px, p.y)));
    }

    float inSand = max(inTop, inBot) * inner;
    if (inSand > 0.004) {
        inside.rgb = mix(inside.rgb, sandCol, saturate(inSand));
        inside.a = max(inside.a, 0.97 * inSand);
    }

    float inAir = inner * (1.0 - saturate(inSand * 1.6))
                * smoothstep(neckY - 4.0 * px, neckY + 2.0 * px, p.y)
                * (1.0 - smoothstep(botSurface - 6.0 * px, botSurface + 2.0 * px, p.y));

    float halfS = max(u.d.x * 1.8, 3.4) * px;
    if (remaining > 0.01 && remaining < 0.995) {
        float core = exp(-pow((p.x - cx) / (halfS * 0.42), 2.0));
        float halo = exp(-pow((p.x - cx) / halfS, 2.0));
        float stream = mix(halo * 0.62, 1.0, core) * inAir;
        stream *= 0.78 + 0.22 * noise(float2(p.y * 0.28, time * 4.2));
        inside.rgb = mix(inside.rgb, sandCol, saturate(stream));
        inside.a = max(inside.a, stream * 0.94);
    }

    if (u.d.w > 0.5 && remaining > 0.015 && remaining < 0.995) {
        float grains = 0.0;
        for (int i = 0; i < 22; i++) {
            float seed = float(i) * 13.9;
            float2 h = hash22(float2(seed, 2.6));
            float fall = fract(time * (0.18 + 0.16 * h.x) + h.y);
            fall = fall * fall * (3.0 - 2.0 * fall);
            float2 a = float2(cx + (h.x - 0.5) * halfS * 1.55, mix(neckY - 2.0 * px, botSurface, fall));
            float2 b = a + float2((h.y - 0.5) * 2.2 * px, 7.0 * px);
            float rad = mix(2.0, 4.2, jelly) * px * (0.75 + 0.55 * h.x);
            grains += 1.0 - saturate(sdCapsule(p, a, b, rad) / max(px, 0.6));
        }
        grains = saturate(grains) * inAir;
        inside.rgb = mix(inside.rgb, sandCol, grains);
        inside.a = max(inside.a, grains);
    }

    float spec = pow(saturate(1.0 - abs((p.x - (cx - hw * 0.42)) / max(hw * 0.18, 2.0 * px))), 8.0);
    spec *= saturate((neckY - 8.0 * px - p.y) / max(neckY - topY, 1.0));
    spec *= mix(0.4, 0.85, jelly) * (1.0 - 0.65 * inSand);
    inside.rgb += u.highlight.rgb * spec;

    float rim = saturate(1.0 - abs(sd + wall * 0.5) / (wall * 0.85 + aa));
    inside.rgb = mix(inside.rgb, mix(u.metalLite.rgb, u.highlight.rgb, 0.5), rim * 0.35 * (1.0 - inner * 0.4));

    if (siren > 0.5) {
        inside.rgb = mix(inside.rgb, u.sirenTint.rgb, 0.18 + 0.45 * u.c.x);
    }

    float topW = hw + 8.0 * px;
    float topBand = 1.0 - smoothstep(0.7 * px, 2.6 * px, abs(sdBox(p - float2(cx, topY - 1.0 * px), float2(topW, 5.0 * px))));
    float botW = halfWidth(botY, glassXY, glassWH, u.c.z, u.c.w, u.c.y) + 8.0 * px;
    float botBand = 1.0 - smoothstep(0.7 * px, 2.6 * px, abs(sdBox(p - float2(cx, botY + 1.0 * px), float2(botW, 5.0 * px))));
    float collar = max(topBand, botBand);
    if (collar > 0.01) {
        float shade = saturate((p.x - cx + topW) / max(topW * 2.0, 1.0));
        float3 met = mix(u.metalLite.rgb, u.metalDark.rgb, shade);
        met = mix(met, u.metal.rgb, 0.32);
        met += u.highlight.rgb * pow(saturate(1.0 - abs(shade - 0.28) * 3.0), 4.0) * 0.25;
        inside.rgb = mix(inside.rgb, met, saturate(collar));
        inside.a = max(inside.a, collar);
        glass = max(glass, collar);
    }

    float3 rgb = mix(color.rgb, inside.rgb, glass);
    float a = max(color.a * (1.0 - glass), inside.a * glass);
    return float4(rgb * a, a);
}
"""
