package cubyz.world;

import java.util.ArrayList;
import java.util.HashMap;

import org.joml.FrustumIntersection;

import cubyz.client.ClientOnly;
import cubyz.client.Cubyz;
import cubyz.utils.datastructures.HashMapKey3D;
import cubyz.utils.math.CubyzMath;

public class RenderOctTree {
	private int lastX, lastY, lastZ, lastRD, lastLOD;
	private float lastFactor;
	public static class OctTreeNode {
		boolean shouldBeRemoved;
		public OctTreeNode[] nextNodes = null;
		public final int x, y, z, size;
		public Chunk chunk;
		public OctTreeNode(int x, int y, int z, int size) {
			this.x = x;
			this.y = y;
			this.z = z;
			this.size = size;
		}
		public void update(int px, int py, int pz, int renderDistance, int maxRD, int minHeight, int maxHeight, int nearRenderDistance) {
			double dx = Math.abs(CubyzMath.moduloMatchSign(x + size/2 - px, Cubyz.surface.getSizeX()));
			double dy = Math.abs(y + size/2 - py);
			double dz = Math.abs(CubyzMath.moduloMatchSign(z + size/2 - pz, Cubyz.surface.getSizeZ()));
			// Check if this chunk is outside the nearRenderDistance or outside the height limits:
			if(y + size <= Cubyz.surface.getRegion(x, z, 16).getMinHeight() || y > Cubyz.surface.getRegion(x, z, 16).getMaxHeight()) {
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
					if(chunk == null || !(chunk instanceof NormalChunk)) {
						if(chunk != null) {
							ClientOnly.deleteChunkMesh.accept(chunk);
							Cubyz.surface.unQueueChunk(chunk);
						}
						chunk = Cubyz.surface.getChunk(x >> NormalChunk.chunkShift, y >> NormalChunk.chunkShift, z >> NormalChunk.chunkShift);
					}
				} else {
					if(chunk == null || (chunk instanceof NormalChunk)) {
						if(chunk != null) {
							ClientOnly.deleteChunkMesh.accept(chunk);
							Cubyz.surface.unQueueChunk(chunk);
						}
						chunk = new ReducedChunk(x, y, z, 1, NormalChunk.chunkShift);
						Cubyz.surface.queueChunk(chunk);
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
						nextNodes[i] = new OctTreeNode(x + ((i & 1) == 0 ? 0 : size/2), y + ((i & 2) == 0 ? 0 : size/2), z + ((i & 4) == 0 ? 0 : size/2), size/2);
					}
				}
				for(int i = 0; i < 8; i++) {
					nextNodes[i].update(px, py, pz, renderDistance, maxRD/2, minHeight, maxHeight, nearRenderDistance);
				}
				if(chunk != null) {
					ClientOnly.deleteChunkMesh.accept(chunk);
					Cubyz.surface.unQueueChunk(chunk);
					chunk = null;
				}
			// Check if parts of this OctTree require a higher resolution:
			} else if(minDist < maxRD*maxRD/4 && size > NormalChunk.chunkSize*2) {
				if(nextNodes == null) {
					nextNodes = new OctTreeNode[8];
					for(int i = 0; i < 8; i++) {
						nextNodes[i] = new OctTreeNode(x + ((i & 1) == 0 ? 0 : size/2), y + ((i & 2) == 0 ? 0 : size/2), z + ((i & 4) == 0 ? 0 : size/2), size/2);
					}
				}
				for(int i = 0; i < 8; i++) {
					nextNodes[i].update(px, py, pz, renderDistance, maxRD/2, minHeight, maxHeight, nearRenderDistance);
				}
				if(chunk != null) {
					ClientOnly.deleteChunkMesh.accept(chunk);
					Cubyz.surface.unQueueChunk(chunk);
					chunk = null;
				}
			// This OctTree doesn't require higher resolution:
			} else {
				if(nextNodes != null) {
					for(int i = 0; i < 8; i++) {
						nextNodes[i].cleanup();
					}
					nextNodes = null;
				}
				if(chunk == null) {
					chunk = new ReducedChunk(x, y, z, CubyzMath.binaryLog(size) - NormalChunk.chunkShift, CubyzMath.binaryLog(size));
					Cubyz.surface.queueChunk(chunk);
				}
			}
		}
		public void getChunks(FrustumIntersection frustumInt, ArrayList<Chunk> chunks, float x0, float z0) {
			if(chunk != null) {
				if(testFrustum(frustumInt, x0, z0)) {
					chunks.add(chunk);
				}
			} else if(nextNodes != null) {
				for(int i = 0; i < 8; i++) {
					nextNodes[i].getChunks(frustumInt, chunks, x0, z0);
				}
			}
		}
		
		public boolean testFrustum(FrustumIntersection frustumInt, float x0, float z0) {
			return frustumInt.testAab(CubyzMath.match(x, x0, Cubyz.surface.getSizeX()), y, CubyzMath.match(z, z0, Cubyz.surface.getSizeZ()), 
					CubyzMath.match(x, x0, Cubyz.surface.getSizeX()) + size, y + size, CubyzMath.match(z, z0, Cubyz.surface.getSizeZ()) + size);
		}
		
		public void cleanup() {
			if(chunk != null) {
				ClientOnly.deleteChunkMesh.accept(chunk);
				Cubyz.surface.unQueueChunk(chunk);
				chunk = null;
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
					if(y + LODSize <= Cubyz.surface.getRegion(x, z, 16).getMinHeight() || y > Cubyz.surface.getRegion(x, z, 16).getMaxHeight()) {
						int dx = Math.max(0, Math.abs(x + LODSize/2 - px) - LODSize/2);
						int dy = Math.max(0, Math.abs(y + LODSize/2 - py) - LODSize/2);
						int dz = Math.max(0, Math.abs(z + LODSize/2 - pz) - LODSize/2);
						if(dx*dx + dy*dy + dz*dz > nearRenderDistance*nearRenderDistance) continue;
					}
					int x̅ = CubyzMath.worldModulo(x, Cubyz.surface.getSizeX());
					int z̅ = CubyzMath.worldModulo(z, Cubyz.surface.getSizeZ());
					int rootX = x̅ >> LODShift;
					int rootY = y >> LODShift;
					int rootZ = z̅ >> LODShift;
		
					HashMapKey3D key = new HashMapKey3D(rootX, rootY, rootZ);
					OctTreeNode node = roots.get(key);
					if(node == null) {
						node = new OctTreeNode(x̅, y, z̅, LODSize);
						// Mark this node to be potentially removed in the next update:
						node.shouldBeRemoved = true;
					} else {
						// Mark that this node should not be removed.
						node.shouldBeRemoved = false;
					}
					newMap.put(key, node);
					node.update(px, py, pz, renderDistance*NormalChunk.chunkSize, maxRenderDistance, Cubyz.surface.getRegion(x, z, 16).getMinHeight(), Cubyz.surface.getRegion(x, z, 16).getMaxHeight(), nearRenderDistance);
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
	
	public Chunk[] getRenderChunks(FrustumIntersection frustumInt, float x0, float z0) {
		ArrayList<Chunk> renderChunks = new ArrayList<>();
		for(OctTreeNode node : roots.values()) {
			// Check if the root is in the frustum:
			if(node.testFrustum(frustumInt, x0, z0)) {
				node.getChunks(frustumInt, renderChunks, x0, z0);
			}
		}
		return renderChunks.toArray(new Chunk[0]);
	}
	
	public void cleanup() {
		for(OctTreeNode node : roots.values()) {
			node.cleanup();
		}
		roots.clear();
	}
	
}
