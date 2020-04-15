package io.cubyz.world;

import org.joml.Vector4f;

public class LocalStellarTorus extends StellarTorus {

	private TorusSurface surface;
	private long localSeed;
	private Vector4f atmosphereColor = new Vector4f(1f, 1f, 1f, 1f);
	public static final int DAYCYCLE = 120000; // Length of one in-game day in 100ms. Midnight is at DAYCYCLE/2. Sunrise and sunset each take about 1/16 of the day. Currently set to 20 minutes
	public static final int SEASONCYCLE = DAYCYCLE * 7; // Length of one in-game season in 100ms. Equals to 7 days per season
	
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
	public Vector4f getAtmosphereColor() {
		return atmosphereColor;
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
	
	public void update() {
		long gameTime = world.getGameTime();
		season = (int) ((gameTime/SEASONCYCLE) % 4);
		
		if (surface != null) {
			surface.update();
		}
	}

	@Override
	public int getDayCycle() {
		return DAYCYCLE;
	}

	@Override
	public int getSeasonCycle() {
		return SEASONCYCLE;
	}

	@Override
	public void setLocalSeed(long localSeed) {
		this.localSeed = localSeed;
	}

}
