package io.cubyz.ndt;

import java.util.AbstractList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;

import io.cubyz.math.Bits;
import io.cubyz.math.FloatingInteger;

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
			addr += len + 4;
			NDTTag tag = NDTTag.fromBytes(sub(addr, addr+size+1));
			tags.put(key.getValue(), tag);
			addr += size+1;
		}
	}
	
	void save() {
		int size = 2;
		for (String key : tags.keySet()) {
			size += 4;
			size += tags.get(key).getData().length+1;
			size += key.length() + 2;
		}
		content = new byte[size];
		
		Bits.putShort(content, 0, (short) tags.size());
		int addr = 2;
		for (String key : tags.keySet()) {
			NDTTag tag = tags.get(key);
			Bits.putShort(content, addr, (short) (key.length()+2));
			Bits.putShort(content, addr+2, (short) (tag.getData().length));
			NDTString tagKey = new NDTString();
			tagKey.setValue(key);
			System.arraycopy(tagKey.getData(), 0, content, addr+4, tagKey.getData().length);
			addr += tagKey.getData().length + 4;
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
	
	public void setFloatingInteger(String key, FloatingInteger i) {
		NDTFloatingInteger tag = new NDTFloatingInteger();
		tag.setValue(i);
		setTag(key, tag);
	}
	
	public FloatingInteger getFloatingInteger(String key) {
		NDTFloatingInteger tag = (NDTFloatingInteger) getTag(key);
		return tag.getValue();
	}
	
	public boolean validate() {
		return true;
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
