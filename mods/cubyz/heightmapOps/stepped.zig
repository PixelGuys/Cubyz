pub fn run(roughnessValue: f32, hillsValue: f32, mountainsValue: f32, roughness: f32, hills: f32, mountains: f32) f32 {
	const variation = roughness*roughnessValue + mountainsValue*mountains;
	const steps = stepFunction(hillsValue*hills/8)*8;
	return variation + steps;
}

fn stepFunction(x: f32) f32 {
	const xmod2 = @mod(x, 2);
	if(xmod2 < 1) {
		return 2.0*xmod2*xmod2 - xmod2 + x;
	} else {
		return @mod(2 - x, 2) + x;
	}
}
