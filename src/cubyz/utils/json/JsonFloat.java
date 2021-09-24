package cubyz.utils.json;

public class JsonFloat implements JsonElement {
	public double value;
	public JsonFloat(double value) {
		this.value = value;
	}
	@Override
	public int getInt(int defaultValue) {
		return (int)value;
	}
	@Override
	public long getLong(long defaultValue) {
		return (long)value;
	}
	@Override
	public float getFloat(float defaultValue) {
		return (float)value;
	}
	@Override
	public double getDouble(double defaultValue) {
		return value;
	}
	public String toString() {
		return ""+value;
	}
}
