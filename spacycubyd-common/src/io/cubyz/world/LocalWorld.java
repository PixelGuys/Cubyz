package io.cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.modding.ModLoader;

public class LocalWorld extends World {

	private String name;
	private int width, depth;
	private ArrayList<Chunk> chunks;
	private ArrayList<Entity> entities = new ArrayList<>();
	
	private ArrayList<BlockInstance> spatials = new ArrayList<>();
	private Map<Block, ArrayList<BlockInstance>> visibleSpatials = new HashMap<>();
	private boolean edited;
	private Player player;
	
	private int seed;
	
	@Override
	public boolean isEdited() {
		return edited;
	}
	
	@Override
	public void receivedEdited() {
		edited = false;
	}
	
	@Override
	public void markEdited() {
		edited = true;
	}
	
	public LocalWorld() {
		name = "World";
		width = 64;
		depth = 64;
		chunks = new ArrayList<>(); // 1024x1024 map
		entities.add(new Player(true));
	}
	
	@Override
	public Player getLocalPlayer() {
		if (player == null) {
			for (Entity en : entities) {
				if (en instanceof Player) {
					if (((Player) en).isLocal()) {
						player = (Player) en;
						player.setWorld(this);
						break;
					}
				}
			}
		}
		return player;
	}
	
	@Override
	public int getWidth() {
		return -1;
	}
	
	@Override
	public int getDepth() {
		return -1;
	}
	
	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	@Override
	public ArrayList<BlockInstance> blocks() {
		return spatials;
	}
	
	@Override
	public Map<Block, ArrayList<BlockInstance>> visibleBlocks() {
		return visibleSpatials;
	}
	
	public void unload(int x, int z) {
		Chunk ch = getChunk(x, z);
		if (ch.isLoaded()) {
			for (BlockInstance bi : ch.list()) {
				spatials.remove(bi);
				visibleSpatials.get(bi.getBlock()).remove(bi);
				//System.out.println("list = " + bi);
			}
			ch.setLoaded(false);
		}
	}
	
	@Override
	public void entityGenerate(int x, int z) {
		try {
			for (int x1 = x - 32; x1 < x + 32; x1++) {
				for (int z1 = z - 32; z1 < z + 32; z1++) {
					Chunk ch = getChunk(x1 / 16, z1 / 16);
					if (!ch.isGenerated()) {
						ch.generateFrom(Noise.generateMapFragment(ch.getX() * 16, ch.getZ() * 16, 16, 16, 300, seed));
						ch.setLoaded(true);
						
						// generated and loaded in memory
					}
					if (!ch.isLoaded()) {
						
					}
				}
			}
			for (int x1 = x - 48; x1 < x + 48; x1++) {
				for (int z1 = z - 48; z1 < z + 48; z1++) {
					if (x1 < x - 32 || x1 > x + 32) {
						if (z1 < z - 32 || z1 > z + 32) {
							//unload(x1 / 16, z1 / 16);
						}
					}
				}
			}
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
	
	@Override
	public Chunk getChunk(int x, int z) {
		Chunk c = null;
		for (Chunk ch : chunks) {
			if (ch.getX() == x && ch.getZ() == z) {
				c = ch;
			}
		}
		
		if (c == null) {
			c = new Chunk(x, z, this);
			// not generated
			chunks.add(c);
		}
		return c;
	}
	
	@Override
	public BlockInstance getBlock(int x, int y, int z) {
		Chunk ch = getChunk(x / 16, z / 16);
		if (y > World.WORLD_HEIGHT || y < 0)
			return null;
		
		if (ch != null) {
			int cx = 0;
			int cz = 0;
			if (x < 0) {
				cx = ((x * -1) % 16);
			} else {
				cx = x % 16;
			}
			//System.out.println(cx);
			if (z < 0) {
				cz = ((z * -1) % 16);
			} else {
				cz = z % 16;
			}
			BlockInstance bi = ch.getBlockInstanceAt(cx, y, cz);
			return bi;
		} else {
			return null;
		}
	}
	
	@Override
	public void removeBlock(int x, int y, int z) {
		Chunk ch = getChunk(x / 16, z / 16);
		if (ch != null) {
			ch.removeBlockAt(x % 16, y, z % 16);
		}
	}
	
	public void _removeBlock(int x, int y, int z) {
		Chunk ch = getChunk(x / 16, z / 16);
		if (ch != null) {
			ch._removeBlockAt(x % 16, y, z % 16);
		}
	}
	
	public void generate() {
		Random r = new Random();
		seed = r.nextInt();
		for (Block b : ModLoader.block_registry.getRegisteredBlocks()) {
			visibleSpatials.put(b, new ArrayList<>());
		}
	}

	@Override
	public boolean isRemote() {
		return false;
	}
	
}
