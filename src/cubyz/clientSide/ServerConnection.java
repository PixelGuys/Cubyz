package cubyz.clientSide;

import cubyz.Constants;
import cubyz.utils.Logger;
import cubyz.utils.Zipper;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;

import java.io.*;
import java.net.Socket;

public class ServerConnection extends Thread{
	private Socket clientSocket;
	private PrintWriter out;
	private BufferedReader in;

	private OutputStream outStream;
	private InputStream inStream;

	public ServerConnection(String fullip, String name, String serverName){
		String ip = "localhost";
		int port = 42069;

		if (fullip.indexOf(':')==-1)
			ip = fullip; //"ip"
		else{
			//"ip:port"
			ip = fullip.substring(0, fullip.indexOf(':'));
			port = Integer.parseInt(fullip.substring(fullip.indexOf(':')+1));
		}
		
		Logger.debug(ip+":"+port);

		//connect
		try {
			//TODO: Might want to use SSL or something similar to encode the message
			clientSocket = new Socket(ip, port);

			outStream = clientSocket.getOutputStream();
			inStream = clientSocket.getInputStream();

			out = new PrintWriter(outStream, true);
			in = new BufferedReader(new InputStreamReader(inStream));
		} catch (IOException e) {
			Logger.error(e);
		}
		
		doHandShake(name, serverName);

		start();
	}
	
	@Override
	public void run(){
		try {
			while (!clientSocket.isClosed()) {
				receiveJSON(JsonParser.parseObjectFromStream(in));
			}
		} catch (IOException e) {
			Logger.error(e);
		}
	}
	
	private void doHandShake(String name, String serverName) {
		try {
			JsonObject jsonObject = new JsonObject();
			jsonObject.put("type", "clientInformation");
			jsonObject.put("version", Constants.GAME_VERSION);
			jsonObject.put("name", name);

			jsonObject.writeObjectToStream(out);

            JsonObject json = JsonParser.parseObjectFromStream(in);
            String type = json.getString("type", "unknown type");
            if (type.equals("worldAssets")){
                Zipper.unpack("serverAssets/"+serverName+"/assets/", inStream);
                Logger.info("Server World Assets received");
            } else {
                Logger.error("Invalid handshake\n"+json);
            }
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
	
	private void receiveJSON(JsonObject json){
		String type = json.getString("type", "unknown type");
		
	}
}
