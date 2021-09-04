package cubyz.world.terrain;

import cubyz.utils.datastructures.Cache;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.terrain.noise.FractalNoise;

public class ClimateMapFragment {
	/**Constants that define how the climate map is generated. TODO: Change these depending on the world.*/
	public static final float	OCEAN_THRESHOLD = 0.5f,
								MOUNTAIN_RATIO = 0.8f,
								MOUNTAIN_POWER = 3f,
								ICE_POINT = -0.5f,
								FROST_POINT = -0.35f,
								HOT_POINT = 0.5f,
								DRY_POINT = 0.35f,
								WET_POINT = 0.65f;
	static final int MAP_SHIFT = 8 + MapFragment.BIOME_SHIFT;
	static final int MAP_SIZE = 1 << MAP_SHIFT;
	static final int MAP_MASK = MAP_SIZE - 1;
	static final float RING_SIZE = 64;
	static final float WIND_SPEED = 1;
	static final float WIND_INFLUENCE = 0.1f;
	final int wx, wz;
	final long seed;
	final Biome.Type[][] map;
	
	public ClimateMapFragment(long seed, int wx, int wz) {
		this.wx = wx;
		this.wz = wz;
		this.seed = seed;
		map = new Biome.Type[MAP_SIZE/MapFragment.BIOME_SIZE][MAP_SIZE/MapFragment.BIOME_SIZE];
		// Create the surrounding height and wind maps needed for wind propagation:
		float[][] heightMap = new float[3*MAP_SIZE/MapFragment.BIOME_SIZE][3*MAP_SIZE/MapFragment.BIOME_SIZE];
		FractalNoise.generateSparseFractalTerrain(wx - MAP_SIZE, wz - MAP_SIZE, 3*MAP_SIZE, 3*MAP_SIZE,
				MAP_SIZE/16, seed^92786504683290654L, heightMap, MapFragment.BIOME_SIZE);
		
		float[][] windXMap = new float[3*MAP_SIZE/MapFragment.BIOME_SIZE][3*MAP_SIZE/MapFragment.BIOME_SIZE];
		FractalNoise.generateSparseFractalTerrain(wx - MAP_SIZE, wz - MAP_SIZE, 3*MAP_SIZE, 3*MAP_SIZE,
				MAP_SIZE/8, seed^4382905640235972L, windXMap, MapFragment.BIOME_SIZE);
		
		float[][] windZMap = new float[3*MAP_SIZE/MapFragment.BIOME_SIZE][3*MAP_SIZE/MapFragment.BIOME_SIZE];
		FractalNoise.generateSparseFractalTerrain(wx - MAP_SIZE, wz - MAP_SIZE, 3*MAP_SIZE, 3*MAP_SIZE,
				MAP_SIZE/8, seed^532985472894530L, windZMap, MapFragment.BIOME_SIZE);
		
		// Make non-ocean regions more flat:
		for(int x = 0; x < heightMap.length; x++) {
			for(int y = 0; y < heightMap[0].length; y++) {
				if(heightMap[x][y] >= OCEAN_THRESHOLD)
					heightMap[x][y] = (float)(OCEAN_THRESHOLD + (1 - OCEAN_THRESHOLD)*Math.pow((heightMap[x][y] - OCEAN_THRESHOLD)/(1 - OCEAN_THRESHOLD), MOUNTAIN_POWER));
			}
		}

		// Calculate the temperature and humidty for each point on the map. This is done by backtracing along the wind.
		// On mountains the water will often rain down, so wind that goes through a mountain will carry less.
		// Oceans carry water, so if the wind went through an ocean it picks up water.
		
		// Alongside that there is also an initial temperature and humidity distribution that mimics the earth.
		// How is that possible? Isn't Cubyz flat?
		// On the earth there are just two arctic poles. Cubyz takes the north pole and places it at (0, 0).
		// Then there are infinite poles with ring shapes and each ring will have an equal distance to the previous one.
		// That's not perfectly realistic, but it's ok in the sense that following a compass will lead to one arctic
		// and away from another.
		
		for(int x = 0; x < map.length; x++) {
			for(int z = 0; z < map.length; z++) {
				float humid = getInitialHumidity(x, z, heightMap[x + map.length][z+map.length]);
				float temp = getInitialTemperature(x, z, heightMap[x + map.length][z+map.length]);
				float humidInfluence = WIND_INFLUENCE;
				float tempInfluence = WIND_INFLUENCE;
				float nextX = x;
				float nextZ = z;
				for(int i = 0; i < 50; i++) {
					float windX = windXMap[(int)nextX + map.length][(int)nextZ + map.length];
					float windZ = windXMap[(int)nextX + map.length][(int)nextZ + map.length];
					nextX += windX*WIND_SPEED;
					nextZ += windZ*WIND_SPEED;
					// Make sure the bounds are ok:
					if(nextX < -map.length || nextX > 2*map.length - 1) {
						break;
					}
					if(nextZ < -map.length || nextZ > 2*map.length - 1) {
						break;
					}
					// Find the local temperature and humidity:
					float localHeight = heightMap[(int)nextX + map.length][(int)nextZ + map.length];
					float localTemp = getInitialTemperature(nextX, nextZ, localHeight);
					float localHumid = getInitialHumidity(nextX, nextZ, localHeight);
					humid = (1 - humidInfluence)*humid + humidInfluence*localHumid;
					temp = (1 - tempInfluence)*temp + tempInfluence*localTemp;
					tempInfluence *= 0.9f; // Distance reduction
					humidInfluence *= 0.9f; // Distance reduction
					// Reduction from mountains:
					humidInfluence *= Math.pow(1 - heightMap[(int)nextX + map.length][(int)nextZ + map.length], 0.05);
				}
				// Insert the biome type:
				map[x][z] = findClimate(heightMap[x + map.length][z+map.length], humid, temp);
			}
		}
	}
	
