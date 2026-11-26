//! GPU presentation with wgpu (DX12).
//!
//! Frames are uploaded with `Queue::write_texture` into one texture per plane
//! (BGRA8: one; NV12: Y as R8 + CbCr as RG8) and converted to RGB in the
//! fragment shader. Video is letterboxed with the viewport; the statistics
//! overlay is a small R8 mask texture drawn with alpha blending.
//!
//! Present path order matters for latency: the caller first acquires the
//! swapchain image ([`Renderer::acquire`], which is where FIFO/frame-latency
//! waits happen), *then* takes the newest frame from the mailbox, uploads and
//! presents. Taking first would show a frame that went stale while waiting.

use std::sync::Arc;

use winit::dpi::PhysicalSize;
use winit::window::Window;

use crate::capture::{ColorSpace, Frame, PixelFormat, YuvMatrix, YuvRange};
use crate::cli::PresentModeChoice;
use crate::font;

const COMMON_WGSL: &str = include_str!("common.wgsl");
const VIDEO_WGSL: &str = include_str!("video.wgsl");
const OVERLAY_WGSL: &str = include_str!("overlay.wgsl");

/// Overlay position from the top-left corner, in logical pixels.
const OVERLAY_MARGIN: f64 = 12.0;
/// Overlay text size: physical pixels per font cell at 100 % DPI scaling.
const OVERLAY_CELL: f64 = 2.0;

pub struct RendererOptions {
    pub present_mode: PresentModeChoice,
    pub frame_latency: u32,
}

/// What the renderer actually got (may differ from what was requested).
#[derive(Debug, Clone)]
pub struct RendererInfo {
    pub adapter: String,
    pub backend: String,
    pub present_mode: wgpu::PresentMode,
    pub surface_format: wgpu::TextureFormat,
    pub frame_latency: u32,
}

#[derive(Debug)]
pub struct RenderError(String);

impl std::fmt::Display for RenderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for RenderError {}

struct Pipeline {
    pipeline: wgpu::RenderPipeline,
    layout: wgpu::BindGroupLayout,
}

struct VideoTextures {
    format: PixelFormat,
    width: u32,
    height: u32,
    planes: Vec<wgpu::Texture>,
    bind_group: wgpu::BindGroup,
}

struct OverlayTexture {
    width: u32,
    height: u32,
    texture: wgpu::Texture,
    bind_group: wgpu::BindGroup,
}

pub struct Renderer {
    window: Arc<Window>,
    instance: wgpu::Instance,
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    /// False while the window has zero size (minimized).
    configured: bool,
    reconfigure_after_present: bool,
    bgra: Pipeline,
    nv12: Pipeline,
    overlay_pipeline: Pipeline,
    linear_sampler: wgpu::Sampler,
    nearest_sampler: wgpu::Sampler,
    /// Y'CbCr parameters for the NV12 shader (see [`yuv_params`]).
    yuv_buffer: wgpu::Buffer,
    /// Colour space currently in `yuv_buffer`.
    yuv_color: Option<ColorSpace>,
    video: Option<VideoTextures>,
    overlay: Option<OverlayTexture>,
    info: RendererInfo,
}

