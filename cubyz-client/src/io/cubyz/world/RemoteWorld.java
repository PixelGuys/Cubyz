package io.cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.joml.Vector4f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;
import io.cubyz.multiplayer.GameProfile;

// TODO
public class RemoteWorld extends World {
	
	private Player localPlayer;
	private GameProfile localGameProfile;
	private Entity[] loadedEntities;
	
	private ArrayList<Chunk> chunks;
	private HashMap<Block, ArrayList<BlockInstance>> visibleBlocks;
	
	public RemoteWorld() {
		localPlayer = (Player) CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:player").newEntity();
		loadedEntities = new Entity[0];
		chunks = new ArrayList<>();
		visibleBlocks = new HashMap<>();
		
		
	}
	
	@Override
	public Player getLocalPlayer() {
		return localPlayer;
	}

	@Override
	public Entity[] getEntities() {
		return loadedEntities;
	}

	@Override
	public Chunk getChunk(int x, int z) {
		return null;
	}

	@Override
	public Chunk _getChunk(int x, int z) {
		return null;
	}

	@Override
	public BlockInstance getBlock(int x, int y, int z) {
		return null;
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
		
	}

	@Override
	public List<Chunk> getChunks() {
		return new ArrayList<Chunk>();
	}

	public Block[] getBlocks() {
		return new Block[0];
	}

	public Map<Block, ArrayList<BlockInstance>> visibleBlocks() {
		return visibleBlocks;
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
		return 0;
	}

	@Override
	public void setGameTime(long time) {
		throw new UnsupportedOperationException("Cannot change remote game time");
	}

	@Override
	public int getRenderDistance() {
		return 4;
	}

	@Override
	public void setRenderDistance(int arg0) {
	}

	@Override
	public Vector4f getClearColor() {
		return new Vector4f(0.5f, 0.5f, 1f, 1f);
	}

	@Override
	public void cleanup() {
		// TODO Auto-generated method stub
		
	}

}
