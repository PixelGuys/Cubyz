package cubyz.server;

import cubyz.Constants;
import cubyz.api.CubyzRegistries;
import cubyz.api.Side;
import cubyz.client.entity.ClientEntity;
import cubyz.modding.ModLoader;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.utils.Logger;
import cubyz.client.ClientSettings;
import cubyz.client.entity.ClientEntityManager;
import cubyz.utils.Pacer;
import cubyz.utils.ThreadPool;
import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;
import cubyz.world.entity.Entity;
import org.joml.Vector3d;
import org.joml.Vector3f;
import pixelguys.json.JsonArray;
import pixelguys.json.JsonElement;
import pixelguys.json.JsonObject;

import java.util.ArrayList;

public final class Server extends Pacer{
	public static final int UPDATES_PER_SEC = 20;
	public static final int UPDATES_TIME_NS = 1_000_000_000 / UPDATES_PER_SEC;
	public static final float UPDATES_TIME_S = UPDATES_TIME_NS / 10e9f;

	private	static final Server server = new Server();

	public static ServerWorld world = null;
	public final static ArrayList<User> users = new ArrayList<>();
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
		users.add(new User(connectionManager, "localhost", 5679));

		try {
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
		connectionManager.cleanup();
		connectionManager = null;
		users.clear();
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
		users.remove(user);
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

		// TODO: world.clientConnection.serverPing(world.getGameTime(), world.getBiome((int)Cubyz.player.getPosition().x, (int)Cubyz.player.getPosition().y, (int)Cubyz.player.getPosition().z).getRegistryID().toString());

		// TODO: Send this through the proper interface and to every player:
		JsonArray entityData = new JsonArray();
		for(Entity ent : world.getEntities()) {
			JsonObject data = new JsonObject();
			data.put("id", ent.id);
			data.put("x", ent.getPosition().x);
			data.put("y", ent.getPosition().y);
			data.put("z", ent.getPosition().z);
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
