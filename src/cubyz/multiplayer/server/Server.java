package cubyz.multiplayer.server;

import cubyz.Constants;
import cubyz.api.Side;
import cubyz.client.GameLauncher;
import cubyz.modding.ModLoader;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.utils.Logger;
import cubyz.utils.Pacer;
import cubyz.utils.datastructures.SimpleList;
import cubyz.world.ServerWorld;
import cubyz.world.entity.Entity;

public final class Server extends Pacer {
	public static final int UPDATES_PER_SEC = 20;
	public static final int UPDATES_TIME_NS = 1_000_000_000 / UPDATES_PER_SEC;
	public static final float UPDATES_TIME_S = UPDATES_TIME_NS / 10e9f;

	private	static final Server server = new Server();

	public static ServerWorld world = null;
	public static User[] users = new User[0];
	private static final SimpleList<User> usersList = new SimpleList<>(new User[16]);
	public static UDPConnectionManager connectionManager = null;

	public static void main(String[] args) {
		try {
			if(ModLoader.mods.isEmpty()) {
				ModLoader.load(Side.SERVER);
			}
			if (world != null) {
				stop();
				world.cleanup();
			}

			Server.world = new ServerWorld(args[0], null);

			if(GameLauncher.renderer == null) { // headless server
				connectionManager = new UDPConnectionManager(Constants.DEFAULT_PORT, true);
			} else { // Singleplayer
				connectionManager = new UDPConnectionManager(Constants.DEFAULT_PORT, false);
				User user = new User(connectionManager, "localhost:5679");
				connect(user);
			}

			server.setFrequency(UPDATES_PER_SEC);
			server.start();
		} catch (Throwable e) {
			Logger.crash(e);
			if(world != null)
				world.cleanup();
			System.exit(1);
		}
		connectionManager.cleanup();
		connectionManager = null;
		usersList.clear();
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

	public static void disconnect(User user) {
		world.forceSave();
		synchronized(usersList) {
			if(user.name != null) {
				Protocols.CHAT.sendToClients(user.name + " #ffff00left");
			}
			usersList.remove(user);
			world.removeEntity(user.player);
			users = usersList.toArray();
		}
	}

	public static void connect(User user) {
		synchronized(usersList) {
			Protocols.CHAT.sendToClients(user.name+" #ffff00joined");
			usersList.add(user);
			users = usersList.toArray();
		}
	}

	@Override
	public void start() throws InterruptedException {
		running = true;
		super.start();
	}

	private Entity[] lastSentEntities = new Entity[0];

	@Override
	public void update() {
		world.update();

		for(User user : users) {
			user.update();
		}
		Entity[] entities = world.getEntities();
		Protocols.ENTITY.sendToClients(entities, lastSentEntities, world.itemEntityManager);
		lastSentEntities = entities;
	}
}
