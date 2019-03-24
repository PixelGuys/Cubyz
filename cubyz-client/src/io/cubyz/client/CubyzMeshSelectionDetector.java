package io.cubyz.client;

import java.util.ArrayList;
import java.util.Map;

import org.joml.Intersectionf;
import org.joml.Vector2f;
import org.joml.Vector3f;
import org.jungle.Camera;
import org.jungle.Spatial;
import org.jungle.renderers.IRenderer;
import org.jungle.renderers.jungle.JungleRender;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.world.BlockSpatial;

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
	 * Return selected spatial
	 * @return selected spatial, or null if none.
	 */
	public BlockInstance getSelectedBlockInstance() {
		return selectedSpatial;
	}
	
	public void selectSpatial(Map<Block, ArrayList<BlockInstance>> blockList, Camera camera) {
		dir = render.getTransformation().getViewMatrix(camera).positiveZ(dir).negate();
	    selectSpatial(blockList, camera.getPosition(), dir);
	}
	
	public void selectSpatial(Map<Block, ArrayList<BlockInstance>> blockList, Vector3f position, Vector3f dir) {
	    float closestDistance = Float.POSITIVE_INFINITY;
	    for (Block block : blockList.keySet()) {
		    for (BlockInstance bi : blockList.get(block)) {
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
	    }
	    if (selectedSpatial != null) {
	        ((BlockSpatial) selectedSpatial.getSpatial()).setSelected(true);
	    }
	}
	
}
