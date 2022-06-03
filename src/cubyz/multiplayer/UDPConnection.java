package cubyz.multiplayer;

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
	final int remotePort;

	private final AtomicInteger messageID = new AtomicInteger(0);
	private final SimpleList<UnconfirmedPackage> unconfirmedPackets = new SimpleList<>(new UnconfirmedPackage[1024]); // TODO: Consider using a hashmap/sorted list instead.
	private final IntSimpleList[] receivedPackets = new IntSimpleList[]{new IntSimpleList(), new IntSimpleList(), new IntSimpleList()}; // Resend the confirmation 3 times, to make sure the server doesn't need to resend stuff.
	private final ReceivedPackage[] lastReceivedPackets = new ReceivedPackage[65536];

	int lastIncompletePackage = 0;


	int lastKeepAliveSent = 0, lastKeepAliveReceived = 0, otherKeepAliveReceived = 0;

	protected boolean disconnected = false;

	public UDPConnection(UDPConnectionManager manager, String ip, int remotePort) {

		Logger.debug(ip+":"+remotePort);
		this.remotePort = remotePort;
		this.manager = manager;
		manager.addConnection(this);

		//connect
		InetAddress remoteAddress = null;
		try {
			remoteAddress = InetAddress.getByName(ip);
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
		for(int i = offset + 8; i + 4 <= offset + length; i += 4) {
			int id = Bits.getInt(data, i);
			synchronized(unconfirmedPackets) {
				for(int j = 0; j < unconfirmedPackets.size; j++) {
					if(unconfirmedPackets.array[j].id == id) {
						unconfirmedPackets.remove(j);
						break; // There must not be any duplicates.
					}
				}
			}
		}
		Logger.debug("Unconfirmed: " + unconfirmedPackets.size);
	}

	void sendKeepAlive() {
		int dataLength = 0;
		byte[] data;
		synchronized(receivedPackets) {
			for(var packets : receivedPackets) {
				dataLength += packets.size;
			}
			if(dataLength + 9 >= MAX_PACKET_SIZE/4) {
				dataLength = (MAX_PACKET_SIZE - 9)/4;
			}
			data = new byte[dataLength*4 + 8];
			Bits.putInt(data, 0, lastKeepAliveSent++);
			Bits.putInt(data, 4, otherKeepAliveReceived);
			int cur = 8;
			for(int i = receivedPackets.length - 1; i >= 0; i--) {
				while(receivedPackets[i].size > 0 && cur < data.length) {
					receivedPackets[i].size--;
					int id = receivedPackets[i].array[receivedPackets[i].size];
					Bits.putInt(data, cur, id);
					cur += 4;
					if(i != receivedPackets.length - 1) {
						receivedPackets[i + 1].add(id);
					}
				}
			}
			assert(cur - 8 == dataLength*4);
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
	}

	private void collectMultiPackets() {
		byte[] data;
		byte protocol;
		while(true) {
			synchronized(lastReceivedPackets) {
				int id = lastIncompletePackage;
				int len = 0;
				if(lastReceivedPackets[id & 65535] == null)
					return;
				while(id != lastIncompletePackage + 65536) {
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
				protocol = lastReceivedPackets[lastIncompletePackage & 65535].packet[0];
				for(; lastIncompletePackage != id; lastIncompletePackage++) {
					byte[] packet = lastReceivedPackets[lastIncompletePackage & 65535].packet;
					System.arraycopy(packet, IMPORTANT_HEADER_SIZE, data, offset, packet.length - IMPORTANT_HEADER_SIZE);
					offset += packet.length - IMPORTANT_HEADER_SIZE;
					lastReceivedPackets[lastIncompletePackage & 65535] = null;
				}
			}
			Protocols.list[protocol].receive(this, data, 0, data.length);
		}
	}

	public void receive(byte[] data, int len) {
		byte protocol = data[0];
		if(Math.random() < 0.1) {
			//Logger.debug("Dropped it :P");
			return; // Drop packet :P
		}
		if(Protocols.list[protocol & 0xff].isImportant) {
			int id = Bits.getInt(data, 2);
			if(id - lastIncompletePackage >= 65536) {
				Logger.warning("Many incomplete packages. Cannot process any more packages for now.");
				return;
			}
			synchronized(receivedPackets) {
				receivedPackets[0].add(id);
			}
			synchronized(lastReceivedPackets) {
				if(id - lastIncompletePackage < 0 || lastReceivedPackets[id & 65535] != null) {
					Logger.warning("Already received it: "+id);
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
