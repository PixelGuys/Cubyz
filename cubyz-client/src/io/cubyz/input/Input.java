package io.cubyz.input;

import org.joml.Vector3f;
import org.lwjgl.glfw.GLFW;

import io.cubyz.ClientSettings;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.client.Cubyz;
import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.Player;
import io.cubyz.rendering.Window;
import io.cubyz.ui.ConsoleGUI;
import io.cubyz.ui.PauseGUI;
import io.cubyz.ui.TransitionStyle;
import io.cubyz.ui.mods.InventoryGUI;

/**
 * Handles all the inputs.
 */

public class Input {
	public MouseInput mouse;

	public boolean clientShowDebug = false;
	
	public void init() {
		mouse = new MouseInput();
		mouse.init(Cubyz.window);
	}
	
	public void update(Window window) {
		mouse.input(window);
		if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			clientShowDebug = !clientShowDebug;
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F3, false);
		}
		if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F11)) {
			Cubyz.renderDeque.push(() -> {
				window.setFullscreen(!window.isFullscreen());
			});
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F11, false);
		}
		if(!Cubyz.gameUI.doesGUIBlockInput() && Cubyz.world != null) {
			if(Keybindings.isPressed("forward")) {
				if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) {
					if(Cubyz.world.getLocalPlayer().isFlying()) {
						Cubyz.playerInc.z = -8;
					} else {
						Cubyz.playerInc.z = -2;
					}
				} else {
					Cubyz.playerInc.z = -1;
				}
			}
			if(Keybindings.isPressed("backward")) {
				Cubyz.playerInc.z = 1;
			}
			if(Keybindings.isPressed("left")) {
				Cubyz.playerInc.x = -1;
			}
			if(Keybindings.isPressed("right")) {
				Cubyz.playerInc.x = 1;
			}
			if(Keybindings.isPressed("jump")) {
				Player localPlayer = Cubyz.world.getLocalPlayer();
				if(localPlayer.isFlying()) {
					Cubyz.world.getLocalPlayer().vy = 0.25F;
				} else if(Cubyz.world.getLocalPlayer().isOnGround()) {
					Cubyz.world.getLocalPlayer().vy = 0.25F;
				}
			}
			if(Keybindings.isPressed("fall")) {
				if(Cubyz.world.getLocalPlayer().isFlying()) {
					Cubyz.world.getLocalPlayer().vy = -0.25F;
				}
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F)) {
				Cubyz.world.getLocalPlayer().setFlying(!Cubyz.world.getLocalPlayer().isFlying());
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_F, false);
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_P)) {
				// debug: spawn a pig
				Vector3f pos = new Vector3f(Cubyz.world.getLocalPlayer().getPosition());
				EntityType pigType = CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:pig");
				if (pigType == null) return;
				Entity pig = pigType.newEntity(Cubyz.surface);
				pig.setPosition(pos);
				Cubyz.surface.addEntity(pig);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_P, false);
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_C)) {
				int mods = Keyboard.getKeyMods();
				if((mods & GLFW.GLFW_MOD_CONTROL) == GLFW.GLFW_MOD_CONTROL) {
					if((mods & GLFW.GLFW_MOD_SHIFT) == GLFW.GLFW_MOD_SHIFT) { // Control + Shift + C
						if(Cubyz.gameUI.getMenuGUI() == null) {
							Cubyz.gameUI.setMenu(new ConsoleGUI());
						}
					}
				}
			}
			if(Keybindings.isPressed("inventory")) {
				Cubyz.gameUI.setMenu(new InventoryGUI());
				Keyboard.setKeyPressed(Keybindings.getKeyCode("inventory"), false);
			}
			if((mouse.isLeftButtonPressed() || mouse.isRightButtonPressed()) && !mouse.isGrabbed() && Cubyz.gameUI.getMenuGUI() == null) {
				mouse.setGrabbed(true);
				mouse.clearPos(window.getWidth()/2, window.getHeight()/2);
			}
			
			if(mouse.isGrabbed()) {
				Cubyz.camera.moveRotation(mouse.getDisplVec().x*0.0089F, mouse.getDisplVec().y*0.0089F, 5F);
				mouse.clearPos(Cubyz.window.getWidth()/2, Cubyz.window.getHeight()/2);
			}
			
			// inventory related
			Cubyz.inventorySelection = (Cubyz.inventorySelection + (int) mouse.getScrollOffset()) & 7;
			if(Keybindings.isPressed("hotbar 1")) {
				Cubyz.inventorySelection = 0;
			}
			if(Keybindings.isPressed("hotbar 2")) {
				Cubyz.inventorySelection = 1;
			}
			if(Keybindings.isPressed("hotbar 3")) {
				Cubyz.inventorySelection = 2;
			}
			if(Keybindings.isPressed("hotbar 4")) {
				Cubyz.inventorySelection = 3;
			}
			if(Keybindings.isPressed("hotbar 5")) {
				Cubyz.inventorySelection = 4;
			}
			if(Keybindings.isPressed("hotbar 6")) {
				Cubyz.inventorySelection = 5;
			}
			if(Keybindings.isPressed("hotbar 7")) {
				Cubyz.inventorySelection = 6;
			}
			if(Keybindings.isPressed("hotbar 8")) {
				Cubyz.inventorySelection = 7;
			}
			
			// render distance
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_MINUS)) {
				if(ClientSettings.RENDER_DISTANCE >= 2)
					ClientSettings.RENDER_DISTANCE--;
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_MINUS, false);
				System.gc();
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_EQUAL)) {
				ClientSettings.RENDER_DISTANCE++;
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_EQUAL, false);
				System.gc();
			}
			Cubyz.msd.selectSpatial(Cubyz.surface.getChunks(), Cubyz.world.getLocalPlayer().getPosition(), Cubyz.camera.getViewMatrix().positiveZ(Cubyz.dir).negate(), Cubyz.surface.getStellarTorus().getWorld().getLocalPlayer(), Cubyz.surface);
		}
		if(Cubyz.world != null) {
			if(Keybindings.isPressed("menu")) {
				if(Cubyz.gameUI.getMenuGUI() != null) {
					Cubyz.gameUI.setMenu(null);
					mouse.setGrabbed(true);
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
				} else {
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
					Cubyz.gameUI.setMenu(new PauseGUI(), TransitionStyle.NONE);
				}
			}
		}
		mouse.clearScroll();
		Keyboard.release();
	}
}
