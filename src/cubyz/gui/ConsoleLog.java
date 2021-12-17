package cubyz.gui;

import cubyz.gui.components.Component;
import cubyz.gui.components.ScrollingContainer;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class ConsoleLog extends MenuGUI {

    private final ScrollingContainer container = new ScrollingContainer();

    private final int DEBUG = 0xffffff;
    private final int WARN = 0xffff00;
    private final int ERROR = 0xff0000;

    @Override
    public void init() {
        this.container.clear();
        this.read();
        this.updateGUIScale();
        this.container.scrollToEnd();
    }

    @Override
    public void updateGUIScale() {
        int y = 10;
        for (Component label : this.container.getChildren()) {
            label.setBounds(20 * GUI_SCALE, (y + 4) * GUI_SCALE, 0, 24 * GUI_SCALE, Component.ALIGN_TOP_LEFT);
            y += 10;
        }
        this.container.setBounds(0, 0, Window.getWidth(), Window.getHeight(), Component.ALIGN_TOP_LEFT);
    }

    @Override
    public void render() {
        Graphics.setColor(0x000000, 200);
        Graphics.fillRect(0, 0, Window.getWidth(), Window.getHeight());
        this.container.render();
    }

    @Override
    public void close() {
        super.close();
        this.container.clear();
    }

    @Override
    public boolean doesPauseGame() {
        return true;
    }

    @Override
    public boolean ungrabsMouse() {
        return true;
    }

    private void read() {
        try {
            int lastLogLevel = DEBUG;
            for (String line : Files.readAllLines(Paths.get("./logs/latest.log"))) {
                if (line.contains("| warning |")) {
                    lastLogLevel = WARN;
                } else if (line.contains("| error |") || line.contains("| crash |")) {
                    lastLogLevel = ERROR;
                } else if (line.contains("| info |") || line.contains("| debug |")) {
                    lastLogLevel = DEBUG;
                }
                log(line, lastLogLevel);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private void log(String msg, int logLevel) {
        this.container.add(new LogLabel(msg, logLevel));
    }

    private static class LogLabel extends Component {

        private final String rawText;
        private final int color;

        public LogLabel(String rawText, int color) {
            this.rawText = rawText;
            this.color = color;
        }

        @Override
        public void render(int x, int y) {
            Graphics.setColor(color);
            Graphics.setFont(Fonts.PIXEL_FONT, 8f * GUI_SCALE);
            Graphics.drawText(x, y, rawText);
        }
    }
}
