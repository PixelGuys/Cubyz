package cubyz.gui.input;

import org.joml.Vector3d;
import org.lwjgl.glfw.GLFW;

import cubyz.api.CubyzRegistries;
import cubyz.client.BlockMeshes;
import cubyz.client.ClientOnly;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.ConsoleLog;
import cubyz.gui.Transition;
import cubyz.gui.game.ConsoleGUI;
import cubyz.gui.game.PauseGUI;
import cubyz.gui.game.inventory.GeneralInventory;
import cubyz.gui.game.inventory.InventoryGUI;
import cubyz.rendering.BackgroundScene;
import cubyz.rendering.Camera;
import cubyz.rendering.Window;
import cubyz.world.entity.Entity;
import cubyz.world.entity.EntityType;
import cubyz.world.items.Inventory;
import cubyz.world.items.ItemStack;
import cubyz.server.Server;
import cubyz.utils.Logger;

/**
 * Handles all the inputs.
 */

public class Input {
	public boolean clientShowDebug = false;

	private boolean executedF3Shortcut = false;

	private final ConsoleLog consoleLog = new ConsoleLog();
	
	public void init() {
		Mouse.init();
	}
	
	public void update() {
		if (Keyboard.isKeyReleased(GLFW.GLFW_KEY_F3)) {
			if(!executedF3Shortcut) {
				clientShowDebug = !clientShowDebug;
			}
			executedF3Shortcut = false;
		}
		if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_F3)) {
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_T)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_T, false);
				BlockMeshes.reloadTextures();
				executedF3Shortcut = true;
			}
			if(Keyboard.isKeyPressed(GLFW.GLFW_KEY_L)) {
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_L, false);
				if(Cubyz.gameUI.getOverlays()[Cubyz.gameUI.getOverlays().length-1] instanceof ConsoleLog)
					Cubyz.gameUI.removeOverlay(consoleLog);
				else Cubyz.gameUI.addOverlay(consoleLog);
				executedF3Shortcut = true;
			}
		}
		if (Keyboard.isKeyReleased(GLFW.GLFW_KEY_F5)) {
			try {
				GameLauncher.renderer.init();
			} catch (Exception e) {
				Logger.error(e);
			}
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F11)) {
			Cubyz.renderDeque.push(() -> {
				Window.setFullscreen(!Window.isFullscreen());
			});
			Keyboard.setKeyPressed(GLFW.GLFW_KEY_F11, false);
		}
		if (Cubyz.world != null) {
			if (!Cubyz.gameUI.doesGUIBlockInput()) {
				if (Keybindings.isPressed("forward")) {
					if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) {
						if (Cubyz.player.isFlying()) {
							Cubyz.playerInc.z = -32;
						} else {
							Cubyz.playerInc.z = -8;
						}
					} else {
						Cubyz.playerInc.z = -4;
					}
				}
				if (Keybindings.isPressed("backward")) {
					Cubyz.playerInc.z = 4;
				}
				if (Keybindings.isPressed("left")) {
					Cubyz.playerInc.x = -4;
				}
				if (Keybindings.isPressed("right")) {
					Cubyz.playerInc.x = 4;
				}
				if (Keybindings.isPressed("jump")) {
					if (Cubyz.player.isFlying()) {
						Cubyz.player.vy = Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL) ? 29.45F : 5.45F;
					} else if (Cubyz.player.isOnGround()) {
						Cubyz.player.vy = 5.45F;
					}
				}
				if (Keybindings.isPressed("fall")) {
					if (Cubyz.player.isFlying()) {
						Cubyz.player.vy = Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL) ? -29F : -5F;
					}
				}
				if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_F)) {
					Cubyz.player.setFlying(!Cubyz.player.isFlying());
					Keyboard.setKeyPressed(GLFW.GLFW_KEY_F, false);
				}
				if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_P)) {
					// debug: spawn a pig
					Vector3d pos = new Vector3d(Cubyz.player.getPosition());
					EntityType pigType = CubyzRegistries.ENTITY_REGISTRY.getByID("cubyz:pig");
					if (pigType == null) return;
					Entity pig = pigType.newEntity(Cubyz.world);
					pig.setPosition(pos);
					Cubyz.world.addEntity(pig);
					Keyboard.setKeyPressed(GLFW.GLFW_KEY_P, false);
				}
				if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_T)) {
					if (Cubyz.gameUI.getMenuGUI() == null) {
						Keyboard.release();
						Keyboard.release();
						Cubyz.gameUI.setMenu(new ConsoleGUI());
					}
				}
				if ((Mouse.isLeftButtonPressed() || Mouse.isRightButtonPressed()) && !Mouse.isGrabbed() && Cubyz.gameUI.getMenuGUI() == null) {
					Mouse.setGrabbed(true);
					Mouse.clearDelta();
				}
			
				// inventory related
				Cubyz.inventorySelection = (Cubyz.inventorySelection - (int) Mouse.getScrollOffset()) & 7;
				if (Keybindings.isPressed("hotbar 1")) {
					Cubyz.inventorySelection = 0;
				}
				if (Keybindings.isPressed("hotbar 2")) {
					Cubyz.inventorySelection = 1;
				}
				if (Keybindings.isPressed("hotbar 3")) {
					Cubyz.inventorySelection = 2;
				}
				if (Keybindings.isPressed("hotbar 4")) {
					Cubyz.inventorySelection = 3;
				}
				if (Keybindings.isPressed("hotbar 5")) {
					Cubyz.inventorySelection = 4;
				}
				if (Keybindings.isPressed("hotbar 6")) {
					Cubyz.inventorySelection = 5;
				}
				if (Keybindings.isPressed("hotbar 7")) {
					Cubyz.inventorySelection = 6;
				}
				if (Keybindings.isPressed("hotbar 8")) {
					Cubyz.inventorySelection = 7;
				}

				if (Keybindings.isPressed("drop")) {
					ItemStack stack = Cubyz.player.getInventory().getStack(Cubyz.inventorySelection);
					if (!stack.empty()) {
						ItemStack droppedStack = new ItemStack(stack);
						stack.clear();
						Cubyz.world.drop(droppedStack, Cubyz.player.getPosition(), Camera.getDirection(), 1, Server.UPDATES_PER_SEC*5 /*5 seconds cooldown before being able to pick it up again.*/);
					}
				}

				Cubyz.msd.selectSpatial(Cubyz.world.getChunks(), Cubyz.player.getPosition(), Camera.getViewMatrix().positiveZ(Cubyz.dir).negate(), Cubyz.player, Cubyz.world);
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_C)) {
				if (Cubyz.gameUI.getMenuGUI() == null) {
					ClientOnly.client.openGUI("cubyz:creative", new Inventory(0));
				} else if (Cubyz.gameUI.getMenuGUI().getRegistryID().toString().equals("cubyz:creative")) {
					Cubyz.gameUI.back();
				}
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_C, false);
			}
			if (Keybindings.isPressed("inventory")) {
				if (Cubyz.gameUI.getMenuGUI() == null) {
					Cubyz.gameUI.setMenu(new InventoryGUI());
				} else if (Cubyz.gameUI.getMenuGUI() instanceof GeneralInventory) {
					Cubyz.gameUI.back();
				}
				Keyboard.setKeyPressed(Keybindings.getKeyCode("inventory"), false);
			}
			
			if (Mouse.isGrabbed()) {
				Camera.moveRotation(Mouse.getDeltaX()*0.0089F, Mouse.getDeltaY()*0.0089F);
				Mouse.clearDelta();
			}
			
			// render distance
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_MINUS)) {
				if (ClientSettings.RENDER_DISTANCE >= 2)
					ClientSettings.RENDER_DISTANCE--;
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_MINUS, false);
				System.gc();
			}
			if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_EQUAL)) {
				ClientSettings.RENDER_DISTANCE++;
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_EQUAL, false);
				System.gc();
			}
		}
		if (Keyboard.isKeyPressed(GLFW.GLFW_KEY_ESCAPE)) {
			if (Cubyz.gameUI.getMenuGUI() != null) {
				// Return to the previous screen if escape was pressed:
				Keyboard.setKeyPressed(GLFW.GLFW_KEY_ESCAPE, false);
				Cubyz.gameUI.back();
			}
		}
		if (Cubyz.world != null) {
			if (Keybindings.isPressed("menu")) {
				if (Cubyz.gameUI.getMenuGUI() != null) {
					Cubyz.gameUI.setMenu(null);
					Mouse.setGrabbed(true);
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
				} else {
					Keyboard.setKeyPressed(Keybindings.getKeyCode("menu"), false);
					Cubyz.gameUI.setMenu(new PauseGUI(), new Transition.None());
				}
			}
		}
		if ((Keyboard.isKeyPressed(GLFW.GLFW_KEY_RIGHT_CONTROL) || Keyboard.isKeyPressed(GLFW.GLFW_KEY_LEFT_CONTROL)) && Keyboard.isKeyPressed(GLFW.GLFW_KEY_PRINT_SCREEN)) {
			BackgroundScene.takeBackgroundImage();
		}

		Mouse.clearScroll();
	}
}
