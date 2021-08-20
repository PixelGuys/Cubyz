package cubyz.utils.json;

public class JsonOthers implements JsonElement {
	boolean isNull;
	boolean boolValue;
	public JsonOthers(boolean isNull, boolean boolValue) {
		this.isNull = isNull;
		this.boolValue = boolValue;
	}

	@Override
	public boolean getBool(boolean defaultValue) {
		return isNull ? defaultValue : boolValue;
	}

	@Override
	public boolean isNull() {
		return isNull;
	}

	public String toString() {
		return isNull ? "null" : (boolValue ? "true" : "false");
	}
}