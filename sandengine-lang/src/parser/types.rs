use anyhow::{anyhow, bail};
use serde_yaml::Mapping;

use crate::{GLSLConvertible, parser::{TYPE_HINT_STRING, ParsingErr, TYPE_HINT_SEQUENCE}};

use super::rules::SandRule;



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




/// Parses a serde_yaml Mapping (dict) and converts it into SandType's
pub fn parse_types(types: &Mapping, rules: &mut Vec<SandRule>) -> anyhow::Result<(Vec<SandType>, Vec<Box<dyn GLSLConvertible>>)> {
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