package io.cubyz.world.cubyzgenerators.biomes;

import java.util.ArrayList;

public class Biome {
	float[] terrainPolynomial; // Use a polynomial function to add some terrain changes. At biome borders this polynomial will be interpolated between the two.
	float heat;
	float height;
	// The coefficients are represented like this: a[0] + a[1]*x + a[2]*x^2 + … + a[n-1]*x^(n-1)
	// TODO: Vegetation models.
	public Biome(float[] polynomial, float heat, float height) {
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
	
	
	// Register them here for now. TODO: @zenith you should implement that into the registry system at some point.
	private static ArrayList<Biome> biomes = new ArrayList<>();
	public static Biome getBiome(float height, float heat) {
		// Just take the closest one. TODO: Better system.
		float closest = Float.MAX_VALUE;
		Biome c = null;
		for(Biome b: biomes) {
			// Heat is more important than height and therefor scaled by 2:
			float dist = 2*(b.heat-heat)*(b.heat-heat) + (b.height-height)*(b.height-height);
			if(dist < closest) {
				c = b;
				closest = dist;
			}
		}
		return c;
	}
	static { // Add some random biomes TODO: More biomes.
		// When creating a new biome there is one things to keep in mind: At their optimal height the biome's polynomial shut return that same height, otherwise terrain generation will get buggy.
		float pol[];
		// Beach:
		pol = new float[] {0.0f, 1.5003947420951773f, -1.7562874281379752f, 1.255892686042798f};
		biomes.add(new Biome(pol, 130.0f/360.0f, 102.0f/256.0f));
		// Flat lands:
		pol = new float[] {0.35f, 0.3f};
		biomes.add(new Biome(pol, 120.0f/360.0f, 128.0f/256.0f));
		// Normal lands low:
		pol = new float[] {0.0f, 1.136290302965442f, -0.44234572015099627f, 0.3060554171855542f};
		biomes.add(new Biome(pol, 110.0f/360.0f, 114.0f/256.0f));
		// Mountains:
		pol = new float[] {0.0f, 5.310967705272164f, -21.14717562082649f, 33.47195695260881f, -16.854499037054477f};
		biomes.add(new Biome(pol, 115.0f/360.0f, 140.0f/256.0f));
		// Extreme mountains:
		pol = new float[] {0.0f, 3.1151893301104367f, -13.738832774207244f, 25.171171602902316f, -13.766278158805507f};
		biomes.add(new Biome(pol, 115.0f/360.0f, 160.0f/256.0f));
	}
}
