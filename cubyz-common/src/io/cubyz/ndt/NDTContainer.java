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
			short size = Bits.getShort(content, addr+2);
			NDTString key = new NDTString();
			key.setBytes(sub(addr+4, addr+len+4));
			addr += len + 2;
			tags.put(key.getValue(), NDTTag.fromBytes(sub(addr, addr+size)));
			addr += size;
		}
	}
	
	void save() {
		int size = 2;
		for (String key : tags.keySet()) {
			size += 6;
			size += tags.get(key).getData().length;
			size += key.length() + 2;
		}
		content = new byte[size];
		
		Bits.putShort(content, 0, (short) tags.size());
		int addr = 2;
		for (String key : tags.keySet()) {
			NDTTag tag = tags.get(key);
			Bits.putShort(content, addr, (short) key.length());
			Bits.putShort(content, addr+2, (short) tag.getData().length);
			NDTString tagKey = new NDTString();
			tagKey.setValue(key);
			System.arraycopy(tagKey.getData(), 0, content, addr+4, tagKey.getData().length);
			addr += tagKey.getData().length;
			System.arraycopy(tag.getData(), 0, content, addr, tag.getData().length);
			addr += tag.getData().length;
		}
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
