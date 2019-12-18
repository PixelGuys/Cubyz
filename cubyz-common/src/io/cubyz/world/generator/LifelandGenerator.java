package io.cubyz.world.generator;

import java.util.Random;

import org.joml.Vector3i;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Registry;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.Ore;
import io.cubyz.world.Chunk;
import io.cubyz.world.Noise;
import io.cubyz.world.Structures;
import io.cubyz.world.World;

//TODO: Add caves
//TODO: Ore Clusters
//TODO: Finish vegetation
//TODO: Clean `generate` method
//		↓↑
//TODO: Mod access
//TODO: Add more diversity

/**
 * Yep, Cubyz's world is called Lifeland
 */
public class LifelandGenerator extends WorldGenerator {

	private static Registry<Block> br = CubyzRegistries.BLOCK_REGISTRY; // shortcut to BLOCK_REGISTRY
	private static Block grass = br.getByID("cubyz:grass");
	private static Block sand = br.getByID("cubyz:sand");
	private static Block snow = br.getByID("cubyz:snow");
	private static Block dirt = br.getByID("cubyz:dirt");
	private static Block ice = br.getByID("cubyz:ice");
	private static Block stone = br.getByID("cubyz:stone");
	private static Block bedrock = br.getByID("cubyz:bedrock");

	// Liquid
	public static final int SEA_LEVEL = 100;
	private static Block water = br.getByID("cubyz:water");

	// Ore Utilities
	public static Ore[] ores;
	public static float[] oreChances;
	public static int[] oreHeights;

	public static void init(Ore[] ores) {
		oreChances = new float[ores.length + 1];
		oreHeights = new int[ores.length];
		for (int i = 0; i < ores.length; i++) {
			oreHeights[i] = ores[i].getHeight();
		}
		// (Selection-)Sort the ores by height to accelerate selectOre
		for (int i = 0; i < oreHeights.length; i++) {
			int lowest = i;
			for (int j = i + 1; j < oreHeights.length; j++) {
				if (oreHeights[j] < oreHeights[lowest])
					lowest = j;
			}
			Ore ore = ores[lowest];
			int height = oreHeights[lowest];
			ores[lowest] = ores[i];
			oreHeights[lowest] = oreHeights[i];
			ores[i] = ore;
			oreHeights[i] = height;
		}
		for (int i = 0; i < ores.length; i++) {
			oreChances[i + 1] = oreChances[i] + ores[i].getChance();
		}
		LifelandGenerator.ores = ores;
	}

	// This function only allows less than 50% of the underground to be ores.
	public static BlockInstance selectOre(float rand, int height, Block undergroundBlock) {
		if (rand >= oreChances[oreHeights.length])
			return new BlockInstance(undergroundBlock);
		for (int i = oreChances.length - 2; i >= 0; i--) {
			if (height > oreHeights[i])
				break;
			if (rand >= oreChances[i])
				return new BlockInstance(ores[i]);
		}
		return new BlockInstance(undergroundBlock);
	}

