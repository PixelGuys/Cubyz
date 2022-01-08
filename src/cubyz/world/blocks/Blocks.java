package cubyz.world.blocks;

import java.util.HashMap;

import org.joml.Vector3i;

import cubyz.utils.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.api.DataOrientedRegistry;
import cubyz.api.Resource;
import cubyz.client.ClientOnly;
import cubyz.utils.json.JsonObject;
import cubyz.world.World;
import cubyz.world.items.BlockDrop;
import cubyz.world.items.Inventory;

public class Blocks implements DataOrientedRegistry {
	public static enum BlockClass {
		WOOD, STONE, SAND, UNBREAKABLE, LEAF, FLUID, AIR
	};
	/**
	 * The total maximum of different block types.
	 * 65536 might not seem like much, but the actual number of different models is a lot higher thanks to RotationModes.
	 * 65536 means that there are 16 Bits reserved for block data.
	 */
	public static final int MAX_BLOCK_COUNT = 65536;
	public static final int TYPE_MASK = 0xffff;

	private static int size = 1; // Start at 1 to account for air.


	private static boolean[] lightingTransparent = new boolean[MAX_BLOCK_COUNT];
	private static boolean[] transparent = new boolean[MAX_BLOCK_COUNT];
	private static Resource[] id = new Resource[MAX_BLOCK_COUNT];

	/**Time in seconds to break this block by hand.*/
	private static float[] hardness = new float[MAX_BLOCK_COUNT];
	/**Minimum pickaxe/axe/shovel power required.*/
	private static float[] breakingPower = new float[MAX_BLOCK_COUNT];
	private static boolean[] solid = new boolean[MAX_BLOCK_COUNT];
	private static boolean[] selectable = new boolean[MAX_BLOCK_COUNT];
	private static BlockDrop[][] blockDrops = new BlockDrop[MAX_BLOCK_COUNT][];
	/**Meaning undegradable parts of trees or other structures can grow through this block.*/
	private static boolean[] degradable = new boolean[MAX_BLOCK_COUNT];
	private static boolean[] viewThrough = new boolean[MAX_BLOCK_COUNT];
	private static BlockClass[] blockClass = new BlockClass[MAX_BLOCK_COUNT];
	private static int[] light = new int[MAX_BLOCK_COUNT];
	/**How much light this block absorbs if it is transparent.*/
	private static int[] absorption = new int[MAX_BLOCK_COUNT];
	/**GUI that is opened on click.*/
	private static String[] gui = new String[MAX_BLOCK_COUNT];
	private static RotationMode[] mode = new RotationMode[MAX_BLOCK_COUNT];

	private static Class<? extends BlockEntity>[] blockEntity = new Class[MAX_BLOCK_COUNT];

	private static HashMap<String, Integer> reverseIndices = new HashMap<>();



	
	/**
	 * @return Whether this block is transparent to the lighting system.
	 */
	public static boolean lightingTransparent(int block) {
		return lightingTransparent[block & TYPE_MASK] || viewThrough(block);
	}
	public static boolean transparent(int block) {
		return transparent[block & TYPE_MASK];
	}
	public static Resource id(int block) {
		return id[block & TYPE_MASK];
	}

	/**Time in seconds to break this block by hand.*/
	public static float hardness(int block) {
		return hardness[block & TYPE_MASK];
	}
	/**Minimum pickaxe/axe/shovel power required.*/
	public static float breakingPower(int block) {
		return breakingPower[block & TYPE_MASK];
	}
	public static boolean solid(int block) {
		return solid[block & TYPE_MASK];
	}
	public static boolean selectable(int block) {
		return selectable[block & TYPE_MASK];
	}
	public static BlockDrop[] blockDrops(int block) {
		return blockDrops[block & TYPE_MASK];
	}
	public static void addBlockDrop(int block, BlockDrop bd) {
		BlockDrop[] newDrops = new BlockDrop[blockDrops[block].length+1];
		System.arraycopy(blockDrops[block], 0, newDrops, 0, blockDrops[block].length);
		newDrops[blockDrops[block].length] = bd;
		blockDrops[block] = newDrops;
	}
	/**Meaning undegradable parts of trees or other structures can grow through this block.*/
	public static boolean degradable(int block) {
		return degradable[block & TYPE_MASK];
	}
	public static boolean viewThrough(int block) {
		if (mode[block & TYPE_MASK] == null) {
			Logger.debug(block);
			System.exit(1);
		}
		return viewThrough[block & TYPE_MASK] || mode[block & TYPE_MASK].checkTransparency(block, 0);
	}
	public static BlockClass blockClass(int block) {
		return blockClass[block & TYPE_MASK];
	}
	public static int light(int block) {
		return light[block & TYPE_MASK];
	}
	/**How much light this block absorbs if it is transparent.*/
	public static int absorption(int block) {
		return absorption[block & TYPE_MASK];
	}
	/**GUI that is opened on click.*/
	public static String gui(int block) {
		return gui[block & TYPE_MASK];
	}
	public static RotationMode mode(int block) {
		return mode[block & TYPE_MASK];
	}
	
