package cubyz.utils;

import java.io.IOException;
import java.util.HashMap;

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
}
