package cubyz.world.entity;

import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.math.Bits;
import cubyz.world.ServerWorld;
import cubyz.world.items.tools.Tool;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.utils.Logger;
import cubyz.world.NormalChunk;
import cubyz.world.World;
import cubyz.world.blocks.Blocks;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;
import pixelguys.json.*;

/**
 * Manages all item entities of a single chunk.
 * Uses a data oriented implementation.
 */

public class ItemEntityManager {
	/**Radius of all item entities hitboxes as a unit sphere of the max-norm (cube).*/
	public static final float RADIUS = 0.1f;
	/**Diameter of all item entities hitboxes as a unit sphere of the max-norm (cube).*/
	public static final float DIAMETER = 2*RADIUS;

	public static final float PICKUP_RANGE = 1;

	private static final float MAX_AIR_SPEED_GRAVITY = 10;

	protected static final int MAX_CAPACITY = 65536;

	public final double[] posxyz = new double[3*MAX_CAPACITY];
	public final double[] velxyz = new double[3*MAX_CAPACITY];
	public final float[] rotxyz = new float[3*MAX_CAPACITY];
	public final ItemStack[] itemStacks = new ItemStack[MAX_CAPACITY];
	public final int[] despawnTime = new int[MAX_CAPACITY];
	/** How long the item should stay on the ground before getting picked up again. */
	public final int[] pickupCooldown = new int[MAX_CAPACITY];

	public final short[] indices = new short[MAX_CAPACITY];
	public final short[] reverseIndices = new short[MAX_CAPACITY];

	private final World world;
	private final float gravity;
	private final float airDragFactor;
	public int size;

	private int lastAdded = 0;

	public final JsonArray lastUpdates = new JsonArray();

	public ItemEntityManager(World world) {
		this.world = world;
		gravity = World.GRAVITY;
		// Assuming linear drag → air is a viscous fluid :D
		// a = d*v → d = a/v
		// a - acceleration(gravity), d - airDragFactor, v - MAX_AIR_SPEED_GRAVITY
		airDragFactor = gravity/MAX_AIR_SPEED_GRAVITY;
	}


	public void loadFrom(JsonObject json) {
		for(JsonElement elem : json.getArrayNoNull("array").array) {
			add(elem);
		}
	}

	public void add(JsonElement elem) {
		Item item = world.registries.itemRegistry.getByID(elem.getString("item", "null"));
		if(item == null) {
			// Check if it is a tool:
			JsonElement tool = elem.get("tool");
			if (tool != null) {
				item = new Tool(tool, world.registries);
			} else {
				Logger.error("Couldn't find item from json: "+elem);
				// item not existant in this version of the game. Can't do much so ignore it.
				return;
			}
		}
		if(((JsonObject)elem).map.containsKey("i")) {
			add(
				elem.getInt("i", 0),
				elem.getDouble("x", 0),
				elem.getDouble("y", 0),
				elem.getDouble("z", 0),
				elem.getDouble("vx", 0),
				elem.getDouble("vy", 0),
				elem.getDouble("vz", 0),
				new ItemStack(item, elem.getInt("amount", 1)),
				elem.getInt("despawnTime", 60),
				0
			);
		} else {
			add(
				elem.getDouble("x", 0),
				elem.getDouble("y", 0),
				elem.getDouble("z", 0),
				elem.getDouble("vx", 0),
				elem.getDouble("vy", 0),
				elem.getDouble("vz", 0),
				new ItemStack(item, elem.getInt("amount", 1)),
				elem.getInt("despawnTime", 60),
				0
			);
		}

	}

	public byte[] getPositionAndVelocityData() {
		byte[] data = new byte[size*(6*8 + 2)];
		int offset = 0;
		for(int ii = 0; ii < size; ii++) {
			int i = indices[ii] & 0xffff;
			Bits.putShort(data, offset, (short)i);
			offset += 2;
			Bits.putDouble(data, offset, posxyz[3*i]);
			offset += 8;
			Bits.putDouble(data, offset, posxyz[3*i+1]);
			offset += 8;
			Bits.putDouble(data, offset, posxyz[3*i+2]);
			offset += 8;
			Bits.putDouble(data, offset, velxyz[3*i]);
			offset += 8;
			Bits.putDouble(data, offset, velxyz[3*i+1]);
			offset += 8;
			Bits.putDouble(data, offset, velxyz[3*i+2]);
			offset += 8;
		}
		return data;
	}

