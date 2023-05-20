use glium::{texture::{self, RawImage2d}, uniforms};
use rand::Rng;



#[repr(C)]
#[derive(Copy, Clone, Default)]
#[allow(non_snake_case)]
pub struct Params {
    pub moveRight: bool,
    pub mousePos: (f32, f32),
    pub mousePressed: bool,
    pub brushSize: u32,
    pub brushMaterial: i32,
    pub time: f32,
}
impl Params {
    pub fn new() -> Self {
        Self {
            moveRight: true,
            mousePos: (0.0, 0.0),
            brushSize: 5,
            brushMaterial: 0,
            mousePressed: false,
            ..Default::default()
        }
    }
}




pub struct Simulation {
    compute_shader: glium::program::ComputeShader,
    _size: (u32, u32),
    workgroups: (u32, u32, u32),

    input_data: texture::Texture2d,
    output_data: texture::Texture2d,
    pub output_color: texture::Texture2d,
    collision_data: texture::Texture2d,
    pub params: Params,
}
impl Simulation {
    pub fn new(display: &glium::Display, size: (u32, u32)) -> Self {
        
        let current_dir = std::env::current_dir().unwrap();
        let shader_src = std::fs::read_to_string(current_dir
                .join("shaders")
                .join("gen")
                .join("falling_sand.glsl")).unwrap();
        let program = glium::program::ComputeShader::from_source(display, shader_src.as_str());
        if let Err(err) = program {
            println!("{}", err);
            panic!();
        };
        let program = program.unwrap();
        
        let format = texture::UncompressedFloatFormat::F32F32F32F32;
        let mip = texture::MipmapsOption::NoMipmap;
        let pixels : Vec<f32> = vec![0.0; (size.0 * size.1 * 4) as usize];

        Self {
            compute_shader: program,
            _size: size,
            workgroups: (((size.0 + 7) as f32 / 8.0) as u32, ((size.1 + 7) as f32 / 8.0) as u32, 1),

            input_data: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(pixels.clone(), size), format, mip).unwrap(),
            output_data: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(pixels.clone(), size), format, mip).unwrap(),
            output_color: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(pixels.clone(), size), format, mip).unwrap(),
            collision_data: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(pixels, size), format, mip).unwrap(),
            params: Params::new(),
        }
    }

    pub fn run(&mut self) {
        let mut rng = rand::thread_rng();
        self.params.moveRight = rng.gen_bool(0.5);
        
        let img_unit_format = glium::uniforms::ImageUnitFormat::RGBA32F;
        let write = glium::uniforms::ImageUnitAccess::Write;
        let output_data_img = self.output_data.image_unit(img_unit_format).unwrap().set_access(write);
        let output_color_img = self.output_color.image_unit(img_unit_format).unwrap().set_access(write);
        let collision_img = self.collision_data.image_unit(img_unit_format).unwrap().set_access(uniforms::ImageUnitAccess::ReadWrite);
        
        self.compute_shader.execute(
            uniform! {
                input_data: &self.input_data,
                output_data: output_data_img,
                output_color: output_color_img,
                collision_data: collision_img,
                moveRight: self.params.moveRight,
                mousePos: self.params.mousePos,
                brushSize: self.params.brushSize * self.params.mousePressed as u32,
                brushMaterial: self.params.brushMaterial,
                time: self.params.time,
            }, self.workgroups.0, self.workgroups.1, self.workgroups.2);
        std::mem::swap(&mut self.input_data, &mut self.output_data);
    }
}