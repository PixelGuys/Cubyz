package cubyz.gui;

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

import java.util.ArrayDeque;
import java.util.ArrayList;

import org.lwjgl.glfw.GLFW;

import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;

/**
 * UI system working in the background, to add effects like transition.
 */

public class UISystem {
	
	private MenuGUI gui;
	/** kept only for transition effect */
	private MenuGUI oldGui;
	private ArrayList<MenuGUI> overlays = new ArrayList<>();
	private ArrayDeque<MenuGUI> menuQueue = new ArrayDeque<>();
	
	public static float guiScale = 1f;
	private TransitionStyle curTransition;
	private long lastAnimTime = System.currentTimeMillis();
	private long transitionDur;

	public boolean showOverlay = true;

	public UISystem() {}
	
	public void addOverlay(MenuGUI over) {
		over.init();
		synchronized(overlays) {
			overlays.add(over);
		}
	}
	
	public boolean removeOverlay(MenuGUI over) {
		synchronized(overlays) {
			return overlays.remove(over);
		}
	}
	
	public MenuGUI[] getOverlays() {
		synchronized(overlays) {
			return overlays.toArray(new MenuGUI[0]);
		}
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
			gui.init();
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

	public void render() {
		if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F1)) {
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F1, false);
			showOverlay = !showOverlay;
		}
		if(showOverlay) {
			glDisable(GL_DEPTH_TEST);
			glDisable(GL_CULL_FACE);
			glEnable(GL_BLEND);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			glActiveTexture(GL_TEXTURE0);
			transitionDur += System.currentTimeMillis() - lastAnimTime;
			lastAnimTime = System.currentTimeMillis();
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
					gui.render();
				}
				if (oldGui != null) {
					Graphics.setGlobalAlphaMultiplier(alpha2);
					oldGui.render();
				}
			} else {
				if (gui != null) {
					gui.render();
				}
			}
			Graphics.setGlobalAlphaMultiplier(1f);
			for(MenuGUI overlay : getOverlays()) {
				overlay.render();
			}
		}
		Window.restoreState();
	}

}