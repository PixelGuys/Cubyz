package io.cubyz;

import java.util.function.BiConsumer;
import java.util.function.Consumer;

import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.cubyz.items.Inventory;

public class ClientOnly {

	public static Consumer<Block> createBlockMesh;
	public static Consumer<EntityType> createEntityMesh;
	public static BiConsumer<String, Object> registerGui;
	public static BiConsumer<String, Inventory> openGui;
	
	static {
		createBlockMesh = (b) -> {
			throw new UnsupportedOperationException("createBlockMesh");
		};
	}
	
}
