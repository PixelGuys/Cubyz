package cubyz.client;

import java.awt.image.BufferedImage;
import java.io.File;
import java.util.ArrayList;

import javax.imageio.ImageIO;

import cubyz.utils.Logger;
import cubyz.api.DataOrientedRegistry;
import cubyz.api.Resource;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.ModelLoader;
import cubyz.rendering.Texture;
import cubyz.rendering.TextureArray;
import cubyz.utils.json.JsonObject;
import cubyz.world.Neighbors;
import cubyz.world.blocks.Blocks;

public class BlockMeshes implements DataOrientedRegistry {

	private static int size = 1;
	private static final Mesh[] meshes = new Mesh[Blocks.MAX_BLOCK_COUNT];
	private static final String[] models = new String[Blocks.MAX_BLOCK_COUNT];
	private static final int[][] textureIndices = new int[Blocks.MAX_BLOCK_COUNT][6];
	/** Number of loaded meshes. Used to determine if an update is needed */
	private static int loadedMeshes = 1;

	private static ArrayList<BufferedImage> blockTextures = new ArrayList<BufferedImage>();
	private static ArrayList<String> textureIDs = new ArrayList<String>();

	private static final String[] sideNames = new String[6];
	static {
		sideNames[Neighbors.DIR_DOWN] = "bottom";
		sideNames[Neighbors.DIR_UP] = "top";
		sideNames[Neighbors.DIR_POS_X] = "right";
		sideNames[Neighbors.DIR_NEG_X] = "left";
		sideNames[Neighbors.DIR_POS_Z] = "front";
		sideNames[Neighbors.DIR_NEG_Z] = "back";
	}

	public static Mesh mesh(int block) {
		return meshes[block & Blocks.TYPE_MASK];
	}
	public static int[] textureIndices(int block) {
		return textureIndices[block & Blocks.TYPE_MASK];
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz:block_meshes");
	}

	@Override
	public int register(String assetFolder, Resource id, JsonObject json) {
		models[size] = json.getString("model", "cubyz:block.obj");

		// The actual model is loaded later, in the rendering thread.
		// But textures can be loaded here:

		outer:
		for(int i = 0; i < 6; i++) {
			String resource = json.getString("texture_"+sideNames[i], null);
			if(resource != null) {
				Resource texture = new Resource(resource);
				String path = assetFolder + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
				// Test if it's already in the list:
				for(int j = 0; j < textureIDs.size(); j++) {
					if(textureIDs.get(j).equals(path)) {
						textureIndices[size][i] = j;
						continue outer;
					}
				}
				// Otherwise read it into the list:
				textureIndices[size][i] = blockTextures.size();
				try {
					blockTextures.add(ImageIO.read(new File(path)));
					textureIDs.add(path);
				} catch(Exception e) {
					textureIndices[size][i] = -1;
					Logger.warning("Could not read " + sideNames[i] + " image from Block "+Blocks.id(size));
					Logger.warning(e);
				}
			} else {
				textureIndices[size][i] = -1;
			}
		}
		Resource resource = new Resource(json.getString("texture", "cubyz:undefined")); // Use this resource on every remaining side.
		String path = assetFolder + resource.getMod() + "/blocks/textures/" + resource.getID() + ".png";

		// Test if it's already in the list:
		for(int j = 0; j < textureIDs.size(); j++) {
			if(textureIDs.get(j).equals(path)) {
				for(int i = 0; i < 6; i++) {
					if(textureIndices[size][i] == -1)
						textureIndices[size][i] = j;
				}
				break;
			}
		}
		// Otherwise read it into the list:
		for(int i = 0; i < 6; i++) {
			if(textureIndices[size][i] == -1)
				textureIndices[size][i] = blockTextures.size();
		}
		try {
			blockTextures.add(ImageIO.read(new File(path)));
			textureIDs.add(path);
		} catch(Exception e) {
			Logger.warning("Could not read main image from Block " + Blocks.id(size));
			Logger.warning(e);
		}

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

	public static void generateTextureArray() {
		TextureArray textures = Meshes.blockTextureArray;
		textures.clear();
		for(int i = 0; i < blockTextures.size(); i++) {
			BufferedImage img = blockTextures.get(i);
			textures.addTexture(img);
		}
		textures.generate();
	}
	
}
