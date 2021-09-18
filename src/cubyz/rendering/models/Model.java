package cubyz.rendering.models;

import org.joml.Matrix3f;
import org.joml.Vector3f;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Neighbors;

/**
 * A simple data holder for the indexed model data.
 * Override for model specific optimizations(like for cube models).
 */
public class Model implements RegistryElement {
	public final float[] positions;
	public final float[] textCoords;
	public final float[] normals;
	public final int[] indices;
	private final Resource id;
	public Model(Resource id, float[] positions, float[] textCoords, float[] normals, int[] indices) {
		this.id = id;
		this.positions = positions;
		this.textCoords = textCoords;
		this.normals = normals;
		this.indices = indices;
	}
	
	private static void addWeightedLight(float weight, float[] srgb, int light) {
		srgb[0] += weight*(light>>>24);
		srgb[1] += weight*(light>>>16 & 255);
		srgb[2] += weight*(light>>>8 & 255);
		srgb[3] += weight*(light & 255);
	}
	public static int interpolateLight(float dx, float dy, float dz, float nx, float ny, float nz, int[] light) {
		dx += 0.5f + nx*0.5f - 0.0000001f;
		dy += 0.5f + ny*0.5f - 0.0000001f;
		dz += 0.5f + nz*0.5f - 0.0000001f;
		int x0 = (int)dx;
		int y0 = (int)dy;
		int z0 = (int)dz;
		dx -= x0;
		dy -= y0;
		dz -= z0;
		float[] srgb = new float[4];
		addWeightedLight((1 - dx)*(1 - dy)*(1 - dz), srgb, light[x0		+ y0*3		+ z0*9]);
		addWeightedLight((1 - dx)*(1 - dy)*dz      , srgb, light[x0		+ y0*3		+ (z0+1)*9]);
		addWeightedLight((1 - dx)*dy      *(1 - dz), srgb, light[x0		+ (y0+1)*3		+ z0*9]);
		addWeightedLight((1 - dx)*dy      *dz      , srgb, light[x0		+ (y0+1)*3		+ (z0+1)*9]);
		addWeightedLight(dx      *(1 - dy)*(1 - dz), srgb, light[(x0+1)	+ y0*3		+ z0*9]);
		addWeightedLight(dx      *(1 - dy)*dz      , srgb, light[(x0+1)	+ y0*3		+ (z0+1)*9]);
		addWeightedLight(dx      *dy      *(1 - dz), srgb, light[(x0+1)	+ (y0+1)*3		+ z0*9]);
		addWeightedLight(dx      *dy      *dz      , srgb, light[(x0+1)	+ (y0+1)*3		+ (z0+1)*9]);
		return (int)(srgb[0])<<24 | (int)(srgb[1])<<16 | (int)(srgb[2])<<8 | (int)(srgb[3]);
	}

	public static int normalToNeighbor(float nx, float ny, float nz) {
		if(nx == -1) {
			return Neighbors.DIR_NEG_X;
		}
		if(nx == 1) {
			return Neighbors.DIR_POS_X;
		}
		if(nz == -1) {
			return Neighbors.DIR_NEG_Z;
		}
		if(nz == 1) {
			return Neighbors.DIR_POS_Z;
		}
		if(ny == -1) {
			return Neighbors.DIR_DOWN;
		}
		if(ny == 1) {
			return Neighbors.DIR_UP;
		}
		return 0;
	}
	
	/**
	 * Adds model to chunk mesh without doing any further transformations.
	 * @param x position relative to chunk.min();
	 * @param y position relative to chunk.min();
	 * @param z position relative to chunk.min();
	 * @param offsetX on texture atlas
	 * @param offsetY on texture atlas
	 * @param light corner light data of block
	 * @param neighbors which of the neighbors of the block instance are full blocks.
	 * @param vertices
	 * @param normals
	 * @param faces
	 * @param lighting
	 * @param texture
	 * @param renderIndices
	 * @param renderIndex
	 */
	public void addToChunkMesh(int x, int y, int z, int[] textureIndices, int[] light, boolean[] neighbors, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		int indexOffset = vertices.size/3;
		for(int i = 0; i < positions.length; i += 3) {
			vertices.add(positions[i] + x);
			vertices.add(positions[i+1] + y);
			vertices.add(positions[i+2] + z);
			
			lighting.add(interpolateLight(positions[i], positions[i+1], positions[i+2], this.normals[i], this.normals[i+1], this.normals[i+2], light));
			renderIndices.add(renderIndex);
		}
		
		for(int i = 0; i < indices.length; i++) {
			faces.add(indices[i] + indexOffset);
		}
		
		for(int i = 0; i < textCoords.length; i += 2) {
			int i3 = i/2*3;
			texture.add(textCoords[i]);
			texture.add(textCoords[i+1]);
			texture.add((float)textureIndices[normalToNeighbor(this.normals[i3], this.normals[i3+1], this.normals[i3+2])]);
		}
		
		normals.add(this.normals);
	}
	
