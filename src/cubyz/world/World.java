package cubyz.world;

import java.util.List;

import cubyz.world.blocks.Block;
import cubyz.world.entity.Player;

/**
 * Base class for Cubyz worlds.
 */

public abstract class World {

	protected int seed;
	
	public abstract Player getLocalPlayer();

	public abstract void cleanup();
	
	public abstract Block [] getBlocks();
	
	public abstract long getGameTime();
	public abstract void setGameTime(long time);
	
	public boolean isLocal() {
		return this instanceof LocalWorld;
	}
	
	public void setSeed(int seed) {
		this.seed = seed;
	}
	
	public int getSeed() {
		return seed;
	}
	
	public void setName(String name) {
		throw new UnsupportedOperationException();
	}
	
	public String getName() {
		throw new UnsupportedOperationException();
	}
	
	public abstract List<StellarTorus> getToruses();
	
	public void update() {}

}
