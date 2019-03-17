package io.cubyz.ui;

import org.jungle.Window;

import io.cubyz.client.Cubyz;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.Label;
import io.cubyz.world.LocalWorld;

public class MainMenuGUI extends MenuGUI {
	
	private Button spPlay = new Button();
	private Button mpPlay = new Button();
	private Button exit = new Button();
	private Label titleLabel = new Label();
	
	public MainMenuGUI() {
		spPlay.setSize(250, 45);
		spPlay.setText("Singleplayer");
		spPlay.setFontSize(16f);
		mpPlay.setSize(200, 40);
		mpPlay.setText("Multiplayer");
		exit.setSize(100, 27);
		exit.setText("Exit");
		titleLabel.setText("SpacyCubyd");
		titleLabel.setFontSize(72f);
		
		spPlay.setOnAction(() -> {
			LocalWorld world = new LocalWorld();
			world.generate();
			Cubyz.gameUI.setMenu(null);
			Cubyz.load(world);
			Cubyz.log.info("World Generated!");
		});
		
		exit.setOnAction(() -> {
			Cubyz.instance.cleanup();
			Cubyz.log.info("Stopped!");
			System.exit(0);
		});
	}
	
	@Override
	public void render(long nvg, Window win) {
		spPlay.setPosition(win.getWidth() / 2 - 125, 300);
		mpPlay.setPosition(win.getWidth() / 2 - 100, 375);
		exit.setPosition(win.getWidth() - 120, win.getHeight() - 40);
		titleLabel.setPosition(win.getWidth() / 2 - 160, 50);
		spPlay.render(nvg, win);
		mpPlay.render(nvg, win);
		exit.render(nvg, win);
		titleLabel.render(nvg, win);
	}

	@Override
	public boolean isFullscreen() {
		return true;
	}

	@Override
	public void init(long nvg) {}

}