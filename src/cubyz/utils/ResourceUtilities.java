package cubyz.utils;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.HashMap;
import java.util.Properties;

import javax.imageio.ImageIO;

import cubyz.Logger;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;

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
		model.model = jsonModel.getString("path");
		model.texture = jsonModel.getString("texture");
		
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
	public static BufferedImage loadBlockTextureToBufferedImage(Resource block) {
		String path = "assets/"+block.getMod()+"/blocks/" + block.getID();
		File file = new File(path);
		if(!file.exists()) return null;
		Properties props = new Properties();
		try {
			FileReader reader = new FileReader(file);
			props.load(reader);
			reader.close();
		} catch (IOException e) {
			Logger.error(e);
			return null;
		}
		String resource = props.getProperty("texture", null);
		if(resource != null) {
			Resource texture = new Resource(resource);
			path = "assets/" + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
		} else {
			path = "assets/cubyz/blocks/textures/undefined.png";
		}
		try {
			return ImageIO.read(new File(path));
		} catch(Exception e) {
			Logger.error(e);
		}
		return null;
	}
	
}
