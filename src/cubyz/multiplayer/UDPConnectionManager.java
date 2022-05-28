package cubyz.multiplayer;

import cubyz.utils.Logger;

import java.io.IOException;
import java.net.*;
import java.util.ArrayList;

public final class UDPConnectionManager extends Thread {
	private final DatagramSocket socket;
	private final DatagramPacket receivedPacket;
	private final ArrayList<UDPConnection> connections = new ArrayList<>();

	public UDPConnectionManager(int receivePort) {
		// Connect
		DatagramSocket socket = null;
		try {
			//TODO: Might want to use SSL or something similar to encode the message
			socket = new DatagramSocket(receivePort);
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
		connections.add(connection);
	}

	public void removeConnection(UDPConnection connection) {
		connections.remove(connection);
	}

	public void cleanup() {
		for(UDPConnection connection : connections) {
			// TODO: Send a final message to the connected client: connection.cleanup();
		}
		interrupt();
		try {
			join();
		} catch(InterruptedException e) {
			Logger.error(e);
		}
	}

	private UDPConnection findConnection(InetAddress addr) {
		for(UDPConnection connection : connections) {
			if(connection.receiver.equals(addr)) {
				return connection;
			}
		}
		throw new IllegalStateException("Unknown connection from address: " + addr);
	}

	@Override
	public void run() {
		assert Thread.currentThread() == this : "UDPConnectionManager.run() shouldn't be called by anyone.";
		try {
			socket.setSoTimeout(100);
			long lastTime = System.currentTimeMillis();
			while (true) {
				try {
					socket.receive(receivedPacket);
					byte[] data = receivedPacket.getData();
					int len = receivedPacket.getLength();
					findConnection(receivedPacket.getAddress()).receive(data, len);
				} catch(SocketTimeoutException e) {
					// No message within the last ~100 ms.
					// TODO: Add a counter that breaks connection if there was no message for a longer time.
				}

				// Send a keep-alive packet roughly every 100 ms:
				if(System.currentTimeMillis() - lastTime > 100) {
					lastTime = System.currentTimeMillis();
					for(UDPConnection connection : connections) {
						connection.sendKeepAlive();
					}
				}
			}
		} catch (Exception e) {
			Logger.crash(e);
		}
	}
}
