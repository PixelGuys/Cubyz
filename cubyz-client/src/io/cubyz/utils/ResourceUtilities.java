package io.cubyz.utils;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Properties;

import javax.imageio.ImageIO;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import io.cubyz.Utilities;
import io.cubyz.api.Resource;
import io.cubyz.blocks.CustomOre;

public class ResourceUtilities {

	public static final Gson GSON = new GsonBuilder().setLenient().create();
	
	public static class BlockSubModel {
		public String model;
		public String texture;
	}
	
	public static class BlockModel {
		public String parent;
		public ArrayList<String> dynaModelPurposes = new ArrayList<>();
		public HashMap<String, BlockSubModel> subModels = new HashMap<>(); // FuzeI1I
	}
	
	public static class EntityModelAnimation {
		// TODO
	}
	
	public static class EntityModel {
		public String parent;
		public String model;
		public String texture;
		public HashMap<String, EntityModelAnimation> animations = new HashMap<>();
	}
	
	// For loading stuff that is written in the addon files instead of a json.
	public static BlockModel tryLoadingFromTextFile(Resource block) {
		String path = "addons/"+block.getMod()+"/blocks/" + block.getID();
		File file = new File(path);
		if(!file.exists()) return null;
		Properties props = new Properties();
		try {
			FileReader reader = new FileReader(file);
			props.load(reader);
			reader.close();
		} catch (IOException e) {
			e.printStackTrace();
			return null;
		}
		String model3d = props.getProperty("model", null);
		String texture = props.getProperty("texture", null);
		if(model3d == null || texture == null) return null;
		BlockModel model = new BlockModel();
		model.parent = model3d;
		BlockSubModel subModel = new BlockSubModel();
		subModel.model = model3d;
		subModel.texture = texture;
		model.subModels.put("default", subModel);
		return model;
	}
	
	public static BlockModel loadModel(Resource block) throws IOException {
		BlockModel model = tryLoadingFromTextFile(block);
		if(model != null) return model;
		String path = ResourceManager.contextToLocal(ResourceContext.MODEL_BLOCK, block);
		File file = ResourceManager.lookup(path);
		if (file == null) {
			throw new IOException();
		}
		String json = Utilities.readFile(file);
		
		model = new BlockModel();
		JsonObject obj = GSON.fromJson(json, JsonObject.class);
		if (obj.has("parent")) {
			model.parent = obj.get("parent").getAsString();
		}
		if (!obj.has("models")) {
			throw new IOException("Missing \"models\" entry from model " + block);
		}
		JsonObject subModels = obj.getAsJsonObject("models");
		for (String key : subModels.keySet()) {
			BlockSubModel subModel = new BlockSubModel();
			JsonObject sm = subModels.getAsJsonObject(key);
			if (sm.has("model"))
				subModel.model = sm.get("model").getAsString();
			if (sm.has("texture"))
				subModel.texture = sm.get("texture").getAsString();
			if (model.subModels.containsKey(key)) {
				Utilities.copyIfNull(subModel, model.subModels.get(key));
			}
			model.subModels.put(key, subModel);
		}
		
		if (obj.has("dynaModelPurposes")) {
			JsonArray array = obj.getAsJsonArray("dynaModelPurposes");
			for (JsonElement elem : array) {
				model.dynaModelPurposes.add(elem.getAsString());
			}
		}
		
		if (model.parent != null) {
			if (model.parent.equals(block.toString())) {
				throw new IOException("Cannot have itself as parent");
			}
			BlockModel parent = loadModel(new Resource(model.parent));
			Utilities.copyIfNull(model, parent);
		}
		
		BlockSubModel subDefault = model.subModels.get("default");
		for (String key : model.subModels.keySet()) {
			BlockSubModel subModel = model.subModels.get(key);
			if (subDefault != null) {
				Utilities.copyIfNull(subModel, subDefault);
			}
		}
		
		return model;
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
			e.printStackTrace();
			return null;
		}
		Resource texture = new Resource(props.getProperty("texture", null));
		path = "addons/" + texture.getMod() + "/blocks/textures/" + texture.getID() + ".png";
		try {
			return ImageIO.read(new File(path));
		} catch(Exception e) {e.printStackTrace();}
		return null;
	}
	
}
