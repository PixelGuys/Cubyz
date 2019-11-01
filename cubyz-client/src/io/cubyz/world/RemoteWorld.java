package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;

import org.joml.Vector4f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.IRegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.math.Bits;
import io.cubyz.multiplayer.GameProfile;
import io.cubyz.save.BlockChange;
import io.cubyz.world.generator.LifelandGenerator;

// TODO
@SuppressWarnings("unused")
public class RemoteWorld extends World {
	
	private Player localPlayer;
	private GameProfile localGameProfile;
	private ArrayList<Entity> entities;
	
	private ArrayList<Chunk> chunks;
	private Block[] blocks;
	
	private LifelandGenerator gen = new LifelandGenerator();
	private long gameTime;
	
	public RemoteWorld() {
		localPlayer = (Player) CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity();
		localPlayer.setWorld(this);
		localPlayer.getPosition().add(10, 200, 10);
		entities = new ArrayList<Entity>();
		entities.add(localPlayer);
		chunks = new ArrayList<>();
		
		blocks = new Block[CubyzRegistries.BLOCK_REGISTRY.registered().length];
		for (IRegistryElement ire : CubyzRegistries.BLOCK_REGISTRY.registered()) {
			Block b = (Block) ire;
			blocks[b.ID] = b;
		}
	}
	
	public ArrayList<BlockChange> transformData(byte[] data) {
		int size = Bits.getInt(data, 8);
		ArrayList<BlockChange> list = new ArrayList<BlockChange>(size);
		for (int i = 0; i < size; i++) {
			list.add(new BlockChange(data, 12 + (i << 4)));
		}
		return list;
	}
	
	@Override
	public Player getLocalPlayer() {
		return localPlayer;
	}

	@Override
	public Entity[] getEntities() {
		return entities.toArray(new Entity[entities.size()]);
	}
	
	@Override
	public void update() {
		Entity[] ent = getEntities();
		for (Entity en : ent) {
			en.update();
		}
	}

	@Override
	public Chunk getChunk(int x, int z) {
		int cx = x;
		if(cx < 0)
			cx -= 15;
		cx = cx / 16;
		int cz = z;
		if(cz < 0)
			cz -= 15;
		cz = cz / 16;
		return _getChunk(cx, cz);
	}

	@Override
	public Chunk _getChunk(int x, int z) {
		for (int i = 0; i < chunks.size(); i++) {
			if (chunks.get(i).getX() == x && chunks.get(i).getZ() == z) {
				return chunks.get(i);
			}
		}
		Chunk ck = new Chunk(x, z, this, new ArrayList<BlockChange>());
		chunks.add(ck);
		return ck;
	}

	@Override
	public BlockInstance getBlock(int x, int y, int z) {
		Chunk ch = getChunk(x, z);
		if (y > World.WORLD_HEIGHT || y < 0)
			return null;
		if (ch != null && ch.isGenerated() && ch.isLoaded()) {
			int cx = x & 15;
			int cz = z & 15;
			BlockInstance bi = ch.getBlockInstanceAt(cx, y, cz);
			return bi;
		} else {
			return null;
		}
	}

	@Override
	public void removeBlock(int x, int y, int z) {
		
	}

	@Override
	public void queueChunk(Chunk ch) {
		// Only LOAD from server. It cannot GENERATE a remote chunk.
	}

	@Override
	public void seek(int x, int z) {
		
	}

	@Override
	public void synchronousSeek(int x, int z) {
		while (getChunk(x/16, z/16) == null) {
			try {
				Thread.sleep(10);
			} catch (InterruptedException e) {
				e.printStackTrace();
			}
		}
	}

	@Override
	public List<Chunk> getChunks() {
		return chunks;
	}

	public Block[] getBlocks() {
		return blocks;
	}

	@Override
	public void placeBlock(int x, int y, int z, Block b) {
		
	}

	@Override
	public Chunk[] getVisibleChunks() {
		return chunks.toArray(new Chunk[0]);
	}

	@Override
	public float getGlobalLighting() {
		return 0.7f;
	}

	@Override
	public long getGameTime() {
		return gameTime;
	}

	@Override
	public void setGameTime(long time) {
		this.gameTime = time;
	}

	@Override
	public int getRenderDistance() {
		return 4;
	}

	@Override
	public void setRenderDistance(int rd) {
	}

	@Override
	public Vector4f getClearColor() {
		return new Vector4f(0.5f, 0.5f, 1f, 1f);
	}

	@Override
	public void cleanup() {
		
	}
	
	public void worldData(int seed) {
		this.setSeed(seed);
	}
	
	public void submit(int x, int z, byte[] data) {
		Chunk ck = new Chunk(x, z, this, transformData(data));
		for (int i = 0; i < chunks.size(); i++) {
			if (chunks.get(i).getX() == x && chunks.get(i).getZ() == z) {
				chunks.remove(i);
			}
		}
		chunks.add(0, ck);
		ck.generateFrom(gen);
		ck.load();
		if (getHighestBlock(localPlayer.getPosition().x, localPlayer.getPosition().z) != -1)
			localPlayer.getPosition().y = getHighestBlock(localPlayer.getPosition().x, localPlayer.getPosition().z)+1;
		ck.applyBlockChanges();
	}

}
