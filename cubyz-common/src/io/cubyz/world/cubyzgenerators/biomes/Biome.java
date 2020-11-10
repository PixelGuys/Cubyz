package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;

/**
 * A climate region with special ground, plants and structures.
 */

public class Biome implements RegistryElement {
	public static enum Type {
		/**hot, wet, lowland*/
		RAINFOREST,
		/**hot, medium, lowland*/
		SHRUBLAND,
		/**hot, dry, lowland*/
		DESERT,
		/**temperate, wet, lowland*/
		SWAMP,
		/**temperate, medium, lowland*/
		FOREST,
		/**temperate, dry, lowland*/
		GRASSLAND,
		/**cold, icy, lowland*/
		TUNDRA,
		/**cold, medium, lowland*/
		TAIGA,
		
		
		/**cold, icy, highland or polar lowland*/
		GLACIER,
		

		/**temperate, medium, highland*/
		MOUNTAIN_FOREST,
		/**temperate, dry, highland*/
		MOUNTAIN_GRASSLAND,
		/**cold, dry, highland*/
		PEAK,
		

		/**temperate ocean*/
		OCEAN,
		/**tropical ocean(coral reefs and stuff)*/
		WARM_OCEAN,
		/**arctic ocean(ice sheets)*/
		ARCTIC_OCEAN,
		
		/**deep ocean trench*/
		TRENCH,
		
		
		/**region that never sees the sun, due to how the torus orbits it.*/
		ETERNAL_DARKNESS,
	}
	public final Type type;
	public float height;
	public float minHeight, maxHeight;
	float roughness;
	protected Resource identifier;
	public BlockStructure struct;
	private boolean supportsRivers; // Whether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	private StructureModel[] vegetationModels; // The first members in this array will get prioritized.
	
	// The coefficients are represented like this: a[0] + a[1]*x + a[2]*x^2 + … + a[n-1]*x^(n-1)
	public Biome(Resource id, String type, float height, float min, float max, float roughness, BlockStructure str, boolean rivers, StructureModel ... models) {
		this.type = Type.valueOf(type);
		identifier = id;
		this.roughness = roughness;
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
	
	@Override
	public Resource getRegistryID() {
		return identifier;
	}
	public float getRoughness() {
		return roughness*Math.min(maxHeight - height, height - minHeight)/(maxHeight - minHeight);
	}
}
