pub mod parser;
use std::path::PathBuf;

use colored::Colorize;
pub use parser::{parse_string, GLSLConvertible, ParsingResult};

// TODO: Create a validator function (extra file) that checks every if/ do condition??

/// Reads a file to a string and parses that string using the parser
pub fn parse_path(filepath: PathBuf) -> anyhow::Result<ParsingResult> {
    let f = std::fs::read_to_string(filepath).unwrap();
    parse_string(&f)
}


/// Creates the procedually generated GLSL files from the ParsingResult
pub fn create_glsl_from_parser(result: &ParsingResult) {
    let cwd = std::env::current_dir().unwrap();

    // ========== Create materials.glsl which contains materials and types ==========
    let mut materials_types = String::from("");

    for t in result.types.iter() {
        materials_types.push_str(t.get_glsl_code().as_str());
    };
    // All checker functions may reference other types defined before this type,
    // so first define all types, then all checker functions
    for t in result.types.iter() {
        materials_types.push_str(t.get_checker_func().as_str());
    };
    materials_types.push('\n');
    let mut all_mats_list = String::new();
    for m in result.materials.iter() {
        materials_types.push_str(m.get_glsl_code().as_str());
        all_mats_list.push_str(format!("MAT_{},\n", m.name.clone()).as_str());
    };

    // We need those functions on the GPU side for converting the uniform inputMaterialID into a material struct
    let helpers_functions = format!("
Material[{}] materials() {{
    Material allMaterials[{}] = {{
        {}
    }};
    return allMaterials;
}}

Material getMaterialFromID(int id) {{
    for (int i = 0; i < materials().length(); i++) {{
        if (id == materials()[i].id) {{
            return materials()[i];
        }};
    }};
    return MAT_NULL;
}}\n\n", result.materials.len(), result.materials.len(), all_mats_list);

    materials_types.push_str(helpers_functions.as_str());

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
        // only generate code for rules that have actually been used by types or materials
        if r.used {
            rule_functions.push_str(format!("{}\n\n", r.get_glsl_code()).as_str());
            // Depending on the mirrored type of the rule, we call them with different cells
            match r.ruletype {
                parser::SandRuleType::Mirrored => {
                    mirrored_rules_call.push_str(format!("rule_{}(self, right, down, downright, pos);\n", r.name).as_str());
                },
                parser::SandRuleType::Left => {
                    left_rules_call.push_str(format!("rule_{}(self, left, down, downright, pos);\n", r.name).as_str());
                },
                parser::SandRuleType::Right => {
                    right_rules_call.push_str(format!("rule_{}(self, right, down, downright, pos);\n", r.name).as_str());
                }
            };
        }
    });
    let path = cwd
        .join("shaders")
        .join("compute")
        .join("gen")
        .join("rules.glsl");
    let rulefile_content = format!(
"
// =============== RULES ===============
{}


// =============== CALLERS ===============
void applyMirroredRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {{
    {}
}}


void applyLeftRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {{
    {}
}}

void applyRightRules(
    inout Cell self,
    inout Cell right,
    inout Cell down,
    inout Cell downright,
    ivec2 pos) {{
    {}
}}", rule_functions, mirrored_rules_call.trim_end(), left_rules_call.trim_end(), right_rules_call.trim_end());

    let res = std::fs::write(path.clone(), rulefile_content);
    if let Err(err) = res {
        println!("{} Err creating file '{}': '{}'", "[sandengine-lang]:".red().bold(), path.display(), err);
    };
}