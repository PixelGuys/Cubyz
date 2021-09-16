package cubyz.rendering.models;

import cubyz.api.Resource;
import cubyz.client.Meshes;
import cubyz.rendering.ModelLoader;
import cubyz.utils.datastructures.FloatFastList;
import cubyz.utils.datastructures.IntFastList;
import cubyz.world.Neighbors;

public class CubeModel extends Model {
	protected CubeModel(Resource id, Model template) {
		super(id, template.positions, template.textCoords, template.normals, template.indices);
	}

	@Override
	public void addToChunkMesh(int x, int y, int z, float offsetX, float offsetY, int[] light, boolean[] neighbors, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		// Being a cube it is possible to optimize neighbor data:
		int indexOffset = vertices.size/3;
		int size = positions.length/3;
		IntFastList indexesAdded = new IntFastList(24);
		for(int i = 0; i < size; i++) {
			int i2 = i*2;
			int i3 = i*3;
			float nx = super.normals[i3];
			float ny = super.normals[i3+1];
			float nz = super.normals[i3+2];
			if(nx == -1 && neighbors[Neighbors.DIR_NEG_X] ||
			   nx == 1 && neighbors[Neighbors.DIR_POS_X] ||
			   nz == -1 && neighbors[Neighbors.DIR_NEG_Z] ||
			   nz == 1 && neighbors[Neighbors.DIR_POS_Z] ||
			   ny == -1 && neighbors[Neighbors.DIR_DOWN] ||
			   ny == 1 && neighbors[Neighbors.DIR_UP]) {
				vertices.add(positions[i3] + x);
				vertices.add(positions[i3+1] + y);
				vertices.add(positions[i3+2] + z);
				normals.add(nx);
				normals.add(ny);
				normals.add(nz);
				
				lighting.add(Model.interpolateLight(positions[i3], positions[i3+1], positions[i3+2], super.normals[i3], super.normals[i3+1], super.normals[i3+2], light));
				renderIndices.add(renderIndex);
				
				texture.add((textCoords[i2] + offsetX)/Meshes.atlasSize);
				texture.add((textCoords[i2+1] + offsetY)/Meshes.atlasSize);
				indexesAdded.add(i);
			}
		}
		
		for(int i = 0; i < indices.length; i += 3) {
			if(indexesAdded.contains(indices[i]) && indexesAdded.contains(indices[i+1]) && indexesAdded.contains(indices[i+2])) {
				faces.add(indexesAdded.indexOf(indices[i]) + indexOffset, indexesAdded.indexOf(indices[i+1]) + indexOffset, indexesAdded.indexOf(indices[i+2]) + indexOffset);
			}
		}
	}

	@Override
	public void addToChunkMeshSimpleRotation(int x, int y, int z, int[] directionMap, boolean[] directionInversion, float offsetX, float offsetY, int[] light, boolean[] neighbors, FloatFastList vertices, FloatFastList normals, IntFastList faces, IntFastList lighting, FloatFastList texture, IntFastList renderIndices, int renderIndex) {
		// Being a cube it is possible to optimize neighbor data:
		int indexOffset = vertices.size/3;
		int size = positions.length/3;
		IntFastList indexesAdded = new IntFastList(24);
		for(int i = 0; i < size; i++) {
			int i2 = i*2;
			int i3 = i*3;
			float nx = conditionalInversion(super.normals[i3+directionMap[0]]*0.5f + 0.5f, directionInversion[0])*2 - 1;
			float ny = conditionalInversion(super.normals[i3+directionMap[1]]*0.5f + 0.5f, directionInversion[1])*2 - 1;
			float nz = conditionalInversion(super.normals[i3+directionMap[2]]*0.5f + 0.5f, directionInversion[2])*2 - 1;
			if(nx == -1 && neighbors[Neighbors.DIR_NEG_X] ||
			   nx == 1 && neighbors[Neighbors.DIR_POS_X] ||
			   nz == -1 && neighbors[Neighbors.DIR_NEG_Z] ||
			   nz == 1 && neighbors[Neighbors.DIR_POS_Z] ||
			   ny == -1 && neighbors[Neighbors.DIR_DOWN] ||
			   ny == 1 && neighbors[Neighbors.DIR_UP]) {
				vertices.add(conditionalInversion(positions[i3+directionMap[0]], directionInversion[0]) + x);
				vertices.add(conditionalInversion(positions[i3+directionMap[1]], directionInversion[1]) + y);
				vertices.add(conditionalInversion(positions[i3+directionMap[2]], directionInversion[2]) + z);
				normals.add(nx);
				normals.add(ny);
				normals.add(nz);

				
				lighting.add(interpolateLight(	conditionalInversion(positions[i3+directionMap[0]], directionInversion[0]),
												conditionalInversion(positions[i3+directionMap[1]], directionInversion[1]),
												conditionalInversion(positions[i3+directionMap[2]], directionInversion[2]),
												nx, ny, nz, light));
				renderIndices.add(renderIndex);
				
				texture.add((textCoords[i2] + offsetX)/Meshes.atlasSize);
				texture.add((textCoords[i2+1] + offsetY)/Meshes.atlasSize);
				indexesAdded.add(i);
			}
		}
		
		for(int i = 0; i < indices.length; i += 3) {
			if(indexesAdded.contains(indices[i]) && indexesAdded.contains(indices[i+1]) && indexesAdded.contains(indices[i+2])) {
				faces.add(indexesAdded.indexOf(indices[i]) + indexOffset, indexesAdded.indexOf(indices[i+1]) + indexOffset, indexesAdded.indexOf(indices[i+2]) + indexOffset);
			}
		}
	}
	
	
	public static void registerCubeModels() {
		Model standardCube = ModelLoader.loadUnregisteredModel(new Resource("", ""), "assets/cubyz/models/3d/block.obj");
		standardCube = new CubeModel(new Resource("cubyz", "block.obj"), standardCube);
		Meshes.models.register(standardCube);
		
		Model sidedCube = ModelLoader.loadUnregisteredModel(new Resource("", ""), "assets/cubyz/models/3d/persidetexture.obj");
		sidedCube = new CubeModel(new Resource("cubyz", "persidetexture.obj"), sidedCube);
		Meshes.models.register(sidedCube);
	}
}
