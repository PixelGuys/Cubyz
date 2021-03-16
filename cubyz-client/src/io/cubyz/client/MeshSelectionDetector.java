package io.cubyz.client;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.items.Inventory;
import io.cubyz.math.CubyzMath;
import io.cubyz.util.ByteWrapper;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;

/**
 * A class used to determine what mesh the player is looking at using ray intersection.
 */

public class MeshSelectionDetector {
	protected Vector3f min = new Vector3f(), max = new Vector3f();
	protected Vector3f pos = new Vector3f(), dir = new Vector3f(); // Store player position at the time this was updated. Used to prevent bugs caused by asynchronous player movement.
	protected Object selectedSpatial; // Can be either a block or an entity.
	protected RayAabIntersection intersection = new RayAabIntersection();
	
	/**
	 * Return selected block instance
	 * @return selected block instance, or null if none.
	 */
	public Object getSelected() {
		return selectedSpatial;
	}
	/**
	 * Select the block or entity the player is looking at.
	 * @param chunks
	 * @param position player position
	 * @param dir camera direction
	 * @param localPlayer
	 * @param worldSize
	 * @param surface
	 */
	public void selectSpatial(NormalChunk[] chunks, Vector3f position, Vector3f direction, Player localPlayer, Surface surface) {
		pos.set(position);
		pos.y += Player.cameraHeight;
		dir.set(direction);
		
		// Test blocks:
		float closestDistance = 6f; // selection now limited
		Object newSpatial = null;
		intersection.set(pos.x, pos.y, pos.z, dir.x, dir.y, dir.z);
		for (NormalChunk ch : chunks) {
			min.set(ch.getMin(pos.x, pos.z, surface.getSizeX(), surface.getSizeZ()));
			max.set(ch.getMax(pos.x, pos.z, surface.getSizeX(), surface.getSizeZ()));
			// Check if the chunk is in view:
			if (!intersection.test(min.x-1, min.y-1, min.z-1, max.x+1, max.y+1, max.z+1)) // 1 is added/subtracted because chunk min-max don't align with the block min max.
				continue;
			synchronized (ch) {
				BlockInstance[] array = ch.getVisibles().array;
				for (int i = 0; i < ch.getVisibles().size; i++) {
					BlockInstance bi = array[i];
					if(bi == null)
						break;
					if(!bi.getBlock().isSolid())
						continue;
					min.set(new Vector3f(bi.getX(), bi.getY(), bi.getZ()));
					max.set(min);
					max.add(1, 1, 1); // scale, scale, scale
					// Because of the huge number of different BlockInstances that will be tested, it is more efficient to use RayAabIntersection and determine the distance separately:
					if (intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
						float distance;
						if(bi.getBlock().mode.changesHitbox()) {
							distance = bi.getBlock().mode.getRayIntersection(intersection, bi, min, max, pos);
						} else {
							distance = min.sub(pos).length();
						}
						if(distance < closestDistance) {
							closestDistance = distance;
							newSpatial = bi;
						}
					}
				}
			}
		}
		// Test entities:
		for(Entity ent : surface.getEntities()) {
			if(ent.getType().model != null) {
				float dist = ent.getType().model.getCollisionDistance(pos, dir, ent);
				if(dist < closestDistance) {
					closestDistance = dist;
					newSpatial = ent;
				}
			}
		}
		if(newSpatial == selectedSpatial)
			return;
		selectedSpatial = newSpatial;
	}
	
	/**
	 * Places a block in the world.
	 * @param inv
	 * @param selectedSlot
	 * @param surface
	 */
	public void placeBlock(Inventory inv, int selectedSlot, Surface surface) {
		if(selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
			BlockInstance bi = (BlockInstance)selectedSpatial;
			ByteWrapper data = new ByteWrapper(bi.getData());
			Vector3f relativePos = new Vector3f(pos);
			relativePos.sub(bi.x, bi.y, bi.z);
			Block b = inv.getBlock(selectedSlot);
			if (b != null) {
				Vector3i neighborDir = new Vector3i();
				// Check if stuff can be added to the block itself:
				if(b == bi.getBlock()) {
					if(b.mode.generateData(Cubyz.surface, bi.x, bi.y, bi.z, relativePos, dir, neighborDir, data, false)) {
						surface.updateBlockData(bi.x, bi.y, bi.z, data.data);
						inv.getStack(selectedSlot).add(-1);
						return;
					}
				}
				// Get the next neighbor:
				Vector3i neighbor = new Vector3i();
				getEmptyPlace(neighbor, neighborDir);
				relativePos.set(pos);
				relativePos.sub(neighbor.x, neighbor.y, neighbor.z);
				boolean dataOnlyUpdate = surface.getBlock(neighbor.x, neighbor.y, neighbor.z) == b;
				if(dataOnlyUpdate) {
					data.data = surface.getBlockData(neighbor.x, neighbor.y, neighbor.z);
					if(b.mode.generateData(Cubyz.surface, neighbor.x, neighbor.y, neighbor.z, relativePos, dir, neighborDir, data, false)) {
						surface.updateBlockData(neighbor.x, neighbor.y, neighbor.z, data.data);
						inv.getStack(selectedSlot).add(-1);
					}
				} else {
					if(b.mode.generateData(Cubyz.surface, neighbor.x, neighbor.y, neighbor.z, relativePos, dir, neighborDir, data, true)) {
						surface.placeBlock(neighbor.x, neighbor.y, neighbor.z, b, data.data);
						inv.getStack(selectedSlot).add(-1);
					}
				}
			}
		}
	}
	
	/**
	 * Returns the free block right next to the currently selected block.
	 * @param pos selected block position
	 * @param dir camera direction
	 */
	private void getEmptyPlace(Vector3i pos, Vector3i dir) {
		int dirX = CubyzMath.nonZeroSign(this.dir.x);
		int dirY = CubyzMath.nonZeroSign(this.dir.y);
		int dirZ = CubyzMath.nonZeroSign(this.dir.z);
		pos.set(((BlockInstance)selectedSpatial).x, ((BlockInstance)selectedSpatial).y, ((BlockInstance)selectedSpatial).z);
		pos.add(-dirX, 0, 0);
		dir.add(dirX, 0, 0);
		min.set(new Vector3f(pos.x, pos.y, pos.z));
		max.set(min);
		max.add(1, 1, 1); // scale, scale, scale
		if (!intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
			pos.add(dirX, -dirY, 0);
			dir.add(-dirX, dirY, 0);
			min.set(new Vector3f(pos.x, pos.y, pos.z));
			max.set(min);
			max.add(1, 1, 1); // scale, scale, scale
			if (!intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
				pos.add(0, dirY, -dirZ);
				dir.add(0, -dirY, dirZ);
			}
		}
	}
	
}
