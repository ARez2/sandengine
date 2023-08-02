use std::{fmt::Debug, path::PathBuf, default::{self, Default}};

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
    pub if_conds: Vec<String>,
    /// Action(s) that will be run when the if-condition evals to true
    pub do_actions: Vec<String>,
    /// Whether the rule is mirrored horizontally
    pub mirror: bool,
    /// Condition that needs to be true in order for the rule to be run.
    /// Can be either a material check or type check
    pub precondition: String,
    /// Whether the rule is used as a base_rule of a type of as extra_rule of a material
    pub used: bool,
}
impl SandRule {
    fn get_func_logic(mut if_conds: Vec<String>, mut do_actions: Vec<String>) -> String {
        if if_conds.is_empty() && do_actions.is_empty() {
            return String::new();
        } else if if_conds.is_empty() && !do_actions.is_empty() {
            return do_actions.remove(0);
        } else if !if_conds.is_empty() && !do_actions.is_empty() {
            return format!(
"if ({}) {{
    {}
}} else {{
    {}
}}", if_conds.remove(0), do_actions.remove(0), SandRule::get_func_logic(if_conds, do_actions));
        };
        String::new()
    }
}
impl GLSLConvertible for SandRule {
    fn get_glsl_code(&self) -> String {
        let directional_cell = match self.ruletype {
            SandRuleType::Mirrored | SandRuleType::Right => "right",
            SandRuleType::Left => "left"
        };
        format!(
"void rule_{} (inout Cell self, inout Cell {}, inout Cell down, inout Cell downright, ivec2 pos) {{
    // If the precondition isnt met, return
    if (!({})) {{
        return;
    }}

    {}
}}", self.name, directional_cell, self.precondition, SandRule::get_func_logic(self.if_conds.clone(), self.do_actions.clone()))

    }
}


#[derive(Debug, Clone, Default)]
pub struct SandType {
    /// Index/ ID of the type
    pub id: usize,
    /// Name of the type (Mapping key)
    pub name: String,
    /// Name of the parent type
    pub inherits: String,
    /// List of children types needed for the type check
    children: Vec<String>,
    /// List of names of the rules that are applied to all
    /// materials of this type
    pub base_rules: Vec<String>,
    /// All accumulated rules, including parent rules
    pub accum_rules: Vec<String>
}
impl GLSLConvertible for SandType {
    fn get_glsl_code(&self) -> String {
        let mut typecheck = format!("return cell.mat.type == TYPE_{}", self.name);
        self.children.iter().for_each(|c| {
            typecheck.push_str(format!(" || cell.mat.type == TYPE_{}", c).as_str());
        });
        format!("#define TYPE_{} {}

bool isType_{}(Cell cell) {{
    {};
}}\n\n", self.name, self.id, self.name, typecheck)
    }
}


#[derive(Debug, Clone, Default)]
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
    let raw_types = data.get("types").expect("[sandengine-lang]: No 'types' found in input file.");
    let raw_materials = data.get("materials").expect("[sandengine-lang]: No 'materials' found in input file.");

    let material_names = parse_material_names(raw_materials.as_mapping().expect("[sandengine-lang]: 'materials' is not a mapping (dictionary-like)"))?;
    
    let res = parse_rules(raw_rules.as_mapping().expect("[sandengine-lang]: 'rules' is not a mapping (dictionary-like)"), material_names);
    if let Ok(mut result) = res {
        rules.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing rules: '{}'", res.err().unwrap());
    }

    let res = parse_types(raw_types.as_mapping().expect("[sandengine-lang]: 'types' is not a mapping (dictionary-like)"), &mut rules);
    if let Ok(mut result) = res {
        types.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing types: '{}'", res.err().unwrap());
    }

    let res = parse_materials(raw_materials.as_mapping().expect("[sandengine-lang]: 'materials' is not a mapping (dictionary-like)"), &mut rules, &types);
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




fn parse_rules(rules: &Mapping, material_names: Vec<String>) -> anyhow::Result<(Vec<SandRule>, Vec<Box<dyn GLSLConvertible>>)> {
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
        
        let mut if_conds = vec![];
        let mut do_actions = vec![];
        parse_conditionals(key.1, false, format!("rules/{}", name), &mut if_conds, &mut do_actions, &material_names)?;
        
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
                if do_actions[0].contains("LEFT") {
                    SandRuleType::Left
                } else {
                    SandRuleType::Right
                }
            }
        };

        let rule = SandRule {
            name,
            ruletype,
            if_conds,
            do_actions,
            mirror: is_mirrored,
            precondition: String::new(),
            used: false,
        };
        //println!("{:#?}", rule);
        rule_structs.push(rule.clone());
        glsl_structs.push(Box::new(rule));
    }

    Ok((rule_structs, glsl_structs))
}


