use std::{fmt::Debug, path::PathBuf};

use anyhow::{anyhow, bail};
use thiserror::Error;
use serde_yaml::{self, Mapping, Value};
use regex::Regex;

use colored::Colorize;


const TYPE_HINT_STRING: &'static str = "string";
const TYPE_HINT_BOOL: &'static str = "bool (true/false)";
const TYPE_HINT_FLOAT: &'static str = "float";
const TYPE_HINT_SEQUENCE: &'static str = "sequence (array, '[...]')";
const TYPE_HINT_COLOR: &'static str = "sequence (array, '[...]') of 3-4 floats (range 0.0-1.0) OR integers (range 0-255). (With 3 elements, the alpha channel defaults to 1.0)";

const GLOBAL_CELLS: [&'static str; 6] = [
    "SELF",
    "LEFT",
    "RIGHT",
    "DOWN",
    "DOWNRIGHT",
    "DOWNLEFT"
];

const DEFAULT_VAL_MIRRORED: bool = false;


#[derive(Debug, Error)]
enum ParsingErr<T: Debug> {
    #[error("{} Mandatory field '{}' is {} '{}'", "(MissingField)".red(), .field_name.bold(), "missing in".bold(), .missing_in.bold())]
    MissingField {
        field_name: String,
        missing_in: String,
    },

    #[error("{} The type of the field '{:?}' inside of '{}' {}. Expected: '{}'", "(InvalidType)".red(),.wrong_type, .missing_in.bold(), "is invalid".bold(), .expected.bold())]
    InvalidType {
        wrong_type: T,
        missing_in: String,
        expected: &'static str,
    },

    #[error("{} The name '{}' (in '{}') {}. Make sure it was defined before referencing it.", "(NotFound)".red(),.missing.bold(), .missing_in.bold(), "was not found".bold())]
    NotFound {
        missing: String,
        missing_in: String,
    },

    #[error("{} The expression '{}' (in '{}') {}.", "(NotRecognized)".red(),.unrecog.bold(), .missing_in.bold(), "was not recognized as valid syntax. Please check it is valid".bold())]
    NotRecognized {
        unrecog: String,
        missing_in: String
    }
}


pub trait GLSLConvertible {
    fn get_glsl_code(&self) -> String;
}

#[derive(Debug, Clone, PartialEq)]
pub enum SandRuleType {
    Mirrored,
    Left,
    Right
}

#[derive(Debug, Clone)]
pub struct SandRule {
    /// Name of the rule (Mapping key)
    pub name: String,
    /// Type of the rule to help sort the rules
    pub ruletype: SandRuleType,
    /// Expression that will need to be true in order
    /// for the 'do' action(s) to run
    pub if_cond: String,
    /// Action(s) that will be run when the if-condition evals to true
    pub do_action: String,
    /// Whether the rule is mirrored horizontally
    pub mirror: bool
}
impl GLSLConvertible for SandRule {
    fn get_glsl_code(&self) -> String {
        format!(
"void rule_{} (inout Cell SELF, inout Cell RIGHT, inout Cell DOWN, inout Cell DOWNRIGHT, ivec2 pos) {{
    if ({}) {{
        {}
    }}
}}", self.name, self.if_cond, self.do_action)

    }
}

// TODO: Add a new property called all_rules where every rule (even inherited) get collected
// TODO: before calling each rule, check if the material is this type

#[derive(Debug, Clone)]
pub struct SandType {
    /// Index/ ID of the type
    pub id: usize,
    /// Name of the type (Mapping key)
    pub name: String,
    /// Name of the parent type
    pub inherits: String,
    /// List of names of the rules that are applied to all
    /// materials of this type
    pub base_rules: Vec<String>
}
impl GLSLConvertible for SandType {
    fn get_glsl_code(&self) -> String {
        format!("#define TYPE_{} {}\n", self.name, self.id)
    }
}


// TODO: Check if certain material is the material with extra_rules, then apply those

#[derive(Debug, Clone)]
pub struct SandMaterial {
    /// Index/ ID of the material
    pub id: usize,
    pub name: String,
    pub mattype: String,
    pub color: [f32; 4],
    pub emission: [f32; 4],
    pub selectable: bool,
    pub density: f32,
    pub extra_rules: Vec<String>
}
impl GLSLConvertible for SandMaterial {
    fn get_glsl_code(&self) -> String {
        format!("#define MAT_{} Material({}, vec4({}, {}, {}, {}), {}, vec4({}, {}, {}, {}), TYPE_{})\n",
            self.name,
            self.id,
            self.color[0],
            self.color[1],
            self.color[2],
            self.color[3],
            self.density,
            self.emission[0],
            self.emission[1],
            self.emission[2],
            self.emission[3],
            self.mattype,
        )
    }
}

