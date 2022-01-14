package cubyz.world.items.tools;

import java.awt.image.BufferedImage;

import org.joml.Vector2f;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Registry;
import cubyz.utils.json.JsonArray;
import cubyz.utils.json.JsonObject;
import cubyz.world.blocks.Blocks;
import cubyz.world.items.Item;

public class Tool extends Item {
	public final Item[] craftingGrid;
	public final Item[][] materialGrid = new Item[16][16];
	public final BufferedImage texture = new BufferedImage(16, 16, BufferedImage.TYPE_INT_ARGB);

	/** Reduction factor to block breaking time. */
	public float pickaxePower;
	/** Reduction factor to block breaking time. */
	public float axePower;
	/** Reduction factor to block breaking time. */
	public float shovelPower;
	/** TODO: damage */
	public float damage = 1;

	public int durability;
	public int maxDurability;

	/** How long it takes to swing the tool in seconds. */
	public float swingTime;

	float mass;

	/** Where the player holds the tool. */
	public final Vector2f handlePosition = new Vector2f();
	/** Moment of inertia relative to the handle */
	float inertiaHandle;

	/** Where the tool rotates around when being thrown. */
	public final Vector2f centerOfMass = new Vector2f();
	/** Moment of inertia relative to the center of mass */
	float inertiaCenterOfMass;

	/**
	 * Creates a new tool from contents of the crafting grid.
	 * @param craftingGrid must be a 5×5 grid with only material items in it.
	 */
	public Tool(Item[] craftingGrid) {
		super(1);
		this.craftingGrid = craftingGrid;
		// Produce the tool and its textures:
		// The material grid, which comes from texture generation, is needed on both server and client, to generate the tool properties.
		TextureGenerator.generate(this);
		ToolPhysics.evaluateTool(this);
	}
	/**
	 * Loads a tool from a json file.
	 * @param items
	 * @param registries
	 */
	public Tool(JsonObject json, CurrentWorldRegistries registries) {
		this(extractItemsFromJson(json.getArrayNoNull("grid"), registries.itemRegistry));
		durability = json.getInt("durability", maxDurability);
	}

	private static Item[] extractItemsFromJson(JsonArray json, Registry<Item> registry) {
		Item[] items = new Item[25];
		String[] ids = new String[25];
		json.getStrings(ids);
		for(int i = 0; i < ids.length; i++) {
			items[i] = registry.getByID(ids[i]);
		}
		return items;
	}

	public JsonObject save() {
		JsonObject json = new JsonObject();
		JsonArray array = new JsonArray();
		String[] ids = new String[craftingGrid.length];
		for(int i = 0; i < craftingGrid.length; i++) {
			if (craftingGrid[i] != null) {
				ids[i] = craftingGrid[i].getRegistryID().toString();
			} else {
				ids[i] = "null";
			}
		}
		array.addStrings(ids);
		json.put("grid", array);
		json.put("durability", durability);
		return json;
	}

	@Override
	public int hashCode() {
		int hash = 0;
		for(Item item : craftingGrid) {
			if (item != null) {
				hash = 33 * hash + item.material.hashCode();
			}
		}
		return hash;
	}

	public float getDamage() {
		return damage;
	}

	public float getPower(int block) {
		switch(Blocks.blockClass(block)) {
			case FLUID:
				return 0;
			case LEAF:
				return 1; // TODO
			case SAND:
				return shovelPower;
			case STONE:
				return pickaxePower;
			case UNBREAKABLE:
				return 0;
			case WOOD:
				return axePower;
			default:
				return 0;
		}
	}

	/**
	 * Uses the tool and returns true if it should be deleted.
	 */
	public boolean onUse() {
		durability--;
		return durability <= 0;
	}
}
