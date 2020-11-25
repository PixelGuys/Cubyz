package io.cubyz.client;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;

/**
 * A class used to determine what mesh the player is looking at using ray intersection.
 */

public class MeshSelectionDetector {
	protected Vector3f min = new Vector3f(), max = new Vector3f();
	private int dirX, dirY, dirZ; // Used to prevent a block placement bug caused by asynchronous player position when selectSpatial and when getEmptyPlace are called.
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
	public void selectSpatial(NormalChunk[] chunks, Vector3f position, Vector3f dir, Player localPlayer, Surface surface) {
		// Test blocks:
		Vector3f transformedPosition = new Vector3f(position.x, position.y + Player.cameraHeight, position.z);
		dirX = (int)Math.signum(dir.x);
		dirY = (int)Math.signum(dir.y);
		dirZ = (int)Math.signum(dir.z);
		float closestDistance = 6f; // selection now limited
		Object newSpatial = null;
		intersection.set(transformedPosition.x, transformedPosition.y, transformedPosition.z, dir.x, dir.y, dir.z);
		for (NormalChunk ch : chunks) {
			min.set(ch.getMin(position.x, position.z, surface.getSizeX(), surface.getSizeZ()));
			max.set(ch.getMax(position.x, position.z, surface.getSizeX(), surface.getSizeZ()));
			// Check if the chunk is in view:
			if (!intersection.test(min.x-1, -1, min.z-1, max.x+1, 256, max.z+1)) // 1 is added/subtracted because chunk min-max don't align with the block min max.
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
					// Because of the huge number of different BlockInstances that will be tested, it is more efficient to use RayAabIntersection and determine the distance sperately:
					if (intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
						float distance;
						if(bi.getBlock().mode.changesHitbox()) {
							distance = bi.getBlock().mode.getRayIntersection(intersection, bi, min, max, transformedPosition);
						} else {
							distance = min.sub(transformedPosition).length();
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
				float dist = ent.getType().model.getCollisionDistance(position, dir, ent);
				if(dist < closestDistance) {
					closestDistance = dist;
					newSpatial = ent;
				}
			}
		}
		if(newSpatial == selectedSpatial)
			return;
		// Mark block spatials as selected/unselected if the selected mesh has changed:
		if(selectedSpatial != null) {
			synchronized(selectedSpatial) {
				if(selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
					for(BlockSpatial spatial : (BlockSpatial[])((BlockInstance)selectedSpatial).getSpatials(localPlayer, surface.getSizeX(), surface.getSizeZ(), null)) {
						spatial.setSelected(false);
					}
				}
			}
		}
		selectedSpatial = newSpatial;
		if(selectedSpatial != null) {
			synchronized(selectedSpatial) {
				if(selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
					for(BlockSpatial spatial : (BlockSpatial[])((BlockInstance)selectedSpatial).getSpatials(localPlayer, surface.getSizeX(), surface.getSizeZ(), null)) {
						spatial.setSelected(true);
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
	public void getEmptyPlace(Vector3i pos, Vector3i dir) {
		if(selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
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
	
}
