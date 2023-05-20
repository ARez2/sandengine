#[macro_use]
extern crate glium;

use std::time::Instant;

use glium::glutin::dpi::PhysicalPosition;
use glium::glutin::event::{VirtualKeyCode};
use glium::{
    glutin::{self, event::WindowEvent, event::Event},
};
pub mod simulation;
use simulation::Simulation;
pub mod renderer;
use renderer::{Renderer, TextureDrawMode};


// One texture for collision:
// each pixel holds a normalized coordinate of a collision point. If the pixel value is vec4(0.0) this means nothing/ gap
// once the next line of coordinates starts until the next vec4(0.0) means one collision island

pub fn run() {
    let size = (640, 480);
    //let size = (1920, 1080);

    let event_loop = glium::glutin::event_loop::EventLoop::new();
    let mut renderer = Renderer::new(size, &event_loop);
    let mut sim = Simulation::new(&renderer.display, size);

    let mut last_render = Instant::now();
    event_loop.run(move |event, _, control_flow| {
        //let next_frame_time = std::time::Instant::now() + std::time::Duration::from_nanos(16_666_667);
        //*control_flow = glutin::event_loop::ControlFlow::WaitUntil(next_frame_time);
        *control_flow = glutin::event_loop::ControlFlow::Poll;
        let frame_delta = last_render.elapsed();
        last_render = Instant::now();
        let _fps = 1.0f64 / frame_delta.as_secs_f64();
        //println!("FPS: {}, delta (ms): {}", fps, frame_delta.as_secs_f64() * 1000.0);

        match event {
            Event::NewEvents(cause) => {
                renderer.new_events(cause, frame_delta);
            },
            Event::MainEventsCleared => {
                renderer.prepare_frame();
                sim.run();
            },
            Event::RedrawRequested(_) => {
                renderer.start_render();
                renderer.render_texture(&sim.output_color, PhysicalPosition::new(0, 0), TextureDrawMode::KeepScale);
                renderer.finish_render();
            },
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                *control_flow = glutin::event_loop::ControlFlow::Exit;
            },
            event => {
                // if the UI etc. has already "consumed" those events, return
                if renderer.process_events(&event) {return};

                match event {
                    Event::WindowEvent {event, .. } => match event {
                        WindowEvent::KeyboardInput { input, .. } => {
                            if let Some(code) = input.virtual_keycode {
                                match code {
                                    VirtualKeyCode::Key0 => sim.params.brushMaterial = 0,
                                    VirtualKeyCode::Key1 => sim.params.brushMaterial = 1,
                                    VirtualKeyCode::Key2 => sim.params.brushMaterial = 2,
                                    VirtualKeyCode::Key3 => sim.params.brushMaterial = 3,
                                    VirtualKeyCode::Key4 => sim.params.brushMaterial = 6,
                                    VirtualKeyCode::Key5 => sim.params.brushMaterial = 7,
                                    VirtualKeyCode::Key6 => sim.params.brushMaterial = 8,
                                    _ => (),
                                };
                            }
                        },
                        WindowEvent::CursorMoved {position, ..} => {
                            let dims = renderer.display.get_framebuffer_dimensions();
                            sim.params.mousePos = (position.x as f32 / dims.0 as f32, position.y as f32 / dims.1 as f32);
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