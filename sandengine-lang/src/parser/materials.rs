use anyhow::{anyhow, bail};
use serde_yaml::Mapping;

use crate::{GLSLConvertible, parser::{TYPE_HINT_STRING, ParsingErr, TYPE_HINT_SEQUENCE}};

use super::{rules::SandRule, types::SandType, extract_vec4, TYPE_HINT_FLOAT};



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


/// Looks at all the keys in the 'materials' and collects them
pub fn parse_material_names(materials: &Mapping) -> anyhow::Result<Vec<String>> {
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
pub fn parse_materials(materials: &Mapping, rules: &mut Vec<SandRule>, types: &Vec<SandType>) -> anyhow::Result<(Vec<SandMaterial>, Vec<Box<dyn GLSLConvertible>>)> {
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