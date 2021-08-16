package cubyz.world;

import java.util.ArrayList;

import cubyz.Logger;
import cubyz.client.ClientOnly;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.BlockEntity;
import cubyz.world.blocks.Updateable;
import cubyz.world.entity.ChunkEntityManager;

/**
 * A chunk of chunks.
 */

public class MetaChunk {
	public static final int metaChunkShift = 4;
	public static final int metaChunkShift2 = 2*metaChunkShift;
	public static final int metaChunkSize = 1 << metaChunkShift;
	public static final int worldShift = metaChunkShift + NormalChunk.chunkShift;
	public static final int worldMask = (1 << worldShift) - 1;
	public final int wx, wy, wz;
	public final NormalChunk[] chunks;
	public final ChunkEntityManager[] entityManagers;
	public final LocalSurface surface;
	public MetaChunk(int wx, int wy, int wz, LocalSurface surface) {
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		chunks = new NormalChunk[metaChunkSize*metaChunkSize*metaChunkSize];
		entityManagers = new ChunkEntityManager[metaChunkSize*metaChunkSize*metaChunkSize];
		this.surface = surface;
	}
	
	public void save() {
		for(NormalChunk chunk : chunks) {
			if(chunk != null)
				chunk.map.mapIO.saveChunk(chunk);
		}
		for(ChunkEntityManager manager : entityManagers) {
			if(manager != null)
				manager.chunk.map.mapIO.saveItemEntities(manager.itemEntityManager);
		}
	}
	
	public void updateBlockEntities() {
		for (NormalChunk ch : chunks) {
			if(ch != null && ch.isLoaded() && ch.getBlockEntities().size() > 0) {
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
			if(ch == null) continue;
			int wx = ch.getX() << NormalChunk.chunkShift;
			int wz = ch.getZ() << NormalChunk.chunkShift;
			if (ch.isLoaded() && ch.getLiquids().size() > 0) {
				Integer[] liquids = ch.getUpdatingLiquids().toArray(new Integer[0]);
				int size = ch.getUpdatingLiquids().size();
				ch.getUpdatingLiquids().clear();
				for (int j = 0; j < size; j++) {
					Block block = ch.getBlockAtIndex(liquids[j]);
					int bx = (liquids[j] >> NormalChunk.chunkShift) & NormalChunk.chunkMask;
					int by = liquids[j] >> NormalChunk.chunkShift2;
					int bz = liquids[j] & NormalChunk.chunkMask;
					Block[] neighbors = ch.getNeighbors(bx, by, bz);
					for (int i = 0; i < 5; i++) {
						Block b = neighbors[i];
						if (b == null) {
							int dx = 0, dy = 0, dz = 0;
							switch (i) {
								case 0: // at x -1
									dx = -1;
								break;
								case 1: // at x +1
									dx = 1;
									break;
								case 2:  // at z -1
									dz = -1;
									break;
								case 3: // at z +1
									dz = 1;
									break;
								case 4: // at y -1
									dy = -1;
									break;
								default:
									System.err.println("(LocalWorld/Liquids) More than 6 nullable neighbors!");
									break;
							}
							if(dy == -1 || (neighbors[4] != null && neighbors[4].getBlockClass() != Block.BlockClass.FLUID)) {
								ch.addBlockPossiblyOutside(block, (byte)0, wx+bx+dx, by+dy, wz+bz+dz, true);
							}
						}
					}
				}
			}
		}
	}
	
	public void cleanup() {
		for (NormalChunk chunk : chunks) {
			if(chunk == null) continue;
			ClientOnly.deleteChunkMesh.accept(chunk);
		}
	}
	
	public void updatePlayer(int x, int y, int z, int renderDistance, int entityDistance, ArrayList<NormalChunk> chunksList, ArrayList<ChunkEntityManager> managers) {
		// Shift the player position, so chunks are loaded once the center comes into render distance:
		x -= NormalChunk.chunkSize/2;
		y -= NormalChunk.chunkSize/2;
		z -= NormalChunk.chunkSize/2;
		int rdSquare = renderDistance*renderDistance << NormalChunk.chunkShift2;
		int edSquare = entityDistance*entityDistance << NormalChunk.chunkShift2;
		edSquare = Math.min(rdSquare, edSquare);
		for(int px = 0; px < metaChunkSize; px++) {
			long dx = px*NormalChunk.chunkSize + wx - x;
			long distX = dx*dx;
			for(int py = 0; py < metaChunkSize; py++) {
				long distY = (long)(py*NormalChunk.chunkSize + wy - y)*(py*NormalChunk.chunkSize + wy - y);
				for(int pz = 0; pz < metaChunkSize; pz++) {
					long dz = pz*NormalChunk.chunkSize + wz - z;
					long distZ = dz*dz;
					long dist = distX + distY + distZ;
					int index = (px << metaChunkShift) | (py <<  metaChunkShift2) | pz;
					NormalChunk chunk = chunks[index];
					if(dist > rdSquare) {
						if(chunk != null) {
							if(chunk.isGenerated())
								chunk.map.mapIO.saveChunk(chunk); // Only needs to be stored if it was ever generated.
							else
								surface.unQueueChunk(chunk);
							ClientOnly.deleteChunkMesh.accept(chunk);
							chunks[index] = null;
						}
					} else if(chunk == null) {
						try {
							chunk = (NormalChunk)surface.chunkProvider.getDeclaredConstructors()[0].newInstance((wx >> NormalChunk.chunkShift) + px, (wy >> NormalChunk.chunkShift) + py, (wz >> NormalChunk.chunkShift) + pz, surface);
							chunks[index] = chunk;
							surface.queueChunk(chunks[index]);
							chunksList.add(chunks[index]);
						} catch (Exception e) {
							Logger.throwable(e);
						}
					} else {
						chunksList.add(chunk);
					}
					ChunkEntityManager manager = entityManagers[index];
					if(dist > edSquare) {
						if(manager != null) {
							manager.chunk.map.mapIO.saveItemEntities(manager.itemEntityManager);
							entityManagers[index] = null;
						}
					} else if(manager == null) {
						manager = new ChunkEntityManager(surface, chunk);
						entityManagers[index] = manager;
						managers.add(manager);
					} else {
						managers.add(manager);
					}
				}
			}
		}
	}
	
	public NormalChunk getChunk(int cx, int cy, int cz) {
		cx -= wx >> NormalChunk.chunkShift;
		cy -= wy >> NormalChunk.chunkShift;
		cz -= wz >> NormalChunk.chunkShift;
		int index = (cx << metaChunkShift) | (cy <<  metaChunkShift2) | cz;
		return chunks[index];
	}
	
	public ChunkEntityManager getEntityManager(int cx, int cy, int cz) {
		cx -= wx >> NormalChunk.chunkShift;
		cy -= wy >> NormalChunk.chunkShift;
		cz -= wz >> NormalChunk.chunkShift;
		int index = (cx << metaChunkShift) | (cy <<  metaChunkShift2) | cz;
		return entityManagers[index];
	}
}
