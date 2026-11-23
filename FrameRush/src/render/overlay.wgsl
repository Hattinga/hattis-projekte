@group(0) @binding(0) var overlay_sampler: sampler;
@group(0) @binding(1) var overlay_mask: texture_2d<f32>;

// The mask holds 1 where a glyph cell is lit. White text on a translucent
// black panel; black and white are the same in sRGB and linear.
@fragment
fn fs_overlay(in: VsOut) -> @location(0) vec4<f32> {
    let ink = textureSample(overlay_mask, overlay_sampler, in.uv).r;
    return mix(vec4<f32>(0.0, 0.0, 0.0, 0.65), vec4<f32>(1.0, 1.0, 1.0, 1.0), step(0.5, ink));
}
