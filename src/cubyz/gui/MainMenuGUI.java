package cubyz.gui;

import cubyz.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
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
		spPlay.setBounds(-125, 300, 250, 50, Component.ALIGN_TOP);
		spPlay.setText(TextKey.createTextKey("gui.cubyz.mainmenu.singleplayer"));
		spPlay.setFontSize(32f);
		
		mpPlay.setBounds(-125, 375, 250, 50, Component.ALIGN_TOP);
		mpPlay.setText(TextKey.createTextKey("gui.cubyz.mainmenu.multiplayer"));
		mpPlay.setFontSize(32f);

		settings.setBounds(-125, 450, 250, 50, Component.ALIGN_TOP);
		settings.setText(TextKey.createTextKey("gui.cubyz.mainmenu.settings"));
		settings.setFontSize(32f);

		exit.setBounds(120, 60, 100, 27, Component.ALIGN_BOTTOM_RIGHT);
		exit.setText(TextKey.createTextKey("gui.cubyz.mainmenu.exit"));
		exit.setFontSize(16f);
		
		titleLabel.setTextAlign(Component.ALIGN_CENTER);
		titleLabel.setText("Cubyz");
		titleLabel.setBounds(0, 50, 0, 74, Component.ALIGN_TOP);
		
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
	public void render(long nvg) {
		spPlay.render(nvg);
		mpPlay.render(nvg);
		settings.render(nvg);
		exit.render(nvg);
		titleLabel.render(nvg);
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