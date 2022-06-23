package cubyz.gui.menu.settings;

import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.components.TextInput;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;
import cubyz.rendering.text.TextLine;
import cubyz.utils.Logger;
import cubyz.utils.translate.TextKey;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class NameSelectionGUI extends MenuGUI {
	private final TextInput nameField = new TextInput();
	private TextLine prompt;
	private TextLine formatting;
	private TextLine formattingExamples;
	private TextLine formattingColor;
	private TextLine formattingColorExamples;
	private final Button done = new Button();

	public NameSelectionGUI(boolean isFirstTime) {
		if(isFirstTime) {
			prompt = new TextLine(Fonts.PIXEL_FONT, TextKey.createTextKey("gui.cubyz.settings.name.initial_prompt").getTranslation(), 16, false);
		} else {
			prompt = new TextLine(Fonts.PIXEL_FONT, TextKey.createTextKey("gui.cubyz.settings.name.later_prompt").getTranslation(), 16, false);
		}
		formatting = new TextLine(Fonts.PIXEL_FONT, TextKey.createTextKey("gui.cubyz.settings.name.format").getTranslation(), 16, false);
		formattingExamples = new TextLine(Fonts.PIXEL_FONT, TextKey.createTextKey("gui.cubyz.settings.name.format.examples").getTranslation(), 16, false);
		formattingColor = new TextLine(Fonts.PIXEL_FONT, TextKey.createTextKey("gui.cubyz.settings.name.format.color").getTranslation(), 16, false);
		formattingColorExamples = new TextLine(Fonts.PIXEL_FONT, TextKey.createTextKey("gui.cubyz.settings.name.format.color.examples").getTranslation(), 16, false);
	}

	@Override
	public void init() {
		done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));
		done.setOnAction(() -> {
			ClientSettings.playerName = nameField.getText();
			ClientSettings.save();
			Cubyz.gameUI.back();
		});

		nameField.setText(ClientSettings.playerName);

		updateGUIScale();
	}

	@Override
	public void updateGUIScale() {
		nameField.setBounds(-250*GUI_SCALE, 0*GUI_SCALE, 500*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_CENTER);
		nameField.setFontSize(16*GUI_SCALE);

		done.setBounds(-250*GUI_SCALE, 50*GUI_SCALE, 500*GUI_SCALE, 30*GUI_SCALE, Component.ALIGN_BOTTOM);
		done.setFontSize(16*GUI_SCALE);

		prompt = new TextLine(Fonts.PIXEL_FONT, prompt.getText(), 12*GUI_SCALE, false);
		formatting = new TextLine(Fonts.PIXEL_FONT, formatting.getText(), 12*GUI_SCALE, false);
		formattingExamples = new TextLine(Fonts.PIXEL_FONT, formattingExamples.getText(), 12*GUI_SCALE, false);
		formattingColor = new TextLine(Fonts.PIXEL_FONT, formattingColor.getText(), 12*GUI_SCALE, false);
		formattingColorExamples = new TextLine(Fonts.PIXEL_FONT, formattingColorExamples.getText(), 12*GUI_SCALE, false);
	}

	@Override
	public void render() {
		nameField.render();
		done.render();
		Logger.info(prompt.getTextWidth());
		prompt.render(Window.getWidth()/2 - prompt.getTextWidth()/2, 10*GUI_SCALE);
		formatting.render(Window.getWidth()/2 - formatting.getTextWidth()/2, 40*GUI_SCALE);
		formattingExamples.render(Window.getWidth()/2 - formattingExamples.getTextWidth()/2, 60*GUI_SCALE);
		formattingColor.render(Window.getWidth()/2 - formattingColor.getTextWidth()/2, 80*GUI_SCALE);
		formattingColorExamples.render(Window.getWidth()/2 - formattingColorExamples.getTextWidth()/2, 100*GUI_SCALE);
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
