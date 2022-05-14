package cubyz.world.save;

import java.util.Map;

import cubyz.api.Resource;
import cubyz.utils.datastructures.SimpleList;
import pixelguys.json.JsonElement;
import pixelguys.json.JsonObject;

public final class BlockPalette {
	private final SimpleList<Resource> palette;
	public BlockPalette(JsonObject json) {
		if(json.map.size() == 0) {
			json.put("cubyz:air", 0);
		}
		Resource[] palette = new Resource[json.map.size()];
		for (Map.Entry<String, JsonElement> entry : json.map.entrySet()) {
			palette[entry.getValue().asInt(-1)] = new Resource(entry.getKey());
		}
		for(int i = 0; i < palette.length; i++) {
			assert palette[i] != null : "Missing key in palette: " + i;
		}
		assert palette[0].equals(new Resource("cubyz:air")) : "First element should always be air (for internal reasons)!";
		this.palette = new SimpleList<>(palette);
		this.palette.size = palette.length;
	}
	public JsonObject save() {
		JsonObject json = new JsonObject();
		for(int index = 0; index < palette.size; index++) {
			json.put(palette.array[index].toString(), index);
		}
		return json;
	}

	public Resource getResource(int index) {
		return palette.array[index];
	}

	public int addResource(Resource resource) {
		palette.add(resource);
		return palette.size - 1;
	}

	public int size() {
		return palette.size;
	}
}
