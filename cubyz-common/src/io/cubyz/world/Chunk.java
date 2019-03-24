 package io.cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3i;

import io.cubyz.api.CubzRegistries;
import io.cubyz.api.Registry;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.Ore;
import io.cubyz.modding.ModLoader;

public class Chunk {

	private BlockInstance[][][] inst;
	private ArrayList<BlockInstance> list = new ArrayList<>();
	private int ox, oy;
	private boolean generated;
	private boolean loaded;
	
	private static Registry<Block> br =  CubzRegistries.BLOCK_REGISTRY; // shortcut to BLOCK_REGISTRY
	
	// Normal:
	private static Block grass = br.getByID("cubyz:grass");
	private static Block sand = br.getByID("cubyz:sand");
	private static Block snow = br.getByID("cubyz:snow");
	private static Block dirt = br.getByID("cubyz:dirt");
	private static Block stone = br.getByID("cubyz:stone");
	private static Block bedrock = br.getByID("cubyz:bedrock");
	
	// Ores:
	private static ArrayList<Ore> ores = new ArrayList<>();
	static {
		ores.add((Ore) br.getByID("cubyz:coal_ore"));
		ores.add((Ore) br.getByID("cubyz:iron_ore"));
		ores.add((Ore) br.getByID("cubyz:ruby_ore"));
		ores.add((Ore) br.getByID("cubyz:gold_ore"));
		ores.add((Ore) br.getByID("cubyz:diamond_ore"));
		ores.add((Ore) br.getByID("cubyz:emerald_ore"));
	}
	
	// Liquids:
	private static Block water = br.getByID("cubyz:water");
	
	public static final int SEA_LEVEL = 100;
	
	private World world;
	
	public Chunk(int ox, int oy, World world) {
		this.ox = ox;
		this.oy = oy;
		this.world = world;
	}
	
	public void setLoaded(boolean loaded) {
		this.loaded = loaded;
	}
	
	public boolean isLoaded() {
		return loaded;
	}
	
	public int getX() {
		return ox;
	}
	
	public int getZ() {
		return oy;
	}
	
	public ArrayList<BlockInstance> list() {
		return list;
	}
	
	/**
	 * Add the <code>Block</code> b at relative space defined by X, Y, and Z, and if out of bounds, call this method from the other chunk (only work for 1 chunk radius)<br/>
	 * Meaning that if x or z are out of bounds, this method will call the same method from other chunks to add it.
	 * @param b
	 * @param x
	 * @param y
	 * @param z
	 */
	public void addBlock(Block b, int x, int y, int z) {
		if(y >= World.WORLD_HEIGHT)
			return;
		int rx = x - (ox << 4);
		if (rx < 0) {
			// Determines if the block is part of another chunk.
			world.getChunk(ox - 1, oy).addBlock(b, x, y, z);
			return;
		}
		if (rx > 15) {
			world.getChunk(ox + 1, oy).addBlock(b, x, y, z);
			return;
		}
		int rz = z - (oy << 4);
		if (rz < 0) {
			world.getChunk(ox, oy - 1).addBlock(b, x, y, z);
			return;
		}
		if (rz > 15) {
			world.getChunk(ox, oy + 1).addBlock(b, x, y, z);
			return;
		}
		if (world.getBlock(x, y, z) != null) {
			return;
		}
		BlockInstance inst0 = new BlockInstance(b);
		inst0.setPosition(new Vector3i(x, y, z));
		inst0.setWorld(world);
		list.add(inst0);
		if(inst == null) {
			inst = new BlockInstance[16][World.WORLD_HEIGHT][16];
		}
		inst[rx][y][rz] = inst0;
		world.markEdit();
		if(loaded) {
			BlockInstance[] neighbors = inst0.getNeighbors();
			for (int i = 0; i < neighbors.length; i++) {
				if (neighbors[i] == null) {
					world.visibleBlocks().get(inst0.getBlock()).add(inst0);
					break;
				}
			}
			for (int i = 0; i < neighbors.length; i++) {
				if (neighbors[i] != null && world.visibleBlocks().get(neighbors[i].getBlock()).contains(neighbors[i])) {
					BlockInstance[] neighbors1 = neighbors[i].getNeighbors();
					boolean vis = true;
					for (int j = 0; j < neighbors.length; j++) {
						if (neighbors[j] == null) {
							vis = false;
							break;
						}
					}
					if(vis) {
						world.visibleBlocks().get(neighbors[i].getBlock()).remove(neighbors[i]);
					}
				}
			}
		}
	}
	
