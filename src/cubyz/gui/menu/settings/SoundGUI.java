package cubyz.gui.menu.settings;

import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.audio.MusicManager;
import cubyz.gui.components.Button;
import cubyz.gui.components.CheckBox;
import cubyz.gui.components.Component;
import cubyz.utils.translate.TextKey;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class SoundGUI extends MenuGUI {

    private Button done = new Button();
    private CheckBox musicOnOff = new CheckBox();

    @Override
    public void init() {

        done.setText(TextKey.createTextKey("gui.cubyz.settings.done"));

        done.setOnAction(() -> {
            Cubyz.gameUI.back();
        });

        musicOnOff.setLabel(TextKey.createTextKey("gui.cubyz.settings.musicOnOff"));
        musicOnOff.setSelected(ClientSettings.musicOnOff);
        musicOnOff.setOnAction(() -> {
            ClientSettings.musicOnOff = musicOnOff.isSelected();
            if (!musicOnOff.isSelected()) {
                MusicManager.stop();
            }
        });

        updateGUIScale();
    }

    @Override
    public void updateGUIScale() {
        done.setBounds(-125 * GUI_SCALE, 40 * GUI_SCALE, 250 * GUI_SCALE, 25 * GUI_SCALE, Component.ALIGN_BOTTOM);
        done.setFontSize(16f * GUI_SCALE);

        musicOnOff.setBounds(-125 * GUI_SCALE, 40 * GUI_SCALE, 16 * GUI_SCALE, 16 * GUI_SCALE, Component.ALIGN_TOP);
        musicOnOff.getLabel().setFontSize(16f * GUI_SCALE);
    }

    @Override
    public void render() {
        done.render();
        musicOnOff.render();
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
