package io.cubyz.world.cubyzgenerators.biomes;

import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

import io.cubyz.world.Noise;

/**
 * The class responsible for generating the biome type map (aka the climate map).
 */

public class BiomeGenerator {
	/**Constants that define how the climate map is generated. TODO: Change these depending on the world.*/
	public static final float	OCEAN_THRESHOLD = 0.5f,
								MOUNTAIN_RATIO = 0.8f,
								MOUNTAIN_POWER = 3f,
								ICE_POINT = -0.5f,
								FROST_POINT = -0.3f,
								HOT_POINT = 0.3f,
								DRY_POINT = 0.35f,
								WET_POINT = 0.65f;
	
	private static final int resolution = 2;
	
	/**
	 * Generates a map with the static parameters defined in this class and 
	 * @param seed
	 * @param width of the map(should be world-width/Region.regionSize)
	 * @param height of the map(should be world-height/Region.regionSize)
	 * @return
	 */
	public static Biome.Type[][] generateTypeMap(long seed, int width, int height) {
		// Generate the height map:
		float[][] heightMap = Noise.generateFractalTerrain(0, 0, width, height, Math.min(width, height) >> 3, seed^7675238959286L, width, height);
		// Make non-mountain regions more flat:
		for(int x = 0; x < width; x++) {
			for(int y = 0; y < height; y++) {
				if(heightMap[x][y] >= OCEAN_THRESHOLD)
					heightMap[x][y] = (float)(OCEAN_THRESHOLD + (1 - OCEAN_THRESHOLD)*Math.pow((heightMap[x][y] - OCEAN_THRESHOLD)/(1 - OCEAN_THRESHOLD), MOUNTAIN_POWER));
			}
		}
		
		
		// Calculate the average heat distribution around the ring of the torus:
		float[] temperature = new float[height];
		// The distribution follows two simple rules:
		// 1. Temperature at the pole rings is lower than at the equator rings.
		// 2. Temperature at the inside is higher than at the outside because heat cannot radiate away as easy.
		// Temperature is giving in a range from -1 to 1.
		for(int i = 0; i < height; i++) {
			temperature[i] = (float)(-Math.cos(i*4*Math.PI/height)*0.9 + Math.sin(i*2*Math.PI/height)*0.1);
		}
		
		// Generate a temperature map for the entire torus by changing the temperature depending on the height:
		float[][] temperatureMap = new float[width][height];
		for(int x = 0; x < width; x++) {
			for(int y = 0; y < height; y++) {
				temperatureMap[x][y] = heightDependantTemperature(temperature[y], heightMap[x][y]);
			}
		}
		
		// Run a simple fluidynamics simulation using the temperature and height map, to make the temperature map smoother and generate humidity:
		float[][] humidityMap = runSimulation(temperatureMap, heightMap, width, height, seed);
		
		
		
		Biome.Type[][] map = new Biome.Type[width][height];
		// Select the biome types based on the constants:
		for(int x = 0; x < width; x++) {
			for(int y = 0; y < height; y++) {
				float temp = temperatureMap[x][y];
				float humid = humidityMap[x][y];
				if(heightMap[x][y] < OCEAN_THRESHOLD) {
					if(temp <= FROST_POINT) {
						map[x][y] = Biome.Type.ARCTIC_OCEAN;
					} else if(temp < HOT_POINT) {
						map[x][y] = Biome.Type.OCEAN;
					} else {
						map[x][y] = Biome.Type.WARM_OCEAN;
					}
				} else if(heightMap[x][y] < (1.0f - OCEAN_THRESHOLD)*(1 - MOUNTAIN_RATIO) + OCEAN_THRESHOLD) {
					if(temp <= FROST_POINT) {
						if(temp <= ICE_POINT) {
							map[x][y] = Biome.Type.GLACIER;
						} else if(humid < WET_POINT) {
							map[x][y] = Biome.Type.TAIGA;
						} else {
							map[x][y] = Biome.Type.TUNDRA;
						}
					} else if(temp < HOT_POINT) {
						if(humid <= DRY_POINT) {
							map[x][y] = Biome.Type.GRASSLAND;
						} else if(humid < WET_POINT) {
							map[x][y] = Biome.Type.FOREST;
						} else {
							map[x][y] = Biome.Type.SWAMP;
						}
					} else {
						if(humid <= DRY_POINT) {
							map[x][y] = Biome.Type.DESERT;
						} else if(humid < WET_POINT) {
							map[x][y] = Biome.Type.SHRUBLAND;
						} else {
							map[x][y] = Biome.Type.RAINFOREST;
						}
					}
				} else {
					if(temp <= FROST_POINT) {
						if(humid <= WET_POINT) {
							map[x][y] = Biome.Type.PEAK;
						} else {
							map[x][y] = Biome.Type.GLACIER;
						}
					} else {
						if(humid <= WET_POINT) {
							map[x][y] = Biome.Type.MOUNTAIN_GRASSLAND;
						} else {
							map[x][y] = Biome.Type.MOUNTAIN_FOREST;
						}
					}
				}
			}
		}
		render(map, width, height);
		return map;
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
	
	private static float[][] runSimulation(float[][] temperatureMap, float[][] heightMap, int width, int height, long seed) {
		float[][] humidityMap = new float[width][height];
		
		// Run the simulation only on a reduced part of the map to reduce required processing power:
		width >>= resolution;
		height >>= resolution;
		float[][] H = new float[width][height];
		float[][] T = new float[width][height];
		float[][] ρ = new float[width][height];
		float[][] vx = Noise.generateFractalTerrain(0, 0, width, height, Math.min(width, height) >> 2, seed^56489356439598L, width, height);
		float[][] vy = Noise.generateFractalTerrain(0, 0, width, height, Math.min(width, height) >> 2, seed^56492654064751L, width, height);
		for(int x = 0; x < width; x++) {
			for(int y = 0; y < height; y++) {
				T[x][y] = temperatureMap[x << resolution][y << resolution];
				H[x][y] = humidityDistribution(y, height);
				ρ[x][y] = 1;
				vx[x][y] -= 0.5f;
				vy[x][y] -= 0.5f;
				vx[x][y] /= 0.5f;
				vy[x][y] /= 0.5f;
			}
		}
		// And some more arrays to store the values of the next iteration:
		float[][] dH = new float[width][height];
		float[][] dT = new float[width][height];
		float[][] dρ = new float[width][height];
		float[][] ax = new float[width][height];
		float[][] ay = new float[width][height];
		
		
		// Do some amount of steps:
		int steps = 100*height/(512 >> resolution);
		float dt = 0.5f*height/(512 >> resolution);
		for(int i = 0; i < steps; i++) {
			
			// update humidity and temperature:
			for(int x = 0; x < width; x++) {
				for(int y = 0; y < height; y++) {
					if(heightMap[x << resolution][y <<  resolution] < OCEAN_THRESHOLD) {
						// Evaporate water above oceans:
						H[x][y] = 1;
					} else {
						// Get closer to the initial humidity distribution(which is needed to create deserts at the edge of tropics):
						H[x][y] += 0.25f*dt*((humidityDistribution(y, height)) - 0.5f);
						// Rain down water on higher terrain:
						H[x][y] *= 1.0f - 0.1f*dt*(0.25f + (heightMap[x << resolution][y <<  resolution] - OCEAN_THRESHOLD)/(1 - OCEAN_THRESHOLD));
					}
					// Get closer to the initial temperature distribution(which is needed to prevent arctic and tropic from mixing):
					T[x][y] += dt*0.1f*(temperatureMap[x << resolution][y << resolution] - T[x][y]);
				}
			}

			// Calculate changes:
			for(int x = 0; x < width; x++) {
				for(int y = 0; y < height; y++) {
					// Displace the current region using the velocity:
					float xNew = x + vx[x][y]*dt;
					float yNew = y + vy[x][y]*dt;
					int x0 = mod((int)Math.floor(xNew), width);
					int y0 = mod((int)Math.floor(yNew), height);
					int x1 = mod(x0+1, width);
					int y1 = mod(y0+1, height);
					float xFac = mod(xNew, 1);
					float yFac = mod(yNew, 1);
					// Distribute content of this region to the regions that are intersected by the displaced region.
					update(ρ[x][y], vx[x][y], vy[x][y], T[x][y], H[x][y], dρ, ax, ay, dT, dH, x0, y0, 1-xFac, 1-yFac);
					update(ρ[x][y], vx[x][y], vy[x][y], T[x][y], H[x][y], dρ, ax, ay, dT, dH, x0, y1, 1-xFac, yFac);
					update(ρ[x][y], vx[x][y], vy[x][y], T[x][y], H[x][y], dρ, ax, ay, dT, dH, x1, y0, xFac, 1-yFac);
					update(ρ[x][y], vx[x][y], vy[x][y], T[x][y], H[x][y], dρ, ax, ay, dT, dH, x1, y1, xFac, yFac);
				}
			}
			
			// Update changes:
			for(int x = 0; x < width; x++) {
				for(int y = 0; y < height; y++) {
					// Divide by ρ to conserve those quantities.
					vx[x][y] = ax[x][y]/dρ[x][y];
					vy[x][y] = ay[x][y]/dρ[x][y];
					H[x][y] = dH[x][y]/dρ[x][y];
					T[x][y] = dT[x][y]/dρ[x][y];
					ρ[x][y] = dρ[x][y];

					ax[x][y] = 0;
					ay[x][y] = 0;
					dρ[x][y] = 0;
					dH[x][y] = 0;
					dT[x][y] = 0;
				}
			}
		}
		
		// Store the results:
		for(int x = 0; x < width << resolution; x++) {
			for(int y = 0; y < height << resolution; y++) {
				int x0 = x >> resolution;
				int y0 = y >> resolution;
				int x1 = mod(x0 + 1, width);
				int y1 = mod(y0 + 1, height);
				float xFac = (x - (x0 << resolution))/(float)(1 << resolution);
				float yFac = (y - (y0 << resolution))/(float)(1 << resolution);

				temperatureMap[x][y] = T[x0][y0]*(1-xFac)*(1-yFac) + T[x0][y1]*(1-xFac)*yFac + T[x1][y0]*xFac*(1-yFac) + T[x1][y1]*xFac*yFac;
				humidityMap[x][y] = H[x0][y0]*(1-xFac)*(1-yFac) + H[x0][y1]*(1-xFac)*yFac + H[x1][y0]*xFac*(1-yFac) + H[x1][y1]*xFac*yFac;
			}
		}
		// Upscale the result and add some randomness using a fractal algorithm.
		for(int x0 = 0; x0 < width; x0++) {
			for(int y0 = 0; y0 < height; y0++) {
				int x1 = mod(x0 + 1, width);
				int y1 = mod(y0 + 1, height);
				fractalInterpolate(T[x0][y0], T[x0][y1], T[x1][y0], T[x1][y1], temperatureMap, resolution, x0, y0, seed, width << resolution, height << resolution);
				fractalInterpolate(H[x0][y0], H[x0][y1], H[x1][y0], H[x1][y1], humidityMap, resolution, x0, y0, seed, width << resolution, height << resolution);
			}
		}
		
		return humidityMap;
	}
	
	private static void fractalInterpolate(float value00, float value01, float value10, float value11, float[][] map, int resolution, int x, int y, long seed, int width, int height) {
		x <<= resolution;
		y <<= resolution;
		int kernelWidth = 1 << resolution;
		float[][] fragment = new float[kernelWidth + 1][kernelWidth + 1];
		// Initialize values:
		fragment[0][0] = value00;
		fragment[0][kernelWidth] = value01;
		fragment[kernelWidth][0] = value10;
		fragment[kernelWidth][kernelWidth] = value11;
		Noise.generateInitializedFractalTerrain(0, 0, height, kernelWidth, seed, width, height, fragment, -Float.MAX_VALUE, Float.MAX_VALUE, 1);
		for(int i = 0; i < kernelWidth; i++) {
			for(int j = 0; j < kernelWidth; j++) {
				map[x + i][y + j] = fragment[i][j];
			}
		}
	}
	
	private static float humidityDistribution(int y, int height) {
		// On earth there is high humidity at the equator and the poles and low humidty at around 30°.
		// Interpolating through this data resulted in this function:
		// 1 - 2916/125*x² - 16038/125*x⁴ + 268272/125*x⁶ - 629856/125*x⁸
		
		// Start by putting x in range:
		float x = y/(float)height;
		x *= 2;
		x %= 1;
		if(x >= 0.5f) x -= 1;
		// Now calculate the function:
		x *= x;
		x = 1 - 2916.0f/125.0f*x - 16038.0f/125.0f*x*x + 268272.0f/125.0f*x*x*x - 629856.0f/125.0f*x*x*x*x;
		// Put the output in scale:
		return x*0.5f + 0.5f;
	}
	
	/**
	 * Update one region that intersects the displaced region in a rectangle of size xFac×yFac.
	 * @param ρ Density of the displaced region.
	 * @param vx x-velocity of the displaced region.
	 * @param vy y-velocity of the displaced region.
	 * @param temperature of the displaced region.
	 * @param humidity of the displaced region.
	 * @param aρ next iteration density array.
	 * @param dx next iteration vx array.
	 * @param dy next iteration vy array.
	 * @param dT next iteration temperature array.
	 * @param dH next iteration humidity array.
	 * @param x coordinate of this region
	 * @param y coordinate of this region
	 * @param xFac
	 * @param yFac
	 */
	private static void update(float ρ, float vx, float vy, float temperature, float humidity, float[][] aρ, float[][] dx, float[][] dy, float[][] dT, float[][] dH, int x, int y, float xFac, float yFac) {
		float factor = ρ*xFac*yFac;
		aρ[x][y] += factor;
		dx[x][y] += vx*factor;
		dy[x][y] += vy*factor;
		dT[x][y] += temperature*factor;
		dH[x][y] += humidity*factor;
	}
	
	public static int mod(int x, int mod) {
		x %= mod;
		if(x < 0) x += mod;
		return x;
	}
	
	public static float mod(float x, int mod) {
		x %= mod;
		if(x < 0) x += mod;
		return x;
	}
	
	
	// Stuff used to test and render the map to file:
	private static void render(Biome.Type[][] map, int width, int height) {
		BufferedImage img = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
		for(int i = 0; i < width; i++) {
			for(int j = 0; j < height; j++) {
				draw(map[i][j], i, j, img);
			}
		}
		// Save the image:
		try {
			File outputfile = new File("image.png");
			ImageIO.write(img, "png", outputfile);
		} catch(Exception e) {
			e.printStackTrace();
		}
	}
	
	public static void draw(Biome.Type value, int x, int y, BufferedImage img) {
		int color;
		switch(value) {
			case ARCTIC_OCEAN:
				color = 0xa0a0ff;
				break;
			case DESERT:
				color = 0xffff30;
				break;
			case FOREST:
				color = 0x009000;
				break;
			case GLACIER:
				color = 0xffffff;
				break;
			case GRASSLAND:
				color = 0x00c000;
				break;
			case MOUNTAIN_FOREST:
				color = 0x80e080;
				break;
			case MOUNTAIN_GRASSLAND:
				color = 0xb0d090;
				break;
			case OCEAN:
				color = 0x0060a0;
				break;
			case PEAK:
				color = 0xaaaaaa;
				break;
			case RAINFOREST:
				color = 0x50c000;
				break;
			case SHRUBLAND:
				color = 0xcc9900;
				break;
			case SWAMP:
				color = 0x305030;
				break;
			case TAIGA:
				color = 0x009060;
				break;
			case TRENCH:
				color = 0x000030;
				break;
			case TUNDRA:
				color = 0xaabbaa;
				break;
			case WARM_OCEAN:
				color = 0x008090;
				break;
			case ETERNAL_DARKNESS:
				color = 0x000000;
				break;
			default:
				color = 0;
				break;
		}
		img.setRGB(x, y, color);
	}
}
