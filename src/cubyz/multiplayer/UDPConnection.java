package cubyz.multiplayer;

import cubyz.Constants;
import cubyz.multiplayer.server.Server;
import cubyz.multiplayer.server.User;
import cubyz.utils.Logger;
import cubyz.utils.datastructures.IntSimpleList;
import cubyz.utils.datastructures.SimpleList;
import cubyz.utils.math.Bits;

import java.io.IOException;
import java.net.*;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicInteger;

public class UDPConnection {
	private static final int MAX_PACKET_SIZE = 65507; // max udp packet size
	private static final int IMPORTANT_HEADER_SIZE = 6;
	private static final int MAX_IMPORTANT_PACKAGE_SIZE = 1500 - 20 - 8 - IMPORTANT_HEADER_SIZE; // Ethernet MTU minus IP header minus udp header minus header size

	private final UDPConnectionManager manager;

	final InetAddress remoteAddress;
	int remotePort;
	boolean bruteforcingPort;
	private int bruteForcedPortRange = 0;

	private final AtomicInteger messageID = new AtomicInteger(0);
	private final SimpleList<UnconfirmedPackage> unconfirmedPackets = new SimpleList<>(new UnconfirmedPackage[1024]);
	private final IntSimpleList[] receivedPackets = new IntSimpleList[]{new IntSimpleList(), new IntSimpleList(), new IntSimpleList()}; // Resend the confirmation 3 times, to make sure the server doesn't need to resend stuff.
	private final ReceivedPackage[] lastReceivedPackets = new ReceivedPackage[65536];

	int lastIncompletePacket = 0;


	int lastKeepAliveSent = 0, lastKeepAliveReceived = 0, otherKeepAliveReceived = 0;

	protected boolean disconnected = false;
	public boolean handShakeComplete = false;

	public long lastConnection = System.currentTimeMillis();

	public UDPConnection(UDPConnectionManager manager, String ipPort) {
		if(ipPort.contains("?")) {
			bruteforcingPort = true;
			ipPort = ipPort.replaceAll("\\?", "");
		} else {
			bruteforcingPort = false;
		}
		String[] ipPortSplit = ipPort.split(":");
		String ipOnly = ipPortSplit[0];
		if(ipPortSplit.length == 2) {
			remotePort = Integer.parseInt(ipPortSplit[1]);
		} else {
			remotePort = Constants.DEFAULT_PORT;
		}

		Logger.debug(ipOnly+":"+remotePort);
		this.manager = manager;
		manager.addConnection(this);

		//connect
		InetAddress remoteAddress = null;
		try {
			remoteAddress = InetAddress.getByName(ipOnly);
		} catch (IOException e) {
			Logger.error(e);
		}
		this.remoteAddress = remoteAddress;
	}

	public void send(Protocol source, byte[] data) {
		send(source, data, 0, data.length);
	}

	public void send(Protocol source, byte[] data, int offset, int length) {
		if(disconnected) return;
		if(source.isImportant) {
			// Split it into smaller packages to reduce loss.
			final int maxSizeMinusHeader = MAX_IMPORTANT_PACKAGE_SIZE;
			int packages = Math.floorDiv(length + maxSizeMinusHeader - 1, maxSizeMinusHeader); // Emulates a ceilDiv.
			int startID = messageID.getAndAdd(packages);
			for(int i = 0; i < packages; i++) {
				byte[] packageData = new byte[Math.min(MAX_IMPORTANT_PACKAGE_SIZE, length) + IMPORTANT_HEADER_SIZE];
				packageData[0] = source.id;
				if(i + 1 == packages) {
					packageData[1] = (byte)0xff;
				} else {
					packageData[1] = 0;
				}
				Bits.putInt(packageData, 2, startID);
				System.arraycopy(data, offset, packageData, IMPORTANT_HEADER_SIZE, packageData.length - IMPORTANT_HEADER_SIZE);
				DatagramPacket packet = new DatagramPacket(packageData, packageData.length, remoteAddress, remotePort);
				synchronized(unconfirmedPackets) {
					unconfirmedPackets.add(new UnconfirmedPackage(packet, lastKeepAliveSent, startID));
				}
				manager.send(packet);
				startID++;
				offset += packageData.length - IMPORTANT_HEADER_SIZE;
				length -= packageData.length - IMPORTANT_HEADER_SIZE;
			}
		} else {
			assert(length + 1 < MAX_PACKET_SIZE) : "Package is too big. Please split it into smaller packages.";
			byte[] fullData = new byte[length + 1];
			fullData[0] = source.id;
			System.arraycopy(data, offset, fullData, 1, length);
			manager.send(new DatagramPacket(fullData, fullData.length, remoteAddress, remotePort));
		}
	}