impl Renderer {
    pub fn new(window: Arc<Window>, options: &RendererOptions) -> Result<Self, RenderError> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::DX12,
            ..wgpu::InstanceDescriptor::new_without_display_handle()
        });
        let surface = instance.create_surface(Arc::clone(&window)).map_err(|e| {
            RenderError(format!("cannot create a DX12 surface for the window: {e}"))
        })?;
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: Some(&surface),
            ..Default::default()
        }))
        .map_err(|e| {
            RenderError(format!(
                "no DX12 GPU adapter can present to this window: {e}"
            ))
        })?;
        let adapter_info = adapter.get_info();
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("framerush"),
            ..Default::default()
        }))
        .map_err(|e| RenderError(format!("cannot open the GPU device: {e}")))?;
        device.set_device_lost_callback(|reason, message| {
            tracing::error!(?reason, %message, "GPU device lost");
        });

        let caps = surface.get_capabilities(&adapter);
        // Prefer a non-sRGB target: video values are already gamma-encoded
        // and pass through unchanged. The shader handles sRGB targets too.
        let format = caps
            .formats
            .iter()
            .copied()
            .find(|f| {
                matches!(
                    f,
                    wgpu::TextureFormat::Bgra8Unorm | wgpu::TextureFormat::Rgba8Unorm
                )
            })
            .or_else(|| caps.formats.first().copied())
            .ok_or_else(|| RenderError("the window surface reports no usable formats".into()))?;
        let requested = match options.present_mode {
            PresentModeChoice::Fifo => wgpu::PresentMode::Fifo,
            PresentModeChoice::Mailbox => wgpu::PresentMode::Mailbox,
            PresentModeChoice::Immediate => wgpu::PresentMode::Immediate,
        };
        let present_mode = if caps.present_modes.contains(&requested) {
            requested
        } else {
            tracing::warn!(?requested, supported = ?caps.present_modes, "present mode not supported, using Fifo");
            wgpu::PresentMode::Fifo
        };
        let alpha_mode = if caps.alpha_modes.contains(&wgpu::CompositeAlphaMode::Opaque) {
            wgpu::CompositeAlphaMode::Opaque
        } else {
            caps.alpha_modes
                .first()
                .copied()
                .unwrap_or(wgpu::CompositeAlphaMode::Auto)
        };
        let size = window.inner_size();
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            color_space: wgpu::SurfaceColorSpace::Auto,
            width: size.width.max(1),
            height: size.height.max(1),
            present_mode,
            desired_maximum_frame_latency: options.frame_latency,
            alpha_mode,
            view_formats: Vec::new(),
        };
        let configured = size.width > 0 && size.height > 0;
        if configured {
            surface.configure(&device, &config);
        }

        let video_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("video"),
            source: wgpu::ShaderSource::Wgsl(
                format!(
                    "const SRGB_TARGET: bool = {};\n{COMMON_WGSL}\n{VIDEO_WGSL}",
                    format.is_srgb()
                )
                .into(),
            ),
        });
        let overlay_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("overlay"),
            source: wgpu::ShaderSource::Wgsl(format!("{COMMON_WGSL}\n{OVERLAY_WGSL}").into()),
        });
        let bgra = create_pipeline(&device, &video_module, "fs_bgra", 1, false, format, None);
        let nv12 = create_pipeline(&device, &video_module, "fs_nv12", 2, true, format, None);
        let overlay_pipeline = create_pipeline(
            &device,
            &overlay_module,
            "fs_overlay",
            1,
            false,
            format,
            Some(wgpu::BlendState::ALPHA_BLENDING),
        );
        let yuv_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("yuv params"),
            size: YUV_PARAMS_SIZE,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let sampler = |filter| {
            device.create_sampler(&wgpu::SamplerDescriptor {
                label: Some("frame sampler"),
                mag_filter: filter,
                min_filter: filter,
                ..Default::default()
            })
        };
        let linear_sampler = sampler(wgpu::FilterMode::Linear);
        let nearest_sampler = sampler(wgpu::FilterMode::Nearest);

        let info = RendererInfo {
            adapter: adapter_info.name.clone(),
            backend: format!("{:?}", adapter_info.backend),
            present_mode,
            surface_format: format,
            frame_latency: options.frame_latency,
        };
        tracing::info!(
            adapter = %info.adapter,
            backend = %info.backend,
            driver = %adapter_info.driver_info,
            format = ?format,
            present_mode = ?present_mode,
            supported_present_modes = ?caps.present_modes,
            frame_latency = options.frame_latency,
            "renderer ready"
        );

        Ok(Self {
            window,
            instance,
            surface,
            device,
            queue,
            config,
            configured,
            reconfigure_after_present: false,
            bgra,
            nv12,
            overlay_pipeline,
            linear_sampler,
            nearest_sampler,
            yuv_buffer,
            yuv_color: None,
            video: None,
            overlay: None,
            info,
        })
    }

    pub fn info(&self) -> &RendererInfo {
        &self.info
    }

    pub fn resize(&mut self, size: PhysicalSize<u32>) {
        self.configured = size.width > 0 && size.height > 0;
        if self.configured {
            self.config.width = size.width;
            self.config.height = size.height;
            self.surface.configure(&self.device, &self.config);
        }
    }

    /// Gets the next swapchain image. This is where the present mode and frame
    /// latency make the thread wait. `None` means: skip this frame.
    pub fn acquire(&mut self) -> Option<wgpu::SurfaceTexture> {
        let target = self.try_acquire();
        if target.is_none() {
            // `write_texture`/`write_buffer` only stage the data; wgpu sends
            // it (and later frees the staging memory) with the next submit.
            // Without a present (minimized window) nothing else submits, and
            // ~3 MB per 1080p frame piled up until the GPU ran out of memory.
            // An empty submit flushes whatever is pending.
            self.queue.submit(std::iter::empty());
        }
        target
    }

    fn try_acquire(&mut self) -> Option<wgpu::SurfaceTexture> {
        if !self.configured {
            return None;
        }
        for attempt in 0..2 {
            match self.surface.get_current_texture() {
                wgpu::CurrentSurfaceTexture::Success(texture) => return Some(texture),
                wgpu::CurrentSurfaceTexture::Suboptimal(texture) => {
                    self.reconfigure_after_present = true;
                    return Some(texture);
                }
                wgpu::CurrentSurfaceTexture::Timeout | wgpu::CurrentSurfaceTexture::Occluded => {
                    return None;
                }
                wgpu::CurrentSurfaceTexture::Outdated if attempt == 0 => {
                    self.surface.configure(&self.device, &self.config);
                }
                wgpu::CurrentSurfaceTexture::Lost if attempt == 0 => {
                    tracing::warn!("surface lost, recreating it");
                    if let Err(err) = self.recreate_surface() {
                        tracing::error!(%err, "cannot recreate the surface");
                        return None;
                    }
                }
                other => {
                    tracing::warn!(status = ?other, "no swapchain image, skipping frame");
                    return None;
                }
            }
        }
        None
    }

    fn recreate_surface(&mut self) -> Result<(), RenderError> {
        self.surface = self
            .instance
            .create_surface(Arc::clone(&self.window))
            .map_err(|e| RenderError(e.to_string()))?;
        self.surface.configure(&self.device, &self.config);
        Ok(())
    }

    /// Copies `frame` into the video textures (recreating them if size or
    /// format changed). Call it only for a frame that will be presented: the
    /// copy is sent to the GPU with the next submit.
    pub fn upload_frame(&mut self, frame: &Frame) {
        if frame.format.frame_len(frame.width, frame.height) != Some(frame.data.len()) {
            tracing::warn!(
                sequence = frame.sequence,
                len = frame.data.len(),
                "frame buffer size does not match its format, dropped"
            );
            return;
        }
        let up_to_date = self.video.as_ref().is_some_and(|v| {
            v.format == frame.format && v.width == frame.width && v.height == frame.height
        });
        if !up_to_date {
            self.video = Some(self.create_video_textures(frame.format, frame.width, frame.height));
        }
        if frame.format == PixelFormat::Nv12 && self.yuv_color != Some(frame.color) {
            let bytes: Vec<u8> = yuv_params(frame.color)
                .iter()
                .flat_map(|v| v.to_le_bytes())
                .collect();
            self.queue.write_buffer(&self.yuv_buffer, 0, &bytes);
            self.yuv_color = Some(frame.color);
            tracing::info!(color = %frame.color, "YUV colour space");
        }
        let video = self.video.as_ref().expect("created above");
        let (w, h) = (frame.width, frame.height);
        match frame.format {
            PixelFormat::Bgra8 => {
                write_plane(&self.queue, &video.planes[0], &frame.data, w * 4, w, h)
            }
            PixelFormat::Nv12 => {
                let (luma, chroma) = frame.data.split_at(w as usize * h as usize);
                write_plane(&self.queue, &video.planes[0], luma, w, w, h);
                // w/2 CbCr pairs of 2 bytes each = w bytes per row.
                write_plane(&self.queue, &video.planes[1], chroma, w, w / 2, h / 2);
            }
        }
    }

    fn create_video_textures(&self, format: PixelFormat, width: u32, height: u32) -> VideoTextures {
        let plane = |label, format, width, height| {
            self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some(label),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            })
        };
        let (planes, pipeline) = match format {
            PixelFormat::Bgra8 => (
                vec![plane(
                    "bgra",
                    wgpu::TextureFormat::Bgra8Unorm,
                    width,
                    height,
                )],
                &self.bgra,
            ),
            PixelFormat::Nv12 => (
                vec![
                    plane("nv12 luma", wgpu::TextureFormat::R8Unorm, width, height),
                    plane(
                        "nv12 chroma",
                        wgpu::TextureFormat::Rg8Unorm,
                        width / 2,
                        height / 2,
                    ),
                ],
                &self.nv12,
            ),
        };
        let views: Vec<_> = planes
            .iter()
            .map(|t| t.create_view(&Default::default()))
            .collect();
        let mut entries = vec![wgpu::BindGroupEntry {
            binding: 0,
            resource: wgpu::BindingResource::Sampler(&self.linear_sampler),
        }];
        entries.extend(
            views
                .iter()
                .zip(1..)
                .map(|(view, binding)| wgpu::BindGroupEntry {
                    binding,
                    resource: wgpu::BindingResource::TextureView(view),
                }),
        );
        if format == PixelFormat::Nv12 {
            entries.push(wgpu::BindGroupEntry {
                binding: 3,
                resource: self.yuv_buffer.as_entire_binding(),
            });
        }
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("video"),
            layout: &pipeline.layout,
            entries: &entries,
        });
        tracing::info!(
            format = format.name(),
            width,
            height,
            "video textures created"
        );
        VideoTextures {
            format,
            width,
            height,
            planes,
            bind_group,
        }
    }

    /// Rasterizes `lines` with the built-in font into the overlay mask.
    pub fn set_overlay_text(&mut self, lines: &[String]) {
        const PAD: usize = 2;
        const LINE_GAP: usize = 3;
        if lines.is_empty() {
            self.overlay = None;
            return;
        }
        let cols = lines.iter().map(|l| font::text_width(l)).max().unwrap_or(0) + 2 * PAD;
        let rows = lines.len() * (font::GLYPH_HEIGHT + LINE_GAP) - LINE_GAP + 2 * PAD;
        let mut mask = vec![0u8; cols * rows];
        for (i, line) in lines.iter().enumerate() {
            let top = PAD + i * (font::GLYPH_HEIGHT + LINE_GAP);
            font::rasterize(line, |x, y| mask[(top + y) * cols + PAD + x] = 255);
        }
        let (width, height) = (cols as u32, rows as u32);
        if self
            .overlay
            .as_ref()
            .is_none_or(|o| o.width != width || o.height != height)
        {
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("overlay"),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::R8Unorm,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            let view = texture.create_view(&Default::default());
            let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("overlay"),
                layout: &self.overlay_pipeline.layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::Sampler(&self.nearest_sampler),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::TextureView(&view),
                    },
                ],
            });
            self.overlay = Some(OverlayTexture {
                width,
                height,
                texture,
                bind_group,
            });
        }
        let overlay = self.overlay.as_ref().expect("created above");
        write_plane(&self.queue, &overlay.texture, &mask, width, width, height);
    }

    /// Draws the current video texture (letterboxed) and optionally the
    /// overlay into `target`, then presents it.
    pub fn draw_and_present(&mut self, target: wgpu::SurfaceTexture, show_overlay: bool) {
        let view = target.texture.create_view(&Default::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("frame"),
            });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("frame"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                ..Default::default()
            });
            let (target_w, target_h) = (self.config.width, self.config.height);
            if let Some(video) = &self.video {
                let [x, y, w, h] = fit_rect(video.width, video.height, target_w, target_h);
                let pipeline = match video.format {
                    PixelFormat::Bgra8 => &self.bgra,
                    PixelFormat::Nv12 => &self.nv12,
                };
                pass.set_viewport(x, y, w, h, 0.0, 1.0);
                pass.set_pipeline(&pipeline.pipeline);
                pass.set_bind_group(0, &video.bind_group, &[]);
                pass.draw(0..3, 0..1);
            }
            if show_overlay && let Some(overlay) = &self.overlay {
                let scale = self.window.scale_factor();
                let cell = (OVERLAY_CELL * scale).round().max(1.0) as f32;
                let margin = (OVERLAY_MARGIN * scale).round() as f32;
                let w = (overlay.width as f32 * cell)
                    .min(target_w as f32 - margin)
                    .max(1.0);
                let h = (overlay.height as f32 * cell)
                    .min(target_h as f32 - margin)
                    .max(1.0);
                pass.set_viewport(margin, margin, w, h, 0.0, 1.0);
                pass.set_pipeline(&self.overlay_pipeline.pipeline);
                pass.set_bind_group(0, &overlay.bind_group, &[]);
                pass.draw(0..3, 0..1);
            }
        }
        self.queue.submit([encoder.finish()]);
        self.window.pre_present_notify();
        self.queue.present(target);
        if self.reconfigure_after_present {
            self.reconfigure_after_present = false;
            self.surface.configure(&self.device, &self.config);
        }
    }
}

