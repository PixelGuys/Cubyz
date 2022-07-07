package cubyz.gui.menu;

import cubyz.Constants;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.components.Label;
import cubyz.gui.components.TextInput;
import cubyz.multiplayer.UDPConnectionManager;
import cubyz.rendering.VisibleChunk;
import cubyz.rendering.text.Fonts;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.Logger;
import cubyz.utils.translate.TextKey;
import cubyz.world.ClientWorld;

import java.awt.*;
import java.awt.datatransfer.Clipboard;
import java.awt.datatransfer.StringSelection;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class MultiplayerJoinGui extends MenuGUI {

	private UDPConnectionManager connection = null;

	private final Thread backgroundThread;

	private static class TextInputWithLabel{
		private final TextInput textInput	 = new TextInput();
		private final Label label			 = new Label();
		private int x, y, labelWidth, inputTextWidth, height;

		public void setText(String stringLabel, String stringTextInput){
			updateGUIScale();
			label.setText(stringLabel);
			textInput.setText(stringTextInput);
		}
		public void setText(TextKey stringLabel, String stringTextInput){
			updateGUIScale();
			label.setText(stringLabel);
			textInput.setText(stringTextInput);
		}
		public String getText(){
			return textInput.getText();
		}
		public void setBounds(int x, int y, int labelWidth, int inputTextWidth, int height){
			this.x = x;
			this.y = y;
			this.labelWidth = labelWidth;
			this.inputTextWidth = inputTextWidth;
			this.height = height;
		}
		public void updateGUIScale() {
			label.setBounds(
					x*GUI_SCALE,
					y*GUI_SCALE+this.height*GUI_SCALE/2,
					labelWidth*GUI_SCALE,
					height*GUI_SCALE, Component.ALIGN_TOP);
			label.setFont(Fonts.PIXEL_FONT);

			textInput.setBounds(
					x*GUI_SCALE+labelWidth,
					y*GUI_SCALE,
					inputTextWidth*GUI_SCALE,
					height*GUI_SCALE, Component.ALIGN_TOP);
			textInput.setFont(Fonts.PIXEL_FONT, height*GUI_SCALE);
		}
		public void render() {
			label.render();
			textInput.render();
		}
	}


	private final TextInputWithLabel guiIPAddress = new TextInputWithLabel();
	private final Button guiJoin = new Button();
	private final Button copy = new Button();
	private final Label ip = new Label();
	private final Label prompt = new Label();

	public MultiplayerJoinGui() {
		backgroundThread = new Thread(() -> {
			synchronized(this) {
				connection = new UDPConnectionManager(Constants.DEFAULT_PORT);
			}
			ip.setText(connection.externalIPPort.replaceAll(":"+Constants.DEFAULT_PORT, ""));
		});
	}

	@Override
	public void init() {
		DiscordIntegration.setStatus("Multiplayer");
		guiIPAddress.setBounds(-250, 100, 150, 250, 20);
		guiIPAddress.setText("IP address", ClientSettings.lastUsedIPAddress);

		prompt.setText(TextKey.createTextKey("gui.cubyz.multiplayer.prompt"));
		prompt.setFont(Fonts.PIXEL_FONT);

		ip.setFont(Fonts.PIXEL_FONT);

		guiJoin.setText(TextKey.createTextKey("gui.cubyz.multiplayer.join"));
		guiJoin.setOnAction(() -> {
			ClientSettings.lastUsedIPAddress = guiIPAddress.getText().trim();
			ClientSettings.save();
			try {
				backgroundThread.join();
			} catch(InterruptedException e) {
				Logger.error(e);
				return;
			}

			ClientWorld world = new ClientWorld(guiIPAddress.getText().trim(), connection, VisibleChunk.class);
			connection = null;
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			GameLauncher.logic.loadWorld(world);
		});

		copy.setText(TextKey.createTextKey("gui.cubyz.multiplayer.copy_ip"));
		copy.setOnAction(() -> {
			StringSelection selection = new StringSelection(ip.getText().getTranslateKey());
			Clipboard clipboard = Toolkit.getDefaultToolkit().getSystemClipboard();
			clipboard.setContents(selection, selection);
		});

		updateGUIScale();
		backgroundThread.start();
	}

	@Override
	public void updateGUIScale() {
		guiIPAddress.updateGUIScale();
		prompt.setBounds(0, 20*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		prompt.setFontSize(12*GUI_SCALE);

		ip.setBounds(0, 50*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		ip.setFontSize(16*GUI_SCALE);

		copy.setBounds(-50*GUI_SCALE, 60*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		copy.setFontSize(16*GUI_SCALE);

		guiJoin.setBounds(-50*GUI_SCALE, 200*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		guiJoin.setFontSize(16*GUI_SCALE);
	}

	@Override
	public void render() {
		guiIPAddress.render();
		guiJoin.render();
		prompt.render();
		ip.render();
		copy.render();
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
	public void close() {
		backgroundThread.interrupt();
		try {
			backgroundThread.join();
		} catch(InterruptedException e) {
			Logger.error(e);
		}
		if(connection != null) {
			connection.cleanup();
		}
		connection = null;
	}
}
