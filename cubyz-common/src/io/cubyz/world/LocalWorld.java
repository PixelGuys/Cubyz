package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Ore;
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
	private StellarTorus currentTorus;
	private long milliTime;
	private long gameTime;
	public boolean inLqdUpdate;
	private int renderDistance = 5;
	private WorldIO wio;
	
	public LocalWorld(String name) {
		this.name = name;
		
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
	public StellarTorus getCurrentTorus() {
		return currentTorus;
	}
	
	// Returns the blocks, so their meshes can be created and stored.
	public Block[] generate() {
		if (!generated) seed = rnd.nextInt();
		Random rand = new Random(seed);
		int randomAmount = 9 + (int)(Math.random()*3); // Generate 9-12 random ores.
		blocks = new Block[CubyzRegistries.BLOCK_REGISTRY.registered().length+randomAmount];
		// Set the IDs again every time a new world is loaded. This is necessary, because the random block creation would otherwise mess with it.
		int ID = 0;
		ArrayList<Ore> ores = new ArrayList<Ore>();
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(!b.isTransparent()) {
				b.ID = ID;
				blocks[ID] = b;
				ID++;
			}
		}
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			if(b.isTransparent()) {
				b.ID = ID;
				blocks[ID] = b;
				ID++;
			}
			try {
				ores.add((Ore)b);
			}
			catch(Exception e) {}
		}
		LifelandGenerator.initOres(ores.toArray(new Ore[ores.size()]));
		if(generated) {
			wio.loadWorldData(); // TODO: fix
		}
		generated = true;
		currentTorus = new LocalStellarTorus(this, rand.nextLong());
		toruses.add(currentTorus);
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
