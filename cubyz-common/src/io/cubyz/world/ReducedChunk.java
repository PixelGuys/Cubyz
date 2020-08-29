package io.cubyz.world;

import java.util.ArrayList;

import io.cubyz.save.BlockChange;

/**
 * A chunk with smaller resolution(2 blocks, 4 blocks, 8 blocks or 16 blocks). Used to work out the far-distance map of cubyz terrain.
 * It is trimmed for low memory-usage and high-performance, because many of those are be needed.
 * Instead of storing blocks it only stores 16 bit color values.
 */
public class ReducedChunk {
	public static Surface surface; // The current surface the player is on.
	public ArrayList<BlockChange> changes;
	public final int resolution; // 0 - 1; 1 - 2; 2 - 4; 3 - 8; 4 - 16
	public final int size;
	public final int cx, cz;
	public final short[] blocks;
	public boolean generated = false;
	public ReducedChunk(int cx, int cz, int resolution, ArrayList<BlockChange> changes) {
		this.cx = cx;
		this.cz = cz;
		this.resolution = resolution;
		System.out.println(resolution);
		size = (World.WORLD_HEIGHT >>> resolution)*(16 >> resolution)*(16 >> resolution);
		blocks = new short[size];
		this.changes = changes;
	}
	
	public void applyBlockChanges() {
		/*for(BlockChange bc : changes) {
			
			int index = ((bc.x >>> resolution) << (4 - resolution)) | ((bc.y >>> resolution) << (8 - 2*resolution)) | (bc.z >>> resolution);
			Block b = bc.newType == -1 ? null : surface.getPlanetBlocks()[bc.newType];
			if (b != null && b.hasBlockEntity()) {
				Vector3i pos = new Vector3i(wx+bc.x, bc.y, wz+bc.z);
				blockEntities.add(b.createBlockEntity(surface, pos));
			}
			blocks[index] = b;
			blockData[index] = bc.newData;
		}*/ // TODO
	}
}
