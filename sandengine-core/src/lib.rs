#[macro_use]
extern crate glium;

use std::time::Instant;

pub mod simulation;
use sandengine_lang::parser::SandMaterial;
use simulation::Simulation;

pub mod renderer;
use renderer::{Renderer};
pub use renderer::RendererDisplay;

use winit::event::{WindowEvent, Event, MouseButton, ElementState, MouseScrollDelta, VirtualKeyCode};
use winit::event_loop::ControlFlow;



// One texture for collision:
// each pixel holds a normalized coordinate of a collision point. If the pixel value is vec4(0.0) this means nothing/ gap
// once the next line of coordinates starts until the next vec4(0.0) means one collision island

// TODO: make a texture for input. All pixels on that will be setCell'ed and then cleared.


/// Core function of the engine. Includes the event loop with simulation, rendering and UI
pub fn run(parsing_result: sandengine_lang::parser::ParsingResult) {
    // Collects a list of selectable materials, given all the SandMaterial structs from the parser
    let selectable_materials: Vec<SandMaterial> = parsing_result.materials.iter().filter_map(|m| {
        if m.selectable {
            Some(m.clone())
        } else {
            None
        }
    }).collect();
    //println!("Selectable: {:?}", selectable_materials);


    let size = (640, 480);
    //let size = (1920, 1080);
    let event_loop = winit::event_loop::EventLoopBuilder::new().build();
    let mut renderer = Renderer::new(size, &event_loop);
    let mut sim = Simulation::new(&renderer.display, size);

    let mut last_render = Instant::now();
    event_loop.run(move |event, _, control_flow| {
        // nanos: 16_666_667
        let next_frame_time = std::time::Instant::now() + std::time::Duration::from_secs(1);
        //*control_flow = ControlFlow::WaitUntil(next_frame_time);
        *control_flow = ControlFlow::Poll;
        let frame_delta = last_render.elapsed();
        last_render = Instant::now();
        let _fps = 1.0f64 / frame_delta.as_secs_f64();
        sim.params.time += frame_delta.as_secs_f32();
        //println!("FPS: {}, delta (ms): {}", fps, frame_delta.as_secs_f64() * 1000.0);

        match event {
            Event::NewEvents(cause) => {
                renderer.new_events(cause, frame_delta);
            },
            Event::RedrawEventsCleared => {
                renderer.redraw();
            },
            Event::MainEventsCleared => {
                renderer.prepare_frame();
                sim.run();
            },
            Event::RedrawRequested(_) => {
                renderer.start_render();
                renderer.render_sim(&sim.output_color, &sim.output_light, &sim.background, sim.params.frame);
                //renderer.render_ui();
                renderer.finish_render();
            },
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                *control_flow = ControlFlow::Exit;
            },
            event => {
                // if the UI etc. has already "consumed" those events, return
                if renderer.process_events(&event) {return};

                if let Event::WindowEvent {event, .. } = event { match event {
                    WindowEvent::KeyboardInput { input, .. } => {
                        if let Some(code) = input.virtual_keycode {
                            let idx = match code {
                                VirtualKeyCode::Key0 => 0,
                                VirtualKeyCode::Key1 => 1,
                                VirtualKeyCode::Key2 => 2,
                                VirtualKeyCode::Key3 => 3,
                                VirtualKeyCode::Key4 => 4,
                                VirtualKeyCode::Key5 => 5,
                                VirtualKeyCode::Key6 => 6,
                                VirtualKeyCode::Key7 => 7,
                                VirtualKeyCode::Key8 => 8,
                                VirtualKeyCode::Key9 => 9,
                                _ => 0,
                            };
                            if idx < selectable_materials.len() {
                                sim.params.brushMaterial = selectable_materials[idx].clone();
                            };
                        }
                    },
                    WindowEvent::CursorMoved {position, ..} => {
                        let dims = renderer.display.get_framebuffer_dimensions();
                        sim.params.mousePos = (position.x as f32 / dims.0 as f32, position.y as f32 / dims.1 as f32);
                    },
                    WindowEvent::MouseInput {state, button, ..} => {
                        match button {
                            MouseButton::Left => {
                                sim.params.mousePressed = state == ElementState::Pressed;
                            },
                            _ => ()
                        }
                    },
                    WindowEvent::MouseWheel {delta: MouseScrollDelta::LineDelta(_x, y), .. } => {
                        let new = std::cmp::max(1, sim.params.brushSize as i32 + y.signum() as i32);
                        sim.params.brushSize = new as u32;
                        println!("Brush Size: {}", sim.params.brushSize);
                    },
                    _ => (),
                    }
                };
            },
        }
        
    });
}