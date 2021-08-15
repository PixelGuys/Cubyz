package cubyz.gui;

import cubyz.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.client.rendering.Font;
import cubyz.client.rendering.Window;
import cubyz.gui.components.Button;
import cubyz.gui.components.Label;
import cubyz.gui.settings.SettingsGUI;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.translate.TextKey;

public class MainMenuGUI extends MenuGUI {
	
	private Button spPlay = new Button();
	private Button mpPlay = new Button();
	private Button exit = new Button();
	private Button settings = new Button();
	private Label titleLabel = new Label();
	
	public MainMenuGUI() {
		DiscordIntegration.setStatus("Main Menu");
		spPlay.setBounds(-125, 300, 250, 45, Component.ALIGN_TOP);
		spPlay.setText(TextKey.createTextKey("gui.cubyz.mainmenu.singleplayer"));
		spPlay.setFontSize(16f);
		
		mpPlay.setBounds(-125, 375, 250, 45, Component.ALIGN_TOP);
		mpPlay.setText(TextKey.createTextKey("gui.cubyz.mainmenu.multiplayer"));
		mpPlay.setFontSize(16f);

		settings.setBounds(-125, 450, 250, 45, Component.ALIGN_TOP);
		settings.setText(TextKey.createTextKey("gui.cubyz.mainmenu.settings"));
		settings.setFontSize(16f);

		exit.setBounds(120, 40, 100, 27, Component.ALIGN_BOTTOM_RIGHT);
		exit.setText(TextKey.createTextKey("gui.cubyz.mainmenu.exit"));
		
		titleLabel.setText("Cubyz");
		titleLabel.setFont(new Font("Title", 72.f));
		titleLabel.setPosition(-80, 50, Component.ALIGN_TOP);
		
		spPlay.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SaveSelectorGUI());
		});
		
		mpPlay.setOnAction(() -> {
			Logger.warning("Multiplayer is not implemented yet!");
		});
		
		exit.setOnAction(() -> {
			GameLauncher.instance.exit();
		});
		
		settings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SettingsGUI());
		});
	}
	
	@Override
	public void render(long nvg, Window win) {
		spPlay.render(nvg, win);
		mpPlay.render(nvg, win);
		settings.render(nvg, win);
		exit.render(nvg, win);
		titleLabel.render(nvg, win);
	}
	
	@Override
	public boolean ungrabsMouse() {
		return true;
	}

	@Override
	public boolean doesPauseGame() {
		return true;
	}

	@Override
	public void init(long nvg) {}

}