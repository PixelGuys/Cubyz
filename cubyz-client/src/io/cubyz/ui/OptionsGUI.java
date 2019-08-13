package io.cubyz.ui;

import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.components.Button;

public class OptionsGUI extends MenuGUI {

	private Button done = new Button();
	
	@Override
	public void init(long nvg) {
		done.setSize(250, 45);
		done.setText(new TextKey("gui.cubyz.options.done"));
		done.setFontSize(16f);
		
		done.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new MainMenuGUI());
		});
	}

	@Override
	public void render(long nvg, Window win) {
		done.setPosition(win.getWidth() / 2 - 125, win.getHeight() - 75);
		
		done.render(nvg, win);
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

}