	void receiveKeepAlive(byte[] data, int offset, int length) {
		otherKeepAliveReceived = Bits.getInt(data, offset);
		lastKeepAliveReceived = Bits.getInt(data, offset + 4);
		for(int i = offset + 8; i + 8 <= offset + length; i += 8) {
			int start = Bits.getInt(data, i);
			int len = Bits.getInt(data, i + 4);
			synchronized(unconfirmedPackets) {
				for(int j = 0; j < unconfirmedPackets.size; j++) {
					int diff = unconfirmedPackets.array[j].id - start;
					if(diff >= 0 && diff < len) {
						unconfirmedPackets.remove(j);
						j--;
					}
				}
			}
		}
	}

	void sendKeepAlive() {
		byte[] data;
		synchronized(receivedPackets) {
			IntSimpleList runLengthEncodingStarts = new IntSimpleList();
			IntSimpleList runLengthEncodingLengths = new IntSimpleList();
			for(var packets : receivedPackets) {
				outer:
				for(int i = 0; i < packets.size; i++) {
					int value = packets.array[i];
					int leftRegion = -1;
					int rightRegion = -1;
					for(int reg = 0; reg < runLengthEncodingStarts.size; reg++) {
						int diff = value - runLengthEncodingStarts.array[reg];
						if(diff >= 0 && diff < runLengthEncodingLengths.array[reg]) {
							continue outer; // Value is already in the list.
						}
						if(diff == runLengthEncodingLengths.array[reg]) {
							leftRegion = reg;
						}
						if(diff == -1) {
							rightRegion = reg;
						}
					}
					if(leftRegion == -1) {
						if(rightRegion == -1) {
							runLengthEncodingStarts.add(value);
							runLengthEncodingLengths.add(1);
						} else {
							runLengthEncodingStarts.array[rightRegion]--;
							runLengthEncodingLengths.array[rightRegion]++;
						}
					} else if(rightRegion == -1) {
						runLengthEncodingLengths.array[leftRegion]++;
					} else {
						// Needs to combine the regions:
						runLengthEncodingLengths.array[leftRegion] += runLengthEncodingLengths.array[rightRegion] + 1;
						runLengthEncodingStarts.removeIndex(rightRegion);
						runLengthEncodingLengths.removeIndex(rightRegion);
					}
				}
			}
			IntSimpleList putBackToFront = receivedPackets[receivedPackets.length - 1];
			System.arraycopy(receivedPackets, 0, receivedPackets, 1, receivedPackets.length - 1);
			receivedPackets[0] = putBackToFront;
			receivedPackets[0].clear();
			data = new byte[runLengthEncodingStarts.size*8 + 8];
			Bits.putInt(data, 0, lastKeepAliveSent++);
			Bits.putInt(data, 4, otherKeepAliveReceived);
			int cur = 8;
			for(int i = 0; i < runLengthEncodingStarts.size; i++) {
				Bits.putInt(data, cur, runLengthEncodingStarts.array[i]);
				cur += 4;
				Bits.putInt(data, cur, runLengthEncodingLengths.array[i]);
				cur += 4;
			}
			assert(cur == data.length);
		}
		send(Protocols.KEEP_ALIVE, data);
		synchronized(unconfirmedPackets) {
			// Resend packets that didn't receive confirmation within the last 2 keep-alive signals.
			for(int i = 0; i < unconfirmedPackets.size; i++) {
				if(lastKeepAliveReceived - unconfirmedPackets.array[i].lastKeepAliveSentBefore >= 2) {
					manager.send(unconfirmedPackets.array[i].packet);
					unconfirmedPackets.array[i].lastKeepAliveSentBefore = lastKeepAliveSent;
				}
			}
		}
		if(bruteforcingPort) { // Brute force through some ports.
			// This is called every 100 ms, so if I send 10 requests it shouldn't be too bad.
			for(int i = 0; i < 5; i++) {
				byte[] fullData = new byte[0];
				//fullData[0] = Protocols.KEEP_ALIVE.id;
				if(((remotePort + bruteForcedPortRange) & 65535) != 0) {
					manager.send(new DatagramPacket(fullData, fullData.length, remoteAddress, (remotePort + bruteForcedPortRange) & 65535));
				}
				if(((remotePort - bruteForcedPortRange) & 65535) != 0) {
					manager.send(new DatagramPacket(fullData, fullData.length, remoteAddress, (remotePort - bruteForcedPortRange) & 65535));
				}
				bruteForcedPortRange++;
			}
		}
	}

