# Sandengine - a falling sand simulation engine written in GLSL and Rust


## A note on compatibility

Even though the fragment and vertex shader use OpenGL version 1.4, the compute
shaders which runs the simulation **requires OpenGL 4.3** (version, where compute
shaders were introduced).



## Todo

### Usability

#### Improve how Materials are defined

### Add physics

- wrapped2D (Box2D) on the CPU simulates bodies
- each Cell stores its position relative one body
- **only static, non moving materials can be part of a rigidbody**
- after the CPU physics step, the transforms of all rigidbodies are transferred
to the GPU using a uniform array

- have 2 more uniform arrays for "new" and "queued for deletion" bodies

- the cell checks if its part of a body that is queued for deletion and if so,
sets itself to empty
- all other cells check the "queued for deletion" list to see if a body is being
deleted, that has a lower idx in the list of bodies and depending on how many
bodies that affects, subtract its own body index (*"2 bodies before my body are*
*getting deleted? `my_body_idx -= 2`*)

- maybe have a struct `RBContructor` to describe the texture (so that a cell can
set itself to the material on the texture if it is inside that rbs texture), pos,
rot of the new rb

```glsl
vec2 rotatePoint(vec2 pt, float rot) {
  return mat4(cos(rot), sin(rot), -sin(rot), cos(rot)) * pt;
}

vec2 rotatePoint(vec2 pt, float rot, vec2 origin) {
  return rotatePoint(pt - origin, rot) + origin;
}

vec2 new_pos = rotatePoint(self.pos, bodies[my_body_idx].rotation, bodies[my_body_idx].position);
```

### Add sounds

- ???


## YAML File Syntax

### Global scope

In general, most global scope things should be named in all uppercase so that you can recognize it and avoid confusion.

#### Cells

- `SELF` - The current cell
- `DOWN` - The cell below
- `RIGHT` - The cell to the right
- (`LEFT` - The cell to the left; **automatically causes the rule to be assymetric (`mirrored: false`)**)
- `DOWNRIGHT` - The cell down and to the right


#### Keywords

- **WIP:** `is` - Checks if something is an instance of a type or material (`typeof`)
- `<`, `>`, `==`, `!=`, `&&`/ `and`, `||`/ `or`, `not` - Logical Operators


#### Functions

- `SWAP <Cell 1> <Cell 2>` - Swaps both cells
    - Example: `SWAP SELF DOWN`
- `SET <Cell> <Material>` - Replaces the `Cell` with a new cell of that material
    - Example: `SET SELF stone` (assuming there is a `stone` material)
- `isType_<your type>(<Cell>)` - For each type defined in `types` there will be
a checker function that returns true if the argument (for example `SELF`) is
that type. **This accounts for inheritance, meaning if the type `plant` inherits**
**the type `organism` (via `inherits: organism`) then**
**`isType_organism(<some plant cell>)` will be true**


#### Materials and Types

- (`TYPE_`)`EMPTY` - The air/ empty material/ type for a cell
- (`TYPE_`)`NULL` - The material/ type that is returned if its nothing else is
- (`TYPE_`)`WALL` - The material/ type just outside the screen

Both `WALL` and `NULL` can not be swapped with another cell.


### Defining rules

Rules will be processed in the order that they are defined.

#### IMPORTANT: Concept of mirrored rules

This simulation uses the margolus offset, meaning each cell can only freely access groups of 2x2 pixels.
That means that "normally" you would **only have access to the own pixel, right,**
**down and downright** pixel.
In order to not limit the user too strictly, after each frame the offset is **shifted**
so that when you write `RIGHT` in a `if` or `do`, then you can assume that it
will be either the left (`LEFT`) or right (`RIGHT`) cell depending on the frame.
The same applies for `DOWNRIGHT`: It is __either__ the cell **down-right** from
the current cell or the cell **down-left** depending on the frame.

This is what is called mirroring in the YAML syntax and which can be turned off
using the `mirrored: false` attribute.

Doing this will cause the parser to look for either access of `LEFT` or `RIGHT`,
turning it into a rule that will be only be run for one of the two options.

#### Syntax

The following lists all possible attributes of a rule, with the values being the default values:

