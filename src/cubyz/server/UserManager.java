package cubyz.server;

/*
* Coordinates Users
* */

import cubyz.utils.Logger;

import java.net.*;
import java.io.*;
import java.util.ArrayList;

public class UserManager extends Thread{
	final int port = 42069;

	//private ServerSocket serverSocket;
	public boolean running = true;

	public ArrayList<User> users = new ArrayList<>();

	@Override
	public void run() {
		//try {
			//serverSocket = new ServerSocket(port);
			//while (running){
				try {
					User user = new User("localhost", 5678, 5679);
					users.add(user);
				} catch (IOException e) {
					Logger.error(e.toString());
				}
			//}
		//} catch (IOException e) {
		//	Logger.error(e.toString());
		//}
	}

	public void dispose() {
		//serverSocket.close();
		for(User user : users) {
			user.interrupt();
		}
	}
}
