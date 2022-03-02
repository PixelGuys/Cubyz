package cubyz.world.entity;

import cubyz.world.NormalChunk;
import cubyz.world.SavableChunk;
import cubyz.world.World;
import cubyz.world.save.ChunkIO;

/**
 * TODO: Will store a reference to each entity of a chunk.
 */

public class ChunkEntityManager extends SavableChunk {
	public final NormalChunk chunk;
	public final ItemEntityManager itemEntityManager;
	public ChunkEntityManager(World world, NormalChunk chunk) {
		super(chunk.wx, chunk.wy, chunk.wz, 1);
		this.chunk = chunk;
		itemEntityManager = new ItemEntityManager(chunk.world, chunk, 1);
		ChunkIO.loadChunkFromFile(chunk.world, this);
	}

	public void update(float deltaTime) {
		itemEntityManager.update(deltaTime);
	}

	public void save() {
		ChunkIO.storeChunkToFile(chunk.world, this);
	}

	@Override
	public byte[] saveToByteArray() {
		return itemEntityManager.store(chunk.world.wio.itemPalette);
	}

	@Override
	public void loadFromByteArray(byte[] array, int len) {
		itemEntityManager.loadFromByteArray(array, len, chunk.world.wio.itemPalette);
	}

	@Override
	public int getWidth() {
		return chunk.getWidth();
	}

	@Override
	public String fileEnding() {
		return "entity";
	}
}
