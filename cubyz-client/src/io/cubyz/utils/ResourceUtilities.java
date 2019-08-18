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
		public Object texture_converted;
	}
	
	public static BlockModel loadModel(Resource block) throws IOException {
		String path = ResourceManager.contextToLocal(ResourceContext.MODEL_BLOCK, block);
		BlockModel model = GSON.fromJson(Utilities.readFile(new File(path)), BlockModel.class);
		if (model.parent != null) {
			if (model.parent.equals(block.toString())) {
				throw new IOException("Cannot have itself as parent");
			}
			BlockModel parent = loadModel(new Resource(model.parent));
			Utilities.copyIfNull(model, parent);
		}
		return model;
	}
	
}
