use std::env;
use copy_to_output::copy_to_output;

fn main() {
    println!("cargo:rerun-if-changed=data/*");
    let profile = &env::var("PROFILE").unwrap();
    copy_to_output("data", profile).expect("Could not copy");
    copy_to_output("shaders", profile).expect("Could not copy");
}