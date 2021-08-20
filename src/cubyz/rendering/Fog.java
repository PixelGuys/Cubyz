package cubyz.rendering;

import org.joml.Vector3f;
import org.joml.Vector4f;

public class Fog {
	
	private boolean active;
	private Vector3f color;
	private float density;
	
	public Fog(boolean active, Vector3f color, float density) {
		this.color = color;
		this.active = active;
		this.density = density;
	}

	public boolean isActive() {
		return active;
	}

	public void setActive(boolean active) {
		this.active = active;
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

	public float getDensity() {
		return density;
	}

	public void setDensity(float density) {
		this.density = density;
	}
	
	
}
