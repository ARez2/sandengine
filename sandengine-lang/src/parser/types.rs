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
    /// 
    /// **NOTE: This is unused right now but might be used in UI**
    pub base_rules: Vec<String>,
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
pub fn parse_types(types: &Mapping, rules: &mut Vec<SandRule>, rule_names: &Vec<String>, type_names: &Vec<String>) -> anyhow::Result<(Vec<SandType>, Vec<Box<dyn GLSLConvertible>>)> {
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
    
    
    // This will be used in both loops
    let update_rule_precondition = |rule: &mut SandRule, typename: &str| {
        // Update the rules precondition to let this type use the rule
        // = pass the precondition check
        if let Some(precondition) = &mut rule.precondition {
            if precondition.is_empty() {
                rule.precondition = Some(format!("isType_{}(self)", typename));
            } else {
                rule.precondition = Some(format!("{} || isType_{}(self)", precondition, typename));
            }
        };
    };
    
    // Iterate over all types, check if the inherited class and the base_rules have been defined somewhere
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
        let inherits = sandtype.1.get("inherits");
        let mut parent = String::new();
        if let Some(p) = inherits {
            // If the 'inherits' keyword is present but has a wrong type, error
            parent = p.as_str().ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: "inherits",
                missing_in: format!("types/{}", name),
                expected: TYPE_HINT_STRING
            }))?.to_string();
            for typename in type_names {
                if typename == &parent {
                    // Modifies the parent SandType to add ourselves to its children
                    // the parent needs information of its children for its checker function
                    add_child_to_type(&parent, &name, &mut type_structs);
                }
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
                    if !rule_names.contains(&rulename.to_string()) {
                        bail!(anyhow!(ParsingErr::NotFound::<bool> {
                            missing: rulename.to_string(),
                            missing_in: format!("types/{}/base_rules", name)
                        }));
                    };

                    let rule = rules.iter_mut().find(|r| {&r.name == rulename}).unwrap();
                    rule.used = true;
                    update_rule_precondition(rule, &name);
                    base_rules.push(rulename.to_string());
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
            base_rules
        };
        type_structs.push(s_type.clone());
        glsl_structs.push(Box::new(s_type));

        idx += 1;
    };

    for sandtype in type_structs.clone() {
        if sandtype.inherits.is_empty() {
            continue;
        };
        for rule in get_parents_rules(&type_structs, &sandtype) {
            let rule = rules.iter_mut().find(|r| {r.name == rule}).unwrap();
            update_rule_precondition(rule, &sandtype.name);
        }
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

fn get_parents_rules(all_types: &Vec<SandType>, current_type: &SandType) -> Vec<String> {
    if current_type.inherits.is_empty() {
        return vec![];
    };
    let parent = all_types.iter().find(|parent| {parent.name == current_type.inherits}).unwrap();
    let mut rules = parent.base_rules.clone();
    rules.append(&mut get_parents_rules(all_types, parent));
    rules
}