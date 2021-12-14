package cubyz.rendering;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import cubyz.world.entity.Player;

public class Spatial {

    private Mesh mesh;
    private final Vector3f position;
    private final Vector3f rotation;
    public Matrix4f modelViewMatrix;
    
    private Vector3f scale = new Vector3f(1, 1, 1);
    private boolean selected;
    
    /**
     * Used to store the distance from the player for transparent blocks, so it doesn't need to get recalculated while sorting.
     */
    public float distance;
    
    public int[] light;
    
    public int scalingData;

    public Spatial(Mesh mesh) {
        this.mesh = mesh;
        position = new Vector3f(0, 0, 0);
        rotation = new Vector3f(0, 0, 0);
        light = new int[8];
        generateMatrix();
    }

    public Spatial(Mesh mesh, int[] light) {
        this.mesh = mesh;
        position = new Vector3f(0, 0, 0);
        rotation = new Vector3f(0, 0, 0);
        this.light = light;
        generateMatrix();
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

    // Doesn't take player position into account.
	public void setPositionRaw(float x, float y, float z) {
		this.position.x = x;
        this.position.y = y;
		this.position.z = z;
        generateMatrix();
    }

	// Does take player position into account.
	public void setPosition(float x, float y, float z, Player p, int worldSizeX, int worldSizeZ) {
		if (p.getPosition().x < worldSizeX/4 && x > 3*worldSizeX/4) {
	        this.position.x = x - worldSizeX;
		} else if (p.getPosition().x > 3*worldSizeX/4 && x < worldSizeX/4) {
	        this.position.x = x + worldSizeX;
		} else {
			this.position.x = x;
		}
		if (p.getPosition().z < worldSizeZ/4 && z >= 3*worldSizeZ/4) {
	        this.position.z = z - worldSizeZ;
		} else if (p.getPosition().z >= 3*worldSizeZ/4 && z < worldSizeZ/4) {
	        this.position.z = z + worldSizeZ;
		} else {
			this.position.z = z;
		}
        this.position.y = y;
        generateMatrix();
    }
	
	public void setPosition(Vector3f position, Player p, int worldSizeX, int worldSizeZ) {
		setPosition(position.x, position.y, position.z, p, worldSizeX, worldSizeZ);
	}

    public Vector3f getScale() {
        return scale;
    }
    
    protected void setMesh(Mesh mesh) {
    	this.mesh = mesh;
    }

    public void setScale(float scale) {
        this.scale.set(scale);
        generateMatrix();
    }

    public void setScale(float xScale, float yScale, float zScale) {
        scale.x = xScale;
        scale.y = yScale;
        scale.z = zScale;
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
        return mesh;
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