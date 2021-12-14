package cubyz.clientSide;

import cubyz.Constants;
import cubyz.utils.Logger;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;
import cubyz.utils.json.JsonString;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;

public class ServerConnection {
    private Socket clientSocket;
    private PrintWriter out;
    private BufferedReader in;

    public ServerConnection(String fullip, String name){
        String ip = "localhost";
        int port = 42069;

        if (fullip.indexOf(':')==-1)
            //"ip"
            ip = fullip;
        else{
            //"ip:port"
            fullip.substring(0, fullip.indexOf(':'));
            fullip.substring(fullip.indexOf(':')+1);
        }

        //connect
        try {
            //TODO: Might want to use SSL or something similar to encode the message
            clientSocket = new Socket(ip, port);
            out = new PrintWriter(clientSocket.getOutputStream(), true);
            in = new BufferedReader(new InputStreamReader(clientSocket.getInputStream()));
        } catch (IOException e) {
            Logger.error(e);
        }

        try {
            JsonObject jsonObject = new JsonObject();
            jsonObject.put("type", "clientinformation");
            jsonObject.put("version", Constants.GAME_VERSION);
            jsonObject.put("name", name);

            jsonObject.writeObjectToStream(out);
        } catch (Exception e) {
            e.printStackTrace();
        }

    }
}
