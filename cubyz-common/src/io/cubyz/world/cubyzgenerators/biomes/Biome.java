package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;

public class Biome implements RegistryElement {
	float temperature;
	float humidity;
	float height;
	public float minHeight, maxHeight;
	float roughness;
	protected Resource identifier;
	public BlockStructure struct;
	private boolean supportsRivers; // Wether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	private StructureModel[] vegetationModels; // The first members in this array will get prioritized.
	
	// The coefficients are represented like this: a[0] + a[1]*x + a[2]*x^2 + … + a[n-1]*x^(n-1)
	public Biome(Resource id, float humidity, float temperature, float height, float min, float max, float roughness, BlockStructure str, boolean rivers, StructureModel ... models) {
		identifier = id;
		this.roughness = roughness;
		this.temperature = temperature;
		this.humidity = humidity;
		this.height = height;
		minHeight = min;
		maxHeight = max;
		struct = str;
		supportsRivers = rivers;
		vegetationModels = models;
	}
	public boolean supportsRivers() {
		return supportsRivers;
	}
	
	public StructureModel[] vegetationModels() {
		return vegetationModels;
	}

	public float dist(float h, float t, float hum) {
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
		// Heat and humidity are more important than height and therefor scaled by 10:
		float dist = 10*(temperature-t)*(temperature-t) + 10*(humidity - hum)*(humidity - hum) + heightFactor;
		return dist;
	}
	
	@Override
	public Resource getRegistryID() {
		return identifier;
	}
	public float getRoughness() {
		return roughness*Math.min(maxHeight - height, height - minHeight)/(maxHeight - minHeight);
	}
}
