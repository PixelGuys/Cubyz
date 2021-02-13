package io.cubyz.rendering;

import org.lwjgl.nanovg.NVGColor;

import static org.lwjgl.nanovg.NanoVGGL3.*;
import static org.lwjgl.system.MemoryUtil.NULL;

public class Hud {

	public long nvg;
	
	public void init(Window window) throws Exception {
	    this.nvg = nvgCreate(0);
	    if (this.nvg == NULL) {
	        throw new Exception("Could not init NanoVG");
	    }
	}
	
	public void render(Window window) {}

	// Color utilities
    public static NVGColor rgba(int r, int g, int b, int a, NVGColor colour) {
        colour.r(r / 255.0f);
        colour.g(g / 255.0f);
        colour.b(b / 255.0f);
        colour.a(a / 255.0f);
        return colour;
    }
    
    public static NVGColor rgba(int r, int g, int b, int a) {
    	return rgba(r, g, b, a, NVGColor.create());
    }
    
    public static NVGColor rgb(int r, int g, int b, NVGColor colour) {
    	return rgba(r, g, b, 255, colour);
    }
    
    public static NVGColor rgb(int r, int g, int b) {
    	return rgba(r, g, b, 255);
    }

    public void cleanup() {
        nvgDelete(nvg);
    }
	
}
