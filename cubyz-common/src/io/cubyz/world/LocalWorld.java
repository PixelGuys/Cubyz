package io.cubyz.world;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Ore;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.save.WorldIO;
import io.cubyz.world.generator.LifelandGenerator;

public class LocalWorld extends World {
	
	private Block[] blocks;
	private Player player;
	protected boolean generated;
	protected Random rnd;
	protected String name;
	
	private ArrayList<StellarTorus> toruses = new ArrayList<>();
	private LocalSurface currentTorus;
	private long milliTime;
	private long gameTime;
	public boolean inLqdUpdate;
	private int renderDistance = 5;
	private WorldIO wio;
	
	public LocalWorld(String name) {
		this.name = name;
		wio = new WorldIO(this, new File("saves/" + name));
		if (wio.hasWorldData()) {
			wio.loadWorldSeed();
			wio.loadWorldData();
			generated = true;
		} else {
			this.seed = new Random().nextInt();
			wio.saveWorldData();
		}
		rnd = new Random(seed);
	}
	
	public void forceSave() {
		wio.saveWorldData();
	}
	
	public String getName() {
		return name;
	}
	
	public void setName(String name) {
		this.name = name;
	}
	
	@Override
	public Player getLocalPlayer() {
		return player;
	}

	@Override
	public Block[] getBlocks() {
		return blocks;
	}

	@Override
	public long getGameTime() {
		return gameTime;
	}

	@Override
	public void setGameTime(long time) {
		this.gameTime = time;
	}

	@Override
	public void setRenderDistance(int RD) {
		renderDistance = RD;
	}

	@Override
	public int getRenderDistance() {
		return renderDistance;
	}

	@Override
	public List<StellarTorus> getToruses() {
		return toruses;
	}

	@Override
	public LocalSurface getCurrentTorus() {
		return currentTorus;
	}
	
	public void setCurrentTorusID(long seed) {
		LocalStellarTorus torus = new LocalStellarTorus(this, seed);
		currentTorus = new LocalSurface(torus);
		currentTorus.link();
		toruses.add(torus);
	}
	
	// Returns the blocks, so their meshes can be created and stored.
	public Block[] generate() {
		if (!generated) {
			seed = rnd.nextInt();
		}
		Random rand = new Random(seed);
		if (currentTorus == null) {
			LocalStellarTorus torus = new LocalStellarTorus(this, rand.nextLong());
			currentTorus = new LocalSurface(torus);
			currentTorus.link();
			toruses.add(torus);
		}
		ArrayList<Block> blockList = new ArrayList<>();
		// Set the IDs again every time a new world is loaded. This is necessary, because the random block creation would otherwise mess with it.
		int ID = 0;
		ArrayList<Ore> ores = new ArrayList<Ore>();
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(!b.isTransparent()) {
				b.ID = ID;
				blockList.add(b);
				ID++;
			}
		}
		// Generate the ores of the current torus:
		if(currentTorus != null && currentTorus instanceof LocalSurface) {
			ID = currentTorus.generate(blockList, ores, ID);
		}
		
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(b.isTransparent()) {
				b.ID = ID;
				blockList.add(b);
				ID++;
			}
			try {
				ores.add((Ore)b);
			}
			catch(Exception e) {}
		}
		LifelandGenerator.initOres(ores.toArray(new Ore[ores.size()]));
		generated = true;
		for (Entity ent : currentTorus.getEntities()) {
			System.out.println(ent);
			if (ent instanceof Player) {
				player = (Player) ent;
			}
		}
		if (player == null) {
			player = (Player) CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity();
			player.setStellarTorus(currentTorus.getStellarTorus());
			currentTorus.addEntity(player);
		}
		wio.saveWorldData();
		blocks = blockList.toArray(new Block[0]);
		return blocks;
	}
	
	@Override
	public void cleanup() {
		
	}
	
	boolean loggedUpdSkip = false;
	boolean DO_LATE_UPDATES = false;
	public void update() {
		// Time
		if(milliTime + 100 < System.currentTimeMillis()) {
			milliTime += 100;
			inLqdUpdate = true;
			gameTime++; // gameTime is measured in 100ms.
			if ((milliTime + 100) < System.currentTimeMillis()) { // we skipped updates
				if (!loggedUpdSkip) {
					if (DO_LATE_UPDATES) {
						CubyzLogger.i.warning(((System.currentTimeMillis() - milliTime) / 100) + " updates late! Doing them.");
					} else {
						CubyzLogger.i.warning(((System.currentTimeMillis() - milliTime) / 100) + " updates skipped!");
					}
					loggedUpdSkip = true;
				}
				if (DO_LATE_UPDATES) {
					update();
				} else {
					milliTime = System.currentTimeMillis();
				}
			} else {
				loggedUpdSkip = false;
			}
		}
		
		currentTorus.update();
	}

}
