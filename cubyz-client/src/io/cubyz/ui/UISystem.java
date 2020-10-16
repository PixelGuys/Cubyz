package io.cubyz.ui;

import static org.lwjgl.nanovg.NanoVG.*;
import static org.lwjgl.nanovg.NanoVGGL3.*;
import static org.lwjgl.system.MemoryUtil.*;

import java.util.ArrayDeque;
import java.util.ArrayList;

import io.cubyz.client.Cubyz;
import io.jungle.Window;
import io.jungle.hud.Font;
import io.jungle.hud.Hud;

/**
 * UI system working in the background, to add effects like transition.
 */

public class UISystem extends Hud {

	private boolean inited = false;
	
	private MenuGUI gui;
	/** kept only for transition effect */
	private MenuGUI oldGui;
	private ArrayList<MenuGUI> overlays = new ArrayList<>();
	private ArrayDeque<MenuGUI> menuQueue = new ArrayDeque<>();
	
	public static float guiScale = 1f;
	private TransitionStyle curTransition;
	private long lastAnimTime = System.currentTimeMillis();
	private long transitionDur;

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
	
	public void back() {
		setMenu(menuQueue.pollLast(), false, TransitionStyle.FADE_OUT_IN);
	}
	
	public void setMenu(MenuGUI gui) {
		setMenu(gui, true, TransitionStyle.FADE_OUT_IN);
	}
	
	public void setMenu(MenuGUI gui, boolean addQueue) {
		setMenu(gui, addQueue, TransitionStyle.FADE_OUT_IN);
	}
	
	public void setMenu(MenuGUI gui, TransitionStyle style) {
		setMenu(gui, true, style);
	}
	
	public void setMenu(MenuGUI gui, boolean addQueue, TransitionStyle style) {
		/*CubyzLogger.instance.fine("Set UI GUI to " + gui); // used to debug UI menu sets
		try {
			throw new Error();
		} catch (Error e) {
			e.printStackTrace(System.out);
		}*/
		this.curTransition = style;
		transitionDur = 0;
		if (style != TransitionStyle.NONE) {
			oldGui = this.gui;
		}
		if (this.gui != null && addQueue) {
			menuQueue.add(this.gui);
		}
		if (this.gui != null && this.gui.ungrabsMouse() && (gui == null ? true : !gui.ungrabsMouse())) {
			Cubyz.mouse.setGrabbed(true);
		}
		if (gui != null) {
			gui.init(nvg);
		}
		this.gui = gui;
		if (gui != null && gui.ungrabsMouse() && (this.gui == null ? true : !this.gui.ungrabsMouse())) {
			Cubyz.mouse.setGrabbed(false);
		}
		if (gui == null || gui.doesPauseGame()) {
			//System.gc();
		}
	}
	
	public MenuGUI getMenuGUI() {
		return gui;
	}
	
	public boolean doesGUIBlockInput() {
		if (gui == null)
			return false;
		else
			return gui.doesPauseGame() || gui.ungrabsMouse();
	}
	
	public boolean doesGUIPauseGame() {
		return gui == null ? false : gui.doesPauseGame();
	}

	@Override
	public void init(Window window) throws Exception {
		nvg = nvgCreate(0);
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
			transitionDur += System.currentTimeMillis() - lastAnimTime;
			lastAnimTime = System.currentTimeMillis();
			nvgBeginFrame(nvg, window.getWidth(), window.getHeight(), 1);
			NGraphics.setGlobalAlphaMultiplier(1f);
			NGraphics.setColor(0, 0, 0);
			if (curTransition == TransitionStyle.FADE_OUT_IN) {
				// those values are meant to be tweaked and will be available for fine tuning from setMenu later
				float fadeSpeed = 250f;
				float fadeSpeedHalf = fadeSpeed / 2f;
				if (transitionDur >= fadeSpeed) {
					curTransition = null;
					oldGui = null;
				}
				float alpha1 = Math.min(Math.max(((float) transitionDur-fadeSpeedHalf)/fadeSpeedHalf, 0f), 1f);
				float alpha2 = Math.min(Math.max(1f - (float) transitionDur/fadeSpeedHalf, 0f), 1f);
				if (gui != null) {
					NGraphics.setGlobalAlphaMultiplier(alpha1);
					gui.render(nvg, window);
				}
				if (oldGui != null) {
					NGraphics.setGlobalAlphaMultiplier(alpha2);
					oldGui.render(nvg, window);
				}
			} else {
				if (gui != null) {
					gui.render(nvg, window);
				}
			}
			NGraphics.setGlobalAlphaMultiplier(1f);
			for (MenuGUI overlay : overlays) {
				overlay.render(nvg, window);
			}
			nvgEndFrame(nvg);
			window.restoreState();
		}
	}

}