pub struct ParsingResult {
    pub rules: Vec<SandRule>,
    pub types: Vec<SandType>,
    pub materials: Vec<SandMaterial>,
    pub data_serialized: Vec<Box<dyn GLSLConvertible>>,
}



pub fn parse_string(f: String) -> anyhow::Result<ParsingResult> {
    let data: Result<_, serde_yaml::Error> = serde_yaml::from_str(&f);
    if let Err(err) = data {
        bail!(err);
    }
    let data: serde_yaml::Value = data.unwrap();

    let mut data_serialized: Vec<Box<dyn GLSLConvertible>> = vec![];
    let mut rules: Vec<SandRule> = vec![];
    let mut types: Vec<SandType> = vec![];
    let mut materials: Vec<SandMaterial> = vec![];
    
    let raw_rules = data.get("rules").expect("[sandengine-lang]: No 'rules' found in input file.");
    let res = parse_rules(raw_rules.as_mapping().expect("[sandengine-lang]: 'rules' is not a mapping (dictionary-like)"));
    if let Ok(mut result) = res {
        rules.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing rules: '{}'", res.err().unwrap());
    }

    let raw_types = data.get("types").expect("[sandengine-lang]: No 'types' found in input file.");
    let res = parse_types(raw_types.as_mapping().expect("[sandengine-lang]: 'types' is not a mapping (dictionary-like)"), &rules);
    if let Ok(mut result) = res {
        types.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing types: '{}'", res.err().unwrap());
    }

    let raw_materials = data.get("materials").expect("[sandengine-lang]: No 'materials' found in input file.");
    let res = parse_materials(raw_materials.as_mapping().expect("[sandengine-lang]: 'materials' is not a mapping (dictionary-like)"), &rules, &types);
    if let Ok(mut result) = res {
        materials.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing materials: '{}'", res.err().unwrap());
    }

    Ok(ParsingResult {
        rules,
        types, materials,
        data_serialized
    })
}




fn parse_rules(rules: &Mapping) -> anyhow::Result<(Vec<SandRule>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut rule_structs: Vec<SandRule> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];

    for key in rules {
        let name = key.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType{
                wrong_type: key.0.clone(),
                missing_in: "rules".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        let if_cond = key.1
            .get("if")
            .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
                field_name: "if".to_string(),
                missing_in: format!("rules/{}", name)
            }))?;
        let mut if_cond = if_cond.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "if".to_string(),
                missing_in: format!("rules/{}", name),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();

        if_cond = if_cond.replace(" or ", " || ");
        if_cond = if_cond.replace(" and ", " && ");

        let do_action = key.1
            .get("do")
            .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
                field_name: "do".to_string(),
                missing_in: format!("rules/{}", name)
            }))?;
        
        // The final string that is the do action
        let mut do_string = String::new();
        let parent_path = &format!("rules/{}", name);
        if let Some(do_action) = do_action.as_str() {
            do_string = parse_do(parent_path, do_action)?;
        };

        if let Some(do_list) = do_action.as_sequence() {
            for do_action in do_list {
                if let Some(do_action) = do_action.as_str() {
                    let do_str = parse_do(parent_path, do_action)?;
                    do_string.push_str(&do_str);
                }
            }
        };
        do_string = do_string.trim_end().to_string();

        let else_ = key.1.get("else");
        let parent_path = &format!("rules/{}/else", name);

        

        
        let is_mirrored = {
            let m = key.1.get("mirrored");
            if let Some(mirror) = m {
                if let Some(mirror) = mirror.as_bool() {
                    mirror
                } else {
                    bail!(ParsingErr::InvalidType {
                        wrong_type: "mirrored",
                        missing_in: format!("rules/{}", name),
                        expected: TYPE_HINT_BOOL })
                }
            } else {
                DEFAULT_VAL_MIRRORED
            }
        };

        let ruletype = match is_mirrored {
            true => SandRuleType::Mirrored,
            false => {
                if do_string.contains("LEFT") {
                    SandRuleType::Left
                } else {
                    SandRuleType::Right
                }
            }
        };

        let rule = SandRule {
            name,
            ruletype,
            if_cond,
            do_action: do_string,
            mirror: is_mirrored,
        };
        rule_structs.push(rule.clone());
        glsl_structs.push(Box::new(rule));
    }

    Ok((rule_structs, glsl_structs))
}


