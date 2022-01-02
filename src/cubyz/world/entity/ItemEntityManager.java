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
	public static final float radius = 0.1f;
	/**Diameter of all item entities hitboxes as a unit sphere of the max-norm (cube).*/
	public static final float diameter = 2*radius;
	
	public static final float pickupRange = 1;
	
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
	private float gravity;
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
	}
	
	public ItemEntityManager(World world, NormalChunk chunk, byte[] data, Palette<Item> itemPalette) {
		// Read the length:
		int index = 0;
		int length = Bits.getInt(data, index);
		index += 4;
		// Check if the length is right:
		if (data.length-index != length*(4*3 + 8*6)) {
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
		
		this.world = world;
		this.chunk = chunk;
		gravity = World.GRAVITY;
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
			int index3 = i*3;
			// Update gravity:
			velxyz[index3+1] -= gravity*deltaTime;
			// Check collision with blocks:
			checkBlocks(index3);
			// Update position:
			posxyz[index3] += velxyz[index3]*deltaTime;
			posxyz[index3+1] += velxyz[index3+1]*deltaTime;
			posxyz[index3+2] += velxyz[index3+2]*deltaTime;
			// Check if it's still inside this chunk:
			if (!chunk.isInside(posxyz[index3], posxyz[index3 + 1], posxyz[index3 + 2])) {
				// Move it to another manager:
				ChunkEntityManager other = world.getEntityManagerAt(((int)posxyz[index3]) & ~Chunk.chunkMask, ((int)posxyz[index3+1]) & ~Chunk.chunkMask, ((int)posxyz[index3+2]) & ~Chunk.chunkMask);
				if (other == null) {
					// TODO: Append it to the right file.
					posxyz[index3] -= velxyz[index3]*deltaTime;
					posxyz[index3+1] -= velxyz[index3+1]*deltaTime;
					posxyz[index3+2] -= velxyz[index3+2]*deltaTime;
				} else if (other.itemEntityManager != this) {
					other.itemEntityManager.add(posxyz[index3], posxyz[index3+1], posxyz[index3+2], velxyz[index3], velxyz[index3+1], velxyz[index3+2], rotxyz[index3], rotxyz[index3+1], rotxyz[index3+2], itemStacks[i], despawnTime[i], pickupCooldown[i]);
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
			int index3 = 3*i;
			if (pickupCooldown[i] >= 0) continue; // Item cannot be picked up yet.
			if (Math.abs(ent.position.x - posxyz[index3]) < ent.width + pickupRange && Math.abs(ent.position.y + ent.height/2 - posxyz[index3+1]) < ent.height + pickupRange && Math.abs(ent.position.z - posxyz[index3+2]) < ent.width + pickupRange) {
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
		add(x + Math.random(), y + Math.random(), z + Math.random(), vx, vy, vz, (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), itemStack, despawnTime, 0);
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
	
	private void checkBlocks(int index3) {
		double x = posxyz[index3] - radius;
		double y = posxyz[index3+1] - radius;
		double z = posxyz[index3+2] - radius;
		int x0 = (int)x;
		int y0 = (int)y;
		int z0 = (int)z;
		checkBlock(index3, x0, y0, z0);
		if (x - x0 + diameter >= 1) {
			checkBlock(index3, x0+1, y0, z0);
			if (y - y0 + diameter >= 1) {
				checkBlock(index3, x0, y0+1, z0);
				checkBlock(index3, x0+1, y0+1, z0);
				if (z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
					checkBlock(index3, x0+1, y0, z0+1);
					checkBlock(index3, x0, y0+1, z0+1);
					checkBlock(index3, x0+1, y0+1, z0+1);
				}
			} else {
				if (z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
					checkBlock(index3, x0+1, y0, z0+1);
				}
			}
		} else {
			if (y - y0 + diameter >= 1) {
				checkBlock(index3, x0, y0+1, z0);
				if (z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
					checkBlock(index3, x0, y0+1, z0+1);
				}
			} else {
				if (z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
				}
			}
		}
	}
	
	private void checkBlock(int index3, int x, int y, int z) {
		// Transform to chunk-relative coordinates:
		x -= chunk.wx;
		y -= chunk.wy;
		z -= chunk.wz;
		int block = chunk.getBlockPossiblyOutside(x, y, z);
		if (block == 0) return;
		// Check if the item entity is inside the block:
		boolean isInside = true;
		if (Blocks.mode(block).changesHitbox()) {
			isInside = Blocks.mode(block).checkEntity(new Vector3d(posxyz[index3], posxyz[index3+1]+radius, posxyz[index3+2]), radius, diameter, x, y, z, block);
		}
		if (isInside) {
			if (Blocks.solid(block)) {
				velxyz[index3] = velxyz[index3+1] = velxyz[index3+2] = 0;
				// TODO: Prevent item entities from getting stuck in a block.
			} else {
				// TODO: Add buoyancy and drag.
			}
		}
	}
}
