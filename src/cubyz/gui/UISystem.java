package cubyz.gui;

import static org.lwjgl.nanovg.NanoVG.*;
import static org.lwjgl.nanovg.NanoVGGL3.*;
import static org.lwjgl.opengl.GL11.GL_BLEND;
import static org.lwjgl.opengl.GL11.GL_CULL_FACE;
import static org.lwjgl.opengl.GL11.GL_DEPTH_TEST;
import static org.lwjgl.opengl.GL11.GL_ONE_MINUS_SRC_ALPHA;
import static org.lwjgl.opengl.GL11.GL_SRC_ALPHA;
import static org.lwjgl.opengl.GL11.glBlendFunc;
import static org.lwjgl.opengl.GL11.glDisable;
import static org.lwjgl.opengl.GL11.glEnable;
import static org.lwjgl.opengl.GL13.GL_TEXTURE0;
import static org.lwjgl.opengl.GL13.glActiveTexture;
import static org.lwjgl.system.MemoryUtil.*;

import java.util.ArrayDeque;
import java.util.ArrayList;

import cubyz.gui.input.Mouse;
import cubyz.rendering.Font;
import cubyz.rendering.Graphics;
import cubyz.rendering.Hud;
import cubyz.rendering.Window;

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
		this.curTransition = style;
		transitionDur = 0;
		if (style != TransitionStyle.NONE) {
			oldGui = this.gui;
		}
		if (this.gui != null && addQueue) {
			menuQueue.add(this.gui);
		}
		if (this.gui != null && this.gui.ungrabsMouse() && (gui == null ? true : !gui.ungrabsMouse())) {
			Mouse.setGrabbed(true);
		}
		if(this.gui != null) {
			this.gui.close();
		}
		if (gui != null) {
			gui.init(nvg);
		}
		this.gui = gui;
		if (gui != null && gui.ungrabsMouse() && (this.gui == null ? true : !this.gui.ungrabsMouse())) {
			Mouse.setGrabbed(false);
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
	public void init() throws Exception {
		nvg = nvgCreate(0);
	    if (nvg == NULL) {
	        throw new Exception("Could not init NanoVG");
	    }
		Font.register("Default", "assets/cubyz/fonts/opensans/OpenSans-Bold.ttf", nvg);
		Font.register("Title", "assets/cubyz/fonts/opensans/OpenSans-Bold.ttf", nvg);
		Font.register("Bold", "assets/cubyz/fonts/opensans/OpenSans-Bold.ttf", nvg);
		Font.register("Light", "assets/cubyz/fonts/opensans/OpenSans-Light.ttf", nvg);
		inited = true;
	}

	@Override
	public void render() {
		if (inited) {
			super.render();
			glDisable(GL_DEPTH_TEST);
			glDisable(GL_CULL_FACE);
			glEnable(GL_BLEND);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			glActiveTexture(GL_TEXTURE0);
			transitionDur += System.currentTimeMillis() - lastAnimTime;
			lastAnimTime = System.currentTimeMillis();
			nvgBeginFrame(nvg, Window.getWidth(), Window.getHeight(), 1);
			Graphics.setGlobalAlphaMultiplier(1);
			Graphics.setColor(0x000000);
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
					Graphics.setGlobalAlphaMultiplier(alpha1);
					gui.render(nvg);
				}
				if (oldGui != null) {
					Graphics.setGlobalAlphaMultiplier(alpha2);
					oldGui.render(nvg);
				}
			} else {
				if (gui != null) {
					gui.render(nvg);
				}
			}
			Graphics.setGlobalAlphaMultiplier(1f);
			for (MenuGUI overlay : overlays) {
				overlay.render(nvg);
			}
			nvgEndFrame(nvg);
			Window.restoreState();
		}
	}

}