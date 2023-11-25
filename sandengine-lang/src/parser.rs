use std::fmt::Debug;

use anyhow::{anyhow, bail};
use thiserror::Error;
use serde_yaml::{self, Value, Mapping};

use colored::Colorize;

pub mod rules;
pub mod types;
pub mod materials;

use rules::SandRule;
use types::SandType;
use materials::SandMaterial;


// ========== Hints that will be displayed on an error message ==========
const TYPE_HINT_STRING: &'static str = "string";
const TYPE_HINT_BOOL: &'static str = "bool (true/false)";
const TYPE_HINT_FLOAT: &'static str = "float (0.0 to 1.0)";
const TYPE_HINT_SEQUENCE: &'static str = "sequence (array, '[...]')";
const TYPE_HINT_COLOR: &'static str = "sequence (array, '[...]') of 3-4 floats (range 0.0-1.0) OR integers (range 0-255). (With 3 elements, the alpha channel defaults to 1.0)";
const TYPE_HINT_MAPPING: &'static str = "mapping (dictionary-like)";

// ========== List of valid global scope Cell names ==========
const GLOBAL_CELLNAMES: [&'static str; 6] = [
    "SELF",
    "LEFT",
    "RIGHT",
    "DOWN",
    "DOWNRIGHT",
    "DOWNLEFT"
];

// ========== Default values for properties ==========
const DEFAULT_VAL_MIRRORED: bool = true;
const DEFAULT_VAL_PRECONDITION: bool = true;
const DEFAULT_VAL_PROBABILITY: f32 = 1.0;


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

    // Checks the input for 'rules', 'types' and 'materials', throws error if not
    // Afterwards, tries to convert them into dictionaries (mappings), errors if not possible
    let raw_rules = check_and_convert_key_to_mapping(&data, "rules")?;
    let raw_types = check_and_convert_key_to_mapping(&data, "types")?;
    let raw_materials = check_and_convert_key_to_mapping(&data, "materials")?;
    
    // Pre-parse the rule-/ material-/ type names in order for them to be referenced earlier than defined
    let rule_names = preparse_keys(&raw_rules,"rules")?;
    let mut type_names = preparse_keys(&raw_types,"types")?;
    type_names.push(String::from("EMPTY"));
    let mut material_names = preparse_keys(&raw_materials,"materials")?;
    material_names.push(String::from("EMPTY"));

    // Try to parse the rules
    let res = rules::parse_rules(&raw_rules, &type_names, &material_names);
    if let Ok(mut result) = res {
        rules.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing rules: '{}'", res.err().unwrap());
    }

    // Try to parse the types
    let res = types::parse_types(&raw_types, &mut rules, &rule_names, &type_names);
    if let Ok(mut result) = res {
        types.append(&mut result.0);
        data_serialized.append(&mut result.1);
    } else {
        bail!("Error while parsing types: '{}'", res.err().unwrap());
    }

    // Try to parse the materials
    let res = materials::parse_materials(&raw_materials, &mut rules, &type_names);
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


/// Looks at all the keys in some section of the YAML and collects them
fn preparse_keys(map: &Mapping, err_name: &str) -> anyhow::Result<Vec<String>> {
    let mut keynames = vec![];
    for key in map {
        let name = key.0.as_str()
            .ok_or(anyhow!(ParsingErr::InvalidType {
                wrong_type: key.0.clone(),
                missing_in: err_name.to_string(),
                expected: TYPE_HINT_STRING
            }))?
            .to_string();
        keynames.push(name);
    };
    Ok(keynames)
}


/// Checks if the keyname exists in the dictionary and tries to convert it to a Mapping
/// Throws ParsingErr::MissingField if nonexistent or ParsingErr::InvalidType if not a Mapping
fn check_and_convert_key_to_mapping<'a>(dict: &'a Value, keyname: &str) -> anyhow::Result<&'a Mapping> {
    let key = dict.get(keyname)
        .ok_or(anyhow!(ParsingErr::MissingField::<bool> {
            field_name: keyname.to_string(),
            missing_in: "Root/ Base level of YAML file".to_string()
        }))?;
    let map = key.as_mapping()
        .ok_or(anyhow!(ParsingErr::InvalidType {
            wrong_type: key.clone(),
            missing_in: "Root/ Base level of YAML file".to_string(),
            expected: TYPE_HINT_MAPPING
        }))?;
    Ok(map)
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