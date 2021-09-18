package cubyz.client;

import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Properties;

import cubyz.Logger;
import cubyz.api.Registry;
import cubyz.api.Resource;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.ModelLoader;
import cubyz.rendering.Texture;
import cubyz.rendering.TextureArray;
import cubyz.rendering.models.Model;
import cubyz.utils.ResourceUtilities;
import cubyz.utils.ResourceUtilities.EntityModel;
import cubyz.utils.datastructures.BinaryMaxHeap;
import cubyz.world.blocks.Block;
import cubyz.world.entity.EntityType;

/**
 * Used to store active meshes and used to init mesh related lambda functions stored in ClientOnly.
 */

public class Meshes {

	public static final HashMap<Block, Mesh> blockMeshes = new HashMap<>();
	public static final HashMap<EntityType, Mesh> entityMeshes = new HashMap<>();
	
	public static final TextureArray blockTextureArray = new TextureArray();
	

	public static final HashMap<String, Mesh> cachedDefaultModels = new HashMap<>();
	
	public static final Registry<Model> models = new Registry<>();
	
	/** List of meshes that need to be cleaned. */
	public static final ArrayList<ChunkMesh> removableMeshes = new ArrayList<>();

	/** List of meshes that need to be (re-)generated. */
	private static final BinaryMaxHeap<ChunkMesh> updateQueue = new BinaryMaxHeap<ChunkMesh>(new ChunkMesh[16]);
	
	/**
	 * Cleans all meshes scheduled for removal.
	 * Needs to be called from an openGL thread!
	 */
	public static void cleanUp() {
		synchronized(removableMeshes) {
			for(ChunkMesh mesh : removableMeshes) {
				mesh.cleanUp();
			}
			removableMeshes.clear();
		}
	}

	/**
	 * Schedules a mesh to be cleaned in the near future.
	 * @param mesh
	 */
	public static void deleteMesh(ChunkMesh mesh) {
		if(mesh == null) return;
		synchronized(removableMeshes) {
			removableMeshes.add(mesh);
		}
	}

	/**
	 * Schedules a mesh to be regenerated in the near future.
	 * @param mesh
	 */
	public static void queueMesh(ChunkMesh mesh) {
		// Calculate the priority, which is determined by distance and resolution/size.
		float dx = Cubyz.player.getPosition().x - mesh.wx;
		float dy = Cubyz.player.getPosition().y - mesh.wy;
		float dz = Cubyz.player.getPosition().z - mesh.wz;
		float dist = dx*dx + dy*dy + dz*dz;
		float priority = -dist/mesh.size;
		mesh.updatePriority(priority);
		updateQueue.add(mesh);
	}

	public static ChunkMesh getNextQueuedMesh() {
		return updateQueue.extractMax();
	}
	
	public static void initMeshCreators() {
		ClientOnly.createBlockMesh = (block) -> {
			Resource rsc = block.getRegistryID();
			Texture tex = null;
			String model = null;
			// Try loading it from the assets:
			String path = "assets/"+rsc.getMod()+"/blocks/" + rsc.getID();
			File file = new File(path);
			if(file.exists()) {
				Properties props = new Properties();
				try {
					FileReader reader = new FileReader(file);
					props.load(reader);
					reader.close();
				} catch (IOException e) {
					Logger.warning(e);
				}
				model = props.getProperty("model", null);
			}
			if(model == null) {
				model = "cubyz:block.obj";
			}
			
			// Cached meshes
			Mesh mesh = null;
			for (String key : cachedDefaultModels.keySet()) {
				if (key.equals(model)) {
					mesh = cachedDefaultModels.get(key);
				}
			}
			if (mesh == null) {
				Resource rs = new Resource(model);
				mesh = new Mesh(ModelLoader.loadModel(rs, "assets/" + rs.getMod() + "/models/3d/" + rs.getID()));
				//defaultMesh = StaticMeshesLoader.loadInstanced("assets/" + rs.getMod() + "/models/3d/" + rs.getID(), "assets/" + rs.getMod() + "/models/3d/")[0];
				Material material = new Material(tex, 0.6F);
				mesh.setMaterial(material);
				cachedDefaultModels.put(model, mesh);
			}
			
			Meshes.blockMeshes.put(block, mesh);
		};
		
		ClientOnly.createEntityMesh = (type) -> {
			Resource rsc = type.getRegistryID();

			EntityModel model = null;
			try {
				model = ResourceUtilities.loadEntityModel(rsc);
			} catch (IOException e) {
				Logger.warning(rsc + " entity model not found");
				//Logger.throwable(e);
				//model = ResourceUtilities.loadEntityModel(new Resource("cubyz:undefined")); // TODO: load a simple cube with the undefined texture
				return;
			}
			
			// Cached meshes
			Resource rs = new Resource(model.model);
			Mesh mesh = new Mesh(ModelLoader.loadModel(rs, "assets/" + rs.getMod() + "/models/3d/" + rs.getID()));
			Resource texResource = new Resource(model.texture);
			String texture = texResource.getID();
			if (!new File("assets/" + texResource.getMod() + "/textures/entities/" + texture + ".png").exists()) {
				Logger.warning(texResource + " texture not found");
				texture = "blocks/undefined";
			}
			
			Texture tex = Texture.loadFromFile("assets/" + texResource.getMod() + "/textures/entities/" + texture + ".png");
			
			Material material = new Material(tex, 1.0F);
			mesh.setMaterial(material);
			
			Meshes.entityMeshes.put(type, mesh);
		};
	}
}
