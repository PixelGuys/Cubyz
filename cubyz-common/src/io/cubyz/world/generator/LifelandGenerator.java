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

	private static Registry<Block> br =  CubyzRegistries.BLOCK_REGISTRY; // shortcut to BLOCK_REGISTRY
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
	public static Ore [] ores;
	public static float [] oreChances;
	public static int [] oreHeights;
	
	public static void init(Ore [] ores) {
		oreChances = new float[ores.length+1];
		oreHeights = new int[ores.length];
		for(int i = 0; i < ores.length; i++) {
			oreHeights[i] = ores[i].getHeight();
		}
		// (Selection-)Sort the ores by height to accelerate selectOre
		for(int i = 0; i < oreHeights.length; i++) {
			int lowest = i;
			for(int j = i+1; j < oreHeights.length; j++) {
				if(oreHeights[j] < oreHeights[lowest])
					lowest = j;
			}
			Ore ore = ores[lowest];
			int height = oreHeights[lowest];
			ores[lowest] = ores[i];
			oreHeights[lowest] = oreHeights[i];
			ores[i] = ore;
			oreHeights[i] = height;
		}
		for(int i = 0; i < ores.length; i++) {
			oreChances[i+1] = oreChances[i] + ores[i].getChance();
		}
		LifelandGenerator.ores = ores;
	}
	
	// This function only allows less than 50% of the underground to be ores.
	public static BlockInstance selectOre(float rand, int height, Block undergroundBlock) {
		if(rand >= oreChances[oreHeights.length])
			return new BlockInstance(undergroundBlock);
		for (int i = oreChances.length - 2; i >= 0; i--) {
			if(height > oreHeights[i])
				break;
		if(rand >= oreChances[i])
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
		float[][] vegetationMap = Noise.generateMapFragment(wx, wy, 16, 16, 128, seed + 3 * (seed + 1 & Integer.MAX_VALUE));
		float[][] oreMap = Noise.generateMapFragment(wx, wy, 16, 16, 128, seed - 3 * (seed - 1 & Integer.MAX_VALUE));
		float[][] heatMap = Noise.generateMapFragment(wx, wy, 16, 16, 4096, seed ^ 123456789);
		boolean[][][] caves = generateCaves(ch, ox, oy, seed); 
		
		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				float value = heightMap[px][py];
				int y = (int) (value * world.getHeight());
				if(y == world.getHeight())
					y--;
				int temperature = (int)((2-value+SEA_LEVEL/(float)world.getHeight())*heatMap[px][py]*120) - 100;
				for (int j = y > SEA_LEVEL ? y : SEA_LEVEL; j >= 0; j--) {
					BlockInstance bi = null;
					if(!caves[px][py][j]) {
						// Don't add anything if in a cave.
					} else if(j > y) {
						if (temperature <= 0 && j == SEA_LEVEL) {
							bi = new BlockInstance(ice);
						} else {
							bi = new BlockInstance(water);
						}
					} else if (((y < SEA_LEVEL + 4 && temperature > 5) || temperature > 40 || y < SEA_LEVEL) && j > y - 3) {
						bi = new BlockInstance(sand);
					} else if (j == y) {
						if(temperature > 0) {
							bi = new BlockInstance(grass);
						} else {
							bi = new BlockInstance(snow);
						}
					} else if (j > y - 3) {
						bi = new BlockInstance(dirt);
					} else if (j > 0) {
						float rand = oreMap[px][py] * j * (256 - j) * (128 - j) * 6741;
						rand = (((int) rand) & 8191) / 8191.0F;
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
				int temperature = (int)((2-heightMap[px][py]+SEA_LEVEL/(float)world.getHeight())*heatMap[px][py]*120) - 100;
				if (heightMap[px][py] * world.getHeight() >= SEA_LEVEL + 4) {
					//if (value < 0) value = 0;
					Structures.generateVegetation(ch, wx + px, (int) (heightMap[px][py] * world.getHeight()) + 1, wy + py, value, temperature, (int)((vegetationMap[px][py]-vegetationMap[px+incx][py+incy]) * 100000000 + incx + incy));
				}
			}
		}
		
		ch.applyBlockChanges();
	}

	// Use cellular automata and a few noise maps to generate seemingly good caves:
	private boolean[][][] generateCaves(Chunk ch, int cx, int cy, int seed) {
		// Generate a noise map for each of the chunk walls:
		// TODO: Make the maps of x and y depend on each other.
		float[][] mapy0 = Noise.generateMapFragment(cx << 4, 0, 16, 256, 64, seed + cy*123456789);
		float[][] mapx0 = Noise.generateMapFragment(cy << 4, 0, 16, 256, 64, seed + cx*987654321);
		float[][] mapy1 = Noise.generateMapFragment((cx << 4), 0, 16, 256, 64, seed + (cy+1)*123456789);
		float[][] mapx1 = Noise.generateMapFragment((cy << 4), 0, 16, 256, 64, seed + (cx+1)*987654321);
		Random r = new Random(seed+cx*573923+cy*29104);
		float chance = 0.34f;
		// generate a random map of automata filled with 50% empty spaces:
		boolean[][][] automata = new boolean[16][16][256]; // x, y, h
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				for(int h = 1; h < 255; h++) {
					if(x == 0 && y == 0) {
						automata[x][y][h] = (mapx0[y][h]+mapy0[x][h]) > chance*2;
					} else if(x == 0) {
						automata[x][y][h] = mapx0[y][h] > chance;
						if(y == 15)
							automata[x][y][h] = (mapx0[y][h]+mapy1[x][h]) > chance*2;
					} else if(y == 0) {
						automata[x][y][h] = mapy0[x][h] > chance;
						if(x == 15)
							automata[x][y][h] = (mapx1[y][h]+mapy0[x][h]) > chance*2;
					} else if(x == 15 && y == 15) {
						automata[x][y][h] = (mapx1[y][h]+mapy1[x][h]) > chance*2;
					} else if(x == 15) {
						automata[x][y][h] = mapx1[y][h] > chance;
					} else if(y == 15) {
						automata[x][y][h] = mapy1[x][h] > chance;
					} else {
						automata[x][y][h] = r.nextBoolean();
					}
				}
				// Put all walls at the bottom and empty spaces at the top
				automata[x][y][0] = true;
				automata[x][y][255] = true;
			}
		}
		chance = 1-chance;
		
		// Iterate through the automata a couple of times.
		for(int i = 0; i < 7; i++) {
			boolean[][][] toggleMap = new boolean[16][16][256]; // x, y, h
			int min = ((i & 1) == 1) ? 0 : 1;
			int max = 16-min;
			for(int x = min; x < max; x++) {
				for(int y = min; y < max; y++) {
					for(int h = 1; h < 255; h++) {
						int walls = 0; // How many walls are neighboring this block.
						if(automata[x][y][h-1]) // down
							walls += 2; // Direct neighbors have more impact.
						if(automata[x][y][h+1]) // up
							walls += 2; // Direct neighbors have more impact.
						// x-1:
						if(x > 0) {
							if(automata[x-1][y][h]) // same h
								walls += 2; // Direct neighbors have more impact.
							if(automata[x-1][y][h-1]) // down
								walls++;
							if(automata[x-1][y][h+1]) // up
								walls++;
						} else { // at the chunk borders use the noise map:
							if(mapx0[y][h] < chance) // same h
								walls += 2; // Direct neighbors have more impact.
							if(mapx0[y][h-1] < chance) // down
								walls++;
							if(mapx0[y][h+1] < chance) // up
								walls++;
						}
						// x+1
						if(x < 15) {
							if(automata[x+1][y][h]) // same h
								walls += 2; // Direct neighbors have more impact.
							if(automata[x+1][y][h-1]) // down
								walls++;
							if(automata[x+1][y][h+1]) // up
								walls++;
						} else { // at the chunk borders use the noise map:
							if(mapx1[y][h] < chance) // same h
								walls += 2; // Direct neighbors have more impact.
							if(mapx1[y][h-1] < chance) // down
								walls++;
							if(mapx1[y][h+1] < chance) // up
								walls++;
						}
						// y-1
						if(y > 0) {
							if(automata[x][y-1][h]) // same h
								walls += 2; // Direct neighbors have more impact.
							if(automata[x][y-1][h-1]) // down
								walls++;
							if(automata[x][y-1][h+1]) // up
								walls++;
						} else { // at the chunk borders use the noise map:
							if(mapy0[x][h] < chance) // same h
								walls += 2; // Direct neighbors have more impact.
							if(mapy0[x][h-1] < chance) // down
								walls++;
							if(mapy0[x][h+1] < chance) // up
								walls++;
						}
						// y+1
						if(y < 15) {
							if(automata[x][y+1][h]) // same h
								walls += 2; // Direct neighbors have more impact.
							if(automata[x][y+1][h-1]) // down
								walls++;
							if(automata[x][y+1][h+1]) // up
								walls++;
						} else { // at the chunk borders use the noise map:
							if(mapy1[x][h] < chance) // same h
								walls += 2; // Direct neighbors have more impact.
							if(mapy1[x][h-1] < chance) // down
								walls++;
							if(mapy1[x][h+1] < chance) // up
								walls++;
						}
						// x-1, y-1
						if(x > 0 && y > 0) {
							if(automata[x-1][y-1][h]) // same h
								walls++;
							if(automata[x-1][y-1][h-1]) // down
								walls++;
							if(automata[x-1][y-1][h+1]) // up
								walls++;
						} else if(y > 0) { // at the chunk borders use the noise map:
							if(mapx0[y-1][h] < chance) // same h
								walls++;
							if(mapx0[y-1][h-1] < chance) // down
								walls++;
							if(mapx0[y-1][h+1] < chance) // up
								walls++;
						} else if(x > 0) { // at the chunk borders use the noise map:
							if(mapy0[x-1][h] < chance) // same h
								walls++;
							if(mapy0[x-1][h-1] < chance) // down
								walls++;
							if(mapy0[x-1][h+1] < chance) // up
								walls++;
						} else { // at the chunk edges use an interpolation between the noise maps:
							if((mapx0[y][h]+mapy0[x][h])/2 < chance) // same h
								walls++;
							if((mapx0[y][h-1]+mapy0[x][h-1])/2 < chance) // down
								walls++;
							if((mapx0[y][h+1]+mapy0[x][h+1])/2 < chance) // up
								walls++;
						}
						// x-1, y+1
						if(x > 0 && y < 15) {
							if(automata[x-1][y+1][h]) // same h
								walls++;
							if(automata[x-1][y+1][h-1]) // down
								walls++;
							if(automata[x-1][y+1][h+1]) // up
								walls++;
						} else if(y < 15) { // at the chunk borders use the noise map:
							if(mapx0[y+1][h] < chance) // same h
								walls++;
							if(mapx0[y+1][h-1] < chance) // down
								walls++;
							if(mapx0[y+1][h+1] < chance) // up
								walls++;
						} else if(x > 0) { // at the chunk borders use the noise map:
							if(mapy1[x-1][h] < chance) // same h
								walls++;
							if(mapy1[x-1][h-1] < chance) // down
								walls++;
							if(mapy1[x-1][h+1] < chance) // up
								walls++;
						} else { // at the chunk edges use an interpolation between the noise maps:
							if((mapx0[y][h]+mapy1[x][h])/2 < chance) // same h
								walls++;
							if((mapx0[y][h-1]+mapy1[x][h-1])/2 < chance) // down
								walls++;
							if((mapx0[y][h+1]+mapy1[x][h+1])/2 < chance) // up
								walls++;
						}
						// x+1, y-1
						if(x < 15 && y > 0) {
							if(automata[x+1][y-1][h]) // same h
								walls++;
							if(automata[x+1][y-1][h-1]) // down
								walls++;
							if(automata[x+1][y-1][h+1]) // up
								walls++;
						} else if(y > 0) { // at the chunk borders use the noise map:
							if(mapx1[y-1][h] < chance) // same h
								walls++;
							if(mapx1[y-1][h-1] < chance) // down
								walls++;
							if(mapx1[y-1][h+1] < chance) // up
								walls++;
						} else if(x < 15) { // at the chunk borders use the noise map:
							if(mapy0[x+1][h] < chance) // same h
								walls++;
							if(mapy0[x+1][h-1] < chance) // down
								walls++;
							if(mapy0[x+1][h+1] < chance) // up
								walls++;
						} else { // at the chunk edges use an interpolation between the noise maps:
							if((mapx1[y][h]+mapy0[x][h])/2 < chance) // same h
								walls++;
							if((mapx1[y][h-1]+mapy0[x][h-1])/2 < chance) // down
								walls++;
							if((mapx1[y][h+1]+mapy0[x][h+1])/2 < chance) // up
								walls++;
						}
						// x+1, y+1
						if(x < 15 && y < 15) {
							if(automata[x+1][y+1][h]) // same h
								walls++;
							if(automata[x+1][y+1][h-1]) // down
								walls++;
							if(automata[x+1][y+1][h+1]) // up
								walls++;
						} else if(y < 15) { // at the chunk borders use the noise map:
							if(mapx1[y+1][h] < chance) // same h
								walls++;
							if(mapx1[y+1][h-1] < chance) // down
								walls++;
							if(mapx1[y+1][h+1] < chance) // up
								walls++;
						} else if(x < 15) { // at the chunk borders use the noise map:
							if(mapy1[x+1][h] < chance) // same h
								walls++;
							if(mapy1[x+1][h-1] < chance) // down
								walls++;
							if(mapy1[x+1][h+1] < chance) // up
								walls++;
						} else { // at the chunk edges use an interpolation between the noise maps:
							if((mapx1[y][h]+mapy1[x][h])/2 < chance) // same h
								walls++;
							if((mapx1[y][h-1]+mapy1[x][h-1])/2 < chance) // down
								walls++;
							if((mapx1[y][h+1]+mapy1[x][h+1])/2 < chance) // up
								walls++;
						}
						if(i < 6)
							toggleMap[x][y][h] = (walls > 17 || (walls > 12 && automata[x][y][h]))^automata[x][y][h];
						else // Clean sharp edges in the last run:
							toggleMap[x][y][h] = (walls > 28 || (walls > 5 && automata[x][y][h]))^automata[x][y][h];
							
					}
				}
			}
			for(int x = min; x < max; x++) {
				for(int y = min; y < max; y++) {
					for(int h = 1; h < 255; h++) {
						automata[x][y][h] = automata[x][y][h]^toggleMap[x][y][h];
					}
				}
			}
		}
		return automata;
	}

}
