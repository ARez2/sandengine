#[macro_use]
extern crate glium;

use std::time::Instant;

use glium::{Rect, BlitTarget, uniforms, glutin::dpi::PhysicalPosition};
#[allow(unused_imports)]
use glium::{glutin, texture, Surface};
use rand::Rng;
use crate::glutin::dpi::PhysicalSize;

#[repr(C)]
#[derive(Copy, Clone, Default)]
#[allow(non_snake_case)]
struct Params {
    moveRight: bool,
    _p0: [bool; 3],
    mousePos: (f32, f32),
    _p1: [f32; 2],
    brushSize: u32,
    _p2: [f32; 3],
    brushMaterial: i32,
    _p3: [f32; 3],
    time: f32,
    //_p4: [f32; 3],
}
impl Params {
    pub fn new() -> Self {
        Self {
            moveRight: true,
            mousePos: (0.0, 0.0),
            brushSize: 0,
            brushMaterial: 0,
            ..Default::default()
        }
    }
}



fn empty_data(size : (u32, u32)) -> texture::RawImage2d<'static, f32> {
	let pixels : Vec<f32> = vec![0.0; (size.0 * size.1 * 4) as usize];
	return texture::RawImage2d::from_raw_rgba(pixels, size);
}

struct Simulation {
    compute_shader: glium::program::ComputeShader,
    size: (u32, u32),
    workgroups: (u32, u32, u32),

    input_data: texture::Texture2d,
    output_data: texture::Texture2d,
    output_color: texture::Texture2d,
    brush_size: u32,
    params: Params,
}
impl Simulation {
    pub fn new(display: &glium::Display, size: (u32, u32)) -> Self {
        implement_uniform_block!(Params, mousePos, brushSize, brushMaterial, time, moveRight);
        
        let program = glium::program::ComputeShader::from_source(display, SIM_SHADER_SRC);
        if let Err(err) = program {
            println!("{}", err);
            panic!();
        };
        let program = program.unwrap();
        
        let format = texture::UncompressedFloatFormat::F32F32F32F32;
        let mip = texture::MipmapsOption::NoMipmap;
        Self {
            compute_shader: program,
            size,
            workgroups: (((size.0 + 7) as f32 / 8.0) as u32, ((size.1 + 7) as f32 / 8.0) as u32, 1),

            input_data: texture::Texture2d::with_format(display, empty_data(size), format, mip).unwrap(),
            output_data: texture::Texture2d::with_format(display, empty_data(size), format, mip).unwrap(),
            output_color: texture::Texture2d::with_format(display, empty_data(size), format, mip).unwrap(),
            brush_size: 1,
            params: Params::new(),
        }
    }

    pub fn run(&mut self, display: &glium::Display) {
        self.params.brushMaterial = 1;
        let mut rng = rand::thread_rng();
        self.params.moveRight = rng.gen_bool(0.5);
        
        let mut buffer: glium::uniforms::UniformBuffer<Params> = glium::uniforms::UniformBuffer::empty(display).unwrap();
        {
            let mut map = buffer.map_write();
            map.write(self.params);
        }

        let img_unit_format = glium::uniforms::ImageUnitFormat::RGBA32F;
        let write = glium::uniforms::ImageUnitAccess::Write;
        let output_data_img = self.output_data.image_unit(img_unit_format).unwrap().set_access(write);
        let output_color_img = self.output_color.image_unit(img_unit_format).unwrap().set_access(write);

        self.compute_shader.execute(
            uniform! {
                input_data: &self.input_data,
                output_data: output_data_img,
                output_color: output_color_img,
                moveRight: self.params.moveRight,
                mousePos: self.params.mousePos,
                brushSize: self.params.brushSize,
                brushMaterial: self.params.brushMaterial,
                time: self.params.time,
            }, self.workgroups.0, self.workgroups.1, self.workgroups.2);
        std::mem::swap(&mut self.input_data, &mut self.output_data);
    }
}

const SIM_SHADER_SRC: &str = include_str!("../shaders/gen/falling_sand.glsl");




fn main() {
    let size = (512, 512);

    let event_loop = glium::glutin::event_loop::EventLoop::new();
    let wb = glutin::window::WindowBuilder::new()
        .with_inner_size(PhysicalSize::<u32>::from(size));
    let cb = glutin::ContextBuilder::new()
        ;//.with_vsync(true)
    let display = glium::Display::new(wb, cb, &event_loop).unwrap();

    let mut sim = Simulation::new(&display, size);
    let mut last_render = Instant::now();
    event_loop.run(move |event, _, control_flow| {
        let next_frame_time = std::time::Instant::now() +
            std::time::Duration::from_nanos(16_666_667);
        //*control_flow = glutin::event_loop::ControlFlow::WaitUntil(next_frame_time);
        *control_flow = glutin::event_loop::ControlFlow::Poll;
        let frame_delta = last_render.elapsed();
        last_render = Instant::now();
        println!("FPS: {}", 1.0f64 / frame_delta.as_secs_f64());

        match event {
            glutin::event::Event::NewEvents(cause) => match cause {
                glutin::event::StartCause::Init => (),
                glutin::event::StartCause::ResumeTimeReached { .. } => (),
                _ => (),
            },

            glutin::event::Event::WindowEvent { event, .. } => match event {
                glutin::event::WindowEvent::CursorMoved {position, ..} => {
                    sim.params.mousePos = (position.x as f32 / size.0 as f32, position.y as f32 / size.1 as f32);
                },
                glutin::event::WindowEvent::MouseInput {state, button, ..} => {
                    match button {
                        glutin::event::MouseButton::Left => {
                            sim.params.brushSize = sim.brush_size * (state == glutin::event::ElementState::Pressed) as u32;
                        },
                        _ => ()
                    }
                },
                glutin::event::WindowEvent::MouseWheel {delta, .. } => {
                    match delta {
                        glutin::event::MouseScrollDelta::LineDelta(_x, y) => {
                            let new = std::cmp::max(1, sim.brush_size as i32 + y.signum() as i32);
                            sim.brush_size = new as u32;
                            println!("Brush Size: {}", sim.brush_size);
                        },
                        _ => (),
                    };
                },
                glutin::event::WindowEvent::CloseRequested => {
                    *control_flow = glutin::event_loop::ControlFlow::Exit;
                    return;
                },
                _ => return,
            },
            _ => (),
        }
        sim.run(&display);

        let mut target = display.draw();
        target.clear_color(0.0, 0.5, 0.0, 1.0);
        
        let full_rect = Rect{left: 0, bottom: 0, width: size.0, height: size.1};
        let full_blitt = BlitTarget{left: 0, bottom: size.1, width: size.0 as i32, height: -(size.1 as i32)};
        target.blit_buffers_from_simple_framebuffer(
            &sim.output_color.as_surface(),
            &full_rect,
            &full_blitt,
            uniforms::MagnifySamplerFilter::Nearest,
            glium::BlitMask::color()
        );
        target.finish().unwrap();
    });
}