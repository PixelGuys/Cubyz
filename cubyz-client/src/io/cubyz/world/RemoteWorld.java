package io.cubyz.world;

import java.util.ArrayList;
import java.util.Map;

import io.spacycubyd.blocks.Block;
import io.spacycubyd.blocks.BlockInstance;
import io.spacycubyd.entity.Entity;
import io.spacycubyd.entity.Player;
import io.spacycubyd.world.Chunk;
import io.spacycubyd.world.World;

public class RemoteWorld extends World {

	@Override
	public boolean isEdited() {
		return false;
	}

	@Override
	public void receivedEdited() {
		
	}

	@Override
	public void markEdited() {
		
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
	public void entityGenerate(int x, int z) {}

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
	public boolean isRemote() {
		return true;
	}

}
