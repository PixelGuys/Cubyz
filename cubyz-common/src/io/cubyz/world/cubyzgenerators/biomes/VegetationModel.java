package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.blocks.Block;

// A simple model that describes how vegetation should be generated.

public interface VegetationModel {
	boolean considerCoordinates(int x, int y, int h, Block[][][] chunk, float random);
}