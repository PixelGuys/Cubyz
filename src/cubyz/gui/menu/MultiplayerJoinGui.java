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
import cubyz.rendering.VisibleChunk;
import cubyz.rendering.text.Fonts;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.translate.TextKey;
import cubyz.world.ClientWorld;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class MultiplayerJoinGui extends MenuGUI {

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
	private final TextInputWithLabel guiPort      = new TextInputWithLabel();
	private final Button             guiJoin      = new Button();

	@Override
	public void init() {
		DiscordIntegration.setStatus("Multiplayer");
		guiIPAddress.setBounds(-250, 100, 150, 250, 20);
		guiIPAddress.setText("IP adress", ClientSettings.lastUsedIPAddress);

		guiPort.setBounds(-250, 180, 150, 250, 20);
		guiPort.setText("local port", ""+Constants.DEFAULT_PORT);

		guiJoin.setBounds(10, 60, 400, 50, Component.ALIGN_BOTTOM_LEFT);
		guiJoin.setText(TextKey.createTextKey("gui.cubyz.multiplayer.join"));
		guiJoin.setFontSize(32);
		guiJoin.setOnAction(() -> {
			ClientSettings.lastUsedIPAddress = guiIPAddress.getText().trim();
			ClientSettings.save();

			ClientWorld world = new ClientWorld(guiIPAddress.getText().trim(), guiPort.getText(), VisibleChunk.class);
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			GameLauncher.logic.loadWorld(world);
		});
		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		guiIPAddress.updateGUIScale();
	}

	@Override
	public void render() {
		guiIPAddress.render();
		guiPort.render();
		guiJoin.render();
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
