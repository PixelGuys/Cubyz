package io.cubyz.world.cubyzgenerators;

import io.cubyz.blocks.Block;

// Some interface to access all different generators(caves,terrain,…) through one simple function.

public interface Generator {
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int cx, int cy, Block[][][] chunk);
}
