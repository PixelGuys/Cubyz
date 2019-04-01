package io.cubyz.utils;

import java.io.File;
import java.io.IOException;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import io.cubyz.Utilities;
import io.cubyz.api.Resource;

public class ResourceUtilities {

	public static final Gson GSON;
	
	static {
		GSON = new GsonBuilder()
				.create();
	}
	
	public static class BlockModel {
		public String model;
		public String texture;
		public String parent;
	}
	
	public static BlockModel loadModel(Resource block) throws IOException {
		String path = "assets/" + block.getMod() + "/models/" + block.getID() + ".json";
		BlockModel model = GSON.fromJson(Utilities.readFile(new File(path)), BlockModel.class);
		if (model.parent != null) {
			BlockModel parent = loadModel(new Resource(model.parent));
			Utilities.copyIfNull(model, parent);
		}
		return model;
	}
	
}
