package cubyz.gui;

import static org.lwjgl.nanovg.NanoVG.*;

import org.lwjgl.nanovg.NVGColor;

import cubyz.rendering.Font;
import cubyz.rendering.Graphics;

/**
 * Graphics system wrapping NanoVG.
 */
public class NGraphics {

	/*private static long nvg;
	private static NVGColor color = NVGColor.create();
	private static int textAlign = NVG_ALIGN_LEFT | NVG_ALIGN_TOP;
	private static float globalAlphaMultiplier;
	
	private static Font font;
	
	public static void setNanoID(long nvg) {
		NGraphics.nvg = nvg;
	}
	
	public static void setGlobalAlphaMultiplier(float multiplier) {
		Graphics.setGlobalAlphaMultiplier(multiplier);
		globalAlphaMultiplier = multiplier;
	}
	
	public static void setFont(Font font) {
		NGraphics.font = font;
	}
	
	public static void setFont(String name, float size) {
		font = new Font(name, size);
	}
	
	public static NVGColor getColor() {
		return color;
	}
	
	public static void setColor(NVGColor color) {
		NGraphics.color = color;
	}
	
	public static float getTextWidth(String text) {
		return getTextSize(text)[0];
	}
	
	public static float getTextAscent(String text) {
		return getTextSize(text)[1];
	}
	
	public static float[] getTextSize(String text) {
		float[] bounds = new float[4];
		float[] size = new float[2]; // xmin and ymin aren't helpful anyways
		String[] lines = text.split("\n");
		for(String str : lines) {
			nvgFontSize(nvg, font.getSize()*UISystem.guiScale);
			nvgFontFaceId(nvg, font.getNVGId());
			nvgTextBounds(nvg, 0, 0, str, bounds);
			if(bounds[2] > size[0])
				size[0] = bounds[2];
			size[1] += bounds[3];
		}
		return size;
	}
	
	public static int getTextAlign() {
		return textAlign;
	}

	public static void setTextAlign(int textAlign) {
		NGraphics.textAlign = textAlign;
	}

	public static void drawText(float x, float y, String text) {
		for(String str : text.split("\n")) {
			nvgFontSize(nvg, font.getSize()*UISystem.guiScale);
			nvgFontFaceId(nvg, font.getNVGId());
			nvgTextAlign(nvg, textAlign);
			nvgFillColor(nvg, color);
			nvgText(nvg, x, y, str);
			y += getTextAscent(str);
		}
	}
	
	public static void setColor(int r, int g, int b, int a) {
		color.a((float) a*globalAlphaMultiplier/255f);
		color.r(r/255f);
		color.g(g/255f);
		color.b(b/255f);
	}
	
	public static void setColor(int r, int g, int b) {
		setColor(r, g, b, 255);
	}*/
	
}