	private float getInitialHumidity(double x, double z, float height) {
		if(height < OCEAN_THRESHOLD) return 1;
		x = x + (wx >> MapFragment.BIOME_SHIFT);
		z = z + (wz >> MapFragment.BIOME_SHIFT);
		double distance = Math.sqrt(x*x + z*z)/RING_SIZE;
		distance %= 1;
		// On earth there is high humidity at the equator and the poles and low humidty at around 30°.
		// Interpolating through this data resulted in this function:
		// 1 - 2916/125*x² - 16038/125*x⁴ + 268272/125*x⁶ - 629856/125*x⁸
		
		if(distance >= 0.5f) distance -= 1;
		// Now calculate the function:
		x = distance*distance;
		x = 1 - 2916.0f/125.0f*x - 16038.0f/125.0f*x*x + 268272.0f/125.0f*x*x*x - 629856.0f/125.0f*x*x*x*x;
		// Put the output in scale:
		return (float)(x*0.5f + 0.5f);
	}
	
	private float getInitialTemperature(double x, double z, float height) {
		x = x + (wx >> MapFragment.BIOME_SHIFT);
		z = z + (wz >> MapFragment.BIOME_SHIFT);
		double temp = Math.sqrt(x*x + z*z)/RING_SIZE%1;
		// Uses a simple triangle function:
		if(temp > 0.5f) {
			temp = 1 - temp;
		}
		temp = 4*temp - 1;
		return heightDependantTemperature((float)temp, height);
	}
	
	/**
	 * Adds height dependent temperature changes.
	 * @param temperature
	 * @param height
	 * @return
	 */
	private static float heightDependantTemperature(float temperature, float height) {
		// On earth temperature changes by `6.5K/km`.
		// On a cubyz world the highest mountain will be `(1 - OCEAN_THRESHOLD)` units high.
		// If the highest possible height of a mountain is assumed to be 10km, the temperature change gets: `65K/(1 - OCEAN_THRESHOLD)*(height - OCEAN_THRESHOLD)`
		// Annual average temperature on earth range between -50°C and +30°C giving a difference of 80K
		// On cubyz average temperature range from -1 to 1 giving a difference of 2.
		// Therefor the total equation gets: `65K*2/80K/(1 - OCEAN_THRESHOLD)*(height - OCEAN_THRESHOLD)` = `1.625/(1 - OCEAN_THRESHOLD)*(height - OCEAN_THRESHOLD)`
		
		// Furthermore I assume that the average temperature is at 1km of height.
		return temperature - 1.625f*(Math.max(0, height - OCEAN_THRESHOLD)/(1 - OCEAN_THRESHOLD) - 0.1f);
	}
	
	private static Biome.Type findClimate(float height, float humid, float temp) {
		if(height < OCEAN_THRESHOLD) {
			if(temp <= FROST_POINT) {
				return Biome.Type.ARCTIC_OCEAN;
			} else if(temp < HOT_POINT) {
				return Biome.Type.OCEAN;
			} else {
				return Biome.Type.WARM_OCEAN;
			}
		} else if(height < (1.0f - OCEAN_THRESHOLD)*(1 - MOUNTAIN_RATIO) + OCEAN_THRESHOLD) {
			if(temp <= FROST_POINT) {
				if(temp <= ICE_POINT) {
					return Biome.Type.GLACIER;
				} else if(humid < WET_POINT) {
					return Biome.Type.TAIGA;
				} else {
					return Biome.Type.TUNDRA;
				}
			} else if(temp < HOT_POINT) {
				if(humid <= DRY_POINT) {
					return Biome.Type.GRASSLAND;
				} else if(humid < WET_POINT) {
					return Biome.Type.FOREST;
				} else {
					return Biome.Type.SWAMP;
				}
			} else {
				if(humid <= DRY_POINT) {
					return Biome.Type.DESERT;
				} else if(humid < WET_POINT) {
					return Biome.Type.SHRUBLAND;
				} else {
					return Biome.Type.RAINFOREST;
				}
			}
		} else {
			if(temp <= FROST_POINT) {
				return Biome.Type.PEAK;
			} else {
				if(humid <= WET_POINT) {
					return Biome.Type.MOUNTAIN_GRASSLAND;
				} else {
					return Biome.Type.MOUNTAIN_FOREST;
				}
			}
		}
	}
	
	@Override
	public int hashCode() {
		return hashCode(wx, wz);
	}
	
	public static int hashCode(int wx, int wz) {
		return (wx >> MAP_SHIFT)*31 + (wz >> MAP_SHIFT);
	}
}
