package cubyz.gui;

import static org.lwjgl.nanovg.NanoVG.*;

import java.nio.ByteBuffer;
import java.util.HashMap;

import javax.swing.UIManager;

import org.lwjgl.nanovg.NVGColor;
import org.lwjgl.nanovg.NVGPaint;
import org.lwjgl.nanovg.NanoVG;
import org.lwjgl.nanovg.NanoVGGL3;

import cubyz.client.rendering.Font;
import cubyz.client.rendering.Hud;
import cubyz.client.rendering.Texture;
import cubyz.utils.TextureConverter;

/**
 * Graphics system wrapping NanoVG.
 */
@SuppressWarnings("unused")
public class NGraphics {

	private static long nvg;
	private static NVGColor color = NVGColor.create();
	private static NVGPaint imagePaint = NVGPaint.create();
	private static int textAlign = NVG_ALIGN_LEFT | NVG_ALIGN_TOP;
	private static float globalAlphaMultiplier;
	
	private static int cx, cy, cw, ch;
	
	/**
	 * Effective size.
	 */
	private static int eWidth, eHeight;
	
	private static Font font;
	
	// necessary to avoid the bytebuffer getting freed by the GC
	private static HashMap<String, ByteBuffer> composedTextures = new HashMap<>();
	private static HashMap<String, Integer> composedTexturesIds = new HashMap<>();
	
	public static void setNanoID(long nvg) {
		NGraphics.nvg = nvg;
	}
	
	public static void setGlobalAlphaMultiplier(float multiplier) {
		globalAlphaMultiplier = multiplier;
	}
	
	public static int loadImage(String path) {
		String [] paths = path.split("#");
		if(paths.length == 1)
			return nvgCreateImage(nvg, paths[0], NVG_IMAGE_NEAREST);
		ByteBuffer buf = null;
		if (!composedTexturesIds.containsKey(path)) {
			buf = TextureConverter.byteBuffer(TextureConverter.compose(paths));
			
			composedTextures.put(path, buf);
			composedTexturesIds.put(path, nvgCreateImageMem(nvg, NVG_IMAGE_NEAREST, buf));
		}
		return composedTexturesIds.get(path);
	}
	
	public static int nvgImageFrom(Texture tex) {
		return NanoVGGL3.nvglCreateImageFromHandle(nvg, tex.getId(), tex.getWidth(), tex.getHeight(), 0);
	}
	
	public static void drawLine(float x, float y, float x2, float y2) {
		nvgBeginPath(nvg);
			nvgMoveTo(nvg, x, y);
			nvgLineTo(nvg, x2, y2);
		nvgFill(nvg);
	}
	
	public static void drawImage(int id, int x, int y, int width, int height) {
		eWidth = (int) (width * UISystem.guiScale);
		eHeight = (int) (height * UISystem.guiScale);
		imagePaint = nvgImagePattern(nvg, x-((eWidth-width)/2), y-((eHeight-height)/2), eWidth, eHeight, 0, id, 1f, imagePaint);
		nvgBeginPath(nvg);
			nvgRect(nvg, x-((eWidth-width)/2), y-((eHeight-height)/2), eWidth, eHeight);
		nvgFillPaint(nvg, imagePaint);
		nvgFill(nvg);
	}
	
	public static void fillCircle(float x, float y, int radius) {
		nvgBeginPath(nvg);
			nvgCircle(nvg, x*UISystem.guiScale, y*UISystem.guiScale, radius*UISystem.guiScale);
		nvgFillColor(nvg, color);
		nvgFill(nvg);
	}
	
	public static void drawRect(float x, float y, float width, float height) {
		eWidth = (int) (width * UISystem.guiScale);
		eHeight = (int) (height * UISystem.guiScale);
		nvgBeginPath(nvg);
			nvgRect(nvg, x-((eWidth-width)/2), y-((eHeight-height)/2), eWidth, eHeight);
		nvgStrokeColor(nvg, color);
		nvgStroke(nvg);
	}
	
	public static void fillRect(float x, float y, float width, float height) {
		eWidth = (int) (width * UISystem.guiScale);
		eHeight = (int) (height * UISystem.guiScale);
		nvgBeginPath(nvg);
			nvgRect(nvg, x-((eWidth-width)/2), y-((eHeight-height)/2), eWidth, eHeight);
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
	}
	
}
