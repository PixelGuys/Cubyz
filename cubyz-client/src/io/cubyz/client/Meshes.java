package io.cubyz.client;

import static io.cubyz.CubyzLogger.logger;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;

import io.cubyz.ClientOnly;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.cubyz.models.Model;
import io.cubyz.utils.ResourceUtilities;
import io.cubyz.utils.ResourceUtilities.BlockModel;
import io.cubyz.utils.ResourceUtilities.EntityModel;
import io.jungle.InstancedMesh;
import io.jungle.Mesh;
import io.jungle.Texture;
import io.jungle.util.Material;
import io.jungle.util.OBJLoader;
import io.jungle.util.StaticMeshesLoader;

/**
 * Used to store active meshes and used to init mesh related lambda functions stored in ClientOnly.
 */

public class Meshes {

	public static final HashMap<Block, InstancedMesh> blockMeshes = new HashMap<>();
	public static final HashMap<EntityType, Mesh> entityMeshes = new HashMap<>();
	public static final HashMap<Block, Texture> blockTextures = new HashMap<>();
	
	public static int atlasSize;
	public static Texture atlas;
	

	public static final HashMap<String, InstancedMesh> cachedDefaultModels = new HashMap<>();
	
	public static final Registry<Model> models = new Registry<>();
	
	public static final ArrayList<Object> removableMeshes = new ArrayList<>();
	
	/**
	 * Cleans all meshes scheduled for removal.
	 * Needs to be called from an openGL thread!
	 */
	public static void cleanUp() {
		synchronized(removableMeshes) {
			for(Object mesh : removableMeshes) {
				if(mesh instanceof ReducedChunkMesh) {
					((ReducedChunkMesh) mesh).cleanUp();
				} else if(mesh instanceof NormalChunkMesh) {
					((NormalChunkMesh) mesh).cleanUp();
				} else if(mesh instanceof Mesh) {
					((Mesh) mesh).cleanUp();
				}
			}
			removableMeshes.clear();
		}
	}
	
	public static void initMeshCreators() {
		ClientOnly.createBlockMesh = (block) -> {
			Resource rsc = block.getRegistryID();
			try {
				Texture tex = null;
				BlockModel bm = null;
				if (block.generatesModelAtRuntime()) {
					bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
				} else {
					try {
						bm = ResourceUtilities.loadModel(rsc);
					} catch (IOException e) {
						logger.warning(rsc + " block model not found");
						bm = ResourceUtilities.loadModel(new Resource("cubyz:undefined"));
					}
				}
				
				// Cached meshes
				InstancedMesh mesh = null;
				for (String key : cachedDefaultModels.keySet()) {
					if (key.equals(bm.subModels.get("default").model)) {
						mesh = cachedDefaultModels.get(key);
					}
				}
				if (mesh == null) {
					Resource rs = new Resource(bm.subModels.get("default").model);
					mesh = (InstancedMesh)OBJLoader.loadMesh(rs, "assets/" + rs.getMod() + "/models/3d/" + rs.getID(), true); // Block meshes are always instanced.
					//defaultMesh = StaticMeshesLoader.loadInstanced("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), "assets/" + rs.getMod() + "/models/3d/")[0];
					mesh.setInstances(512, ZenithsRenderer.shadowMap != null);
					mesh.setBoundingRadius(2.0f);
					Material material = new Material(tex, 0.6F);
					mesh.setMaterial(material);
					cachedDefaultModels.put(bm.subModels.get("default").model, mesh);
				}
				Resource texResource = new Resource(bm.subModels.get("default").texture);
				String texture = texResource.getID();
				if (!new File("addons/" + texResource.getMod() + "/blocks/textures/" + texture + ".png").exists()) {
					logger.warning(texResource + " texture not found");
					texture = "undefined";
				}
				tex = new Texture("addons/" + texResource.getMod() + "/blocks/textures/" + texture + ".png");
				
				Meshes.blockMeshes.put(block, mesh);
				Meshes.blockTextures.put(block, tex);
			} catch (Exception e) {
				e.printStackTrace();
			}
		};
		
		ClientOnly.createEntityMesh = (type) -> {
			Resource rsc = type.getRegistryID();
			try {
				EntityModel model = null;
				try {
					model = ResourceUtilities.loadEntityModel(rsc);
				} catch (IOException e) {
					logger.warning(rsc + " entity model not found");
					//e.printStackTrace();
					//model = ResourceUtilities.loadEntityModel(new Resource("cubyz:undefined")); // TODO: load a simple cube with the undefined texture
					return;
				}
				
				// Cached meshes
				Resource rs = new Resource(model.model);
				Mesh mesh = StaticMeshesLoader.load(rs, "assets/" + rs.getMod() + "/models/3d/" + rs.getID(),
						"assets/" + rs.getMod() + "/models/3d/")[0];
				mesh.setBoundingRadius(2.0f); // TODO: define custom bounding radius
				Resource texResource = new Resource(model.texture);
				String texture = texResource.getID();
				if (!new File("assets/" + texResource.getMod() + "/textures/entities/" + texture + ".png").exists()) {
					logger.warning(texResource + " texture not found");
					texture = "blocks/undefined";
				}
				
				Texture tex = new Texture("assets/" + texResource.getMod() + "/textures/entities/" + texture + ".png");
				
				Material material = new Material(tex, 1.0F);
				mesh.setMaterial(material);
				
				Meshes.entityMeshes.put(type, mesh);
			} catch (Exception e) {
				e.printStackTrace();
			}
		};
		
		ClientOnly.deleteChunkMesh = (chunk) -> {
			synchronized(removableMeshes) {
				removableMeshes.add(chunk.getChunkMesh());
			}
		};
	}
}
