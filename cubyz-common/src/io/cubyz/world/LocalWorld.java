package io.cubyz.world;

import java.io.File;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Random;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.Ore;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.save.WorldIO;

public class LocalWorld extends World {

	private String name;
	private List<Chunk> chunks;
	private int lastChunk = -1;
	private ArrayList<Entity> entities = new ArrayList<>();
	
	//private List<BlockInstance> spatials = new ArrayList<>();
	private Block [] blocks;
	private Player player;
	
	private WorldIO wio;
	
	private ChunkGenerationThread thread;
	
	private class ChunkGenerationThread extends Thread {
		private static final int MAX_QUEUE_SIZE = 16;
		Deque<Chunk> loadList = new ArrayDeque<>(MAX_QUEUE_SIZE); // FIFO order (First In, First Out)
		
		public void queue(Chunk ch) {
			if (!isQueued(ch)) {
				if (loadList.size() == MAX_QUEUE_SIZE) {
					CubyzLogger.instance.info("Hang on, the Local-Chunk-Thread's queue is full, blocking!");
					while (!loadList.isEmpty()) {
						System.out.print(""); // again, used as replacement to Thread.onSpinWait(), also necessary due to some JVM oddities
					}
				}
				loadList.add(ch);
			}
		}
		
		public boolean isQueued(Chunk ch) {
			Chunk[] list = loadList.toArray(new Chunk[0]);
			for (Chunk ch2 : list) {
				if (ch2 == ch) {
					return true;
				}
			}
			return false;
		}
		
		public void run() {
			while (true) {
				if (!loadList.isEmpty()) {
					Chunk popped = loadList.pop();
//					CubyzLogger.instance.fine("Generating " + popped.chunk.getX() + "," + popped.chunk.getZ());
					synchronousGenerate(popped);
					popped.load();
					//seed = (int) System.currentTimeMillis(); // enable it if you want fun (don't forget to disable before commit!!!)
				}
				System.out.print("");
			}
		}
	}
	
	public LocalWorld() {
		name = "World";
		chunks = new ArrayList<>();
		entities.add(new Player(true));
		
		thread = new ChunkGenerationThread();
		thread.setName("Local-Chunk-Thread");
		thread.setDaemon(true);
		thread.start();
		
		wio = new WorldIO(this, new File("saves/" + name));
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
	public List<Chunk> getChunks() {
		return chunks;
	}

	@Override
	public Block [] getBlocks() {
		return blocks;
	}
	
	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	public void unload(int x, int z) {
		Chunk ch = getChunk(x, z);
		if (ch.isLoaded()) {
			ch.setLoaded(false);
		}
	}
	
	@Override
	public void synchronousSeek(int x, int z) {
		Chunk ch = getChunk(x / 16, z / 16);
		if (!ch.isGenerated()) {
			synchronousGenerate(ch);
			ch.load();
		}
	}
	
	public void synchronousGenerate(Chunk ch) {
		int x = ch.getX() * 16; int y = ch.getZ() * 16;
		float[][] heightMap = Noise.generateMapFragment(x, y, 16, 16, 256, seed);
		float[][] vegetationMap = Noise.generateMapFragment(x, y, 16, 16, 128, seed + 3 * (seed + 1 & Integer.MAX_VALUE));
		float[][] oreMap = Noise.generateMapFragment(x, y, 16, 16, 128, seed - 3 * (seed - 1 & Integer.MAX_VALUE));
		float[][] heatMap = Noise.generateMapFragment(x, y, 16, 16, 4096, seed ^ 123456789);
		ch.generateFrom(heightMap, vegetationMap, oreMap, heatMap);
	}
	
	@Override
	public Chunk getChunk(int x, int z) {
		if(lastChunk >= 0 && chunks.get(lastChunk).getX() == x && chunks.get(lastChunk).getZ() == z) {
			return chunks.get(lastChunk);
		}
		for (int i = 0; i < chunks.size(); i++) {
			if (chunks.get(i).getX() == x && chunks.get(i).getZ() == z) {
				lastChunk = i;
				return chunks.get(i);
			}
		}
		
		Chunk c = new Chunk(x, z, this);
		// not generated
		chunks.add(c);
		lastChunk = chunks.size()-1;
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
	
	@Override
	public void placeBlock(int x, int y, int z, Block b) {
		Chunk ch = getChunk(x / 16, z / 16);
		if (ch != null) {
			ch.addBlockAt(x % 16, y, z % 16, b);
		}
	}
	
	public void generate() {
		Random r = new Random();
		int ID = 0;
		seed = r.nextInt();
		ArrayList<Ore> ores = new ArrayList<Ore>();
		blocks = new Block[CubzRegistries.BLOCK_REGISTRY.registered().length];
		for (IRegistryElement ire : CubzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(!b.isTransparent()) {
				blocks[ID] = b;
				b.ID = ID;
				ID++;
			}
		}
		for (IRegistryElement ire : CubzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(b.isTransparent()) {
				blocks[ID] = b;
				b.ID = ID;
				ID++;
			}
			try {
				ores.add((Ore)b);
			}
			catch(Exception e) {}
		}
		Chunk.init(ores.toArray(new Ore[ores.size()]));
	}

	@Override
	public void queueChunk(Chunk ch) {
		thread.queue(ch);
	}

	@Override
	public void seek(int x, int z) {
		int renderDistance = 5;
		int blockDistance = renderDistance << 4;
		int minX = x-blockDistance;	// Avoid
		int maxX = x+blockDistance;	// recalculating
		int minZ = z-blockDistance;	// them
		int maxZ = z+blockDistance;	// .
		for (int x1 = minX-48; x1 <= maxX+48; x1 += 16) {
			for (int z1 = minZ-48; z1 <= maxZ+48; z1 += 16) {
				Chunk ch = getChunk(x1/16,z1/16);
				if (!ch.isLoaded() && x1 > minX && x1 < maxX && z1 > minZ && z1 < maxZ) {
					if (!ch.isGenerated()) {
						queueChunk(ch);
					} else {
						ch.setLoaded(true);
					}
				} else if (ch.isLoaded() && (x1 < minX || x1 > maxX || z1 < minZ || z1 > maxZ)) {
					ch.setLoaded(false);
				}
			}
		}
	}
}
