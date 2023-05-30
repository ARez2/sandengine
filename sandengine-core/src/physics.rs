
use std::time::Duration;

use nphysics2d::math::Point;
use nphysics2d::ncollide2d::shape::{Polyline, ShapeHandle, Ball};
use nphysics2d::object::{DefaultBodySet, DefaultColliderSet, ColliderDesc, BodyPartHandle, RigidBodyDesc, DefaultBodyHandle, DefaultColliderHandle, Body};
use nphysics2d::force_generator::DefaultForceGeneratorSet;
use nphysics2d::joint::DefaultJointConstraintSet;
use nphysics2d::world::{DefaultMechanicalWorld, DefaultGeometricalWorld};
use nphysics2d::nalgebra::{self as na, Point2, DimAdd, Isometry2};
use na::Vector2;

use rayon::prelude::*;

pub type PhysicsPrecision = f32;

pub struct Physics {
    mechanical_world: DefaultMechanicalWorld<PhysicsPrecision>,
    geometrical_world: DefaultGeometricalWorld<PhysicsPrecision>,

    bodies: DefaultBodySet<PhysicsPrecision>,
    colliders: DefaultColliderSet<PhysicsPrecision>,
    joint_constraints: DefaultJointConstraintSet<PhysicsPrecision>,
    force_generators: DefaultForceGeneratorSet<PhysicsPrecision>,

    terrain_parent_handle: BodyPartHandle<DefaultBodyHandle>,
    terrain_collider_handle: DefaultColliderHandle,
    rb_handle: DefaultBodyHandle,
    rb_part_handle: BodyPartHandle<DefaultBodyHandle>,
}
impl Physics {
    pub fn new() -> Self {
        let mechanical_world = DefaultMechanicalWorld::new(Vector2::new(0.0, -9.81));
        let geometrical_world = DefaultGeometricalWorld::new();

        let mut bodies = DefaultBodySet::new();
        let mut colliders = DefaultColliderSet::new();
        let joint_constraints = DefaultJointConstraintSet::new();
        let force_generators = DefaultForceGeneratorSet::new();

        // Setup terrain collision
        let parent_rigid_body = RigidBodyDesc::new()
            .status(nphysics2d::object::BodyStatus::Static)
            .build();
        let terrain_parent = bodies.insert(parent_rigid_body);
        let terrain_parent_handle = BodyPartHandle(terrain_parent, 0);
        let collider = ColliderDesc::new(ShapeHandle::new(Polyline::new(vec![Point2::new(0.0, 0.0), Point2::new(1.0, 1.0)], None)))
            .build(terrain_parent_handle);
        let terrain_collider_handle = colliders.insert(collider);

        // Setup ball collision
        let rb = RigidBodyDesc::new()
            .translation(Vector2::new(100.0, 200.0))
            .gravity_enabled(true)
            .build();
        let rb_handle = bodies.insert(rb);
        let rb_part_handle = BodyPartHandle(rb_handle, 0);
        let shape = ShapeHandle::new(Ball::new(1.5));
        let collider = ColliderDesc::new(shape)
            .build(rb_part_handle);
        let ball_collider_handle = colliders.insert(collider);
        
        Self {
            mechanical_world,
            geometrical_world,
            bodies,
            colliders,
            joint_constraints,
            force_generators,

            terrain_parent_handle,
            terrain_collider_handle,
            rb_handle,
            rb_part_handle,
        }
    }


    pub fn ball_pos(&mut self) -> Point2<PhysicsPrecision> {
        let rb: &mut dyn Body<f32> = self.bodies.get_mut(self.rb_part_handle.0).unwrap();
        // rb.set_translation(Vector2::new(pos.0, pos.1));
        
        let trans = rb.part(0).unwrap().position().translation;
        Point2::new(trans.x, trans.y)
    }


    pub fn set_delta(&mut self, delta: Duration) {
        self.mechanical_world.set_timestep(delta.as_secs_f32());
    }

    pub fn physics_step(&mut self) {
        self.mechanical_world.step(
            &mut self.geometrical_world,
            &mut self.bodies,
            &mut self.colliders,
            &mut self.joint_constraints,
            &mut self.force_generators,
        );
    }