	//TODO: Take in consideration caves.
	//TODO: Ore Clusters
	//TODO: Finish vegetation
	//TODO: Clean this method
	public void generateFrom(float[][] map, float[][] vegetation, float[][] oreMap, float[][] heatMap) {
		if(inst == null) {
			inst = new BlockInstance[16][World.WORLD_HEIGHT][16];
		}
		int wx = ox << 4;
		int wy = oy << 4;
		
		// heightmap pass
		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				float value = map[px][py];
				int y = (int) (value * World.WORLD_HEIGHT);
				if(y == World.WORLD_HEIGHT)
					y--;
				int temperature = (int)((2-value+SEA_LEVEL/(float)World.WORLD_HEIGHT)*heatMap[px][py]*120) - 100;
				for (int j = y > SEA_LEVEL ? y : SEA_LEVEL; j >= 0; j--) {
					BlockInstance bi = null;
					if(j > y) {
						bi = new BlockInstance(water);
					}else if ((y < SEA_LEVEL + 4 || temperature > 40) && j > y - 3) {
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
						bi = selectOre(rand, j);
					} else {
						bi = new BlockInstance(bedrock);
					}
					bi.setPosition(new Vector3i(wx + px, j, wy + py));
					bi.setWorld(world);
					//world.blocks().add(bi);
					list.add(bi);
					inst[px][j][py] = bi;
					/*if (bi.getBlock() instanceof IBlockEntity) {
						updatables.add(bi);
					}*/
				}
				world.markEdit();
			}
		}
		
		// Vegetation pass
		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				float value = vegetation[px][py];
				int incx = px == 0 ? 1 : -1;
				int incy = py == 0 ? 1 : -1;
				int temperature = (int)((2-map[px][py]+SEA_LEVEL/(float)World.WORLD_HEIGHT)*heatMap[px][py]*120) - 100;
				if (temperature < 40 && map[px][py] * World.WORLD_HEIGHT >= SEA_LEVEL + 3 && value > 0.5f && ((int)((vegetation[px][py]-vegetation[px+incx][py+incy]) * 100000000) & 63) == 1) {	// "&(2^n - 1)" is a faster way to do "%(2^n)"
					Structures.generateTree(this, wx + px, (int) (map[px][py] * World.WORLD_HEIGHT) + 1, wy + py);
				}
			}
		}
		generated = true;
	}
	
	// Loads the chunk
	public void load() {
		loaded = true;
		int wx = ox << 4;
		int wy = oy << 4;
		boolean chx0 = world.getChunk(ox - 1, oy).isGenerated();
		boolean chx1 = world.getChunk(ox + 1, oy).isGenerated();
		boolean chy0 = world.getChunk(ox, oy - 1).isGenerated();
		boolean chy1 = world.getChunk(ox, oy + 1).isGenerated();
		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				for (int j = world.WORLD_HEIGHT - 1; j >= 0; j--) {
					if (inst[px][j][py] == null) {
						continue;
					}
					BlockInstance[] neighbors = inst[px][j][py].getNeighbors();
					for (int i = 0; i < neighbors.length; i++) {
						if (neighbors[i] == null 	&& (j != 0 || i != 4)
													&& (px != 0 || i != 0 || chx0)
													&& (px != 15 || i != 1 || chx1)
													&& (py != 0 || i != 3 || chy0)
													&& (py != 15 || i != 2 || chy1)) {
							world.visibleBlocks().get(inst[px][j][py].getBlock()).add(inst[px][j][py]);
							break;
						}
					}
				}
				// Checks if blocks from neighboring chunks are changed
				int [] neighbor = {1, 0, 2, 3};
				int [] dx = {-1, 16, px, px};
				int [] dy = {py, py, -1, 16};
				boolean [] toCheck = {
						chx0 && px == 0,
						chx1 && px == 15,
						chy0 && py == 0,
						chy1 && py == 15};
				for(int k = 0; k < 4; k++) {
					if (toCheck[k]) {
						for (int j = World.WORLD_HEIGHT - 1; j >= 0; j--) {
							BlockInstance inst0 = world.getBlock(wx + dx[k], j, wy + dy[k]);
							if(inst0 == null) {
								continue;
							}
							if(world.visibleBlocks().get(inst0.getBlock()).contains(inst0)) {
								continue;
							}
							if (inst0.getNeighbor(neighbor[k]) == null) {
								world.visibleBlocks().get(inst0.getBlock()).add(inst0);
								continue;
							}
						}
					}
				}
				world.markEdit();
			}
		}
	}
	
	// This function only allows a less than 50% of the underground to be ores.
	public BlockInstance selectOre(float rand, int height) {
		float chance1 = 0.0F;
		float chance2 = 0.0F;
		for (Ore ore : ores) {
			chance2 += ore.getChance();
			if(height < ore.getHeight() && rand > chance1 && rand < chance2)
				return new BlockInstance(ore);
			chance1 += ore.getChance();
		}
		return new BlockInstance(stone);
	}
	
	public boolean isGenerated() {
		return generated;
	}
	
	public BlockInstance getBlockInstanceAt(int x, int y, int z) {
		try {
			return inst[x][y][z];
		} catch (Exception e) {
			return null;
		}
	}
	
	public void _removeBlockAt(int x, int y, int z) {
		BlockInstance bi = getBlockInstanceAt(x, y, z);
		world.visibleBlocks().get(bi.getBlock()).remove(bi);
		inst[x][y][z] = null;
	}
	
	public boolean _c(BlockInstance c) {
		for (Block bs : world.visibleBlocks().keySet()) {
			for (BlockInstance bi : world.visibleBlocks().get(bs)) {
				if (bi == c) {
					return true;
				}
			}
		}
		return false;
	}
	
	public void removeBlockAt(int x, int y, int z) {
		BlockInstance bi = getBlockInstanceAt(x, y, z);
		if (bi != null) {
			world.visibleBlocks().get(bi.getBlock()).remove(bi);
			inst[x][y][z] = null;
			// 0 = EAST  (x - 1)
			// 1 = WEST  (x + 1)
			// 2 = NORTH (z + 1)
			// 3 = SOUTH (z - 1)
			// 4 = DOWN
			// 5 = UP
			BlockInstance[] neighbors = bi.getNeighbors();
			for (int i = 0; i < neighbors.length; i++) {
				BlockInstance inst = neighbors[i];
				//System.out.println(i + ": " + inst);
				if (inst != null && inst != bi) {
					if (!_c(inst)) {
						world.visibleBlocks().get(inst.getBlock()).add(inst);
					}
				}
			}
			world.markEdit();
			inst[x][y][z] = null;
		}
	}
	
}