	@Override
	public void generate(Chunk ch, World world) {
		int ox = ch.getX();
		int oy = ch.getZ();
		int wx = ox << 4;
		int wy = oy << 4;
		int seed = world.getSeed();
		float[][] heightMap = Noise.generateMapFragment(wx, wy, 16, 16, 256, seed);
		float[][] vegetationMap = Noise.generateMapFragment(wx, wy, 16, 16, 128,
				seed + 3 * (seed + 1 & Integer.MAX_VALUE));
		float[][] oreMap = Noise.generateMapFragment(wx, wy, 16, 16, 128, seed - 3*(seed - 1 & Integer.MAX_VALUE));
		float[][] heatMap = Noise.generateMapFragment(wx, wy, 16, 16, 4096, seed ^ 123456789);
		boolean[][][] caves = generate(seed, ox, oy);

		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				float value = heightMap[px][py];
				int y = (int) (value * world.getHeight());
				if (y == world.getHeight())
					y--;
				int temperature = (int) ((2 - value + SEA_LEVEL / (float) world.getHeight())*heatMap[px][py] * 120)
						- 100;
				for (int j = y > SEA_LEVEL ? y : SEA_LEVEL; j >= 0; j--) {
					BlockInstance bi = null;
					if (caves[px][py][j]) {
						// Don't add anything if in a cave.
					} else if (j > y) {
						if (temperature <= 0 && j == SEA_LEVEL) {
							bi = new BlockInstance(ice);
						} else {
							bi = new BlockInstance(water);
						}
					} else if (((y < SEA_LEVEL + 4 && temperature > 5) || temperature > 40 || y < SEA_LEVEL)
							&& j > y - 3) {
						bi = new BlockInstance(sand);
					} else if (j == y) {
						if (temperature > 0) {
							bi = new BlockInstance(grass);
						} else {
							bi = new BlockInstance(snow);
						}
					} else if (j > y - 3) {
						bi = new BlockInstance(dirt);
					} else if (j > 0) {
						float rand = oreMap[px][py]*j*(256 - j)*(128 - j)*6741;
						rand = (((int) rand) & 8191)/8191.0F;
						bi = selectOre(rand, j, stone);
					} else {
						bi = new BlockInstance(bedrock);
					}
					if (bi != null) {
						bi.setPosition(new Vector3i(wx + px, j, wy + py));
						ch.rawAddBlock(px, j, py, bi);
						if (bi.getBlock() != null && bi.getBlock().hasBlockEntity()) {
							ch.blockEntities().put(bi, bi.getBlock().createBlockEntity(bi.getPosition()));
						}
					}
				}
			}
		}

		// Vegetation pass
		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				float value = vegetationMap[px][py];
				int incx = px == 0 ? 1 : -1;
				int incy = py == 0 ? 1 : -1;
				int temperature = (int) ((2 - heightMap[px][py] + SEA_LEVEL / (float) world.getHeight())*heatMap[px][py]*120) - 100;
				if (heightMap[px][py]*world.getHeight() >= SEA_LEVEL + 4) {
					// if (value < 0) value = 0;
					Structures.generateVegetation(ch, wx + px, (int) (heightMap[px][py] * world.getHeight()) + 1,
							wy + py, value, temperature,
							(int) ((vegetationMap[px][py] - vegetationMap[px + incx][py + incy]) * 100000000 + incx
									+ incy));
				}
			}
		}

		ch.applyBlockChanges();
	}

	private static int range = 8;
	private Random rand;

	private boolean[][][] generate(int seed, int cx, int cy) {
		boolean[][][] caveMap = new boolean[16][16][256];
		rand = new Random(seed);
		long rand1 = rand.nextLong();
		long rand2 = rand.nextLong();

		for (int x = cx - range; x <= cx + range; ++x) {
			for (int y = cy - range; y <= cy + range; ++y) {
				long randX = (long) x * rand1;
				long randY = (long) y * rand2;
				rand.setSeed(randX ^ randY ^ seed);
				considerCoordinates(x, y, cx, cy, caveMap);
			}
		}
		return caveMap;
	}

	private void createJunction(long random, int cx, int cy, boolean[][][] caveMap, double worldX, double worldH, double worldY) {
		this.generateCave(random, cx, cy, caveMap, worldX, worldH, worldY, 1.0F + rand.nextFloat() * 6, 0, 0, -1, 0, 0.5);
	}

	private void generateCave(long random, int cx, int cy, boolean[][][] caveMap, double worldX, double worldH, double worldY, float p_151541_12_, float direction, float slope, int curStep, int caveLength, double caveHeightModifier) {
		double cwx = (double) (cx*16 + 8);
		double cwy = (double) (cy*16 + 8);
		float directionModifier = 0.0F;
		float slopeModifier = 0.0F;
		Random localRand = new Random(random);
		// Choose a random cave length if not specified:
		if(caveLength == 0) {
			int local = range*16 - 16;
			caveLength = local - localRand.nextInt(local / 4);
		}

		boolean junctionRoom = false;

		if (curStep == -1) { // Halve the cave length and go to junction mode.
			curStep = caveLength / 2;
			junctionRoom = true;
		}

		int var27 = localRand.nextInt(caveLength / 2) + caveLength / 4;

		for (boolean highSlope = localRand.nextInt(6) == 0; curStep < caveLength; ++curStep) {
			double xyscale = 1.5 + (double)(Math.sin((float)curStep * (float)Math.PI / (float)caveLength)*p_151541_12_);
			double hscale = xyscale * caveHeightModifier;
			// Move cave center point one unit into a direction given by slope and direction:
			float xzunit = (float)Math.cos(slope);
			float hunit = (float)Math.sin(slope);
			worldX += (double)(Math.cos(direction) * xzunit);
			worldH += (double)hunit;
			worldY += (double)(Math.sin(direction) * xzunit);

			if (highSlope) {
				slope *= 0.92F;
			} else {
				slope *= 0.7F;
			}

			slope += slopeModifier * 0.1F;
			direction += directionModifier * 0.1F;
			slopeModifier *= 0.9F;
			directionModifier *= 0.75F;
			slopeModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*2;
			directionModifier += (localRand.nextFloat() - localRand.nextFloat())*localRand.nextFloat()*4;

			if (!junctionRoom && curStep == var27 && p_151541_12_ > 1 && caveLength > 0) {
				this.generateCave(localRand.nextLong(), cx, cy, caveMap, worldX, worldH, worldY, localRand.nextFloat()*0.5F + 0.5F, direction - ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1);
				this.generateCave(localRand.nextLong(), cx, cy, caveMap, worldX, worldH, worldY, localRand.nextFloat()*0.5F + 0.5F, direction + ((float)Math.PI/2), slope/3.0F, curStep, caveLength, 1);
				return;
			}

			if (junctionRoom || localRand.nextInt(4) != 0) {
				double deltaX = worldX - cwx;
				double deltaY = worldY - cwy;
				double var39 = (double)(caveLength - curStep);
				double var41 = (double)(p_151541_12_ + 18);

				if (deltaX * deltaX + deltaY * deltaY - var39 * var39 > var41 * var41) {
					return;
				}

				if (worldX >= cwx - 16 - xyscale*2 && worldY >= cwy - 16 - xyscale*2 && worldX <= cwx + 16 + xyscale*2 && worldY <= cwy + 16 + xyscale*2) {
					// Determine min and max of the current cave segment in all directions.
					int xmin = (int) (Math.floor(worldX - xyscale) - cx*16 - 1);
					int xmax = (int) (Math.floor(worldX + xyscale) - cx*16 + 1);
					int hmin = (int)(worldH - 0.7*hscale - 0.5); // Make also sure the ground of the cave is kind of flat, so the player can easily walk through.
					int hmax = (int) (Math.floor(worldH + hscale) + 1);
					int ymin = (int) (Math.floor(worldY - xyscale) - cy*16 - 1);
					int ymax = (int) (Math.floor(worldY + xyscale) - cy*16 + 1);
					if (xmin < 0)
						xmin = 0;
					if (xmax > 16)
						xmax = 16;
					if (hmin < 1)
						hmin = 1; // Don't make caves in the bedrock layer.
					if (hmax > 248)
						hmax = 248;
					if (ymin < 0)
						ymin = 0;
					if (ymax > 16)
						ymax = 16;

					// Go through all blocks within range of the cave center and remove them if they
					// are within range of the center.
					for (int curX = xmin; curX < xmax; ++curX) {
						double distToCenterX = ((double) (curX + cx*16) + 0.5 - worldX) / xyscale;
						
						for (int curY = ymin; curY < ymax; ++curY) {
							double distToCenterY = ((double) (curY + cy*16) + 0.5 - worldY) / xyscale;
							int curHeightIndex = hmax;
							if (distToCenterX * distToCenterX + distToCenterY * distToCenterY < 1.0) {
								for (int curH = hmax - 1; curH >= hmin; --curH) {
									double distToCenterH = ((double) curH + 0.5 - worldH) / hscale;
									if (distToCenterX*distToCenterX + distToCenterH*distToCenterH + distToCenterY*distToCenterY < 1.0) {
										caveMap[curX][curY][curHeightIndex] = true;
									}
									--curHeightIndex;
								}
							}
						}
						// Make only one room when junction is made.
						if (junctionRoom) {
							break;
						}
					}
				}
			}
		}
	}

	private void considerCoordinates(int x, int y, int cx, int cy, boolean[][][] caveMap) {
		// Determine how many caves start in this chunk. Make sure the number is usually close to one, but can also rarely reach higher values.
		int caveSpawns = rand.nextInt(rand.nextInt(rand.nextInt(15) + 1) + 1);

		// Add a 5/6 chance to skip this chunk to make sure the underworld isn't flooded with caves.
		if (rand.nextInt(6) != 0) {
			caveSpawns = 0;
		}

		for (int j = 0; j < caveSpawns; ++j) {
			// Choose some in world coordinates to start generating:
			double worldX = (double)((x << 4) + rand.nextInt(16));
			double worldH = (double)rand.nextInt(rand.nextInt(200) + 8); // Make more caves on the bottom of the world.
			double worldY = (double)((y << 4) + rand.nextInt(16));
			// Randomly pick how many caves origin from this location and add a junction room if there are more than 2:
			int starters = 1+rand.nextInt(4);
			if (starters > 1) {
				this.createJunction(rand.nextLong(), cx, cy, caveMap, worldX, worldH, worldY);
			}

			for (int i = 0; i < starters; ++i) {
				float direction = rand.nextFloat()*(float)Math.PI*2.0F;
				float slope = (rand.nextFloat() - 0.5F)/4.0F;
				// Greatly increase the slope for a small amount of random caves:
				if(rand.nextInt(16) == 0) {
					slope *= 8.0F;
				}
				float var19 = rand.nextFloat()*2.0F + rand.nextFloat();

				if (rand.nextInt(10) == 0) {
					var19 *= rand.nextFloat()*rand.nextFloat()*3.0F + 1.0F;
				}

				this.generateCave(rand.nextLong(), cx, cy, caveMap, worldX, worldH, worldY, var19, direction, slope, 0, 0, 1);
			}
		}
	}
}
