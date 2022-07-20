package cubyz.world;

import cubyz.api.CurrentWorldRegistries;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.entity.ClientPlayer;
import cubyz.client.entity.InterpolatedItemEntityManager;
import cubyz.multiplayer.client.ServerConnection;
import cubyz.modding.ModLoader;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.rendering.RenderOctTree;
import cubyz.rendering.VisibleChunk;
import cubyz.multiplayer.server.Server;
import cubyz.utils.ThreadPool;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.BlockInstance;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.Entity;
import cubyz.world.items.ItemStack;
import cubyz.world.save.BlockPalette;
import cubyz.world.terrain.biomes.Biome;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector4f;
import pixelguys.json.JsonObject;

import java.util.ArrayList;

//TODO:
public class ClientWorld extends World {
	public final ServerConnection serverConnection;
	public final UDPConnectionManager connectionManager;
	private final ClientPlayer player;
	float ambientLight = 0f;
	Vector4f clearColor = new Vector4f(0, 0, 0, 1.0f);

	public final Class<?> chunkProvider;

	public Biome playerBiome;
	public final ArrayList<String> chatHistory = new ArrayList<>();

	public ClientWorld(String ip, UDPConnectionManager connectionManager, Class<?> chunkProvider) throws InterruptedException {
		super("server");
		super.itemEntityManager = new InterpolatedItemEntityManager(this);
		this.chunkProvider = chunkProvider;
		// Check if the chunkProvider is valid:
		if (!NormalChunk.class.isAssignableFrom(chunkProvider) ||
				chunkProvider.getConstructors().length != 1 ||
				chunkProvider.getConstructors()[0].getParameterTypes().length != 4 ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[0].equals(World.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[1].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[2].equals(Integer.class) ||
				!chunkProvider.getConstructors()[0].getParameterTypes()[3].equals(Integer.class))
			throw new IllegalArgumentException("Chunk provider "+chunkProvider+" is invalid! It needs to be a subclass of NormalChunk and MUST contain a single constructor with parameters (ServerWorld, Integer, Integer, Integer)");

		this.connectionManager = connectionManager;
		serverConnection = new ServerConnection(connectionManager, this, ip);

		player = new ClientPlayer(this, 0);
		serverConnection.doHandShake(ClientSettings.playerName);
	}

	public void finishHandshake(JsonObject json) {
		blockPalette = new BlockPalette(json.getObjectOrNew("blockPalette"));
		spawn.x = json.getObjectOrNew("spawn").getInt("x", 0);
		spawn.y = json.getObjectOrNew("spawn").getInt("y", 0);
		spawn.z = json.getObjectOrNew("spawn").getInt("z", 0);

		if(Server.world != null) {
			// Share the registries of the local server:
			registries = Server.world.getCurrentRegistries();
		} else {
			registries = new CurrentWorldRegistries(this, "serverAssets/", blockPalette);
		}

		player.loadFrom(json.getObjectOrNew("player"), this);
		player.id = json.getInt("player_id", -1);

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
		long newTime = System.currentTimeMillis();
		while(milliTime + 100 < newTime) {
			milliTime += 100;
			if (doGameTimeCycle) gameTime++; // gameTime is measured in 100ms.
		}
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
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity) {
		Protocols.GENERIC_UPDATE.itemStackDrop(serverConnection, stack, pos, dir, velocity);
	}

	@Override
	public void updateBlock(int x, int y, int z, int newBlock) {
		NormalChunk ch = getChunk(x, y, z);
		if (ch != null) {
			int old = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
			if(old != newBlock) {
				ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, newBlock);
				Protocols.BLOCK_UPDATE.send(serverConnection, x, y, z, newBlock);
			}
		}
	}

	/**
	 * Block update that came from the server. In this case there needs to be no update sent to the server.
	 * @param x
	 * @param y
	 * @param z
	 * @param newBlock
	 */
	public void remoteUpdateBlock(int x, int y, int z, int newBlock) {
		NormalChunk ch = getChunk(x, y, z);
		if (ch != null) {
			int old = ch.getBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
			if(old != newBlock) {
				ch.updateBlock(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask, newBlock);
			}
		}
	}

	@Override
	public void queueChunks(ChunkData[] chunks) {
		Protocols.CHUNK_REQUEST.sendRequest(serverConnection, chunks);
	}

	@Override
	public MetaChunk getMetaChunk(int wx, int wy, int wz) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public NormalChunk getChunk(int wx, int wy, int wz) {
		RenderOctTree.OctTreeNode node = Cubyz.chunkTree.findNode(new ChunkData(wx, wy, wz, 1));
		if(node == null)
			return null;
		ChunkData chunk = node.mesh.getChunk();
		if(chunk instanceof NormalChunk)
			return (NormalChunk)chunk;
		return null;
	}

	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		throw new IllegalArgumentException("a");
	}

	@Override
	public void cleanup() {
		connectionManager.cleanup();
		ThreadPool.clear();
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

	public final BlockInstance getBlockInstance(int x, int y, int z) {
		VisibleChunk ch = (VisibleChunk)getChunk(x, y, z);
		if (ch != null && ch.isLoaded()) {
			return ch.getBlockInstanceAt(Chunk.getIndex(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask));
		} else {
			return null;
		}
	}

	@Override
	public int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		NormalChunk ch = getChunk(x, y, z);
		if (ch == null || !ch.isLoaded() || !easyLighting)
			return 0xffffffff;
		return ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
	}
	@Override
	public void getLight(NormalChunk ch, int x, int y, int z, int[] array) {
		int block = getBlock(x, y, z);
		if (block == 0) return;
		int selfLight = Blocks.light(block);
		x--;
		y--;
		z--;
		for(int ix = 0; ix < 3; ix++) {
			for(int iy = 0; iy < 3; iy++) {
				for(int iz = 0; iz < 3; iz++) {
					array[ix + iy*3 + iz*9] = getLight(ch, x+ix, y+iy, z+iz, selfLight);
				}
			}
		}
	}
	@Override
	protected int getLight(NormalChunk ch, int x, int y, int z, int minLight) {
		if (x - ch.wx != (x & Chunk.chunkMask) || y - ch.wy != (y & Chunk.chunkMask) || z - ch.wz != (z & Chunk.chunkMask))
			ch = getChunk(x, y, z);
		if (ch == null || !ch.isLoaded())
			return 0xff000000;
		int light = ch.getLight(x & Chunk.chunkMask, y & Chunk.chunkMask, z & Chunk.chunkMask);
		// Make sure all light channels are at least as big as the minimum:
		if ((light & 0xff000000) >>> 24 < (minLight & 0xff000000) >>> 24) light = (light & 0x00ffffff) | (minLight & 0xff000000);
		if ((light & 0x00ff0000) < (minLight & 0x00ff0000)) light = (light & 0xff00ffff) | (minLight & 0x00ff0000);
		if ((light & 0x0000ff00) < (minLight & 0x0000ff00)) light = (light & 0xffff00ff) | (minLight & 0x0000ff00);
		if ((light & 0x000000ff) < (minLight & 0x000000ff)) light = (light & 0xffffff00) | (minLight & 0x000000ff);
		return light;
	}
}
