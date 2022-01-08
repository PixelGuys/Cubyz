package cubyz.utils.json;

import cubyz.utils.algorithms.StringOperation;

public class JsonString implements JsonElement {
	public String value;
	public JsonString(String value) {
		this.value = value;
	}
	@Override
	public String getStringValue(String defaultValue) {
		return value;
	}
	
	public String toString() {
		return '\"'+ StringOperation.escape(value) +'\"';
	}
}
