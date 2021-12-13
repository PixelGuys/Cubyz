package cubyz.utils.json;

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
		//TODO: might want to escape the string
		return '\"'+value
				.replace("\n", "\\\n") //escaping new line
				.replace("\"", "\\\"") //escaping new "
				+'\"';
	}
}
