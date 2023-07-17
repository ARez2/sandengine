use glium::{
    glutin::{self, dpi::PhysicalSize, event::Event, event_loop::EventLoop, window::Icon},
    uniforms::{self, Sampler}, BlitTarget, Frame, Program, Rect, Surface, BackfaceCullingMode, DrawParameters,
};
use imgui_winit_support::WinitPlatform;
use nphysics2d::nalgebra::Point2;
use rayon::prelude::*;

#[derive(Copy, Clone)]
struct Vertex {
    position: [f32; 2],
    tex_coords: [f32; 2],
}

implement_vertex!(Vertex, position, tex_coords);

const QUAD: [Vertex; 4] = [
    Vertex {
        position: [-1.0, -1.0],
        tex_coords: [0.0, 0.0],
    },
    Vertex {
        position: [-1.0, 1.0],
        tex_coords: [0.0, 1.0],
    },
    Vertex {
        position: [1.0, 1.0],
        tex_coords: [1.0, 1.0],
    },
    Vertex {
        position: [1.0, -1.0],
        tex_coords: [1.0, 0.0],
    },
];

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TextureDrawMode {
    Stretch,
    KeepScale,
    Scale(glium::glutin::dpi::PhysicalSize<u32>),
}

pub struct Renderer {
    draw_program: Program,
    pub display: glium::Display,
    winit_platform: WinitPlatform,
    imgui_context: imgui::Context,
    ui_renderer: imgui_glium_renderer::Renderer,

    current_frame: Option<Frame>,
}

impl Renderer {
    pub fn new(size: (u32, u32), event_loop: &EventLoop<()>) -> Self {
        let wb = glutin::window::WindowBuilder::new()
            .with_inner_size(PhysicalSize::<u32>::from(size))
            //.with_fullscreen(Some(glutin::window::Fullscreen::Borderless(None)))
            .with_title("SandEngine");
        let cb = glutin::ContextBuilder::new().with_gl(glutin::GlRequest::Latest); //.with_vsync(true)
        let display = glium::Display::new(wb, cb, event_loop).unwrap();

        let (icon_rgba, icon_width, icon_height) = {
            let image = image::open("icon.png")
                .expect("Failed to open icon path")
                .into_rgba8();
            let (width, height) = image.dimensions();
            let rgba = image.into_raw();
            (rgba, width, height)
        };
        let icon = Icon::from_rgba(icon_rgba, icon_width, icon_height).unwrap();
        display.gl_window().window().set_window_icon(Some(icon));

        let (winit_platform, mut imgui_context) = Renderer::imgui_init(&display);
        let ui_renderer = imgui_glium_renderer::Renderer::init(&mut imgui_context, &display)
            .expect("Failed to initialize UI renderer");

        let vertex_shader_src = include_str!("../../shaders/vertex.glsl");
        let fragment_shader_src = include_str!("../../shaders/fragment.glsl");
        let draw_program =
            glium::Program::from_source(&display, vertex_shader_src, fragment_shader_src, None)
                .unwrap();

        Renderer {
            draw_program,
            display,
            winit_platform,
            imgui_context,
            ui_renderer,

            current_frame: None,
        }
    }

    fn imgui_init(
        display: &glium::Display,
    ) -> (imgui_winit_support::WinitPlatform, imgui::Context) {
        let mut imgui_context = imgui::Context::create();
        imgui_context.set_ini_filename(None);

        let mut winit_platform = imgui_winit_support::WinitPlatform::init(&mut imgui_context);

        let gl_window = display.gl_window();
        let window = gl_window.window();

        let dpi_mode = imgui_winit_support::HiDpiMode::Default;

        winit_platform.attach_window(imgui_context.io_mut(), window, dpi_mode);

        imgui_context
            .fonts()
            .add_font(&[imgui::FontSource::TtfData {
                data: include_bytes!("../../fonts/Fragment_Mono/FragmentMono-Regular.ttf"),
                size_pixels: 15.0,
                config: None,
            }]);

        (winit_platform, imgui_context)
    }

    pub fn prepare_frame(&mut self) {
        let gl_window = self.display.gl_window();
        self.winit_platform
            .prepare_frame(self.imgui_context.io_mut(), gl_window.window())
            .expect("Failed to prepare frame");
        gl_window.window().request_redraw();
    }

    pub fn new_events(
        &mut self,
        _event: glium::glutin::event::StartCause,
        delta: std::time::Duration,
    ) {
        self.imgui_context.io_mut().update_delta_time(delta);
    }

