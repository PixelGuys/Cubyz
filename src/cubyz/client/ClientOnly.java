package cubyz.client;

import java.util.function.Consumer;

import cubyz.api.ClientConnection;
import cubyz.world.blocks.Block;
import cubyz.world.entity.EntityType;

/**
 * A collection of mostly functions that are only available in the client context.
 */

public class ClientOnly {

	public static Consumer<Block[]> generateTextureAtlas;
	public static Consumer<Block> createBlockMesh;
	public static Consumer<EntityType> createEntityMesh;
	
	// I didn't know where else to put it.
	public static ClientConnection client;
	
	static {
		createBlockMesh = (b) -> {
			throw new UnsupportedOperationException("createBlockMesh");
		};
	}
	
}
