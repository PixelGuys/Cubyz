package cubyz.rendering;

import org.joml.Vector3f;
import org.joml.Vector4f;

public class DirectionalLight {
    
    @Override
	public String toString() {
		return "DirectionalLight [color=" + color + ", direction=" + direction + ", intensity=" + direction.length() + "]";
	}

	private Vector3f color;

    private Vector3f direction;

    public DirectionalLight(Vector3f color, Vector3f direction) {
        this.color = color;
        this.direction = direction;
    }

    public DirectionalLight(DirectionalLight light) {
        this(new Vector3f(light.getColor()), new Vector3f(light.getDirection()));
    }

    public Vector3f getColor() {
        return color;
    }

    public void setColor(Vector3f color) {
        this.color = color;
    }
    
    public void setColor(Vector4f color) {
    	this.color.x = color.x;
		this.color.y = color.y;
		this.color.z = color.z;
    }

    public Vector3f getDirection() {
        return direction;
    }

    public void setDirection(Vector3f direction) {
        this.direction = direction;
    }
}