fn parse_conditionals(parent: &Value, parent_is_else: bool, parent_path: String, if_conds: &mut Vec<String>, do_actions: &mut Vec<String>, material_names: &Vec<String>) -> anyhow::Result<()> {
    let if_cond = parent.get("if");

    // We are on the top level of all conditions, so if is mandatory
    if if_cond.is_none() && !parent_is_else {
        bail!(anyhow!(ParsingErr::<bool>::MissingField {
            field_name: "if".to_string(),
            missing_in: format!("{}", parent_path)
        }));
    } else if if_cond.is_some() {
        let if_cond = if_cond.unwrap();

        let mut if_cond = if_cond.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "if".to_string(),
                missing_in: format!("{}", parent_path),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();

        parse_global_scope(&mut if_cond);

        let material_pattern = r"\w* [[:punct:]]* (\w*)";
        let re = Regex::new(material_pattern).unwrap();
        
        re.captures_iter(if_cond.clone().as_str()).for_each(|captures| {
            for m in material_names {
                if m == captures.get(1).unwrap().as_str() {
                    if_cond = if_cond.replace(m, format!("MAT_{}", m).as_str());
                };
            }
        });

        if_conds.push(if_cond);
    }
    
    // A 'do' is always mandatory, so bail if non existent
    let do_action = parent
        .get("do")
        .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
            field_name: "do".to_string(),
            missing_in: format!("{}", parent_path)
        }))?;
    

    // The final string that is the do action
    let mut do_string = String::new();
    if let Some(do_action) = do_action.as_str() {
        do_string = parse_do(&parent_path, &do_action)?;
        parse_global_scope(&mut do_string);
    };

    if let Some(do_list) = do_action.as_sequence() {
        for do_action in do_list {
            if let Some(do_action) = do_action.as_str() {
                let mut do_str = parse_do(&parent_path, do_action)?;
                parse_global_scope(&mut do_str);
                do_string.push_str(&do_str);
            }
        }
    };
    do_string = do_string.trim_end().to_string();

    do_actions.push(do_string);

    let else_: Option<&Value> = parent.get("else");
    if let Some(e) = else_ {
        parse_conditionals(e, true, format!("{}/else", parent_path), if_conds, do_actions, material_names)
    } else {
        Ok(())
    }
}


/// Replaces all global scope variables with GLSL-friendly ones
fn parse_global_scope(parse_str: &mut String) {
    *parse_str = parse_str.replace(" or ", " || ");
    *parse_str = parse_str.replace(" and ", " && ");
    
    *parse_str = parse_str.replace("empty", "MAT_EMPTY");

    *parse_str = parse_str.replace("SELF", "self");
    *parse_str = parse_str.replace("RIGHT", "right");
    *parse_str = parse_str.replace("LEFT", "left");
    *parse_str = parse_str.replace("DOWN", "down");
    *parse_str = parse_str.replace("DOWNRIGHT", "downright");
    *parse_str = parse_str.replace("DOWNLEFT", "downleft");
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
        do_string.push_str(format!("{} = newCell(MAT_{}, pos);\n", first_arg, second_arg).as_str());
    }

    if !found_match {
        bail!(ParsingErr::<bool>::NotRecognized {
            unrecog: do_str.to_string(),
            missing_in: format!("{}/do", parent)
        });
    }

    Ok(do_string)
}



