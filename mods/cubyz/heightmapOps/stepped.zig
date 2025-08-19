pub fn run(roughnessValue: f32, hillsValue: f32, mountainsValue: f32, roughness: f32, hills: f32, mountains: f32) f32 {
    const variation = roughness * roughnessValue + mountainsValue * mountains;
    const steps = stepFunction(hillsValue*hills/16)*16;
    return variation + steps;
}

fn stepFunction(x: f32) f32 {
    return @abs(@mod(x, 2.0) - 1.0) + x;
}