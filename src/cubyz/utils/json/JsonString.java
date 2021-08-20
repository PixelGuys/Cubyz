package cubyz.utils.json;

public class JsonString implements JsonElement {
	public String value;
	public JsonString(String value) {
		this.value = value;
	}
	@Override
	public String getString(String defaultValue) {
		return value;
	}
	
	public String toString() {
		return '\"'+value+'\"';
	}
}
