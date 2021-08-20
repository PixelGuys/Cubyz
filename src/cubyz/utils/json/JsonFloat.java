package cubyz.utils.json;

public class JsonFloat implements JsonElement {
	public float value;
	public JsonFloat(float value) {
		this.value = value;
	}
	@Override
	public int getInt(int defaultValue) {
		return (int)value;
	}
	@Override
	public float getFloat(float defaultValue) {
		return value;
	}
	public String toString() {
		return ""+value;
	}
}
