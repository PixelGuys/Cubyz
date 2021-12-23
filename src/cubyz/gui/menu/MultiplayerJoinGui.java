package cubyz.gui.menu;

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
import cubyz.world.World;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class MultiplayerJoinGui extends MenuGUI {

	private class TextInputWithLabel{
		private TextInput textInput	 = new TextInput();
		private Label label			 = new Label();
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


	private TextInputWithLabel guiIPAdress  = new TextInputWithLabel();
	private TextInputWithLabel guiName	    = new TextInputWithLabel();
	private Button			   guiJoin	    = new Button();

	@Override
	public void init() {
		DiscordIntegration.setStatus("Multiplayer");
		guiIPAdress.setBounds(-250, 100, 150, 250, 20);
		guiIPAdress.setText("IP adress", "localhost:42069");

		/* TODO: Until we have a logIn server or something like that, the user can enter any name.
		*   This can be exploited very easly. Might be good to change this in the future.*/
		guiName.setBounds(-250, 140, 150, 250, 20);
		guiName.setText(TextKey.createTextKey("gui.cubyz.multiplayer.displayname"), "TheLegend27");

		guiJoin.setBounds(10, 60, 400, 50, Component.ALIGN_BOTTOM_LEFT);
		guiJoin.setText(TextKey.createTextKey("gui.cubyz.multiplayer.join"));
		guiJoin.setFontSize(32);
		guiJoin.setOnAction(() -> {
			//new Thread(() -> Server.main(new String[0]), "Server Thread").start();

			World world = new ClientWorld(guiIPAdress.getText(), guiName.getText(), VisibleChunk.class);
			Cubyz.gameUI.setMenu(null, false); // hide from UISystem.back()
			GameLauncher.logic.loadWorld(world);
		});
		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		guiIPAdress.updateGUIScale();
	}

	@Override
	public void render() {
		guiIPAdress.render();
		guiName.render();
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
