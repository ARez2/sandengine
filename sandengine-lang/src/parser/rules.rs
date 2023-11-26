use anyhow::{anyhow, bail};
use regex::Regex;
use serde_yaml::{Mapping, Value};

use crate::{GLSLConvertible, parser::{DEFAULT_VAL_PROBABILITY, TYPE_HINT_STRING, ParsingErr, TYPE_HINT_BOOL, TYPE_HINT_FLOAT}};

use super::{DEFAULT_VAL_MIRRORED, DEFAULT_VAL_PRECONDITION, GLOBAL_CELLNAMES};





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
    /// The probability that this rule will be run
    pub probability: f32,
    /// Whether the rule is used as a base_rule of a type of as extra_rule of a material
    pub used: bool,
}
impl SandRule {
    /// Helpers function to handle nested conditionals and actions
    fn get_func_logic(mut if_conds: Vec<String>, mut do_actions: Vec<String>, indent_lvl: usize) -> String {
        if if_conds.is_empty() && do_actions.is_empty() {
            return String::new();
        } else if if_conds.is_empty() && !do_actions.is_empty() {
            return do_actions.remove(0);
        } else if !if_conds.is_empty() && !do_actions.is_empty() {
            let ind1 = " ".repeat(indent_lvl * 4);
            let ind2 = " ".repeat((indent_lvl + 1) * 4);
            return format!(
"{ind1}if ({}) {{
{ind2}{}
{ind1}}} else {{
{}
{ind1}}}", if_conds.remove(0),
            do_actions.remove(0),
            SandRule::get_func_logic(if_conds, do_actions, indent_lvl + 1));
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

        let probability = {
            if self.probability != DEFAULT_VAL_PROBABILITY {
                format!(
"    if (rand.y > {}) {{
        return;
    }}\n", self.probability)
            } else {
                String::new()
            }
        };

        let precond = match &self.precondition {
            Some(cond) => format!(
"    if (!({})) {{
        return;
    }}\n", cond),
            None => String::new(),
        };
        format!(
"void rule_{rulename} (inout Cell self, inout Cell {celldir}, inout Cell down, inout Cell downright, vec4 rand, ivec2 pos) {{
{probability_check}{precondition}{ruletext}
}}", rulename = self.name,
    celldir = directional_cell,
    probability_check = probability,
    precondition = precond,
    ruletext = SandRule::get_func_logic(self.if_conds.clone(), self.do_actions.clone(), 1))
    
    }
}





/// Parses a serde_yaml Mapping (dict) and converts it into SandRule's
pub fn parse_rules(rules: &Mapping, type_names: &Vec<String>, material_names: &Vec<String>) -> anyhow::Result<(Vec<SandRule>, Vec<Box<dyn GLSLConvertible>>)> {
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
        parse_conditionals(key.1, false, format!("rules/{}", name), &mut if_conds, &mut do_actions, &type_names, &material_names)?;
        

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
                // TODO: Make option for precondition to also be a string
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

        // Check if the "probability" key exists, use the default value if not
        let prob = key.1.get("probability");
        let probability = {
            if let Some(prob) = prob {
                if let Some(prob) = prob.as_f64() {
                    prob as f32
                } else {
                    bail!(ParsingErr::InvalidType {
                        wrong_type: "probability",
                        missing_in: format!("rules/{}", name),
                        expected: TYPE_HINT_FLOAT })
                }
            } else {
                DEFAULT_VAL_PROBABILITY
            }
        };

        let rule = SandRule {
            name,
            ruletype,
            if_conds,
            do_actions,
            mirror: is_mirrored,
            precondition,
            probability,
            used: false,
        };
        //println!("{:#?}", rule);
        rule_structs.push(rule.clone());
        glsl_structs.push(Box::new(rule));
    }

    Ok((rule_structs, glsl_structs))
}


/// Function to recursively parse the if-do-else's
fn parse_conditionals(
    parent: &Value,
    parent_is_else: bool,
    parent_path: String,
    if_conds: &mut Vec<String>,
    do_actions: &mut Vec<String>,
    type_names: &Vec<String>,
    material_names: &Vec<String>
) -> anyhow::Result<()> {
    let if_cond = parent.get("if");

    // We are on the top level of all conditions, so an 'if' is mandatory
    if if_cond.is_none() && !parent_is_else {
        bail!(anyhow!(ParsingErr::<bool>::MissingField {
            field_name: "if".to_string(),
            missing_in: format!("{}", parent_path)
        }));
    } else if if_cond.is_some() {
        let if_cond = if_cond.unwrap();
        let parent_path = format!("{}/if", parent_path);

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
        
        let material_pattern = r"\w*.mat\s*(==|!=)\s*(\w*)";
        let re = Regex::new(material_pattern).unwrap();
        'outer: for capture in re.captures_iter(if_cond.clone().as_str()) {
            let capture = capture.get(2).unwrap().as_str();
            for m in material_names {
                if m == capture {
                    if_cond = if_cond.replace(m, format!("MAT_{}", m).as_str());
                    continue 'outer;
                };
            };
            bail!(anyhow!(ParsingErr::NotFound::<bool> {
                missing: capture.to_string(),
                missing_in: format!("{}", parent_path)
            }));
        };

        let type_pattern = r"isType_(\w*)\(\w*\)";
        let re = Regex::new(type_pattern).unwrap();
        for capture in re.captures_iter(if_cond.clone().as_str()) {
            let capture = capture.get(1).unwrap().as_str();
            if !type_names.contains(&capture.to_string()) {
                bail!(anyhow!(ParsingErr::NotFound::<bool> {
                    missing: capture.to_string(),
                    missing_in: format!("{} -> isType_", parent_path)
                }));
            }
        };

        if_conds.push(if_cond);
    }
    
    // A 'do' is always mandatory, so bail if non existent
    let do_action = parent
        .get("do")
        .ok_or(anyhow!(ParsingErr::<bool>::MissingField {
            field_name: "do".to_string(),
            missing_in: format!("{}", parent_path)
        }))?;
    
    let parent_path = format!("{}/do", parent_path);

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
        parse_conditionals(e, true, format!("{}/else", parent_path), if_conds, do_actions, type_names, material_names)
    } else {
        Ok(())
    }
}


/// Replaces all global scope variables with GLSL-friendly ones
fn parse_global_scope(parse_str: &mut String) {
    *parse_str = parse_str.replace(" or ", " || ");
    *parse_str = parse_str.replace(" and ", " && ");
    *parse_str = parse_str.replace("not ", " !");
    
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
        if !GLOBAL_CELLNAMES.contains(&first_cell) {
            bail!(ParsingErr::<bool>::NotFound {
                missing: first_cell.to_string(),
                missing_in: format!("{}", parent)
            });
        };
        let second_cell = captures.get(2).unwrap().as_str();
        if !GLOBAL_CELLNAMES.contains(&second_cell) {
            bail!(ParsingErr::<bool>::NotFound {
                missing: second_cell.to_string(),
                missing_in: format!("{}", parent)
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
        if !GLOBAL_CELLNAMES.contains(&first_arg) {
            bail!(ParsingErr::<bool>::NotFound {
                missing: first_arg.to_string(),
                missing_in: format!("{}", parent)
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
            missing_in: format!("{}", parent)
        });
    }

    Ok(do_string)
}