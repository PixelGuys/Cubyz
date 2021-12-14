package cubyz.gui.menu;

import java.awt.Rectangle;

import org.joml.Vector2d;

import cubyz.utils.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.components.Label;
import cubyz.gui.input.Mouse;
import cubyz.gui.menu.settings.SettingsGUI;
import cubyz.rendering.Graphics;
import cubyz.rendering.Texture;
import cubyz.rendering.Window;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.ResourceManager;
import cubyz.utils.translate.TextKey;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class MainMenuGUI extends MenuGUI {
	
	private Button exit = new Button();
	private Button settings = new Button();
	private Label titleLabel = new Label();
	
	private Texture spImage;
	private Texture mpImage;
	private Label spLabel = new Label(TextKey.createTextKey("gui.cubyz.mainmenu.singleplayer"));
	private Label mpLabel = new Label(TextKey.createTextKey("gui.cubyz.mainmenu.multiplayer"));
	private float spSize = 0.9f;
	private float mpSize = 0.9f;
	
	private boolean loadedTextures = false;
	private boolean mousePressed = false;
	
	public MainMenuGUI() {
		DiscordIntegration.setStatus("Main Menu");

		settings.setText(TextKey.createTextKey("gui.cubyz.mainmenu.settings"));

		exit.setText(TextKey.createTextKey("gui.cubyz.mainmenu.exit"));
		
		titleLabel.setTextAlign(Component.ALIGN_CENTER);
		titleLabel.setText("Cubyz");
		
		exit.setOnAction(() -> {
			GameLauncher.instance.exit();
		});
		
		settings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SettingsGUI());
		});

		updateGUIScale();
	}

	public void updateGUIScale() {
		settings.setBounds(20 * GUI_SCALE, 60 * GUI_SCALE, 100 * GUI_SCALE, 27 * GUI_SCALE, Component.ALIGN_BOTTOM_LEFT);
		settings.setFontSize(16f * GUI_SCALE);

		exit.setBounds(120 * GUI_SCALE, 60 * GUI_SCALE, 100 * GUI_SCALE, 27 * GUI_SCALE, Component.ALIGN_BOTTOM_RIGHT);
		exit.setFontSize(16f * GUI_SCALE);

		titleLabel.setBounds(0 * GUI_SCALE, 50 * GUI_SCALE, 0 * GUI_SCALE, 74 * GUI_SCALE, Component.ALIGN_TOP);
	}
	
	void launchSingleplayer() {
		Cubyz.gameUI.setMenu(new SaveSelectorGUI());
	}
	
	void launchMultiplayer() {
		Logger.warning("Multiplayer is not implemented yet!");
		Cubyz.gameUI.setMenu(new MultiplayerJoinGui());
	}
	
	@Override
	public void init() {
		spSize = 0.9f;
		mpSize = 0.9f;
		lastRender = System.currentTimeMillis();
	}
	
	long lastRender = System.currentTimeMillis();
	@Override
	public void render() {
		float delta = (System.currentTimeMillis() - lastRender) / 1000.0f;
		lastRender = System.currentTimeMillis();
		if (!loadedTextures) {
			spImage = Texture.loadFromFile(ResourceManager.lookup("cubyz/textures/singleplayer_image.png"));
			// TODO: when multiplayer is actually implemented, change the image so that we can see other players in it
			mpImage = Texture.loadFromFile(ResourceManager.lookup("cubyz/textures/multiplayer_image.png"));
			loadedTextures = true;
		}
		
		Graphics.setColor(0xFFFFFF);
		float spImageWidth = Window.getWidth() / 2;
		float spImageHeight = spImageWidth / (16f / 9f);
		Rectangle spImageBox = new Rectangle(
				(int) (spImageWidth * (1 - spSize) / 2),
				(int) (Window.getHeight() - spImageHeight + spImageHeight * (1 - spSize) / 2),
				(int) (spImageWidth * spSize), (int) (spImageHeight * spSize));
		Graphics.drawImage(spImage, spImageBox.x, spImageBox.y, spImageBox.width, spImageBox.height);
		spLabel.setBounds((int) -spImageWidth / 2, (int) (Window.getHeight() / 2 - spImageHeight / 2), 200 * GUI_SCALE, 24 * GUI_SCALE, Component.ALIGN_CENTER);
		spLabel.render();
		
		float mpImageWidth = Window.getWidth() / 2;
		float mpImageHeight = mpImageWidth / (16f / 9f);
		Rectangle mpImageBox = new Rectangle(
				(int) (spImageWidth + mpImageWidth * (1 - mpSize) / 2),
				(int) (Window.getHeight() - mpImageHeight + mpImageHeight * (1 - mpSize) / 2),
				(int) (mpImageWidth * mpSize), (int) (mpImageHeight * mpSize));
		Graphics.drawImage(mpImage, mpImageBox.x, mpImageBox.y, mpImageBox.width, mpImageBox.height);
		mpLabel.setBounds((int) spImageWidth / 2, (int) (Window.getHeight() / 2 - mpImageHeight / 2), 200 * GUI_SCALE, 24 * GUI_SCALE, Component.ALIGN_CENTER);
		mpLabel.render();
		
		settings.render();
		exit.render();
		titleLabel.render();
		
		if (Cubyz.gameUI.getMenuGUI() != this) {
			mousePressed = false;
			return; // one of the buttons changed the GUI
		}
		
		Vector2d pos = Mouse.getCurrentPos();
		if (spImageBox.contains(pos.x, pos.y)) {
			if (spSize < 1.0f) {
				spSize += 0.5f * delta;
			}
		} else {
			if (spSize > 0.9f) {
				spSize -= 0.5f * delta;
			}
		}
		if (mpImageBox.contains(pos.x, pos.y)) {
			if (mpSize < 1.0f) {
				mpSize += 0.5f * delta;
			}
		} else {
			if (mpSize > 0.9f) {
				mpSize -= 0.5f * delta;
			}
		}
		
		if (Mouse.isLeftButtonPressed()) {
			if (!mousePressed) {
				mousePressed = true;
			}
		} else {
			if (mousePressed) { // released mouse
				if (spImageBox.contains(pos.x, pos.y)) {
					launchSingleplayer();
				} else if (mpImageBox.contains(pos.x, pos.y)) {
					launchMultiplayer();
				}
			}
			mousePressed = false;
		}
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