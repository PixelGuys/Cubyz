package io.spacycubyd.utils;

import java.util.Random;

import club.minnced.discord.rpc.DiscordEventHandlers;
import club.minnced.discord.rpc.DiscordEventHandlers.OnReady;
import io.spacycubyd.client.SpacyCubyd;
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
		String appID = "527033701343952896"; //NOTE: Normal > 527033701343952896
		String steamID = "";
		DiscordEventHandlers handlers = new DiscordEventHandlers();
		handlers.ready = new OnReady() {

			@Override
			public void accept(DiscordUser arg0) {
				System.out.println("Ready as user " + arg0.username);
			}
			
		};
		handlers.joinGame = (secret) -> {
			String serverIP = secret.split(":")[0]; //NOTE: Normal > 0
			int serverPort = Integer.parseInt(secret.split(":")[1]);
			System.out.println("Attempting to join server " + serverIP + " at port " + serverPort);
			SpacyCubyd.requestJoin(serverIP, serverPort);
		};
		
		handlers.joinRequest = (user) -> {
			System.out.println("Join request from " + user.toString() + ", " + user.username);
			if (SpacyCubyd.serverOnline < SpacyCubyd.serverCapacity) {
				lib.Discord_Respond(user.userId, DiscordRPC.DISCORD_REPLY_YES);
			} else {
				lib.Discord_Respond(user.userId, DiscordRPC.DISCORD_REPLY_NO);
			}
		};
		String userDir = System.getProperty("user.dir");
		String javaExec = System.getProperty("java.home") + "/bin/java.exe";
		String classpath = System.getProperty("java.class.path");
		lib.Discord_Initialize(appID, handlers, false, steamID);
		
		String path = javaExec + " -cp " + classpath + " -jar " + userDir + "/cubz.jar";
		SpacyCubyd.log.fine("Registered launch path as " + path);
		lib.Discord_Register(appID, path);
		
		presence = new DiscordRichPresence();
		presence.largeImageKey = "cubz_logo";
		presence.state = "Multiplayer";
		presence.largeImageText = SpacyCubyd.serverIP;
		
		presence.joinSecret = SpacyCubyd.serverIP + ":" + SpacyCubyd.serverPort;
		presence.partySize = SpacyCubyd.serverOnline;
		presence.partyMax = SpacyCubyd.serverCapacity;
		
		presence.partyId = generatePartyID();
		
		setStatus("No status.");
		
		lib.Discord_UpdatePresence(presence);
		
		worker = new Thread(() -> {
            while (!Thread.currentThread().isInterrupted()) {
                lib.Discord_RunCallbacks();
                try {
                    Thread.sleep(2000L); //NOTE: Normal > 2000L
                } catch (InterruptedException ignored) {
                	break;
                }
            }
        });
		worker.setName("RPC-Callback-Handler");
		worker.start();
		SpacyCubyd.log.info("Discord RPC integration opened!");
	}
	
	public static boolean isEnabled() {
		return true;
	}
	
	public static void updateState() {
		if (SpacyCubyd.isIntegratedServer) {
			presence.state = "Singleplayer";
			//presence.joinSecret = null;
			//presence.partySize = 0; //NOTE: Normal > 0
		}
		else {
			if (SpacyCubyd.isOnlineServerOpened) {
				presence.state = "Join me ;)";
				presence.partyMax = 50; // temporary || NOTE: Normal > 50
			} else {
				presence.state = "Multiplayer";
				presence.partyMax = 50; // temporary || NOTE: Normal > 50
			}
		}
		DiscordRPC.INSTANCE.Discord_UpdatePresence(presence);
	}
	
	public static void setStatus(String status) {
		presence.details = status;
		updateState();
	}
	
	public static void closeRPC() {
		DiscordRPC lib = DiscordRPC.INSTANCE;
		if (worker != null)
			worker.interrupt();
		lib.Discord_Shutdown();
	}
	
}
