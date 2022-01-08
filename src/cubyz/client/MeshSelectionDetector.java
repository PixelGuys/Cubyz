package cubyz.client;

import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;

import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.math.CubyzMath;
import cubyz.world.NormalChunk;
import cubyz.world.World;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.Entity;
import cubyz.world.entity.Player;
import cubyz.world.items.Inventory;

/**
 * A class used to determine what mesh the player is looking at using ray intersection.
 */

public class MeshSelectionDetector {
	protected Vector3d min = new Vector3d(), max = new Vector3d();
	protected Vector3d pos = new Vector3d();
	protected Vector3f dir = new Vector3f(); // Store player position at the time this was updated. Used to prevent bugs caused by asynchronous player movement.
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
	 * @param world
	 */
	public void selectSpatial(NormalChunk[] chunks, Vector3d position, Vector3f direction, Player localPlayer, World world) {
		pos.set(position);
		pos.y += Player.cameraHeight;
		dir.set(direction);
		
		// Test blocks:
		double closestDistance = 6f; // selection now limited
		Object newSpatial = null;
		intersection.set(0, 0, 0, dir.x, dir.y, dir.z);
		for (NormalChunk ch : chunks) {
			min.set(ch.getMin());
			max.set(ch.getMax());
			// Sadly RayAabIntersection doesn't work with double, so we have to convert to relative distances before testing:
			min.sub(pos);
			max.sub(pos);
			Vector3f minf = new Vector3f((float)min.x, (float)min.y, (float)min.z);
			Vector3f maxf = new Vector3f((float)max.x, (float)max.y, (float)max.z);
			// Check if the chunk is in view:
			if (!intersection.test(minf.x-1, minf.y-1, minf.z-1, maxf.x+1, maxf.y+1, maxf.z+1)) // 1 is added/subtracted because chunk min-max don't align with the block min max.
				continue;
			synchronized (ch) {
				BlockInstance[] array = ch.getVisibles().array;
				for (int i = 0; i < ch.getVisibles().size; i++) {
					BlockInstance bi = array[i];
					if (bi == null)
						break;
					if (!Blocks.solid(bi.getBlock()))
						continue;
					min.set(new Vector3f(bi.x, bi.y, bi.z));
					min.sub(pos);
					max.set(min);
					max.add(1, 1, 1); // scale, scale, scale
					minf.set((float)min.x, (float)min.y, (float)min.z);
					maxf.set((float)max.x, (float)max.y, (float)max.z);
					// Because of the huge number of different BlockInstances that will be tested, it is more efficient to use RayAabIntersection and determine the distance separately:
					if (intersection.test(minf.x, minf.y, minf.z, maxf.x, maxf.y, maxf.z)) {
						double distance;
						if (Blocks.mode(bi.getBlock()).changesHitbox()) {
							distance = Blocks.mode(bi.getBlock()).getRayIntersection(intersection, bi, minf, maxf, new Vector3f());
						} else {
							distance = minf.length();
						}
						if (distance < closestDistance) {
							closestDistance = distance;
							newSpatial = bi;
						}
					}
				}
			}
		}
		// Test entities:
		for(Entity ent : world.getEntities()) {
			if (ent.getType().model != null) {
				double dist = ent.getType().model.getCollisionDistance(pos, dir, ent);
				if (dist < closestDistance) {
					closestDistance = dist;
					newSpatial = ent;
				}
			}
		}
		if (newSpatial == selectedSpatial)
			return;
		selectedSpatial = newSpatial;
	}
	
	/**
	 * Places a block in the world.
	 * @param inv
	 * @param selectedSlot
	 * @param world
	 */
	public void placeBlock(Inventory inv, int selectedSlot, World world) {
		if (selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
			BlockInstance bi = (BlockInstance)selectedSpatial;
			IntWrapper block = new IntWrapper(bi.getBlock());
			Vector3d relativePos = new Vector3d(pos);
			relativePos.sub(bi.x, bi.y, bi.z);
			int b = inv.getBlock(selectedSlot);
			if (b != 0) {
				Vector3i neighborDir = new Vector3i();
				// Check if stuff can be added to the block itself:
				if (b == bi.getBlock()) {
					if (Blocks.mode(b).generateData(Cubyz.world, bi.x, bi.y, bi.z, relativePos, dir, neighborDir, block, false)) {
						world.updateBlock(bi.x, bi.y, bi.z, block.data);
						inv.getStack(selectedSlot).add(-1);
						return;
					}
				}
				// Get the next neighbor:
				Vector3i neighbor = new Vector3i();
				getEmptyPlace(neighbor, neighborDir);
				relativePos.set(pos);
				relativePos.sub(neighbor.x, neighbor.y, neighbor.z);
				boolean dataOnlyUpdate = world.getBlock(neighbor.x, neighbor.y, neighbor.z) == b;
				if (dataOnlyUpdate) {
					block.data = world.getBlock(neighbor.x, neighbor.y, neighbor.z);
					if (Blocks.mode(b).generateData(Cubyz.world, neighbor.x, neighbor.y, neighbor.z, relativePos, dir, neighborDir, block, false)) {
						world.updateBlock(neighbor.x, neighbor.y, neighbor.z, block.data);
						inv.getStack(selectedSlot).add(-1);
					}
				} else {
					// Check if the block can actually be placed at that point. There might be entities or other blocks in the way.
					if (Blocks.solid(world.getBlock(neighbor.x, neighbor.y, neighbor.z)))
						return;
					for(Entity ent : world.getEntities()) {
						Vector3d pos = ent.getPosition();
						// Check if the block is inside:
						if (neighbor.x < pos.x + ent.width && neighbor.x + 1 > pos.x - ent.width
						        && neighbor.z < pos.z + ent.width && neighbor.z + 1 > pos.z - ent.width
						        && neighbor.y < pos.y + ent.height && neighbor.y + 1 > pos.y)
							return;
					}
					block.data = b;
					if (Blocks.mode(b).generateData(Cubyz.world, neighbor.x, neighbor.y, neighbor.z, relativePos, dir, neighborDir, block, true)) {
						world.placeBlock(neighbor.x, neighbor.y, neighbor.z, block.data);
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
		min.set(pos.x, pos.y, pos.z).sub(this.pos);
		max.set(min);
		max.add(1, 1, 1); // scale, scale, scale
		if (!intersection.test((float)min.x, (float)min.y, (float)min.z, (float)max.x, (float)max.y, (float)max.z)) {
			pos.add(dirX, -dirY, 0);
			dir.add(-dirX, dirY, 0);
			min.set(pos.x, pos.y, pos.z).sub(this.pos);
			max.set(min);
			max.add(1, 1, 1); // scale, scale, scale
			if (!intersection.test((float)min.x, (float)min.y, (float)min.z, (float)max.x, (float)max.y, (float)max.z)) {
				pos.add(0, dirY, -dirZ);
				dir.add(0, -dirY, dirZ);
			}
		}
	}
	
}
