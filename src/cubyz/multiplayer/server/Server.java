package cubyz.multiplayer.server;

import cubyz.Constants;
import cubyz.api.Side;
import cubyz.modding.ModLoader;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.utils.Logger;
import cubyz.utils.Pacer;
import cubyz.utils.datastructures.SimpleList;
import cubyz.world.ServerWorld;
import cubyz.world.entity.Entity;
import pixelguys.json.JsonArray;
import pixelguys.json.JsonObject;

public final class Server extends Pacer{
	public static final int UPDATES_PER_SEC = 20;
	public static final int UPDATES_TIME_NS = 1_000_000_000 / UPDATES_PER_SEC;
	public static final float UPDATES_TIME_S = UPDATES_TIME_NS / 10e9f;

	private	static final Server server = new Server();

	public static ServerWorld world = null;
	public static User[] users = new User[0];
	private static final SimpleList<User> usersList = new SimpleList<>(new User[16]);
	public static UDPConnectionManager connectionManager = null;

	public static void main(String[] args) {
		if(ModLoader.mods.isEmpty()) {
			ModLoader.load(Side.SERVER);
		}
		if (world != null) {
			stop();
			world.cleanup();
		}

		Server.world = new ServerWorld(args[0], null);

		connectionManager = new UDPConnectionManager(Constants.DEFAULT_PORT);
		User user = new User(connectionManager, "localhost", 5679);
		connect(user);

		try {
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
			usersList.remove(user);
			users = usersList.toArray();
		}
	}

	public static void connect(User user) {
		synchronized(usersList) {
			usersList.add(user);
			users = usersList.toArray();
		}
	}

	@Override
	public void start() throws InterruptedException {
		running = true;
		super.start();
	}

	@Override
	public void update() {
		world.update();

		for(User user : users) {
			user.update();
		}
		JsonArray entityData = new JsonArray();
		for(Entity ent : world.getEntities()) {
			JsonObject data = new JsonObject();
			data.put("id", ent.id);
			data.put("x", ent.getPosition().x);
			data.put("y", ent.getPosition().y);
			data.put("z", ent.getPosition().z);
			data.put("vx", ent.vx);
			data.put("vy", ent.vy);
			data.put("vz", ent.vz);
			data.put("rot_x", ent.getRotation().x);
			data.put("rot_y", ent.getRotation().y);
			data.put("rot_z", ent.getRotation().z);
			data.put("type", ent.getType().getRegistryID().toString());
			data.put("height", ent.height);
			if(!ent.name.isEmpty()) {
				data.put("name", ent.name);
			}
			entityData.add(data);
		}
		for(User user : users) {
			Protocols.ENTITY.send(user, entityData);
		}
	}
}
