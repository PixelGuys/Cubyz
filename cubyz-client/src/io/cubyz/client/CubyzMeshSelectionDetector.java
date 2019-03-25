package io.cubyz.client;

import java.util.List;
import org.joml.Intersectionf;
import org.joml.Vector2f;
import org.joml.Vector3f;
import org.jungle.Camera;
import org.jungle.renderers.IRenderer;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.world.BlockSpatial;
import io.cubyz.world.Chunk;

public class CubyzMeshSelectionDetector {

	protected IRenderer render;
	protected Vector3f dir = new Vector3f();
	protected Vector3f min = new Vector3f(), max = new Vector3f();
	protected Vector2f nearFar = new Vector2f();
	protected BlockInstance selectedSpatial;
	
	public CubyzMeshSelectionDetector(IRenderer render) {
		this.render = render;
	}
	
	/**
	 * Return selected block instance
	 * @return selected block instance, or null if none.
	 */
	public BlockInstance getSelectedBlockInstance() {
		return selectedSpatial;
	}
	
	public void selectSpatial(List<Chunk> chunks, Camera camera) {
		dir = render.getTransformation().getViewMatrix(camera).positiveZ(dir).negate();
	    selectSpatial(chunks, camera.getPosition(), dir);
	}
	
	public void selectSpatial(List<Chunk> chunks, Vector3f position, Vector3f dir) {
	    float closestDistance = Float.POSITIVE_INFINITY;
	    selectedSpatial = null;
	    for (Chunk ch : chunks) {
	    	if(!ch.isLoaded())
	    		continue;
	    	try {
		    for (BlockInstance bi : ch.getVisibles()) {
		        ((BlockSpatial) bi.getSpatial()).setSelected(false);
		        min.set(bi.getPosition());
		        max.set(bi.getPosition());
		        min.add(-0.5f, -0.5f, -0.5f); // -scale, -scale, -scale
		        max.add(0.5f, 0.5f, 0.5f); // scale, scale, scale
		        if (Intersectionf.intersectRayAab(position, dir, min, max, nearFar) && nearFar.x < closestDistance) {
		            closestDistance = nearFar.x;
		            selectedSpatial = bi;
		        }
		    }
	    	}catch(Exception e) {}
	    }
	    if (selectedSpatial != null) {
	        ((BlockSpatial) selectedSpatial.getSpatial()).setSelected(true);
	    }
	}
	
}
