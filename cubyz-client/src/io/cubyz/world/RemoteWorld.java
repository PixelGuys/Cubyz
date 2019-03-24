package io.cubyz.world;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;

// TODO
public class RemoteWorld extends World {

	@Override
	public boolean isEdited() {
		return false;
	}

	@Override
	public void unmarkEdit() {
		
	}

	@Override
	public void markEdit() {
		
	}
	
	@Override
	public Player getLocalPlayer() {
		return null;
	}

	@Override
	public Entity[] getEntities() {
		return null;
	}

	@Override
	public Chunk getChunk(int x, int z) {
		return null;
	}

	@Override
	public BlockInstance getBlock(int x, int y, int z) {
		return null;
	}

	@Override
	public void removeBlock(int x, int y, int z) {}

	@Override
	public void queueChunk(ChunkAction action) {
		// LOAD would be loading from server, UNLOAD would be unloading from client, and GENERATE would do nothing
	}

	@Override
	public void seek(int x, int z) {
		
	}

	@Override
	public void synchronousSeek(int x, int z) {
		
	}

	@Override
	public List<Chunk> getChunks() {
		// TODO Auto-generated method stub
		return null;
	}

	public Block[] getBlocks() {
		// TODO Auto-generated method stub
		return null;
	}

	public Map<Block, ArrayList<BlockInstance>> visibleBlocks() {
		// TODO Auto-generated method stub
		return null;
	}

}
