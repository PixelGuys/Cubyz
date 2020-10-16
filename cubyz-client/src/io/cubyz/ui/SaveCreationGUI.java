package io.cubyz.ui;

import java.io.File;

import io.cubyz.ClientOnly;
import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.TextInput;
import io.cubyz.world.CustomObject;
import io.cubyz.world.LocalWorld;
import io.jungle.Window;
import io.jungle.hud.Font;

/**
 * GUI shown when creating a new world in a new world file.<br>
 * TODO: world seed.
 */

public class SaveCreationGUI extends MenuGUI {
	
	private Button create;
	private Button cancel;
	private TextInput name;
	
	@Override
	public void init(long nvg) {
		name = new TextInput();
		create = new Button();
		cancel = new Button();
		
		name.setSize(200, 30);
		name.setFont(new Font("Default", 20f));
		
		int num = 1;
		while(new File("saves/Save "+num).exists()) {
			num++;
		}
		name.setText("Save " + num);
		
		create.setSize(200, 50);
		create.setText(TextKey.createTextKey("gui.cubyz.saves.create"));
		create.setOnAction(() -> {
			LocalWorld world = new LocalWorld(name.getText());
			Block[] blocks = world.generate();
			for(Block bl : blocks) {
				if (bl instanceof CustomObject) {
					ClientOnly.createBlockMesh.accept(bl);
				}
			}
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			Cubyz.loadWorld(world.getCurrentTorus());
		});
		
		cancel.setSize(100, 50);
		cancel.setText(TextKey.createTextKey("gui.cubyz.general.cancel"));
		cancel.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
	}

	@Override
	public void render(long nvg, Window win) {
		create.setPosition(10, win.getHeight() - 60);
		name.setPosition(win.getWidth() / 2 - 100, 100);
		cancel.setPosition(win.getWidth() - 110, win.getHeight() - 60);
		
		name.render(nvg, win);
		create.render(nvg, win);
		cancel.render(nvg, win);
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
