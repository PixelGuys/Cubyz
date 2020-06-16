package io.jungle;

import org.joml.Vector3f;

public class Spatial {

    private Mesh[] meshes;
    private final Vector3f position;
    private final Vector3f rotation;
    
    private float scale;
    private boolean selected;
    
    public int[] light;

    public Spatial(Mesh mesh) {
        this.meshes = new Mesh[] {mesh};
        position = new Vector3f(0, 0, 0);
        scale = 1;
        rotation = new Vector3f(0, 0, 0);
        light = new int[8];
    }

    public Spatial(Mesh mesh, int[] light) {
        this.meshes = new Mesh[] {mesh};
        position = new Vector3f(0, 0, 0);
        scale = 1;
        rotation = new Vector3f(0, 0, 0);
        this.light = light;
    }
    
    public Spatial(Mesh[] meshes) {
    	this.meshes = meshes;
    	position = new Vector3f(0, 0, 0);
    	scale = 1;
    	rotation = new Vector3f(0, 0, 0);
        light = new int[8];
    }
    
    public Spatial() {
    	this((Mesh) null);
    }

    public Vector3f getPosition() {
        return position;
    }
    
    public boolean isSelected() {
    	return selected;
    }
    
    public void setSelected(boolean selected) {
    	this.selected = selected;
    }

	public void setPosition(float x, float y, float z) {
        this.position.x = x;
        this.position.y = y;
        this.position.z = z;
    }
	
	public void setPosition(Vector3f position) {
		this.position.set(position);
	}

    public float getScale() {
        return scale;
    }
    
    protected void setMeshes(Mesh[] mesh) {
    	this.meshes = mesh;
    }

    public void setScale(float scale) {
        this.scale = scale;
    }

    public Vector3f getRotation() {
        return rotation;
    }

    public void setRotation(float x, float y, float z) {
        this.rotation.x = x;
        this.rotation.y = y;
        this.rotation.z = z;
    }

    public Mesh getMesh() {
        return meshes[0];
    }
    
    public Mesh[] getMeshes() {
    	return meshes;
    }
    
}