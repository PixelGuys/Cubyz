package io.cubyz;

import java.util.function.Consumer;

import io.cubyz.api.ClientConnection;
import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.Player;
import io.cubyz.world.Chunk;

/**
 * A collection of mostly functions that are only available in the client context.
 */

public class ClientOnly {

	public static Consumer<Block[]> generateTextureAtlas;
	public static Consumer<Block> createBlockMesh;
	public static Consumer<EntityType> createEntityMesh;
	public static Consumer<Player> onBorderCrossing;
	public static Consumer<Chunk> deleteChunkMesh;
	
	// I didn't know where else to put it.
	public static ClientConnection client;
	
	static {
		createBlockMesh = (b) -> {
			throw new UnsupportedOperationException("createBlockMesh");
		};
		onBorderCrossing = (p) -> {
			return; // This lambda is used for updating the Spatial position to be in correct relation to the player.
		};
	}
	
}
