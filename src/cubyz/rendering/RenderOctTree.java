package cubyz.rendering;

import java.util.ArrayList;
import java.util.HashMap;

import org.joml.FrustumIntersection;

import cubyz.client.ChunkMesh;
import cubyz.client.Cubyz;
import cubyz.client.Meshes;
import cubyz.client.NormalChunkMesh;
import cubyz.client.ReducedChunkMesh;
import cubyz.utils.datastructures.HashMapKey3D;
import cubyz.world.ChunkData;
import cubyz.world.NormalChunk;

public class RenderOctTree {
	private int lastX, lastY, lastZ, lastRD, lastLOD;
	private float lastFactor;
	public static class OctTreeNode {
		boolean shouldBeRemoved;
		public OctTreeNode[] nextNodes = null;
		public final int x, y, z, size;
		//public Chunk chunk;
		public ChunkMesh mesh;
		public OctTreeNode(ReducedChunkMesh replacement, int x, int y, int z, int size) {
			this.x = x;
			this.y = y;
			this.z = z;
			this.size = size;
			if(size == NormalChunk.chunkSize) {
				mesh = new NormalChunkMesh(replacement, x, y, z, size);
			} else {
				mesh = new ReducedChunkMesh(replacement, x, y, z, size);
				ChunkData data = new ChunkData(x, y, z, size/NormalChunk.chunkSize);
				data.setMeshListener((ReducedChunkMesh)mesh);
				Cubyz.world.queueChunk(data);
			}
		}
		public void update(int px, int py, int pz, int renderDistance, int maxRD, int minHeight, int maxHeight, int nearRenderDistance) {
			synchronized(this) {
				// Calculate the minimum distance between this chunk and the player:
				double dx = Math.abs(x + size/2 - px);
				double dy = Math.abs(y + size/2 - py);
				double dz = Math.abs(z + size/2 - pz);
				dx = Math.max(0, dx - size/2);
				dy = Math.max(0, dy - size/2);
				dz = Math.max(0, dz - size/2);
				double minDist = dx*dx + dy*dy + dz*dz;
				// Check if this chunk is outside the nearRenderDistance or outside the height limits:
				if(y + size <= Cubyz.world.getOrGenerateMapFragment(x, z, 32).getMinHeight() || y > Cubyz.world.getOrGenerateMapFragment(x, z, 32).getMaxHeight()) {
					if(minDist > nearRenderDistance*nearRenderDistance) {
						if(nextNodes != null) {
							for(int i = 0; i < 8; i++) {
								nextNodes[i].cleanup();
							}
							nextNodes = null;
						}
						return;
					}
				}
				
				// Check if this chunk has reached the smallest possible size:
				if(size == NormalChunk.chunkSize) {
					// Check if this is a normal or a reduced chunk:
					if(minDist < renderDistance*renderDistance) {
						if(mesh.getChunk() == null) {
							((NormalChunkMesh)mesh).updateChunk(Cubyz.world.getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift));
						}
					} else {
						if(mesh.getChunk() != null) {
							((NormalChunkMesh)mesh).updateChunk(null);
						}
					}
					return;
				}
				// Check if parts of this OctTree require using normal chunks:
				if(size == NormalChunk.chunkSize*2 && minDist < renderDistance*renderDistance) {
					if(nextNodes == null) {
						nextNodes = new OctTreeNode[8];
						for(int i = 0; i < 8; i++) {
							nextNodes[i] = new OctTreeNode((ReducedChunkMesh)mesh, x + ((i & 1) == 0 ? 0 : size/2), y + ((i & 2) == 0 ? 0 : size/2), z + ((i & 4) == 0 ? 0 : size/2), size/2);
						}
					}
					for(int i = 0; i < 8; i++) {
						nextNodes[i].update(px, py, pz, renderDistance, maxRD/2, minHeight, maxHeight, nearRenderDistance);
					}
				// Check if parts of this OctTree require a higher resolution:
				} else if(minDist < maxRD*maxRD/4 && size > NormalChunk.chunkSize*2) {
					if(nextNodes == null) {
						nextNodes = new OctTreeNode[8];
						for(int i = 0; i < 8; i++) {
							nextNodes[i] = new OctTreeNode((ReducedChunkMesh)mesh, x + ((i & 1) == 0 ? 0 : size/2), y + ((i & 2) == 0 ? 0 : size/2), z + ((i & 4) == 0 ? 0 : size/2), size/2);
						}
					}
					for(int i = 0; i < 8; i++) {
						nextNodes[i].update(px, py, pz, renderDistance, maxRD/2, minHeight, maxHeight, nearRenderDistance);
					}
				// This OctTree doesn't require higher resolution:
				} else {
					if(nextNodes != null) {
						for(int i = 0; i < 8; i++) {
							nextNodes[i].cleanup();
						}
						nextNodes = null;
					}
				}
			}
		}
		public void getChunks(FrustumIntersection frustumInt, ArrayList<ChunkMesh> meshes, double x0, double y0, double z0) {
			synchronized(this) {
				if(nextNodes != null) {
					for(int i = 0; i < 8; i++) {
						nextNodes[i].getChunks(frustumInt, meshes, x0, y0, z0);
					}
				} else {
					if(testFrustum(frustumInt, x0, y0, z0)) {
						meshes.add(mesh);
					}
				}
			}
		}
		
		public boolean testFrustum(FrustumIntersection frustumInt, double x0, double y0, double z0) {
			return frustumInt.testAab((float)(x - x0), (float)(y - y0), (float)(z - z0), (float)(x + size - x0), (float)(y + size - y0), (float)(z + size - z0));
		}
		
