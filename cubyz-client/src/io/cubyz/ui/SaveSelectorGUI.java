package io.cubyz.ui;

import io.cubyz.ui.components.Button;
import io.jungle.Window;

public class SaveSelectorGUI extends MenuGUI {
	
	private Button[] saveButtons;;
	
	@Override
	public void init(long nvg) {
		int y = 0;
		saveButtons = new Button[3];
		for (int i = 0; i < saveButtons.length; i++) {
			Button b = new Button();
		}
	}

	@Override
	public void render(long nvg, Window win) {
		
	}

	@Override
	public boolean doesPauseGame() {
		return false;
	}

}
