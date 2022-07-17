package cubyz.rendering;

import java.util.ArrayList;
import java.util.HashMap;

import cubyz.Constants;
import cubyz.multiplayer.Protocols;
import cubyz.world.*;
import org.joml.FrustumIntersection;

import cubyz.client.ChunkMesh;
import cubyz.client.Cubyz;
import cubyz.client.Meshes;
import cubyz.client.NormalChunkMesh;
import cubyz.client.ReducedChunkMesh;
import cubyz.utils.datastructures.HashMapKey3D;

public class RenderOctTree {
	private int lastX, lastY, lastZ, lastRD;
	private float lastFactor;
	public static class OctTreeNode {
		boolean shouldBeRemoved;
		public OctTreeNode[] nextNodes = null;
		public final int wx, wy, wz, size;
		public final ChunkMesh mesh;
		
		public OctTreeNode(ReducedChunkMesh replacement, int wx, int wy, int wz, int size, ArrayList<ChunkData> meshRequests) {
			this.wx = wx;
			this.wy = wy;
			this.wz = wz;
			this.size = size;
			if (size == Chunk.chunkSize) {
				mesh = new NormalChunkMesh(replacement, wx, wy, wz, size);
			} else {
				mesh = new ReducedChunkMesh(replacement, wx, wy, wz, size);
			}
			meshRequests.add(new ChunkData(wx, wy, wz, mesh.voxelSize));
		}
		public void update(int px, int py, int pz, int renderDistance, int maxRD, int minHeight, int maxHeight, int nearRenderDistance, ArrayList<ChunkData> meshRequests) {
			synchronized(this) {
				// Calculate the minimum distance between this chunk and the player:
				double minDist = mesh.getMinDistanceSquared(px, py, pz);
				// Check if this chunk is outside the nearRenderDistance or outside the height limits:
				if (wy + size <= 0/*Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMinHeight()*/ || wy > 1024/*Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMaxHeight()*/) {
					if (minDist > nearRenderDistance*nearRenderDistance) {
						if (nextNodes != null) {
							for(int i = 0; i < 8; i++) {
								nextNodes[i].cleanup();
							}
							nextNodes = null;
						}
						return;
					}
				}
				// Check if parts of this OctTree require using normal chunks:
				if (size == Chunk.chunkSize*2 && minDist < renderDistance*renderDistance) {
					if (nextNodes == null) {
						OctTreeNode[] nextNodes = new OctTreeNode[8];
						for(int i = 0; i < 8; i++) {
							nextNodes[i] = new OctTreeNode((ReducedChunkMesh)mesh, wx + ((i & 1) == 0 ? 0 : size/2), wy + ((i & 2) == 0 ? 0 : size/2), wz + ((i & 4) == 0 ? 0 : size/2), size/2, meshRequests);
						}
						this.nextNodes = nextNodes;
					}
					for(int i = 0; i < 8; i++) {
						nextNodes[i].update(px, py, pz, renderDistance, maxRD/2, minHeight, maxHeight, nearRenderDistance, meshRequests);
					}
				// Check if parts of this OctTree require a higher resolution:
				} else if (minDist < maxRD*maxRD/4 && size > Chunk.chunkSize*2) {
					if (nextNodes == null) {
						OctTreeNode[] nextNodes = new OctTreeNode[8];
						for(int i = 0; i < 8; i++) {
							nextNodes[i] = new OctTreeNode((ReducedChunkMesh)mesh, wx + ((i & 1) == 0 ? 0 : size/2), wy + ((i & 2) == 0 ? 0 : size/2), wz + ((i & 4) == 0 ? 0 : size/2), size/2, meshRequests);
						}
						this.nextNodes = nextNodes;
					}
					for(int i = 0; i < 8; i++) {
						nextNodes[i].update(px, py, pz, renderDistance, maxRD/2, minHeight, maxHeight, nearRenderDistance, meshRequests);
					}
				// This OctTree doesn't require higher resolution:
				} else {
					if (nextNodes != null) {
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
				if (nextNodes != null) {
					for(int i = 0; i < 8; i++) {
						nextNodes[i].getChunks(frustumInt, meshes, x0, y0, z0);
					}
				} else {
					if (testFrustum(frustumInt, x0, y0, z0)) {
						meshes.add(mesh);
					}
				}
			}
		}
		
		public boolean testFrustum(FrustumIntersection frustumInt, double x0, double y0, double z0) {
			return frustumInt.testAab((float)(wx - x0), (float)(wy - y0), (float)(wz - z0), (float)(wx + size - x0), (float)(wy + size - y0), (float)(wz + size - z0));
		}
		
		public void cleanup() {
			if (mesh != null) {
				Meshes.deleteMesh(mesh);
				// TODO: Look into unqueue-ing the chunk when it isn't needed anymore. Maybe that could be done server-side?
			}
			if (nextNodes != null) {
				for(int i = 0; i < 8; i++) {
					nextNodes[i].cleanup();
				}
			}
		}
	}
	HashMap<HashMapKey3D, OctTreeNode> roots = new HashMap<>();
	public void update(int renderDistance, float LODFactor) {
		if(lastRD != renderDistance || lastFactor != LODFactor) {
			Protocols.GENERIC_UPDATE.sendRenderDistance(Cubyz.world.serverConnection, renderDistance, LODFactor);
		}
		int px = (int)Cubyz.player.getPosition().x;
		int py = (int)Cubyz.player.getPosition().y;
		int pz = (int)Cubyz.player.getPosition().z;
		//if (lastX == px && lastY == py && lastZ == pz && lastRD == renderDistance && lastFactor == LODFactor) return; TODO: Send a chunk request to the server for normalChunks as well, to prevent issues here.
		
		int maxRenderDistance = (int)Math.ceil((renderDistance << Constants.HIGHEST_LOD)*LODFactor*Chunk.chunkSize);
		int nearRenderDistance = renderDistance*Chunk.chunkSize; // Only render underground for nearby chunks. Otherwise the lag gets massive. TODO: render at least some ReducedChunks there.
		int LODShift = Constants.HIGHEST_LOD + Chunk.chunkShift;
		int LODSize = Chunk.chunkSize << Constants.HIGHEST_LOD;
		int LODMask = LODSize - 1;
		int minX = (px - maxRenderDistance - LODMask) & ~LODMask;
		int maxX = (px + maxRenderDistance + LODMask) & ~LODMask;
		// The LOD chunks are offset from grid to make generation easier.
		minX += LODSize/2 - Chunk.chunkSize;
		maxX += LODSize/2 - Chunk.chunkSize;
		HashMap<HashMapKey3D, OctTreeNode> newMap = new HashMap<>();
		ArrayList<ChunkData> meshRequests = new ArrayList<>();
		for(int x = minX; x <= maxX; x += LODSize) {
			int maxYRenderDistance = (int)Math.ceil(Math.sqrt(maxRenderDistance*maxRenderDistance - (x - px)*(x - px)));
			int minY = (py - maxYRenderDistance - LODMask) & ~LODMask;
			int maxY = (py + maxYRenderDistance + LODMask) & ~LODMask;
			// The LOD chunks are offset from grid to make generation easier.
			minY += LODSize/2 - Chunk.chunkSize;
			maxY += LODSize/2 - Chunk.chunkSize;
			
			for(int y = minY; y <= maxY; y += LODSize) {
				int maxZRenderDistance = (int)Math.ceil(Math.sqrt(maxYRenderDistance*maxYRenderDistance - (y - py)*(y - py)));
				int minZ = (pz - maxZRenderDistance - LODMask) & ~LODMask;
				int maxZ = (pz + maxZRenderDistance + LODMask) & ~LODMask;
				// The LOD chunks are offset from grid to make generation easier.
				minZ += LODSize/2 - Chunk.chunkSize;
				maxZ += LODSize/2 - Chunk.chunkSize;
				
				for(int z = minZ; z <= maxZ; z += LODSize) {
					// Make sure underground chunks are only generated if they are close to the player.
					if (y + LODSize <= 0/*Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMinHeight()*/ || y > 1024/*Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMaxHeight()*/) {
						int dx = Math.max(0, Math.abs(x + LODSize/2 - px) - LODSize/2);
						int dy = Math.max(0, Math.abs(y + LODSize/2 - py) - LODSize/2);
						int dz = Math.max(0, Math.abs(z + LODSize/2 - pz) - LODSize/2);
						if (dx*dx + dy*dy + dz*dz > nearRenderDistance*nearRenderDistance) continue;
					}
					int rootX = x >> LODShift;
					int rootY = y >> LODShift;
					int rootZ = z >> LODShift;
		
					HashMapKey3D key = new HashMapKey3D(rootX, rootY, rootZ);
					OctTreeNode node = roots.get(key);
					if (node == null) {
						node = new OctTreeNode(null, x, y, z, LODSize, meshRequests);
						// Mark this node to be potentially removed in the next update:
						node.shouldBeRemoved = true;
					} else {
						// Mark that this node should not be removed.
						node.shouldBeRemoved = false;
					}
					newMap.put(key, node);
					node.update(px, py, pz, renderDistance*Chunk.chunkSize, maxRenderDistance, 0/*Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMinHeight()*/, 1024/*Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMaxHeight()*/, nearRenderDistance, meshRequests);
				}
			}
		}
		// Clean memory for unused nodes:
		for(OctTreeNode node : roots.values()) {
			if (node.shouldBeRemoved) {
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
		lastFactor = LODFactor;
		// Make requests after updating the list, to avoid concurrency issues and reduce number of requests:
		Cubyz.world.queueChunks(meshRequests.toArray(new ChunkData[0]));
	}

	public OctTreeNode findNode(ChunkData chunkData) {
		int LODShift = Constants.HIGHEST_LOD + Chunk.chunkShift;
		int LODSize = 1 << LODShift;
		int rootX = (chunkData.wx - LODSize/2 + Chunk.chunkSize) >> LODShift;
		int rootY = (chunkData.wy - LODSize/2 + Chunk.chunkSize) >> LODShift;
		int rootZ = (chunkData.wz - LODSize/2 + Chunk.chunkSize) >> LODShift;

		HashMapKey3D key = new HashMapKey3D(rootX, rootY, rootZ);

		OctTreeNode node = roots.get(key);
		if (node == null) return null;

		outer:
		while (node.mesh.voxelSize != chunkData.voxelSize) {
			OctTreeNode[] nextNodes = node.nextNodes;
			if (nextNodes == null) return null;
			for (int i = 0; i < 8; i++) {
				if (nextNodes[i].wx <= chunkData.wx && nextNodes[i].wx + nextNodes[i].size > chunkData.wx
						&& nextNodes[i].wy <= chunkData.wy && nextNodes[i].wy + nextNodes[i].size > chunkData.wy
						&& nextNodes[i].wz <= chunkData.wz && nextNodes[i].wz + nextNodes[i].size > chunkData.wz) {
					node = nextNodes[i];
					continue outer;
				}
			}
			return null;
		}

		return node;
	}

	public void updateChunkMesh(VisibleChunk mesh) {
		OctTreeNode node = findNode(mesh);
		if (node != null) {
			((NormalChunkMesh)node.mesh).updateChunk(mesh);
		}
	}

	public void updateChunkMesh(ReducedChunkVisibilityData mesh) {
		OctTreeNode node = findNode(mesh);
		if (node != null) {
			((ReducedChunkMesh)node.mesh).updateChunk(mesh);
		}
	}
	
	public ChunkMesh[] getRenderChunks(FrustumIntersection frustumInt, double x0, double y0, double z0) {
		ArrayList<ChunkMesh> meshes = new ArrayList<>();
		for(OctTreeNode node : roots.values()) {
			// Check if the root is in the frustum:
			if (node.testFrustum(frustumInt, x0, y0, z0)) {
				node.getChunks(frustumInt, meshes, x0, y0, z0);
			}
		}
		return meshes.toArray(new ChunkMesh[0]);
	}
	
	public void cleanup() {
		lastRD = 0;
		lastFactor = 0;
		for(OctTreeNode node : roots.values()) {
			node.cleanup();
		}
		roots.clear();
		Meshes.clearMeshQueue();
	}
	
}