	private JsonObject storeSingle(int i) {
		int i3 = i*3;
		JsonObject obj = new JsonObject();
		obj.put("i", i);
		obj.put("x", posxyz[i3]);
		obj.put("y", posxyz[i3 + 1]);
		obj.put("z", posxyz[i3 + 2]);
		obj.put("vx", velxyz[i3]);
		obj.put("vy", velxyz[i3 + 1]);
		obj.put("vz", velxyz[i3 + 2]);
		if(itemStacks[i].getItem() instanceof Tool) {
			obj.put("tool", ((Tool)itemStacks[i].getItem()).save());
		} else {
			obj.put("item", itemStacks[i].getItem().getRegistryID().toString());
		}
		obj.put("amount", itemStacks[i].getAmount());
		obj.put("despawnTime", despawnTime[i]);
		return obj;
	}

	public JsonObject store() {
		synchronized(this) {
			JsonArray items = new JsonArray();
			for(int ii = 0; ii < size; ii++) {
				JsonObject obj = storeSingle(indices[ii] & 0xffff);
				items.add(obj);
			}
			JsonObject json = new JsonObject();
			json.put("array", items);
			return json;
		}
	}

	public void update(float deltaTime) {
		for(int ii = 0; ii < size; ii++) {
			int i = indices[ii] & 0xffff;
			int i3 = i*3;
			NormalChunk chunk = world.getChunk((int)posxyz[i3], (int)posxyz[i3+1], (int)posxyz[i3+2]);
			if(chunk != null) {
				// Check collision with blocks:
				updateEnt(chunk, i3, deltaTime);
			}
			pickupCooldown[i]--;
			despawnTime[i]--;
			if (despawnTime[i] < 0) {
				remove(i);
				ii--;
			}
		}
	}

	public void checkEntity(Entity ent) {
		for(int ii = 0; ii < size; ii++) {
			int i = indices[ii] & 0xffff;
			int i3 = 3*i;
			if (pickupCooldown[i] >= 0) continue; // Item cannot be picked up yet.
			if (Math.abs(ent.position.x - posxyz[i3]) < ent.width + PICKUP_RANGE && Math.abs(ent.position.y + ent.height/2 - posxyz[i3 + 1]) < ent.height + PICKUP_RANGE && Math.abs(ent.position.z - posxyz[i3 + 2]) < ent.width + PICKUP_RANGE) {
				if(ent.getInventory().canCollect(itemStacks[i].getItem())) {
					if(ent instanceof Player) {
						// Needs to go through the network.
						for(User user : Server.users) {
							if(user.player == ent) {
								Protocols.GENERIC_UPDATE.itemStackCollect(user, itemStacks[i]);
								remove(i);
								ii--;
								break;
							}
						}
					} else {
						int newAmount = ent.getInventory().addItem(itemStacks[i].getItem(), itemStacks[i].getAmount());
						if(newAmount != 0) {
							itemStacks[i].setAmount(newAmount);
						} else {
							remove(i);
							ii--;
						}
					}
				}
			}
		}
	}

	public void add(int x, int y, int z, double vx, double vy, double vz, ItemStack itemStack, int despawnTime) {
		add(
			x + RADIUS + (1 - DIAMETER)*Math.random(),
			y + RADIUS + (1 - DIAMETER)*Math.random(),
			z + RADIUS + (1 - DIAMETER)*Math.random(),
			vx, vy, vz,
			(float)(2*Math.random()*Math.PI),
			(float)(2*Math.random()*Math.PI),
			(float)(2*Math.random()*Math.PI),
			itemStack, despawnTime, 0
		);
	}

	public void add(double x, double y, double z, double vx, double vy, double vz, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		add(x, y, z, vx, vy, vz, (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), itemStack, despawnTime, pickupCooldown);
	}

