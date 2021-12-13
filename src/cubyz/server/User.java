package cubyz.server;

import cubyz.utils.Logger;
import cubyz.utils.json.JsonObject;
import cubyz.utils.json.JsonParser;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;

/*
*   A User
* */
public class User {
    private Socket clientSocket;
    private PrintWriter out;
    private BufferedReader in;



    public User(Socket clientSocket) throws IOException {
        this.clientSocket = clientSocket;

        out = new PrintWriter(clientSocket.getOutputStream(), true);
        in = new BufferedReader(new InputStreamReader(clientSocket.getInputStream()));

        while (!clientSocket.isClosed()) {
            receiveJSON(JsonParser.parseObjectFromStream(in));
        }
    }
    public void receiveJSON(JsonObject json){
        String type = json.getString("type", "unknown type");
        if (type.equals("clientinformation")){
            String name     = json.getString("name", "unnamed");
            String version  =  json.getString("version", "unknown");

            Logger.info("User joined: "+name+", who is using version: "+version);
        }
    }
    public void dispose() throws IOException {
        in.close();
        out.close();
        clientSocket.close();
    }
}