```yaml
# Collection of all rules, this field name cannot be changed and
# will throw an error if non-existent
rules:
    # Name of the rule
    rulename:
        # Condition that needs to be true in order for the do action to run
        if: <condition>
        # Action that will be run when the if condition is true
        do: <some action>
        # Alternative do syntax (for multiple actions):
        # do:
        #     - <action 1>
        #     - <action 2>
        #     - ...
        # OPTIONAL: Only if a random value from 0-1 is smaller than this value
        # the do action will be run
        chance: 1.0

        # OPTIONAL: Provides an alternative path for when the if condition is false
        else:
            # OPTIONAL: The if here can be left out to always execute the do action
            if: <condition>
            do: <action>
            # OPTIONAL: Same as the other chance
            chance: 1.0

        
        # OPTIONAL: Whether the rule should be mirrored to the left
        # see "Concept of mirrored rules"
        mirrored: true
        # OPTIONAL: The parser will detect on which type or material the rule was used and
        # will only allow that specific type/ material to run the rule (if SELF is that mat/ type)
        # Note, that if there is no precondition, the use of 'isType_<type>' is often neccesary
        precondition: true
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
        # check if there is a plant cell below us.
        # Could also check for a specific material for example
        # DOWN.mat == vine
        if: isType_empty(SELF) and isType_plant(DOWN)
        do: set SELF vine # vine is a material
```


### Defining types

Types are just a collection of rules, coupled with inheritance.

A parent type must be defined **before the child** (inheritant) can reference it.

```yaml
# Collection of all types, this field name cannot be changed and
# will throw an error if non-existent
types:
    # Name of the type
    typename:
        # OPTIONAL: Type of which to inherit all base_rules
        inherits: <some type>
        # OPTIONAL: List of rules that will be applied to all materials of that type
        # Can be left out if empty
        base_rules: []
```


#### Examples

```yaml
types:
    organism:
        base_rules: [
            grow
        ]
    plant:
        inherits: organism
        # Note there are no base_rules here
```

```yaml
types:
    solid:
    movable_solid:
        base_rules: [
            gravity,
            slide_diagonally
        ]
```

```yaml
rules:
  fall_slide:
    if: DOWN.mat.density < SELF.mat.density
    do:
      - SWAP SELF DOWN
    else:
      if: RIGHT.mat.density < SELF.mat.density and DOWNRIGHT.mat.density < SELF.mat.density
      do: SWAP SELF DOWNRIGHT
    mirrored: true
  rise_up:
    if: isType_gas(DOWN) and not isType_solid(SELF) and DOWN.mat.density < SELF.mat.density
    do: SWAP DOWN SELF
    else:
      if: isType_gas(DOWN) and not isType_solid(RIGHT) and DOWN.mat.density < RIGHT.mat.density
      do: SWAP DOWN RIGHT
    precondition: false
```


### Defining materials

```yaml
# Collection of all materials, this field name cannot be changed and
# will throw an error if non-existent
materials:
    # Name of the material
    materialname:
        # The color of the material, valid options for defining it are:
        # color: [255, 0, 255, 255]
        # color: [255, 0, 255] # Note, only 3 values with assume alpha is 1
        # color: [1.0, 0, 255, 0.3] # Example of mixed types
        color: [1.0, 0.0, 1.0, 1.0]
        # OPTIONAL: How much light the material should emit
        # See the color attribute for possible ways of defining the value
        emission: [0.0, 0.0, 0.0, 0.0]
        # By specifying a type, this material inherits all rules of the base type
        type: <type>
        # OPTIONAL: Whether the material can be selectable with NUM_0-9 or the UI
        selectable: true
        # Density of the material, used for swapping and vertical ordering of materials
        density: 2.2
        # OPTIONAL: Add some rules here which are unique to this material
        # and cannot be added to the type
        extra_rules: [
            somerule
        ]
```

#### Examples

```yaml
materials:
  sand:
    type: movable_solid
    color: [1.0, 1.0, 0]
    density: 1.5
  
  rock:
    type: solid
    color: [0.2, 0.2, 0.2]
    density: 4.0

  water:
    type: liquid
    color: [0.0, 0.0, 1.0, 0.5]
    density: 1.5

  radioactive:
    type: solid
    color: [0.196, 0.55, 0.184]
    emission: [0.05, 0.7, 0.05, 0.9]
    density: 5.0
```


## Project structure

This binary crate is a collection of library crates related to the **sandengine**.

### `sandengine-core`

Responsible for:

- Running the compute shader which simulates everything
- Rendering the simulation
- Rendering the UI

### `sandengine-lang`

Responsible for:

- Reading in the [YAML File](#yaml-file-syntax), defining rules, types and materials
- Parsing that input and producing Rust structs, holding the information
included in the the [YAML File](#yaml-file-syntax)
- Converting those structs into valid GLSL code (located under [shaders/compute/gen](https://github.com/ARez2/sandengine/tree/main/shaders/compute/gen))

### `data` folder

Holds textures, assets and the [YAML File](#yaml-file-syntax).
