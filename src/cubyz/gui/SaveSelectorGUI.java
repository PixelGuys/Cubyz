package cubyz.gui;

import java.io.File;
import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.FileVisitor;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;

import cubyz.Logger;
import cubyz.client.ClientOnly;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.rendering.Window;
import cubyz.gui.components.Button;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.utils.translate.TextKey;
import cubyz.world.CustomObject;
import cubyz.world.LocalWorld;
import cubyz.world.VisibleChunk;
import cubyz.world.blocks.Block;

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
			b.setBounds(10, y, 200, 40, Component.ALIGN_TOP_LEFT);
			b.setOnAction(() -> {
				LocalWorld world = new LocalWorld(name, VisibleChunk.class);
				Block[] blocks = world.generate();
				for(Block bl : blocks) {
					if (bl instanceof CustomObject) {
						ClientOnly.createBlockMesh.accept(bl);
					}
				}
				Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
				GameLauncher.logic.loadWorld(world.getCurrentTorus());
			});
			saveButtons[i] = b;
			b = new Button(TextKey.createTextKey("gui.cubyz.saves.delete"));
			b.setBounds(220, y, 100, 40, Component.ALIGN_TOP_LEFT);
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
								Logger.throwable(exc);
								return FileVisitResult.TERMINATE;
							}
	
							@Override
							public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
								Files.delete(dir);
								return FileVisitResult.CONTINUE;
							}
							
						});
					} catch (IOException e) {
						Logger.throwable(e);
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
		createNew.setBounds(10, 50, 300, 40, Component.ALIGN_BOTTOM_LEFT);
		createNew.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SaveCreationGUI());
		});
		back = new Button(TextKey.createTextKey("gui.cubyz.general.back"));
		back.setBounds(110, 50, 100, 40, Component.ALIGN_BOTTOM_RIGHT);
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
		createNew.render(nvg, win);
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
