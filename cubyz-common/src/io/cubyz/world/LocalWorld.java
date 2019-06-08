package io.cubyz.world;

import java.io.File;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Random;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.ITickeable;
import io.cubyz.blocks.Ore;
import io.cubyz.blocks.TileEntity;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.math.Bits;
import io.cubyz.save.BlockChange;
import io.cubyz.save.WorldIO;

public class LocalWorld extends World {
	
	private static Random rnd = new Random();

	private String name;
	private List<Chunk> chunks;
	private Chunk [] visibleChunks;
	private int lastChunk = -1;
	private ArrayList<Entity> entities = new ArrayList<>();
	
	// Stores a reference to the lists of WorldIO.
	public ArrayList<byte[]> blockData;	
	public ArrayList<int[]> chunkData;
	
	private static final int renderDistance = 5;
	
	private Block [] blocks;
	private Player player;
	
	private WorldIO wio;
	
	private ChunkGenerationThread thread;
	
	private class ChunkGenerationThread extends Thread {
		private static final int MAX_QUEUE_SIZE = renderDistance << 2;
		Deque<Chunk> loadList = new ArrayDeque<>(MAX_QUEUE_SIZE); // FIFO order (First In, First Out)
		
		public void queue(Chunk ch) {
			if (!isQueued(ch)) {
				if (loadList.size() >= MAX_QUEUE_SIZE) {
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
					//CubyzLogger.instance.fine("Generating " + popped.getX() + "," + popped.getZ());
					synchronousGenerate(popped);
					popped.load();
					//seed = (int) System.currentTimeMillis(); // enable it if you want fun (don't forget to disable before commit!!!)
				}
				System.out.print("");
			}
		}
	}
	
	public String getName() {
		return name;
	}
	
	public void setName(String name) {
		this.name = name;
	}
	
	public LocalWorld() {
		name = "World";
		chunks = new ArrayList<>();
		visibleChunks = new Chunk[0];
		entities.add(CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity());
		
		thread = new ChunkGenerationThread();
		thread.setName("Local-Chunk-Thread");
		thread.setDaemon(true);
		thread.start();
		
		wio = new WorldIO(this, new File("saves/" + name));
		if (wio.hasWorldData()) {
			wio.loadWorldData();
		} else {
			wio.saveWorldData();
		}
	}
	
