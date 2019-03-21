package io.cubyz.world;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

import io.cubyz.CubzLogger;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.modding.ModLoader;

public class LocalWorld extends World {

	private String name;
	private ArrayList<Chunk> chunks;
	private ArrayList<Entity> entities = new ArrayList<>();
	
	private List<BlockInstance> spatials = new ArrayList<>();
	private Map<Block, ArrayList<BlockInstance>> visibleSpatials = Collections.synchronizedMap(new HashMap<>());
	private boolean edited;
	private Player player;
	
	private int seed;
	
	private ChunkGenerationThread thread;
	
	private class ChunkGenerationThread extends Thread {
		Deque<ChunkAction> loadList = new ArrayDeque<>(); // FIFO order (First In, First Out)
		
		public void queue(ChunkAction ca) {
			
			if (!isQueued(ca.chunk)) {
				//CubzLogger.instance.fine("Queued " + ca.type + " for chunk " + ca.chunk);
				loadList.add(ca);
			}
		}
		
		public boolean isQueued(Chunk chunk) {
			ChunkAction[] list = loadList.toArray(new ChunkAction[0]);
			for (ChunkAction ch : list) {
				if (ch != null) {
					if (ch.chunk == chunk)
						return true;
				}
			}
			return false;
		}
		
		public void run() {
			while (true) {
				if (!loadList.isEmpty()) {
					ChunkAction popped = loadList.pop();
					if (popped.type == ChunkActionType.GENERATE) {
						CubzLogger.instance.fine("Generating " + popped.chunk.getX() + "," + popped.chunk.getZ());
						if (!popped.chunk.isGenerated()) {
							synchronousGenerate(popped.chunk);
						} else {
							if (!popped.chunk.isLoaded()) {
								
							}
						}
					}
					else if (popped.type == ChunkActionType.UNLOAD) {
						CubzLogger.instance.fine("Unloading " + popped.chunk.getX() + "," + popped.chunk.getZ());
						for (BlockInstance bi : popped.chunk.list()) {
							Block b = bi.getBlock();
							visibleSpatials.get(b).remove(bi);
							spatials.remove(bi);
						}
						popped.chunk.setLoaded(false);
					}
				}
				System.out.print("");
			}
		}
	}
	
	@Override
	public boolean isEdited() {
		return edited;
	}
	
	@Override
	public void unmarkEdit() {
		edited = false;
	}
	
	@Override
	public void markEdit() {
		edited = true;
	}
	
	public LocalWorld() {
		name = "World";
		chunks = new ArrayList<>();
		entities.add(new Player(true));
		
		thread = new ChunkGenerationThread();
		thread.setName("Local-Chunk-Thread");
		thread.setDaemon(true);
		thread.start();
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
	
	/**
	 * Provided for compatibility.
	 */
	@Override
	public int getWidth() {
		return -1;
	}
	
	/**
	 * Providded for compatibility.
	 */
	@Override
	public int getDepth() {
		return -1;
	}
	
	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	@Override
	public List<BlockInstance> blocks() {
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
			}
			ch.setLoaded(false);
		}
	}
	
	@Override
	public void synchronousSeek(int x, int z) {
		Chunk ch = getChunk(x / 16, z / 16);
		if (!ch.isGenerated()) {
			synchronousGenerate(ch);
			ch.setLoaded(true);
		}
	}
	
	public void synchronousGenerate(Chunk ch) {
		int x = ch.getX() * 16; int y = ch.getZ() * 16;
		float[][] heightMap = Noise.generateMapFragment(x, y, 16, 16, 300, seed);
		ch.generateFrom(heightMap);
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
		int cx = x;
		if(cx < 0)
			cx -= 15;
		cx = cx / 16;
		int cz = z;
		if(cz < 0)
			cz -= 15;
		cz = cz / 16;
		Chunk ch = getChunk(cx, cz);
		if (y > World.WORLD_HEIGHT || y < 0)
			return null;
		
		if (ch != null) {
			cx = x & 15;
			cz = z & 15;
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
		for (IRegistryElement ire : ModLoader.block_registry.registered()) {
			Block b = (Block) ire;
			visibleSpatials.put(b, new ArrayList<>());
		}
	}

	@Override
	public void queueChunk(ChunkAction action) {
		thread.queue(action);
	}

	@Override
	public void seek(int x, int z) {
		int renderDistance = 2-1;
		int blockDistance = renderDistance*16;
		for (int x1 = x - blockDistance-16; x1 < x + blockDistance+16; x1++) {
			for (int z1 = z - blockDistance-16; z1 < z + blockDistance+16; z1++) {
				Chunk ch = getChunk(x1/16,z1/16);
				if (x1>x-blockDistance&&x1<x+blockDistance&&z1>z-blockDistance&&z1<z+blockDistance) {
					if (!ch.isGenerated()) {
						queueChunk(new ChunkAction(ch, ChunkActionType.GENERATE));
					}
				} else {
					if (ch.isLoaded()) {
						queueChunk(new ChunkAction(ch, ChunkActionType.UNLOAD));
					}
				}
			}
		}
	}
	
}
