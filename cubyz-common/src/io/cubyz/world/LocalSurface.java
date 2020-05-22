package io.cubyz.world;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.BlockingDeque;
import java.util.concurrent.LinkedBlockingDeque;

import org.joml.Vector4f;

import io.cubyz.CubyzLogger;
import io.cubyz.Profiler;
import io.cubyz.Settings;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.base.init.ItemInit;
import io.cubyz.base.init.MaterialInit;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.CustomOre;
import io.cubyz.blocks.Updateable;
import io.cubyz.blocks.Ore;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.handler.PlaceBlockHandler;
import io.cubyz.handler.RemoveBlockHandler;
import io.cubyz.math.Bits;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;
import io.cubyz.save.TorusIO;
import io.cubyz.world.cubyzgenerators.CrystalCavernGenerator;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.generator.LifelandGenerator;
import io.cubyz.world.generator.SurfaceGenerator;

public class LocalSurface extends Surface {
	private static Random rnd = new Random();
	
	private List<MetaChunk> metaChunks;
	private Chunk [] chunks;
	private int lastX = Integer.MAX_VALUE, lastZ = Integer.MAX_VALUE; // Chunk coordinates of the last chunk update.
	private int doubleRD; // Corresponds to the doubled value of the last used render distance.
	private int worldAnd = 65535; // worldSize-1. Used for bitwise and to better work with coordinates.
	private ArrayList<Entity> entities = new ArrayList<>();
	
	private Block[] torusBlocks;
	
	// Stores a reference to the lists of WorldIO.
	public ArrayList<byte[]> blockData;	
	public ArrayList<int[]> chunkData;
	
	private static int MAX_QUEUE_SIZE = 40;
	
	private SurfaceGenerator generator;
	
	private TorusIO tio;
	