/// `textures` sampled planes at bindings 1..; with `yuv_uniform`, the YUV
/// parameter buffer at binding 3.
fn create_pipeline(
    device: &wgpu::Device,
    module: &wgpu::ShaderModule,
    fragment_entry: &str,
    textures: u32,
    yuv_uniform: bool,
    target: wgpu::TextureFormat,
    blend: Option<wgpu::BlendState>,
) -> Pipeline {
    let mut entries = vec![wgpu::BindGroupLayoutEntry {
        binding: 0,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
        count: None,
    }];
    entries.extend((1..=textures).map(|binding| wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Texture {
            sample_type: wgpu::TextureSampleType::Float { filterable: true },
            view_dimension: wgpu::TextureViewDimension::D2,
            multisampled: false,
        },
        count: None,
    }));
    if yuv_uniform {
        entries.push(wgpu::BindGroupLayoutEntry {
            binding: 3,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Uniform,
                has_dynamic_offset: false,
                min_binding_size: wgpu::BufferSize::new(YUV_PARAMS_SIZE),
            },
            count: None,
        });
    }
    let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some(fragment_entry),
        entries: &entries,
    });
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some(fragment_entry),
        bind_group_layouts: &[Some(&layout)],
        immediate_size: 0,
    });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some(fragment_entry),
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module,
            entry_point: Some("vs_fullscreen"),
            compilation_options: Default::default(),
            buffers: &[],
        },
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        fragment: Some(wgpu::FragmentState {
            module,
            entry_point: Some(fragment_entry),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: target,
                blend,
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        multiview_mask: None,
        cache: None,
    });
    Pipeline { pipeline, layout }
}

