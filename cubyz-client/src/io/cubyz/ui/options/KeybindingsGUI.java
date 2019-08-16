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
			button.setText(GLFW.glfwGetKeyName(Keybindings.getKeyCode(name), -1));
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
