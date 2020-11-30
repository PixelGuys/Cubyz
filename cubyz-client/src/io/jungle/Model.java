package io.jungle;

import io.cubyz.client.Meshes;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;

/**
 * A simple data holder for the indexed model data.
 * Override for model specific optimizations(like for cube models).
 */
public class Model {
	public final float[] positions;
	public final float[] textCoords;
	public final float[] normals;
	public final int[] indices;
	public Model(float[] positions, float[] textCoords, float[] normals, int[] indices) {
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
	private static int interpolateLight(float dx, float dy, float dz, int[] light) {
		float[] srgb = new float[4];
		addWeightedLight((1 - dx)*(1 - dy)*(1 - dz), srgb, light[0]);
		addWeightedLight((1 - dx)*(1 - dy)*dz      , srgb, light[1]);
		addWeightedLight((1 - dx)*dy      *(1 - dz), srgb, light[2]);
		addWeightedLight((1 - dx)*dy      *dz      , srgb, light[3]);
		addWeightedLight(dx      *(1 - dy)*(1 - dz), srgb, light[4]);
		addWeightedLight(dx      *(1 - dy)*dz      , srgb, light[5]);
		addWeightedLight(dx      *dy      *(1 - dz), srgb, light[6]);
		addWeightedLight(dx      *dy      *dz      , srgb, light[7]);
		return (int)(srgb[0])<<24 | (int)(srgb[1])<<16 | (int)(srgb[2])<<8 | (int)(srgb[3]);
	}
	
	/**
	 * Adds model to chunk mesh without doing any further transformations.
	 * @param x position relative to chunk.min();
	 * @param y position relative to chunk.min();
	 * @param z position relative to chunk.min();
	 * @param offsetX on texture atlas
	 * @param offsetY on texture atlas
	 * @param light corner light data of block
	 * @param vertices
	 * @param normals
	 * @param faces
	 * @param lighting
	 * @param texture
	 * @param renderIndices
	 * @param renderIndex
	 */
	public void addToChunkMesh(int x, int y, int z, float offsetX, float offsetY, int[] light, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		int indexOffset = vertices.size/3;
		for(int i = 0; i < positions.length; i += 3) {
			vertices.add(positions[i] + x);
			vertices.add(positions[i+1] + y);
			vertices.add(positions[i+2] + z);
			
			lighting.add(interpolateLight(positions[i], positions[i+1], positions[i+2], light));
			renderIndices.add(renderIndex);
		}
		
		for(int i = 0; i < indices.length; i++) {
			faces.add(indices[i] + indexOffset);
		}
		
		for(int i = 0; i < textCoords.length; i += 2) {
			texture.add((textCoords[i] + offsetX)/Meshes.atlasSize);
			texture.add((textCoords[i+1] + offsetY)/Meshes.atlasSize);
		}
		
		normals.add(this.normals);
	}
	
	private static float conditionalInversion(float coord, boolean inverse) {
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
	 * @param vertices
	 * @param normals
	 * @param faces
	 * @param lighting
	 * @param texture
	 * @param renderIndices
	 * @param renderIndex
	 */
	public void addToChunkMeshSimpleRotation(int x, int y, int z, int[] directionMap, boolean[] directionInversion, float offsetX, float offsetY, int[] light, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		int indexOffset = vertices.size/3;
		for(int i = 0; i < positions.length; i += 3) {
			vertices.add(conditionalInversion(positions[i+directionMap[0]], directionInversion[0]) + x);
			vertices.add(conditionalInversion(positions[i+directionMap[1]], directionInversion[1]) + y);
			vertices.add(conditionalInversion(positions[i+directionMap[2]], directionInversion[2]) + z);
			
			lighting.add(interpolateLight(positions[i+directionMap[0]], positions[i+directionMap[1]], positions[i+directionMap[2]], light));
			renderIndices.add(renderIndex);
		}
		
		for(int i = 0; i < indices.length; i++) {
			faces.add(indices[i] + indexOffset);
		}
		
		for(int i = 0; i < textCoords.length; i += 2) {
			texture.add((textCoords[i] + offsetX)/Meshes.atlasSize);
			texture.add((textCoords[i+1] + offsetY)/Meshes.atlasSize);
		}
		
		normals.add(this.normals);
	}
}
