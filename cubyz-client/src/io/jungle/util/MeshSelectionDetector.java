package io.jungle.util;

import org.joml.Intersectionf;
import org.joml.Vector2f;
import org.joml.Vector3f;

import io.jungle.Camera;
import io.jungle.Spatial;
import io.jungle.renderers.Renderer;

public class MeshSelectionDetector {

	protected Renderer render;
	protected Vector3f dir = new Vector3f();
	protected Vector3f min = new Vector3f(), max = new Vector3f();
	protected Vector2f nearFar = new Vector2f();
	protected Spatial selectedSpatial;
	
	public MeshSelectionDetector(Renderer render) {
		this.render = render;
	}
	
	/**
	 * Return selected spatial
	 * @return selected spatial, or null if none.
	 */
	public Spatial getSelectedSpatial() {
		return selectedSpatial;
	}
	
	public void selectSpatial(Spatial[] gameItems, Camera camera) {
		dir = render.getTransformation().getViewMatrix(camera).positiveZ(dir).negate();
	    selectSpatial(gameItems, camera.getPosition(), dir);
	}
	
	public void selectSpatial(Spatial[] gameItems, Vector3f position, Vector3f dir) {
	    float closestDistance = Float.POSITIVE_INFINITY;
	    for (Spatial gameItem : gameItems) {
	        gameItem.setSelected(false);
	        min.set(gameItem.getPosition());
	        max.set(gameItem.getPosition());
	        min.sub(gameItem.getScale());
	        max.add(gameItem.getScale());
	        if (Intersectionf.intersectRayAab(position, dir, min, max, nearFar) && nearFar.x < closestDistance) {
	            closestDistance = nearFar.x;
	            selectedSpatial = gameItem;
	        }
	    }
	    if (selectedSpatial != null) {
	        selectedSpatial.setSelected(true);
	    }
	}
	
}
