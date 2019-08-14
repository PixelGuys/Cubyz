package io.cubyz.ui;

import org.jungle.Window;
import org.jungle.hud.Font;

import io.cubyz.client.Cubyz;
import io.cubyz.multiplayer.server.CubyzServer;
import io.cubyz.translate.TextKey;
import io.cubyz.ui.components.Button;
import io.cubyz.ui.components.Label;
import io.cubyz.world.LocalWorld;
import io.cubyz.world.RemoteWorld;

public class MainMenuGUI extends MenuGUI {
	
	private Button spPlay = new Button();
	private Button mpPlay = new Button();
	private Button exit = new Button();
	private Button options = new Button();
	private Label titleLabel = new Label();
	
	public MainMenuGUI() {
		spPlay.setSize(250, 45);
		spPlay.setText(new TextKey("gui.cubyz.mainmenu.singleplayer"));
		spPlay.setFontSize(16f);
		
		mpPlay.setSize(250, 45);
		mpPlay.setText(new TextKey("gui.cubyz.mainmenu.multiplayer"));
		mpPlay.setFontSize(16f);
		
		options.setSize(250, 45);
		options.setText(new TextKey("gui.cubyz.mainmenu.options"));
		options.setFontSize(16f);
		
		exit.setSize(100, 27);
		exit.setText(new TextKey("gui.cubyz.mainmenu.exit"));
		titleLabel.setText("Cubyz");
		titleLabel.setFont(new Font("OpenSans Bold", 72.f));
		
		spPlay.setOnAction(() -> {
			// TODO: Start local server and let Cubyz join it
			/*
			CubyzServer server = new CubyzServer(Cubyz.serverPort);
			try {
				server.start(true);
			} catch (Exception e) {
				e.printStackTrace();
			}
			Cubyz.requestJoin("localhost");
			*/
			LocalWorld world = new LocalWorld();
			world.generate();
			//RemoteWorld world = new RemoteWorld();
			Cubyz.gameUI.setMenu(null);
			Cubyz.loadWorld(world);
		});
		
		exit.setOnAction(() -> {
			Cubyz.instance.game.exit();
		});
		
		options.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new OptionsGUI());
		});
	}
	
	@Override
	public void render(long nvg, Window win) {
		spPlay.setPosition(win.getWidth() / 2 - 125, 300);
		mpPlay.setPosition(win.getWidth() / 2 - 125, 450);
		options.setPosition(win.getWidth() / 2 - 125, 375);
		exit.setPosition(win.getWidth() - 120, win.getHeight() - 40);
		titleLabel.setPosition(win.getWidth() / 2 - 80, 50);
		
		spPlay.render(nvg, win);
		mpPlay.render(nvg, win);
		options.render(nvg, win);
		exit.render(nvg, win);
		titleLabel.render(nvg, win);
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

	@Override
	public void init(long nvg) {}

}