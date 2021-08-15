package cubyz.world;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Random;
import java.util.concurrent.BlockingDeque;
import java.util.concurrent.LinkedBlockingDeque;

import org.joml.Vector3f;
import org.joml.Vector4f;

import cubyz.Logger;
import cubyz.Settings;
import cubyz.api.CurrentSurfaceRegistries;
import cubyz.utils.datastructures.HashMapKey3D;
import cubyz.utils.math.CubyzMath;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.CrystalTextureProvider;
import cubyz.world.blocks.CustomBlock;
import cubyz.world.blocks.Ore;
import cubyz.world.blocks.OreTextureProvider;
import cubyz.world.cubyzgenerators.CrystalCavernGenerator;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.cubyzgenerators.biomes.BiomeGenerator;
import cubyz.world.cubyzgenerators.biomes.Biome.Type;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.Entity;
import cubyz.world.entity.ItemEntityManager;
import cubyz.world.generator.LifelandGenerator;
import cubyz.world.generator.SurfaceGenerator;
import cubyz.world.handler.PlaceBlockHandler;
import cubyz.world.handler.RemoveBlockHandler;
import cubyz.world.items.BlockDrop;
import cubyz.world.items.ItemStack;
import cubyz.world.save.TorusIO;

public class LocalSurface extends Surface {
	private Region[] regions;
	private HashMap<HashMapKey3D, MetaChunk> metaChunks = new HashMap<HashMapKey3D, MetaChunk>();
	private NormalChunk[] chunks = new NormalChunk[0];
	//private OldReducedChunk[] reducedChunks;
	private ChunkEntityManager[] entityManagers = new ChunkEntityManager[0];
	private int lastX = Integer.MAX_VALUE, lastY = Integer.MAX_VALUE, lastZ = Integer.MAX_VALUE; // Chunk coordinates of the last chunk update.
	private int lastRegX = Integer.MAX_VALUE, lastRegZ = Integer.MAX_VALUE; // Region coordinates of the last chunk update.
	private int regDRD; // double renderdistance of Region.
	private final int worldSizeX = 131072, worldSizeZ = 32768;
	private ArrayList<Entity> entities = new ArrayList<>();
	
	private Block[] torusBlocks;
	
	private SurfaceGenerator generator;
	
	private TorusIO tio;
	