/// Converts a string with YAML 'do-syntax' into valid GLSL code which can be run
fn parse_do(parent: &str, do_str: &str) -> anyhow::Result<String> {
    let mut do_string = String::new();

    let mut found_match = false;

    let swap_pattern = r"SWAP (\w+) (\w+)";
    let re = Regex::new(swap_pattern).unwrap();
    
    if let Some(captures) = re.captures(do_str) {
        found_match = true;

        let first_cell = captures.get(1).unwrap().as_str();
        if !GLOBAL_CELLS.contains(&first_cell) {
            bail!(ParsingErr::<bool>::NotFound {
                missing: first_cell.to_string(),
                missing_in: format!("{}/do", parent)
            });
        };
        let second_cell = captures.get(2).unwrap().as_str();
        if !GLOBAL_CELLS.contains(&second_cell) {
            bail!(ParsingErr::<bool>::NotFound {
                missing: second_cell.to_string(),
                missing_in: format!("{}/do", parent)
            });
        }

        do_string.push_str(format!("swap({}, {});\n", first_cell, second_cell).as_str());
    }

    let set_pattern = r"SET (\w+) (\w+)";
    let re = Regex::new(set_pattern).unwrap();
    if let Some(captures) = re.captures(do_str) {
        found_match = true;
        
        // Needs to be a cell
        let first_arg = captures.get(1).unwrap().as_str();
        if !GLOBAL_CELLS.contains(&first_arg) {
            bail!(ParsingErr::<bool>::NotFound {
                missing: first_arg.to_string(),
                missing_in: format!("{}/do", parent)
            });
        }
        // TODO: Check if it is either a GLOBAL_CELL or material
        // Right now, it just assumes its a material
        let second_arg = captures.get(2).unwrap().as_str();
        do_string.push_str(format!("{} = setCell({}, pos);\n", first_arg, second_arg).as_str());
    }

    if !found_match {
        bail!(ParsingErr::<bool>::NotRecognized {
            unrecog: do_str.to_string(),
            missing_in: format!("{}/do", parent)
        });
    }

    Ok(do_string)
}



fn parse_types(types: &Mapping, rules: &Vec<SandRule>) -> anyhow::Result<(Vec<SandType>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut type_structs: Vec<SandType> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];
    
    let mut idx = 0;
    for sandtype in types {
        let name = sandtype.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: sandtype.0.clone(),
                missing_in: "types".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        let inherits = sandtype.1.get("inherits");
        let mut parent = String::new();
        if let Some(p) = inherits {
            let parent_str = p.as_str().ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "inherits",
                missing_in: format!("types/{}", name),
                expected: TYPE_HINT_STRING
            }))?;
            for t in type_structs.iter() {
                if t.name == parent_str {
                    parent = parent_str.to_string();
                }
            }
            if parent.is_empty() {
                bail!(ParsingErr::<bool>::NotFound {
                    missing: parent_str.to_string(),
                    missing_in: format!("types/{}", name),
                });
            }
        };
        let mut base_rules = vec![];
        let b_rules = sandtype.1.get("base_rules");
        if let Some(b_rules) = b_rules {
            if let Some(b_rules) = b_rules.as_sequence() {
                for baserule in b_rules {
                    let rulename = baserule.as_str().ok_or(
                        anyhow!(ParsingErr::InvalidType {
                            wrong_type: "base_rules",
                            missing_in: format!("types/{}", name),
                            expected: TYPE_HINT_STRING
                        }))?;
                    let mut rule_valid = false;
                    for r in rules {
                        if r.name == rulename {
                            base_rules.push(rulename.to_string());
                            rule_valid = true;
                            break;
                        }
                    };
                    if !rule_valid {
                        bail!(ParsingErr::<bool>::NotFound {
                            missing: rulename.to_string(),
                            missing_in: format!("types/{}/base_rules", name),
                        });
                    }
                }
            } else {
                bail!(ParsingErr::InvalidType {
                    wrong_type: "base_rules",
                    missing_in: format!("types/{}", name),
                    expected: TYPE_HINT_SEQUENCE,
                });
            }
        };

        let s_type = SandType {
            id: idx,
            name,
            inherits: parent,
            base_rules
        };
        type_structs.push(s_type.clone());
        glsl_structs.push(Box::new(s_type));

        idx += 1;
    }
    
    Ok((type_structs, glsl_structs))
}


