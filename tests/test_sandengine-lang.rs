use sandengine_lang::parser::parse_string;

#[test]
#[should_panic = "No 'rules' found in input file"]
fn missing_rules() {
    let _ = parse_string(String::from("
    types:
        movable_solid:
            base_rules: [
                gravity,
                slide_diagonally
            ]


    materials:
        sand:
            color: [1.0, 1.0, 0.0, 1.0]
            type: movable_solid
            density: 1.5
            selectable: true
    "));
}


#[test]
#[should_panic = "No 'types' found in input file"]
fn missing_types() {
    let _ = parse_string(String::from("
    rules:
        gravity:
            if: DOWN.density < SELF.density
            do: SWAP SELF DOWN
            mirrored: false
        slide_diagonally:
            if: DOWNRIGHT.density < SELF.density
            do: swap(SELF, DOWNRIGHT)
            mirrored: true

    materials:
        sand:
            color: [1.0, 1.0, 0.0, 1.0]
            type: movable_solid
            density: 1.5
            selectable: true
    "));
}


#[test]
#[should_panic = "No 'materials' found in input file"]
fn missing_materials() {
    let _ = parse_string(String::from("
    rules:
        gravity:
            if: DOWN.density < SELF.density
            do: SWAP SELF DOWN
            mirrored: false
        slide_diagonally:
            if: DOWNRIGHT.density < SELF.density
            do: swap(SELF, DOWNRIGHT)
            mirrored: true
    

    types:
        movable_solid:
            base_rules: [
                gravity,
                slide_diagonally
            ]
    "));
}


#[test]
fn invalid_name() {
    let res = parse_string(String::from("
    rules:
        1.0:
            if: DOWN.density < SELF.density
            do: SWAP SELF DOWN
            mirrored: false
        slide_diagonally:
            if: DOWNRIGHT.density < SELF.density
            do: swap(SELF, DOWNRIGHT)
            mirrored: true
    "));
    assert!(res.err().unwrap().to_string().contains(&"InvalidType"));
}

#[test]
fn missing_field() {
    let res = parse_string(String::from("
    rules:
        gravity:
            #if: DOWN.density < SELF.density
            do: SWAP SELF DOWN
            mirrored: false
        slide_diagonally:
            if: DOWNRIGHT.density < SELF.density
            do: swap(SELF, DOWNRIGHT)
            mirrored: true
    "));
    assert!(res.err().unwrap().to_string().contains(&"MissingField"));

    let res = parse_string(String::from("
    rules:
        gravity:
            if: DOWN.density < SELF.density
            do: SWAP SELF DOWN
            mirrored: false
        slide_diagonally:
            if: DOWNRIGHT.density < SELF.density
            do: swap(SELF, DOWNRIGHT)
            mirrored: true


    types:
        movable_solid:
            base_rules: [
                gravity,
                slide_diagonally
            ]

    
    materials:
        sand:
            #color: [1.0, 1.0, 0.0, 1.0]
            type: movable_solid
            density: 1.5
            selectable: true
    "));
    assert!(res.err().unwrap().to_string().contains(&"MissingField"));
}


#[test]
fn not_found() {
    let res = parse_string(String::from("
    rules:
        gravity:
            if: DOWN.density < SELF.density
            do: SWAP SELF DOWN
            mirrored: false
        slide_diagonally:
            if: DOWNRIGHT.density < SELF.density
            do: swap(SELF, DOWNRIGHT)
            mirrored: true


    types:
        movable_solid:
            base_rules: [
                gravity,
                slide_diagonally
            ]

    
    materials:
        sand:
            color: [1.0, 1.0, 0.0, 1.0]
            type: liquid
            density: 1.5
            selectable: true
    "));
    assert!(res.err().unwrap().to_string().contains(&"NotFound"));
}