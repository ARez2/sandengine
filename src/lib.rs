

pub fn run() {
    build_shaders();
    sandengine_core::run();
}


fn build_shaders() {
    std::fs::read_dir("shaders/").unwrap().into_iter().filter(|f| {
        if let Ok(file) = f {
            return file.path().is_file() && file.path().extension().unwrap() == "glsl";
        } else {
            return false;
        };
    }).for_each(|file| {
        let mut had_includes: bool = false;

        let path = file.unwrap().path();
        let mut contents = std::fs::read_to_string(path.clone()).unwrap();
        let searchstr = "#include \"";
        let mut start_idx = contents.find(searchstr).unwrap_or(0);
        while start_idx != 0 {
            had_includes = true;
            let incl_path = contents
                                    .split_at(start_idx + searchstr.len()).1
                                    .split("\"\n")
                                    .nth(0)
                                    .unwrap();
            println!("{}: Include path: {}", path.clone().display(), incl_path);
            let incl_src = std::fs::read_to_string(path.parent().unwrap().join(incl_path));
            if let Ok(mut incl_src) = incl_src {
                incl_src.push_str("\n\n\n");
                let start_idx = contents.find(searchstr).unwrap();
                let end_idx = start_idx + searchstr.len() + incl_path.len() + 1;
                contents.replace_range(start_idx..end_idx, incl_src.as_str());
            }

            start_idx = contents.find("#include ").unwrap_or(0);
        }

        if had_includes {
            std::fs::write(format!("shaders/gen/{}", path.file_name().unwrap().to_str().unwrap()), contents).unwrap();
        }
    });
}