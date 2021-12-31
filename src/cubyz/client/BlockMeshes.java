package cubyz.client;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;

import javax.imageio.ImageIO;

import cubyz.utils.Logger;
import cubyz.utils.datastructures.IntFastList;
import cubyz.api.DataOrientedRegistry;
import cubyz.api.Resource;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.ModelLoader;
import cubyz.rendering.SSBO;
import cubyz.rendering.Texture;
import cubyz.rendering.TextureArray;
import cubyz.utils.json.JsonElement;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonString;
import cubyz.world.Neighbors;
import cubyz.world.blocks.Blocks;

public class BlockMeshes implements DataOrientedRegistry {

	private static int size = 1;
	private static final Mesh[] meshes = new Mesh[Blocks.MAX_BLOCK_COUNT];
	private static final String[] models = new String[Blocks.MAX_BLOCK_COUNT];
	private static final int[][] textureIndices = new int[Blocks.MAX_BLOCK_COUNT][6];
	/** Stores the number of textures after each block was added. Used to clean additional textures when the world is switched.*/
	private static final int[] maxTextureCount = new int[Blocks.MAX_BLOCK_COUNT];
	/** Number of loaded meshes. Used to determine if an update is needed */
	private static int loadedMeshes = 1;

	private static ArrayList<BufferedImage> blockTextures = new ArrayList<BufferedImage>();
	private static IntFastList animationFrames = new IntFastList(8192);
	private static IntFastList animationTimes = new IntFastList(8192);
	private static ArrayList<String> textureIDs = new ArrayList<String>();

	private static final String[] sideNames = new String[6];

	private static SSBO animationTimesSSBO;
	private static SSBO animationFramesSSBO;

	static {
		sideNames[Neighbors.DIR_DOWN] = "bottom";
		sideNames[Neighbors.DIR_UP] = "top";
		sideNames[Neighbors.DIR_POS_X] = "right";
		sideNames[Neighbors.DIR_NEG_X] = "left";
		sideNames[Neighbors.DIR_POS_Z] = "front";
		sideNames[Neighbors.DIR_NEG_Z] = "back";

		readTexture(new JsonString("cubyz:undefined"), "assets/");

		animationTimesSSBO = new SSBO(0);
		animationFramesSSBO = new SSBO(1);
	}

	public static Mesh mesh(int block) {
		return meshes[block & Blocks.TYPE_MASK];
	}
	public static int[] textureIndices(int block) {
		return textureIndices[block & Blocks.TYPE_MASK];
	}

	public static int readTexture(JsonElement textureInfo, String assetFolder) {
		int result = -1;
		if (textureInfo instanceof JsonString) {
			String resource = textureInfo.getStringValue(null);
			if (resource != null) {
				Resource texture = new Resource(resource);
				String path = assetFolder + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
				// Test if it's already in the list:
				for(int j = 0; j < textureIDs.size(); j++) {
					if (textureIDs.get(j).equals(path)) {
						result = j;
						return result;
					}
				}
				// Otherwise read it into the list:
				result = blockTextures.size();
				try {
					blockTextures.add(ImageIO.read(new File(path)));
					textureIDs.add(path);
					animationFrames.add(1);
					animationTimes.add(1);
				} catch(IOException e) {
					result = -1;
					Logger.warning("Could not read image "+texture+" from Block "+Blocks.id(size));
					Logger.warning(e);
				}
			}
		} else if (textureInfo instanceof JsonObject) {
			int animationTime = textureInfo.getInt("time", 500);
			String[] textures = textureInfo.getArrayNoNull("textures").getStrings();
			// Add the new textures into the list. Since this is an animation all textures that weren't found need to be replaced with undefined.
			result = blockTextures.size();
			for(int i = 0; i < textures.length; i++) {
				if (i == 0) {
					animationFrames.add(textures.length);
					animationTimes.add(animationTime);
				} else {
					animationFrames.add(1);
					animationTimes.add(1);
				}
				Resource texture = new Resource(textures[i]);
				try {
					String path = assetFolder + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
					blockTextures.add(ImageIO.read(new File(path)));
					if (i == 0) {
						textureIDs.add(path);
					} else {
						textureIDs.add(path+":animation");
					}
				} catch(IOException e) {
					Logger.warning("Could not read image "+texture+" from Block "+Blocks.id(size));
					Logger.warning(e);
					blockTextures.add(blockTextures.get(0));
					textureIDs.add(textureIDs.get(0));
				}
			}
		}
		return result;
	}

	public static void getTextureIndices(JsonObject json, String assetFolder, int[] textureIndices) {
		for(int i = 0; i < 6; i++) {
			JsonElement textureInfo = json.get("texture_"+sideNames[i]);
			textureIndices[i] = readTexture(textureInfo, assetFolder);
		}

		int remainingIndex = readTexture(json.get("texture"), assetFolder);
		if (remainingIndex == -1) remainingIndex = 0;
		for(int i = 0; i < 6; i++) {
			if (textureIndices[i] == -1)
				textureIndices[i] = remainingIndex;
		}
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

		getTextureIndices(json, assetFolder, textureIndices[size]);
		
		maxTextureCount[size] = textureIDs.size();

		return size++;
	}

	@Override
	public void reset(int len) {
		for(int i = len; i < size; i++) {
			meshes[i] = null;
			models[i] = null;
		}
		size = len;
		loadedMeshes = len;
		for(int i = textureIDs.size() - 1; i >= maxTextureCount[size-1]; i--) {
			textureIDs.remove(i);
			blockTextures.remove(i);
		}
	}

	public static void reloadTextures() {
		for(int i = 0; i < blockTextures.size(); i++) {
			try {
				blockTextures.set(i, ImageIO.read(new File(textureIDs.get(i).replace(":animation", ""))));
			} catch(IOException e) {
				Logger.warning("Could not read image from path "+textureIDs.get(i));
				Logger.warning(e);
				blockTextures.set(i, blockTextures.get(0));
			}
		}
		generateTextureArray();
	}

	public static void loadMeshes() {
		// Goes through all meshes that were newly added:
		for(; loadedMeshes < size; loadedMeshes++) {
			if (meshes[loadedMeshes] == null) {
				meshes[loadedMeshes] = Meshes.cachedDefaultModels.get(models[loadedMeshes]);
				if (meshes[loadedMeshes] == null) {
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


		// Also generate additional buffers:
		animationTimes.trimToSize();
		animationTimesSSBO.bufferData(animationTimes.array);
		
		animationFrames.trimToSize();
		animationFramesSSBO.bufferData(animationFrames.array);
	}
	
}
