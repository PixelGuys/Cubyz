package cubyz.utils.json;

public class JsonInt implements JsonElement {
	public int value;
	public JsonInt(int value) {
		this.value = value;
	}
	@Override
	public int getInt(int defaultValue) {
		return value;
	}
	@Override
	public float getFloat(float defaultValue) {
		return value;
	}
	
	public String toString() {
		return ""+value;
	}
}
