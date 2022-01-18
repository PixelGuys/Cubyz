package cubyz.rendering.models;

import cubyz.api.Resource;
import cubyz.client.Meshes;
import cubyz.rendering.ModelLoader;
import cubyz.utils.VertexAttribList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Neighbors;

import static cubyz.client.NormalChunkMesh.*;

public class CubeModel extends Model {
	protected CubeModel(Resource id, Model template) {
		super(id, template.positions, template.textCoords, template.normals, template.indices);
	}

	@Override
	public void addToChunkMesh(int x, int y, int z, int[] textureIndices, int[] light, byte neighbors, VertexAttribList vertices, IntFastList faces) {
		// Being a cube it is possible to optimize neighbor data:
		int indexOffset = vertices.currentVertex();
		int size = positions.length/3;
		int[] indicesAdded = new int[size];
		int position = 0;
		for(int i = 0; i < size; i++) {
			int i2 = i*2;
			int i3 = i*3;
			float nx = super.normals[i3];
			float ny = super.normals[i3+1];
			float nz = super.normals[i3+2];
			if (nx == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_X]) != 0 ||
			   nx == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_X]) != 0 ||
			   nz == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_Z]) != 0 ||
			   nz == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_Z]) != 0 ||
			   ny == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_DOWN]) != 0 ||
			   ny == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_UP]) != 0) {
				vertices.add(POSITION_X, positions[i3] + x);
				vertices.add(POSITION_Y, positions[i3+1] + y);
				vertices.add(POSITION_Z, positions[i3+2] + z);
				vertices.add(NORMAL_X, nx);
				vertices.add(NORMAL_Y, ny);
				vertices.add(NORMAL_Z, nz);
				
				vertices.add(LIGHTING, Model.interpolateLight(positions[i3], positions[i3+1], positions[i3+2], super.normals[i3], super.normals[i3+1], super.normals[i3+2], light));
				
				vertices.add(TEXTURE_X, textCoords[i2]);
				vertices.add(TEXTURE_Y, textCoords[i2+1]);
				vertices.add(TEXTURE_Z, (float)textureIndices[normalToNeighbor(this.normals[i3], this.normals[i3+1], this.normals[i3+2])]);
				
				vertices.endVertex();
				indicesAdded[i] = position++;
			} else {
				indicesAdded[i] = -1;
			}
		}
		
		for(int i = 0; i < indices.length; i += 3) {
			if (indicesAdded[indices[i]] != -1 && indicesAdded[indices[i + 1]] != -1 && indicesAdded[indices[i + 2]] != -1) {
				faces.add(indicesAdded[indices[i]] + indexOffset, indicesAdded[indices[i + 1]] + indexOffset, indicesAdded[indices[i + 2]] + indexOffset);
			}
		}
	}

	@Override
	public void addToChunkMeshSimpleRotation(int x, int y, int z, int[] directionMap, boolean[] directionInversion, int[] textureIndices, int[] light, byte neighbors, VertexAttribList vertices, IntFastList faces) {
		// Being a cube it is possible to optimize neighbor data:
		int indexOffset = vertices.currentVertex();
		int size = positions.length/3;
		int[] indicesAdded = new int[size];
		int position = 0;
		for(int i = 0; i < size; i++) {
			int i2 = i*2;
			int i3 = i*3;
			float nx = conditionalInversion(super.normals[i3+directionMap[0]]*0.5f + 0.5f, directionInversion[0])*2 - 1;
			float ny = conditionalInversion(super.normals[i3+directionMap[1]]*0.5f + 0.5f, directionInversion[1])*2 - 1;
			float nz = conditionalInversion(super.normals[i3+directionMap[2]]*0.5f + 0.5f, directionInversion[2])*2 - 1;
			if (nx == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_X]) != 0 ||
			   nx == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_X]) != 0 ||
			   nz == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_NEG_Z]) != 0 ||
			   nz == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_POS_Z]) != 0 ||
			   ny == -1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_DOWN]) != 0 ||
			   ny == 1 && (neighbors & Neighbors.BIT_MASK[Neighbors.DIR_UP]) != 0) {
				vertices.add(POSITION_X, conditionalInversion(positions[i3+directionMap[0]], directionInversion[0]) + x);
				vertices.add(POSITION_Y, conditionalInversion(positions[i3+directionMap[1]], directionInversion[1]) + y);
				vertices.add(POSITION_Z, conditionalInversion(positions[i3+directionMap[2]], directionInversion[2]) + z);
				vertices.add(NORMAL_X, nx);
				vertices.add(NORMAL_Y, ny);
				vertices.add(NORMAL_Z, nz);

				
				vertices.add(LIGHTING, interpolateLight(conditionalInversion(positions[i3+directionMap[0]], directionInversion[0]),
				                                        conditionalInversion(positions[i3+directionMap[1]], directionInversion[1]),
				                                        conditionalInversion(positions[i3+directionMap[2]], directionInversion[2]),
				                                        nx, ny, nz, light));

				vertices.add(TEXTURE_X, textCoords[i2]);
				vertices.add(TEXTURE_Y, textCoords[i2+1]);
				vertices.add(TEXTURE_Z, (float)textureIndices[normalToNeighbor(this.normals[i3], this.normals[i3+1], this.normals[i3+2])]);
				
				vertices.endVertex();

				indicesAdded[i] = position++;
			} else {
				indicesAdded[i] = -1;
			}
		}
		
		for(int i = 0; i < indices.length; i += 3) {
			if (indicesAdded[indices[i]] != -1 && indicesAdded[indices[i + 1]] != -1 && indicesAdded[indices[i + 2]] != -1) {
				faces.add(indicesAdded[indices[i]] + indexOffset, indicesAdded[indices[i + 1]] + indexOffset, indicesAdded[indices[i + 2]] + indexOffset);
			}
		}
	}
	
	
	public static void registerCubeModels() {
		Model standardCube = ModelLoader.loadUnregisteredModel(new Resource("", ""), "assets/cubyz/models/3d/block.obj");
		standardCube = new CubeModel(new Resource("cubyz", "block.obj"), standardCube);
		Meshes.models.register(standardCube);
	}
}
