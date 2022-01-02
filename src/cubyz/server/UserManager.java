package cubyz.server;

/*
* Coordinates Users
* */

import cubyz.utils.Logger;

import java.net.*;
import java.io.*;

public class UserManager extends Thread{
	final int port = 42069;

	private ServerSocket serverSocket;
	public boolean running = true;

	@Override
	public void run() {
		try {
			serverSocket = new ServerSocket(port);
			while (running){
				try {
					User user = new User(serverSocket.accept());
				} catch (IOException e) {
					Logger.error(e.toString());
				}
			}
		} catch (IOException e) {
			Logger.error(e.toString());
		}
	}

	public void dispose() throws IOException {
		serverSocket.close();
	}
}
