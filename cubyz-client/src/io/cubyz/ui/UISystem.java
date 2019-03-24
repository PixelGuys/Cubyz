package io.cubyz.ui;

import static org.lwjgl.nanovg.NanoVG.*;
import static org.lwjgl.nanovg.NanoVGGL3.*;
import static org.lwjgl.system.MemoryUtil.*;

import java.util.ArrayList;

import org.jungle.Window;
import org.jungle.hud.Font;
import org.jungle.hud.Hud;

public class UISystem extends Hud {

	private boolean inited = false;
	
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

	public void updateUI() {}

	@Override
	public void init(Window window) throws Exception {
		nvg = window.getOptions().antialiasing ? nvgCreate(NVG_ANTIALIAS | NVG_STENCIL_STROKES) : nvgCreate(NVG_STENCIL_STROKES);
	    if (nvg == NULL) {
	        throw new Exception("Could not init nanovg");
	    }
		Font.register("OpenSans Bold", "res/fonts/opensans/OpenSans-Bold.ttf", nvg);
		NGraphics.setNanoID(nvg);
		inited = true;
	}

	@Override
	public void render(Window window) {
		if (inited) {
			super.render(window);
			nvgBeginFrame(nvg, window.getWidth(), window.getHeight(), 1);
			NGraphics.setColor(0, 0, 0, 255);
			NGraphics.setTextAlign(NVG_ALIGN_LEFT | NVG_ALIGN_TOP);
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