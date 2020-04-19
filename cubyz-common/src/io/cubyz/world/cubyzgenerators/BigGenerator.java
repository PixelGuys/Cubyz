package io.cubyz.world.cubyzgenerators;

import io.cubyz.blocks.Block;
import io.cubyz.world.LocalTorusSurface;

// A generate that needs access to the MetaChunks directly. Useful for generating big structures like rivers.

public interface BigGenerator extends Generator {
	abstract int getPriority(); // Used to prioritize certain generators(like map generation) over others(like vegetation generation).
	abstract void generate(long seed, int wx, int wy, Block[][][] chunk, boolean[][] vegetationIgnoreMap, LocalTorusSurface world); // Needs world coordinates!
	default void generate(long seed, int cx, int cy, Block[][][] chunk, boolean[][] vegetationIgnoreMap) {}
}
