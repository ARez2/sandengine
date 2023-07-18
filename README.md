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

## YAML File for materials

### Global scope

- `SELF` - The current cell
- `DOWN` - The cell below
- `RIGHT` - The cell to the right
- `DOWNRIGHT` - The cell down and to the right


#### Keywords

- `is` - Checks if something is an instance of a type or material (`typeof`)
- `<`, `>`, `==`, `!=`, `&&`, `||` - Logical Operators


#### Functions

- `swap(Cell first, Cell second)`


### Defining rules

Rules will be processed in the order that they are defined.

```yaml
rules:
    rulename:
        if: <condition>
        do: <action>
        mirrored: true
```

#### Examples

```yaml
rules:
    gravity:
        if: SELF.mat.density > DOWN.mat.density
        do: swap(SELF, DOWN)
```

```yaml
rules:
    grow:
        if: SELF is air && down is soil # Will be translated to `if self.mat == AIR && down.mat == SOIL`
        do: set SELF plant # Will be translated to `self = newCell(PLANT, ...)`
```

```yaml
rules:
    evaporate:
        if: (SELF is lava || SELF is fire) && DOWN is liquid
        do: set DOWN smoke, swap(SELF, DOWN)
```


### Defining types

Types are just a collection of rules, coupled with inheritance.

```yaml
types:
    typename:
        inherits: something
        base_rules: [
            rule1,
            rule2
        ]
```

#### Examples

```yaml
types:
    movable_solid:
        base_rules: [
            gravity,
            slide_diagonally
        ]
```

This would evaluate to
`#define TYPE_MOVABLE_SOLID <index/ id>`


### Defining materials

```yaml
materials:
    materialname:
        color: [1.0, 0.5, 0.0, 1.0]
        type: <type> # By specifying a type, this material inherits all rules of the base type
        selectable: true
        density: 2.2
        extra_rules: [
            somerule
        ]
```

#### Examples

```yaml
materials:
    lava:
        color: [0.9, 0.2, 0.1, 1.0],
        type: liquid
        selectable: true
        density: 1.2
        extra_rules: [
            evaporate
        ]

```
