use std::{fmt::Debug, path::PathBuf, default::{self, Default}};

use anyhow::{anyhow, bail};
use thiserror::Error;
use serde_yaml::{self, Mapping, Value};
use regex::Regex;

use colored::Colorize;


// ========== Hints that will be displayed on an error message ==========
const TYPE_HINT_STRING: &'static str = "string";
const TYPE_HINT_BOOL: &'static str = "bool (true/false)";
const TYPE_HINT_FLOAT: &'static str = "float";
const TYPE_HINT_SEQUENCE: &'static str = "sequence (array, '[...]')";
const TYPE_HINT_COLOR: &'static str = "sequence (array, '[...]') of 3-4 floats (range 0.0-1.0) OR integers (range 0-255). (With 3 elements, the alpha channel defaults to 1.0)";

// ========== List of valid global scope Cell names ==========
const GLOBAL_CELLS: [&'static str; 6] = [
    "SELF",
    "LEFT",
    "RIGHT",
    "DOWN",
    "DOWNRIGHT",
    "DOWNLEFT"
];

// ========== Default values for properties ==========
const DEFAULT_VAL_MIRRORED: bool = false;
const DEFAULT_VAL_PRECONDITION: bool = true;


#[derive(Debug, Error)]
/// Custom Error type using the thiserror crate. Will be displayed in the console
enum ParsingErr<T: Debug> {
    /// Emitted, when a mandatory property in the YAML file was not found
    #[error("{} Mandatory field '{}' is {} '{}'", "(MissingField)".red(), .field_name.bold(), "missing in".bold(), .missing_in.bold())]
    MissingField {
        field_name: String,
        missing_in: String,
    },

    /// Emitted, when a property in the YAML has an invalid data type
    #[error("{} The type of the field '{:?}' inside of '{}' {}. Expected: '{}'", "(InvalidType)".red(),.wrong_type, .missing_in.bold(), "is invalid".bold(), .expected.bold())]
    InvalidType {
        wrong_type: T,
        missing_in: String,
        expected: &'static str,
    },

    /// Emitted, when something was not defined before it was referenced
    #[error("{} The name '{}' (in '{}') {}. Make sure it was defined before referencing it.", "(NotFound)".red(),.missing.bold(), .missing_in.bold(), "was not found".bold())]
    NotFound {
        missing: String,
        missing_in: String,
    },

    /// Emitted, when some operator, function etc. is not valid in global scope
    #[error("{} The expression '{}' (in '{}') {}.", "(NotRecognized)".red(),.unrecog.bold(), .missing_in.bold(), "was not recognized as valid syntax. Please check it is valid".bold())]
    NotRecognized {
        unrecog: String,
        missing_in: String
    }
}


/// Each struct returned from the parser implements this to simplify the conversion to GLSL
pub trait GLSLConvertible {
    fn get_glsl_code(&self) -> String;
}


/// Mirrored type of the rule
#[derive(Debug, Clone, PartialEq)]
pub enum SandRuleType {
    Mirrored,
    Left,
    Right
}

/// Holds information about a rule defined in the YAML file
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
    pub precondition: Option<String>,
    /// Whether the rule is used as a base_rule of a type of as extra_rule of a material
    pub used: bool,
}
impl SandRule {
    /// Helpers function to handle nested conditionals and actions
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
        let precond = match &self.precondition {
            Some(cond) => format!(
"if (!({})) {{
    return;
}}", cond),
            None => String::new(),
        };
        format!(
"void rule_{} (inout Cell self, inout Cell {}, inout Cell down, inout Cell downright, ivec2 pos) {{
    {}

    {}
}}", self.name, directional_cell, precond, SandRule::get_func_logic(self.if_conds.clone(), self.do_actions.clone()))

    }
}


/// Holds information about material types defined inside the YAML
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
impl SandType {
    /// Helper function to generate the function, which checks if a cell is of this type
    /// accounts for inheritance
    pub fn get_checker_func(&self) -> String {
        let mut typecheck = format!("return cell.mat.type == TYPE_{}", self.name);
        self.children.iter().for_each(|c| {
            typecheck.push_str(format!(" || cell.mat.type == TYPE_{}", c).as_str());
        });
        format!(
"bool isType_{}(Cell cell) {{
    {};
}}\n\n", self.name, typecheck)
    }
}
impl GLSLConvertible for SandType {
    fn get_glsl_code(&self) -> String {
        format!("#define TYPE_{} {}\n\n", self.name, self.id)
    }
}


