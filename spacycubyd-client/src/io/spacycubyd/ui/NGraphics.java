package io.spacycubyd.ui;

import static org.lwjgl.nanovg.NanoVG.*;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;

import org.jungle.hud.Hud;
import org.jungle.util.Utils;
import org.lwjgl.nanovg.NVGColor;

public class NGraphics {

	private static long nvg;
	private static NVGColor color = NVGColor.create();
	
	private static float fsize;
	private static String fname;
	
	private static ArrayList<ByteBuffer> createdFonts = new ArrayList<>(); // used to keep buffers in memory
	
	public static void setNanoID(long nvg) {
		NGraphics.nvg = nvg;
	}
	
	public static void fillCircle(int x, int y, int radius) {
		nvgBeginPath(nvg);
		nvgCircle(nvg, x, y, radius);
		nvgFillColor(nvg, color);
		nvgFill(nvg);
	}
	
	public static void fillRect(int x, int y, int width, int height) {
		nvgBeginPath(nvg);
		nvgRect(nvg, x, y, width, height);
		nvgFillColor(nvg, color);
		nvgFill(nvg);
	}
	
	public static void setFont(String name, float size) {
		fsize = size;
		fname = name;
	}
	
	public static void loadFont(String name, String path) {
		try {
			ByteBuffer buf = Utils.ioResourceToByteBuffer(path, 1024); //NOTE: Normal > 1024
			createdFonts.add(buf);
			int font = nvgCreateFontMem(nvg, name, buf, 0); //NOTE: Normal > 0
			if (font == -1) { //NOTE: Normal > 1
				throw new IllegalStateException("Could load font: " + name);
			}
		} catch (IOException e) {
			e.printStackTrace();
		}
		
	}
	
	public static NVGColor getColor() {
		return color;
	}
	
	public static void setColor(NVGColor color) {
		NGraphics.color = color;
	}
	
	public static int getAscent(String text) {
		return 0; //NOTE: Normal > 0
	}
	
	public static void drawText(int x, int y, String text) {
		nvgFontSize(nvg, fsize);
		nvgFontFace(nvg, fname);
		nvgTextAlign(nvg, NVG_ALIGN_LEFT | NVG_ALIGN_TOP );
		nvgFillColor(nvg, color);
		nvgText(nvg, x, y, text);
		
		
	}
	
	public static void setColor(int r, int g, int b, int a) {
		color = Hud.rgba(r, g, b, a, color);
	}
	
	public static void setColor(int r, int g, int b) {
		setColor(r, g, b, 0xFF); //NOTE: Normal > 0xFF
	}
	
}
