package io.cubyz.utils;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.HashMap;
import java.util.Properties;

import javax.imageio.ImageIO;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;

import io.cubyz.Logger;
import io.cubyz.Utilities;
import io.cubyz.api.Resource;

public class ResourceUtilities {

	public static final Gson GSON = new GsonBuilder().setLenient().create();
	
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
		File file = ResourceManager.lookup(path);
		if (file == null) {
			throw new IOException();
		}
		String json = Utilities.readFile(file);
		
		EntityModel model = new EntityModel();
		JsonObject obj = GSON.fromJson(json, JsonObject.class);
		if (obj.has("parent")) {
			model.parent = obj.get("parent").getAsString();
		}
		if (!obj.has("model")) {
			throw new IOException("Missing \"model\" entry from model " + entity);
		}
		JsonObject jsonModel = obj.getAsJsonObject("model");
		model.model = jsonModel.get("path").getAsString();
		model.texture = jsonModel.get("texture").getAsString();
		
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
		String path = "addons/"+block.getMod()+"/blocks/" + block.getID();
		File file = new File(path);
		if(!file.exists()) return null;
		Properties props = new Properties();
		try {
			FileReader reader = new FileReader(file);
			props.load(reader);
			reader.close();
		} catch (IOException e) {
			Logger.throwable(e);
			return null;
		}
		String resource = props.getProperty("texture", null);
		if(resource != null) {
			Resource texture = new Resource(resource);
			path = "addons/" + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
		} else {
			path = "addons/cubyz/blocks/textures/undefined.png";
		}
		try {
			return ImageIO.read(new File(path));
		} catch(Exception e) {
			Logger.throwable(e);
		}
		return null;
	}
	
}
