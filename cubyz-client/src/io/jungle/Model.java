package io.jungle;

import io.cubyz.client.Meshes;
import io.cubyz.util.FloatFastList;
import io.cubyz.util.IntFastList;

/**
 * A simple data holder for the indexed model data.
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
	
	public void addToChunkMesh(int x, int y, int z, float offsetX, float offsetY, int[] light, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture) {
		int indexOffset = vertices.size/3;
		for(int i = 0; i < positions.length; i += 3) {
			vertices.add(positions[i] + x);
			vertices.add(positions[i+1] + y);
			vertices.add(positions[i+2] + z);
			
			lighting.add(interpolateLight(positions[i], positions[i+1], positions[i+2], light));
		}
		
		for(int i = 0; i < indices.length; i++) {
			faces.add(indices[i] + indexOffset);
		}
		
		for(int i = 0; i < textCoords.length; i += 2) {
			// TODO: Use atlas specific coordinates!
			texture.add((textCoords[i] + offsetX)/Meshes.atlasSize);
			texture.add((textCoords[i+1] + offsetY)/Meshes.atlasSize);
		}
		
		normals.add(this.normals);
	}
}
