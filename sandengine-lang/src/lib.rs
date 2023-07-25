pub mod parser;
use colored::Colorize;
use parser::parse_file;

pub fn parse() {
    let cwd = std::env::current_dir().unwrap();
    let filepath = cwd.join("data")
        .join("materials.yaml");
    let parse_res = parse_file(filepath);
    match parse_res {
        Ok(result) => {
            println!("{}{:#?}", "Rules: ".bold(), result.rules);
            println!("{}{:#?}", "Types: ".bold(), result.types);
            println!("{}{:#?}", "Materials: ".bold(), result.materials);
            println!("{}", "[sandengine-lang]: Parsing ok.".green().bold());
        },
        Err(err) => {
            println!("{} '{}'", "[sandengine-lang]:".red().bold(), err);
        }
    }
}