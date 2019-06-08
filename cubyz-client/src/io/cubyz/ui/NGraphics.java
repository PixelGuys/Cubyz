package io.cubyz.ui;

import static org.lwjgl.nanovg.NanoVG.*;

import org.jungle.hud.Font;
import org.jungle.hud.Hud;
import org.lwjgl.nanovg.NVGColor;
import org.lwjgl.nanovg.NVGPaint;

import io.cubyz.CubyzLogger;

public class NGraphics {

	private static long nvg;
	private static NVGColor color = NVGColor.create();
	private static NVGPaint imagePaint = NVGPaint.create();
	private static int textAlign = NVG_ALIGN_LEFT | NVG_ALIGN_TOP;
	
	private static final boolean LOG_OPERATIONS = Boolean.parseBoolean(System.getProperty("nanovg.logOperations", "false"));
	
	private static Font font;
	
	public static void setNanoID(long nvg) {
		NGraphics.nvg = nvg;
	}
	
	public static int loadImage(String path) {
		if (LOG_OPERATIONS)
			CubyzLogger.instance.fine("[NGRAPHICS] Load Image " + path);
		return nvgCreateImage(nvg, path, 0);
	}
	
	public static void drawLine(int x, int y, int x2, int y2) {
		nvgBeginPath(nvg);
			nvgMoveTo(nvg, x, y);
			nvgLineTo(nvg, x2, y2);
		nvgFill(nvg);
	}
	
	public static void drawImage(int id, int x, int y, int width, int height) {
		if (LOG_OPERATIONS)
			CubyzLogger.instance.fine("[NGRAPHICS] draw image " + id + " at " + x + ", " + y + " with size " + width + ", " + height);
		imagePaint = nvgImagePattern(nvg, x, y, width, height, 0, id, 1f, imagePaint);
		nvgBeginPath(nvg);
		nvgRect(nvg, x, y, width, height);
		nvgFillPaint(nvg, imagePaint);
		nvgFill(nvg);
	}
	
	public static void fillCircle(int x, int y, int radius) {
		if (LOG_OPERATIONS)
			CubyzLogger.instance.fine("[NGRAPHICS] fill circle at " + x + ", " + y + " with radius " + radius);
		nvgBeginPath(nvg);
		nvgCircle(nvg, x, y, radius);
		nvgFillColor(nvg, color);
		nvgFill(nvg);
	}
	
	public static void drawRect(int x, int y, int width, int height) {
		if (LOG_OPERATIONS)
			CubyzLogger.instance.fine("[NGRAPHICS] draw rect at " + x + ", " + y + " with size " + width + ", " + height);
		nvgBeginPath(nvg);
		nvgRect(nvg, x, y, width, height);
		nvgStrokeColor(nvg, color);
		nvgStroke(nvg);
	}
	
	public static void fillRect(int x, int y, int width, int height) {
		if (LOG_OPERATIONS)
			CubyzLogger.instance.fine("[NGRAPHICS] fill rect at " + x + ", " + y + " with size " + width + ", " + height);
		nvgBeginPath(nvg);
		nvgRect(nvg, x, y, width, height);
		nvgFillColor(nvg, color);
		nvgFill(nvg);
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
	
	public static int getAscent(String text) {
		return 0;
	}
	
	public static int getTextAlign() {
		return textAlign;
	}

	public static void setTextAlign(int textAlign) {
		NGraphics.textAlign = textAlign;
	}

	public static void drawText(int x, int y, String text) {
		if (LOG_OPERATIONS)
			CubyzLogger.instance.fine("[NGRAPHICS] draw text \"" + text + "\" at " + x + ", " + y);
		nvgFontSize(nvg, font.getSize());
		nvgFontFaceId(nvg, font.getNVGId());
		nvgTextAlign(nvg, textAlign);
		nvgFillColor(nvg, color);
		nvgText(nvg, x, y, text);
	}
	
	public static void setColor(int r, int g, int b, int a) {
		color = Hud.rgba(r, g, b, a, color);
	}
	
	public static void setColor(int r, int g, int b) {
		setColor(r, g, b, 0xFF);
	}
	
}
