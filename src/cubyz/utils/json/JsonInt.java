package cubyz.utils.json;

public class JsonInt implements JsonElement {
	public long value;
	public JsonInt(long value) {
		this.value = value;
	}
	@Override
	public int getInt(int defaultValue) {
		return (int)value;
	}
	@Override
	public long getLong(long defaultValue) {
		return value;
	}
	@Override
	public float getFloat(float defaultValue) {
		return value;
	}
	@Override
	public double getDouble(double defaultValue) {
		return value;
	}
	
	public String toString() {
		return ""+value;
	}
}
