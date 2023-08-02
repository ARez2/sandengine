use std::str::FromStr;
use colored::Colorize;

pub extern crate sandengine_lang;

pub fn run() {
    let parse_res = sandengine_lang::parse();
    match parse_res {
        Ok(result) => {
            // println!("{}{:#?}", "Rules: ".bold(), result.rules);
            // println!("{}{:#?}", "Types: ".bold(), result.types);
            println!("{}{:#?}", "Materials: ".bold(), result.materials);
            println!("{}", "[sandengine-lang]: Parsing ok.".green().bold());
            sandengine_lang::create_glsl_from_parser(&result);
            
            build_compute_shaders();
            sandengine_core::run(result);
        },
        Err(err) => {
            println!("{} {}", "[sandengine-lang]:".red().bold(), err);
        }
    };
}



fn build_compute_shaders() {
    let shaderpath = std::path::PathBuf::from_str("shaders/compute").unwrap();
    std::fs::read_dir(shaderpath.clone()).unwrap().filter(|f| {
        if let Ok(file) = f {
            return file.path().is_file() && file.path().extension().unwrap() == "glsl";
        } else {
            false
        }
    }).for_each(|file| {
        let mut had_includes: bool = false;

        let path = file.unwrap().path();
        let mut contents = std::fs::read_to_string(path.clone()).unwrap();
        let searchstr = "\n#include \"";
        let mut start_idx = contents.find(searchstr).unwrap_or(0);
        while start_idx != 0 {
            had_includes = true;
            let incl_path = contents
                    .split_at(start_idx + searchstr.len()).1
                    .split("\"").next()
                    .unwrap();
            println!("{}: Include path: {}", path.clone().display(), incl_path);
            let incl_src = std::fs::read_to_string(path.parent().unwrap().join(incl_path));
            if let Ok(mut incl_src) = incl_src {
                incl_src.push_str("\n\n\n");
                let start_idx = contents.find(searchstr).unwrap();
                let end_idx = start_idx + searchstr.len() + incl_path.len() + 1;

                let char_before = contents.chars().nth(start_idx - 1).unwrap();
                if char_before == ' ' || char_before == '/' {
                    contents.replace_range(start_idx..end_idx, "");
                } else {
                    contents.replace_range(start_idx..end_idx, incl_src.as_str());
                }
            }

            start_idx = contents.find(searchstr).unwrap_or(0);
        }

        if had_includes {
            std::fs::write(shaderpath.join("gen").join(path.file_name().unwrap().to_str().unwrap()), contents).unwrap();
        }
    });
}