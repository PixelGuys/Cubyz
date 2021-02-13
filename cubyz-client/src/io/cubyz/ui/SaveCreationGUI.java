package io.cubyz.ui;

import java.io.File;

import io.cubyz.ClientOnly;
import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.client.GameLauncher;
import io.cubyz.rendering.Font;
import io.cubyz.rendering.Window;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.TextInput;
import io.cubyz.world.CustomObject;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.VisibleChunk;

/**
 * GUI shown when creating a new world in a new world file.<br>
 * TODO: world seed and other related settings.
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
		
		name.setBounds(-100, 100, 200, 30, Component.ALIGN_TOP);
		name.setFont(new Font("Default", 20f));
		
		int num = 1;
		while(new File("saves/Save "+num).exists()) {
			num++;
		}
		name.setText("Save " + num);

		create.setBounds(10, 60, 200, 50, Component.ALIGN_BOTTOM_LEFT);
		create.setText(TextKey.createTextKey("gui.cubyz.saves.create"));
		create.setOnAction(() -> {
			LocalWorld world = new LocalWorld(name.getText(), VisibleChunk.class);
			Block[] blocks = world.generate();
			for(Block bl : blocks) {
				if (bl instanceof CustomObject) {
					ClientOnly.createBlockMesh.accept(bl);
				}
			}
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			GameLauncher.logic.loadWorld(world.getCurrentTorus());
		});

		cancel.setBounds(110, 60, 100, 50, Component.ALIGN_BOTTOM_RIGHT);
		cancel.setText(TextKey.createTextKey("gui.cubyz.general.cancel"));
		cancel.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
	}

	@Override
	public void render(long nvg, Window win) {
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
