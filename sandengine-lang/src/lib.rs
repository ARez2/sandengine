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
            // println!("{}{:#?}", "Rules: ".bold(), result.rules);
            // println!("{}{:#?}", "Types: ".bold(), result.types);
            // println!("{}{:#?}", "Materials: ".bold(), result.materials);
            println!("{}", "[sandengine-lang]: Parsing ok.".green().bold());

            // ========== Create materials.glsl which contains materials and types ==========
            let mut materials_types = String::from(MATERIAL_STRUCT);

            for t in result.types {
                materials_types.push_str(t.get_glsl_code().as_str());
            };
            materials_types.push('\n');
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
            };

            // ========== Create rules.glsl which contains all rules and rule callers ==========
            let mut rule_functions = String::new();
            let mut mirrored_rules_call = String::new();
            let mut left_rules_call = String::new();
            let mut right_rules_call = String::new();

            result.rules.iter().for_each(|r| {
                rule_functions.push_str(format!("{}\n\n", r.get_glsl_code()).as_str());
                match r.ruletype {
                    parser::SandRuleType::Mirrored => {
                        mirrored_rules_call.push_str(format!("rule_{}(SELF, RIGHT, DOWN, DOWNRIGHT, pos);\n", r.name).as_str());
                    },
                    parser::SandRuleType::Left => {
                        left_rules_call.push_str(format!("rule_{}(SELF, LEFT, DOWN, DOWNRIGHT, pos);\n", r.name).as_str());
                    },
                    parser::SandRuleType::Right => {
                        right_rules_call.push_str(format!("rule_{}(SELF, RIGHT, DOWN, DOWNRIGHT, pos);\n", r.name).as_str());
                    }
                };
            });
            let path = cwd
                .join("shaders")
                .join("compute")
                .join("gen")
                .join("rules.glsl");
            let mut rulefile_content = format!(
"
// =============== RULES ===============
{}


// =============== CALLERS ===============
void applyMirroredRules(
    inout Cell SELF,
    inout Cell RIGHT,
    inout Cell DOWN,
    inout Cell DOWNRIGHT,
    ivec2 pos) {{
    {}
}}


void applyLeftRules(
    inout Cell SELF,
    inout Cell LEFT,
    inout Cell DOWN,
    inout Cell DOWNLEFT,
    ivec2 pos) {{
    {}
}}

void applyRightRules(
    inout Cell SELF,
    inout Cell RIGHT,
    inout Cell DOWN,
    inout Cell DOWNRIGHT,
    ivec2 pos) {{
    {}
}}", rule_functions, mirrored_rules_call.trim_end(), left_rules_call.trim_end(), right_rules_call.trim_end());

            let res = std::fs::write(path.clone(), rulefile_content);
            if let Err(err) = res {
                println!("{} Err creating file '{}': '{}'", "[sandengine-lang]:".red().bold(), path.display(), err);
            };
        },
        Err(err) => {
            println!("{} {}", "[sandengine-lang]:".red().bold(), err);
        }
    }
}