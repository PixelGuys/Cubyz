package cubyz.gui;

import java.awt.Rectangle;

import org.joml.Vector2d;

import cubyz.Logger;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.components.Button;
import cubyz.gui.components.Label;
import cubyz.gui.input.Mouse;
import cubyz.gui.settings.SettingsGUI;
import cubyz.rendering.Graphics;
import cubyz.rendering.Texture;
import cubyz.rendering.Window;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.ResourceManager;
import cubyz.utils.translate.TextKey;

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

		settings.setBounds(20, 60, 100, 27, Component.ALIGN_BOTTOM_LEFT);
		settings.setText(TextKey.createTextKey("gui.cubyz.mainmenu.settings"));
		settings.setFontSize(16f);

		exit.setBounds(120, 60, 100, 27, Component.ALIGN_BOTTOM_RIGHT);
		exit.setText(TextKey.createTextKey("gui.cubyz.mainmenu.exit"));
		exit.setFontSize(16f);
		
		titleLabel.setTextAlign(Component.ALIGN_CENTER);
		titleLabel.setText("Cubyz");
		titleLabel.setBounds(0, 50, 0, 74, Component.ALIGN_TOP);
		
		exit.setOnAction(() -> {
			GameLauncher.instance.exit();
		});
		
		settings.setOnAction(() -> {
			Cubyz.gameUI.setMenu(new SettingsGUI());
		});
	}
	
	void launchSingleplayer() {
		Cubyz.gameUI.setMenu(new SaveSelectorGUI());
	}
	
	void launchMultiplayer() {
		Logger.warning("Multiplayer is not implemented yet!");
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
		spLabel.setBounds((int) -spImageWidth / 2, (int) (Window.getHeight() / 2 - spImageHeight / 2), 200, 24, Component.ALIGN_CENTER);
		spLabel.render();
		
		float mpImageWidth = Window.getWidth() / 2;
		float mpImageHeight = mpImageWidth / (16f / 9f);
		Rectangle mpImageBox = new Rectangle(
				(int) (spImageWidth + mpImageWidth * (1 - mpSize) / 2),
				(int) (Window.getHeight() - mpImageHeight + mpImageHeight * (1 - mpSize) / 2),
				(int) (mpImageWidth * mpSize), (int) (mpImageHeight * mpSize));
		Graphics.drawImage(mpImage, mpImageBox.x, mpImageBox.y, mpImageBox.width, mpImageBox.height);
		mpLabel.setBounds((int) spImageWidth / 2, (int) (Window.getHeight() / 2 - mpImageHeight / 2), 200, 24, Component.ALIGN_CENTER);
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