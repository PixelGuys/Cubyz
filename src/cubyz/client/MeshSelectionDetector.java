package cubyz.client;

import cubyz.world.ClientWorld;
import cubyz.world.items.ItemStack;
import org.joml.RayAabIntersection;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3i;

import cubyz.utils.datastructures.IntWrapper;
import cubyz.utils.math.CubyzMath;
import cubyz.world.World;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.Entity;
import cubyz.world.entity.Player;

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
	 * @param position player position
	 * @param direction camera direction
	 * @param world
	 */
	public void selectSpatial(Vector3d position, Vector3f direction, ClientWorld world) {
		pos.set(position);
		pos.y += Player.cameraHeight;
		dir.set(direction);

		intersection.set(0, 0, 0, dir.x, dir.y, dir.z);
		
		// Test blocks:
		double closestDistance = 6.0; // selection now limited
		// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
		int stepX = (int)Math.signum(dir.x);
		int stepY = (int)Math.signum(dir.y);
		int stepZ = (int)Math.signum(dir.z);
		double tDeltaX = Math.abs(1/dir.x);
		double tDeltaY = Math.abs(1/dir.y);
		double tDeltaZ = Math.abs(1/dir.z);
		double tMaxX = (Math.floor(pos.x) - pos.x)/dir.x;
		double tMaxY = (Math.floor(pos.y) - pos.y)/dir.y;
		double tMaxZ = (Math.floor(pos.z) - pos.z)/dir.z;
		tMaxX = Math.max(tMaxX, tMaxX + tDeltaX*stepX);
		tMaxY = Math.max(tMaxY, tMaxY + tDeltaY*stepY);
		tMaxZ = Math.max(tMaxZ, tMaxZ + tDeltaZ*stepZ);
		if(dir.x == 0) tMaxX = Double.POSITIVE_INFINITY;
		if(dir.y == 0) tMaxY = Double.POSITIVE_INFINITY;
		if(dir.z == 0) tMaxZ = Double.POSITIVE_INFINITY;
		int x = (int)Math.floor(pos.x);
		int y = (int)Math.floor(pos.y);
		int z = (int)Math.floor(pos.z);

		double total_tMax = 0;

		while(total_tMax < closestDistance) {
			int block = world.getBlock(x, y, z);
			if (Blocks.mode(block).changesHitbox()) {
				Vector3d min = new Vector3d(x, y, z);
				min.sub(pos);
				Vector3d max = new Vector3d(min);
				max.add(1, 1, 1);
				Vector3f minf = new Vector3f((float)min.x, (float)min.y, (float)min.z);
				Vector3f maxf = new Vector3f((float)max.x, (float)max.y, (float)max.z);
				double distance = Blocks.mode(block).getRayIntersection(intersection, block, minf, maxf, new Vector3f());
				if(distance > closestDistance) {
					block = 0;
				}
			}
			if(block != 0) break;
			if(tMaxX < tMaxY) {
				if(tMaxX < tMaxZ) {
					x = x + stepX;
					total_tMax = tMaxX;
					tMaxX = tMaxX + tDeltaX;
				} else {
					z = z + stepZ;
					total_tMax = tMaxZ;
					tMaxZ = tMaxZ + tDeltaZ;
				}
			} else {
				if(tMaxY < tMaxZ) {
					y = y + stepY;
					total_tMax = tMaxY;
					tMaxY = tMaxY + tDeltaY;
				} else {
					z = z + stepZ;
					total_tMax = tMaxZ;
					tMaxZ = tMaxZ + tDeltaZ;
				}
			}
		}

		Object newSpatial = null;
		if(total_tMax < closestDistance) {
			newSpatial = world.getBlockInstance(x, y, z);
		}
		// Test entities:
		for(Entity ent : world.getEntities()) {
			// TODO!
		}
		if (newSpatial == selectedSpatial)
			return;
		selectedSpatial = newSpatial;
	}
	
	/**
	 * Places a block in the world.
	 * @param stack
	 * @param world
	 */
	public void placeBlock(ItemStack stack, World world) {
		if (selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
			BlockInstance bi = (BlockInstance)selectedSpatial;
			IntWrapper block = new IntWrapper(bi.getBlock());
			Vector3d relativePos = new Vector3d(pos);
			relativePos.sub(bi.x, bi.y, bi.z);
			int b = stack.getBlock();
			if (b != 0) {
				Vector3i neighborDir = new Vector3i();
				// Check if stuff can be added to the block itself:
				if (b == bi.getBlock()) {
					if (Blocks.mode(b).generateData(Cubyz.world, bi.x, bi.y, bi.z, relativePos, dir, neighborDir, block, false)) {
						world.updateBlock(bi.x, bi.y, bi.z, block.data);
						stack.add(-1);
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
						stack.add(-1);
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
						world.updateBlock(neighbor.x, neighbor.y, neighbor.z, block.data);
						stack.add(-1);
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
