package io.spacycubyd.world;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.joml.Vector3i;

import io.spacycubyd.blocks.Block;
import io.spacycubyd.blocks.BlockInstance;
import io.spacycubyd.entity.Entity;
import io.spacycubyd.entity.Player;

public abstract class World {

	public static final int WORLD_HEIGHT = 255;
	
	public abstract boolean isEdited();
	public abstract void receivedEdited();
	public abstract void markEdited();
	
	public abstract Player getLocalPlayer();
	public abstract int getWidth();
	public abstract int getDepth();
	
	public int getHeight() {
		return WORLD_HEIGHT;
	}
	
	public abstract ArrayList<BlockInstance> blocks();
	public abstract Map<Block, ArrayList<BlockInstance>> visibleBlocks();
	public abstract Entity[] getEntities();
	
	public abstract void entityGenerate(int x, int z);
	public abstract Chunk getChunk(int x, int z);
	public abstract BlockInstance getBlock(int x, int y, int z);
	public BlockInstance getBlock(Vector3i vec) {
		return getBlock(vec.x, vec.y, vec.z);
	}
	public abstract void removeBlock(int x, int y, int z);
	
	public int getHighestY(int x, int z) {
		for (int y = 255; y > 0; y--) {
			if (getBlock(x, y, z) != null) {
				return y;
			}
		}
		return -1; // not generated
	}
	
	public abstract boolean isRemote();
	
}