	public boolean isConnected() {
		return otherKeepAliveReceived != 0;
	}

	private void collectMultiPackets() {
		byte[] data;
		byte protocol;
		while(true) {
			synchronized(lastReceivedPackets) {
				int id = lastIncompletePacket;
				int len = 0;
				if(lastReceivedPackets[id & 65535] == null)
					return;
				while(id != lastIncompletePacket + 65536) {
					if(lastReceivedPackets[id & 65535] == null)
						return;
					len += lastReceivedPackets[id & 65535].packet.length - IMPORTANT_HEADER_SIZE;
					if(lastReceivedPackets[id & 65535].isEnd)
						break;
					id++;
				}
				id++;
				data = new byte[len];
				int offset = 0;
				protocol = lastReceivedPackets[lastIncompletePacket & 65535].packet[0];
				for(; lastIncompletePacket != id; lastIncompletePacket++) {
					byte[] packet = lastReceivedPackets[lastIncompletePacket & 65535].packet;
					System.arraycopy(packet, IMPORTANT_HEADER_SIZE, data, offset, packet.length - IMPORTANT_HEADER_SIZE);
					offset += packet.length - IMPORTANT_HEADER_SIZE;
					lastReceivedPackets[lastIncompletePacket & 65535] = null;
				}
			}
			Protocols.list[protocol].receive(this, data, 0, data.length);
		}
	}

	public void receive(byte[] data, int len) {
		byte protocol = data[0];
		if(!handShakeComplete && protocol != Protocols.HANDSHAKE.id && protocol != Protocols.KEEP_ALIVE.id) {
			return; // Reject all non-handshake packets until the handshake is done.
		}
		lastConnection = System.currentTimeMillis();
		Protocols.bytesReceived[protocol] += len + 20 + 8; // Including IP header and udp header
		if(Protocols.list[protocol & 0xff].isImportant) {
			int id = Bits.getInt(data, 2);
			if(handShakeComplete && protocol == Protocols.HANDSHAKE.id && id == 0) { // Got a new "first" packet from client. So the client tries to reconnect, but we still think it's connected.
				if(this instanceof User) {
					Server.disconnect((User)this);
					disconnected = true;
					manager.removeConnection(this);
					new Thread(() -> {
						try {
							Server.connect(new User(manager, remoteAddress.getHostAddress() + ":" + remotePort));
						} catch(Throwable e) {
							Logger.error(e);
						}
					}).start();
				} else {
					throw new IllegalStateException("Server 'reconnected'? This makes no sense and the game can't handle that.");
				}
			}
			if(id - lastIncompletePacket >= 65536) {
				Logger.warning("Many incomplete packages. Cannot process any more packages for now.");
				return;
			}
			synchronized(receivedPackets) {
				receivedPackets[0].add(id);
			}
			synchronized(lastReceivedPackets) {
				if(id - lastIncompletePacket < 0 || lastReceivedPackets[id & 65535] != null) {
					return; // Already received the package in the past.
				}
				lastReceivedPackets[id & 65535] = new ReceivedPackage(Arrays.copyOf(data, len), data[1] != 0);
				// Check if a message got completed:
				collectMultiPackets();
			}
		} else {
			Protocols.list[protocol & 0xff].receive(this, data, 1, len - 1);
		}
	}

	public void disconnect() {
		// Send 3 disconnect packages to the other side, just to be sure.
		// If all of them don't get through then there is probably a network issue anyways which would lead to a timeout.
		Protocols.DISCONNECT.disconnect(this);
		try {Thread.sleep(10);} catch(Exception e) {}
		Protocols.DISCONNECT.disconnect(this);
		try {Thread.sleep(10);} catch(Exception e) {}
		Protocols.DISCONNECT.disconnect(this);
		disconnected = true;
		manager.removeConnection(this);
		Logger.info("Disconnected");
	}

	private static final class UnconfirmedPackage {
		private final DatagramPacket packet;
		private int lastKeepAliveSentBefore;
		private final int id;

		private UnconfirmedPackage(DatagramPacket packet, int lastKeepAliveSentBefore, int id) {
			this.packet = packet;
			this.lastKeepAliveSentBefore = lastKeepAliveSentBefore;
			this.id = id;
		}
	}

	private static final class ReceivedPackage {
		private final byte[] packet;
		private final boolean isEnd;

		private ReceivedPackage(byte[] packet, boolean isEnd) {
			this.packet = packet;
			this.isEnd = isEnd;
		}
	}
}
