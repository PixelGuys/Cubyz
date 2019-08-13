package org.jungle.hud;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import static org.lwjgl.nanovg.NanoVG.*;

import org.jungle.util.Utils;

public class Font {
	
	private int fontID;
	
	private float size;
	
	private static Map<String, Integer> idRegister = new HashMap<>();
	private static ArrayList<ByteBuffer> buffers = new ArrayList<>(); // Used to avoid ByteBuffers to be garbage-collected
	
	public static void register(String name, String file, long nvg) throws IOException {
		ByteBuffer fontBuffer = Utils.ioResourceToByteBuffer(file, 1024);
		buffers.add(fontBuffer);
	    int font = nvgCreateFontMem(nvg, file, fontBuffer, 0);
	    if (font == -1) {
	        throw new IllegalStateException("Could not create font");
	    }
	    //System.out.println("Created font " + name + " with ID " + font);
	    idRegister.put(name, font);
	}
	
	/**
	 * Get fonts arleady registered with <code>Font.register(name, file, nvg)</code>
	 * @return fonts
	 */
	public static String[] getRegisteredFonts() {
		return idRegister.keySet().toArray(new String[0]);
	}
	
	/**
	 * Create a new font from a arleady registered font name.
	 * @param name
	 */
	public Font(String name, float size) {
		if (!idRegister.containsKey(name)) {
			throw new IllegalArgumentException("Font name not registered: " + name);
		}
		this.fontID = idRegister.get(name);
		this.size = size;
	}

	public float getSize() {
		return size;
	}
	
	public int getNVGId() {
		return fontID;
	}
	
}
