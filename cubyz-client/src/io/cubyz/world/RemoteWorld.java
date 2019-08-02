package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.joml.Vector4f;

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
		return null;
	}

	public Block[] getBlocks() {
		return null;
	}

	public Map<Block, ArrayList<BlockInstance>> visibleBlocks() {
		return null;
	}

	@Override
	public void placeBlock(int x, int y, int z, Block b) {
		
	}

	@Override
	public Chunk[] getVisibleChunks() {
		return null;
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
		return 0;
	}

	@Override
	public void setRenderDistance(int arg0) {
	}

	@Override
	public Vector4f getClearColor() {
		// TODO Auto-generated method stub
		return null;
	}

}
