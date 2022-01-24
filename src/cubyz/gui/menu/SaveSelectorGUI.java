package cubyz.gui.menu;

import java.io.File;
import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.FileVisitor;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;

import cubyz.utils.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.components.ScrollingContainer;
import cubyz.rendering.VisibleChunk;
import cubyz.rendering.Window;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.utils.translate.TextKey;
import cubyz.world.ServerWorld;
import cubyz.world.World;
import cubyz.server.Server;

import static cubyz.client.ClientSettings.GUI_SCALE;

/**
 * GUI used to select the world to play.
 */

public class SaveSelectorGUI extends MenuGUI {

	private Button[] saveButtons;
	private Button[] deleteButtons;
	private Button createNew;
	private Button back;

	private ScrollingContainer container;
	
	@Override
	public void init() {
		container = new ScrollingContainer();

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
			b.setOnAction(() -> {
				new Thread(() -> Server.main(new String[0]), "Server Thread").start();
				World world = new ServerWorld(name, null, VisibleChunk.class);
				Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
				GameLauncher.logic.loadWorld(world);
			});
			saveButtons[i] = b;
			container.add(b);
			b = new Button(TextKey.createTextKey("gui.cubyz.saves.delete"));
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
							public FileVisitResult visitFileFailed(Path file, IOException e) throws IOException {
								Logger.error(e);
								return FileVisitResult.TERMINATE;
							}
	
							@Override
							public FileVisitResult postVisitDirectory(Path dir, IOException e) throws IOException {
								Files.delete(dir);
								return FileVisitResult.CONTINUE;
							}
							
						});
					} catch (IOException e) {
						Logger.error(e);
					}
					// Remove the buttons:
					saveButtons[index] = null;
					deleteButtons[index] = null;
					init(); // re-init to re-order
				}
			});
			deleteButtons[i] = b;
			container.add(b);
		}
		createNew = new Button(TextKey.createTextKey("gui.cubyz.saves.create"));
		createNew.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SaveCreationGUI());
		});
		back = new Button(TextKey.createTextKey("gui.cubyz.general.back"));
		back.setOnAction(() -> {
			Cubyz.gameUI.back();
		});

		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		container.setBounds(10 * GUI_SCALE, 10 * GUI_SCALE, Window.getWidth() - 20, Window.getHeight() - 70 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
		int y = 0;
		for (int i = 0; i < saveButtons.length; i++) {
			saveButtons[i].setBounds(0, y * GUI_SCALE, 200 * GUI_SCALE, 20 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
			saveButtons[i].setMaxResizeWidth(200*GUI_SCALE, Component.ALIGN_LEFT);
			saveButtons[i].setFontSize(16 * GUI_SCALE);
			deleteButtons[i].setBounds(210 * GUI_SCALE, y * GUI_SCALE, 50 * GUI_SCALE, 20 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
			deleteButtons[i].setFontSize(16 * GUI_SCALE);
			y += 30;
		}
		createNew.setBounds(10 * GUI_SCALE, 30 * GUI_SCALE, 150 * GUI_SCALE, 20 * GUI_SCALE, Component.ALIGN_BOTTOM_LEFT);
		createNew.setFontSize(16 * GUI_SCALE);

		back.setBounds(60 * GUI_SCALE, 30 * GUI_SCALE, 50 * GUI_SCALE, 20 * GUI_SCALE, Component.ALIGN_BOTTOM_RIGHT);
		back.setFontSize(16 * GUI_SCALE);
	}

	@Override
	public void render() {
		container.render();
		if (createNew == null) init();
		createNew.render();
		back.render();
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
