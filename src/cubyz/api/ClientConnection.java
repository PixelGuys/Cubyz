package cubyz.api;

import cubyz.world.NormalChunk;
import cubyz.world.ReducedChunkVisibilityData;
import cubyz.world.items.Inventory;

/**
 * Used to send events like block placing or GUI opening to the client or processes them if already on the client.
 */

public interface ClientConnection {
	void openGUI(String name, Inventory inv);

	/**
	 * Sends a regurlar signal after each update.
	 * Used to send some basic data.
	 * @param gameTime
	 * @param biome
	 */
	void serverPing(long gameTime, String biome);

	void updateChunkMesh(NormalChunk mesh);

	void updateChunkMesh(ReducedChunkVisibilityData mesh);
}
