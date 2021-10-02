package cubyz.gui.input;

import org.joml.Vector3f;
import org.lwjgl.glfw.GLFW;

import cubyz.api.CubyzRegistries;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.gui.ConsoleGUI;
import cubyz.gui.PauseGUI;
import cubyz.gui.TransitionStyle;
import cubyz.gui.mods.InventoryGUI;
import cubyz.rendering.BackgroundScene;
import cubyz.rendering.Camera;
import cubyz.rendering.Window;
import cubyz.world.entity.Entity;
import cubyz.world.entity.EntityType;

/**
 * Handles all the inputs.
 */

public class Input {
	public boolean clientShowDebug = false;
	
	public void init() {
		Mouse.init();
	}
	
	public void update() {
		if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			clientShowDebug = !clientShowDebug;
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F3, false);
		}
		if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F11)) {
			Cubyz.renderDeque.push(() -> {
				Window.setFullscreen(!Window.isFullscreen());
			});
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F11, false);
		}
		if(!Cubyz.gameUI.doesGUIBlockInput() && Cubyz.world != null) {
			if(Keybindings.isPressed("forward")) {
				if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) {
					if(Cubyz.player.isFlying()) {
						Cubyz.playerInc.z = -32;
					} else {
						Cubyz.playerInc.z = -8;
					}
				} else {
					Cubyz.playerInc.z = -4;
				}
			}
			if(Keybindings.isPressed("backward")) {
				Cubyz.playerInc.z = 4;
			}
			if(Keybindings.isPressed("left")) {
				Cubyz.playerInc.x = -4;
			}
			if(Keybindings.isPressed("right")) {
				Cubyz.playerInc.x = 4;
			}
			if(Keybindings.isPressed("jump")) {
				if(Cubyz.player.isFlying()) {
					Cubyz.player.vy = 5;
				} else if(Cubyz.player.isOnGround()) {
					Cubyz.player.vy = 5;
				}
			}
			if(Keybindings.isPressed("fall")) {
				if(Cubyz.player.isFlying()) {
					Cubyz.player.vy = -5;
				}
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F)) {
				Cubyz.player.setFlying(!Cubyz.player.isFlying());
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_F, false);
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_P)) {
				// debug: spawn a pig
				Vector3f pos = new Vector3f(Cubyz.player.getPosition());
				EntityType pigType = CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:pig");
				if (pigType == null) return;
				Entity pig = pigType.newEntity(Cubyz.world);
				pig.setPosition(pos);
				Cubyz.world.addEntity(pig);
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_P, false);
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_T)) {
				if(Cubyz.gameUI.getMenuGUI() == null) {
					Cubyz.gameUI.setMenu(new ConsoleGUI());
				}
			}
			if(Keybindings.isPressed("inventory")) {
				Cubyz.gameUI.setMenu(new InventoryGUI());
				Keyboard.setKeyPressed(Keybindings.getKeyCode("inventory"), false);
			}
			if((Mouse.isLeftButtonPressed() || Mouse.isRightButtonPressed()) && !Mouse.isGrabbed() && Cubyz.gameUI.getMenuGUI() == null) {
				Mouse.setGrabbed(true);
				Mouse.clearDelta();
			}
			
			if(Mouse.isGrabbed()) {
				Camera.moveRotation(Mouse.getDeltaX()*0.0089F, Mouse.getDeltaY()*0.0089F);
				Mouse.clearDelta();
			}
			
			// inventory related
			Cubyz.inventorySelection = (Cubyz.inventorySelection - (int) Mouse.getScrollOffset()) & 7;
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
			Cubyz.msd.selectSpatial(Cubyz.world.getChunks(), Cubyz.player.getPosition(), Camera.getViewMatrix().positiveZ(Cubyz.dir).negate(), Cubyz.player, Cubyz.world);
		}
		if(Cubyz.world != null) {
			if(Keybindings.isPressed("menu")) {
				if(Cubyz.gameUI.getMenuGUI() != null) {
					Cubyz.gameUI.setMenu(null);
					Mouse.setGrabbed(true);
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
				} else {
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
					Cubyz.gameUI.setMenu(new PauseGUI(), TransitionStyle.NONE);
				}
			}
		}
		if((Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_CONTROL) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) && Keyboard.isKeyPressed(GLFW.GLFW_KEY_PRINT_SCREEN)) {
			BackgroundScene.takeBackgroundImage();
		}

		Mouse.clearScroll();
	}
}
