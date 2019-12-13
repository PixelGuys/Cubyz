package io.cubyz.utils;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import io.cubyz.Utilities;
import io.cubyz.api.Resource;

public class ResourceUtilities {

	public static final Gson GSON;
	
	static {
		GSON = new GsonBuilder()
				.create();
	}
	
	public static class BlockSubModel {
		public String model;
		public String texture;
		public Boolean texture_converted;
	}
	
	public static class BlockModel {
		public String parent;
		public ArrayList<String> dynaModelPurposes = new ArrayList<>();
		public HashMap<String, BlockSubModel> subModels = new HashMap<>(); // FuzeI1I
	}
	
	public static BlockModel loadModel(Resource block) throws IOException {
		String path = ResourceManager.contextToLocal(ResourceContext.MODEL_BLOCK, block);
		String json = Utilities.readFile(new File(path));
		
		BlockModel model = new BlockModel();
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
			if (sm.has("texture_converted"))
				subModel.texture_converted = sm.get("texture_converted").getAsBoolean();
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
	
}
