pub mod parser;
use colored::Colorize;
use parser::{parse_string, GLSLConvertible};

const MATERIAL_STRUCT: &'static str = 
"struct Material {
    int id;
    vec4 color;
    float density;
    vec4 emission;

    int type;
};
";


pub fn parse() {
    let cwd = std::env::current_dir().unwrap();
    let filepath = cwd.join("data")
        .join("materials.yaml");
    let f = std::fs::read_to_string(filepath).unwrap();
    let parse_res = parse_string(f);
    match parse_res {
        Ok(result) => {
            println!("{}{:#?}", "Rules: ".bold(), result.rules);
            println!("{}{:#?}", "Types: ".bold(), result.types);
            println!("{}{:#?}", "Materials: ".bold(), result.materials);
            println!("{}", "[sandengine-lang]: Parsing ok.".green().bold());

            let mut materials_types = String::from(MATERIAL_STRUCT);

            for t in result.types {
                materials_types.push_str(t.get_glsl_code().as_str());
            };
            for m in result.materials {
                materials_types.push_str(m.get_glsl_code().as_str());
            };

            let path = cwd
                .join("shaders")
                .join("compute")
                .join("gen")
                .join("materials.glsl");
            let res = std::fs::write(path.clone(), materials_types);
            if let Err(err) = res {
                println!("{} Err creating file '{}': '{}'", "[sandengine-lang]:".red().bold(), path.display(), err);
            }
        },
        Err(err) => {
            println!("{} '{}'", "[sandengine-lang]:".red().bold(), err);
        }
    }
}