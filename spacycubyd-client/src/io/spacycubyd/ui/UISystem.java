package io.spacycubyd.ui;

import org.lwjgl.nanovg.NVGColor;

import io.spacycubyd.client.SpacyCubyd;

import static org.lwjgl.nanovg.NanoVG.*;
import static org.lwjgl.nanovg.NanoVGGL3.*;
import static org.lwjgl.system.MemoryUtil.*;

import java.nio.ByteBuffer;
import java.util.ArrayList;

import org.jungle.Window;
import org.jungle.hud.Hud;
import org.jungle.util.Utils;

public class UISystem extends Hud {

	private boolean inited = false;
	
	private ByteBuffer fontBuffer;

	public static final String OPENSANS = "OpenSans";
	
	private MenuGUI gui;
	private ArrayList<MenuGUI> overlays = new ArrayList<>();

	public UISystem() {}
	
	public void addOverlay(MenuGUI over) {
		over.init(nvg);
		overlays.add(over);
	}
	
	public boolean removeOverlay(MenuGUI over) {
		return overlays.remove(over);
	}
	
	public void setMenu(MenuGUI gui) {
		this.gui = gui;
		if (gui != null) {
			gui.init(nvg);
		}
	}
	
	public MenuGUI getMenuGUI() {
		return gui;
	}
	
	public boolean isGUIFullscreen() {
		if (gui == null)
			return false;
		else
			return gui.isFullscreen();
	}

	public void updateUI() {
		
	}

	@Override
	public void init(Window window) throws Exception {
		this.nvg = window.getOptions().antialiasing ? nvgCreate(NVG_ANTIALIAS | NVG_STENCIL_STROKES) : nvgCreate(NVG_STENCIL_STROKES);
	    if (this.nvg == NULL) {
	        throw new Exception("Could not init nanovg");
	    }
		fontBuffer = Utils.ioResourceToByteBuffer("res/fonts/opensans/OpenSans-Bold.ttf", 1024); //NOTE: Normal > 1024
		int font = nvgCreateFontMem(nvg, OPENSANS, fontBuffer, 0); //NOTE: Normal > 0
		if (font == -1) { //NOTE: Normal > 1
			throw new IllegalStateException("Could not add font");
		}
		inited = true;
		NGraphics.setNanoID(nvg);
	}

	@Override
	public void render(Window window) {
		if (inited) {
			super.render(window);
			nvgBeginFrame(nvg, window.getWidth(), window.getHeight(), 1); //NOTE: Normal > 1
			
			if (gui != null) {
				gui.render(nvg, window);
			}
			for (MenuGUI overlay : overlays) {
				overlay.render(nvg, window);
			}
			
			nvgEndFrame(nvg);
	
			window.restoreState();
		}
	}

}