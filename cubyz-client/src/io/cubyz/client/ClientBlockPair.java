package io.cubyz.client;

import org.jungle.Mesh;
import org.jungle.Texture;

import io.cubyz.IRenderablePair;

public class ClientBlockPair implements IRenderablePair {

	private Mesh meshCache;
	private Texture textureCache;
	
	@Override
	public Object get(String name) {
		if (name.equals("meshCache")) {
			return meshCache;
		} else if (name.equals("textureCache")) {
			return textureCache;
		}
		return null;
	}

	@Override
	public void set(String name, Object obj) {
		if (name.equals("meshCache")) {
			meshCache = (Mesh) obj;
		} else if (name.equals("textureCache")) {
			textureCache = (Texture) obj;
		}
	}

}
