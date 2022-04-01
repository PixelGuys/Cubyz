package cubyz.server;

import cubyz.client.ItemTextures;
import cubyz.gui.MenuGUI;
import cubyz.gui.audio.MusicManager;
import cubyz.gui.game.GameOverlay;
import cubyz.rendering.VisibleChunk;
import cubyz.utils.Logger;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.entity.ClientEntityManager;
import cubyz.utils.Pacer;
import cubyz.world.ServerWorld;

public final class Server extends Pacer{
	public static final int UPDATES_PER_SEC = 20;
	public static final int UPDATES_TIME_NS = 1_000_000_000 / UPDATES_PER_SEC;
	public static final float UPDATES_TIME_S = UPDATES_TIME_NS / 10e9f;

	private	static final Server server = new Server();

	public static ServerWorld world = null;

	public static void main(String[] args) {
		if (world != null) {
			stop();
			world.cleanup();
		}

		UserManager userManager = new UserManager();
		userManager.start();

		Server.world = new ServerWorld(args[0], null, VisibleChunk.class);

		try {
			while (Cubyz.world == null) {
				// TODO: Remove this when Server and Client are sufficiently untangled.
				Thread.sleep(10);
			}
			server.setFrequency(UPDATES_PER_SEC);
			server.start();
		} catch (Throwable e) {
			Logger.crash(e);
			if(world != null)
				world.cleanup();
			System.exit(1);
		}
		if(world != null)
			world.cleanup();
		world = null;
	}
	public static void stop(){
		if (server != null)
			server.running = false;
	}

	private Server(){
		super("Server");
	}

	@Override
	public void start() throws InterruptedException {
		running = true;
		super.start();
	}

	@Override
	public void update() {
		world.update();
		// TODO: Adjust for multiple players:

		world.clientConnection.serverPing(world.getGameTime(), world.getBiome((int) Cubyz.player.getPosition().x, (int) Cubyz.player.getPosition().z).getRegistryID().toString());
		// TODO: Move this to the client, or generalize this for multiplayer.

		world.seek((int) Cubyz.player.getPosition().x, (int) Cubyz.player.getPosition().y, (int) Cubyz.player.getPosition().z, ClientSettings.RENDER_DISTANCE);
		// TODO: Send this through the proper interface and to every player:
		ClientEntityManager.serverUpdate(world.getEntities());
	}
}
