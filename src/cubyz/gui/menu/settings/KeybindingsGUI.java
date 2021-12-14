package cubyz.gui.menu.settings;

import org.lwjgl.glfw.GLFW;

import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.components.Label;
import cubyz.gui.components.ScrollingContainer;
import cubyz.gui.input.Keybindings;
import cubyz.gui.input.Keyboard;
import cubyz.gui.input.Mouse;
import cubyz.rendering.Window;
import cubyz.utils.Utilities;
import cubyz.utils.translate.TextKey;

import static org.lwjgl.glfw.GLFW.*;
import static cubyz.client.ClientSettings.GUI_SCALE;

public class KeybindingsGUI extends MenuGUI {

	private final ScrollingContainer container = new ScrollingContainer();
	private Button done;
	private String listen;
	private Label[] labels;
	private Button[] buttons;
	
	@Override
	public void init() {
		initUI();
	}
	
	private String nonAlpha(int keyCode) {
		switch (keyCode) {
			case GLFW.GLFW_KEY_SPACE: return "Space";
			case GLFW.GLFW_KEY_ESCAPE: return "Escape";
			case GLFW.GLFW_KEY_F1: return "F1";
			case GLFW.GLFW_KEY_F2: return "F2";
			case GLFW.GLFW_KEY_F3: return "F3";
			case GLFW.GLFW_KEY_F4: return "F4";
			case GLFW.GLFW_KEY_F5: return "F5";
			case GLFW.GLFW_KEY_F6: return "F6";
			case GLFW.GLFW_KEY_F7: return "F7";
			case GLFW.GLFW_KEY_F8: return "F8";
			case GLFW.GLFW_KEY_F9: return "F9";
			case GLFW.GLFW_KEY_F10: return "F10";
			case GLFW.GLFW_KEY_F11: return "F11";
			case GLFW.GLFW_KEY_F12: return "F12";
			case GLFW.GLFW_KEY_F13: return "F13";
			case GLFW.GLFW_KEY_F14: return "F14";
			case GLFW.GLFW_KEY_F15: return "F15";
			case GLFW.GLFW_KEY_F16: return "F16";
			case GLFW.GLFW_KEY_F17: return "F17";
			case GLFW.GLFW_KEY_F18: return "F18";
			case GLFW.GLFW_KEY_F19: return "F19";
			case GLFW.GLFW_KEY_F20: return "F20";
			case GLFW.GLFW_KEY_F21: return "F21";
			case GLFW.GLFW_KEY_F22: return "F22";
			case GLFW.GLFW_KEY_F23: return "F23";
			case GLFW.GLFW_KEY_F24: return "F24";
			case GLFW.GLFW_KEY_F25: return "F25";
			case GLFW.GLFW_KEY_UP: return "Up";
			case GLFW.GLFW_KEY_DOWN: return "Down";
			case GLFW.GLFW_KEY_LEFT: return "Left";
			case GLFW.GLFW_KEY_RIGHT: return "Right";
			case GLFW.GLFW_KEY_KP_0: return "Numpad 0";
			case GLFW.GLFW_KEY_KP_1: return "Numpad 1";
			case GLFW.GLFW_KEY_KP_2: return "Numpad 2";
			case GLFW.GLFW_KEY_KP_3: return "Numpad 3";
			case GLFW.GLFW_KEY_KP_4: return "Numpad 4";
			case GLFW.GLFW_KEY_KP_5: return "Numpad 5";
			case GLFW.GLFW_KEY_KP_6: return "Numpad 6";
			case GLFW.GLFW_KEY_KP_7: return "Numpad 7";
			case GLFW.GLFW_KEY_KP_8: return "Numpad 8";
			case GLFW.GLFW_KEY_KP_9: return "Numpad 9";
			case GLFW.GLFW_KEY_KP_ADD: return "Numpad +";
			case GLFW.GLFW_KEY_KP_SUBTRACT: return "Numpad -";
			case GLFW.GLFW_KEY_KP_DIVIDE: return "Numpad /";
			case GLFW.GLFW_KEY_KP_MULTIPLY: return "Numpad *";
			case GLFW.GLFW_KEY_KP_EQUAL: return "Numpad =";
			case GLFW.GLFW_KEY_KP_ENTER: return "Numpad Enter";
			case GLFW.GLFW_KEY_HOME: return "Home";
			case GLFW.GLFW_KEY_MENU: return "Menu";
			case GLFW.GLFW_KEY_LEFT_SHIFT: return "Shift";
			case GLFW.GLFW_KEY_LEFT_CONTROL: return "Ctrl";
			case GLFW.GLFW_KEY_RIGHT_SHIFT: return "Right Shift";
			case GLFW.GLFW_KEY_RIGHT_CONTROL: return "Right Ctrl";
			case Keybindings.MOUSE_LEFT_CLICK: return "Left Click";
			case Keybindings.MOUSE_MIDDLE_CLICK: return "Middle Click";
			case Keybindings.MOUSE_RIGHT_CLICK: return "Right Click";
			default: return "Unknown";
		}
	}
	
