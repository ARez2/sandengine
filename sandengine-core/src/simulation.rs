use glium::{texture::{self, RawImage2d}, uniforms, Surface};
use rand::Rng;
use image::{io::Reader as ImageReader, GenericImageView};
use sandengine_lang::parser::materials::SandMaterial;
use crate::RendererDisplay;


#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SimRigidBody {
    id: i32,
    _padding: [i32; 1],
    pos: [f32; 2],
    //_padding2: [i32; 1],
    rot: f32,
}

const MAX_RBS: usize = 16;

#[repr(C)]
#[derive(Clone, Copy)]
struct SimBodies {
    bodies: [SimRigidBody; MAX_RBS]
}
implement_uniform_block!(SimRigidBody, id, pos, rot);
implement_uniform_block!(SimBodies, bodies);

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SimRBCell {
    matID: i32,
    _pad: [i32; 1],
    orig_pos: [i32; 2],
    pos: [i32; 2],
    rb_idx: i32,
    _pad2: [i32; 1]
}
implement_uniform_block!(SimRBCell, matID, orig_pos, pos, rb_idx);


pub const MODSHAPE_CIRCLE: i32 = 0;
pub const MODSHAPE_SQUARE: i32 = 1;
const MAX_MODIFICATIONS: usize = 256;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct SimModification {
    pub position: [i32; 2],
    //pub _pad: [i32; 1],
    pub mod_shape: i32,
    //pub _pad2: [i32; 1],
    pub mod_size: i32,
    //pub _pad3: [i32; 1],
    pub mod_matID: i32,
    pub _pad4: [i32; 3],
}
implement_uniform_block!(SimModification, position, mod_shape, mod_size, mod_matID);

#[repr(C)]
#[derive(Clone, Copy)]
struct SimModifications {
    sim_modifications: [SimModification; MAX_MODIFICATIONS]
}
implement_uniform_block!(SimModifications, sim_modifications);


#[repr(C)]
#[derive(Clone, Default)]
#[allow(non_snake_case)]
pub struct Params {
    pub moveRight: bool,
    pub mousePos: (f32, f32),
    pub mousePressed: bool,
    // TODO: Move brush properties outside of the Simulation struct
    pub brushSize: u32,
    pub brushMaterial: SandMaterial,
    pub time: f32,
    pub frame: i32,
}
impl Params {
    pub fn new() -> Self {
        Self {
            moveRight: true,
            mousePos: (0.0, 0.0),
            brushSize: 5,
            brushMaterial: SandMaterial::default(),
            mousePressed: false,
            frame: 0,
            ..Default::default()
        }
    }
}



/// Holds all neccessary data to run the falling sand simulation (compute shader)
pub struct Simulation {
    /// The compute shader
    compute_shader: glium::program::ComputeShader,
    /// The size of the simulation
    size: (u32, u32),
    /// The number of work groups for the compute shader
    workgroups: (u32, u32, u32),

    /// Input Texture, that stores the cell information (material id etc.)
    input_data: texture::Texture2d,
    /// Output Texture, that stores the cell information (material id etc.)
    output_data: texture::Texture2d,
    /// The final color returned from the compute shader
    pub output_color: texture::Texture2d,
    /// Input Texture, that stores the illumination for each cell
    input_light: texture::Texture2d,
    /// Output Texture, that stores the illumination for each cell
    pub output_light: texture::Texture2d,
    pub collision_tex_scale: u32,
    pub collision_data: texture::Texture2d,

    /// The image, that is displayed behind the simulation
    pub background: texture::Texture2d,

    /// The parameters for the simulation (uniforms)
    pub params: Params,

    modifications_buffer: glium::uniforms::UniformBuffer<SimModifications>,
    pub modifications: Vec<SimModification>
}
impl Simulation {
    pub fn new(display: &RendererDisplay, size: (u32, u32)) -> Self {
        let current_dir = std::env::current_dir().unwrap();
        let compute_shader_src = std::fs::read_to_string(current_dir.join("shaders/compute/gen/falling_sand.glsl")).unwrap();

        // Creates the shader program
        let program = glium::program::ComputeShader::from_source(display, &compute_shader_src);
        if let Err(err) = program {
            println!("{}", err);
            panic!();
        };
        let program = program.unwrap();
        
        // Set up all the required textures with their format and mipmaps

        let format = texture::UncompressedFloatFormat::F32F32F32F32;
        let auto_mip = texture::MipmapsOption::AutoGeneratedMipmaps;
        let no_mip = texture::MipmapsOption::NoMipmap;
        let data : Vec<f32> = vec![0.0; (size.0 * size.1 * 4) as usize];
        let collision_tex_scale = 8;
        let colsize = (size.0 / collision_tex_scale, size.1 / collision_tex_scale);
        let coldata : Vec<f32> = vec![0.0; (colsize.0 * colsize.1 * 4) as usize];

        let output_color = texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(data.clone(), size), format, auto_mip).unwrap();

