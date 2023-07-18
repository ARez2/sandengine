# Sandengine - a falling sand simulation written in GLSL and Rust

## Todo

### Usability

#### Improve how Materials are defined

- Remove need to define properties which arent important to that material (Add default values)
    - Maybe proc gen the actual GLSL definitions and define the materials in a file? This way, properties not definied in the file, will just be assigned default values
    - `serde_yaml` crate
    - An Editor could simply work with that config file

#### Improve definition of logic

- Provide standardized logics for movable solids, liquids, gases which can be optionally added to a material (like `use movSolid, Liquid`)
- Provide a way to easily define custom logic (maybe through a visual editor, see [this video by TodePond](https://www.youtube.com/watch?v=sQYUQNozljo))

### Add physics

- Simple Ray intersections

### Add sounds

- ???
