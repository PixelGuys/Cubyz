package io.spacycubyd;

import java.util.function.Consumer;
import java.util.function.Function;

import io.spacycubyd.blocks.Block;
import io.spacycubyd.blocks.BlockInstance;
import io.spacycubyd.blocks.IBlockSpatial;

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
