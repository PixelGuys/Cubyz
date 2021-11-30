package cubyz.server;

import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.world.ChunkData;
import cubyz.world.items.ItemStack;

public interface ServerConnection {
	/**
	 * Tells the server to generate a specific chunk and send it over, calling data.meshListener when done.
	 * The server is free to not generate the mesh.
	 * @param data
	 */
	abstract void requestChunk(ChunkData data);
	/**
	 * Gets the server name. Is cached for a remote connection.
	 * @return name
	 */
	abstract String getName();

	/**
	 * Drops an item on the ground.
	 * @param stack
	 * @param pos
	 * @param dir
	 * @param velocity
	 */
	abstract void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity);
}
