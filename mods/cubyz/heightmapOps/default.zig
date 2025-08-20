pub fn run(roughnessValue: f32, hillsValue: f32, mountainsValue: f32, roughness: f32, hills: f32, mountains: f32) f32 {
	return roughnessValue*roughness + hillsValue*hills + mountainsValue*mountains;
}
