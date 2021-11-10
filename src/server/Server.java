package server;

import cubyz.Logger;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.entity.ClientEntityManager;
import cubyz.world.NormalChunk;

public class Server {
	public static final int UPDATES_PER_SEC = 10;
	public static final int UPDATES_TIME_NS = 1_000_000_000 / UPDATES_PER_SEC;
	public static final float UPDATES_TIME_S = UPDATES_TIME_NS / 10e9f;
	public static boolean running;
	public static void main(String[] args) {
		try {
			running = true;
			while(Cubyz.world == null) {
				// TODO: Init world here.
				Thread.sleep(10);
			}
			long previousTime = System.nanoTime();
			while (running) {
				update();
				// Sync:
				if(System.nanoTime() - previousTime < UPDATES_TIME_NS) {
					Thread.sleep((UPDATES_TIME_NS - (System.nanoTime() - previousTime))/1000000);
					previousTime += UPDATES_TIME_NS;
				} else {
					Logger.warning("Server Thread is lagging behind.");
					previousTime = System.nanoTime();
				}
			}
		} catch (Exception e) {
			Logger.crash(e);
		}
	}

	public static void update() {
		Cubyz.world.update();
		// TODO: Adjust for multiple players:
		Cubyz.world.clientConnection.serverPing(Cubyz.world.getGameTime(), Cubyz.world.getBiome((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().z).getRegistryID().toString());
		// TODO: Move this to the client, or generalize this for multiplayer.
		Cubyz.world.seek((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().y, (int)Cubyz.player.getPosition().z, ClientSettings.RENDER_DISTANCE, ClientSettings.EFFECTIVE_RENDER_DISTANCE*NormalChunk.chunkSize*2);

		// TODO: Send this through the proper interface and to every player:
		ClientEntityManager.serverUpdate(Cubyz.world.getEntities());
	}
}
