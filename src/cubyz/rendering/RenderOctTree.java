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
import cubyz.utils.math.CubyzMath;
import cubyz.world.NormalChunk;
import cubyz.world.ReducedChunk;

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
			System.out.println(replacement);
			this.x = x;
			this.y = y;
			this.z = z;
			this.size = size;
			if(size == NormalChunk.chunkSize) {
				mesh = new NormalChunkMesh(replacement, x, y, z, size);
			} else {
				mesh = new ReducedChunkMesh(replacement, x, y, z, size);
			}
		}
		public void update(int px, int py, int pz, int renderDistance, int maxRD, int minHeight, int maxHeight, int nearRenderDistance) {
			synchronized(this) {
				double dx = Math.abs(x + size/2 - px);
				double dy = Math.abs(y + size/2 - py);
				double dz = Math.abs(z + size/2 - pz);
				// Check if this chunk is outside the nearRenderDistance or outside the height limits:
				if(y + size <= Cubyz.surface.getMapFragment(x, z, 16).getMinHeight() || y > Cubyz.surface.getMapFragment(x, z, 16).getMaxHeight()) {
					int dx2 = (int)Math.max(0, dx - size/2);
					int dy2 = (int)Math.max(0, dy - size/2);
					int dz2 = (int)Math.max(0, dz - size/2);
					if(dx2*dx2 + dy2*dy2 + dz2*dz2 > nearRenderDistance*nearRenderDistance) return;
				}
				
				// Check if this chunk has reached the smallest possible size:
				if(size == NormalChunk.chunkSize) {
					// Check if this is a normal or a reduced chunk:
					double dist = dx*dx + dy*dy + dz*dz;
					if(dist < renderDistance*renderDistance) {
						if(mesh.getChunk() == null) {
							((NormalChunkMesh)mesh).updateChunk(Cubyz.surface.getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift));
						}
					} else {
						if(mesh.getChunk() != null) {
							((NormalChunkMesh)mesh).updateChunk(null);
						}
					}
					return;
				}
				// Calculate the minimum distance between the next nodes and the player:
				dx = Math.max(0, dx - size/4);
				dy = Math.max(0, dy - size/4);
				dz = Math.max(0, dz - size/4);
				double minDist = dx*dx + dy*dy + dz*dz;
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
				if(mesh.getChunk() == null) {
					((ReducedChunkMesh)mesh).updateChunk(new ReducedChunk(x, y, z, CubyzMath.binaryLog(size) - NormalChunk.chunkShift, CubyzMath.binaryLog(size)));
					Cubyz.surface.queueChunk(mesh.getChunk());
				}
			}
		}
		public void getChunks(FrustumIntersection frustumInt, ArrayList<ChunkMesh> meshes, float x0, float z0) {
			synchronized(this) {
				if(nextNodes != null) {
					for(int i = 0; i < 8; i++) {
						nextNodes[i].getChunks(frustumInt, meshes, x0, z0);
					}
				} else {
					if(testFrustum(frustumInt, x0, z0)) {
						meshes.add(mesh);
					}
				}
			}
		}
		
		public boolean testFrustum(FrustumIntersection frustumInt, float x0, float z0) {
			return frustumInt.testAab(x, y, z, x + size, y + size, z + size);
		}
		
		public void cleanup() {
			if(mesh != null) {
				Meshes.deleteMesh(mesh);
				Cubyz.surface.unQueueChunk(mesh.getChunk());
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
		if(lastX == px && lastY == py && lastZ == pz && lastRD == renderDistance && lastLOD == highestLOD && lastFactor == LODFactor) return;
		
		int maxRenderDistance = (int)Math.ceil((renderDistance << highestLOD)*LODFactor*NormalChunk.chunkSize);
		int nearRenderDistance = renderDistance*NormalChunk.chunkSize; // Only render underground for nearby chunks. Otherwise the lag gets massive. TODO: render at least some ReducedChunks there.
		int LODShift = highestLOD + NormalChunk.chunkShift;
		int LODSize = NormalChunk.chunkSize << highestLOD;
		int LODMask = LODSize - 1;
		int minX = (px - maxRenderDistance) & ~LODMask;
		int maxX = (px + maxRenderDistance + LODMask) & ~LODMask;
		HashMap<HashMapKey3D, OctTreeNode> newMap = new HashMap<HashMapKey3D, OctTreeNode>();
		for(int x = minX; x <= maxX; x += LODSize) {
			int maxYRenderDistance = (int)Math.ceil(Math.sqrt(maxRenderDistance*maxRenderDistance - (x - px)*(x - px)));
			int minY = (py - maxYRenderDistance) & ~LODMask;
			int maxY = (py + maxYRenderDistance + LODMask) & ~LODMask;
			
			for(int y = minY; y <= maxY; y += LODSize) {
				int maxZRenderDistance = (int)Math.ceil(Math.sqrt(maxYRenderDistance*maxYRenderDistance - (y - py)*(y - py)));
				int minZ = (pz - maxZRenderDistance) & ~LODMask;
				int maxZ = (pz + maxZRenderDistance + LODMask) & ~LODMask;
				
				for(int z = minZ; z <= maxZ; z += LODSize) {
					// Make sure underground chunks are only generated if they are close to the player.
					if(y + LODSize <= Cubyz.surface.getMapFragment(x, z, 16).getMinHeight() || y > Cubyz.surface.getMapFragment(x, z, 16).getMaxHeight()) {
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
					node.update(px, py, pz, renderDistance*NormalChunk.chunkSize, maxRenderDistance, Cubyz.surface.getMapFragment(x, z, 16).getMinHeight(), Cubyz.surface.getMapFragment(x, z, 16).getMaxHeight(), nearRenderDistance);
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
	
	public ChunkMesh[] getRenderChunks(FrustumIntersection frustumInt, float x0, float z0) {
		ArrayList<ChunkMesh> meshes = new ArrayList<>();
		for(OctTreeNode node : roots.values()) {
			// Check if the root is in the frustum:
			if(node.testFrustum(frustumInt, x0, z0)) {
				node.getChunks(frustumInt, meshes, x0, z0);
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