	public void add(int i, double x, double y, double z, double vx, double vy, double vz, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		add(
			i, x, y, z,
			vx, vy, vz,
			(float)(2*Math.random()*Math.PI),
			(float)(2*Math.random()*Math.PI),
			(float)(2*Math.random()*Math.PI),
			itemStack, despawnTime, pickupCooldown
		);
	}
	public void add(double x, double y, double z, double vx, double vy, double vz, float rotX, float rotY, float rotZ, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		synchronized(this) {
			if(size == MAX_CAPACITY) {
				Logger.error("capacity limit reached. Failed to add itemStack: "+itemStack.getAmount()+"×"+itemStack.getItem().getRegistryID());
				return;
			}
			while(itemStacks[lastAdded] != null) {
				lastAdded = lastAdded+1 & 0xffff;
			}
			add(lastAdded, x, y, z, vx, vy, vz, rotX, rotY, rotZ, itemStack, despawnTime, pickupCooldown);
		}
	}

	public void add(int i, double x, double y, double z, double vx, double vy, double vz, float rotX, float rotY, float rotZ, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		synchronized(this) {
			assert itemStacks[i] == null : "some item entities were not cleared correctly";
			int index3 = 3*i;
			posxyz[index3] = x;
			posxyz[index3 + 1] = y;
			posxyz[index3 + 2] = z;
			velxyz[index3] = vx;
			velxyz[index3 + 1] = vy;
			velxyz[index3 + 2] = vz;
			rotxyz[index3] = rotX;
			rotxyz[index3 + 1] = rotY;
			rotxyz[index3 + 2] = rotZ;
			itemStacks[i] = itemStack;
			this.despawnTime[i] = despawnTime;
			this.pickupCooldown[i] = pickupCooldown;
			if(world instanceof ServerWorld) {
				lastUpdates.add(storeSingle(i));
			}
			indices[size] = (short)i;
			reverseIndices[i] = (short)size;
			size++;
		}
	}

	public void remove(int i) {
		synchronized(this) {
			size--;
			// Put the stuff at the last index to the removed index:
			int ii = reverseIndices[i] & 0xffff;
			indices[ii] = indices[size];
			reverseIndices[indices[ii] & 0xffff] = (short)ii;
			itemStacks[i] = null; // Allow it to be garbage collected.
			if(world instanceof ServerWorld) {
				lastUpdates.add(new JsonInt(i));
			}
		}
	}

	public Vector3d getPosition(int index) {
		index *= 3;
		return new Vector3d(posxyz[index], posxyz[index+1], posxyz[index+2]);
	}

	public Vector3f getRotation(int index) {
		index *= 3;
		return new Vector3f(rotxyz[index], rotxyz[index+1], rotxyz[index+2]);
	}

	private void updateEnt(NormalChunk chunk, int index3, float deltaTime) {
		boolean startedInABlock = checkBlocks(chunk, index3);
		if(startedInABlock) {
			fixStuckInBlock(chunk, index3, deltaTime);
			return;
		}
		float drag = airDragFactor;
		float[] acceleration = new float[] {0, -gravity*deltaTime, 0};
		// Update gravity:
		for(int i = 0; i < 3; i++) { // Change one coordinate at a time and see if it would collide.
			double old = posxyz[index3 + i];
			posxyz[index3 + i] += velxyz[index3 + i]*deltaTime + acceleration[i]*deltaTime;
			if(checkBlocks(chunk, index3)) {
				posxyz[index3 + i] = old;
				velxyz[index3 + i] *= 0.5; // Half it to effectively perform asynchronous binary search for the collision boundary.
			}
			drag += 0.5; // TODO: Calculate drag from block properties and add buoyancy.
		}
		// Apply drag:
		for(int i = 0; i < 3; i++) {
			velxyz[index3 + i] += acceleration[i];
			velxyz[index3 + i] *= Math.max(0, 1 - drag*deltaTime);
		}
	}