#[derive(Debug, Clone, Default)]
pub struct SandMaterial {
    /// Index/ ID of the material
    pub id: usize,
    /// Name of the material
    pub name: String,
    /// Type of the material
    pub mattype: String,
    /// Color of the material
    pub color: [f32; 4],
    /// Emission value of the material
    pub emission: [f32; 4],
    /// Whether this material is selectable from the UI or NUM keys
    pub selectable: bool,
    /// Density of the material
    pub density: f32,
    /// Extra rules of the material, which are unique to this
    /// material and cannot be defined in the base_rules of the type
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

/// Helper struct that holds all generated structs
pub struct ParsingResult {
    pub rules: Vec<SandRule>,
    pub types: Vec<SandType>,
    pub materials: Vec<SandMaterial>,
    pub data_serialized: Vec<Box<dyn GLSLConvertible>>,
}


/// Parses a string (YAML syntax) and converts it into Rust structs holding the data
pub fn parse_string(f: &str) -> anyhow::Result<ParsingResult> {
    // Convert the string into a serde_yaml object
    let data: Result<_, serde_yaml::Error> = serde_yaml::from_str(f);
    if let Err(err) = data {
        bail!(err);
    }
    let data: serde_yaml::Value = data.unwrap();

    // Create the required lists of structs
    let mut data_serialized: Vec<Box<dyn GLSLConvertible>> = vec![];
    let mut rules: Vec<SandRule> = vec![];
    let mut types: Vec<SandType> = vec![];
    let mut materials: Vec<SandMaterial> = vec![];

    // Checks the input for 'rules', 'types' and 'materials', panicks if not found
    let raw_rules = data.get("rules").expect("[sandengine-lang]: No 'rules' found in input file.");
    let raw_types = data.get("types").expect("[sandengine-lang]: No 'types' found in input file.");
    let raw_materials = data.get("materials").expect("[sandengine-lang]: No 'materials' found in input file.");

    // Pre-parses just the material names in order for the rules to be able to recognize them
    let material_names = parse_material_names(raw_materials.as_mapping().expect("[sandengine-lang]: 'materials' is not a mapping (dictionary-like)"))?;
    
    // Try to parse the rules
    let res = parse_rules(raw_rules.as_mapping().expect("[sandengine-lang]: 'rules' is not a mapping (dictionary-like)"), material_names);
    if let Ok(mut result) = res {
        rules.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing rules: '{}'", res.err().unwrap());
    }

    // Try to parse the types
    let res = parse_types(raw_types.as_mapping().expect("[sandengine-lang]: 'types' is not a mapping (dictionary-like)"), &mut rules);
    if let Ok(mut result) = res {
        types.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing types: '{}'", res.err().unwrap());
    }

    // Try to parse the materials
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



/// Parses a serde_yaml Mapping (dict) and converts it into SandRule's
fn parse_rules(rules: &Mapping, material_names: Vec<String>) -> anyhow::Result<(Vec<SandRule>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut rule_structs: Vec<SandRule> = vec![];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![];

    for key in rules {
        // Extract the name of the rule
        let name = key.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType{
                wrong_type: key.0.clone(),
                missing_in: "rules".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        
        let mut if_conds = vec![];
        let mut do_actions = vec![];
        // Parse (possibly nested) if's and do's
        parse_conditionals(key.1, false, format!("rules/{}", name), &mut if_conds, &mut do_actions, &material_names)?;
        
        // Checks the input for the 'mirrored' keyword, uses default value if not found
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

        // Generates the type of the rule based on whether the if's and do's contain certain keywords
        // TODO: Rule cant contain both LEFT and RIGHT, throw error if so
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

        // Checks for the 'precondition' key, if not found use default value
        let do_precondition = {
            let pre = key.1.get("precondition");
            if let Some(pre) = pre {
                if let Some(pre) = pre.as_bool() {
                    pre
                } else {
                    bail!(ParsingErr::InvalidType {
                        wrong_type: "precondition",
                        missing_in: format!("rules/{}", name),
                        expected: TYPE_HINT_BOOL })
                }
            } else {
                DEFAULT_VAL_PRECONDITION
            }
        };
        let precondition = match do_precondition {
            true => Some(String::new()),
            false => None
        };

        // TODO: Use chance key, add way to get random values

        let rule = SandRule {
            name,
            ruletype,
            if_conds,
            do_actions,
            mirror: is_mirrored,
            precondition,
            used: false,
        };
        //println!("{:#?}", rule);
        rule_structs.push(rule.clone());
        glsl_structs.push(Box::new(rule));
    }

    Ok((rule_structs, glsl_structs))
}


/// Function to recursively parse the if-do-else's
fn parse_conditionals(parent: &Value, parent_is_else: bool, parent_path: String, if_conds: &mut Vec<String>, do_actions: &mut Vec<String>, material_names: &Vec<String>) -> anyhow::Result<()> {
    let if_cond = parent.get("if");

    // We are on the top level of all conditions, so an 'if' is mandatory
    if if_cond.is_none() && !parent_is_else {
        bail!(anyhow!(ParsingErr::<bool>::MissingField {
            field_name: "if".to_string(),
            missing_in: format!("{}", parent_path)
        }));
    } else if if_cond.is_some() {
        let if_cond = if_cond.unwrap();

        // Check that the if condition has the right type
        let mut if_cond = if_cond.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "if".to_string(),
                missing_in: format!("{}", parent_path),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();

        // Passes the if condition through the global scope parser
        parse_global_scope(&mut if_cond);
        
        // Use regex to find when a material is being accessed
        //         Would trigger here
        //               VVV
        // "SELF.mat == vine"
        
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
    

    // Do processing on the 'do' to convert it into something more GLSL-like
    // The final string that is the do action
    let mut do_string = String::new();
    if let Some(do_action) = do_action.as_str() {
        do_string = parse_do(&parent_path, &do_action)?;
        parse_global_scope(&mut do_string);
    };

    // Also process do's which are written as list of actions
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
    *parse_str = parse_str.replace("not ", " !");
    
    // IDEA: Use EMPTY in YAML Syntax
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

    // Use regex to find when a swap operation is requested as action
    // Would trigger here
    //       VVV
    // "SWAP SELF DOWN"
    let swap_pattern = r"SWAP (\w+) (\w+)";
    let re = Regex::new(swap_pattern).unwrap();
    
    // Check that the arguments to this function are correct
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

    // Use regex to find when a set (newCell) operation is requested as action
    // Would trigger here
    //           VVV
    // "SET SELF vine"
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



/// Parses a serde_yaml Mapping (dict) and converts it into SandType's
fn parse_types(types: &Mapping, rules: &mut Vec<SandRule>) -> anyhow::Result<(Vec<SandType>, Vec<Box<dyn GLSLConvertible>>)> {
    // Define the default types
    let mut type_structs: Vec<SandType> = vec![
        SandType {
            id: 0,
            name: String::from("EMPTY"),
            ..Default::default()
        },
        SandType {
            id: 1,
            name: String::from("NULL"),
            ..Default::default()
        },
        SandType {
            id: 2,
            name: String::from("WALL"),
            ..Default::default()
        },
    ];
    let mut glsl_structs: Vec<Box<dyn GLSLConvertible>> = vec![
        Box::new(type_structs[0].clone()),
        Box::new(type_structs[1].clone()),
        Box::new(type_structs[2].clone())
    ];
    
    let mut idx = type_structs.len();
    for sandtype in types {
        // Extract the name of the type
        let name = sandtype.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: sandtype.0.clone(),
                missing_in: "types".to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();

        // Processes the inheritance of types (and therefore inheritance of base_rules)
        let mut accum_rules = vec![];
        let inherits = sandtype.1.get("inherits");
        let mut parent = String::new();
        if let Some(p) = inherits {
            // If the 'inherits' keyword is present but has a wrong type, error
            let parent_str = p.as_str().ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "inherits",
                missing_in: format!("types/{}", name),
                expected: TYPE_HINT_STRING
            }))?;
            // Check previously defined types if they match the 'inherits' string
            let mut all_types = type_structs.clone();
            for t in type_structs.iter_mut() {
                if t.name == parent_str {
                    parent = parent_str.to_string();
                    // Modifies the parent SandType to add ourselves to its children
                    // the parent needs information of its children for its checker function
                    add_child_to_type(&t.name, &name, &mut all_types);
                    // Collects all the parents (and parents-parents, ...) rules
                    accum_rules = get_accum_rules(&all_types, t);
                }
            };
            type_structs = all_types;

            // If the parent name defined in 'inherits' was not found, error
            if parent.is_empty() {
                bail!(ParsingErr::<bool>::NotFound {
                    missing: parent_str.to_string(),
                    missing_in: format!("types/{}", name),
                });
            }
        };
        // Check if all rules defined in base_rules exist
        let mut base_rules = vec![];
        let b_rules = sandtype.1.get("base_rules");
        if let Some(b_rules) = b_rules {
            if let Some(b_rules) = b_rules.as_sequence() {
                for baserule in b_rules {
                    // If the thing defined as rulename isnt even a string, error
                    let rulename = baserule.as_str().ok_or(
                        anyhow!(ParsingErr::InvalidType {
                            wrong_type: "base_rules",
                            missing_in: format!("types/{}", name),
                            expected: TYPE_HINT_STRING
                        }))?;
                    // Checks all defined rules for the name of the base_rule
                    let mut rule_valid = false;
                    for r in rules.iter_mut() {
                        if r.name == rulename {
                            // Rule was used by this type, tell it that it has been used
                            r.used = true;
                            base_rules.push(rulename.to_string());
                            accum_rules.push(rulename.to_string());
                            
                            // Update the rules precondition to let this type use the rule
                            // = pass the precondition check
                            if let Some(precondition) = &mut r.precondition {
                                if precondition.is_empty() {
                                    r.precondition = Some(format!("isType_{}(self)", name));
                                } else {
                                    r.precondition = Some(format!("{} || isType_{}(self)", precondition, name));
                                }
                            }
                            rule_valid = true;
                            break;
                        }
                    };
                    // Referenced rule name was not defined in 'rules', error
                    if !rule_valid {
                        bail!(ParsingErr::<bool>::NotFound {
                            missing: rulename.to_string(),
                            missing_in: format!("types/{}/base_rules", name),
                        });
                    }
                }
            } else {
                // base_rules is not a sequence, error
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


/// Recursively adds a type (child) to its parents and parents parents
fn add_child_to_type(parent_name: &str, childname: &str, types: &mut Vec<SandType>) {
    let mut parents_parent_name = String::new();
    for t in types.iter_mut() {
        if t.name == parent_name {
            // We found our parent, updates our parents children
            t.children.push(childname.to_string());
            parents_parent_name = t.inherits.clone();
            break;
        }
    };
    // This childs parent also has a parent, add this type to its grandparents children
    if !parents_parent_name.is_empty() {
        add_child_to_type(&parents_parent_name, childname, types);
    }
}


/// Recursively collects all the parents and grandparents base_rules
fn get_accum_rules(all_types: &Vec<SandType>, current_type: &SandType) -> Vec<String> {
    if !current_type.inherits.is_empty() {
        for t in all_types {
            if t.name == current_type.inherits {
                // We found our parent, add its rules to the list
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


/// Looks at all the keys in the 'materials' and collects them
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


/// Parses a serde_yaml Mapping (dict) and converts it into SandMaterial's
fn parse_materials(materials: &Mapping, rules: &mut Vec<SandRule>, types: &Vec<SandType>) -> anyhow::Result<(Vec<SandMaterial>, Vec<Box<dyn GLSLConvertible>>)> {
    let mut material_structs: Vec<SandMaterial> = vec![
        SandMaterial {
            id: 0,
            name: String::from("EMPTY"),
            mattype: String::from("EMPTY"),
            color: [0.0, 0.0, 0.0, 0.0],
            emission: [0.0, 0.0, 0.0, 0.0],
            selectable: true,
            density: 1.0,
            ..Default::default()
        },
        SandMaterial {
            id: 1,
            name: String::from("NULL"),
            mattype: String::from("NULL"),
            color: [1.0, 0.0, 1.0, 1.0],
            emission: [0.0, 0.0, 0.0, 0.0],
            selectable: false,
            density: 0.0,
            ..Default::default()
        },
        SandMaterial {
            id: 2,
            name: String::from("WALL"),
            mattype: String::from("WALL"),
            color: [0.1, 0.2, 0.3, 1.0],
            emission: [0.0, 0.0, 0.0, 0.0],
            selectable: false,
            density: 9999.0,
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
                                if let Some(precondition) = &mut r.precondition {
                                    if precondition.is_empty() {
                                        r.precondition = Some(format!("self.mat == MAT_{}", name));
                                    } else {
                                        r.precondition = Some(format!("{} || self.mat == MAT_{}", precondition, name));
                                    }
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


/// Helper function to convert a mapping into a [f32; 4] (the rust type representing a color)
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
                }
                if comp >= 0.0 && comp <= 1.0 {
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