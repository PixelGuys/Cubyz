package io.cubyz.world;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.BlockingDeque;
import java.util.concurrent.LinkedBlockingDeque;

import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.IUpdateable;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.math.Bits;
import io.cubyz.save.BlockChange;
import io.cubyz.save.WorldIO;
import io.cubyz.world.generator.LifelandGenerator;
import io.cubyz.world.generator.WorldGenerator;

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
	
	private static int renderDistance = 5;
	private static int MAX_QUEUE_SIZE = renderDistance << 2;
	
	private Block [] blocks;
	private Player player;
	private WorldGenerator generator;
	
	private WorldIO wio;
	
	private ChunkGenerationThread thread;
	private boolean generated;
	
	private static final int DAYCYCLE = 120000; // Length of one in-game day in 100ms. Midnight is at DAYCYCLE/2. Sunrise and sunset each take about 1/16 of the day.
	long gameTime = 0; // Time of the game in 100ms.
	long milliTime;
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);
	
	// TODO: Make world updates threaded, would save load from main thread
	private class ChunkGenerationThread extends Thread {
		BlockingDeque<Chunk> loadList = new LinkedBlockingDeque<>(MAX_QUEUE_SIZE); // FIFO order (First In, First Out)
		
		public void queue(Chunk ch) {
			if (!isQueued(ch)) {
				try {
					loadList.put(ch);
				} catch (InterruptedException e) {
					System.err.println("Interrupted while queuing chunk. This is unexpected.");
				}
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
		
		public int getQueueSize() {
			return loadList.size();
		}
		
		public void run() {
			while (true) {
				try {
					Chunk popped = loadList.take();
					synchronousGenerate(popped);
					popped.load();
				} catch (InterruptedException e) {
					break;
				}
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
		
		thread = new ChunkGenerationThread();
		thread.setName("Local-Chunk-Thread");
		thread.setDaemon(true);
		thread.start();
		
		generator = new LifelandGenerator();
		wio = new WorldIO(this, new File("saves/" + name));
		if (wio.hasWorldData()) {
			wio.loadWorldData();
			generated = true;
		} else {
			wio.saveWorldData();
		}
		milliTime = System.currentTimeMillis();
	}

	
	public void forceSave() {
		wio.saveWorldData();
	}
	
	@Override
	public Player getLocalPlayer() {
		if (player == null) {
			for (Entity e : entities) {
				if (e instanceof Player) {
					player = (Player) e;
				}
			}
			if (player == null) {
				player = (Player) CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity();
				entities.add(player);
				player.setWorld(this);
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
	
	public void setEntities(Entity[] arr) {
		entities = new ArrayList<Entity>();
		for (Entity e : arr) {
			entities.add(e);
		}
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
		ch.generateFrom(generator);
		wio.saveChunk(ch);
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
			if (chunks.get(i).getX() == x && chunks.get(i).getZ() == z) { // Sometimes a nullptr-exception is thrown here! probably due to modification in parallel (world generation)
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
	
	public Block getBlock(int x, int y, int z) {
		BlockInstance bi = getBlockInstance(x, y, z);
		if (bi == null)
			return null;
		return bi.getBlock();
	}
	
	@Override
	public BlockInstance getBlockInstance(int x, int y, int z) {
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
			wio.saveChunk(ch);
			wio.saveWorldData();
		}
	}
	
	@Override
	public void placeBlock(int x, int y, int z, Block b) {
		Chunk ch = getChunk(x, z);
		if (ch != null) {
			ch.addBlockAt(x & 15, y, z & 15, b, true);
			wio.saveChunk(ch);
			wio.saveWorldData();
		}
	}
	
	boolean lqdUpdate;
	public void update() {
		// Time
		if(milliTime + 100 < System.currentTimeMillis()) {
			milliTime += 100;
			lqdUpdate = true;
			gameTime++; // gameTime is measured in 100ms.
		}
		// Ambient light
		{
			int dayTime = Math.abs((int)(gameTime % DAYCYCLE) - (DAYCYCLE >> 1));
			if(dayTime < (DAYCYCLE >> 2)-(DAYCYCLE >> 4)) {
				ambientLight = 0.1f;
				clearColor.x = clearColor.y = clearColor.z = 0;
			} else if(dayTime > (DAYCYCLE >> 2)+(DAYCYCLE >> 4)) {
				ambientLight = 0.7f;
				clearColor.x = clearColor.y = 0.8f;
				clearColor.z = 1.0f;
			} else {
				//b:
				if(dayTime > (DAYCYCLE >> 2)) {
					clearColor.z = 1.0f*(dayTime-(DAYCYCLE >> 2))/(DAYCYCLE >> 4);
				} else {
					clearColor.z = 0.0f;
				}
				//g:
				if(dayTime > (DAYCYCLE >> 2)+(DAYCYCLE >> 5)) {
					clearColor.y = 0.8f;
				} else if(dayTime > (DAYCYCLE >> 2)-(DAYCYCLE >> 5)) {
					clearColor.y = 0.8f+0.8f*(dayTime-(DAYCYCLE >> 2)-(DAYCYCLE >> 5))/(DAYCYCLE >> 4);
				} else {
					clearColor.y = 0.0f;
				}
				//r:
				if(dayTime > (DAYCYCLE >> 2)) {
					clearColor.x = 0.8f;
				}
				else {
					clearColor.x = 0.8f+0.8f*(dayTime-(DAYCYCLE >> 2))/(DAYCYCLE >> 4);
				}
				dayTime -= (DAYCYCLE >> 2);
				dayTime <<= 3;
				ambientLight = 0.4f + 0.3f*dayTime/(DAYCYCLE >> 1);
			}
		}
		// Entities
		for (Entity en : entities) {
			en.update();
		}
		// Block Entities
		for (Chunk ch : visibleChunks) {
			if (ch.isLoaded() && ch.blockEntities().size() > 0) {
				BlockEntity[] tileEntities = ch.blockEntities().values().toArray(new BlockEntity[ch.blockEntities().values().size()]);
				for (BlockEntity te : tileEntities) {
					if (te instanceof IUpdateable) {
						IUpdateable tk = (IUpdateable) te;
						tk.update(false);
						if (tk.randomUpdates()) {
							if (rnd.nextInt(5) <= 1) { // 1/5 chance
								tk.update(true);
							}
						}
					}
				}
			}
		}
		
		// Liquids
		if (gameTime % 3 == 0 && lqdUpdate) {
			lqdUpdate = false;
			for (Chunk ch : visibleChunks) {
				if (ch.isLoaded() && ch.liquids().size() > 0) {
					BlockInstance[] liquids = ch.liquids().toArray(new BlockInstance[ch.liquids().size()]);
					for (BlockInstance bi : liquids) {
						BlockInstance[] neighbors = bi.getNeighbors(ch);
						for (int i = 0; i < neighbors.length; i++) {
							BlockInstance b = neighbors[i];
							if (b == null) switch (i) {
							case 0:
								ch.addBlock(bi.getBlock(), bi.getX()-1, bi.getY(), bi.getZ());
								break;
							case 1:
								ch.addBlock(bi.getBlock(), bi.getX()+1, bi.getY(), bi.getZ());
								break;
							case 2:
								ch.addBlock(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ()+1);
								break;
							case 3:
								ch.addBlock(bi.getBlock(), bi.getX(), bi.getY(), bi.getZ()-1);
								break;
							case 4:
								ch.addBlock(bi.getBlock(), bi.getX(), bi.getY()-1, bi.getZ());
								break;
							case 5: // not placing up!
								break;
							default:
								System.err.println("(LocalWorld/Liquids) More than 6 nullable neighbors!");
								break;
							}
						}
					}
				}
			}
		}
	}
	
	public void generate() {
		if (!generated) seed = rnd.nextInt();
		blocks = new Block[CubyzRegistries.BLOCK_REGISTRY.registered().length];
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			blocks[b.ID] = b;
		}
		generated = true;
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
			wio.saveChunk(visibleChunks[k]);
		}
		visibleChunks = newVisibles;
		lastX = x;
		lastZ = z;
		if (minK != visibleChunks.length) { // if atleast one chunk got unloaded
			wio.saveWorldData();
			//System.gc();
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
	
	public float getGlobalLighting() {
		return ambientLight;
	}

	@Override
	public long getGameTime() {
		return gameTime;
	}

	@Override
	public void setGameTime(long time) {
		gameTime = time;
	}

	@Override
	public void setRenderDistance(int RD) {
		renderDistance = RD;
		MAX_QUEUE_SIZE = renderDistance << 2;
	}
	
	public int getChunkQueueSize() {
		return thread.getQueueSize();
	}

	@Override
	public int getRenderDistance() {
		return renderDistance;
	}

	@Override
	public Vector4f getClearColor() {
		return clearColor;
	}

	@Override
	public void cleanup() {
		// Be sure to dereference and finalize the maximum of things
		try {
			forceSave();
			
			thread.interrupt();
			thread.join();
			thread = null;
			
			chunks = null;
			visibleChunks = null;
			chunkData = null;
			blockData = null;
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		BlockInstance bi = getBlockInstance(x, y, z);
		Chunk ck = getChunk(bi.getX(), bi.getZ());
		return ck.blockEntities().get(bi);
	}
	
}
