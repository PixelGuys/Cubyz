package io.jungle;

import org.joml.Matrix4f;
import org.joml.Vector3f;

public class Spatial {

    private Mesh[] meshes;
    private final Vector3f position;
    private final Vector3f rotation;
    public Matrix4f modelViewMatrix;
    
    private float scale;
    private boolean selected;
    
    public int[] light;

    public Spatial(Mesh mesh) {
        this.meshes = new Mesh[] {mesh};
        position = new Vector3f(0, 0, 0);
        scale = 1;
        rotation = new Vector3f(0, 0, 0);
        light = new int[8];
        generateMatrix();
    }

    public Spatial(Mesh mesh, int[] light) {
        this.meshes = new Mesh[] {mesh};
        position = new Vector3f(0, 0, 0);
        scale = 1;
        rotation = new Vector3f(0, 0, 0);
        this.light = light;
        generateMatrix();
    }
    
    public Spatial(Mesh[] meshes) {
    	this.meshes = meshes;
    	position = new Vector3f(0, 0, 0);
    	scale = 1;
    	rotation = new Vector3f(0, 0, 0);
        light = new int[8];
        generateMatrix();
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
        generateMatrix();
    }
	
	public void setPosition(Vector3f position) {
		this.position.set(position);
        generateMatrix();
	}

    public float getScale() {
        return scale;
    }
    
    protected void setMeshes(Mesh[] mesh) {
    	this.meshes = mesh;
    }

    public void setScale(float scale) {
        this.scale = scale;
        generateMatrix();
    }

    public Vector3f getRotation() {
        return rotation;
    }

    public void setRotation(float x, float y, float z) {
        this.rotation.x = x;
        this.rotation.y = y;
        this.rotation.z = z;
        generateMatrix();
    }

    public Mesh getMesh() {
        return meshes[0];
    }
    
    public Mesh[] getMeshes() {
    	return meshes;
    }
    
    private void generateMatrix() {
		modelViewMatrix = new Matrix4f().identity()
			.translate(position)
			.rotateX(-rotation.x)
			.rotateY(-rotation.y)
			.rotateZ(-rotation.z)
			.scale(scale);
    }
    
}