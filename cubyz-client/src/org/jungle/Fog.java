package org.jungle;

import org.joml.Vector3f;

public class Fog {

	public static final Fog NO_FOG = new Fog();
	
	private boolean active;
	private Vector3f color;
	private float density;
	
	public Fog(boolean active, Vector3f color, float density) {
		this.color = color;
		this.active = active;
		this.density = density;
	}
	
	public Fog() {
		this(false, new Vector3f(0, 0, 0), 0);
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

	public float getDensity() {
		return density;
	}

	public void setDensity(float density) {
		this.density = density;
	}
	
	
}
