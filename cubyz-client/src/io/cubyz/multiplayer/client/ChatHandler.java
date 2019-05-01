package io.cubyz.multiplayer.client;

import java.util.ArrayList;

public abstract class ChatHandler {

	public abstract ArrayList<String> getAllMessages();
	public abstract void send(String msg);
	
}