		public void cleanup() {
			if(mesh != null) {
				Meshes.deleteMesh(mesh);
				if(Cubyz.world != null)
					Cubyz.world.unQueueChunk(mesh.getChunk());
				mesh = null;
			}
			if(nextNodes != null) {
				for(int i = 0; i < 8; i++) {
					nextNodes[i].cleanup();
				}
			}
		}
	}
	HashMap<HashMapKey3D, OctTreeNode> roots = new HashMap<HashMapKey3D, OctTreeNode>();
	public void update(int px, int py, int pz, int renderDistance, int highestLOD, float LODFactor) {
		//if(lastX == px && lastY == py && lastZ == pz && lastRD == renderDistance && lastLOD == highestLOD && lastFactor == LODFactor) return; TODO: Send a chunk request to the server for normalChunks as well, to prevent issues here.
		
		int maxRenderDistance = (int)Math.ceil((renderDistance << highestLOD)*LODFactor*NormalChunk.chunkSize);
		int nearRenderDistance = renderDistance*NormalChunk.chunkSize; // Only render underground for nearby chunks. Otherwise the lag gets massive. TODO: render at least some ReducedChunks there.
		int LODShift = highestLOD + NormalChunk.chunkShift;
		int LODSize = NormalChunk.chunkSize << highestLOD;
		int LODMask = LODSize - 1;
		int minX = (px - maxRenderDistance - LODMask) & ~LODMask;
		int maxX = (px + maxRenderDistance + LODMask) & ~LODMask;
		// The LOD chunks are offset from grid to make generation easier.
		minX += LODSize/2 - NormalChunk.chunkSize;
		maxX += LODSize/2 - NormalChunk.chunkSize;
		HashMap<HashMapKey3D, OctTreeNode> newMap = new HashMap<HashMapKey3D, OctTreeNode>();
		for(int x = minX; x <= maxX; x += LODSize) {
			int maxYRenderDistance = (int)Math.ceil(Math.sqrt(maxRenderDistance*maxRenderDistance - (x - px)*(x - px)));
			int minY = (py - maxYRenderDistance - LODMask) & ~LODMask;
			int maxY = (py + maxYRenderDistance + LODMask) & ~LODMask;
			// The LOD chunks are offset from grid to make generation easier.
			minY += LODSize/2 - NormalChunk.chunkSize;
			maxY += LODSize/2 - NormalChunk.chunkSize;
			
			for(int y = minY; y <= maxY; y += LODSize) {
				int maxZRenderDistance = (int)Math.ceil(Math.sqrt(maxYRenderDistance*maxYRenderDistance - (y - py)*(y - py)));
				int minZ = (pz - maxZRenderDistance - LODMask) & ~LODMask;
				int maxZ = (pz + maxZRenderDistance + LODMask) & ~LODMask;
				// The LOD chunks are offset from grid to make generation easier.
				minZ += LODSize/2 - NormalChunk.chunkSize;
				maxZ += LODSize/2 - NormalChunk.chunkSize;
				
				for(int z = minZ; z <= maxZ; z += LODSize) {
					// Make sure underground chunks are only generated if they are close to the player.
					if(y + LODSize <= Cubyz.world.getOrGenerateMapFragment(x, z, 32).getMinHeight() || y > Cubyz.world.getOrGenerateMapFragment(x, z, 32).getMaxHeight()) {
						int dx = Math.max(0, Math.abs(x + LODSize/2 - px) - LODSize/2);
						int dy = Math.max(0, Math.abs(y + LODSize/2 - py) - LODSize/2);
						int dz = Math.max(0, Math.abs(z + LODSize/2 - pz) - LODSize/2);
						if(dx*dx + dy*dy + dz*dz > nearRenderDistance*nearRenderDistance) continue;
					}
					int rootX = x >> LODShift;
					int rootY = y >> LODShift;
					int rootZ = z >> LODShift;
		
					HashMapKey3D key = new HashMapKey3D(rootX, rootY, rootZ);
					OctTreeNode node = roots.get(key);
					if(node == null) {
						node = new OctTreeNode(null, x, y, z, LODSize);
						// Mark this node to be potentially removed in the next update:
						node.shouldBeRemoved = true;
					} else {
						// Mark that this node should not be removed.
						node.shouldBeRemoved = false;
					}
					newMap.put(key, node);
					node.update(px, py, pz, renderDistance*NormalChunk.chunkSize, maxRenderDistance, Cubyz.world.getOrGenerateMapFragment(x, z, 32).getMinHeight(), Cubyz.world.getOrGenerateMapFragment(x, z, 32).getMaxHeight(), nearRenderDistance);
				}
			}
		}
		// Clean memory for unused nodes:
		for(OctTreeNode node : roots.values()) {
			if(node.shouldBeRemoved) {
				node.cleanup();
			} else {
				// Mark this node to be potentially removed in the next update:
				node.shouldBeRemoved = true;
			}
		}
		roots = newMap;
		lastX = px;
		lastY = py;
		lastZ = pz;
		lastRD = renderDistance;
		lastLOD = highestLOD;
		lastFactor = LODFactor;
		
	}
	
	public ChunkMesh[] getRenderChunks(FrustumIntersection frustumInt, double x0, double y0, double z0) {
		ArrayList<ChunkMesh> meshes = new ArrayList<>();
		for(OctTreeNode node : roots.values()) {
			// Check if the root is in the frustum:
			if(node.testFrustum(frustumInt, x0, y0, z0)) {
				node.getChunks(frustumInt, meshes, x0, y0, z0);
			}
		}
		return meshes.toArray(new ChunkMesh[0]);
	}
	
	public void cleanup() {
		for(OctTreeNode node : roots.values()) {
			node.cleanup();
		}
		roots.clear();
	}
	
}
