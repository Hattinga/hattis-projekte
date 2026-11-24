// The renderer prepends `const SRGB_TARGET: bool = ...;`: true when the
// swapchain format is *Srgb, so the hardware re-encodes what we output.

@group(0) @binding(0) var frame_sampler: sampler;
@group(0) @binding(1) var plane0: texture_2d<f32>;
@group(0) @binding(2) var plane1: texture_2d<f32>;

// Y'CbCr -> R'G'B' parameters, written by the renderer from the frame's
// matrix (BT.601/BT.709) and range (limited/full). See `yuv_params` in mod.rs.
struct Yuv {
    // y' = (Y - y_offset) * y_scale, c' = (C - 128/255) * c_scale
    y_offset: f32,
    y_scale: f32,
    c_scale: f32,
    _pad: f32,
    // r = y' + x * cr', g = y' + y * cb' + z * cr', b = y' + w * cb'
    coeffs: vec4<f32>,
};
@group(0) @binding(3) var<uniform> yuv: Yuv;

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

@fragment
fn fs_nv12(in: VsOut) -> @location(0) vec4<f32> {
    let y = (textureSample(plane0, frame_sampler, in.uv).r - yuv.y_offset) * yuv.y_scale;
    let c = (textureSample(plane1, frame_sampler, in.uv).rg - vec2<f32>(128.0 / 255.0)) * yuv.c_scale;
    let rgb = vec3<f32>(
        y + yuv.coeffs.x * c.y,
        y + yuv.coeffs.y * c.x + yuv.coeffs.z * c.y,
        y + yuv.coeffs.w * c.x,
    );
    return to_target(clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.0)));
}
