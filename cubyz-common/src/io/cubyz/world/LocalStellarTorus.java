package io.cubyz.world;

import org.joml.Vector4f;

public class LocalStellarTorus extends StellarTorus {

	private TorusSurface surface;
	private long localSeed;
	
	public LocalStellarTorus(World world, long seed) {
		this(world, "P.K. Kusuo Saiki", seed);
	}
	
	public LocalStellarTorus(World world, String name, long seed) {
		this.name = name;
		this.world = world;
		localSeed = seed;
	}
	
	@Override
	public void cleanup() {
		
	}

	@Override
	public float getGlobalLighting() {
		return 0;
	}

	@Override
	public Vector4f getAtmosphereColor() {
		return null;
	}

	@Override
	public long getLocalSeed() {
		return localSeed;
	}

	@Override
	public boolean hasSurface() {
		return surface != null;
	}
	
	public TorusSurface getSurface() {
		return surface;
	}

}
