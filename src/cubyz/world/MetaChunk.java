package cubyz.world;

import java.util.ArrayList;

import cubyz.utils.Logger;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.Updateable;
import cubyz.world.entity.ChunkEntityManager;

/**
 * A chunk of chunks.
 */

public class MetaChunk {
	public static final int metaChunkShift = 4;
	public static final int metaChunkShift2 = 2*metaChunkShift;
	public static final int metaChunkSize = 1 << metaChunkShift;
	public static final int worldShift = metaChunkShift + Chunk.chunkShift;
	public static final int worldMask = (1 << worldShift) - 1;
	public final int wx, wy, wz;
	public final NormalChunk[] chunks;
	public final ChunkEntityManager[] entityManagers;
	public final World world;
	public MetaChunk(int wx, int wy, int wz, World world) {
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		chunks = new NormalChunk[metaChunkSize*metaChunkSize*metaChunkSize];
		entityManagers = new ChunkEntityManager[metaChunkSize*metaChunkSize*metaChunkSize];
		this.world = world;
	}
	
	public void save() {
		for(NormalChunk chunk : chunks) {
			if (chunk != null)
				chunk.save();
		}
		for(ChunkEntityManager manager : entityManagers) {
			if (manager != null)
				manager.chunk.map.mapIO.saveItemEntities(manager.itemEntityManager);
		}
	}
	
	public void clean() {
		for(NormalChunk chunk : chunks) {
			if (chunk != null)
				chunk.clean();
		}
		for(ChunkEntityManager manager : entityManagers) {
			if (manager != null)
				manager.chunk.map.mapIO.saveItemEntities(manager.itemEntityManager);
		}
	}
	
	public void updateBlockEntities() {
		for (NormalChunk ch : chunks) {
			if (ch != null && ch.isLoaded() && ch.getBlockEntities().size() > 0) {
				BlockEntity[] blockEntities = ch.getBlockEntities().toArray(new BlockEntity[0]);
				for (BlockEntity be : blockEntities) {
					if (be == null) break; // end of array
					if (be instanceof Updateable) {
						Updateable tk = (Updateable) be;
						tk.update(false);
						if (tk.randomUpdates()) {
							// TODO: Random ticks.
							/*if (rnd.nextInt(5) < 1) { // 1/5 chance
								tk.update(true);
							}*/
						}
					}
				}
			}
		}
	}
	
	public void liquidUpdate() {
		for (NormalChunk ch : chunks) {
			if (ch == null) continue;
			int wx = ch.wx;
			int wy = ch.wy;
			int wz = ch.wz;
			if (ch.isLoaded() && ch.getLiquids().size() > 0) {
				Integer[] liquids = ch.getUpdatingLiquids().toArray(new Integer[0]);
				int size = ch.getUpdatingLiquids().size();
				ch.getUpdatingLiquids().clear();
				for (int j = 0; j < size; j++) {
					int block = ch.getBlockAtIndex(liquids[j]);
					int bx = liquids[j]/Chunk.getIndex(1, 0, 0) & Chunk.chunkMask;
					int by = liquids[j]/Chunk.getIndex(0, 1, 0) & Chunk.chunkMask;
					int bz = liquids[j]/Chunk.getIndex(0, 0, 1) & Chunk.chunkMask;
					int[] neighbors = ch.getNeighbors(bx, by, bz);
					for (int i = 0; i < 6; i++) {
						if(i == Neighbors.DIR_UP) continue;
						int b = neighbors[i];
						if (b == 0) {
							int dx = Neighbors.REL_X[i];
							int dy = Neighbors.REL_Y[i];
							int dz = Neighbors.REL_Z[i];
							if (dy == -1 || (neighbors[Neighbors.DIR_DOWN] != 0 && Blocks.blockClass(neighbors[Neighbors.DIR_DOWN]) != Blocks.BlockClass.FLUID)) {
								ch.addBlockPossiblyOutside(block, wx+bx+dx, wy+by+dy, wz+bz+dz, true);
							}
						}
					}
				}
			}
		}
	}
	
	public void updatePlayer(int x, int y, int z, int renderDistance, int entityDistance, ArrayList<NormalChunk> chunksList, ArrayList<ChunkEntityManager> managers) {
		// Shift the player position, so chunks are loaded once the center comes into render distance:
		x -= Chunk.chunkSize/2;
		y -= Chunk.chunkSize/2;
		z -= Chunk.chunkSize/2;
		int rdSquare = renderDistance*renderDistance << Chunk.chunkShift2;
		int edSquare = entityDistance*entityDistance << Chunk.chunkShift2;
		edSquare = Math.min(rdSquare, edSquare);
		for(int px = 0; px < metaChunkSize; px++) {
			int wx = px*Chunk.chunkSize + this.wx;
			long dx = Math.max(0, Math.abs(wx - x) - Chunk.chunkSize/2);
			long distX = dx*dx;
			for(int py = 0; py < metaChunkSize; py++) {
				int wy = py*Chunk.chunkSize + this.wy;
				long dy = Math.max(0, Math.abs(wy - y) - Chunk.chunkSize/2);
				long distY = dy*dy;
				for(int pz = 0; pz < metaChunkSize; pz++) {
					int wz = pz*Chunk.chunkSize + this.wz;
					long dz = Math.max(0, Math.abs(wz - z) - Chunk.chunkSize/2);
					long distZ = dz*dz;
					long dist = distX + distY + distZ;
					int index = (px << metaChunkShift) | (py <<  metaChunkShift2) | pz;
					NormalChunk chunk = chunks[index];
					if (dist > rdSquare) {
						if (chunk != null) {
							chunk.clean();
							chunks[index] = null;
						}
					} else if (chunk == null) {
						try {
							chunk = (NormalChunk)world.chunkProvider.getDeclaredConstructors()[0].newInstance(world, wx, wy, wz);
							chunks[index] = chunk;
							world.queueChunk(chunks[index]);
							chunksList.add(chunks[index]);
						} catch (Exception e) {
							Logger.error(e);
						}
					} else {
						chunksList.add(chunk);
					}
					ChunkEntityManager manager = entityManagers[index];
					if (dist > edSquare) {
						if (manager != null) {
							manager.chunk.map.mapIO.saveItemEntities(manager.itemEntityManager);
							entityManagers[index] = null;
						}
					} else if (manager == null) {
						manager = new ChunkEntityManager(world, chunk);
						entityManagers[index] = manager;
						managers.add(manager);
					} else {
						managers.add(manager);
					}
				}
			}
		}
	}
	
	public NormalChunk getChunk(int wx, int wy, int wz) {
		int cx = (wx - this.wx) >> Chunk.chunkShift;
		int cy = (wy - this.wy) >> Chunk.chunkShift;
		int cz = (wz - this.wz) >> Chunk.chunkShift;
		int index = (cx << metaChunkShift) | (cy <<  metaChunkShift2) | cz;
		return chunks[index];
	}
	
	public ChunkEntityManager getEntityManager(int wx, int wy, int wz) {
		int cx = (wx - this.wx) >> Chunk.chunkShift;
		int cy = (wy - this.wy) >> Chunk.chunkShift;
		int cz = (wz - this.wz) >> Chunk.chunkShift;
		int index = (cx << metaChunkShift) | (cy <<  metaChunkShift2) | cz;
		return entityManagers[index];
	}
}
