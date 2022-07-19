package cubyz.multiplayer.protocols;

import cubyz.Constants;
import cubyz.multiplayer.client.ServerConnection;
import cubyz.multiplayer.Protocol;
import cubyz.multiplayer.UDPConnection;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.Logger;
import cubyz.utils.Utils;
import cubyz.utils.Zipper;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;

public class HandshakeProtocol extends Protocol {
	HashMap<UDPConnection, Byte> state = new HashMap<>();
	private static final byte STEP_START = 0;
	private static final byte STEP_USER_DATA = 1;
	private static final byte STEP_ASSETS = 2;
	private static final byte STEP_SERVER_DATA = 3;

	public HandshakeProtocol() {
		super((byte)1, true);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		if(state.get(conn) == data[offset] - 1) {
			state.put(conn, data[offset]);
			switch(data[offset]) {
				case STEP_USER_DATA:
					JsonObject json = JsonParser.parseObjectFromString(new String(data, offset+1, length - 1, StandardCharsets.UTF_8));
					String name = json.getString("name", "unnamed");
					String version = json.getString("version", "unknown");

					Logger.info("User joined: " + name + ", who is using version: " + version);
					// TODO: Send the world data.
					ByteArrayOutputStream out = new ByteArrayOutputStream();
					out.write(STEP_ASSETS);
					Zipper.pack("saves/" + Server.world.getName() + "/assets/", out);
					conn.send(this, out.toByteArray());

					JsonObject jsonObject = new JsonObject();
					((User)conn).initPlayer(name);
					jsonObject.put("player", ((User)conn).player.save());
					jsonObject.put("player_id", ((User)conn).player.id);
					jsonObject.put("blockPalette", Server.world.blockPalette.save());
					JsonObject spawn = new JsonObject();
					spawn.put("x", Server.world.spawn.x);
					spawn.put("y", Server.world.spawn.y);
					spawn.put("z", Server.world.spawn.z);
					jsonObject.put("spawn", spawn);
					byte[] string = jsonObject.toString().getBytes(StandardCharsets.UTF_8);
					byte[] outData = new byte[string.length + 1];
					outData[0] = STEP_SERVER_DATA;
					System.arraycopy(string, 0, outData, 1, string.length);
					state.put(conn, STEP_SERVER_DATA);
					conn.send(this, outData);
					state.remove(conn); // Handshake is done.
					conn.handShakeComplete = true;
					synchronized(conn) { // Notify the waiting server thread.
						conn.notifyAll();
					}
					break;
				case STEP_ASSETS:
					Logger.info("Received assets.");
					ByteArrayInputStream in = new ByteArrayInputStream(data, offset+1, length);
					String serverAssets = "serverAssets";
					Utils.deleteDirectory(new File(serverAssets).toPath());
					Zipper.unpack(serverAssets, in);
					break;
				case STEP_SERVER_DATA:
					assert conn instanceof ServerConnection : "Trying to do client handshake from the server side.";
					json = JsonParser.parseObjectFromString(new String(data, offset+1, length - 1, StandardCharsets.UTF_8));
					((ServerConnection)conn).world.finishHandshake(json);
					state.remove(conn); // Handshake is done.
					conn.handShakeComplete = true;

					synchronized(conn) { // Notify the waiting client thread.
						conn.notifyAll();
					}
					break;
				default:
					Logger.error("Unknown state in HandShakeProtocol " + data[offset]);
			}
		} else {
			// Ignore packages that refer to an unexpected state. Normally those might be packages that were resent by the other side.
		}
	}

	public void serverSide(UDPConnection conn) {
		state.put(conn, STEP_START);
	}

	public void clientSide(UDPConnection conn, String name) throws InterruptedException {
		try {
			Thread.sleep(10);
		} catch(Exception e) {
			Logger.error(e);
		}
		JsonObject jsonObject = new JsonObject();
		jsonObject.put("version", Constants.GAME_VERSION);
		jsonObject.put("name", name);
		byte[] string = jsonObject.toString().getBytes(StandardCharsets.UTF_8);
		byte[] out = new byte[string.length + 1];
		out[0] = STEP_USER_DATA;
		System.arraycopy(string, 0, out, 1, string.length);
		conn.send(this, out);
		state.put(conn, STEP_USER_DATA);

		synchronized(conn) {
			conn.wait();
		}
	}
}
