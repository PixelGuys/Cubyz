package cubyz.world.terrain.biomes;

import java.util.function.Consumer;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.utils.datastructures.ChanceObject;
import cubyz.utils.datastructures.FastList;
import cubyz.utils.json.JsonArray;
import cubyz.utils.json.JsonElement;
import cubyz.utils.json.JsonObject;

/**
 * A climate region with special ground, plants and structures.
 */

public class Biome extends ChanceObject implements RegistryElement {
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
		/**cold, icy, lowland*/
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
		TRENCH;
	}
	
	public final Type type;
	public final float minHeight, maxHeight;
	public final float roughness;
	public final float hills;
	public final float mountains;
	private final Resource identifier;
	public final BlockStructure struct;
	/** Whether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways. */
	public final boolean supportsRivers;
	/** The first members in this array will get prioritized. */
	public final StructureModel[] vegetationModels;
	public Biome[] upperReplacements = new Biome[0];
	public Biome[] lowerReplacements = new Biome[0];
	public final String preferredMusic;
	public final boolean isValidPlayerSpawn;
	
	public Biome(Resource id, String type, float min, float max, float roughness, float hills, float mountains, float chance, String music, BlockStructure str, boolean rivers, boolean isValidPlayerSpawn, StructureModel ... models) {
		super(chance);
		this.type = Type.valueOf(type);
		identifier = id;
		this.roughness = roughness;
		this.hills = hills;
		this.mountains = mountains;
		minHeight = min;
		maxHeight = max;
		struct = str;
		supportsRivers = rivers;
		vegetationModels = models;
		preferredMusic = music;
		this.isValidPlayerSpawn = isValidPlayerSpawn;
	}

	public Biome(Resource id, JsonObject json) {
		super(json.getFloat("chance", 1));
		this.type = Type.valueOf(json.getString("type", "grassland").toUpperCase());
		identifier = id;
		this.roughness = json.getFloat("roughness", 0);
		this.hills = json.getFloat("hills", 0);
		this.mountains = json.getFloat("mountains", 0);
		minHeight = json.getFloat("minHeight", 0);
		maxHeight = json.getFloat("maxHeight", 1);
		supportsRivers = json.getBool("rivers", false);
		preferredMusic = json.getString("music", null);
		isValidPlayerSpawn = json.getBool("validPlayerSpawn", false);

		String[] blockStructure = json.getArrayNoNull("ground_structure").getStrings();
		struct = new BlockStructure(blockStructure);

		JsonArray structures = json.getArrayNoNull("structures");
		FastList<StructureModel> vegetation = new FastList<StructureModel>(new StructureModel[structures.array.size()]);
		for(JsonElement elem : structures.array) {
			if (elem instanceof JsonObject) {
				StructureModel model = StructureModel.loadStructure((JsonObject) elem);
				if (model != null)
					vegetation.add(model);
			}
		}
		vegetationModels = vegetation.toArray();
	}
	
	@Override
	public Resource getRegistryID() {
		return identifier;
	}
	
	public static void checkLowerTypesInRegistry(Type type, Consumer<Biome> consumer, BiomeRegistry reg) {
		switch(type) {
			case RAINFOREST:
			case SHRUBLAND:
			case DESERT:
				reg.byTypeBiomes.get(Type.WARM_OCEAN).forEach(consumer);
				break;
			case SWAMP:
			case FOREST:
			case GRASSLAND:
				reg.byTypeBiomes.get(Type.OCEAN).forEach(consumer);
				break;
			case TUNDRA:
			case TAIGA:
			case GLACIER:
				reg.byTypeBiomes.get(Type.ARCTIC_OCEAN).forEach(consumer);
				break;
			case MOUNTAIN_FOREST:
				reg.byTypeBiomes.get(Type.FOREST).forEach(consumer);
				break;
			case MOUNTAIN_GRASSLAND:
				reg.byTypeBiomes.get(Type.GRASSLAND).forEach(consumer);
				break;
			case PEAK:
				reg.byTypeBiomes.get(Type.TUNDRA).forEach(consumer);
				break;
			case WARM_OCEAN:
			case OCEAN:
			case ARCTIC_OCEAN:
				reg.byTypeBiomes.get(Type.TRENCH).forEach(consumer);
				break;
			default:
				break;
		}
	}
	
	public static void checkHigherTypesInRegistry(Type type, Consumer<Biome> consumer, BiomeRegistry reg) {
		switch(type) {
			case SWAMP:
			case RAINFOREST:
			case FOREST:
			case TAIGA:
				reg.byTypeBiomes.get(Type.MOUNTAIN_FOREST).forEach(consumer);
				break;
			case SHRUBLAND:
			case GRASSLAND:
				reg.byTypeBiomes.get(Type.MOUNTAIN_GRASSLAND).forEach(consumer);
				break;
			case MOUNTAIN_FOREST:
			case MOUNTAIN_GRASSLAND:
				reg.byTypeBiomes.get(Type.PEAK).forEach(consumer);
				break;
			case DESERT:
			case TUNDRA:
			case GLACIER:
				reg.byTypeBiomes.get(Type.PEAK).forEach(consumer);
				break;
			case WARM_OCEAN:
				reg.byTypeBiomes.get(Type.RAINFOREST).forEach(consumer);
				reg.byTypeBiomes.get(Type.SHRUBLAND).forEach(consumer);
				reg.byTypeBiomes.get(Type.DESERT).forEach(consumer);
				break;
			case OCEAN:
				reg.byTypeBiomes.get(Type.SWAMP).forEach(consumer);
				reg.byTypeBiomes.get(Type.FOREST).forEach(consumer);
				reg.byTypeBiomes.get(Type.GRASSLAND).forEach(consumer);
				break;
			case ARCTIC_OCEAN:
				reg.byTypeBiomes.get(Type.GLACIER).forEach(consumer);
				reg.byTypeBiomes.get(Type.TUNDRA).forEach(consumer);
				break;
				
			case TRENCH:
				reg.byTypeBiomes.get(Type.ARCTIC_OCEAN).forEach(consumer);
				reg.byTypeBiomes.get(Type.OCEAN).forEach(consumer);
				reg.byTypeBiomes.get(Type.WARM_OCEAN).forEach(consumer);
				break;
			default:
				break;
		}
	}
}
