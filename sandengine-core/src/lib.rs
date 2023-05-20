#[macro_use]
extern crate glium;

use std::time::Instant;

use glium::glutin::window::Icon;
#[allow(unused_imports)]
use glium::{
    glutin::{self, event_loop::EventLoop, event::WindowEvent, event::Event, dpi::PhysicalSize},
    texture, Surface, Rect, BlitTarget, uniforms
};
pub mod simulation;
use simulation::Simulation;



// One texture for collision:
// each pixel holds a normalized coordinate of a collision point. If the pixel value is vec4(0.0) this means nothing/ gap
// once the next line of coordinates starts until the next vec4(0.0) means one collision island

pub fn run() {
    let size = (513, 512);
    //let size = (1920, 1080);
    let (event_loop, display) = create_window(size);
    let (mut winit_platform, mut imgui_context) = imgui_init(&display);
    let mut ui_renderer = imgui_glium_renderer::Renderer::init(&mut imgui_context, &display)
        .expect("Failed to initialize UI renderer");
    let mut sim = Simulation::new(&display, size);

    let mut last_render = Instant::now();
    event_loop.run(move |event, _, control_flow| {
        let next_frame_time = std::time::Instant::now() +
            std::time::Duration::from_nanos(16_666_667);
        //*control_flow = glutin::event_loop::ControlFlow::WaitUntil(next_frame_time);
        *control_flow = glutin::event_loop::ControlFlow::Poll;
        let frame_delta = last_render.elapsed();
        last_render = Instant::now();
        let fps = 1.0f64 / frame_delta.as_secs_f64();

        sim.run();

        match event {
            Event::NewEvents(cause) => match cause {
                _ => {
                    imgui_context.io_mut().update_delta_time(frame_delta);
                }
            },
            Event::MainEventsCleared => {
                let gl_window = display.gl_window();
                winit_platform
                    .prepare_frame(imgui_context.io_mut(), gl_window.window())
                    .expect("Failed to prepare frame");
                gl_window.window().request_redraw();
            },
            Event::RedrawRequested(_) => {
                // Create frame for the all important `&imgui::Ui`
                let ui = imgui_context.frame();

                ui.show_demo_window(&mut true);
                let gl_window = display.gl_window();
                
                let mut target = display.draw();
                target.clear_color(0.0, 0.5, 0.0, 1.0);
                
                // Render Simulation
                let full_rect = Rect{left: 0, bottom: 0, width: size.0, height: size.1};
                let full_blitt = BlitTarget{left: 0, bottom: size.1, width: size.0 as i32, height: -(size.1 as i32)};
                target.blit_buffers_from_simple_framebuffer(
                    &sim.output_color.as_surface(),
                    &full_rect,
                    &full_blitt,
                    uniforms::MagnifySamplerFilter::Nearest,
                    glium::BlitMask::color()
                );
                
                // Render UI
                winit_platform.prepare_render(ui, gl_window.window());
                let ui_draw_data = imgui_context.render();
                ui_renderer.render(&mut target, ui_draw_data).expect("Could not render UI.");
                
                target.finish().unwrap();
            },
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                *control_flow = glutin::event_loop::ControlFlow::Exit;
                return;
            },
            event => {
                let gl_window = display.gl_window();
                winit_platform.handle_event(imgui_context.io_mut(), gl_window.window(), &event);
                if imgui_context.io().want_capture_mouse || imgui_context.io().want_capture_keyboard {
                    return;
                }
                match event {
                    Event::WindowEvent {event, .. } => match event {
                        WindowEvent::KeyboardInput { input, .. } => {
                        },
                        WindowEvent::CursorMoved {position, ..} => {
                            sim.params.mousePos = (position.x as f32 / size.0 as f32, position.y as f32 / size.1 as f32);
                        },
                        WindowEvent::MouseInput {state, button, ..} => {
                            match button {
                                glutin::event::MouseButton::Left => {
                                    sim.params.mousePressed = state == glutin::event::ElementState::Pressed;
                                },
                                _ => ()
                            }
                        },
                        WindowEvent::MouseWheel {delta, .. } => {
                            match delta {
                                glutin::event::MouseScrollDelta::LineDelta(_x, y) => {
                                    let new = std::cmp::max(1, sim.params.brushSize as i32 + y.signum() as i32);
                                    sim.params.brushSize = new as u32;
                                    println!("Brush Size: {}", sim.params.brushSize);
                                },
                                _ => (),
                            };
                        },
                        _ => (),
                    },
                    _ => (),
                };
            },
        }
        
    });
}


fn create_window(size : (u32, u32)) -> (EventLoop<()>, glium::Display) {
    let event_loop = glium::glutin::event_loop::EventLoop::new();
    let wb = glutin::window::WindowBuilder::new()
        .with_inner_size(PhysicalSize::<u32>::from(size))
        .with_title("SandEngine");
    let cb = glutin::ContextBuilder::new()
        ;//.with_vsync(true)
    let display = glium::Display::new(wb, cb, &event_loop).unwrap();

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
    (event_loop, display)
}


fn imgui_init(display: &glium::Display) -> (imgui_winit_support::WinitPlatform, imgui::Context) {
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