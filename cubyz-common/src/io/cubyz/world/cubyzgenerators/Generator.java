package io.cubyz.world.cubyzgenerators;

import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;

// Some interface to access all different generators(caves,terrain,…) through one simple function.

public interface Generator extends IRegistryElement {
	
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int cx, int cy, Block[][][] chunk, boolean[][] vegetationIgnoreMap);
	
	@Override
	public default void setID(int id) {
		throw new UnsupportedOperationException();
	}
	
}