	@Override
	public Player getLocalPlayer() {
		if (player == null) {
			for (Entity en : entities) {
				if (en instanceof Player) {
					player = (Player) en;
					player.setWorld(this);
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
	public Chunk[] getVisibleChunks() {
		return visibleChunks;
	}

	@Override
	public Block [] getBlocks() {
		return blocks;
	}
	
	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	@Override
	public void synchronousSeek(int x, int z) {
		Chunk ch = getChunk(x, z);
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
		
		wio.saveChunk(ch, ch.getX(), ch.getZ());
	}
	
	@Override
	public Chunk getChunk(int x, int z) {	// World -> Chunk coordinate system is a bit harder than just x/16. java seems to floor when bigger and to ceil when lower than 0.
		int cx = x;
		if(cx < 0)
			cx -= 15;
		cx = cx / 16;
		int cz = z;
		if(cz < 0)
			cz -= 15;
		cz = cz / 16;
		return _getChunk(cx, cz);
	}
	
	@Override
	public Chunk _getChunk(int x, int z) {
		if(lastChunk >= 0 && lastChunk < chunks.size() && chunks.get(lastChunk).getX() == x && chunks.get(lastChunk).getZ() == z) {
			return chunks.get(lastChunk);
		}
		for (int i = 0; i < chunks.size(); i++) {
			if (chunks.get(i).getX() == x && chunks.get(i).getZ() == z) {
				lastChunk = i;
				return chunks.get(i);
			}
		}
		Chunk c = new Chunk(x, z, this, transformData(getChunkData(x, z)));
		// not generated
		chunks.add(c);
		lastChunk = chunks.size()-1;
		return c;
	}
	
	public byte[] getChunkData(int x, int z) { // Gets the data of a Chunk.
		int index = -1;
		for(int i = 0; i < chunkData.size(); i++) {
			int [] arr = chunkData.get(i);
			if(arr[0] == x && arr[1] == z) {
				index = i;
				break;
			}
		}
		if(index == -1) {
			byte[] dummy = new byte[12];
			Bits.putInt(dummy, 0, x);
			Bits.putInt(dummy, 4, z);
			Bits.putInt(dummy, 8, 0);
			return dummy;
		}
		return blockData.get(index);
	}
	
	public ArrayList<BlockChange> transformData(byte[] data) {
		int size = Bits.getInt(data, 8);
		ArrayList<BlockChange> list = new ArrayList<BlockChange>(size);
		for (int i = 0; i < size; i++) {
			list.add(new BlockChange(data, 12 + (i << 4)));
		}
		return list;
	}
	
	@Override
	public BlockInstance getBlock(int x, int y, int z) {
		Chunk ch = getChunk(x, z);
		if (y > World.WORLD_HEIGHT || y < 0)
			return null;
		
		if (ch != null) {
			int cx = x & 15;
			int cz = z & 15;
			BlockInstance bi = ch.getBlockInstanceAt(cx, y, cz);
			return bi;
		} else {
			return null;
		}
	}
	
	@Override
	public void removeBlock(int x, int y, int z) {
		Chunk ch = getChunk(x, z);
		if (ch != null) {
			ch.removeBlockAt(x & 15, y, z & 15, true);
		}
	}
	
	@Override
	public void placeBlock(int x, int y, int z, Block b) {
		Chunk ch = getChunk(x, z);
		if (ch != null) {
			ch.addBlockAt(x & 15, y, z & 15, b, true);
		}
	}
	
	public void update() {
		// Entities
		for (Entity en : entities) {
			en.update();
		}
		// Tile Entities
		for (Chunk ch : visibleChunks) {
			if (ch.isLoaded()) {
				TileEntity[] tileEntities = ch.tileEntities().toArray(new TileEntity[0]);
				for (TileEntity te : tileEntities) {
					if (te instanceof ITickeable) {
						ITickeable tk = (ITickeable) te;
						tk.tick(false);
						if (tk.randomTicks()) {
							if (rnd.nextInt(20) < 10) {
								tk.tick(true);
							}
						}
					}
				}
			}
		}
	}
	
	public void generate() {
		int ID = 0;
		seed = rnd.nextInt();
		ArrayList<Ore> ores = new ArrayList<Ore>();
		blocks = new Block[CubyzRegistries.BLOCK_REGISTRY.registered().length];
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(!b.isTransparent()) {
				blocks[ID] = b;
				b.ID = ID;
				ID++;
			}
		}
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
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

	private int lastX = Integer.MAX_VALUE;
	private int lastZ = Integer.MAX_VALUE;
	@Override
	public void seek(int x, int z) {
		int local = x & 15;
		x -= local;
		x /= 16;
		x += renderDistance;
		if(local > 7)
			x++;
		local = z & 15;
		z -= local;
		z /= 16;
		z += renderDistance;
		if(local > 7)
			z++;
		if(x == lastX && z == lastZ)
			return;
		int doubleRD = renderDistance << 1;
		Chunk [] newVisibles = new Chunk[doubleRD*doubleRD];
		int index = 0;
		int minK = 0;
		for(int i = x-doubleRD; i < x; i++) {
			for(int j = z-doubleRD; j < z; j++) {
				boolean notIn = true;
				for(int k = minK; k < visibleChunks.length; k++) {
					if(visibleChunks[k].getX() == i && visibleChunks[k].getZ() == j) {
						newVisibles[index] = visibleChunks[k];
						// Removes this chunk out of the list of chunks that will be considered in this function.
						visibleChunks[k] = visibleChunks[minK];
						visibleChunks[minK] = newVisibles[index];
						minK++;
						notIn = false;
						break;
					}
				}
				if(notIn) {
					Chunk ch = getChunk(i << 4, j << 4);
					if (!ch.isGenerated()) {
						queueChunk(ch);
					} else {
						ch.setLoaded(true);
					}
					newVisibles[index] = ch;
				}
				index++;
			}
		}
		for(int k = minK; k < visibleChunks.length; k++) {
			visibleChunks[k].setLoaded(false);
			chunks.remove(visibleChunks[k]);
			wio.saveChunk(visibleChunks[k], visibleChunks[k].getX(), visibleChunks[k].getZ());
		}
		visibleChunks = newVisibles;
		lastX = x;
		lastZ = z;
		if (minK != visibleChunks.length) { // if atleast one chunk got unloaded
			wio.saveWorldData();
		}
		
		// Check if one of the never loaded chunks is outside of players range.
		// Those chunks were never loaded and therefore don't need to get saved.
		x -= renderDistance;
		z -= renderDistance;
		for(int i = 0; i < chunks.size(); i++) {
			Chunk ch = chunks.get(i);
			int delta = Math.abs(ch.getX()-x);
			if(delta >= renderDistance+2) {
				chunks.remove(ch);
				continue;
			}
			delta = Math.abs(ch.getZ()-z);
			if(delta >= renderDistance+2) {
				chunks.remove(ch);
			}
		}
		
	}
}
