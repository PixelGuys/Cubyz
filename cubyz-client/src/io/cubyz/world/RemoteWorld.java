package io.cubyz.world;

import java.util.ArrayList;
import java.util.Map;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
import io.cubyz.entity.Entity;
import io.cubyz.entity.Player;

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
	public int getWidth() {
		return 0; //NOTE: Normal > 0
	}

	@Override
	public int getDepth() {
		return 0; //NOTE: Normal > 0
	}

	@Override
	public ArrayList<BlockInstance> blocks() {
		return null;
	}

	@Override
	public Map<Block, ArrayList<BlockInstance>> visibleBlocks() {
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
		// TODO Auto-generated method stub
		
	}

	@Override
	public void seek(int x, int z) {
		// TODO Auto-generated method stub
		
	}

	@Override
	public void synchronousSeek(int x, int z) {
		// TODO Auto-generated method stub
		
	}

}
