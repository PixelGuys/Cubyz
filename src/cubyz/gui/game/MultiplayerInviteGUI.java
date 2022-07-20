package cubyz.gui.game;

import cubyz.Constants;
import cubyz.client.ClientSettings;
import cubyz.client.Cubyz;
import cubyz.gui.MenuGUI;
import cubyz.gui.components.*;
import cubyz.gui.components.Button;
import cubyz.gui.components.Component;
import cubyz.gui.components.Label;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.rendering.Graphics;
import cubyz.rendering.Window;
import cubyz.rendering.text.Fonts;
import cubyz.utils.DiscordIntegration;
import cubyz.utils.Logger;
import cubyz.utils.datastructures.SimpleList;
import cubyz.utils.translate.TextKey;

import java.awt.*;
import java.awt.datatransfer.Clipboard;
import java.awt.datatransfer.StringSelection;

import static cubyz.client.ClientSettings.GUI_SCALE;

public class MultiplayerInviteGUI extends MenuGUI {

	private final Thread backgroundThread;

	private final Button copy = new Button();
	private final Label ip = new Label();
	private final Label prompt = new Label();
	private final Label enterIP_label = new Label();
	private final TextInput enterIP_text = new TextInput();
	private final Button enterIP_button = new Button();

	private final ScrollingContainer container = new ScrollingContainer();

	private final SimpleList<Button> cancelButtons = new SimpleList<>(new Button[64]);
	private final SimpleList<Label> ips = new SimpleList<>(new Label[64]);
	private final SimpleList<Label> names = new SimpleList<>(new Label[64]);

	public MultiplayerInviteGUI() {
		backgroundThread = new Thread(() -> {
			if(!Cubyz.world.connectionManager.online) {
				Cubyz.world.connectionManager.makeOnline();
			}
			ip.setText(Cubyz.world.connectionManager.externalIPPort.replaceAll(":"+Constants.DEFAULT_PORT, ""));
		}, "Search for IP");
		backgroundThread.start();
	}

	public void refresh() {
		container.clear();
		cancelButtons.clear();
		ips.clear();
		names.clear();
		for(UDPConnection conn : Server.connectionManager.connections.toArray(new UDPConnection[0])) {
			if(conn instanceof User) {
				User user = (User)conn;
				Button cancel = new Button();
				cancel.setText(user.name == null ? "gui.cubyz.general.cancel" : "gui.cubyz.multiplayer.kick");
				cancel.setOnAction(() -> {
					user.disconnect();
					synchronized(user) {
						if(user.waitingThread != null) {
							user.waitingThread.interrupt();
						}
					}
					refresh();
				});
				cancelButtons.add(cancel);
				Label ip = new Label();
				ip.setText(user.ipPort);
				ip.setFont(Fonts.PIXEL_FONT);
				ip.setTextAlign(Component.ALIGN_TOP_LEFT);
				ips.add(ip);
				Label name = new Label();
				name.setText(user.name == null ? "???" : user.name);
				name.setFont(Fonts.PIXEL_FONT);
				name.setTextAlign(Component.ALIGN_TOP_LEFT);
				names.add(name);

				container.add(cancel);
				container.add(ip);
				container.add(name);
			}
		}
		updateGUIScale();
	}

	@Override
	public void init() {
		DiscordIntegration.setStatus("Multiplayer");

		prompt.setText(TextKey.createTextKey("gui.cubyz.multiplayer.invite_prompt"));
		prompt.setFont(Fonts.PIXEL_FONT);

		enterIP_label.setText(TextKey.createTextKey("IP"));
		enterIP_label.setFont(Fonts.PIXEL_FONT);
		enterIP_label.setTextAlign(Component.ALIGN_TOP_LEFT);
		enterIP_text.setText(ClientSettings.lastUsedIPAddress);
		enterIP_text.setFont(Fonts.PIXEL_FONT, 16);
		enterIP_button.setText(TextKey.createTextKey("gui.cubyz.multiplayer.invite"));
		enterIP_button.setOnAction(() -> {
			ClientSettings.lastUsedIPAddress = enterIP_text.getText().trim();
			ClientSettings.save();
			new Thread(() -> {
				try {
					Server.connect(new User(Server.connectionManager, enterIP_text.getText().trim()));
				} catch(InterruptedException e) {
				} catch(Exception e) {
					Logger.error(e);
				}
			}, "Invite "+enterIP_text.getText().trim()).start();
			try {
				Thread.sleep(10);
			} catch(InterruptedException e) {}
			refresh();
		});

		ip.setFont(Fonts.PIXEL_FONT);

		copy.setText(TextKey.createTextKey("gui.cubyz.multiplayer.copy_ip"));
		copy.setOnAction(() -> {
			StringSelection selection = new StringSelection(ip.getText().getTranslateKey());
			Clipboard clipboard = Toolkit.getDefaultToolkit().getSystemClipboard();
			clipboard.setContents(selection, selection);
		});

		container.setInteriorAlign(Component.ALIGN_TOP);

		refresh();
	}

	@Override
	public void updateGUIScale() {
		prompt.setBounds(0, 20*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		prompt.setFontSize(12*GUI_SCALE);

		ip.setBounds(0, 50*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		ip.setFontSize(16*GUI_SCALE);

		copy.setBounds(-50*GUI_SCALE, 60*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		copy.setFontSize(16*GUI_SCALE);

		enterIP_label.setBounds(-150*GUI_SCALE, 90*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		enterIP_label.setFontSize(16*GUI_SCALE);

		enterIP_text.setBounds(-100*GUI_SCALE, 90*GUI_SCALE, 180*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		enterIP_text.setFontSize(16*GUI_SCALE);

		enterIP_button.setBounds(100*GUI_SCALE, 90*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP);
		enterIP_button.setFontSize(16*GUI_SCALE);

		container.setBounds(20*GUI_SCALE, 120*GUI_SCALE, Window.getWidth() - 40*GUI_SCALE, Window.getHeight() - 100*GUI_SCALE, Component.ALIGN_TOP_LEFT);

		int y = 0;
		for(int i = 0; i < cancelButtons.size; i++) {
			cancelButtons.array[i].setBounds(101*GUI_SCALE, y*GUI_SCALE, 100*GUI_SCALE, 20*GUI_SCALE, Component.ALIGN_TOP_RIGHT);
			cancelButtons.array[i].setFontSize(16*GUI_SCALE);
			ips.array[i].setBounds(1*GUI_SCALE, y*GUI_SCALE, 0, 20*GUI_SCALE, Component.ALIGN_TOP_LEFT);
			ips.array[i].setFontSize(16*GUI_SCALE);
			names.array[i].setBounds(120*GUI_SCALE, y*GUI_SCALE, 0, 20*GUI_SCALE, Component.ALIGN_TOP_LEFT);
			names.array[i].setFontSize(16*GUI_SCALE);
			y += 30;
		}
	}

	@Override
	public void render() {
		Graphics.setColor(0x7F7FA0);
		Graphics.fillRect(20*GUI_SCALE, 10*GUI_SCALE, Window.getWidth() - 40*GUI_SCALE, Window.getHeight() - 30*GUI_SCALE);
		prompt.render();
		ip.render();
		copy.render();
		container.render();
		enterIP_label.render();
		enterIP_text.render();
		enterIP_button.render();
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
	}
}