	private List<ChunkGenerationThread> generatorThreads = new ArrayList<>();
	private boolean generated;
	
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);
	
	private final long localSeed; // Each torus has a different seed for world generation. All those seeds are generated using the main world seed.
	
	private final Biome.Type[][] biomeMap;
	
	// synchronized common list for chunk generation
	private volatile BlockingDeque<Chunk> loadList = new LinkedBlockingDeque<>();
	//private volatile BlockingDeque<OldReducedChunk> reducedLoadList = new LinkedBlockingDeque<>();
	
	public final Class<?> chunkProvider;
	
	boolean liquidUpdate;
	
	BlockEntity[] blockEntities = new BlockEntity[0];
	Integer[] liquids = new Integer[0];
	
	public CurrentSurfaceRegistries registries;

	private ArrayList<CustomBlock> customBlocks = new ArrayList<>();
	
	private class ChunkGenerationThread extends Thread {
		volatile boolean running = true;
		public void run() {
			while (running) {
				Chunk popped = null;
				try {
					popped = loadList.take();
				} catch (InterruptedException e) {
					break;
				}
				try {
					synchronousGenerate(popped);
					if(popped instanceof NormalChunk)
						((NormalChunk)popped).load();
				} catch (Exception e) {
					Logger.severe("Could not generate " + popped.getVoxelSize() + "-chunk " + popped.getWorldX()+", " + popped.getWorldY() + ", " + popped.getWorldZ() + " !");
					Logger.throwable(e);
				}
			}
		}
		
		@Override
		public void interrupt() {
			running = false; // Make sure the Thread stops in all cases.
			super.interrupt();
		}
	}
	
	public LocalSurface(LocalStellarTorus torus, Class<?> chunkProvider) {
		registries = new CurrentSurfaceRegistries();
		localSeed = torus.getLocalSeed();
		this.torus = torus;
		this.chunkProvider = chunkProvider;
		// Check if the chunkProvider is valid:
		if(!NormalChunk.class.isAssignableFrom(chunkProvider) ||
				chunkProvider.getConstructors().length != 1 ||
				chunkProvider.getConstructors()[0].getParameterTypes().length != 4 ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[0].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[1].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[2].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[3].equals(Surface.class))
			throw new IllegalArgumentException("Chunk provider "+chunkProvider+" is invalid! It needs to be a subclass of NormalChunk and MUST contain a single constructor with parameters (Integer, Integer, Integer, Surface)");
		regions = new Region[0];
		
		for (int i = 0; i < Runtime.getRuntime().availableProcessors(); i++) {
			ChunkGenerationThread thread = new ChunkGenerationThread();
			thread.setName("Local-Chunk-Thread-" + i);
			thread.setDaemon(true);
			thread.start();
			generatorThreads.add(thread);
		}
		generator = registries.worldGeneratorRegistry.getByID("cubyz:lifeland");
		if (generator instanceof LifelandGenerator) {
			((LifelandGenerator) generator).sortGenerators();
		}
		tio = new TorusIO(torus, new File("saves/" + torus.getWorld().getName() + "/" + localSeed)); // use seed in path
		if (tio.hasTorusData()) {
			generated = true;
		} else {
			tio.saveTorusData(this);
		}
		
		biomeMap = BiomeGenerator.generateTypeMap(localSeed, worldSizeX/Region.regionSize, worldSizeZ/Region.regionSize);
	}
	
	public int generate(ArrayList<Block> blockList, ArrayList<Ore> ores, int ID) {
		Random rand = new Random(localSeed);
		int randomAmount = 9 + rand.nextInt(3); // TODO
		int i = 0;
		for(i = 0; i < randomAmount; i++) {
			CustomBlock block = CustomBlock.random(rand, registries, new OreTextureProvider());
			customBlocks.add(block);
			ores.add(block);
			blockList.add(block);
			block.ID = ID++;
			registries.blockRegistry.register(block);
		}

		// Create the crystal ore for the CrystalCaverns:
		CustomBlock glowCrystalOre = CustomBlock.random(rand, registries, new OreTextureProvider());
		glowCrystalOre.makeGlow(); // Make sure it glows.
		customBlocks.add(glowCrystalOre);
		ores.add(glowCrystalOre);
		blockList.add(glowCrystalOre);
		glowCrystalOre.ID = ID++;
		registries.blockRegistry.register(glowCrystalOre);
		i++;
		// Create the crystal block for the CrystalCaverns:
		CustomBlock crystalBlock = new CustomBlock(0, 0, 0, new CrystalTextureProvider()); // TODO: Add a CustomBlock type or interface because this is no ore.
		crystalBlock.setID(glowCrystalOre.getRegistryID().toString()+"_glow_crystal");
		crystalBlock.setHardness(40);
		crystalBlock.addBlockDrop(new BlockDrop(glowCrystalOre.getBlockDrops()[0].item, 4));
		crystalBlock.setLight(glowCrystalOre.color);
		crystalBlock.color = glowCrystalOre.color;
		crystalBlock.seed = glowCrystalOre.seed;
		customBlocks.add(crystalBlock);
		ores.add(crystalBlock);
		blockList.add(crystalBlock);
		crystalBlock.ID = ID++;
		registries.blockRegistry.register(crystalBlock);
		i++;
		// Init crystal caverns with those two blocks:
		CrystalCavernGenerator.init(crystalBlock, glowCrystalOre);

		tio.loadTorusData(this); // load data here in order for entities to also be loaded.
		
		if(generated) {
			tio.saveTorusData(this);
		}
		generated = true;
		torusBlocks = blockList.toArray(new Block[0]);
		return ID;
	}

	
	public void forceSave() {
		for(MetaChunk chunk : metaChunks.values()) {
			if(chunk != null) chunk.save();
		}
		tio.saveTorusData(this);
		((LocalWorld) torus.getWorld()).forceSave();
		for(Region region : regions) {
			if(region != null)
				region.regIO.saveData();
		}
	}
	
	public void addEntity(Entity ent) {
		entities.add(ent);
	}
	
	public void removeEntity(Entity ent) {
		entities.remove(ent);
	}
	
	public void setEntities(Entity[] arr) {
		entities = new ArrayList<>(arr.length);
		for (Entity e : arr) {
			entities.add(e);
		}
	}
	
	@Override
	public boolean isValidSpawnLocation(int x, int z) {
		// Just make sure there is a forest nearby, so the player will always be able to get the resources needed to start properly.
		int mapX = biomeMap.length*x/worldSizeX;
		int mapZ = biomeMap[0].length*z/worldSizeZ;
		return biomeMap[mapX][mapZ] == Biome.Type.FOREST
				| biomeMap[mapX][mapZ] == Biome.Type.GRASSLAND
				| biomeMap[mapX][mapZ] == Biome.Type.MOUNTAIN_FOREST
				| biomeMap[mapX][mapZ] == Biome.Type.RAINFOREST
				| biomeMap[mapX][mapZ] == Biome.Type.SWAMP
				| biomeMap[mapX][mapZ] == Biome.Type.TAIGA;
	}
	
	public void synchronousGenerate(Chunk ch) {
		ch.generateFrom(generator);
	}
	
	@Override
	public void removeBlock(int x, int y, int z) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if (ch != null) {
			Block b = ch.getBlock(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask);
			ch.removeBlockAt(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask, true);
			for (RemoveBlockHandler hand : removeBlockHandlers) {
				hand.onBlockRemoved(b, x, y, z);
			}
			// Fetch block drops:
			for(BlockDrop drop : b.getBlockDrops()) {
				int amount = (int)(drop.amount);
				float randomPart = drop.amount - amount;
				if(Math.random() < randomPart) amount++;
				if(amount > 0) {
					ItemEntityManager manager = this.getEntityManagerAt(x & ~NormalChunk.chunkMask, y & ~NormalChunk.chunkMask, z & ~NormalChunk.chunkMask).itemEntityManager;
					manager.add(x, y, z, 0, 0, 0, new ItemStack(drop.item, amount), 30*300 /*5 minutes at normal update speed.*/);
				}
			}
		}
	}
	
	@Override
	public void placeBlock(int x, int y, int z, Block b, byte data) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if (ch != null) {
			ch.addBlock(b, data, x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask, false);
			for (PlaceBlockHandler hand : placeBlockHandlers) {
				hand.onBlockPlaced(b, x, y, z);
			}
		}
	}
	
	@Override
	public void drop(ItemStack stack, Vector3f pos, Vector3f dir, float velocity) {
		ItemEntityManager manager = this.getEntityManagerAt((int)pos.x & ~NormalChunk.chunkMask, (int)pos.y & ~NormalChunk.chunkMask, (int)pos.z & ~NormalChunk.chunkMask).itemEntityManager;
		manager.add(pos.x, pos.y, pos.z, dir.x*velocity, dir.y*velocity, dir.z*velocity, stack, 30*300 /*5 minutes at normal update speed.*/);
	}
	
	@Override
	public void updateBlockData(int x, int y, int z, byte data) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if (ch != null) {
			ch.setBlockData(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask, data);
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
		for (int i = 0; i < entities.size(); i++) {
			Entity en = entities.get(i);
			en.update();
			// Check item entities:
			if(en.getInventory() != null) {
				int x0 = (int)(en.getPosition().x - en.width) & ~NormalChunk.chunkMask;
				int y0 = (int)(en.getPosition().y - en.width) & ~NormalChunk.chunkMask;
				int z0 = (int)(en.getPosition().z - en.width) & ~NormalChunk.chunkMask;
				int x1 = (int)(en.getPosition().x + en.width) & ~NormalChunk.chunkMask;
				int y1 = (int)(en.getPosition().y + en.width) & ~NormalChunk.chunkMask;
				int z1 = (int)(en.getPosition().z + en.width) & ~NormalChunk.chunkMask;
				if(getEntityManagerAt(x0, y0, z0) != null)
					getEntityManagerAt(x0, y0, z0).itemEntityManager.checkEntity(en);
				if(x0 != x1) {
					if(getEntityManagerAt(x1, y0, z0) != null)
						getEntityManagerAt(x1, y0, z0).itemEntityManager.checkEntity(en);
					if(y0 != y1) {
						if(getEntityManagerAt(x0, y1, z0) != null)
							getEntityManagerAt(x0, y1, z0).itemEntityManager.checkEntity(en);
						if(getEntityManagerAt(x1, y1, z0) != null)
							getEntityManagerAt(x1, y1, z0).itemEntityManager.checkEntity(en);
						if(z0 != z1) {
							if(getEntityManagerAt(x0, y0, z1) != null)
								getEntityManagerAt(x0, y0, z1).itemEntityManager.checkEntity(en);
							if(getEntityManagerAt(x1, y0, z1) != null)
								getEntityManagerAt(x1, y0, z1).itemEntityManager.checkEntity(en);
							if(getEntityManagerAt(x0, y1, z1) != null)
								getEntityManagerAt(x0, y1, z1).itemEntityManager.checkEntity(en);
							if(getEntityManagerAt(x1, y1, z1) != null)
								getEntityManagerAt(x1, y1, z1).itemEntityManager.checkEntity(en);
						}
					}
				} else if(y0 != y1) {
					if(getEntityManagerAt(x0, y1, z0) != null)
						getEntityManagerAt(x0, y1, z0).itemEntityManager.checkEntity(en);
					if(z0 != z1) {
						if(getEntityManagerAt(x0, y0, z1) != null)
							getEntityManagerAt(x0, y0, z1).itemEntityManager.checkEntity(en);
						if(getEntityManagerAt(x0, y1, z1) != null)
							getEntityManagerAt(x0, y1, z1).itemEntityManager.checkEntity(en);
					}
				} else if(z0 != z1) {
					if(getEntityManagerAt(x0, y0, z1) != null)
						getEntityManagerAt(x0, y0, z1).itemEntityManager.checkEntity(en);
				}
			}
		}
		// Item Entities
		for(int i = 0; i < entityManagers.length; i++) {
			entityManagers[i].itemEntityManager.update();
		}
		// Block Entities
		for(MetaChunk chunk : metaChunks.values()) {
			chunk.updateBlockEntities();
		}
		
		// Liquids
		if (gameTime % 3 == 0 && world.inLqdUpdate) {
			world.inLqdUpdate = false;
			//Profiler.startProfiling();
			for(MetaChunk chunk : metaChunks.values()) {
				chunk.liquidUpdate();
			}
			//Profiler.printProfileTime("liquid-update");
		}
	}

	@Override
	public void queueChunk(Chunk ch) {
		try {
			loadList.put(ch);
		} catch (InterruptedException e) {
			System.err.println("Interrupted while queuing chunk. This is unexpected.");
		}
	}
	
	@Override
	public void unQueueChunk(Chunk ch) {
		loadList.remove(ch);
	}
	
	public int getChunkQueueSize() {
		return loadList.size();
	}
	
	@Override
	public void seek(int x, int y, int z, int renderDistance, int regionRenderDistance) {
		int xOld = x;
		int yOld = y;
		int zOld = z;
		// Care about the Regions:
		regionRenderDistance = (regionRenderDistance+Region.regionSize-1)/Region.regionSize;
		int local = x & Region.regionMask;
		x >>= Region.regionShift;
		x += regionRenderDistance;
		if(local >= Region.regionSize/2)
			x++;
		local = z & Region.regionMask;
		z >>= Region.regionShift;
		z += regionRenderDistance;
		if(local >= Region.regionSize/2)
			z++;
		int regionDRD = regionRenderDistance << 1;
		if(x != lastRegX || z != lastRegZ || regionDRD != regDRD) {
			Region[] newRegions = new Region[regionDRD*regionDRD];
			// Go through the old regions and put them in the new array:
			for(int i = 0; i < regions.length; i++) {
				if(regions[i] != null) {
					int dx = CubyzMath.moduloMatchSign((regions[i].wx >> Region.regionShift) - (x-regionDRD), worldSizeX >> Region.regionShift);
					int dz = CubyzMath.moduloMatchSign((regions[i].wz >> Region.regionShift) - (z-regionDRD), worldSizeZ >> Region.regionShift);
					if(dx >= 0 && dx < regionDRD && dz >= 0 && dz < regionDRD) {
						int index = dx*regionDRD + dz;
						newRegions[index] = regions[i];
					} else {
						regions[i].regIO.saveData();
					}
				}
			}
			regions = newRegions;
			lastRegX = x;
			lastRegZ = z;
			regDRD = regionDRD;
		}
		
		// Care about the metaChunks:
		if(xOld != lastX || yOld != lastY || zOld != lastZ) {
			ArrayList<NormalChunk> chunkList = new ArrayList<>();
			ArrayList<ChunkEntityManager> managers = new ArrayList<>();
			HashMap<HashMapKey3D, MetaChunk> newMetaChunks = new HashMap<HashMapKey3D, MetaChunk>();
			int metaRenderDistance = (int)Math.ceil(renderDistance/(float)(MetaChunk.metaChunkSize*NormalChunk.chunkSize));
			x = xOld;
			y = yOld;
			z = zOld;
			int x0 = x/(MetaChunk.metaChunkSize*NormalChunk.chunkSize);
			int y0 = y/(MetaChunk.metaChunkSize*NormalChunk.chunkSize);
			int z0 = z/(MetaChunk.metaChunkSize*NormalChunk.chunkSize);
			for(int metaX = x0 - metaRenderDistance; metaX <= x0 + metaRenderDistance + 1; metaX++) {
				for(int metaY = y0 - metaRenderDistance; metaY <= y0 + metaRenderDistance + 1; metaY++) {
					for(int metaZ = z0 - metaRenderDistance; metaZ <= z0 + metaRenderDistance + 1; metaZ++) {
						int xReal = CubyzMath.worldModulo(metaX, worldSizeX/(MetaChunk.metaChunkSize*NormalChunk.chunkSize));
						int zReal = CubyzMath.worldModulo(metaZ, worldSizeZ/(MetaChunk.metaChunkSize*NormalChunk.chunkSize));
						HashMapKey3D key = new HashMapKey3D(xReal, metaY, zReal);
						// Check if it already exists:
						MetaChunk metaChunk = metaChunks.get(key);
						if(metaChunk == null) {
							metaChunk = new MetaChunk(xReal*(MetaChunk.metaChunkSize*NormalChunk.chunkSize), metaY*(MetaChunk.metaChunkSize*NormalChunk.chunkSize), zReal*(MetaChunk.metaChunkSize*NormalChunk.chunkSize), this);
						}
						newMetaChunks.put(key, metaChunk);
						metaChunk.updatePlayer(xOld, yOld, zOld, renderDistance, Settings.entityDistance, chunkList, managers);
					}
				}
			}
			chunks = chunkList.toArray(new NormalChunk[0]);
			entityManagers = managers.toArray(new ChunkEntityManager[0]);
			metaChunks = newMetaChunks;
			lastX = xOld;
			lastY = yOld;
			lastZ = zOld;
		}
	}
	
	public void setBlocks(Block[] blocks) {
		torusBlocks = blocks;
	}

	@Override
	public Region getRegion(int wx, int wz, int voxelSize) {
		wx &= ~Region.regionMask;
		wz &= ~Region.regionMask;
		int x = wx >> Region.regionShift;
		int z = wz >> Region.regionShift;
		// Test if the chunk can be found in the list of visible chunks:
		int dx = CubyzMath.moduloMatchSign(x - (lastRegX - regDRD/2), worldSizeX >> Region.regionShift) + regDRD/2;
		int dz = CubyzMath.moduloMatchSign(z - (lastRegZ - regDRD/2), worldSizeZ >> Region.regionShift) + regDRD/2;
		if(dx >= 0 && dx < regDRD && dz >= 0 && dz < regDRD) {
			int index = dx*regDRD + dz;
			synchronized(regions) {
				Region ret = regions[index];
				
				if (ret != null) {
					ret.ensureResolution(getSeed(), registries, voxelSize);
					return ret;
				} else {
					Region reg = new Region(wx, wz, localSeed, this, registries, tio, voxelSize);
					regions[index] = reg;
					return reg;
				}
			}
		}
		return new Region(wx, wz, localSeed, this, registries, tio, voxelSize);
	}
	
	public Region getNoGenerateRegion(int wx, int wy) {
		for(Region reg : regions) {
			if(reg.wx == wx && reg.wz == wy) {
				return reg;
			}
		}
		return null;
	}
	
	public MetaChunk getMetaChunk(int cx, int cy, int cz) {
		cx = CubyzMath.worldModulo(cx, worldSizeX >> NormalChunk.chunkShift);
		cz = CubyzMath.worldModulo(cz, worldSizeZ >> NormalChunk.chunkShift);
		// Test if the metachunk exists:
		int metaX = cx >> (MetaChunk.metaChunkShift);
		int metaY = cy >> (MetaChunk.metaChunkShift);
		int metaZ = cz >> (MetaChunk.metaChunkShift);
		HashMapKey3D key = new HashMapKey3D(metaX, metaY, metaZ);
		return metaChunks.get(key);
	}
	
	@Override
	public NormalChunk getChunk(int cx, int cy, int cz) {
		cx = CubyzMath.worldModulo(cx, worldSizeX >> NormalChunk.chunkShift);
		cz = CubyzMath.worldModulo(cz, worldSizeZ >> NormalChunk.chunkShift);
		MetaChunk meta = getMetaChunk(cx, cy, cz);
		if(meta != null) {
			return meta.getChunk(cx, cy, cz);
		}
		return null;
	}

	@Override
	public ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz) {
		int cx = wx >> NormalChunk.chunkShift;
		int cy = wy >> NormalChunk.chunkShift;
		int cz = wz >> NormalChunk.chunkShift;
		cx = CubyzMath.worldModulo(cx, worldSizeX >> NormalChunk.chunkShift);
		cz = CubyzMath.worldModulo(cz, worldSizeZ >> NormalChunk.chunkShift);
		MetaChunk meta = getMetaChunk(cx, cy, cz);
		if(meta != null) {
			return meta.getEntityManager(cx, cy, cz);
		}
		return null;
	}
	
	@Override
	public ChunkEntityManager[] getEntityManagers() {
		return entityManagers;
	}

	@Override
	public Block getBlock(int x, int y, int z) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if (ch != null && ch.isGenerated()) {
			Block b = ch.getBlock(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask);
			return b;
		} else {
			return null;
		}
	}
	
	@Override
	public byte getBlockData(int x, int y, int z) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if (ch != null && ch.isGenerated()) {
			return ch.getBlockData(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask);
		} else {
			return 0;
		}
	}
	
	public long getSeed() {
		return localSeed;
	}
	
	public float getGlobalLighting() {
		return ambientLight;
	}

	@Override
	public Vector4f getClearColor() {
		return clearColor;
	}

	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		/*BlockInstance bi = getBlockInstance(x, y, z);
		Chunk ck = _getNoGenerateChunk(bi.getX() >> NormalChunk.chunkShift, bi.getZ() >> NormalChunk.chunkShift);
		return ck.blockEntities().get(bi);*/
		return null; // TODO: Work on BlockEntities!
	}
	
	@Override
	public int getSizeX() {
		return worldSizeX;
	}
	
	@Override
	public int getSizeZ() {
		return worldSizeZ;
	}
	
	public ArrayList<CustomBlock> getCustomBlocks() {
		return customBlocks;
	}

	@Override
	public NormalChunk[] getChunks() {
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
	
	public int getHeight(int wx, int wz) {
		return (int)getRegion(wx, wz, 1).getHeight(wx, wz);
	}

	@Override
	public void cleanup() {
		// Be sure to dereference and finalize the maximum of things
		try {
			forceSave();
			
			for (Thread thread : generatorThreads) {
				thread.interrupt();
				thread.join();
			}
			generatorThreads = new ArrayList<>();

			// Clean up additional GPU data:
			for(MetaChunk chunk : metaChunks.values()) {
				chunk.cleanup();
			}
			
			metaChunks = null;
		} catch (Exception e) {
			Logger.throwable(e);
		}
	}

	@Override
	public CurrentSurfaceRegistries getCurrentRegistries() {
		return registries;
	}

	@Override
	public Biome getBiome(int wx, int wz) {
		Region reg = getRegion(wx, wz, 1);
		return reg.getBiome(wx, wz);
	}

	@Override
	public Vector3f getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if(ch == null || !ch.isLoaded() || !easyLighting)
			return new Vector3f(1, 1, 1);
		int light = ch.getLight(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask);
		int sun = (light >>> 24) & 255;
		int r = (light >>> 16) & 255;
		int g = (light >>> 8) & 255;
		int b = (light >>> 0) & 255;
		if(sun*sunLight.x > r) r = (int)(sun*sunLight.x);
		if(sun*sunLight.y > g) g = (int)(sun*sunLight.y);
		if(sun*sunLight.z > b) b = (int)(sun*sunLight.z);
		return new Vector3f(r/255.0f, g/255.0f, b/255.0f);
	}

	@Override
	public void getLight(int x, int y, int z, int[] array) {
		Block block = getBlock(x, y, z);
		if(block == null) return;
		int selfLight = block.getLight();
		x--;
		y--;
		z--;
		for(int ix = 0; ix < 3; ix++) {
			for(int iy = 0; iy < 3; iy++) {
				for(int iz = 0; iz < 3; iz++) {
					array[ix + iy*3 + iz*9] = getLight(x+ix, y+iy, z+iz, selfLight);
				}
			}
		}
	}
	
	private int getLight(int x, int y, int z, int minLight) {
		NormalChunk ch = getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
		if(ch == null || !ch.isLoaded())
			return 0xff000000;
		int light = ch.getLight(x & NormalChunk.chunkMask, y & NormalChunk.chunkMask, z & NormalChunk.chunkMask);
		// Make sure all light channels are at least as big as the minimum:
		if((light & 0xff000000) >>> 24 < (minLight & 0xff000000) >>> 24) light = (light & 0x00ffffff) | (minLight & 0xff000000);
		if((light & 0x00ff0000) < (minLight & 0x00ff0000)) light = (light & 0xff00ffff) | (minLight & 0x00ff0000);
		if((light & 0x0000ff00) < (minLight & 0x0000ff00)) light = (light & 0xffff00ff) | (minLight & 0x0000ff00);
		if((light & 0x000000ff) < (minLight & 0x000000ff)) light = (light & 0xffffff00) | (minLight & 0x000000ff);
		return light;
	}

	@Override
	public Type[][] getBiomeMap() {
		return biomeMap;
	}
}