	public void initUI() {
		container.clear();
		
		done = new Button();
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		done.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
		
		buttons = new Button[Keybindings.keyNames.length];
		labels = new Label[Keybindings.keyNames.length];
		int i = 0;
		for (String name : Keybindings.keyNames) {
			Label label = new Label();
			Button button = new Button();
			String text = null;
			if (Keybindings.getKeyCode(name) < 1000) {
				text = GLFW.glfwGetKeyName(Keybindings.getKeyCode(name), GLFW.glfwGetKeyScancode(Keybindings.getKeyCode(name)));
			}
			if (text == null) {
				text = nonAlpha(Keybindings.getKeyCode(name));
			}
			button.setText(text);
			label.setText(Utilities.capitalize(name));
			
			button.setOnAction(() -> {
				if (listen == null) {
					listen = name;
					glfwSetKeyCallback(Window.getWindowHandle(), (window, key, scancode, action, mods) -> {
						glfwKeyCallback(key, scancode, action, mods);
					});
					button.setText("Click or press any key");
				}
			});
			label.setTextAlign(Component.ALIGN_TOP_LEFT);
			container.add(label);
			container.add(button);

			buttons[i] = button;
			labels[i] = label;
			
			i++;
		}
		
		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		done.setBounds(100 * GUI_SCALE, 30 * GUI_SCALE, 80 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_BOTTOM_RIGHT);
		done.setFontSize(16 * GUI_SCALE);
		
		int y = 10;
		for (int i = 0; i < buttons.length; i++) {
			buttons[i].setBounds(160 * GUI_SCALE, y * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
			buttons[i].setFontSize(16 * GUI_SCALE);

			labels[i].setBounds(20 * GUI_SCALE, (y + 4) * GUI_SCALE, 0 * GUI_SCALE, 24 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
			labels[i].setFontSize(16 * GUI_SCALE);

			y += 30;
		}
		
		container.setBounds(0, 0, Window.getWidth(), Window.getHeight() - 70 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
	}

	public void endListen(int keyCode) {
		Keybindings.setKeyCode(listen, keyCode);
		initUI();
		listen = null;
		glfwSetKeyCallback(Window.getWindowHandle(), (window, key, scancode, action, mods) -> {
			Keyboard.glfwKeyCallback(key, scancode, action, mods);
		});
	}

	public void glfwKeyCallback(int key, int scancode, int action, int mods) {
		endListen(key);
	}

	@Override
	public void close() {
		if (listen != null)
			endListen(Keybindings.getKeyCode(listen));
	}

	@Override
	public void render() {
		if (listen != null) {
			if (Mouse.isLeftButtonPressed()) {
				endListen(Keybindings.MOUSE_LEFT_CLICK);
			} else if (Mouse.isMiddleButtonPressed()) {
				endListen(Keybindings.MOUSE_MIDDLE_CLICK);
			} else if (Mouse.isRightButtonPressed()) {
				endListen(Keybindings.MOUSE_RIGHT_CLICK);
			}
		}
		
		container.render();
		done.render();
	}
	
	@Override
	public boolean ungrabsMouse() {
		return true;
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