fn write_plane(
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    data: &[u8],
    bytes_per_row: u32,
    width: u32,
    height: u32,
) {
    queue.write_texture(
        wgpu::TexelCopyTextureInfo {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        data,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(bytes_per_row),
            rows_per_image: Some(height),
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
}

/// Size of the `Yuv` uniform in video.wgsl: 8 x f32.
const YUV_PARAMS_SIZE: u64 = 32;

/// Uniform values for the `Yuv` struct in video.wgsl:
/// `[y_offset, y_scale, c_scale, 0, cr->r, cb->g, cr->g, cb->b]`.
///
/// Coefficients follow from the luma weights Kr and Kb (ITU-R BT.601 /
/// BT.709): R = Y + 2(1-Kr)Cr, B = Y + 2(1-Kb)Cb, and G from
/// Y = Kr R + Kg G + Kb B.
pub fn yuv_params(color: ColorSpace) -> [f32; 8] {
    let (kr, kb) = match color.matrix {
        YuvMatrix::Bt601 => (0.299_f64, 0.114_f64),
        YuvMatrix::Bt709 => (0.2126, 0.0722),
    };
    let kg = 1.0 - kr - kb;
    let cr_r = 2.0 * (1.0 - kr);
    let cb_b = 2.0 * (1.0 - kb);
    let cb_g = -cb_b * kb / kg;
    let cr_g = -cr_r * kr / kg;
    let (y_offset, y_scale, c_scale) = match color.range {
        YuvRange::Limited => (16.0 / 255.0, 255.0 / 219.0, 255.0 / 224.0),
        YuvRange::Full => (0.0, 1.0, 1.0),
    };
    [y_offset, y_scale, c_scale, 0.0, cr_r, cb_g, cr_g, cb_b].map(|v| v as f32)
}

/// Largest rectangle with the source's aspect ratio that fits the target,
/// centred, on whole pixels: `[x, y, width, height]`.
pub fn fit_rect(src_w: u32, src_h: u32, dst_w: u32, dst_h: u32) -> [f32; 4] {
    let (sw, sh, dw, dh) = (src_w as f64, src_h as f64, dst_w as f64, dst_h as f64);
    let scale = (dw / sw).min(dh / sh);
    let (w, h) = ((sw * scale).round().max(1.0), (sh * scale).round().max(1.0));
    let (x, y) = (((dw - w) / 2.0).floor(), ((dh - h) / 2.0).floor());
    [x as f32, y as f32, w as f32, h as f32]
}

#[cfg(test)]
mod tests {
    use super::{fit_rect, yuv_params};
    use crate::capture::{ColorSpace, YuvMatrix, YuvRange};

    /// Applies the shader's formula to 8-bit Y, Cb, Cr.
    fn to_rgb(color: ColorSpace, y: u8, cb: u8, cr: u8) -> [f32; 3] {
        let [y_off, y_scale, c_scale, _, cr_r, cb_g, cr_g, cb_b] = yuv_params(color);
        let y = (f32::from(y) / 255.0 - y_off) * y_scale;
        let cb = (f32::from(cb) / 255.0 - 128.0 / 255.0) * c_scale;
        let cr = (f32::from(cr) / 255.0 - 128.0 / 255.0) * c_scale;
        [y + cr_r * cr, y + cb_g * cb + cr_g * cr, y + cb_b * cb]
    }

    fn assert_rgb(actual: [f32; 3], expected: [f32; 3]) {
        for (a, e) in actual.iter().zip(expected) {
            assert!((a - e).abs() < 0.01, "{actual:?} != {expected:?}");
        }
    }

    #[test]
    fn bt709_coefficients_match_the_standard() {
        let p = yuv_params(ColorSpace::BT709_LIMITED);
        for (got, want) in p[4..].iter().zip([1.5748, -0.18732, -0.46812, 1.8556]) {
            assert!((got - want).abs() < 1e-4, "{p:?}");
        }
    }

    #[test]
    fn bt601_coefficients_match_the_standard() {
        let p = yuv_params(ColorSpace {
            matrix: YuvMatrix::Bt601,
            range: YuvRange::Full,
        });
        for (got, want) in p[4..].iter().zip([1.402, -0.344136, -0.714136, 1.772]) {
            assert!((got - want).abs() < 1e-4, "{p:?}");
        }
    }

    #[test]
    fn black_and_white_per_range() {
        let limited = ColorSpace::BT709_LIMITED;
        assert_rgb(to_rgb(limited, 16, 128, 128), [0.0; 3]);
        assert_rgb(to_rgb(limited, 235, 128, 128), [1.0; 3]);
        let full = ColorSpace {
            matrix: YuvMatrix::Bt601,
            range: YuvRange::Full,
        };
        assert_rgb(to_rgb(full, 0, 128, 128), [0.0; 3]);
        assert_rgb(to_rgb(full, 255, 128, 128), [1.0; 3]);
        // Full-range BT.601 red as JPEG encodes it: Y 76, Cb 85, Cr 255.
        assert_rgb(to_rgb(full, 76, 85, 255), [1.0, 0.0, 0.0]);
    }

    #[test]
    fn same_size_maps_one_to_one() {
        assert_eq!(fit_rect(1920, 1080, 1920, 1080), [0.0, 0.0, 1920.0, 1080.0]);
    }

    #[test]
    fn wider_target_gets_pillarbox() {
        // 16:9 on a 21:9 monitor.
        assert_eq!(
            fit_rect(1920, 1080, 2560, 1080),
            [320.0, 0.0, 1920.0, 1080.0]
        );
    }

    #[test]
    fn taller_target_gets_letterbox() {
        assert_eq!(
            fit_rect(1920, 1080, 1280, 1024),
            [0.0, 152.0, 1280.0, 720.0]
        );
    }

    #[test]
    fn upscale_to_1440p() {
        assert_eq!(fit_rect(1920, 1080, 2560, 1440), [0.0, 0.0, 2560.0, 1440.0]);
    }
}