	private void fixStuckInBlock(NormalChunk chunk, int index3, float deltaTime) {
		double x = posxyz[index3] - 0.5;
		double y = posxyz[index3+1] - 0.5;
		double z = posxyz[index3+2] - 0.5;
		int x0 = (int)Math.floor(x);
		int y0 = (int)Math.floor(y);
		int z0 = (int)Math.floor(z);
		// Find the closest non-solid block and go there:
		int closestDx = -1;
		int closestDy = -1;
		int closestDz = -1;
		double closestDist = Double.MAX_VALUE;
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					boolean isBlockSolid = checkBlock(chunk, index3, x0 + dx, y0 + dy, z0 + dz);
					if(!isBlockSolid) {
						double dist = (x0 + dx - x)*(x0 + dx - x) + (y0 + dy - y)*(y0 + dy - y) + (z0 + dz - z)*(z0 + dz - z);
						if(dist < closestDist) {
							closestDist = dist;
							closestDx = dx;
							closestDy = dy;
							closestDz = dz;
						}
					}
				}
			}
		}
		velxyz[index3] = 0;
		velxyz[index3+1] = 0;
		velxyz[index3+2] = 0;
		final double factor = 1;
		if(closestDist == Double.MAX_VALUE) {
			// Surrounded by solid blocks → move upwards
			velxyz[index3+1] = factor;
			posxyz[index3+1] += velxyz[index3+1]*deltaTime;
		} else {
			velxyz[index3] = factor*(x0 + closestDx - x);
			velxyz[index3+1] = factor*(y0 + closestDy - y);
			velxyz[index3+2] = factor*(z0 + closestDz - z);
			posxyz[index3] += velxyz[index3]*deltaTime;
			posxyz[index3+1] += velxyz[index3+1]*deltaTime;
			posxyz[index3+2] += velxyz[index3+2]*deltaTime;
		}
	}

	private boolean checkBlocks(NormalChunk chunk, int index3) {
		double x = posxyz[index3] - RADIUS;
		double y = posxyz[index3+1] - RADIUS;
		double z = posxyz[index3+2] - RADIUS;
		int x0 = (int)Math.floor(x);
		int y0 = (int)Math.floor(y);
		int z0 = (int)Math.floor(z);
		boolean isSolid = checkBlock(chunk, index3, x0, y0, z0);
		if (x - x0 + DIAMETER >= 1) {
			isSolid |= checkBlock(chunk, index3, x0+1, y0, z0);
			if (y - y0 + DIAMETER >= 1) {
				isSolid |= checkBlock(chunk, index3, x0, y0+1, z0);
				isSolid |= checkBlock(chunk, index3, x0+1, y0+1, z0);
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(chunk, index3, x0, y0, z0+1);
					isSolid |= checkBlock(chunk, index3, x0+1, y0, z0+1);
					isSolid |= checkBlock(chunk, index3, x0, y0+1, z0+1);
					isSolid |= checkBlock(chunk, index3, x0+1, y0+1, z0+1);
				}
			} else {
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(chunk, index3, x0, y0, z0+1);
					isSolid |= checkBlock(chunk, index3, x0+1, y0, z0+1);
				}
			}
		} else {
			if (y - y0 + DIAMETER >= 1) {
				isSolid |= checkBlock(chunk, index3, x0, y0+1, z0);
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(chunk, index3, x0, y0, z0+1);
					isSolid |= checkBlock(chunk, index3, x0, y0+1, z0+1);
				}
			} else {
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(chunk, index3, x0, y0, z0+1);
				}
			}
		}
		return isSolid;
	}

	private boolean checkBlock(NormalChunk chunk, int index3, int x, int y, int z) {
		// Transform to chunk-relative coordinates:
		int block = chunk.getBlockPossiblyOutside(x - chunk.wx, y - chunk.wy, z - chunk.wz);
		if (block == 0) return false;
		// Check if the item entity is inside the block:
		boolean isInside = true;
		if (Blocks.mode(block).changesHitbox()) {
			isInside = Blocks.mode(block).checkEntity(new Vector3d(posxyz[index3], posxyz[index3+1]-RADIUS, posxyz[index3+2]), RADIUS, DIAMETER, x, y, z, block);
		}
		return isInside && Blocks.solid(block);
	}
}
