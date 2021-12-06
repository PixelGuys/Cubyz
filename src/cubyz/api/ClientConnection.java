package cubyz.api;

import cubyz.world.NormalChunk;
import cubyz.world.ReducedChunkVisibilityData;
import cubyz.world.items.Inventory;

/**
 * Used to send events like block placing or GUI opening to the client or processes them if already on the client.
 */

public interface ClientConnection {
	public void openGUI(String name, Inventory inv);
	
	/**
	 * Sends a regurlar signal after each update.
	 * Used to send some basic data.
	 * @param gameTime
	 * @param biome
	 */
	public void serverPing(long gameTime, String biome);

	public void updateChunkMesh(NormalChunk mesh);

	public void updateChunkMesh(ReducedChunkVisibilityData mesh);
}
