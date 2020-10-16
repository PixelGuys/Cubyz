package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;

/**
 * If a structure is large enough to show up on reduced chunks, this interface should be added to the StructureModel.
 */

public interface ReducedStructureModel {
	abstract void generate(int x, int z, int height, ReducedChunk chunk, MetaChunk metaChunk, Random rand);
}
