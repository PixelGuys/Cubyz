package io.cubyz.world.cubyzgenerators.biomes;

import java.util.ArrayList;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;

public class Biome implements IRegistryElement {
	float[] terrainPolynomial; // Use a polynomial function to add some terrain changes. At biome borders this polynomial will be interpolated between the two.
	float heat;
	float height;
	protected Resource identifier;
	
	// The coefficients are represented like this: a[0] + a[1]*x + a[2]*x^2 + … + a[n-1]*x^(n-1)
	// TODO: Vegetation models.
	public Biome(Resource id, float[] polynomial, float heat, float height) {
		identifier = id;
		terrainPolynomial = polynomial;
		// TODO: Make sure there are no range problems.

		this.heat = heat;
		this.height = height;
	}
	public float evaluatePolynomial(float x) {
		float res = terrainPolynomial[0];
		float x2 = 1;
		for(int i = 1; i < terrainPolynomial.length; i++) {
			x2 *= x;
			res += x2*terrainPolynomial[i];
		}
		return res;
	}

	
	public static Biome getBiome(float height, float heat) {
		// Just take the closest one. TODO: Better system.
		float closest = Float.MAX_VALUE;
		Biome c = null;
		for(IRegistryElement o : CubyzRegistries.BIOME_REGISTRY.registered()) {
			Biome b = (Biome) o;
			// Heat is more important than height and therefor scaled by 2:
			float dist = 2*(b.heat-heat)*(b.heat-heat) + (b.height-height)*(b.height-height);
			if(dist < closest) {
				c = b;
				closest = dist;
			}
		}
		return c;
	}
	
	@Override
	public Resource getRegistryID() {
		return identifier;
	}
	
	@Override
	public void setID(int ID) {
		throw new UnsupportedOperationException();
	}
}
