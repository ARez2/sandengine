extern crate wrapped2d;

use wrapped2d::b2;
use wrapped2d::user_data::NoUserData;

type World = b2::World<NoUserData>;


pub struct Physics {

}
impl Physics {
    pub fn new() -> Self {
        let mut world = World::new(&b2::Vec2 { x: 0., y: -10. });

        let b_def = b2::BodyDef {
            body_type: b2::BodyType::Static,
            position: b2::Vec2 { x: 0., y: -10. },
            ..b2::BodyDef::new()
        };

        let ground_box = b2::PolygonShape::new_box(20., 1.);

        let ground_handle = world.create_body(&b_def);
        world
            .body_mut(ground_handle)
            .create_fast_fixture(&ground_box, 0.);

        let mut b_def = b2::BodyDef {
            body_type: b2::BodyType::Dynamic,
            position: b2::Vec2 { x: -20., y: 20. },
            ..b2::BodyDef::new()
        };

        let cube_shape = b2::PolygonShape::new_box(1., 1.);

        let mut circle_shape = b2::CircleShape::new();
        circle_shape.set_radius(1.);

        let mut f_def = b2::FixtureDef {
            density: 1.,
            restitution: 0.2,
            friction: 0.3,
            ..b2::FixtureDef::new()
        };

        Physics {
        }
    }
}