	protected static float conditionalInversion(float coord, boolean inverse) {
		return inverse ? 1-coord : coord;
	}
	
	/**
	 * Adds model to chunk mesh, but does a cube-symmetric rotation.
	 * @param x position relative to chunk.min();
	 * @param y position relative to chunk.min();
	 * @param z position relative to chunk.min();
	 * @param directionMap Maps each direction(x(0), y(1), z(2)) to which direction it was before rotation.
	 * @param directionInversion Shows which directions(x, y, z) are mirrored after applying rotation.
	 * @param offsetX on texture atlas
	 * @param offsetY on texture atlas
	 * @param light corner light data of block
	 * @param neighbors which of the neighbors of the block instance are full blocks.
	 * @param vertices
	 * @param normals
	 * @param faces
	 * @param lighting
	 * @param texture
	 * @param renderIndices
	 * @param renderIndex
	 */
	public void addToChunkMeshSimpleRotation(int x, int y, int z, int[] directionMap, boolean[] directionInversion, int[] textureIndices, int[] light, boolean[] neighbors, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		int indexOffset = vertices.size/3;
		for(int i = 0; i < positions.length; i += 3) {
			vertices.add(conditionalInversion(positions[i+directionMap[0]], directionInversion[0]) + x);
			vertices.add(conditionalInversion(positions[i+directionMap[1]], directionInversion[1]) + y);
			vertices.add(conditionalInversion(positions[i+directionMap[2]], directionInversion[2]) + z);
			
			lighting.add(interpolateLight(	conditionalInversion(positions[i+directionMap[0]], directionInversion[0]),
											conditionalInversion(positions[i+directionMap[1]], directionInversion[1]),
											conditionalInversion(positions[i+directionMap[2]], directionInversion[2]),
											this.normals[i], this.normals[i+1], this.normals[i+2], light));
			renderIndices.add(renderIndex);
		}
		
		for(int i = 0; i < indices.length; i++) {
			faces.add(indices[i] + indexOffset);
		}
		
		for(int i = 0; i < textCoords.length; i += 2) {
			int i3 = i/2*3;
			texture.add(textCoords[i]);
			texture.add(textCoords[i+1]);
			texture.add((float)textureIndices[normalToNeighbor(this.normals[i3], this.normals[i3+1], this.normals[i3+2])]);
		}
		
		normals.add(this.normals);
	}
	
	/**
	 * Adds model to chunk mesh, but multiplies a rotation matrix to the coordinates.
	 * This is also the only operation that allows floating point translation.
	 * @param x position relative to chunk.min();
	 * @param y position relative to chunk.min();
	 * @param z position relative to chunk.min();
	 * @param rotationMatrix set to null if only floating translation is required.
	 * @param offsetX on texture atlas
	 * @param offsetY on texture atlas
	 * @param light corner light data of block
	 * @param neighbors which of the neighbors of the block instance are full blocks.
	 * @param vertices
	 * @param normals
	 * @param faces
	 * @param lighting
	 * @param texture
	 * @param renderIndices
	 * @param renderIndex
	 */
	public void addToChunkMeshRotation(float x, float y, float z, Matrix3f rotationMatrix, int[] textureIndices, int[] light, boolean[] neighbors, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		int indexOffset = vertices.size/3;
		for(int i = 0; i < positions.length; i += 3) {
			Vector3f pos = new Vector3f(positions[i], positions[i+1], positions[i+2]);
			Vector3f normal = new Vector3f(this.normals[i], this.normals[i+1], this.normals[i+2]);
			if(rotationMatrix != null) {
				pos = pos.mul(rotationMatrix);
				normal = normal.mul(rotationMatrix);
			}
			vertices.add(pos.x + x);
			vertices.add(pos.y + y);
			vertices.add(pos.z + z);
			normals.add(normal.x);
			normals.add(normal.y);
			normals.add(normal.z);
			
			lighting.add(interpolateLight(pos.x, pos.y, pos.z, normal.x, normal.y, normal.z, light));
			renderIndices.add(renderIndex);
		}
		
		for(int i = 0; i < indices.length; i++) {
			faces.add(indices[i] + indexOffset);
		}
		
		for(int i = 0; i < textCoords.length; i += 2) {
			int i3 = i/2*3;
			texture.add(textCoords[i]);
			texture.add(textCoords[i+1]);
			texture.add((float)textureIndices[normalToNeighbor(this.normals[i3], this.normals[i3+1], this.normals[i3+2])]);
		}
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}
}