fn parse_materials(materials: &Mapping, rules: &Vec<SandRule>, types: &Vec<SandType>) -> anyhow::Result<(Vec<SandMaterial>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut material_structs: Vec<SandMaterial> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];

    let mut idx = 0;
    for mat in materials {
        let name = mat.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: mat.0.clone(),
                missing_in: "materials".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();

        let mattype = mat.1.get("type")
            .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
                field_name: "type".to_string(),
                missing_in: format!("materials/{}", name)
            }))?;
        let mattype = mattype.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "type".to_string(),
                missing_in: format!("materials/{}", name),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        let mut type_valid = false;
        for t in types {
            if t.name == mattype {
                type_valid = true;
                break;
            }
        };
        if !type_valid {
            bail!(ParsingErr::<bool>::NotFound {
                missing: mattype,
                missing_in: format!("materials/{}/type", name)
            });
        }

        let color = extract_vec4(mat.1, name.clone(), "color", [1.0, 0.0, 1.0, 1.0], true)?;
        let emission = extract_vec4(mat.1, name.clone(), "emission", [0.0, 0.0, 0.0, 0.0], false)?;

        let selectable = match mat.1.get("selectable") {
            Some(selectable) => {
                if let Some(selectable) = selectable.as_bool() {
                    selectable
                } else {
                    false
                }
            },
            None => true,
        };

        let density = mat.1.get("density")
            .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
                field_name: "density".to_string(),
                missing_in: format!("materials/{}", name)
            }))?;
        let density = density.as_f64()
            .ok_or(ParsingErr::InvalidType {
                wrong_type: "density".to_string(),
                missing_in: format!("materials/{}/density", name),
                expected: TYPE_HINT_FLOAT
            })?
            as f32;
        
        let mut extra_rules = Vec::<String>::new();
        let extra_rules_data = mat.1.get("extra_rules");
        if let Some(extra) = extra_rules_data {
            if let Some(extra) = extra.as_sequence() {
                for extra_rule in extra {
                    if let Some(extra_rule) = extra_rule.as_str() {
                        for r in rules {
                            if r.name == extra_rule {
                                extra_rules.push(extra_rule.to_string());
                            }
                        }
                    } else {
                        bail!(ParsingErr::InvalidType {
                            wrong_type: "extra_rules",
                            missing_in: format!("materials/{}", name),
                            expected: TYPE_HINT_STRING
                        });
                    }
                }
            } else {
                bail!(ParsingErr::InvalidType {
                    wrong_type: "extra_rules",
                    missing_in: format!("materials/{}", name),
                    expected: TYPE_HINT_SEQUENCE,
                });
            }
        }
        
        let mat = SandMaterial {
            id: idx,
            name,
            mattype,
            color,
            emission,
            selectable,
            density,
            extra_rules
        };
        material_structs.push(mat.clone());
        glsl_structs.push(Box::new(mat));

        idx += 1;
    }

    
    Ok((material_structs, glsl_structs))
}


fn extract_vec4(yaml_data: &Value, parent_name: String, field_name: &'static str, default: [f32; 4], mandatory: bool) -> anyhow::Result<[f32; 4]> {
    let missing_in = format!("materials/{}/{}", parent_name, field_name);
    let vec4_data = yaml_data.get(field_name);

    if vec4_data.is_none() {
        if mandatory {
            bail!(ParsingErr::<bool>::MissingField {
                field_name: field_name.to_string(),
                missing_in,
            });
        } else {
            return Ok(default);
        }
    };

    let vec4_val = vec4_data.unwrap();
    
    let mut vec4 = default;
    // TODO: Add alternative HEX color definition
    if let Some(comps) = vec4_val.as_sequence() {
        if comps.is_empty() || comps.len() > 4 || comps.len() < 3 {
            bail!(ParsingErr::InvalidType {
                wrong_type: field_name,
                missing_in,
                expected: TYPE_HINT_COLOR,
            });
        }
        for (idx, comp) in comps.iter().enumerate() {
            if let Some(comp) = comp.as_u64() {
                if comp > 0 && comp <= 255 {
                    vec4[idx] = comp as f32 / 255.0;
                    continue;
                }
            }
            if let Some(comp) = comp.as_f64() {
                if comp > 1.0 && comp <= 255.0 {
                    vec4[idx] = comp as f32 / 255.0;
                    continue;
                } else if comp >= 0.0 && comp <= 1.0 {
                    vec4[idx] = comp as f32;
                    continue;
                }
            }
            
            bail!(ParsingErr::InvalidType {
                wrong_type: field_name,
                missing_in,
                expected: TYPE_HINT_COLOR
            });
        };
    } else {
        bail!(ParsingErr::InvalidType {
            wrong_type: field_name,
            missing_in,
            expected: TYPE_HINT_COLOR
        });
    }
    Ok(vec4)
}