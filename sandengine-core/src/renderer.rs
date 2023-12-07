use glium::{
    uniforms::{self, Sampler}, Frame, Program, Surface, DrawParameters, program::ProgramChooserCreationError, glutin::surface::WindowSurface,
};
//use imgui_winit_support::WinitPlatform;
use nphysics2d::nalgebra::Point2;
use rayon::prelude::*;
use winit::{event_loop::EventLoop, dpi::{PhysicalSize, LogicalSize}, window::{Icon, Window}, event::{Event, self}};

const APPLICATION_ICON: &'static [u8] = include_bytes!("../../icon.png");

pub type RendererDisplay = glium::Display<WindowSurface>;

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
/// Helper to define how a texture is rendered by the Renderer
pub enum TextureDrawMode {
    /// Stretches the texture across the screen
    Stretch,
    /// Keeps the original size
    KeepScale,
    /// Scales the texture to the given Size
    Scale(PhysicalSize<u32>),
}


/// Renderer for displaying the simulation and UI
pub struct Renderer {
    /// Program that includes the fragment/ vertex shader
    draw_program: Program,
    /// The display, used for drawing
    pub display: RendererDisplay,
    /// The winit window handle
    pub window: Window,
    /// The window handle
    //winit_platform: WinitPlatform,
    /// imgui (UI) context
    //imgui_context: imgui::Context,
    /// Imgui renderer
    //ui_renderer: imgui_glium_renderer::Renderer,

    /// Holds the frame, once the start_render function is called
    current_frame: Option<Frame>,
}

impl Renderer {
    /// Creates a new renderer
    pub fn new(size: (u32, u32), scale: f32, event_loop: &EventLoop<()>) -> Self {
        let window_size = PhysicalSize::<f32>::new(size.0 as f32 * scale, size.1 as f32 * scale);
        let (window, display) = glium::backend::glutin::SimpleWindowBuilder::new()
            .with_title("SandEngine")
            .build(event_loop);
        window.set_inner_size(window_size);

        // Loads the application (window) icon
        let (icon_rgba, icon_width, icon_height) = {
            let image = image::load_from_memory(APPLICATION_ICON)
                .expect("Failed to load application icon")
                .into_rgba8();
            let (width, height) = image.dimensions();
            let rgba = image.into_raw();
            (rgba, width, height)
        };
        let icon = Icon::from_rgba(icon_rgba, icon_width, icon_height).unwrap();
        window.set_window_icon(Some(icon));

        // let (winit_platform, mut imgui_context) = Renderer::imgui_init(&display);
        // let ui_renderer = imgui_glium_renderer::Renderer::init(&mut imgui_context, &display)
        //     .expect("Failed to initialize UI renderer");

        // Builds the program, that draws everything
        let vertex140_shader_src = include_str!("../../shaders/vertex140.glsl");
        let fragment140_shader_src = include_str!("../../shaders/fragment140.glsl");
        let draw_program = program!(&display,
            140 => {
                vertex: vertex140_shader_src,
                fragment: fragment140_shader_src
            },
        );
        if let Err(err) = draw_program {
            if let ProgramChooserCreationError::ProgramCreationError(e) = err {
                println!("{}", e)
            } else {
                println!("No possible OpenGL version found.")
            };
            std::process::exit(1);
        };
        let draw_program = draw_program.unwrap();

        Renderer {
            draw_program,
            display,
            window,
            //winit_platform,
            //imgui_context,
            //ui_renderer,

            current_frame: None,
        }
    }

    // /// Helper function to set up ImGui
    // fn imgui_init(
    //     display: &RendererDisplay,
    // ) -> (imgui_winit_support::WinitPlatform, imgui::Context) {
    //     let mut imgui_context = imgui::Context::create();
    //     imgui_context.set_ini_filename(None);

    //     let mut winit_platform = imgui_winit_support::WinitPlatform::init(&mut imgui_context);

    //     let gl_window = display.gl_window();
    //     let window = gl_window.window();

    //     let dpi_mode = imgui_winit_support::HiDpiMode::Default;

    //     winit_platform.attach_window(imgui_context.io_mut(), window, dpi_mode);

    //     imgui_context
    //         .fonts()
    //         .add_font(&[imgui::FontSource::TtfData {
    //             data: include_bytes!("../../fonts/Fragment_Mono/FragmentMono-Regular.ttf"),
    //             size_pixels: 15.0,
    //             config: None,
    //         }]);

    //     (winit_platform, imgui_context)
    // }

    pub fn redraw(&self) {
        self.window.request_redraw();
    }

    /// Prepares the renderer to start drawing
    pub fn prepare_frame(&mut self) {
        // let gl_window = self.display.gl_window();
        // self.winit_platform
        //     .prepare_frame(self.imgui_context.io_mut(), gl_window.window())
        //     .expect("Failed to prepare frame");
        
    }

    pub fn new_events(
        &mut self,
        _event: event::StartCause,
        delta: std::time::Duration,
    ) {
        //self.imgui_context.io_mut().update_delta_time(delta);
    }

    /// Let the UI handle the (input) event and return whether it has been consumed
    pub fn process_events(&mut self, event: &Event<()>) -> bool {
        // let gl_window = self.display.gl_window();
        // self.winit_platform
        //     .handle_event(self.imgui_context.io_mut(), gl_window.window(), event);

        // self.imgui_context.io().want_capture_mouse || self.imgui_context.io().want_capture_keyboard
        false
    }

    /// Starts drawing, clearing the screen before
    pub fn start_render(&mut self) {
        let mut target = self.display.draw();
        target.clear_color(0.0, 0.5, 0.0, 1.0);

        self.current_frame = Some(target);
    }

    /// Calls the imgui (UI) renderer
    pub fn render_ui(&mut self) {
        // // Create frame for the all important `&imgui::Ui`
        // let ui = self.imgui_context.frame();

        // ui.show_demo_window(&mut true);
        // let gl_window = self.display.gl_window();

        // // Render UI
        // self.winit_platform.prepare_render(ui, gl_window.window());
        // let ui_draw_data = self.imgui_context.render();
        // if let Some(target) = &mut self.current_frame {
        //     self.ui_renderer
        //         .render(target, ui_draw_data)
        //         .expect("Could not render UI.");
        // }
    }

    /// Renders the simulation, including providing uniforms for the fragment and vertex shaders
    pub fn render_sim(
        &mut self,
        texture: &glium::Texture2d,
        light_texture: &glium::Texture2d,
        background: &glium::Texture2d,
        frame_nr: i32
    ) {
        if let Some(target) = &mut self.current_frame {
            let index_buffer =
            glium::IndexBuffer::new(&self.display, glium::index::PrimitiveType::TriangleStrip, &[1 as u16, 2, 0, 3])
                .unwrap();

                let uniforms = uniform! {
                color_tex: Sampler::new(texture)
                    .magnify_filter(uniforms::MagnifySamplerFilter::Nearest)
                    .minify_filter(uniforms::MinifySamplerFilter::LinearMipmapNearest),
                light_tex: light_texture,
                tex_size: (texture.dimensions().0 as f32, texture.dimensions().1 as f32),
                background_tex: background,
                frame: frame_nr
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

    /// Finishes drawing and displays it on the screen
    pub fn finish_render(&mut self) {
        if let Some(f) = self.current_frame.take() {
            f.finish().unwrap();
        }
    }
}
