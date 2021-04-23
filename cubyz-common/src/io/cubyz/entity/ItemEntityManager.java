package io.cubyz.entity;

import java.util.Arrays;

import org.joml.Vector3f;

import io.cubyz.Logger;
import io.cubyz.blocks.Block;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.math.Bits;
import io.cubyz.save.Palette;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;

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
	
	public float[] posxyz;
	public float[] velxyz;
	public float[] rotxyz;
	public ItemStack[] itemStacks;
	public int[] despawnTime;

	public final NormalChunk chunk;
	private final Surface surface;
	private float gravity;
	public int size;
	private int capacity;
	
	public ItemEntityManager(Surface surface, NormalChunk chunk, int minCapacity) {
		// Always use a multiple of 64 as the capacity.
		capacity = (minCapacity+63) & ~63;
		posxyz = new float[3 * capacity];
		velxyz = new float[3 * capacity];
		rotxyz = new float[3 * capacity];
		itemStacks = new ItemStack[capacity];
		despawnTime = new int[capacity];
		
		this.surface = surface;
		this.chunk = chunk;
		gravity = surface.getStellarTorus().getGravity();
	}
	
	public ItemEntityManager(Surface surface, NormalChunk chunk, byte[] data, Palette<Item> itemPalette) {
		// Read the length:
		int index = 0;
		int length = Bits.getInt(data, index);
		index += 4;
		// Check if the length is right:
		if(data.length-index != length*4*9) {
			Logger.warning("Save file is corrupted. Skipping item entites for chunk "+chunk.getWorldX()+" "+chunk.getWorldY()+" "+chunk.getWorldZ());
			length = 0;
		}
		// Init variables:
		capacity = (length+63) & ~63;
		posxyz = new float[3 * capacity];
		velxyz = new float[3 * capacity];
		rotxyz = new float[3 * capacity];
		itemStacks = new ItemStack[capacity];
		despawnTime = new int[capacity];
		
		this.surface = surface;
		this.chunk = chunk;
		gravity = surface.getStellarTorus().getGravity();
		// Read the data:
		for(int i = 0; i < length; i++) {
			float x = Bits.getFloat(data, index);
			index += 4;
			float y = Bits.getFloat(data, index);
			index += 4;
			float z = Bits.getFloat(data, index);
			index += 4;
			float vx = Bits.getFloat(data, index);
			index += 4;
			float vy = Bits.getFloat(data, index);
			index += 4;
			float vz = Bits.getFloat(data, index);
			index += 4;
			Item item = itemPalette.getElement(Bits.getInt(data, index));
			index += 4;
			int itemAmount = Bits.getInt(data, index);
			index += 4;
			int despawnTime = Bits.getInt(data, index);
			index += 4;
			add(x, y, z, vx, vy, vz, new ItemStack(item, itemAmount), despawnTime);
		}
	}
	
	public byte[] store(Palette<Item> itemPalette) {
		byte[] data = new byte[size*4*9 + 4];
		int index = 0;
		Bits.putInt(data, 0, size);
		index += 4;
		for(int i = 0; i < size; i++) {
			int i3 = i*3;
			Bits.putFloat(data, index, posxyz[i3]);
			index += 4;
			Bits.putFloat(data, index, posxyz[i3+1]);
			index += 4;
			Bits.putFloat(data, index, posxyz[i3+2]);
			index += 4;
			Bits.putFloat(data, index, velxyz[i3]);
			index += 4;
			Bits.putFloat(data, index, velxyz[i3+1]);
			index += 4;
			Bits.putFloat(data, index, velxyz[i3+2]);
			index += 4;
			Bits.putInt(data, index, itemPalette.getIndex(itemStacks[i].getItem()));
			index += 4;
			Bits.putInt(data, index, itemStacks[i].getAmount());
			index += 4;
			Bits.putInt(data, index, despawnTime[i]);
			index += 4;
		}
		return data;
	}
	
	public void update() {
		for(int i = 0; i < size; i++) {
			int index3 = i*3;
			// Update gravity:
			velxyz[index3+1] -= gravity;
			// Check collision with blocks:
			checkBlocks(index3);
			// Update position:
			posxyz[index3] += velxyz[index3];
			posxyz[index3+1] += velxyz[index3+1];
			posxyz[index3+2] += velxyz[index3+2];
			// Check if it's still inside this chunk:
			if(!chunk.isInside(posxyz[index3], posxyz[index3 + 1], posxyz[index3 + 2])) {
				// Move it to another manager:
				ChunkEntityManager other = surface.getEntityManagerAt(((int)posxyz[index3]) & ~NormalChunk.chunkMask, ((int)posxyz[index3+1]) & ~NormalChunk.chunkMask, ((int)posxyz[index3+2]) & ~NormalChunk.chunkMask);
				if(other == null) {
					// TODO: Append it to the right file.
				} else {
					other.itemEntityManager.add(posxyz[index3], posxyz[index3+1], posxyz[index3+2], velxyz[index3], velxyz[index3+1], velxyz[index3+2], rotxyz[index3], rotxyz[index3+1], rotxyz[index3+2], itemStacks[i], despawnTime[i]);
				}
					remove(i);
				i--;
				continue;
			}
			despawnTime[i]--;
			if(despawnTime[i] < 0) {
				remove(i);
				i--;
			}
		}
	}
	
	public void checkEntity(Entity ent) {
		for(int i = 0; i < size; i++) {
			int index3 = 3*i;
			if(Math.abs(ent.position.x - posxyz[index3]) < ent.width + pickupRange && Math.abs(ent.position.y + ent.height/2 - posxyz[index3+1]) < ent.height + pickupRange && Math.abs(ent.position.z - posxyz[index3+2]) < ent.width + pickupRange) {
				int newAmount = ent.getInventory().addItem(itemStacks[i].getItem(), itemStacks[i].getAmount());
				if(newAmount != 0) {
					itemStacks[i].setAmount(newAmount);
				} else {
					remove(i);
					i--;
					continue;
				}
			}
		}
	}
	
	public void add(int x, int y, int z, float vx, float vy, float vz, ItemStack itemStack, int despawnTime) {
		add(x + (float)Math.random(), y + (float)Math.random(), z + (float)Math.random(), vx, vy, vz, (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), itemStack, despawnTime);
	}
	
	public void add(float x, float y, float z, float vx, float vy, float vz, ItemStack itemStack, int despawnTime) {
		add(x, y, z, vx, vy, vz, (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), (float)(2*Math.random()*Math.PI), itemStack, despawnTime);
	}
	
	public void add(float x, float y, float z, float vx, float vy, float vz, float rotX, float rotY, float rotZ, ItemStack itemStack, int despawnTime) {
		if(size == capacity) {
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
	}
	
	public Vector3f getPosition(int index) {
		index *= 3;
		return new Vector3f(posxyz[index], posxyz[index+1], posxyz[index+2]);
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
	}
	
	private void checkBlocks(int index3) {
		float x = posxyz[index3] - radius;
		float y = posxyz[index3+1] - radius;
		float z = posxyz[index3+2] - radius;
		int x0 = (int)x;
		int y0 = (int)y;
		int z0 = (int)z;
		checkBlock(index3, x0, y0, z0);
		if(x - x0 + diameter >= 1) {
			checkBlock(index3, x0+1, y0, z0);
			if(y - y0 + diameter >= 1) {
				checkBlock(index3, x0, y0+1, z0);
				checkBlock(index3, x0+1, y0+1, z0);
				if(z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
					checkBlock(index3, x0+1, y0, z0+1);
					checkBlock(index3, x0, y0+1, z0+1);
					checkBlock(index3, x0+1, y0+1, z0+1);
				}
			} else {
				if(z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
					checkBlock(index3, x0+1, y0, z0+1);
				}
			}
		} else {
			if(y - y0 + diameter >= 1) {
				checkBlock(index3, x0, y0+1, z0);
				if(z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
					checkBlock(index3, x0, y0+1, z0+1);
				}
			} else {
				if(z - z0 + diameter >= 1) {
					checkBlock(index3, x0, y0, z0+1);
				}
			}
		}
	}
	
	private void checkBlock(int index3, int x, int y, int z) {
		// Transform to chunk-relative coordinates:
		x -= chunk.getWorldX();
		y -= chunk.getWorldY();
		z -= chunk.getWorldZ();
		Block block = chunk.getBlockUnbound(x, y, z);
		if(block == null) return;
		byte data = chunk.getDataUnbound(x, y, z);
		// Check if the item entity is inside the block:
		boolean isInside = true;
		if(block.mode.changesHitbox()) {
			isInside = block.mode.checkEntity(new Vector3f(posxyz[index3], posxyz[index3+1]+radius, posxyz[index3+2]), radius, diameter, x, y, z, data);
		}
		if(isInside) {
			if(block.isSolid()) {
				velxyz[index3] = velxyz[index3+1] = velxyz[index3+2] = 0;
				// TODO: Prevent item entities from getting stuck in a block.
			} else {
				// TODO: Add buoyancy and drag.
			}
		}
	}
}
