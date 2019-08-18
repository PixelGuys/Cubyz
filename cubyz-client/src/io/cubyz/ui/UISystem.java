package io.cubyz.ui;

import static org.lwjgl.nanovg.NanoVG.*;
import static org.lwjgl.nanovg.NanoVGGL3.*;
import static org.lwjgl.system.MemoryUtil.*;

import java.util.ArrayList;

import org.jungle.Window;
import org.jungle.hud.Font;
import org.jungle.hud.Hud;

import io.cubyz.client.Cubyz;

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
	
	public ArrayList<MenuGUI> getOverlays() {
		return overlays;
	}
	
	public void setMenu(MenuGUI gui) {
		if (this.gui != null && this.gui.ungrabsMouse()) {
			Cubyz.mouse.setGrabbed(true);
		}
		this.gui = gui;
		if (gui != null && gui.ungrabsMouse()) {
			Cubyz.mouse.setGrabbed(false);
		}
		if (gui != null) {
			gui.init(nvg);
		}
		if (gui == null || gui.doesPauseGame()) {
			//System.gc();
		}
	}
	
	public MenuGUI getMenuGUI() {
		return gui;
	}
	
	public boolean doesGUIPauseGame() {
		if (gui == null)
			return false;
		else
			return gui.doesPauseGame();
	}

	@Override
	public void init(Window window) throws Exception {
		nvg = window.getOptions().antialiasing ? nvgCreate(NVG_ANTIALIAS | NVG_STENCIL_STROKES) : nvgCreate(NVG_STENCIL_STROKES);
	    if (nvg == NULL) {
	        throw new Exception("Could not init NanoVG");
	    }
		Font.register("Default", "assets/cubyz/fonts/opensans/OpenSans-Bold.ttf", nvg);
		Font.register("Title", "assets/cubyz/fonts/opensans/OpenSans-Bold.ttf", nvg);
		Font.register("Bold", "assets/cubyz/fonts/opensans/OpenSans-Bold.ttf", nvg);
		Font.register("Light", "assets/cubyz/fonts/opensans/OpenSans-Light.ttf", nvg);
		NGraphics.setNanoID(nvg);
		inited = true;
	}

	@Override
	public void render(Window window) {
		if (inited) {
			super.render(window);
			nvgBeginFrame(nvg, window.getWidth(), window.getHeight(), 1);
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