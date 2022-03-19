package cubyz.world.entity;

import java.util.Arrays;

import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.Chunk;
import cubyz.world.NormalChunk;
import cubyz.world.World;
import cubyz.world.blocks.Blocks;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;
import cubyz.world.save.Palette;

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

	private static final int capacityIncrease = 64;

	public double[] posxyz;
	public double[] velxyz;
	public float[] rotxyz;
	public ItemStack[] itemStacks;
	public int[] despawnTime;
	/** How long the item should stay on the ground before getting picked up again. */
	public int[] pickupCooldown;

	public final NormalChunk chunk;
	private final World world;
	private final float gravity;
	private final float airDragFactor;
	public int size;
	private int capacity;

	public ItemEntityManager(World world, NormalChunk chunk, int minCapacity) {
		// Always use a multiple of 64 as the capacity.
		capacity = (minCapacity+63) & ~63;
		posxyz = new double[3 * capacity];
		velxyz = new double[3 * capacity];
		rotxyz = new float[3 * capacity];
		itemStacks = new ItemStack[capacity];
		despawnTime = new int[capacity];
		pickupCooldown = new int[capacity];

		this.world = world;
		this.chunk = chunk;
		gravity = World.GRAVITY;
		// Assuming linear drag → air is a viscous fluid :D
		// a = d*v → d = a/v
		// a - acceleration(gravity), d - airDragFactor, v - MAX_AIR_SPEED_GRAVITY
		airDragFactor = gravity/MAX_AIR_SPEED_GRAVITY;
	}


	void loadFromByteArray(byte[] data, int len, Palette<Item> itemPalette) {
		// Read the length:
		int index = 0;
		int length = Bits.getInt(data, index);
		index += 4;
		// Check if the length is right:
		if (len - index < length*(4*3 + 8*6)) {
			Logger.warning("Save file is corrupted. Skipping item entites for chunk "+chunk.wx+" "+chunk.wy+" "+chunk.wz);
			length = 0;
		}
		// Init variables:
		capacity = (length+63) & ~63;
		posxyz = new double[3 * capacity];
		velxyz = new double[3 * capacity];
		rotxyz = new float[3 * capacity];
		itemStacks = new ItemStack[capacity];
		despawnTime = new int[capacity];
		pickupCooldown = new int[capacity];

		// Read the data:
		for(int i = 0; i < length; i++) {
			double x = Bits.getDouble(data, index);
			index += 8;
			double y = Bits.getDouble(data, index);
			index += 8;
			double z = Bits.getDouble(data, index);
			index += 8;
			double vx = Bits.getDouble(data, index);
			index += 8;
			double vy = Bits.getDouble(data, index);
			index += 8;
			double vz = Bits.getDouble(data, index);
			index += 8;
			Item item = itemPalette.getElement(Bits.getInt(data, index));
			index += 4;
			int itemAmount = Bits.getInt(data, index);
			index += 4;
			int despawnTime = Bits.getInt(data, index);
			index += 4;
			add(x, y, z, vx, vy, vz, new ItemStack(item, itemAmount), despawnTime, 0);
		}
	}

	public byte[] store(Palette<Item> itemPalette) {
		byte[] data = new byte[size*(4*3 + 8*6) + 4];
		int index = 0;
		Bits.putInt(data, 0, size);
		index += 4;
		for(int i = 0; i < size; i++) {
			int i3 = i*3;
			Bits.putDouble(data, index, posxyz[i3]);
			index += 8;
			Bits.putDouble(data, index, posxyz[i3+1]);
			index += 8;
			Bits.putDouble(data, index, posxyz[i3+2]);
			index += 8;
			Bits.putDouble(data, index, velxyz[i3]);
			index += 8;
			Bits.putDouble(data, index, velxyz[i3+1]);
			index += 8;
			Bits.putDouble(data, index, velxyz[i3+2]);
			index += 8;
			Bits.putInt(data, index, itemPalette.getIndex(itemStacks[i].getItem()));
			index += 4;
			Bits.putInt(data, index, itemStacks[i].getAmount());
			index += 4;
			Bits.putInt(data, index, despawnTime[i]);
			index += 4;
		}
		return data;
	}

	public void update(float deltaTime) {
		for(int i = 0; i < size; i++) {
			int i3 = i*3;
			// Update gravity:
			velxyz[i3 + 1] = velxyz[i3+1] - gravity*deltaTime;
			// Check collision with blocks:
			updateEnt(i3, deltaTime);
			// Check if it's still inside this chunk:
			if (!chunk.isInside(posxyz[i3], posxyz[i3 + 1], posxyz[i3 + 2])) {
				// Move it to another manager:
				ChunkEntityManager other = world.getEntityManagerAt(((int)posxyz[i3]) & ~Chunk.chunkMask, ((int)posxyz[i3 + 1]) & ~Chunk.chunkMask, ((int)posxyz[i3 + 2]) & ~Chunk.chunkMask);
				if (other == null) {
					// TODO: Append it to the right file.
					posxyz[i3] -= velxyz[i3]*deltaTime;
					posxyz[i3 + 1] -= velxyz[i3 + 1]*deltaTime;
					posxyz[i3 + 2] -= velxyz[i3 + 2]*deltaTime;
				} else if (other.itemEntityManager != this) {
					other.itemEntityManager.add(posxyz[i3], posxyz[i3 + 1], posxyz[i3 + 2], velxyz[i3], velxyz[i3 + 1], velxyz[i3 + 2], rotxyz[i3], rotxyz[i3 + 1], rotxyz[i3 + 2], itemStacks[i], despawnTime[i], pickupCooldown[i]);
					remove(i);
					i--;
				}
				continue;
			}
			pickupCooldown[i]--;
			despawnTime[i]--;
			if (despawnTime[i] < 0) {
				remove(i);
				i--;
			}
		}
	}

	public void checkEntity(Entity ent) {
		for(int i = 0; i < size; i++) {
			int i3 = 3*i;
			if (pickupCooldown[i] >= 0) continue; // Item cannot be picked up yet.
			if (Math.abs(ent.position.x - posxyz[i3]) < ent.width + PICKUP_RANGE && Math.abs(ent.position.y + ent.height/2 - posxyz[i3 + 1]) < ent.height + PICKUP_RANGE && Math.abs(ent.position.z - posxyz[i3 + 2]) < ent.width + PICKUP_RANGE) {
				int newAmount = ent.getInventory().addItem(itemStacks[i].getItem(), itemStacks[i].getAmount());
				if (newAmount != 0) {
					itemStacks[i].setAmount(newAmount);
				} else {
					remove(i);
					i--;
					continue;
				}
			}
		}
	}

	public void add(int x, int y, int z, double vx, double vy, double vz, ItemStack itemStack, int despawnTime) {
		add(x + RADIUS + (1 - DIAMETER)*Math.random(), y + RADIUS + (1 - DIAMETER)*Math.random(), z + RADIUS + (1 - DIAMETER)*Math.random(), vx, vy, vz, (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), itemStack, despawnTime, 0);
	}

	public void add(double x, double y, double z, double vx, double vy, double vz, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		add(x, y, z, vx, vy, vz, (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), itemStack, despawnTime, pickupCooldown);
	}

	public void add(double x, double y, double z, double vx, double vy, double vz, float rotX, float rotY, float rotZ, ItemStack itemStack, int despawnTime, int pickupCooldown) {
		if (size == capacity) {
			increaseCapacity();
		}
		int index3 = 3 * size;
		posxyz[index3] = x;
		posxyz[index3+1] = y;
		posxyz[index3+2] = z;
		velxyz[index3] = vx;
		velxyz[index3+1] = vy;
		velxyz[index3+2] = vz;
		rotxyz[index3] = rotX;
		rotxyz[index3+1] = rotY;
		rotxyz[index3+2] = rotZ;
		itemStacks[size] = itemStack;
		this.despawnTime[size] = despawnTime;
		this.pickupCooldown[size] = pickupCooldown;
		size++;
	}

	public void remove(int index) {
		size--;
		// Put the stuff at the last index to the removed index:
		int index3 = 3*index;
		int size3 = size*3;
		posxyz[index3] = posxyz[size3];
		posxyz[index3+1] = posxyz[size3+1];
		posxyz[index3+2] = posxyz[size3+2];
		velxyz[index3] = velxyz[size3];
		velxyz[index3+1] = velxyz[size3+1];
		velxyz[index3+2] = velxyz[size3+2];
		rotxyz[index3] = rotxyz[size3];
		rotxyz[index3+1] = rotxyz[size3+1];
		rotxyz[index3+2] = rotxyz[size3+2];
		itemStacks[index] = itemStacks[size];
		itemStacks[size] = null; // Allow it to be garbage collected.
		despawnTime[index] = despawnTime[size];
		pickupCooldown[index] = pickupCooldown[size];
	}

	public Vector3d getPosition(int index) {
		index *= 3;
		return new Vector3d(posxyz[index], posxyz[index+1], posxyz[index+2]);
	}

	public Vector3f getRotation(int index) {
		index *= 3;
		return new Vector3f(rotxyz[index], rotxyz[index+1], rotxyz[index+2]);
	}

	private void increaseCapacity() {
		capacity += capacityIncrease;
		posxyz = Arrays.copyOf(posxyz, capacity*3);
		velxyz = Arrays.copyOf(velxyz, capacity*3);
		rotxyz = Arrays.copyOf(rotxyz, capacity*3);
		itemStacks = Arrays.copyOf(itemStacks, capacity);
		despawnTime = Arrays.copyOf(despawnTime, capacity);
		pickupCooldown = Arrays.copyOf(pickupCooldown, capacity);
	}

	private void updateEnt(int index3, float deltaTime) {
		deltaTime *= 0.1f;
		boolean startedInABlock = checkBlocks(index3);
		if(startedInABlock) {
			fixStuckInBlock(index3, deltaTime);
			return;
		}
		float drag = airDragFactor;
		for(int i = 0; i < 3; i++) { // Change one coordinate at a time and see if it would collide.
			double old = posxyz[index3 + i];
			posxyz[index3 + i] += velxyz[index3 + i]*deltaTime;
			if(checkBlocks(index3)) {
				posxyz[index3 + i] = old;
				velxyz[index3 + i] *= 0.5; // Half it to effectively perform asynchronous binary search for the collision boundary.
			}
			drag += 0.5; // TODO: Calculate drag from block properties and add buoyancy.
		}
		// Apply drag:
		for(int i = 0; i < 3; i++) {
			velxyz[index3 + i] *= Math.max(0, 1 - drag*deltaTime);
		}
	}

	private void fixStuckInBlock(int index3, float deltaTime) {
		double x = posxyz[index3] - 0.5;
		double y = posxyz[index3+1] - 0.5;
		double z = posxyz[index3+2] - 0.5;
		int x0 = (int)x;
		int y0 = (int)y;
		int z0 = (int)z;
		// Find the closest non-solid block and go there:
		int closestDx = -1;
		int closestDy = -1;
		int closestDz = -1;
		double closestDist = Double.MAX_VALUE;
		for(int dx = 0; dx <= 1; dx++) {
			for(int dy = 0; dy <= 1; dy++) {
				for(int dz = 0; dz <= 1; dz++) {
					boolean isBlockSolid = checkBlock(index3, x0 + dx, y0 + dy, z0 + dz);
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

	private boolean checkBlocks(int index3) {
		double x = posxyz[index3] - RADIUS;
		double y = posxyz[index3+1] - RADIUS;
		double z = posxyz[index3+2] - RADIUS;
		int x0 = (int)x;
		int y0 = (int)y;
		int z0 = (int)z;
		boolean isSolid = checkBlock(index3, x0, y0, z0);
		if (x - x0 + DIAMETER >= 1) {
			isSolid |= checkBlock(index3, x0+1, y0, z0);
			if (y - y0 + DIAMETER >= 1) {
				isSolid |= checkBlock(index3, x0, y0+1, z0);
				isSolid |= checkBlock(index3, x0+1, y0+1, z0);
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(index3, x0, y0, z0+1);
					isSolid |= checkBlock(index3, x0+1, y0, z0+1);
					isSolid |= checkBlock(index3, x0, y0+1, z0+1);
					isSolid |= checkBlock(index3, x0+1, y0+1, z0+1);
				}
			} else {
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(index3, x0, y0, z0+1);
					isSolid |= checkBlock(index3, x0+1, y0, z0+1);
				}
			}
		} else {
			if (y - y0 + DIAMETER >= 1) {
				isSolid |= checkBlock(index3, x0, y0+1, z0);
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(index3, x0, y0, z0+1);
					isSolid |= checkBlock(index3, x0, y0+1, z0+1);
				}
			} else {
				if (z - z0 + DIAMETER >= 1) {
					isSolid |= checkBlock(index3, x0, y0, z0+1);
				}
			}
		}
		return isSolid;
	}

	private boolean checkBlock(int index3, int x, int y, int z) {
		// Transform to chunk-relative coordinates:
		x -= chunk.wx;
		y -= chunk.wy;
		z -= chunk.wz;
		int block = chunk.getBlockPossiblyOutside(x, y, z);
		if (block == 0) return false;
		// Check if the item entity is inside the block:
		boolean isInside = true;
		if (Blocks.mode(block).changesHitbox()) {
			isInside = Blocks.mode(block).checkEntity(new Vector3d(posxyz[index3], posxyz[index3+1]+RADIUS, posxyz[index3+2]), RADIUS, DIAMETER, x, y, z, block);
		}
		if (isInside) {
			if (Blocks.solid(block)) {
				return true;
			}
		}
		return false;
	}
}
