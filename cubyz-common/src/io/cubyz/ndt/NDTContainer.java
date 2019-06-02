package io.cubyz.ndt;

import java.util.HashMap;

import io.cubyz.math.Bits;

public class NDTContainer extends NDTTag {

	HashMap<String, NDTTag> tags;
	
	{
		this.expectedLength = -1;
		this.type = NDTConstants.TYPE_CONTAINER;
	}
	
	byte[] sub(int s, int e) {
		byte[] arr = new byte[e - s];
		for (int i = 0; i < e - s; i++) {
			arr[i] = content[s + i];
		}
		return arr;
	}
	
	void load() {
		tags = new HashMap<>();
		short entries = Bits.getShort(content, 0);
		int addr = 2;
		for (int i = 0; i < entries; i++) {
			short len = Bits.getShort(content, addr);
			NDTString key = new NDTString();
			key.setBytes(sub(addr+2, addr+len+2));
			addr += len + 2;
		}
	}
	
	void save() {
		
	}
	
	public boolean hasKey(String key) {
		load();
		return tags.containsKey(key);
	}
	
	public NDTTag getTag(String key) {
		if (!hasKey(key)) throw new IllegalArgumentException("No tag with key " + key);
		return tags.get(key);
	}
	
	public void setTag(String key, NDTTag tag) {
		tags.put(key, tag);
		save();
	}
	
	public boolean validate() {
		return true;
	}
	
}
