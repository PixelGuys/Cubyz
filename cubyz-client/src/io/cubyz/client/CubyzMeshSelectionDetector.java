package io.cubyz.client;

import org.joml.RayAabIntersection;
import org.joml.Vector3f;
import org.joml.Vector3i;

import io.cubyz.blocks.BlockInstance;
import io.cubyz.math.Vector3fi;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.Chunk;
import io.jungle.renderers.Renderer;

public class CubyzMeshSelectionDetector {

	protected Renderer render;
	protected Vector3f min = new Vector3f(), max = new Vector3f();
	protected int x, z, dirX, dirY, dirZ; // Used to prevent a block placement bug caused by asynchronous player position when selectSpatial and when getEmptyPlace are called.
	protected BlockInstance selectedSpatial;
	RayAabIntersection intersection = new RayAabIntersection();
	
	public CubyzMeshSelectionDetector(Renderer render) {
		this.render = render;
	}
	
	/**
	 * Return selected block instance
	 * @return selected block instance, or null if none.
	 */
	public BlockInstance getSelectedBlockInstance() {
		return selectedSpatial;
	}
	
	public void selectSpatial(Chunk[] chunks, Vector3fi position, Vector3f dir, int worldAnd) {
		Vector3f transformedPosition = new Vector3f(position.relX, position.y+1.5F, position.relZ);
		x = position.x;
		z = position.z;
		dirX = (int)Math.signum(dir.x);
		dirY = (int)Math.signum(dir.y);
		dirZ = (int)Math.signum(dir.z);
		float closestDistance = 6f; // selection now limited
		BlockInstance newSpatial = null;
		intersection.set(transformedPosition.x, transformedPosition.y, transformedPosition.z, dir.x, dir.y, dir.z);
		for (Chunk ch : chunks) {
			min.set(ch.getMin(position, worldAnd));
			max.set(ch.getMax(position, worldAnd));
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
					min.set(new Vector3f(bi.getX() - x, bi.getY(), bi.getZ() - z));
					max.set(min);
					min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
					max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
					// Because of the huge number of different BlockInstances that will be tested, it is more efficient to use RayAabIntersection and determine the distance sperately:
					if (intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
						float distance = min.add(0.5f, 0.5f, 0.5f).sub(transformedPosition).length();
						if(distance < closestDistance) {
							closestDistance = distance;
							newSpatial = bi;
						}
					}
				}
			}
		}
		if(newSpatial == selectedSpatial)
			return;
		if(selectedSpatial != null) {
			synchronized(selectedSpatial) {
				((BlockSpatial) selectedSpatial.getSpatial()).setSelected(false);
			}
		}
		selectedSpatial = newSpatial;
		if(selectedSpatial != null) {
			synchronized(selectedSpatial) {
				((BlockSpatial) selectedSpatial.getSpatial()).setSelected(true);
			}
		}
	}
	
	// Returns the free block right next to the currently selected block.
	public void getEmptyPlace(Vector3i pos, Vector3i dir) {
		if(selectedSpatial != null) {
			pos.set(selectedSpatial.getPosition());
			pos.add(-dirX, 0, 0);
			dir.add(dirX, 0, 0);
			min.set(new Vector3f(pos.x - x, pos.y, pos.z - z));
			max.set(min);
			min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
			max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
			if (!intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
				pos.add(dirX, -dirY, 0);
				dir.add(-dirX, dirY, 0);
				min.set(new Vector3f(pos.x - x, pos.y, pos.z - z));
				max.set(min);
				min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
				max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
				if (!intersection.test(min.x, min.y, min.z, max.x, max.y, max.z)) {
					pos.add(0, dirY, -dirZ);
					dir.add(0, -dirY, dirZ);
				}
			}
		}
	}
	
}
