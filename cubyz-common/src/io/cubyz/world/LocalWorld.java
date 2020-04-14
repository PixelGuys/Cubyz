package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.CustomOre;
import io.cubyz.blocks.Ore;
import io.cubyz.entity.Player;
import io.cubyz.world.generator.LifelandGenerator;

public class LocalWorld extends World {
	
	private Block[] blocks;
	private Player player;
	protected boolean generated;
	protected Random rnd;
	
	private ArrayList<StellarTorus> toruses = new ArrayList<>();
	private StellarTorus homeTorus;
	
	@Override
	public Player getLocalPlayer() {
		return null;
	}

	@Override
	public Block[] getBlocks() {
		return blocks;
	}

	@Override
	public long getGameTime() {
		return 0;
	}

	@Override
	public void setGameTime(long time) {
		
	}

	@Override
	public void setRenderDistance(int RD) {
		
	}

	@Override
	public int getRenderDistance() {
		return 0;
	}

	@Override
	public List<StellarTorus> getToruses() {
		return toruses;
	}

	@Override
	public StellarTorus getHomeTorus() {
		return homeTorus;
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
		
		homeTorus = new LocalStellarTorus(this);
		toruses.add(homeTorus);
		return blocks;
	}
	
	@Override
	public void cleanup() {
		
	}

}
