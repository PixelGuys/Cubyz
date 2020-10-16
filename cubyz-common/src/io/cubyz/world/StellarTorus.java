package io.cubyz.world;

import org.joml.Vector4f;

/**
 * STELLAR TORUSES !!1!!!
 */
public abstract class StellarTorus {
	protected int season; // 0=Spring, 1=Summer, 2=Autumn, 3=Winter
	protected World world;
	protected StellarTorus orbitalParent;
	protected String name;
	protected float distance, angle; // the relative angle and distance to the orbital parent.
	// if this torus doesn't have an orbital parent, use the following variables:
	protected float absX, absY; // absolute positions if the above condition is true
	protected float gravity = 0.022f;

	public abstract void cleanup();
	
	public abstract Vector4f getAtmosphereColor(); // = clear color in practice
	
	public abstract long getLocalSeed();
	public abstract void setLocalSeed(long localSeed);
	
	public void setGravity(float gravity) {
		this.gravity = gravity;
	}
	
	public float getGravity() {
		return gravity;
	}
	
	public StellarTorus getOrbitalParent() {
		return orbitalParent;
	}
	
	public abstract boolean hasSurface();
	
	public int getSeason() {
		return season;
	}
	
	public abstract int getDayCycle();
	public abstract int getSeasonCycle();
	
	public void setName(String name) {
		this.name = name;
	}
	
	public String getName() {
		return name;
	}
	
	public World getWorld() {
		return world;
	}
	
	public void update() {}
}