        let path = current_dir.join("data").join("ice_pepe.png");
        let bg_img = ImageReader::open(path).unwrap().decode().unwrap();
        let background = texture::Texture2d::with_format(
            display,
            RawImage2d::from_raw_rgba_reversed(bg_img.as_bytes(), bg_img.dimensions()),
            texture::UncompressedFloatFormat::F32F32F32F32,
            texture::MipmapsOption::AutoGeneratedMipmaps).unwrap();
        

        let mods = [
            SimModification {
                mod_shape: MODSHAPE_CIRCLE,
                mod_size: 0,
                mod_matID: 0,
                ..Default::default()
            }; MAX_MODIFICATIONS];
        let modifications_buffer = glium::uniforms::UniformBuffer::new(
            display,
            SimModifications {sim_modifications: mods}).unwrap();
        
        Self {
            compute_shader: program,
            size,
            workgroups: (((size.0 + 7) as f32 / 8.0) as u32, ((size.1 + 7) as f32 / 8.0) as u32, 1),

            input_data: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(data.clone(), size), format, no_mip).unwrap(),
            output_data: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(data.clone(), size), format, no_mip).unwrap(),
            output_color,
            input_light: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(data.clone(), size), format, no_mip).unwrap(),
            output_light: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(data.clone(), size), format, no_mip).unwrap(),
            collision_tex_scale,
            collision_data: texture::Texture2d::with_format(display, RawImage2d::from_raw_rgba(coldata, colsize), format, no_mip).unwrap(),
            
            background,
            
            params: Params::new(),

            modifications_buffer,
            modifications: vec![]
        }
    }

    /// Runs the simulation for one step
    pub fn run(&mut self) {
        self.collision_data.as_surface().clear_color(0.0, 0.0, 0.0, 1.0);

        // Updates simulation parameters
        let mut rng = rand::thread_rng();
        self.params.moveRight = rng.gen_bool(0.5);
        self.params.frame += 1;

        {
            let mut buf = self.modifications_buffer.map();
            for i in 0..(self.modifications.len()).min(MAX_MODIFICATIONS) {
                buf.sim_modifications[i] = self.modifications[i];
            }
        }
        
        // Prepares the textures as images in order for them to be writable by the compute shader
        let img_unit_format = glium::uniforms::ImageUnitFormat::RGBA32F;
        let write = glium::uniforms::ImageUnitAccess::Write;
        let read_write = uniforms::ImageUnitAccess::ReadWrite;
        let output_data_img = self.output_data.image_unit(img_unit_format).unwrap().set_access(write);
        let output_light_img = self.output_light.image_unit(img_unit_format).unwrap().set_access(write);
        let output_color_img = self.output_color.image_unit(img_unit_format).unwrap().set_access(write);
        let collision_img = self.collision_data.image_unit(img_unit_format).unwrap().set_access(read_write);

        // Runs the compute shader with the uniforms
        self.compute_shader.execute(
            uniform! {
                input_data: &self.input_data,
                output_data: output_data_img,
                output_color: output_color_img,
                collision_data: collision_img,
                input_light: &self.input_light,
                output_light: output_light_img,

                moveRight: self.params.moveRight,
                time: self.params.time,
                simSize: (self.size.0 as i32, self.size.1 as i32),
                frame: self.params.frame,
                SimModifications: &self.modifications_buffer,
            }, self.workgroups.0, self.workgroups.1, self.workgroups.2);

        // Swaps the input and output textures so that the output of the current frame
        // is the input of the next frame
        std::mem::swap(&mut self.input_data, &mut self.output_data);
        std::mem::swap(&mut self.input_light, &mut self.output_light);

        unsafe {
            self.output_color.generate_mipmaps();
            //self.output_light.generate_mipmaps();
        };

        {
            let mut buf = self.modifications_buffer.map();
            for i in 0..(self.modifications.len()).min(MAX_MODIFICATIONS) {
                buf.sim_modifications[i].mod_size = 0;
            }
        }
        self.modifications.clear();
    }
}