	public static Class<? extends BlockEntity> blockEntity(int block) {
		return blockEntity[block & TYPE_MASK];
	}
	
	public static void setBlockEntity(int block, Class<? extends BlockEntity> ent) {
		blockEntity[block & TYPE_MASK] = ent;
	}
	
	public static BlockEntity createBlockEntity(int block, World world, Vector3i pos) {
		if (blockEntity != null) {
			try {
				return blockEntity[block & TYPE_MASK].getConstructor(World.class, Vector3i.class).newInstance(world, pos);
			} catch (Exception e) {
				Logger.error(e);
			}
		}
		return null;
	}

	public static int getByID(String id) {
		if (!reverseIndices.containsKey(id)) {
			Logger.error("Couldn't find block "+id+". Replacing it with air...");
			return 0;
		}
		return reverseIndices.getOrDefault(id, 0);
	}

	/**
	 * Fires the blocks on click event(usually nothing or GUI opening).
	 * @param world
	 * @param pos
	 * @return if the block did something on click.
	 */
	public static boolean onClick(int block, World world, Vector3i pos) {
		if (gui[block & TYPE_MASK] != null) {
			ClientOnly.client.openGUI("cubyz:workbench", new Inventory(26)); // TODO: Care about the inventory.
			return true;
		}
		return false;
	}

	public static int size() {
		return size;
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz:blocks");
	}

	public Blocks() {
		id[0] = new Resource("cubyz:air");
		breakingPower[0] = 0;
		hardness[0] = 0;
		blockClass[0] = BlockClass.AIR;
		light[0] = 0;
		absorption[0] = 0;
		lightingTransparent[0] = true;
		degradable[0] = true;
		selectable[0] = false;
		solid[0] = false;
		gui[0] = null;
		mode[0] = null;
		transparent[0] = true;
		viewThrough[0] = true;
		blockDrops[0] = null;
	}

	@Override
	public int register(String assetPath, Resource id, JsonObject json) {
		if (reverseIndices.containsKey(id.toString())) {
			Logger.error("Attempted to register block with id "+id+" twice!");
			return reverseIndices.get(id.toString());
		}
		reverseIndices.put(id.toString(), size);
		Blocks.id[size] = id;
		breakingPower[size] = json.getFloat("breakingPower", 0);
		hardness[size] = json.getFloat("hardness", 1);
		blockClass[size] = BlockClass.valueOf(json.getString("class", "STONE").toUpperCase());
		light[size] = json.getInt("emittedLight", 0);
		absorption[size] = json.getInt("absorbedLight", 0);
		lightingTransparent[size] = json.has("absorbedLight");
		degradable[size] = json.getBool("degradable", false);
		selectable[size] = json.getBool("selectable", true);
		solid[size] = json.getBool("solid", true);
		gui[size] = json.getString("GUI", null);
		mode[size] = CubyzRegistries.ROTATION_MODE_REGISTRY.getByID(json.getString("rotation", "cubyz:no_rotation"));
		transparent[size] = json.getBool("transparent", false);
		viewThrough[size] = json.getBool("viewThrough", false) || transparent[size];
		blockDrops[size] = new BlockDrop[0];
		return size++;
	}

	@Override
	public void reset(int len) {
		// null all references to allow garbage collect.
		for(int i = len; i < size; i++) {
			reverseIndices.remove(id[i].toString());
			id[i] = null;
			blockDrops[i] = null;
			gui[i] = null;
			mode[i] = null;
			blockEntity[i] = null;
		}
		size = len;
	}
	
}
