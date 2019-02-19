 package io.spacycubyd.world;

import org.joml.Vector3i;

import io.spacycubyd.blocks.Block;
import io.spacycubyd.blocks.BlockInstance;
import io.spacycubyd.modding.ModLoader;

public class Chunk {

	private BlockInstance[][][] inst;
	private int ox, oy;
	private boolean generated;
	private static Block grassBlock = ModLoader.block_registry.getByID("cubz:grass");
	private static Block dirtBlock = ModLoader.block_registry.getByID("cubz:dirt");
	private static Block water = ModLoader.block_registry.getByID("cubz:water");
	
	public static final int SEA_LEVEL = 67;
	
	private World world;
	
	public Chunk(int ox, int oy, World world) {
		this.ox = ox;
		this.oy = oy;
		this.world = world;
	}
	
	public int getX() {
		return ox;
	}
	
	public int getZ() {
		return oy;
	}
	
	public void generateFrom(float[][] map) {
		//System.out.println(dirtBlock);
		inst = new BlockInstance[16][255][16];
		for (int px = 0; px < 16; px++) {
			for (int py = 0; py < 16; py++) {
				float value = map[px][py];
				if (value < 0) {
					value -= value;
				}
				int y = (int) (value * World.WORLD_HEIGHT);
				if (y < SEA_LEVEL-1) {
					y = SEA_LEVEL-1;
				}
				for (int j = y; j > -1; j--) {
					if (j > SEA_LEVEL) {
						if (j == y) {
							inst[px][j][py] = new BlockInstance(grassBlock);
						} else {
							inst[px][j][py] = new BlockInstance(dirtBlock);
						}
					} else {
						inst[px][j][py] = new BlockInstance(water);
					}
					BlockInstance bi = inst[px][j][py];
					bi.setPosition(new Vector3i(ox * 16 + px, j, oy * 16 + py));
					bi.setWorld(world);
					world.blocks().add(inst[px][j][py]);
					if (j < 255) {
						BlockInstance is = inst[px][j+1][py];
						if (is != null) {
							if (is.getBlock().isTransparent()) {
								world.visibleBlocks().get(bi.getBlock()).add(bi);
							}
						} else {
							world.visibleBlocks().get(bi.getBlock()).add(bi);
						}
					}
				}
				world.markEdited();
			}
		}
		
		generated = true;
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
		world.blocks().remove(bi);
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
			world.blocks().remove(bi);
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
			world.markEdited();
			inst[x][y][z] = null;
		}
	}
	
}
