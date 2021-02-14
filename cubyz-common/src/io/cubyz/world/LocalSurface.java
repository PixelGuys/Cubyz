package io.cubyz.world;

import java.io.File;
import java.lang.reflect.InvocationTargetException;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.BlockingDeque;
import java.util.concurrent.LinkedBlockingDeque;

import org.joml.Vector3f;
import org.joml.Vector4f;

import io.cubyz.ClientOnly;
import io.cubyz.Settings;
import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.CustomBlock;
import io.cubyz.blocks.Updateable;
import io.cubyz.blocks.Ore;
import io.cubyz.blocks.OreTextureProvider;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.blocks.CrystalTextureProvider;
import io.cubyz.entity.Entity;
import io.cubyz.entity.ItemEntityManager;
import io.cubyz.handler.PlaceBlockHandler;
import io.cubyz.handler.RemoveBlockHandler;
import io.cubyz.items.BlockDrop;
import io.cubyz.items.ItemStack;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.TorusIO;
import io.cubyz.util.FastList;
import io.cubyz.world.cubyzgenerators.CrystalCavernGenerator;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.Biome.Type;
import io.cubyz.world.cubyzgenerators.biomes.BiomeGenerator;
import io.cubyz.world.generator.LifelandGenerator;
import io.cubyz.world.generator.SurfaceGenerator;

import static io.cubyz.CubyzLogger.logger;

public class LocalSurface extends Surface {
	private static Random rnd = new Random();
	
	private Region[] regions;
	private NormalChunk[] chunks;
	private ReducedChunk[] reducedChunks;
	private ChunkEntityManager[] entityManagers;
	private int lastX = Integer.MAX_VALUE, lastZ = Integer.MAX_VALUE; // Chunk coordinates of the last chunk update.
	private int lastRegX = Integer.MAX_VALUE, lastRegZ = Integer.MAX_VALUE; // Region coordinates of the last chunk update.
	private int lastEntityX = Integer.MAX_VALUE, lastEntityZ = Integer.MAX_VALUE, doubleEntityRD;
	private int regDRD; // double renderdistance of Region.
	private int doubleRD; // Corresponds to the doubled value of the last used render distance.
	private final int worldSizeX = 65536, worldSizeZ = 16384;
	private ArrayList<Entity> entities = new ArrayList<>();
	
	private Block[] torusBlocks;
	
	private static int MAX_QUEUE_SIZE = 40;
	
	private SurfaceGenerator generator;
	
	private TorusIO tio;
	
