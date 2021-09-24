package cubyz.gui;

import java.io.File;

import cubyz.client.ClientOnly;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.components.Button;
import cubyz.gui.components.TextInput;
import cubyz.rendering.VisibleChunk;
import cubyz.rendering.text.Fonts;
import cubyz.utils.translate.TextKey;
import cubyz.world.CustomObject;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;

/**
 * GUI shown when creating a new world in a new world file.<br>
 * TODO: world seed and other related settings.
 */

public class SaveCreationGUI extends MenuGUI {
	
	private Button create;
	private Button cancel;
	private TextInput name;
	
	@Override
	public void init() {
		name = new TextInput();
		create = new Button();
		cancel = new Button();
		
		name.setBounds(-250, 100, 500, 40, Component.ALIGN_TOP);
		name.setFont(Fonts.PIXEL_FONT, 32);
		
		int num = 1;
		while(new File("saves/Save "+num).exists()) {
			num++;
		}
		name.setText("Save " + num);

		create.setBounds(10, 60, 200, 50, Component.ALIGN_BOTTOM_LEFT);
		create.setText(TextKey.createTextKey("gui.cubyz.saves.create"));
		create.setFontSize(32);
		create.setOnAction(() -> {
			ServerWorld world = new ServerWorld(name.getText(), VisibleChunk.class);
			Block[] blocks = world.generate();
			for(Block bl : blocks) {
				if (bl instanceof CustomObject) {
					ClientOnly.createBlockMesh.accept(bl);
				}
			}
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			GameLauncher.logic.loadWorld(world);
		});

		cancel.setBounds(110, 60, 100, 50, Component.ALIGN_BOTTOM_RIGHT);
		cancel.setText(TextKey.createTextKey("gui.cubyz.general.cancel"));
		cancel.setFontSize(32);
		cancel.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
	}

	@Override
	public void render() {
		name.render();
		create.render();
		cancel.render();
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