fn parse_types(types: &Mapping, rules: &mut Vec<SandRule>) -> anyhow::Result<(Vec<SandType>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut type_structs: Vec<SandType> = vec![
        SandType {
            id: 0,
            name: String::from("empty"),
            ..Default::default()
        },
        SandType {
            id: 1,
            name: String::from("null"),
            ..Default::default()
        },
        SandType {
            id: 2,
            name: String::from("wall"),
            ..Default::default()
        },
    ];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![
        Box::new(type_structs[0].clone()),
        Box::new(type_structs[1].clone()),
        Box::new(type_structs[2].clone())
    ];
    
    // Index is 3 because of the 3 default types
    let mut idx = type_structs.len();
    for sandtype in types {
        let name = sandtype.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: sandtype.0.clone(),
                missing_in: "types".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        let mut accum_rules = vec![];
        let inherits = sandtype.1.get("inherits");
        let mut parent = String::new();
        if let Some(p) = inherits {
            let parent_str = p.as_str().ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "inherits",
                missing_in: format!("types/{}", name),
                expected: TYPE_HINT_STRING
            }))?;
            let mut all_types = type_structs.clone();
            for t in type_structs.iter_mut() {
                if t.name == parent_str {
                    parent = parent_str.to_string();
                    add_child_to_type(&t.name, &name, &mut all_types);
                    accum_rules = get_accum_rules(&all_types, t);
                }
            };
            type_structs = all_types;

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
                    for r in rules.iter_mut() {
                        if r.name == rulename {
                            r.used = true;
                            base_rules.push(rulename.to_string());
                            accum_rules.push(rulename.to_string());

                            if r.precondition.is_empty() {
                                r.precondition = format!("isType_{}(self)", name);
                            } else {
                                r.precondition = format!("{} || isType_{}(self)", r.precondition, name);
                            }
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
            children: vec![],
            base_rules,
            accum_rules
        };
        type_structs.push(s_type.clone());
        glsl_structs.push(Box::new(s_type));

        idx += 1;
    }
    
    Ok((type_structs, glsl_structs))
}


fn add_child_to_type(parent_name: &str, childname: &str, types: &mut Vec<SandType>) {
    let mut parents_parent_name = String::new();
    for t in types.iter_mut() {
        if t.name == parent_name {
            t.children.push(childname.to_string());
            parents_parent_name = t.inherits.clone();
            break;
        }
    };
    if !parents_parent_name.is_empty() {
        add_child_to_type(&parents_parent_name, childname, types);
    }
}


fn get_accum_rules(all_types: &Vec<SandType>, current_type: &SandType) -> Vec<String> {
    if !current_type.inherits.is_empty() {
        for t in all_types {
            if t.name == current_type.inherits {
                let mut parent_rules = get_accum_rules(all_types, t);
                let mut r = current_type.base_rules.clone();
                r.append(&mut parent_rules);
                return r;
            }
        }
        return vec![];
    } else {
        return current_type.base_rules.clone();
    }
}



fn parse_material_names(materials: &Mapping) -> anyhow::Result<Vec<String>> {
    let mut matnames = vec![];
    for mat in materials {
        let name = mat.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: mat.0.clone(),
                missing_in: "materials".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        matnames.push(name);
    };
    Ok(matnames)
}


fn parse_materials(materials: &Mapping, rules: &mut Vec<SandRule>, types: &Vec<SandType>) -> anyhow::Result<(Vec<SandMaterial>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut material_structs: Vec<SandMaterial> = vec![
        SandMaterial {
            id: 0,
            name: String::from("EMPTY"),
            mattype: String::from("empty"),
            color: [0.0, 0.0, 0.0, 0.0],
            emission: [0.0, 0.0, 0.0, 0.0],
            selectable: true,
            density: 1.0,
            ..Default::default()
        },
        SandMaterial {
            id: 1,
            name: String::from("NULL"),
            mattype: String::from("null"),
            color: [1.0, 0.0, 1.0, 1.0],
            emission: [0.0, 0.0, 0.0, 0.0],
            selectable: false,
            density: 0.0,
            ..Default::default()
        },
        SandMaterial {
            id: 2,
            name: String::from("WALL"),
            mattype: String::from("wall"),
            color: [0.0, 0.0, 0.0, 0.0],
            emission: [0.0, 0.0, 0.0, 0.0],
            selectable: false,
            density: 0.0,
            ..Default::default()
        },
    ];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![
        Box::new(material_structs[0].clone()),
        Box::new(material_structs[1].clone()),
        Box::new(material_structs[2].clone()),
    ];

    // Index is 3 because of the 3 default materials
    let mut idx = material_structs.len();
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
                        for r in rules.iter_mut() {
                            if r.name == extra_rule {
                                r.used = true;
                                if r.precondition.is_empty() {
                                    r.precondition = format!("self.mat == MAT_{}", name);
                                } else {
                                    r.precondition = format!("{} || self.mat == MAT_{}", r.precondition, name)
                                }
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