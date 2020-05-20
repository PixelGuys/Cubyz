package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;

public class Biome implements IRegistryElement {
	float[] terrainPolynomial; // Use a polynomial function to add some terrain changes. At biome borders this polynomial will be interpolated between the two.
	float heat;
	float height;
	float minHeight, maxHeight;
	protected Resource identifier;
	public BlockStructure struct;
	private boolean supportsRivers; // Wether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	private VegetationModel[] vegetationModels; // The first members in this array will get prioritized.
	
	// The coefficients are represented like this: a[0] + a[1]*x + a[2]*x^2 + … + a[n-1]*x^(n-1)
	public Biome(Resource id, float[] polynomial, float heat, float height, float min, float max, BlockStructure str, boolean rivers, VegetationModel ... models) {
		identifier = id;
		terrainPolynomial = polynomial;
		// TODO: Make sure there are no range problems.

		this.heat = heat;
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
	public double evaluatePolynomial(double x) {
		double res = terrainPolynomial[0];
		double x2 = 1;
		for(int i = 1; i < terrainPolynomial.length; i++) {
			x2 *= x;
			res += x2*terrainPolynomial[i];
		}
		return res;
	}
	
	public VegetationModel[] vegetationModels() {
		return vegetationModels;
	}

	public float dist(float h, float t) {
		float heightFactor;
		if(h >= height) {
			heightFactor = (h-height)/(maxHeight-height);
		} else {
			heightFactor = (h-height)/(minHeight-height);
		}
		// Heat is more important than height and therefor scaled by 2:
		float dist = 2*(heat-t)*(heat-t) + heightFactor*heightFactor;
		return dist;
	}
	
	public static Biome getBiome(float height, float heat) {
		// Just take the closest one. TODO: Better system.
		float closest = Float.MAX_VALUE;
		Biome c = null;
		for(IRegistryElement o : CubyzRegistries.BIOME_REGISTRY.registered()) {
			Biome b = (Biome) o;
			if(b.minHeight <= height && b.maxHeight >= height) {
				float dist = b.dist(height, heat);
				if(dist < closest) {
					c = b;
					closest = dist;
				}
			}
		}
		if(c == null) System.out.println(height+" "+heat);
		return c;
	}
	
	public static float evaluatePolynomial(float height, float heat, float x) {
		// Creates a much smoother terrain by interpolating between the biomes based on their distance in the height-heat space.
		double res = 0;
		double weight = 0;
		for(IRegistryElement o : CubyzRegistries.BIOME_REGISTRY.registered()) {
			Biome b = (Biome)o;
			double dist = b.dist(height, heat);
			dist = Math.pow(dist, -1);
			res += b.evaluatePolynomial(x)*dist;
			weight += dist;
		}
		return (float)(res/weight);
	}
	
	@Override
	public Resource getRegistryID() {
		return identifier;
	}
}
