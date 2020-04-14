package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;

import org.joml.Vector3i;
import org.joml.Vector4f;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockEntity;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.handler.BlockVisibilityChangeHandler;
import io.cubyz.handler.Handler;
import io.cubyz.handler.PlaceBlockHandler;
import io.cubyz.handler.RemoveBlockHandler;

/**
 * Base class for Cubyz worlds.
 */
public abstract class World {

	public static final int WORLD_HEIGHT = 256;
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
	
	public abstract void setRenderDistance(int RD);
	public abstract int getRenderDistance();
	
	public abstract List<StellarTorus> getToruses();
	public abstract StellarTorus getHomeTorus();
	
	public void update() {}

}
