package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;

public class Biome implements RegistryElement {
	float heat;
	float height;
	public float minHeight, maxHeight;
	float roughness;
	protected Resource identifier;
	public BlockStructure struct;
	private boolean supportsRivers; // Wether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	private VegetationModel[] vegetationModels; // The first members in this array will get prioritized.
	
	// The coefficients are represented like this: a[0] + a[1]*x + a[2]*x^2 + … + a[n-1]*x^(n-1)
	public Biome(Resource id, float heat, float height, float min, float max, float roughness, BlockStructure str, boolean rivers, VegetationModel ... models) {
		identifier = id;
		this.heat = heat;
		this.height = height;
		this.roughness = roughness;
		minHeight = min;
		maxHeight = max;
		struct = str;
		supportsRivers = rivers;
		vegetationModels = models;
	}
	public boolean supportsRivers() {
		return supportsRivers;
	}
	
	public VegetationModel[] vegetationModels() {
		return vegetationModels;
	}

	public float dist(float h, float t) {
		if(h >= maxHeight || h <= minHeight) return Float.MAX_VALUE;
		float heightFactor;
		if(h >= height) {
			heightFactor = (h-height)/(maxHeight-height);
		} else {
			heightFactor = (h-height)/(minHeight-height);
		}
		// Make sure heightFactor goes to ∞ when it gets to the borders, which are thanks to the code piece above at ±1.
		// This is done using the function 1/(1-x²) - 1 which also has the advantage of being close to x²(matching normal distance calculation) for small x.
		heightFactor = 1/(1-heightFactor*heightFactor) - 1;
		// Heat is more important than height and therefor scaled by 2:
		float dist = 2*(heat-t)*(heat-t) + heightFactor;
		return dist;
	}
	
	@Override
	public Resource getRegistryID() {
		return identifier;
	}
	public float getRoughness(float h) {
		return Math.min(h-minHeight, maxHeight-h);
	}
}
