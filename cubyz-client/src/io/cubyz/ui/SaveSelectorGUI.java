package io.cubyz.ui;

import java.io.File;

import io.cubyz.ClientOnly;
import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.save.WorldIO;
import io.cubyz.ui.components.Button;
import io.cubyz.world.CustomObject;
import io.cubyz.world.LocalWorld;
import io.jungle.Window;

public class SaveSelectorGUI extends MenuGUI {

	private Button[] saveButtons;
	private Button[] deleteButtons;
	private Button createNew;
	
	@Override
	public void init(long nvg) {
		int y = 0;
		// Find all save folders that currently exist:
		File folder = new File("saves");
		if (!folder.exists()) {
			folder.mkdir();
		}
		File[] listOfFiles = folder.listFiles();
		saveButtons = new Button[listOfFiles.length];
		deleteButtons = new Button[listOfFiles.length];
		for (int i = 0; i < listOfFiles.length; i++) {
		  if (listOfFiles[i].isDirectory()) {
		    System.out.println("Directory " + listOfFiles[i].getName());
		  }
		}
		for (int i = 0; i < saveButtons.length; i++) {
			String name = listOfFiles[i].getName();
			Button b = new Button("Load " + name);
			b.setSize(100, 40);
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
				Cubyz.loadWorld(world);
			});
			saveButtons[i] = b;
			b = new Button("Delete "+name);
			b.setSize(100, 40);
			b.setPosition(120, y);
			int index = i;
			b.setOnAction(() -> {
				// Delete the folder
				String[]entries = listOfFiles[index].list();
				for(String s: entries){
				    File currentFile = new File(listOfFiles[index].getPath(),s);
				    currentFile.delete();
				}
				listOfFiles[index].delete();
				// Remove the buttons:
				saveButtons[index] = null;
				deleteButtons[index] = null;
			});
			y += 60;
			deleteButtons[i] = b;
		}
		y += 60;
		createNew = new Button("Create New Game");
		createNew.setSize(100, 40);
		createNew.setPosition(10, y);
		createNew.setOnAction(() -> {
			// TODO: Enter custom name. (We need a Textfield and a new screen for that!)
			int num = 1;
			while(new File("saves/Save "+num).exists()) {
				num++;
			}
			LocalWorld world = new LocalWorld("Save "+num);
			Block[] blocks = world.generate();
			for(Block bl : blocks) {
				if (bl instanceof CustomObject) {
					ClientOnly.createBlockMesh.accept(bl);
				}
			}
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			Cubyz.loadWorld(world);
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
		createNew.render(nvg, win);
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
