package io.cubyz;

import java.util.function.Consumer;
import java.util.function.Function;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.blocks.IBlockSpatial;

public class ClientOnly {

	public static Function<BlockInstance, IBlockSpatial> createBlockSpatial;
	public static Consumer<Block> createBlockMesh;
	
	static {
		createBlockSpatial = (b) -> {
			throw new UnsupportedOperationException("createBlockSpatial");
		};
		createBlockMesh = (b) -> {
			throw new UnsupportedOperationException("createBlockSpatial");
		};
	}
	
}
