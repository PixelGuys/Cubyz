package cubyz.multiplayer;

import cubyz.utils.Logger;

import java.io.IOException;
import java.net.*;
import java.util.ArrayList;

public final class UDPConnectionManager extends Thread {
	private final DatagramSocket socket;
	private final DatagramPacket receivedPacket;
	private final ArrayList<UDPConnection> connections = new ArrayList<>();
	private volatile boolean running = true;

	public UDPConnectionManager(int localPort) {
		// Connect
		DatagramSocket socket = null;
		try {
			//TODO: Might want to use SSL or something similar to encode the message
			socket = new DatagramSocket(localPort);
		} catch (SocketException e) {
			Logger.error(e);
		}
		this.socket = socket;

		receivedPacket = new DatagramPacket(new byte[65536], 65536);

		start();
	}

	public void send(DatagramPacket packet) {
		try {
			socket.send(packet);
		} catch(IOException e) {
			Logger.error(e);
		}
	}

	public void addConnection(UDPConnection connection) {
		synchronized(connections) {
			connections.add(connection);
		}
	}

	public void removeConnection(UDPConnection connection) {
		synchronized(connections) {
			connections.remove(connection);
		}
	}

	public void cleanup() {
		while(!connections.isEmpty()) {
			connections.get(0).disconnect();
		}
		running = false;
		if(Thread.currentThread() != this) {
			interrupt();
			try {
				join();
			} catch(InterruptedException e) {
				Logger.error(e);
			}
		}
		socket.close();
	}

	private UDPConnection findConnection(InetAddress addr, int port) {
		for(UDPConnection connection : connections) {
			if(connection.remoteAddress.equals(addr) && connection.remotePort == port) {
				return connection;
			}
		}
		Logger.error("Unknown connection from address: " + addr+":"+port);
		return null;
	}

	@Override
	public void run() {
		assert Thread.currentThread() == this : "UDPConnectionManager.run() shouldn't be called by anyone.";
		try {
			socket.setSoTimeout(100);
			long lastTime = System.currentTimeMillis();
			while (running) {
				try {
					socket.receive(receivedPacket);
					byte[] data = receivedPacket.getData();
					int len = receivedPacket.getLength();
					UDPConnection conn = findConnection(receivedPacket.getAddress(), receivedPacket.getPort());
					if(conn != null) {
						conn.receive(data, len);
					}
				} catch(SocketTimeoutException e) {
					// No message within the last ~100 ms.
					// TODO: Add a counter that breaks connection if there was no message for a longer time.
				}

				// Send a keep-alive packet roughly every 100 ms:
				if(System.currentTimeMillis() - lastTime > 100) {
					lastTime = System.currentTimeMillis();
					for(UDPConnection connection : connections.toArray(new UDPConnection[0])) {
						connection.sendKeepAlive();
					}
				}
			}
		} catch (Exception e) {
			Logger.crash(e);
		}
	}
}