    pub fn create_collision_from_texture(&mut self, texture: &glium::texture::Texture2d) -> Option<Vec<Point2<PhysicsPrecision>>> {
        let data = texture.read_to_pixel_buffer().read().unwrap();
        let width = texture.width() as usize;
        let w = width as PhysicsPrecision;
        let center: std::sync::Mutex<Point2<PhysicsPrecision>> = std::sync::Mutex::new(Point2::new(0.0, 0.0));
        let mut pts: Vec<(Point2<PhysicsPrecision>, usize)> = data.par_iter().enumerate().filter_map(|(idx, pix)| {
            if pix == &(255, 255, 255, 255) {
                let pt: Point2<PhysicsPrecision> = Point2::new(idx as PhysicsPrecision % w, idx as PhysicsPrecision / w);
                let mut c = center.lock().unwrap();
                *c = Point2::new(c.x + pt.x, c.y + pt.y);
                
                Some((pt, idx))
            } else {
                None
            }
        }).collect();
        // pts.par_sort_by_key(|(_, idx)| {
        //     *idx
        // });

        let mut reference_point = *center.lock().unwrap();
        reference_point = Point2::new(reference_point.x / pts.len() as f32, reference_point.y / pts.len() as f32);
        // Sort the points in clockwise order based on angles with respect to the reference point
        pts.par_sort_by(|&(ref pt1, _), &(ref pt2, _)| {
            let angle1 = calculate_angle(&reference_point, pt1);
            let angle2 = calculate_angle(&reference_point, pt2);
            angle1.partial_cmp(&angle2).unwrap()
        });
        let pts: Vec<Point2<PhysicsPrecision>> = pts.par_iter().map(|(pt, _)| {
            *pt
        }).collect();

        if pts.len() <= 0 {
            return None;
        }

        // Simplify the line by applying the Ramer-Douglas-Peucker algorithm
        let simplified_pts = simplify_line(&pts, 0.5);
        //println!("{:?}", pts);
        //simplified_pts

        if simplified_pts.len() < 2 {
            return None;
        }
        
        let polyline = Polyline::new(simplified_pts.clone(), None);
        let shape = ShapeHandle::new(polyline);

        self.colliders.remove(self.terrain_collider_handle);

        let collider = ColliderDesc::new(shape)
            .build(self.terrain_parent_handle);
        self.terrain_collider_handle = self.colliders.insert(collider);

        Some(simplified_pts)
    }
}

// Calculate the angle between two points with respect to the centroid
fn calculate_angle(centroid: &Point2<PhysicsPrecision>, point: &Point2<PhysicsPrecision>) -> PhysicsPrecision {
    let vector = point - centroid;
    vector.y.atan2(vector.x)
}


// Ramer-Douglas-Peucker algorithm
fn perpendicular_distance(
    point: &Point2<PhysicsPrecision>,
    start_point: &Point2<PhysicsPrecision>,
    end_point: &Point2<PhysicsPrecision>,
) -> PhysicsPrecision {
    let line_vector = end_point - start_point;
    let line_length = line_vector.norm();
    let normalized_line_vector = line_vector / line_length;

    let point_vector = *point - start_point;
    let dot_product = normalized_line_vector.dot(&point_vector);

    let perpendicular_point = start_point + dot_product * normalized_line_vector;

    (point - &perpendicular_point).norm()
}

fn simplify_recursive(
    points: &[Point2<PhysicsPrecision>],
    keep_indices: &mut [bool],
    start_index: usize,
    end_index: usize,
    epsilon: PhysicsPrecision,
) {
    if end_index <= start_index + 1 {
        return;
    }

    let mut max_distance = 0.0;
    let mut farthest_index = start_index;

    for i in (start_index + 1)..end_index {
        let distance = perpendicular_distance(&points[i], &points[start_index], &points[end_index]);

        if distance > max_distance {
            max_distance = distance;
            farthest_index = i;
        }
    }

    if max_distance > epsilon {
        keep_indices[farthest_index] = true;

        simplify_recursive(points, keep_indices, start_index, farthest_index, epsilon);
        simplify_recursive(points, keep_indices, farthest_index, end_index, epsilon);
    }
}

fn simplify_line(points: &[Point2<PhysicsPrecision>], epsilon: PhysicsPrecision) -> Vec<Point2<PhysicsPrecision>> {
    let num_points = points.len();

    if num_points < 3 {
        return points.to_vec();
    }

    let mut keep_indices = vec![false; num_points];
    keep_indices[0] = true;
    keep_indices[num_points - 1] = true;

    simplify_recursive(points, &mut keep_indices, 0, num_points - 1, epsilon);

    let simplified_points: Vec<Point2<PhysicsPrecision>> = points
        .iter()
        .zip(keep_indices.into_iter())
        .filter_map(|(&pt, keep)| if keep { Some(pt) } else { None })
        .collect();

    simplified_points
}
