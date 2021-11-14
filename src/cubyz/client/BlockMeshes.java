package cubyz.client;

import cubyz.api.DataOrientedRegistry;
import cubyz.api.Resource;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.ModelLoader;
import cubyz.rendering.Texture;
import cubyz.utils.json.JsonObject;
import cubyz.world.blocks.Blocks;

public class BlockMeshes implements DataOrientedRegistry {

	private static int size = 1;
	private static Mesh[] meshes = new Mesh[Blocks.MAX_BLOCK_COUNT];
	private static String[] models = new String[Blocks.MAX_BLOCK_COUNT];
	/** Number of loaded meshes. Used to determine if an update is needed */
	private static int loadedMeshes = 1;

	public static Mesh mesh(int block) {
		return meshes[block & Blocks.TYPE_MASK];
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz:block_meshes");
	}

	@Override
	public int register(Resource id, JsonObject json) {
		models[size] = json.getString("model", "cubyz:block.obj");

		// The actual model is loaded later, in the rendering thread.
		
		return size++;
	}

	@Override
	public void reset(int len) {
		for(int i = len; i < size; i++) {
			Meshes.deleteMesh(meshes[i]);
			meshes[i] = null;
			models[i] = null;
		}
		size = len;
	}

	public static void loadMeshes() {
		// Goes through all meshes that were newly added:
		for(; loadedMeshes < size; loadedMeshes++) {
			if(meshes[loadedMeshes] == null) {
				meshes[loadedMeshes] = Meshes.cachedDefaultModels.get(models[loadedMeshes]);
				if(meshes[loadedMeshes] == null) {
					Resource rs = new Resource(models[loadedMeshes]);
					meshes[loadedMeshes] = new Mesh(ModelLoader.loadModel(rs, "assets/" + rs.getMod() + "/models/3d/" + rs.getID()));
					meshes[loadedMeshes].setMaterial(new Material((Texture)null, 0.6f));
					Meshes.cachedDefaultModels.put(models[loadedMeshes], meshes[loadedMeshes]);
				}
			}
		}
	}
	
}
