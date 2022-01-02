package cubyz.world;

import cubyz.api.CurrentWorldRegistries;
import cubyz.clientSide.ServerConnection;
import cubyz.modding.ModLoader;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.entity.ChunkEntityManager;
import cubyz.world.entity.Entity;
import cubyz.world.items.ItemStack;
import cubyz.world.terrain.biomes.Biome;
import org.joml.Vector3d;
import org.joml.Vector3f;

//TODO:
public class ClientWorld extends World{
	private ServerConnection serverConnection;
	
	public ClientWorld(String ip, String playerName, Class<?> chunkProvider) {
		super("server", chunkProvider);

		//wio = new WorldIO(this, new File("saves/" + name));
		serverConnection = new ServerConnection(ip, playerName, getName());
		
		registries = new CurrentWorldRegistries(this, "serverAssets");

		// Call mods for this new world. Mods sometimes need to do extra stuff for the specific world.
		ModLoader.postWorldGen(registries);


	}

	@Override
	public void generate() {

	}

	@Override
	public void forceSave() {

	}

	@Override
	public void addEntity(Entity ent) {

	}

	@Override
	public void removeEntity(Entity ent) {

	}

	@Override
	public void setEntities(Entity[] arr) {

	}

	@Override
	public boolean isValidSpawnLocation(int x, int z) {
		return false;
	}

	@Override
	public void removeBlock(int x, int y, int z) {

	}

	@Override
	public void placeBlock(int x, int y, int z, int b) {

	}

	@Override
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity, int pickupCooldown) {

	}

	@Override
	public void drop(ItemStack stack, Vector3d pos, Vector3f dir, float velocity) {

	}

	@Override
	public void updateBlock(int x, int y, int z, int block) {

	}

	@Override
	public void update() {

	}

	@Override
	public void queueChunk(ChunkData ch) {

	}

	@Override
	public void unQueueChunk(ChunkData ch) {

	}

	@Override
	public int getChunkQueueSize() {
		return 0;
	}

	@Override
	public void seek(int x, int y, int z, int renderDistance, int regionRenderDistance) {

	}

	@Override
	public MetaChunk getMetaChunk(int wx, int wy, int wz) {
		return null;
	}

	@Override
	public NormalChunk getChunk(int wx, int wy, int wz) {
		return null;
	}

	@Override
	public ChunkEntityManager getEntityManagerAt(int wx, int wy, int wz) {
		return null;
	}

	@Override
	public int getBlock(int x, int y, int z) {
		return 0;
	}

	@Override
	public BlockEntity getBlockEntity(int x, int y, int z) {
		return null;
	}

	@Override
	public void cleanup() {

	}

	@Override
	public int getHeight(int wx, int wz) {
		return 0;
	}

	@Override
	public CurrentWorldRegistries getCurrentRegistries() {
		return null;
	}

	@Override
	public Biome getBiome(int wx, int wz) {
		return null;
	}

	@Override
	public int getLight(int x, int y, int z, Vector3f sunLight, boolean easyLighting) {
		return 0;
	}

	@Override
	public void getLight(NormalChunk ch, int x, int y, int z, int[] array) {

	}

	@Override
	protected int getLight(NormalChunk ch, int x, int y, int z, int minLight) {
		return 0;
	}
}
