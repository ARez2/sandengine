use std::{fmt::Debug, path::PathBuf};

use anyhow::{anyhow, bail};
use thiserror::Error;
use serde_yaml::{self, Mapping};


const TYPE_HINT_STRING: &'static str = "string";
const TYPE_HINT_BOOL: &'static str = "bool (true/false)";
const TYPE_HINT_FLOAT: &'static str = "float";
const TYPE_HINT_SEQUENCE: &'static str = "sequence (array, '[...]'";
const TYPE_HINT_COLOR: &'static str = "sequence (array, '[...]' of 3-4 floats (range 0.0-1.0) OR integers (range 0-255). With 3 elements, the alpha channel defaults to 1.0";


#[derive(Debug, Error)]
enum ParsingErr<T: Debug> {
    #[error("Mandatory field '{field_name}' is missing in '{missing_in}'")]
    MissingField {
        field_name: String,
        missing_in: String,
    },

    #[error("The type of the field '{wrong_type:?}' inside of '{missing_in}' is invalid. The expect type would be: '{expected}'")]
    InvalidType {
        wrong_type: T,
        missing_in: String,
        expected: &'static str,
    },

    #[error("The name '{missing}' (in '{missing_in}') was not found. Make sure it was defined before referencing it.")]
    NotFound {
        missing: String,
        missing_in: String,
    }
}


trait GLSLConvertible {
    fn get_glsl_code(&self) -> String;
}

#[derive(Debug, Clone)]
pub struct SandRule {
    /// Name of the rule (Mapping key)
    pub name: String,
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
        String::new()
    }
}

#[derive(Debug, Clone)]
pub struct SandType {
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
        String::new()
    }
}

#[derive(Debug, Clone)]
pub struct SandMaterial {
    pub name: String,
    pub mattype: String,
    pub color: [f32; 4],
    pub selectable: bool,
    pub density: f32,
    pub extra_rules: Vec<String>
}
impl GLSLConvertible for SandMaterial {
    fn get_glsl_code(&self) -> String {
        String::new()
    }
}

pub struct ParsingResult {
    pub rules: Vec<SandRule>,
    pub types: Vec<SandType>,
    pub materials: Vec<SandMaterial>,
    pub data_serialized: Vec<Box<dyn GLSLConvertible>>,
}


pub fn parse() {
    let cwd = std::env::current_dir().unwrap();
    let filepath = cwd.join("data")
        .join("materials.yaml");
    let parse_res = parse_file(filepath);
    match parse_res {
        Ok(result) => {

        },
        Err(err) => {
            println!("[sandengine-lang]: '{}'", err);
        }
    }
}


fn parse_file(file: PathBuf) -> anyhow::Result<ParsingResult> {
    let f = std::fs::read_to_string(file).unwrap();
    let data: serde_yaml::Value = serde_yaml::from_str(&f).unwrap();

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
        let if_cond = if_cond.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: if_cond.clone(),
                missing_in: format!("rules/{}/if", name),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        let do_action = key.1
            .get("do")
            .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
                field_name: "do".to_string(),
                missing_in: format!("rules/{}", name)
            }))?;
        let do_action = do_action.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: do_action.clone(),
                missing_in: format!("rules/{}/do", name),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        let is_mirrored = {
            let m = key.1.get("mirrored");
            if let Some(mirror) = m {
                if let Some(mirror) = mirror.as_bool() {
                    mirror
                } else {
                    bail!(ParsingErr::InvalidType {
                        wrong_type: mirror.clone(),
                        missing_in: format!("rules/{}", name),
                        expected: TYPE_HINT_BOOL })
                }
            } else {
                false
            }
        };
        let rule = SandRule {
            name,
            if_cond,
            do_action,
            mirror: is_mirrored,
        };
        println!("{rule:?}");
        rule_structs.push(rule.clone());
        glsl_structs.push(Box::new(rule));
    }

    Ok((rule_structs, glsl_structs))
}


fn parse_types(types: &Mapping, rules: &Vec<SandRule>) -> anyhow::Result<(Vec<SandType>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut type_structs: Vec<SandType> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];
    
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
                wrong_type: p.clone(),
                missing_in: format!("types/{}/inherits", name),
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
                            wrong_type: baserule.clone(),
                            missing_in: format!("types/{}/base_rules", name),
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
            name,
            inherits: parent,
            base_rules
        };
        println!("{:?}", s_type);
        type_structs.push(s_type.clone());
        glsl_structs.push(Box::new(s_type));
    }
    
    Ok((type_structs, glsl_structs))
}


fn parse_materials(materials: &Mapping, rules: &Vec<SandRule>, types: &Vec<SandType>) -> anyhow::Result<(Vec<SandMaterial>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut material_structs: Vec<SandMaterial> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];

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
                wrong_type: mattype.clone(),
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

        let mut color = [1.0, 0.0, 1.0, 1.0];
        let color_val = mat.1.get("color")
            .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
                field_name: "color".to_string(),
                missing_in: format!("materials/{}", name),
            }))?;
        // TODO: Add alternative HEX color definition
        if let Some(col) = color_val.as_sequence() {
            if col.is_empty() || col.len() > 4 || col.len() < 3 {
                bail!(ParsingErr::InvalidType {
                    wrong_type: col.clone(),
                    missing_in: format!("materials/{}/color", name),
                    expected: TYPE_HINT_COLOR,
                });
            }
            for (idx, comp) in col.iter().enumerate() {
                if let Some(comp) = comp.as_f64() {
                    color[idx] = comp as f32;
                    continue;
                }
                if let Some(comp) = comp.as_u64() {
                    if comp > 0 && comp <= 255 {
                        color[idx] = comp as f32 / 255.0;
                        continue;
                    }
                }
                bail!(ParsingErr::InvalidType {
                    wrong_type: comp.clone(),
                    missing_in: format!("materials/{}/color", name),
                    expected: TYPE_HINT_COLOR
                });
            }
        }

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
                wrong_type: density.clone(),
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
                            wrong_type: extra_rule.clone(),
                            missing_in: format!("materials/{}/extra_rules", name),
                            expected: TYPE_HINT_STRING
                        });
                    }
                }
            } else {
                bail!(ParsingErr::InvalidType {
                    wrong_type: extra.clone(),
                    missing_in: format!("materials/{}/extra_rules", name),
                    expected: TYPE_HINT_SEQUENCE,
                });
            }
        }
        
        let mat = SandMaterial {
            name,
            mattype,
            color,
            selectable,
            density,
            extra_rules
        };
        println!("{:?}", mat);
        material_structs.push(mat.clone());
        glsl_structs.push(Box::new(mat));
    }

    
    Ok((material_structs, glsl_structs))
}