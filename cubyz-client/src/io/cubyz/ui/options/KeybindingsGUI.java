package io.cubyz.ui.options;

import org.jungle.Keyboard;
import org.jungle.Window;
import org.jungle.hud.Font;
import org.lwjgl.glfw.GLFW;

import io.cubyz.Keybindings;
import io.cubyz.Utilities;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.MenuGUI;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.Label;
import io.cubyz.ui.components.ScrollingContainer;

public class KeybindingsGUI extends MenuGUI {

	private ScrollingContainer container;
	private Button done;
	private String listen;
	
	@Override
	public void init(long nvg) {
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
			default: return "Unknown";
		}
	}
	
	public void initUI() {
		container = new ScrollingContainer();
		
		done = new Button();
		done.setText(new TextKey("gui.cubyz.options.done"));
		done.setSize(250, 45);
		done.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new OptionsGUI());
		});
		
		int y = 30;
		for (String name : Keybindings.keyNames) {
			Label label = new Label();
			Button button = new Button();
			String text = GLFW.glfwGetKeyName(Keybindings.getKeyCode(name), GLFW.glfwGetKeyScancode(Keybindings.getKeyCode(name)));
			if (text == null) {
				text = nonAlpha(Keybindings.getKeyCode(name));
			}
			button.setText(text);
			label.setFont(new Font("OpenSans Bold", 24f));
			label.setText(Utilities.capitalize(name));
			
			button.setPosition(120, y);
			button.setSize(250, 25);
			button.setOnAction(() -> {
				if (listen == null) {
					listen = name;
					button.setText("Press any key");
				}
			});
			label.setPosition(20, y);
			container.add(label);
			container.add(button);
			
			y += 40;
		}
		
	}

	@Override
	public void render(long nvg, Window win) {
		if (listen != null && Keyboard.hasKeyCode()) {
			Keybindings.setKeyCode(listen, Keyboard.getKeyCode());
			initUI();
			listen = null;
		}
		
		container.setSize(win.getWidth(), win.getHeight()-70);
		done.setPosition(win.getWidth()-270, win.getHeight()-65);
		
		container.render(nvg, win);
		done.render(nvg, win);
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
