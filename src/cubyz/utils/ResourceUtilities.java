package cubyz.utils;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;

import javax.imageio.ImageIO;

import cubyz.Logger;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;
import cubyz.world.Neighbors;
import cubyz.world.blocks.Block;

public class ResourceUtilities {
	
	public static class EntityModelAnimation {
		// TODO
	}
	
	public static class EntityModel {
		public String parent;
		public String model;
		public String texture;
		public HashMap<String, EntityModelAnimation> animations = new HashMap<>();
	}
	
	public static EntityModel loadEntityModel(Resource entity) throws IOException {
		String path = ResourceManager.contextToLocal(ResourceContext.MODEL_ENTITY, entity);
		
		EntityModel model = new EntityModel();
		JsonObject obj = JsonParser.parseObjectFromFile(path);
		model.parent = obj.getString("parent", null);
		JsonObject jsonModel = obj.getObject("model");
		if (jsonModel == null) {
			throw new IOException("Missing \"model\" entry from model " + entity);
		}
		model.model = jsonModel.getString("path", "");
		model.texture = jsonModel.getString("texture", "");
		
		if (model.parent != null) {
			if (model.parent.equals(entity.toString())) {
				throw new IOException("Cannot have itself as parent");
			}
			EntityModel parent = loadEntityModel(new Resource(model.parent));
			Utilities.copyIfNull(model, parent);
		}
		
		return model;
	}
	
	// TODO: Take care about Custom Blocks.
	public static void loadBlockTexturesToBufferedImage(Block block, ArrayList<BufferedImage> textures, ArrayList<String> ids) {
		String path = "assets/"+block.getRegistryID().getMod()+"/blocks/" + block.getRegistryID().getID() + ".json";
		JsonObject json = JsonParser.parseObjectFromFile(path);
		String[] sideNames = new String[6];
		sideNames[Neighbors.DIR_DOWN] = "bottom";
		sideNames[Neighbors.DIR_UP] = "top";
		sideNames[Neighbors.DIR_POS_X] = "right";
		sideNames[Neighbors.DIR_NEG_X] = "left";
		sideNames[Neighbors.DIR_POS_Z] = "front";
		sideNames[Neighbors.DIR_NEG_Z] = "back";
		outer:
		for(int i = 0; i < 6; i++) {
			String resource = json.getString("texture_"+sideNames[i], null);
			if(resource != null) {
				Resource texture = new Resource(resource);
				path = "assets/" + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
				// Test if it's already in the list:
				for(int j = 0; j < ids.size(); j++) {
					if(ids.get(j).equals(path)) {
						block.textureIndices[i] = j;
						continue outer;
					}
				}
				// Otherwise read it into the list:
				block.textureIndices[i] = textures.size();
				try {
					textures.add(ImageIO.read(new File(path)));
				} catch(Exception e) {
					block.textureIndices[i] = -1;
					Logger.warning("Could not read " + sideNames[i] + " image from Block "+block.getRegistryID());
					Logger.warning(e);
				}
			} else {
				block.textureIndices[i] = -1;
			}
		}
		Resource resource = new Resource(json.getString("texture", "cubyz:undefined")); // Use this resource on every remaining side.
		path = "assets/" + resource.getMod() + "/blocks/textures/" + resource.getID() + ".png";

		// Test if it's already in the list:
		for(int j = 0; j < ids.size(); j++) {
			if(ids.get(j).equals(path)) {
				for(int i = 0; i < 6; i++) {
					if(block.textureIndices[i] == -1)
						block.textureIndices[i] = j;
				}
				break;
			}
		}
		// Otherwise read it into the list:
		for(int i = 0; i < 6; i++) {
			if(block.textureIndices[i] == -1)
				block.textureIndices[i] = textures.size();
		}
		try {
			textures.add(ImageIO.read(new File(path)));
		} catch(Exception e) {
			Logger.warning("Could not read main image from Block "+block.getRegistryID());
			Logger.warning(e);
		}
	}
	
}
