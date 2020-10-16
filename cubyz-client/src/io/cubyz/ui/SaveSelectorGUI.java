package io.cubyz.ui;

import java.io.File;
import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.FileVisitor;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;

import io.cubyz.ClientOnly;
import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.translate.ContextualTextKey;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.components.Button;
import io.cubyz.world.CustomObject;
import io.cubyz.world.LocalWorld;
import io.jungle.Window;

import static io.cubyz.CubyzLogger.logger;

/**
 * GUI used to select the world to play.
 */

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
			ContextualTextKey tk = new ContextualTextKey("gui.cubyz.saves.play", name);
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
			b = new Button(TextKey.createTextKey("gui.cubyz.saves.delete"));
			b.setSize(100, 40);
			b.setPosition(220, y);
			int index = i;
			Path path = listOfFiles[i].toPath();
			b.setOnAction(new Runnable() {
				public void run() {
					// Delete the folder
					try {
						Files.walkFileTree(path, new FileVisitor<Path>() {
	
							@Override
							public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
								return FileVisitResult.CONTINUE;
							}
	
							@Override
							public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
								Files.delete(file);
								return FileVisitResult.CONTINUE;
							}
	
							@Override
							public FileVisitResult visitFileFailed(Path file, IOException exc) throws IOException {
								logger.throwable(exc);
								return FileVisitResult.TERMINATE;
							}
	
							@Override
							public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
								Files.delete(dir);
								return FileVisitResult.CONTINUE;
							}
							
						});
					} catch (IOException e) {
						e.printStackTrace();
					}
					// Remove the buttons:
					saveButtons[index] = null;
					deleteButtons[index] = null;
					init(nvg); // re-init to re-order
				}
			});
			y += 60;
			deleteButtons[i] = b;
		}
		y += 60;
		createNew = new Button(TextKey.createTextKey("gui.cubyz.saves.create"));
		createNew.setSize(300, 40);
		createNew.setPosition(10, 0);
		createNew.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SaveCreationGUI());
		});
		back = new Button(TextKey.createTextKey("gui.cubyz.general.back"));
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
