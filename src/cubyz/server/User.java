package cubyz.server;

import cubyz.client.Cubyz;
import cubyz.multiplayer.Protocols;
import cubyz.multiplayer.UDPConnection;
import cubyz.utils.Logger;
import cubyz.utils.Zipper;
import cubyz.world.entity.Entity;
import pixelguys.json.JsonObject;
import pixelguys.json.JsonParser;

import java.io.*;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/*
*   A User
* */
public class User extends UDPConnection {

	public User(String ip, int sendPort, int receivePort) throws IOException {
		super(ip, sendPort, receivePort);
		doHandShake();
	}
	/*public void receiveJSON(JsonObject json){
		String type = json.getString("type", "unknown type");
		if (type.equals("clientInformation")){
			String name     = json.getString("name", "unnamed");
			String version  =  json.getString("version", "unknown");

			Logger.info("User joined: "+name+", who is using version: "+version);
		}
	}*/
	
	private void doHandShake() {
		Protocols.HANDSHAKE.serverSide(this);
		/*try {
            JsonObject json = JsonParser.parseObjectFromBufferedReader(in, "");
			String type = json.getString("type", "unknown type");
			if (type.equals("clientInformation")){
				String name     = json.getString("name", "unnamed");
				String version  =  json.getString("version", "unknown");
	
				Logger.info("User joined: "+name+", who is using version: "+version);
			}
			sendWorldAssets();
			sendInitialPlayerData();
		} catch (Exception e) {
			Logger.error(e);
		}*/
	}

	public void sendWorldAssets(){
		/*JsonObject head = new JsonObject();
		head.put("type","worldAssets");
		head.writeObjectToStream(out);

		String assetPath = "saves/" + Server.world.getName() + "/assets/";
		Zipper.pack(assetPath,outStream); //potential bug: Stream doesnt know the file size
		try {
			outStream.write(0);
		} catch(IOException e) {
			Logger.error(e);
		}*/
	}

	public void sendInitialPlayerData(){
		/*JsonObject head = new JsonObject();
		head.put("type","initialPlayerData");
		head.put("position", Entity.saveVector(Server.world.player.getPosition()));
		head.put("inventory", Server.world.player.getInventory().save());
		head.writeObjectToStream(out);*/
	}
}
