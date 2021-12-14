package cubyz.utils;

import java.util.Random;

import club.minnced.discord.rpc.DiscordEventHandlers;
import club.minnced.discord.rpc.DiscordEventHandlers.OnReady;
import cubyz.client.Cubyz;
import cubyz.client.GameLauncher;
import cubyz.gui.ToastManager;
import cubyz.gui.ToastManager.Toast;
import club.minnced.discord.rpc.DiscordRPC;
import club.minnced.discord.rpc.DiscordRichPresence;
import club.minnced.discord.rpc.DiscordUser;

public class DiscordIntegration {

	static DiscordRichPresence presence;
	static Thread worker;
	
	public static String generatePartyID() {
		return Integer.toHexString(new Random().nextInt());
	}
	
	public static void startRPC() {
		DiscordRPC lib = DiscordRPC.INSTANCE;
		String appID = "527033701343952896";
		DiscordEventHandlers handlers = new DiscordEventHandlers();
		handlers.errored = handlers.disconnected = new DiscordEventHandlers.OnStatus() {

			@Override
			public void accept(int errorCode, String message) {
				System.err.println(errorCode + ": " + message);
				ToastManager.queuedToasts.push(new Toast("Discord Integration", "An error occured: " + message));
			}
			
		};
		handlers.ready = new OnReady() {
			@Override
			public void accept(DiscordUser user) {
				ToastManager.queuedToasts.push(new Toast("Discord Integration", "Hello " + user.username + " !"));
				System.out.println("Linked!");
			}
			
		};
		handlers.joinGame = (secret) -> {
			String serverIP = secret.split(":")[0];
			int serverPort = Integer.parseInt(secret.split(":")[1]);
			System.out.println("Attempting to join server " + serverIP + " at port " + serverPort);
			//GameLauncher.logic.requestJoin(serverIP, serverPort);
		};
		
		handlers.joinRequest = (user) -> {
			ToastManager.queuedToasts.push(new Toast("Discord Integration", "Join request from " + user.username));
			if (GameLauncher.logic.serverOnline < GameLauncher.logic.serverCapacity) {
				lib.Discord_Respond(user.userId, DiscordRPC.DISCORD_REPLY_YES);
			} else {
				lib.Discord_Respond(user.userId, DiscordRPC.DISCORD_REPLY_NO);
			}
		};
		String javaExec = System.getProperty("java.home") + "/bin/java" + (System.getProperty("os.name").contains("windows") ? ".exe" : "");
		String classpath = System.getProperty("java.class.path");
		lib.Discord_Initialize(appID, handlers, false, null);
		
		String path = javaExec + " -cp " + classpath + " cubyz.client.GameLauncher";
		Logger.info("Registered launch path as " + path);
		lib.Discord_Register(appID, path);
		lib.Discord_RunCallbacks();
		
		presence = new DiscordRichPresence();
		presence.largeImageKey = "cubz_logo";
		//presence.largeImageText = Cubyz.serverIP;
		
		//presence.joinSecret = Cubyz.serverIP + ":" + Cubyz.serverPort;
		//presence.partySize = Cubyz.serverOnline;
		//presence.partyMax = Cubyz.serverCapacity;
		
		//presence.partyId = generatePartyID();
		
		
		worker = new Thread(() -> {
            while (!Thread.currentThread().isInterrupted()) {
                lib.Discord_RunCallbacks();
                try {
                    Thread.sleep(2000);
                } catch (InterruptedException ignored) {
                	break;
                }
            }
        });
		worker.setName("RPC-Callback-Handler");
		worker.start();
		Logger.info("Discord RPC integration opened!");
		ToastManager.queuedToasts.add(new Toast("Discord Integration", "Linking.."));
		setStatus("On Main Menu");
	}
	
	public static boolean isEnabled() {
		return worker != null;
	}
	
	public static void updateState() {
		if (Cubyz.world != null) {
			if (GameLauncher.logic.isIntegratedServer) {
				presence.details = "Singleplayer";
			} else {
				if (GameLauncher.logic.isOnlineServerOpened) {
					presence.details = "Join me ;)";
					presence.partyMax = 50; // temporary
				} else {
					presence.details = "Multiplayer";
					presence.partyMax = 50; // temporary
				}
			}
		} else {
			presence.details = null;
		}
		DiscordRPC.INSTANCE.Discord_UpdatePresence(presence);
	}
	
	public static void setStatus(String status) {
		if (isEnabled()) {
			presence.state = status;
			updateState();
		}
	}
	
	public static void closeRPC() {
		DiscordRPC lib = DiscordRPC.INSTANCE;
		if (worker != null)
			worker.interrupt();
		worker = null;
		lib.Discord_Shutdown();
	}
	
}