	private List<ChunkGenerationThread> threads = new ArrayList<>();
	private boolean generated;
	
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);
	
	long localSeed; // Each torus has a different seed for world generation. All those seeds are generated using the main world seed.
	
	// synchronized common list for chunk generation
	private volatile BlockingDeque<Chunk> loadList = new LinkedBlockingDeque<>(MAX_QUEUE_SIZE);
	
	boolean liquidUpdate;
	
	BlockEntity[] blockEntities = new BlockEntity[0];
	Integer[] liquids = new Integer[0];

	private ArrayList<CustomOre> customOres = new ArrayList<>();
	
	private void queue(Chunk ch) {
		if (!isQueued(ch)) {
			try {
				loadList.put(ch);
			} catch (InterruptedException e) {
				System.err.println("Interrupted while queuing chunk. This is unexpected.");
			}
		}
	}
	
	private boolean isQueued(Chunk ch) {
		Chunk[] list = loadList.toArray(new Chunk[0]);
		for (Chunk ch2 : list) {
			if (ch2 == ch) {
				return true;
			}
		}
		return false;
	}
	
	private class ChunkGenerationThread extends Thread {
		public void run() {
			while (true) {
				Chunk popped = null;
				try {
					popped = loadList.take();
				} catch (InterruptedException e) {
					break;
				}
				try {
					if(popped.isLoaded()) {
						throw new Exception("OOPS. This ChunkGenerationThread tried to load a chunk twice. @zenith please fix this.");
					}
					synchronousGenerate(popped);
					popped.load();
				} catch (Exception e) {
					CubyzLogger.instance.severe("Could not generate chunk " + popped.getX() + ", " + popped.getZ() + " !");
					CubyzLogger.instance.throwable(e);
				}
			}
		}
	}
	
	public LocalSurface(LocalStellarTorus torus) {
		localSeed = torus.getLocalSeed();
		this.torus = torus;
		MaterialInit.resetCustom();
		ItemInit.resetCustom();
		metaChunks = new ArrayList<>();
		chunks = new Chunk[0];
		
		for (int i = 0; i < Runtime.getRuntime().availableProcessors(); i++) {
			ChunkGenerationThread thread = new ChunkGenerationThread();
			thread.setName("Local-Chunk-Thread-" + i);
			thread.setDaemon(true);
			thread.start();
			threads.add(thread);
		}
		generator = CubyzRegistries.STELLAR_TORUS_GENERATOR_REGISTRY.getByID("cubyz:lifeland");
		if (generator instanceof LifelandGenerator) {
			((LifelandGenerator) generator).sortGenerators();
		}
		tio = new TorusIO(torus, new File("saves/" + torus.getWorld().getName() + "/" + localSeed)); // use seed in path
		if (tio.hasTorusData()) {
			generated = true;
		} else {
			tio.saveTorusData(this);
		}
		//setChunkQueueSize(torus.world.getRenderDistance() << 2);
	}
	
	public void link() {
		tio.link(this);
		tio.loadTorusData(this); // load data here in order for entities to also be loaded.
	}
	
	// Returns the blocks, so their meshes can be created and stored.
	public int generate(ArrayList<Block> blockList, ArrayList<Ore> ores, int ID) {
		Random rand = new Random(localSeed);
		int randomAmount = 9 + rand.nextInt(3); // TODO
		torusBlocks = new Block[randomAmount+2];
		int i = 0;
		for(i = 0; i < randomAmount; i++) {
			torusBlocks[i] = CustomOre.random(rand);
			customOres.add((CustomOre)torusBlocks[i]);
			ores.add((Ore)torusBlocks[i]);
			blockList.add(torusBlocks[i]);
			torusBlocks[i].ID = ID++;
		}
		
		// Create the crystal ore for the CrystalCaverns:
		CustomOre glowCrystalOre = CustomOre.random(rand);
		torusBlocks[i] = glowCrystalOre;
		glowCrystalOre.makeGlow(); // Make sure it glows.
		customOres.add(glowCrystalOre);
		ores.add((Ore)torusBlocks[i]);
		blockList.add(torusBlocks[i]);
		torusBlocks[i].ID = ID++;
		i++;
		// Create the crystal block for the CrystalCaverns:
		CustomOre crystalBlock = new CustomOre(0, 0, 0); // TODO: Add a CustomBlock type or interface because this is no ore.
		crystalBlock.setID(glowCrystalOre.getRegistryID().toString()+"_glow_crystal");
		crystalBlock.setHardness(40);
		crystalBlock.setBlockDrop(glowCrystalOre.getBlockDrop());
		crystalBlock.setLight(glowCrystalOre.color);
		crystalBlock.color = glowCrystalOre.color;
		crystalBlock.seed = -1; // TODO: Fix crystal block within the new ore texture generation system.
		torusBlocks[i] = crystalBlock;
		customOres.add((CustomOre)torusBlocks[i]);
		ores.add((Ore)torusBlocks[i]);
		blockList.add(torusBlocks[i]);
		torusBlocks[i].ID = ID++;
		i++;
		// Init crystal caverns with those two blocks:
		CrystalCavernGenerator.init(crystalBlock, glowCrystalOre);
		
		if(generated) {
			tio.saveTorusData(this);
		}
		generated = true;
		return ID;
	}
	
	public void setChunkQueueSize(int size) {
		synchronized (loadList) {
			loadList.clear();
			MAX_QUEUE_SIZE = size;
			loadList = new LinkedBlockingDeque<>(size);
		}
		System.out.println("max queue size is now " + size);
	}

	
	public void forceSave() {
		tio.saveTorusData(this);
		((LocalWorld) torus.getWorld()).forceSave();
	}
	
	public void addEntity(Entity ent) {
		entities.add(ent);
	}
	
	public void setEntities(Entity[] arr) {
		entities = new ArrayList<>(arr.length);
		for (Entity e : arr) {
			entities.add(e);
		}
	}
	
	@Override
	public void synchronousSeek(int x, int z, int renderDistance) {
		// Transform to chunk coordinates:
		x >>= 4;
		z >>= 4;
		Chunk ch = getChunk(x, z);
		if(ch == null) {
			ch = new Chunk(x, z, this, transformData(getChunkData(x, z)));
			Chunk[] newList = new Chunk[chunks.length+1];
			newList[chunks.length] = ch;
			chunks = newList;
		}
		if (!ch.isGenerated()) { // TODO actually fix synchronousSeek so we can access blocks generated through it
			synchronousGenerate(ch);
			ch.load();
			int local = x & 15;
			x += renderDistance;
			if(local > 7)
				x++;
			local = z & 15;
			z += renderDistance;
			if(local > 7)
				z++;
			lastX = x;
			lastZ = z;
			doubleRD = renderDistance << 1;
		}
	}
	
	public void synchronousGenerate(Chunk ch) {
		ch.generateFrom(generator);
		tio.saveChunk(ch);
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
	public void removeBlock(int x, int y, int z) {
		Chunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null) {
			Block b = ch.getBlockAt(x & 15, y, z & 15);
			ch.removeBlockAt(x & 15, y, z & 15, true);
			tio.saveChunk(ch); // TODO: Don't save it every time.
			tio.saveTorusData(this);
			for (RemoveBlockHandler hand : removeBlockHandlers) {
				hand.onBlockRemoved(b, x, y, z);
			}
		}
	}
	
	@Override
	public void placeBlock(int x, int y, int z, Block b) {
		Chunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null) {
			ch.addBlockAt(x & 15, y, z & 15, b, true);
			tio.saveChunk(ch); // TODO: Don't save it every time.
			tio.saveTorusData(this);
			for (PlaceBlockHandler hand : placeBlockHandlers) {
				hand.onBlockPlaced(b, x, y, z);
			}
		}
	}
	
	public void update() {
		long gameTime = torus.world.getGameTime();
		int dayCycle = torus.getDayCycle();
		LocalWorld world = (LocalWorld) torus.getWorld();
		// Ambient light
		{
			int dayTime = Math.abs((int)(gameTime % dayCycle) - (dayCycle >> 1));
			if(dayTime < (dayCycle >> 2)-(dayCycle >> 4)) {
				ambientLight = 0.1f;
				clearColor.x = clearColor.y = clearColor.z = 0;
			} else if(dayTime > (dayCycle >> 2)+(dayCycle >> 4)) {
				ambientLight = 0.7f;
				clearColor.x = clearColor.y = 0.8f;
				clearColor.z = 1.0f;
			} else {
				//b:
				if(dayTime > (dayCycle >> 2)) {
					clearColor.z = 1.0f*(dayTime-(dayCycle >> 2))/(dayCycle >> 4);
				} else {
					clearColor.z = 0.0f;
				}
				//g:
				if(dayTime > (dayCycle >> 2)+(dayCycle >> 5)) {
					clearColor.y = 0.8f;
				} else if(dayTime > (dayCycle >> 2)-(dayCycle >> 5)) {
					clearColor.y = 0.8f+0.8f*(dayTime-(dayCycle >> 2)-(dayCycle >> 5))/(dayCycle >> 4);
				} else {
					clearColor.y = 0.0f;
				}
				//r:
				if(dayTime > (dayCycle >> 2)) {
					clearColor.x = 0.8f;
				} else {
					clearColor.x = 0.8f+0.8f*(dayTime-(dayCycle >> 2))/(dayCycle >> 4);
				}
				dayTime -= (dayCycle >> 2);
				dayTime <<= 3;
				ambientLight = 0.4f + 0.3f*dayTime/(dayCycle >> 1);
			}
		}
		// Entities
		for (Entity en : entities) {
			en.update();
		}
		// Block Entities
		for (Chunk ch : chunks) {
			if (ch.isLoaded() && ch.getBlockEntities().size() > 0) {
				blockEntities = ch.getBlockEntities().values().toArray(blockEntities);
				for (BlockEntity be : blockEntities) {
					if (be == null) continue;
					if (be instanceof Updateable) {
						Updateable tk = (Updateable) be;
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
		if (gameTime % 3 == 0 && world.inLqdUpdate) {
			world.inLqdUpdate = false;
			//Profiler.startProfiling();
			for (Chunk ch : chunks) {
				int wx = ch.getX() << 4;
				int wz = ch.getZ() << 4;
				if (ch.isLoaded() && ch.getLiquids().size() > 0) {
					liquids = ch.getUpdatingLiquids().toArray(liquids);
					int size = ch.getUpdatingLiquids().size();
					ch.getUpdatingLiquids().clear();
					for (int j = 0; j < size; j++) {
						Block block = ch.getBlockAtIndex(liquids[j]);
						int bx = (liquids[j] >> 4) & 15;
						int by = liquids[j] >> 8;
						int bz = liquids[j] & 15;
						Block[] neighbors = ch.getNeighbors(bx, by, bz);
						for (int i = 0; i < 5; i++) {
							Block b = neighbors[i];
							if (b == null) {
								int dx = 0, dy = 0, dz = 0;
								switch (i) {
									case 0: // at x -1
										dx = -1;
									break;
									case 1: // at x +1
										dx = 1;
										break;
									case 2:  // at z -1
										dz = -1;
										break;
									case 3: // at z +1
										dz = 1;
										break;
									case 4: // at y -1
										dy = -1;
										break;
									default:
										System.err.println("(LocalWorld/Liquids) More than 6 nullable neighbors!");
										break;
								}
								if(dy == -1 || (neighbors[4] != null && neighbors[4].getBlockClass() != Block.BlockClass.FLUID)) {
									ch.addBlockPossiblyOutside(block, (wx+bx+dx) & worldAnd, by+dy, (wz+bz+dz) & worldAnd);
								}
							}
						}
					}
				}
			}
			//Profiler.printProfileTime("liquid-update");
		}
	}

	@Override
	public void queueChunk(Chunk ch) {
		queue(ch);
	}
	
	@Override
	public void seek(int x, int z, int renderDistance) {
		int local = x & 15;
		x >>= 4;
		x += renderDistance;
		if(local > 7)
			x++;
		local = z & 15;
		z >>= 4;
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
				for(int k = minK; k < chunks.length; k++) {
					if(chunks[k].getX() == i && chunks[k].getZ() == j) {
						newVisibles[index] = chunks[k];
						// Removes this chunk out of the list of chunks that will be considered in this function.
						chunks[k] = chunks[minK];
						chunks[minK] = newVisibles[index];
						minK++;
						notIn = false;
						break;
					}
				}
				if(notIn) {
					Chunk ch = getChunk(i, j);
					if(ch == null) {
						ch = new Chunk(i, j, this, transformData(getChunkData(i, j)));
					}
					newVisibles[index] = ch;
				}
				index++;
			}
		}
		for(int k = minK; k < chunks.length; k++) {
			tio.saveChunk(chunks[k]);
		}
		chunks = newVisibles;
		lastX = x;
		lastZ = z;
		this.doubleRD = doubleRD;
		// Generate the chunks after they can get access to their neighbors:
		for(Chunk ch : newVisibles) {
			if (!ch.isGenerated()) {
				queueChunk(ch);
			}
		}
		if (minK != chunks.length) { // if at least one chunk got unloaded
			tio.saveTorusData(this);
		}
	}
	
	public void getMapData(int x, int y, int width, int height, float [][] heightMap, float[][] heatMap, Biome[][] biomeMap) {
		int x0 = x&(~255);
		int y0 = y&(~255);
		for(int px = x0; CubyzMath.matchSign((px-x) & worldAnd, worldAnd) < width; px += 256) {
			for(int py = y0; CubyzMath.matchSign((py-y) & worldAnd, worldAnd) < height; py += 256) {
				MetaChunk ch = getMetaChunk(px&worldAnd ,py&worldAnd);
				int xS = Math.max(px-x, 0);
				int yS = Math.max(py-y, 0);
				int xE = Math.min(px+256-x, width);
				int yE = Math.min(py+256-y, height);
				for(int cx = xS; cx < xE; cx++) {
					for(int cy = yS; cy < yE; cy++) {
						heightMap[cx][cy] = ch.heightMap[(cx+x)&255][(cy+y)&255];
						heatMap[cx][cy] = ch.heatMap[(cx+x)&255][(cy+y)&255];
						biomeMap[cx][cy] = ch.biomeMap[(cx+x)&255][(cy+y)&255];
					}
				}
			}
		}
	}
	
	public MetaChunk getMetaChunk(int wx, int wz) {
		for(MetaChunk ch : metaChunks.toArray(new MetaChunk[0])) {
			if(ch.x == wx && ch.z == wz) {
				return ch;
			}
		}
		synchronized(metaChunks) {
			// Now that the thread got access to this part the list might already contain the searched MetaChunk:
			for(MetaChunk ch : metaChunks) {
				if(ch.x == wx && ch.z == wz) {
					return ch;
				}
			}
			// Every time a new MetaChunk is created, go through the list and if the length is at the limit(determined by the renderdistance) remove those that are farthest from the player:
			while(metaChunks.size() > (doubleRD/16 + 4)*(doubleRD/16 + 4)) {
				int max = 0;
				int index = 0;
				for(int i = 0; i < metaChunks.size(); i++) {
					Player player = torus.world.getLocalPlayer();
					int dist = CubyzMath.matchSign(metaChunks.get(i).x-player.getPosition().x, worldAnd)*CubyzMath.matchSign(metaChunks.get(i).x-player.getPosition().x, worldAnd) + CubyzMath.matchSign(metaChunks.get(i).z-player.getPosition().z, worldAnd)*CubyzMath.matchSign(metaChunks.get(i).z-player.getPosition().z, worldAnd);
					if(dist > max) {
						max = dist;
						index = i;
					}
				}
				metaChunks.remove(index);
			}
			MetaChunk ch = new MetaChunk(wx, wz, localSeed, this);
			metaChunks.add(ch);
			return ch;
		}
	}
	
	public MetaChunk getNoGenerateMetaChunk(int wx, int wy) {
		for(MetaChunk ch : metaChunks) {
			if(ch.x == wx && ch.z == wy) {
				return ch;
			}
		}
		return null;
	}
	
	@Override
	public Chunk getChunk(int x, int z) {
		x &= worldAnd >>> 4;
		z &= worldAnd >>> 4;
		// First test if the chunk can be found in the list of visible chunks:
		if(x < lastX && x >= lastX-doubleRD && z < lastZ && z >= lastZ-doubleRD) {
			// Sometimes errors happen when resizing the renderDistance. If they happen just go on to iterating through the whole long list.
			// Any seemingly useless checks in here are important!
			int index = (x-(lastX-doubleRD))*doubleRD + (z-(lastZ-doubleRD));
			if(index < chunks.length && index >= 0) {
				Chunk ret = chunks[index];
				if(x == ret.getX() && z == ret.getZ())
					return ret;
			}
		}
		return null;
	}
	
	@Override
	public Block getBlock(int x, int y, int z) {
		if (y > World.WORLD_HEIGHT || y < 0)
			return null;

		Chunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null && ch.isGenerated()) {
			Block b = ch.getBlockAt(x & 15, y, z & 15);
			return b;
		} else {
			return null;
		}
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
	
	public long getSeed() {
		return localSeed;
	}
	
	public float getGlobalLighting() {
		return ambientLight;
	}
	
	public int getChunkQueueSize() {
		return loadList.size();
	}

	@Override
	public Vector4f getClearColor() {
		return clearColor;
	}

	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		/*BlockInstance bi = getBlockInstance(x, y, z);
		Chunk ck = _getNoGenerateChunk(bi.getX() >> 4, bi.getZ() >> 4);
		return ck.blockEntities().get(bi);*/
		return null; // TODO: Work on BlockEntities!
	}
	
	@Override
	public int getAnd() {
		return worldAnd;
	}
	
	public ArrayList<CustomOre> getCustomOres() {
		return customOres;
	}

	@Override
	public Chunk[] getChunks() {
		return chunks;
	}

	@Override
	public Block[] getPlanetBlocks() {
		return torusBlocks;
	}
	
	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	public int getHeight(int x, int z) {
		return (int)(getMetaChunk(x & ~255, z & ~255).heightMap[x & 255][z & 255]*World.WORLD_HEIGHT);
	}

	@Override
	public void cleanup() {
		// Be sure to dereference and finalize the maximum of things
		try {
			forceSave();
			
			for (Thread thread : threads) {
				thread.interrupt();
				thread.join();
			}
			threads = new ArrayList<>();
			
			chunks = null;
			chunkData = null;
			blockData = null;
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
}
