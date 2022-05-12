package cubyz.world;

import cubyz.api.CurrentWorldRegistries;
import cubyz.client.Cubyz;
import cubyz.client.entity.ClientPlayer;
import cubyz.clientSide.ServerConnection;
import cubyz.modding.ModLoader;
import cubyz.multiplayer.Protocols;
import cubyz.server.Server;
import cubyz.utils.Logger;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.Entity;
import cubyz.world.items.ItemStack;
import cubyz.world.terrain.biomes.Biome;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector4f;

//TODO:
public class ClientWorld extends World {
	private ServerConnection serverConnection;
	private ClientPlayer player;
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);

	public ClientWorld(String ip, String playerName, Class<?> chunkProvider) {
		super("server", chunkProvider);

		//wio = new WorldIO(this, new File("saves/" + name));
		serverConnection = new ServerConnection(ip, 5679, 5678, playerName);

		player = new ClientPlayer(0);
		player.loadFrom(serverConnection.doHandShake(playerName).getObjectOrNew("player"), this);

		registries = new CurrentWorldRegistries(this, "serverAssets");

		// Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
		ModLoader.postWorldGen(registries);


	}

	public ClientPlayer getLocalPlayer() {
		return player;
	}

	public Vector4f getClearColor() {
		return clearColor;
	}

	public float getGlobalLighting() {
		return ambientLight;
	}

	public void update() {
		int dayCycle = World.DAY_CYCLE;
		// Ambient light
		{
			int dayTime = Math.abs((int)(gameTime % dayCycle) - (dayCycle >> 1));
			if (dayTime < (dayCycle >> 2)-(dayCycle >> 4)) {
				ambientLight = 0.1f;
				clearColor.x = clearColor.y = clearColor.z = 0;
			} else if (dayTime > (dayCycle >> 2)+(dayCycle >> 4)) {
				ambientLight = 1.0f;
				clearColor.x = clearColor.y = 0.8f;
				clearColor.z = 1.0f;
			} else {
				//b:
				if (dayTime > (dayCycle >> 2)) {
					clearColor.z = 1.0f*(dayTime-(dayCycle >> 2))/(dayCycle >> 4);
				} else {
					clearColor.z = 0.0f;
				}
				//g:
				if (dayTime > (dayCycle >> 2)+(dayCycle >> 5)) {
					clearColor.y = 0.8f;
				} else if (dayTime > (dayCycle >> 2)-(dayCycle >> 5)) {
					clearColor.y = 0.8f+0.8f*(dayTime-(dayCycle >> 2)-(dayCycle >> 5))/(dayCycle >> 4);
				} else {
					clearColor.y = 0.0f;
				}
				//r:
				if (dayTime > (dayCycle >> 2)) {
					clearColor.x = 0.8f;
				} else {
					clearColor.x = 0.8f+0.8f*(dayTime-(dayCycle >> 2))/(dayCycle >> 4);
				}
				dayTime -= dayCycle >> 2;
				dayTime <<= 3;
				ambientLight = 0.55f + 0.45f*dayTime/(dayCycle >> 1);
			}
		}
	}

	@Override
	public void generate() {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void forceSave() {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void addEntity(Entity ent) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void removeEntity(Entity ent) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void setEntities(Entity[] arr) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public boolean isValidSpawnLocation(int x, int z) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void removeBlock(int x, int y, int z) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void placeBlock(int x, int y, int z, int b) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity, int pickupCooldown) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void updateBlock(int x, int y, int z, int block) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void queueChunk(ChunkData ch) {
		Protocols.CHUNK_REQUEST.sendRequest(serverConnection, ch);
	}

	@Override
	@Deprecated
	public void unQueueChunk(ChunkData ch) {
		// TODO!
		Logger.error("Use of unimplemented function ClientWorld.unQueueChunk()");
	}

	@Override
	public int getChunkQueueSize() {
		// TODO!
		Logger.error("Use of unimplemented function ClientWorld.getChunkQueueSize()");
		return 0;
	}

	@Override
	public void seek(int x, int y, int z, int renderDistance) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public MetaChunk getMetaChunk(int wx, int wy, int wz) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public NormalChunk getChunk(int wx, int wy, int wz) {
		Logger.error("Use of unimplemented function ClientWorld.getChunk()");
		return Server.world.getChunk(wx, wy, wz);
	}

	@Override
	public ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public int getBlock(int x, int y, int z) {
		// TODO!
		Logger.error("Use of unimplemented function ClientWorld.getBlock()");
		return 0;
	}

	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void cleanup() {
		throw new IllegalArgumentException("a");
	}

	@Override
	public int getHeight(int wx, int wz) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public CurrentWorldRegistries getCurrentRegistries() {
		return registries;
	}

	@Override
	public Biome getBiome(int wx, int wy, int wz) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void getLight(NormalChunk ch, int x, int y, int z, int[] array) {
		throw new IllegalArgumentException("a");
	}

	@Override
	protected int getLight(NormalChunk ch, int x, int y, int z, int minLight) {
		throw new IllegalArgumentException("a");
	}
}
