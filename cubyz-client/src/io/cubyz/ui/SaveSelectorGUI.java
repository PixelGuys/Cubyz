package io.cubyz.ui;

import java.io.File;

import io.cubyz.ClientOnly;
import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.save.WorldIO;
import io.cubyz.ui.components.Button;
import io.cubyz.world.LocalWorld;
import io.jungle.Window;

public class SaveSelectorGUI extends MenuGUI {
	
	private Button[] saveButtons;
	
	@Override
	public void init(long nvg) {
		int y = 0;
		saveButtons = new Button[3];
		for (int i = 0; i < saveButtons.length; i++) {
			String name = "Save " + (i+1);
			boolean exists = new File("saves/"+name).exists();
			Button b = new Button((exists ? "" : "Create ") + name);
			b.setSize(100, 40);
			b.setPosition(10, y);
			b.setOnAction(() -> {
				LocalWorld world = new LocalWorld(name);
				Block[] blocks = world.generate();
				for(Block bl : blocks) {
					ClientOnly.createBlockMesh.accept(bl);
				}
				Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
				Cubyz.loadWorld(world);
			});
			y += 60;
			saveButtons[i] = b;
		}
	}

	@Override
	public void render(long nvg, Window win) {
		for (Button b : saveButtons) {
			b.render(nvg, win);
		}
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
