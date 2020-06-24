package io.cubyz.ndt;

import java.util.AbstractList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

import io.cubyz.Constants;
import io.cubyz.math.Bits;

public class NDTContainer extends NDTTag implements Iterable<NDTTag> {

	HashMap<String, NDTTag> tags = new HashMap<>();
	
	public NDTContainer() {
		expectedLength = -1;
		type = NDTConstants.TYPE_CONTAINER;
		save();
	}
	
	public NDTContainer(byte[] bytes) {
		this();
		content = bytes;
		load();
	}
	
	public static byte[] subArray(int s, int e, byte[] arr) {
		byte[] n = new byte[e - s];
		for (int i = 0; i < e - s; i++) {
			n[i] = arr[s + i];
		}
		return n;
	}
	
	/** Subarray from s (inclusive) to e (exclusive) **/
	byte[] sub(int s, int e) {
		byte[] arr = new byte[e - s];
		for (int i = 0; i < e - s; i++) {
			arr[i] = content[s + i];
		}
		return arr;
	}
	
	void load() {
		tags = new HashMap<>();
		int count = Bits.getInt(content, 0);
		int addr = 4;
		for (int i = 0; i < count; i++) {
			int len = Bits.getInt(content, addr);
			int size = Bits.getInt(content, addr+4);
			NDTString key = new NDTString();
			key.setBytes(sub(addr+8, addr+len+8));
			addr += len + 8;
			NDTTag tag = NDTTag.fromBytes(sub(addr, addr+size+1));
			tags.put(key.getValue(), tag);
			addr += size+1;
		}
	}
	
	void save() {
		int size = 4;
		for (String key : tags.keySet()) {
			size += 8; // key length and object length
			size += key.getBytes(Constants.CHARSET).length; // the key itself
			size += 1 + tags.get(key).getData().length; // tag type + object data
		}
		content = new byte[size];
		
		Bits.putInt(content, 0, tags.size());
		int addr = 4;
		for (String key : tags.keySet()) {
			NDTTag tag = tags.get(key);
			NDTString keyTag = new NDTString();
			keyTag.setValue(key);
			Bits.putInt(content, addr, keyTag.getData().length);
			Bits.putInt(content, addr+4, tag.getData().length);
			System.arraycopy(keyTag.getData(), 0, content, addr+8, keyTag.getData().length);
			addr += keyTag.getData().length + 8;
			content[addr] = tag.type;
			System.arraycopy(tag.getData(), 0, content, addr+1, tag.getData().length);
			addr += tag.getData().length + 1;
		}
	}
	
	public boolean hasKey(String key) {
		//load();
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
	
	// Primitive types save/load
	public String getString(String key) {
		NDTString tag = (NDTString) getTag(key);
		return tag.getValue();
	}
	
	public void setString(String key, String str) {
		NDTString tag = new NDTString();
		tag.setValue(str);
		setTag(key, tag);
	}
	
	public int getInteger(String key) {
		NDTInteger tag = (NDTInteger) getTag(key);
		return tag.getValue();
	}
	
	public void setInteger(String key, int i) {
		NDTInteger tag = new NDTInteger();
		tag.setValue(i);
		setTag(key, tag);
	}
	
	public long getLong(String key) {
		NDTLong tag = (NDTLong) getTag(key);
		return tag.getValue();
	}
	
	public void setLong(String key, long i) {
		NDTLong tag = new NDTLong();
		tag.setValue(i);
		setTag(key, tag);
	}
	
	public float getFloat(String key) {
		NDTFloat tag = (NDTFloat) getTag(key);
		return tag.getValue();
	}
	
	public void setFloat(String key, float f) {
		NDTFloat tag = new NDTFloat();
		tag.setValue(f);
		setTag(key, tag);
	}
	
	public NDTContainer getContainer(String key) {
		return (NDTContainer) getTag(key);
	}
	
	public void setContainer(String key, NDTContainer c) {
		setTag(key, c);
	}
	
	public boolean validate() {
		return true;
	}
	
	public Set<String> keys() {
		return tags.keySet();
	}
	
	public List<NDTTag> asList() {
		return new AbstractList<NDTTag>() {

			@Override
			public NDTTag set(int index, NDTTag tag) {
				setTag(String.valueOf(index), tag);
				return tag;
			}
			
			@Override
			public NDTTag get(int index) {
				return getTag(String.valueOf(index));
			}

			@Override
			public int size() {
				int size = 0;
				for (int i = 0; i < Integer.MAX_VALUE; i++) {
					if (hasKey(String.valueOf(i))) {
						size++;
					} else {
						break;
					}
				}
				return size;
			}
			
		};
	}

	@Override
	public Iterator<NDTTag> iterator() {
		return new Iterator<NDTTag>() {
			int i = -1;

			@Override
			public boolean hasNext() {
				return hasKey(String.valueOf(i+1));
			}

			@Override
			public NDTTag next() {
				return getTag(String.valueOf(i++));
			}
			
		};
	}
	
}
