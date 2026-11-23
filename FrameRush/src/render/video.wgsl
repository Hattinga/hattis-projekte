// The renderer prepends `const SRGB_TARGET: bool = ...;`: true when the
// swapchain format is *Srgb, so the hardware re-encodes what we output.

@group(0) @binding(0) var frame_sampler: sampler;
@group(0) @binding(1) var plane0: texture_2d<f32>;
@group(0) @binding(2) var plane1: texture_2d<f32>;

fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    let low = c / 12.92;
    let high = pow((c + vec3<f32>(0.055)) / 1.055, vec3<f32>(2.4));
    return select(high, low, c <= vec3<f32>(0.04045));
}

// Video values are gamma-encoded (R'G'B'). A non-sRGB target takes them as
// they are; an sRGB target expects linear values and encodes them again.
fn to_target(rgb: vec3<f32>) -> vec4<f32> {
    if SRGB_TARGET {
        return vec4<f32>(srgb_to_linear(rgb), 1.0);
    }
    return vec4<f32>(rgb, 1.0);
}

@fragment
fn fs_bgra(in: VsOut) -> @location(0) vec4<f32> {
    return to_target(textureSample(plane0, frame_sampler, in.uv).rgb);
}

// NV12, BT.709, limited range: Y 16..235, CbCr 16..240 around 128.
// TODO(M2): a capture source must report its matrix (MF_MT_YUV_MATRIX) and
// range (MF_MT_VIDEO_NOMINAL_RANGE); this shader assumes BT.709 limited.
@fragment
fn fs_nv12(in: VsOut) -> @location(0) vec4<f32> {
    let y = (textureSample(plane0, frame_sampler, in.uv).r - 16.0 / 255.0) * (255.0 / 219.0);
    let c = (textureSample(plane1, frame_sampler, in.uv).rg - vec2<f32>(128.0 / 255.0)) * (255.0 / 224.0);
    let rgb = vec3<f32>(
        y + 1.5748 * c.y,
        y - 0.18733 * c.x - 0.46812 * c.y,
        y + 1.8556 * c.x,
    );
    return to_target(clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.0)));
}
