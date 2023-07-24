use anyhow::{Context, anyhow};
use serde_yaml::{self, Value, Mapping};

#[derive(Debug)]
enum ParsingErr {
    FileNotFound(String),
    MissingField(String),

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
struct SandType {
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
struct SandMaterial {
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



pub fn parse() {
    let cwd = std::env::current_dir().unwrap();
    println!("{:?}", cwd);
    let f = std::fs::read_to_string(
        cwd.join("data")
        .join("materials.yaml")
    ).unwrap();
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
        println!("[sandengine-lang]: Error while parsing rules: '{}'", res.err().unwrap());
    }

    let raw_types = data.get("types").expect("[sandengine-lang]: No 'types' found in input file.");
    let res = parse_types(raw_types.as_mapping().expect("[sandengine-lang]: 'types' is not a mapping (dictionary-like)"), &rules);
    if let Ok(mut result) = res {
        types.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        println!("[sandengine-lang]: Error while parsing types: '{}'", res.err().unwrap());
    }

    let raw_materials = data.get("materials").expect("[sandengine-lang]: No 'materials' found in input file.");
    let res = parse_materials(raw_materials.as_mapping().expect("[sandengine-lang]: 'materials' is not a mapping (dictionary-like)"), &rules, &types);
    if let Ok(mut result) = res {
        materials.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        println!("[sandengine-lang]: Error while parsing materials: '{}'", res.err().unwrap());
    }

}


fn err(msg: &str) {
    println!("[sandengine-lang]: {msg}");
}

fn parse_rules(rules: &Mapping) -> anyhow::Result<(Vec<SandRule>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut rule_structs: Vec<SandRule> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];

    for key in rules {
        // TODO: Convert panics into proper error/ warning system
        let name = key.0.as_str()
        .context(format!("Converting rule name {:?} to string failed", key.0))?
            .to_string();
        let if_cond = key.1.to_owned()
            .get("if")
            .context("Getting 'if:' for rule {name} failed")?
            .as_str()
            .unwrap()
            .to_string();
        let do_action = key.1.to_owned()
            .get("do")
            .context("Getting 'do:' for rule {name} failed")?
            .as_str()
            .unwrap()
            .to_string();
        let is_mirrored = {
            let m = key.1.get("mirrored");
            if let Some(mirror) = m {
                if let Some(mirror) = mirror.as_bool() {
                    mirror
                } else {
                    false
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
            .context(format!("Converting type name {:?} to string failed", sandtype.0))?
            .to_string();
        let inherits = sandtype.1.get("inherits");
        let mut parent = String::new();
        if let Some(p) = inherits {
            let parent_str = p.as_str().context(format!("Converting parent name {:?} failed", p))?;
            for t in type_structs.iter() {
                if t.name == parent_str {
                    parent = parent_str.to_string();
                }
            }
            if parent.is_empty() {
                return Err(anyhow!("Parent/ 'inherits' class {} not found at type definition of {}. Make sure it was defined before this type.", parent_str, name))
            }
        };
        let mut base_rules = vec![];
        let b_rules = sandtype.1.get("base_rules");
        if let Some(b_rules) = b_rules {
            if let Some(b_rules) = b_rules.as_sequence() {
                for baserule in b_rules {
                    let rulename = baserule.as_str().context(format!("Could not convert rulename {:?} in type {}'s baserules to string", baserule, name))?;
                    let mut rule_valid = false;
                    for r in rules {
                        if r.name == rulename {
                            base_rules.push(rulename.to_string());
                            rule_valid = true;
                            break;
                        }
                    };
                    if !rule_valid {
                        return Err(anyhow!("base_rule {} of type {} was not defined in 'rules'.", rulename, name));
                    }
                }
            } else {
                return Err(anyhow!(format!("field 'base_rules' at type '{}' is not a sequence (array/ [])", name)));
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
            .context(format!("Converting material name {:?} to string failed", mat.0))?
            .to_string();

        let mattype = mat.1.get("type")
            .context(format!("Getting the 'type' field for material {} failed. Make sure it exists.", name))?;
        let mattype = mattype.as_str()
            .context(format!("Converting typename {:?} at material {} failed.", mattype, name))?
            .to_string();
        let mut type_valid = false;
        for t in types {
            if t.name == mattype {
                type_valid = true;
                break;
            }
        };
        if !type_valid {
            return Err(anyhow!(format!("Type {} is not a valid material type (in definition of material {}). Make sure it is defined in 'types' first.", mattype, name)));
        }

        let mut color = [1.0, 0.0, 1.0, 1.0];
        let color_val = mat.1.get("color")
            .context(format!("Getting the 'color' for material {} failed. Make sure the field exists.", name))?;
        // TODO: Add alternative HEX color definition
        if let Some(col) = color_val.as_sequence() {
            if col.len() > 4 || col.is_empty() {
                return Err(anyhow!(format!("Getting color information for material {} failed. Make sure it is an array of at least 3, max. 4 elements (float 0-1 or int 0-255).", name)));
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
                return Err(anyhow!(format!("Getting color information for material {} failed. Make sure it is an array of at least 3, max. 4 elements (float 0-1 or int 0-255).", name)));
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
            .context(format!("Getting 'density' field for material {} failed. Make sure it exists.", name))?
            .as_f64()
            .context(format!("'density' value at material {} is not a float.", name))?
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
                        return Err(anyhow!(format!("The extra_rule '{:?}' field at material {} is not a string", extra_rule, name)));
                    }
                }
            } else {
                return Err(anyhow!(format!("The 'extra_rules' field at material {} is not a sequence (array/ '[]').", name)));
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