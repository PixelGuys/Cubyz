package io.cubyz.ui;

import java.io.File;

import io.cubyz.ClientOnly;
import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.ContextualTextKey;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.components.Button;
import io.cubyz.world.CustomObject;
import io.cubyz.world.LocalWorld;
import io.jungle.Window;

public class SaveSelectorGUI extends MenuGUI {

	private Button[] saveButtons;
	private Button[] deleteButtons;
	private Button createNew;
	private Button back;
	
	@Override
	public void init(long nvg) {
		int y = 10;
		// Find all save folders that currently exist:
		File folder = new File("saves");
		if (!folder.exists()) {
			folder.mkdir();
		}
		File[] listOfFiles = folder.listFiles();
		saveButtons = new Button[listOfFiles.length];
		deleteButtons = new Button[listOfFiles.length];
		for (int i = 0; i < saveButtons.length; i++) {
			String name = listOfFiles[i].getName();
			ContextualTextKey tk = new ContextualTextKey("gui.cubyz.saves.play", 1);
			tk.setArgument(0, name);
			Button b = new Button(tk);
			b.setSize(200, 40);
			b.setPosition(10, y);
			b.setOnAction(() -> {
				LocalWorld world = new LocalWorld(name);
				Block[] blocks = world.generate();
				for(Block bl : blocks) {
					if (bl instanceof CustomObject) {
						ClientOnly.createBlockMesh.accept(bl);
					}
				}
				Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
				Cubyz.loadWorld(world.getCurrentTorus());
			});
			saveButtons[i] = b;
			b = new Button(new TextKey("gui.cubyz.saves.delete"));
			b.setSize(100, 40);
			b.setPosition(220, y);
			int index = i;
			b.setOnAction(() -> {
				// Delete the folder
				String[] entries = listOfFiles[index].list();
				for(String s: entries){
				    File currentFile = new File(listOfFiles[index].getPath(),s);
				    currentFile.delete();
				}
				listOfFiles[index].delete();
				// Remove the buttons:
				saveButtons[index] = null;
				deleteButtons[index] = null;
				init(nvg); // re-init to re-order
			});
			y += 60;
			deleteButtons[i] = b;
		}
		y += 60;
		createNew = new Button(new TextKey("gui.cubyz.saves.create"));
		createNew.setSize(300, 40);
		createNew.setPosition(10, 0);
		createNew.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SaveCreationGUI());
		});
		back = new Button(new TextKey("gui.cubyz.general.back"));
		back.setSize(100, 40);
		back.setOnAction(() -> {
			Cubyz.gameUI.back();
		});
	}

	@Override
	public void render(long nvg, Window win) {
		for (Button b : saveButtons) {
			if(b != null)
				b.render(nvg, win);
		}
		for (Button b : deleteButtons) {
			if(b != null)
				b.render(nvg, win);
		}
		if(createNew == null) init(nvg);
		createNew.y = win.getHeight() - 50;
		createNew.render(nvg, win);
		back.setPosition(win.getWidth() - 110, win.getHeight() - 50);
		back.render(nvg, win);
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