	private List<ChunkGenerationThread> generatorThreads = new ArrayList<>();
	private boolean generated;
	
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);
	
	private final long localSeed; // Each torus has a different seed for world generation. All those seeds are generated using the main world seed.
	
	private final Biome.Type[][] biomeMap;
	
	// synchronized common list for chunk generation
	private volatile BlockingDeque<NormalChunk> loadList = new LinkedBlockingDeque<>(MAX_QUEUE_SIZE);
	private volatile BlockingDeque<ReducedChunk> reducedLoadList = new LinkedBlockingDeque<>(MAX_QUEUE_SIZE);
	
	private final Class<?> chunkProvider;
	
	boolean liquidUpdate;
	
	BlockEntity[] blockEntities = new BlockEntity[0];
	Integer[] liquids = new Integer[0];
	
	public CurrentSurfaceRegistries registries;

	private ArrayList<CustomBlock> customBlocks = new ArrayList<>();
	
	private void queue(NormalChunk ch) {
		if (!isQueued(ch)) {
			try {
				loadList.put(ch);
			} catch (InterruptedException e) {
				System.err.println("Interrupted while queuing chunk. This is unexpected.");
			}
		}
	}
	
	private boolean isQueued(NormalChunk ch) {
		NormalChunk[] list = loadList.toArray(new NormalChunk[0]);
		for (NormalChunk ch2 : list) {
			if (ch2 == ch) {
				return true;
			}
		}
		return false;
	}
	
	private void queue(ReducedChunk ch) {
		if (!isQueued(ch)) {
			try {
				reducedLoadList.put(ch);
			} catch (InterruptedException e) {
				System.err.println("Interrupted while queuing chunk. This is unexpected.");
			}
		}
	}
	
	private boolean isQueued(ReducedChunk ch) {
		ReducedChunk[] list = reducedLoadList.toArray(new ReducedChunk[0]);
		for (ReducedChunk ch2 : list) {
			if (ch2 == ch) {
				return true;
			}
		}
		return false;
	}
	
	private class ChunkGenerationThread extends Thread {
		volatile boolean running = true;
		public void run() {
			while (running) {
				if(!loadList.isEmpty()) {
					NormalChunk popped = null;
					try {
						popped = loadList.take();
					} catch (InterruptedException e) {
						break;
					}
					try {
						synchronousGenerate(popped);
						popped.load();
					} catch (Exception e) {
						logger.severe("Could not generate chunk " + popped.getX() + ", " + popped.getZ() + " !");
						logger.throwable(e);
					}
				} else if(!reducedLoadList.isEmpty()) {
					ReducedChunk popped = null;
					try {
						popped = reducedLoadList.take();
					} catch (InterruptedException e) {
						break;
					}
					try {
						generator.generate(popped, LocalSurface.this);
						popped.generated = true;
					} catch (Exception e) {
						logger.severe("Could not generate reduced chunk " + popped.cx + ", " + popped.cz + " !");
						logger.throwable(e);
					}
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
				chunkProvider.getConstructors()[0].getParameterTypes().length != 3 ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[0].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[1].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[2].equals(Surface.class))
			throw new IllegalArgumentException("Chunk provider "+chunkProvider+" is invalid! It needs to be a subclass of NormalChunk and MUST contain a single constructor with parameters (Integer, Integer, Surface)");
		regions = new Region[0];
		chunks = new NormalChunk[0];
		entityManagers = new ChunkEntityManager[0];
		reducedChunks = new ReducedChunk[0];
		
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
		
		biomeMap = BiomeGenerator.generateTypeMap(localSeed, worldSizeX/256, worldSizeZ/256);
		//setChunkQueueSize(torus.world.getRenderDistance() << 2);
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
	
	public void setChunkQueueSize(int size) {
		synchronized (loadList) {
			loadList.clear();
			MAX_QUEUE_SIZE = size;
			loadList = new LinkedBlockingDeque<>(size);
		}
		System.out.println("max queue size is now " + size);
	}

	
	public void forceSave() {
		for(NormalChunk chunk : chunks) {
			chunk.region.regIO.saveChunk(chunk);
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
	
	public void synchronousGenerate(NormalChunk ch) {
		ch.generateFrom(generator);
	}
	
	@Override
	public void removeBlock(int x, int y, int z) {
		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null) {
			Block b = ch.getBlockAt(x & 15, y, z & 15);
			ch.removeBlockAt(x & 15, y, z & 15, true);
			for (RemoveBlockHandler hand : removeBlockHandlers) {
				hand.onBlockRemoved(b, x, y, z);
			}
			// Fetch block drops:
			for(BlockDrop drop : b.getBlockDrops()) {
				int amount = (int)(drop.amount);
				float randomPart = drop.amount - amount;
				if(Math.random() < randomPart) amount++;
				if(amount > 0) {
					ItemEntityManager manager = this.getEntityManagerAt(x & ~15, z & ~15).itemEntityManager;
					manager.add(x, y, z, 0, 0, 0, new ItemStack(drop.item, amount), 30*300 /*5 minutes at normal update speed.*/);
				}
			}
		}
	}
	
	@Override
	public void placeBlock(int x, int y, int z, Block b, byte data) {
		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null) {
			ch.addBlock(b, data, x & 15, y, z & 15, false);
			for (PlaceBlockHandler hand : placeBlockHandlers) {
				hand.onBlockPlaced(b, x, y, z);
			}
		}
	}
	
	@Override
	public void drop(ItemStack stack, Vector3f pos, Vector3f dir, float velocity) {
		ItemEntityManager manager = this.getEntityManagerAt(((int)pos.x) & ~15, ((int)pos.z) & ~15).itemEntityManager;
		manager.add(pos.x, pos.y, pos.z, dir.x*velocity, dir.y*velocity, dir.z*velocity, stack, 30*300 /*5 minutes at normal update speed.*/);
	}
	
	@Override
	public void updateBlockData(int x, int y, int z, byte data) {
		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null) {
			ch.setBlockData(x & 15, y, z & 15, data);
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
				int x0 = (int)(en.getPosition().x - en.width) & ~15;
				int z0 = (int)(en.getPosition().z - en.width) & ~15;
				int x1 = (int)(en.getPosition().x + en.width) & ~15;
				int z1 = (int)(en.getPosition().z + en.width) & ~15;
				if(getEntityManagerAt(x0, z0) != null)
					getEntityManagerAt(x0, z0).itemEntityManager.checkEntity(en);
				if(x0 != x1) {
					if(getEntityManagerAt(x1, z0) != null)
						getEntityManagerAt(x1, z0).itemEntityManager.checkEntity(en);
					if(z0 != z1) {
						if(getEntityManagerAt(x0, z1) != null)
							getEntityManagerAt(x0, z1).itemEntityManager.checkEntity(en);
						if(getEntityManagerAt(x1, z1) != null)
							getEntityManagerAt(x1, z1).itemEntityManager.checkEntity(en);
					}
				} else if(z0 != z1) {
					if(getEntityManagerAt(x0, z1) != null)
						getEntityManagerAt(x0, z1).itemEntityManager.checkEntity(en);
				}
			}
		}
		// Item Entities
		for(int i = 0; i < entityManagers.length; i++) {
			entityManagers[i].itemEntityManager.update();
		}
		// Block Entities
		for (NormalChunk ch : chunks) {
			if (ch.isLoaded() && ch.getBlockEntities().size() > 0) {
				blockEntities = ch.getBlockEntities().toArray(blockEntities);
				for (BlockEntity be : blockEntities) {
					if (be == null) break; // end of array
					if (be instanceof Updateable) {
						Updateable tk = (Updateable) be;
						tk.update(false);
						if (tk.randomUpdates()) {
							if (rnd.nextInt(5) < 1) { // 1/5 chance
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
			for (NormalChunk ch : chunks) {
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
									ch.addBlockPossiblyOutside(block, (byte)0, CubyzMath.worldModulo(wx+bx+dx, worldSizeX), by+dy, CubyzMath.worldModulo(wz+bz+dz, worldSizeZ), true);
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
	public void queueChunk(NormalChunk ch) {
		queue(ch);
	}
	

	public void unQueueChunk(NormalChunk ch) {
		loadList.remove(ch);
	}

	public void queueChunk(ReducedChunk ch) {
		queue(ch);
	}

	public void unQueueChunk(ReducedChunk ch) {
		reducedLoadList.remove(ch);
	}
	
	@Override
	public void seek(int x, int z, int renderDistance, int highestLOD, float LODFactor) {
		int xOld = x;
		int zOld = z;
		// Care about the Regions:
		int mcRD = (renderDistance*10 >>> 4) + 4;
		int local = x & 255;
		x >>= 8;
		x += mcRD;
		if(local > 127)
			x++;
		local = z & 255;
		z >>= 8;
		z += mcRD;
		if(local > 127)
			z++;
		if(x != lastRegX || z != lastRegZ) {
			int mcDRD = mcRD << 1;
			Region[] newRegions = new Region[mcDRD*mcDRD];
			// Go through the old regions and put them in the new array:
			for(int i = 0; i < regions.length; i++) {
				if(regions[i] != null) {
					int dx = CubyzMath.moduloMatchSign((regions[i].wx >> 8) - (x-mcDRD), worldSizeX >> 8);
					int dz = CubyzMath.moduloMatchSign((regions[i].wz >> 8) - (z-mcDRD), worldSizeZ >> 8);
					if(dx >= 0 && dx < mcDRD && dz >= 0 && dz < mcDRD) {
						int index = dx*mcDRD + dz;
						newRegions[index] = regions[i];
					} else {
						regions[i].regIO.saveData();
					}
				}
			}
			regions = newRegions;
			lastRegX = x;
			lastRegZ = z;
			this.regDRD = mcDRD;
		}

		// Care about the Chunks:
		x = xOld;
		z = zOld;
		local = x & 15;
		x >>= 4;
		x += renderDistance;
		if(local > 7)
			x++;
		local = z & 15;
		z >>= 4;
		z += renderDistance;
		if(local > 7)
			z++;
		if(x != lastX || z != lastZ) {
			int doubleRD = renderDistance << 1;
			NormalChunk [] newVisibles = new NormalChunk[doubleRD*doubleRD];
			// Go through the old chunks and put them in the new array:
			for(int i = 0; i < chunks.length; i++) {
				int dx = CubyzMath.moduloMatchSign(chunks[i].cx - (x-doubleRD), worldSizeX >> 4);
				int dz = CubyzMath.moduloMatchSign(chunks[i].cz - (z-doubleRD), worldSizeZ >> 4);
				if(dx >= 0 && dx < doubleRD && dz >= 0 && dz < doubleRD) {
					int index = dx*doubleRD + dz;
					newVisibles[index] = chunks[i];
				} else {
					if(chunks[i].isGenerated())
						chunks[i].region.regIO.saveChunk(chunks[i]); // Only needs to be stored if it was ever generated.
					else
						unQueueChunk(chunks[i]);
					ClientOnly.deleteChunkMesh.accept(chunks[i]);
				}
			}
			// Fill the gaps:
			ArrayList<NormalChunk> chunksToQueue = new ArrayList<>();
			int index = 0;
			for(int i = x-doubleRD; i < x; i++) {
				for(int j = z-doubleRD; j < z; j++) {
					if(newVisibles[index] != null) {
						index++;
						continue;
					}
					try {
						NormalChunk ch = (NormalChunk)chunkProvider.getDeclaredConstructors()[0].newInstance(CubyzMath.worldModulo(i, worldSizeX >> 4), CubyzMath.worldModulo(j, worldSizeZ >> 4), this);
						chunksToQueue.add(ch);
						newVisibles[index] = ch;
						index++;
					} catch (InstantiationException e) {
						e.printStackTrace();
					} catch (IllegalAccessException e) {
						e.printStackTrace();
					} catch (IllegalArgumentException e) {
						e.printStackTrace();
					} catch (InvocationTargetException e) {
						e.printStackTrace();
					} catch (SecurityException e) {
						e.printStackTrace();
					}
				}
			}
			chunks = newVisibles;
			lastX = x;
			lastZ = z;
			this.doubleRD = doubleRD;
			
			// Load chunks after they have access to their neighbors:
			for(NormalChunk ch : chunksToQueue) {
				queueChunk(ch);
			}
			// Save the data:
			tio.saveTorusData(this);
			
			int entityDistance = Math.min(Settings.entityDistance, renderDistance);
			
			// Update the entity managers:
			x += entityDistance - renderDistance;
			z += entityDistance - renderDistance;
			ChunkEntityManager [] newManagers = new ChunkEntityManager[entityDistance*entityDistance*4];
			// Go through the old managers and put them in the new array:
			for(int i = 0; i < entityManagers.length; i++) {
				int dx = CubyzMath.moduloMatchSign((entityManagers[i].wx >> 4) - (x - entityDistance*2), worldSizeX >> 4);
				int dz = CubyzMath.moduloMatchSign((entityManagers[i].wz >> 4) - (z - entityDistance*2), worldSizeZ >> 4);
				if(dx >= 0 && dx < entityDistance*2 && dz >= 0 && dz < entityDistance*2) {
					index = dx*entityDistance*2 + dz;
					newManagers[index] = entityManagers[i];
				} else {
					if(entityManagers[i].chunk.isGenerated())
						entityManagers[i].chunk.region.regIO.saveItemEntities(entityManagers[i].itemEntityManager); // Only needs to be stored if it was ever generated.
				}
			}
			// Fill the gaps:
			index = 0;
			for(int i = x - 2*entityDistance; i < x; i++) {
				for(int j = z - 2*entityDistance; j < z; j++) {
					if(newManagers[index] == null) {
						newManagers[index] = new ChunkEntityManager(this, this.getChunk(CubyzMath.worldModulo(i, worldSizeX >> 4), CubyzMath.worldModulo(j, worldSizeZ >> 4)));
					}
					index++;
				}
			}
			entityManagers = newManagers;
			this.doubleEntityRD = 2*entityDistance;
			lastEntityX = x;
			lastEntityZ = z;
		}

		// Care about the ReducedChunks:
		generateReducedChunks(xOld, zOld, (int)(renderDistance*LODFactor), highestLOD);
	}
	
	public void generateReducedChunks(int x, int z, int renderDistance, int maxResolution) {
		int local = x & 15;
		x >>= 4;
		if(local > 7)
			x++;
		local = z & 15;
		z >>= 4;
		if(local > 7)
			z++;
		// Go through all resolutions:
		FastList<ReducedChunk> newReduced = new FastList<ReducedChunk>(reducedChunks.length, ReducedChunk.class);
		int minXLast = x - doubleRD/2;
		int maxXLast = x + doubleRD/2;
		int minZLast = z - doubleRD/2;
		int maxZLast = z + doubleRD/2;
		renderDistance &= ~1; // Make sure the render distance is a multiple of 2, so the chunks are always placed correctly.
		int minK = 0;
		int widthShift = 4;
		ArrayList<ReducedChunk> reducedChunksToQueue = new ArrayList<>();
		for(int res = 1; res <= maxResolution; res++) {
			int widthShiftOld = widthShift;
			int widthOld = 1 << (widthShift - 4);
			widthShift++;
			int widthNew = 1 << (widthShift - 4);
			int widthMask = widthNew - 1;
			// Pad between the different chunk sizes:
			int minXNew = minXLast;
			int maxXNew = maxXLast;
			int minZNew = minZLast;
			int maxZNew = maxZLast;
			if((minXNew & widthMask) != 0) minXNew -= widthOld;
			if((maxXNew & widthMask) != 0) maxXNew += widthOld;
			if((minZNew & widthMask) != 0) minZNew -= widthOld;
			if((maxZNew & widthMask) != 0) maxZNew += widthOld;
			for(int cx = minXNew; cx < maxXNew; cx += widthOld) {
				loop:
				for(int cz = minZNew; cz < maxZNew; cz += widthOld) {
					boolean visible = cx < minXLast || cx >= maxXLast || cz < minZLast || cz >= maxZLast;
					if(!visible) continue;
					for(int k = minK; k < reducedChunks.length; k++) {
						if(reducedChunks[k].resolutionShift == res && reducedChunks[k].widthShift == widthShiftOld && CubyzMath.moduloMatchSign(reducedChunks[k].cx-cx, worldSizeX >> 4) == 0 && CubyzMath.moduloMatchSign(reducedChunks[k].cz-cz, worldSizeZ >> 4) == 0) {
							newReduced.add(reducedChunks[k]);
							// Removes this chunk out of the list of chunks that will be considered in this function.
							reducedChunks[k] = reducedChunks[minK];
							reducedChunks[minK] = newReduced.array[newReduced.size - 1];
							minK++;
							continue loop;
						}
					}
					ReducedChunk ch = new ReducedChunk(cx, cz, res, widthShiftOld);
					reducedChunksToQueue.add(ch);
					newReduced.add(ch);
					
				}
			}
			// Now add the real chunks:
			minXLast = minXNew;
			maxXLast = maxXNew;
			minZLast = minZNew;
			maxZLast = maxZNew;
			minXNew = minXLast - renderDistance;
			maxXNew = maxXLast + renderDistance;
			minZNew = minZLast - renderDistance;
			maxZNew = maxZLast + renderDistance;
			for(int cx = minXNew; cx < maxXNew; cx += widthNew) {
				loop:
				for(int cz = minZNew; cz < maxZNew; cz += widthNew) {
					boolean visible = cx < minXLast || cx >= maxXLast || cz < minZLast || cz >= maxZLast;
					if(!visible) continue;
					for(int k = minK; k < reducedChunks.length; k++) {
						if(reducedChunks[k].resolutionShift == res && reducedChunks[k].widthShift == widthShift && CubyzMath.moduloMatchSign(reducedChunks[k].cx-cx, worldSizeX >> 4) == 0 && CubyzMath.moduloMatchSign(reducedChunks[k].cz-cz, worldSizeZ >> 4) == 0) {
							newReduced.add(reducedChunks[k]);
							// Removes this chunk out of the list of chunks that will be considered in this function.
							reducedChunks[k] = reducedChunks[minK];
							reducedChunks[minK] = newReduced.array[newReduced.size - 1];
							minK++;
							continue loop;
						}
					}
					ReducedChunk ch = new ReducedChunk(cx, cz, res, widthShift);
					reducedChunksToQueue.add(ch);
					newReduced.add(ch);
					
				}
			}
			minXLast = minXNew;
			maxXLast = maxXNew;
			minZLast = minZNew;
			maxZLast = maxZNew;
			renderDistance *= 2;
		}
		for (int k = minK; k < reducedChunks.length; k++) {
			unQueueChunk(reducedChunks[k]);
			ClientOnly.deleteChunkMesh.accept(reducedChunks[k]);
		}
		newReduced.trimToSize();
		reducedChunks = newReduced.array;
		// Load chunks after they have access to their neighbors:
		for(ReducedChunk ch : reducedChunksToQueue) {
			queueChunk(ch);
		}
	}
	
	public void setBlocks(Block[] blocks) {
		torusBlocks = blocks;
	}
	
	public void getMapData(int x, int z, int width, int height, float [][] heightMap, Biome[][] biomeMap) {
		int x0 = x&(~255);
		int z0 = z&(~255);
		for(int px = x0; CubyzMath.moduloMatchSign(px - x, worldSizeX) < width; px += 256) {
			for(int pz = z0; CubyzMath.moduloMatchSign(pz-z, worldSizeZ) < height; pz += 256) {
				Region ch = getRegion(CubyzMath.worldModulo(px, worldSizeX), CubyzMath.worldModulo(pz, worldSizeZ));
				int xS = Math.max(px-x, 0);
				int zS = Math.max(pz-z, 0);
				int xE = Math.min(px + 256 - x, width);
				int zE = Math.min(pz + 256 - z, height);
				for(int cx = xS; cx < xE; cx++) {
					for(int cz = zS; cz < zE; cz++) {
						heightMap[cx][cz] = ch.heightMap[(cx + x) & 255][(cz + z) & 255];
						biomeMap[cx][cz] = ch.biomeMap[(cx + x) & 255][(cz + z) & 255];
					}
				}
			}
		}
	}

	
	@Override
	public Region getRegion(int wx, int wz) {
		wx &= ~255;
		wz &= ~255;
		int x = wx >> 8;
		int z = wz >> 8;
		// Test if the chunk can be found in the list of visible chunks:
		int dx = CubyzMath.moduloMatchSign(x-(lastRegX-regDRD), worldSizeX >> 8);
		int dz = CubyzMath.moduloMatchSign(z-(lastRegZ-regDRD), worldSizeZ >> 8);
		if(dx >= 0 && dx < regDRD && dz >= 0 && dz < regDRD) {
			int index = dx*regDRD + dz;
			synchronized(regions) {
				Region ret = regions[index];
				
				if (ret != null) {
					return ret;
				} else {
					Region reg = new Region(wx, wz, localSeed, this, registries, tio);
					regions[index] = reg;
					return reg;
				}
			}
		}
		return new Region(wx, wz, localSeed, this, registries, tio);
	}
	
	public Region getNoGenerateRegion(int wx, int wy) {
		for(Region reg : regions) {
			if(reg.wx == wx && reg.wz == wy) {
				return reg;
			}
		}
		return null;
	}
	
	@Override
	public NormalChunk getChunk(int x, int z) {
		// Test if the chunk can be found in the list of visible chunks:
		int dx = CubyzMath.moduloMatchSign(x-(lastX-doubleRD), worldSizeX >> 4);
		int dz = CubyzMath.moduloMatchSign(z-(lastZ-doubleRD), worldSizeZ >> 4);
		if(dx >= 0 && dx < doubleRD && dz >= 0 && dz < doubleRD) {
			int index = dx*doubleRD + dz;
			return chunks[index];
		}
		return null;
	}

	@Override
	public ChunkEntityManager getEntityManagerAt(int wx, int wz) {
		int x = wx >> 4;
		int z = wz >> 4;
		// Test if the chunk can be found in the list of visible chunks:
		int dx = CubyzMath.moduloMatchSign(x-(lastEntityX-doubleEntityRD), worldSizeX >> 4);
		int dz = CubyzMath.moduloMatchSign(z-(lastEntityZ-doubleEntityRD), worldSizeZ >> 4);
		if(dx >= 0 && dx < doubleEntityRD && dz >= 0 && dz < doubleEntityRD) {
			int index = dx*doubleEntityRD + dz;
			return entityManagers[index];
		}
		return null;
	}
	
	@Override
	public ChunkEntityManager[] getEntityManagers() {
		return entityManagers;
	}

	@Override
	public Block getBlock(int x, int y, int z) {
		if (y > World.WORLD_HEIGHT || y < 0)
			return null;

		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null && ch.isGenerated()) {
			Block b = ch.getBlockAt(x & 15, y, z & 15);
			return b;
		} else {
			return null;
		}
	}
	
	@Override
	public byte getBlockData(int x, int y, int z) {
		if (y > World.WORLD_HEIGHT || y < 0)
			return 0;

		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if (ch != null && ch.isGenerated()) {
			return ch.getBlockData(x & 15, y, z & 15);
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
	
	public int getHeight(int x, int z) {
		return (int)(getRegion(x & ~255, z & ~255).heightMap[x & 255][z & 255]);
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
			for(ReducedChunk chunk : reducedChunks) {
				ClientOnly.deleteChunkMesh.accept(chunk);
			}
			for(NormalChunk chunk : chunks) {
				ClientOnly.deleteChunkMesh.accept(chunk);
			}
			
			reducedChunks = null;
			chunks = null;
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	@Override
	public CurrentSurfaceRegistries getCurrentRegistries() {
		return registries;
	}

	@Override
	public Biome getBiome(int x, int z) {
		Region reg = getRegion(x & ~255, z & ~255);
		return reg.biomeMap[x & 255][z & 255];
	}

	@Override
	public Vector3f getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if(ch == null || !ch.isLoaded() || !easyLighting)
			return new Vector3f(1, 1, 1);
		int light = ch.getLight(x & 15, y, z & 15);
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
		NormalChunk ch = getChunk(x >> 4, z >> 4);
		if(ch == null || !ch.isLoaded())
			return 0xff000000;
		int light = ch.getLight(x & 15, y, z & 15);
		// Make sure all light channels are at least as big as the minimum:
		if((light & 0xff000000) >>> 24 < (minLight & 0xff000000) >>> 24) light = (light & 0x00ffffff) | (minLight & 0xff000000);
		if((light & 0x00ff0000) < (minLight & 0x00ff0000)) light = (light & 0xff00ffff) | (minLight & 0x00ff0000);
		if((light & 0x0000ff00) < (minLight & 0x0000ff00)) light = (light & 0xffff00ff) | (minLight & 0x0000ff00);
		if((light & 0x000000ff) < (minLight & 0x000000ff)) light = (light & 0xffffff00) | (minLight & 0x000000ff);
		return light;
	}

	@Override
	public ReducedChunk[] getReducedChunks() {
		return reducedChunks;
	}

	@Override
	public Type[][] getBiomeMap() {
		return biomeMap;
	}
}
