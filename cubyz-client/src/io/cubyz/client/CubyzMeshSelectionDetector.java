package io.cubyz.client;

import org.joml.Intersectionf;
import org.joml.Vector2f;
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
	protected Vector2f nearFar = new Vector2f();
	protected BlockInstance selectedSpatial;
	
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
		//this.dir = dir;
		Vector3f transformedPosition = new Vector3f(position.relX, position.y+1.5F, position.relZ);
		//float closestDistance = Float.POSITIVE_INFINITY;
		float closestDistance = 6f; // selection now limited
		BlockInstance newSpatial = null;
		//position.x = position.z = 0;
		for (Chunk ch : chunks) {
			min.set(ch.getMin(position, worldAnd));
			max.set(ch.getMax(position, worldAnd));
			// Check if the chunk is in view:
			if (!Intersectionf.intersectRayAab(transformedPosition, dir, min, max, nearFar))
				continue;
			synchronized (ch) {
				BlockInstance[] array = ch.getVisibles().array;
				for (int i = 0; i < ch.getVisibles().size; i++) {
					BlockInstance bi = array[i];
					if(bi == null)
						break;
					if(!bi.getBlock().isSolid())
						continue;
					min.set(new Vector3f(bi.getX() - position.x, bi.getY(), bi.getZ() - position.z));
					max.set(min);
					min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
					max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
					if (Intersectionf.intersectRayAab(transformedPosition, dir, min, max, nearFar) && nearFar.x < closestDistance) {
						closestDistance = nearFar.x;
						newSpatial = bi;
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
	public Vector3i getEmptyPlace(Vector3fi position, Vector3f dir) {
		//position = new Vector3f(position.x, position.y+1.5F, position.z);
		Vector3f transformedPosition = new Vector3f(position.relX, position.y+1.5F, position.relZ);
		if(selectedSpatial != null) {
			Vector3i pos = new Vector3i(selectedSpatial.getPosition());
			pos.add(-(int)Math.signum(dir.x), 0, 0);
			min.set(new Vector3f(pos.x - position.x, pos.y, pos.z - position.z));
			max.set(min);
			min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
			max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
			if (Intersectionf.intersectRayAab(transformedPosition, dir, min, max, nearFar)) {
				return pos;
			}
			pos.add((int)Math.signum(dir.x), -(int)Math.signum(dir.y), 0);
			min.set(new Vector3f(pos.x - position.x, pos.y, pos.z - position.z));
			max.set(min);
			min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
			max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
			if (Intersectionf.intersectRayAab(transformedPosition, dir, min, max, nearFar)) {
				return pos;
			}
			pos.add(0, (int)Math.signum(dir.y), -(int)Math.signum(dir.z));
			return pos;
		}
		return null;
	}
	
}