    pub fn process_events(&mut self, event: &Event<()>) -> bool {
        let gl_window = self.display.gl_window();
        self.winit_platform
            .handle_event(self.imgui_context.io_mut(), gl_window.window(), event);

        self.imgui_context.io().want_capture_mouse || self.imgui_context.io().want_capture_keyboard
    }

    pub fn start_render(&mut self) {
        let mut target = self.display.draw();
        target.clear_color(0.0, 0.5, 0.0, 1.0);

        self.current_frame = Some(target);
    }

    pub fn render_ui(&mut self) {
        // Create frame for the all important `&imgui::Ui`
        let ui = self.imgui_context.frame();

        ui.show_demo_window(&mut true);
        let gl_window = self.display.gl_window();

        // Render UI
        self.winit_platform.prepare_render(ui, gl_window.window());
        let ui_draw_data = self.imgui_context.render();
        if let Some(target) = &mut self.current_frame {
            self.ui_renderer
                .render(target, ui_draw_data)
                .expect("Could not render UI.");
        }
    }

    pub fn render_texture(
        &mut self,
        texture: &glium::Texture2d,
        pos: glium::glutin::dpi::PhysicalPosition<u32>,
        draw_mode: TextureDrawMode,
        flip: bool,
    ) {
        if let Some(target) = &mut self.current_frame {
            let source_rect = Rect {
                left: 0,
                bottom: 0,
                width: texture.width(),
                height: texture.height(),
            };
            let dims = target.get_dimensions();

            let (bottom, height_multi) = match flip {
                true => (dims.1 - pos.y, -1),
                false => (pos.y, 1),
            };

            let target_rect = match draw_mode {
                TextureDrawMode::Stretch => BlitTarget {
                    left: pos.x,
                    bottom,
                    width: dims.0 as i32,
                    height: height_multi * (dims.1 as i32),
                },
                TextureDrawMode::KeepScale => BlitTarget {
                    left: pos.x,
                    bottom,
                    width: texture.width() as i32,
                    height: height_multi * (texture.height() as i32),
                },
                TextureDrawMode::Scale(new_size) => BlitTarget {
                    left: pos.x,
                    bottom,
                    width: new_size.width as i32,
                    height: height_multi * (new_size.height as i32),
                },
            };

            // target.blit_buffers_from_simple_framebuffer(
            //     &texture.as_surface(),
            //     &source_rect,
            //     &target_rect,
            //     uniforms::MagnifySamplerFilter::Nearest,
            //     glium::BlitMask::color(),
            // );


            let index_buffer =
            glium::IndexBuffer::new(&self.display, glium::index::PrimitiveType::TriangleStrip, &[1 as u16, 2, 0, 3])
                .unwrap();
            let uniforms = uniform! {
                tex: Sampler::new(texture)
                    .magnify_filter(uniforms::MagnifySamplerFilter::Nearest)
                    .minify_filter(uniforms::MinifySamplerFilter::Nearest),
            };

            let draw_parameters = DrawParameters::default();
            

            target
                .draw(
                    &glium::vertex::VertexBuffer::new(&self.display, &QUAD).unwrap(),
                    &index_buffer,
                    &self.draw_program,
                    &uniforms,
                    &Default::default(),
                ).unwrap();
        }
    }

    pub fn draw_primitive(
        &mut self,
        points: &Vec<Point2<f32>>,
        scale: f32,
        mode: glium::index::PrimitiveType,
    ) {
        if let Some(target) = &mut self.current_frame {
            let dims = target.get_dimensions();
            let shape: Vec<Vertex> = points
                .par_iter()
                .map(|pt| Vertex {
                    position: [pt.x, pt.y],
                    tex_coords: [0.0, 0.0],
                })
                .collect();
            let vertex_buffer = glium::VertexBuffer::new(&self.display, &shape).unwrap();
            let indices = glium::index::NoIndices(mode);
            target
                .draw(
                    &vertex_buffer,
                    &indices,
                    &self.draw_program,
                    &uniform! {
                        texSize: (dims.0 as f32 / scale, dims.1 as f32 / scale)
                    },
                    &Default::default(),
                )
                .expect("Cannot draw to the target.");
        }
    }

    pub fn finish_render(&mut self) {
        if let Some(f) = self.current_frame.take() {
            f.finish().unwrap();
        }
    }
}
