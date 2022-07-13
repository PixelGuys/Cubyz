package cubyz.multiplayer;

import cubyz.Constants;
import cubyz.utils.Logger;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Implements parts of the STUN(Session Traversal Utilities for NAT) protocol to discover public IP+Port
 * Reference: https://datatracker.ietf.org/doc/html/rfc5389
 */
public final class STUN {
	private static final String[] ipServerList;
	private static final int MAPPED_ADDRESS = 0x0001;
	private static final int XOR_MAPPED_ADDRESS = 0x0020;
	private static final byte[] MAGIC_COOKIE = {0x21, 0x12, (byte)0xA4, 0x42};

	static {
		List<String> list;
		try {
			list = Files.readAllLines(Path.of("assets/cubyz/network/stun_servers"));
		} catch(IOException e) {
			Logger.error(e);
			list = new ArrayList<>();
		}
		Collections.shuffle(list); // Shuffle the list, so we faster notice if any one of these stopped working.
		ipServerList = list.toArray(new String[0]);
	}

	public static String requestIPPort(UDPConnectionManager connection) {
		String oldIPPort = null;

		for(String server : ipServerList) {
			byte[] data = null;
			try {
				// Prepare (empty) request message:
				SecureRandom rand = new SecureRandom();
				byte[] transactionID = new byte[12];
				rand.nextBytes(transactionID);
				byte[] message = new byte[] {
						0x00, 0x01, // message type
						0x00, 0x00, // message length
						MAGIC_COOKIE[0], MAGIC_COOKIE[1], MAGIC_COOKIE[2], MAGIC_COOKIE[3], // "Magic cookie"
						0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // transaction ID
				};
				System.arraycopy(transactionID, 0, message, 8, 12);

				String[] ipPort = server.split(":");
				DatagramPacket packet = new DatagramPacket(message, 20);
				InetAddress addr = InetAddress.getByName(ipPort[0]);
				packet.setAddress(addr);
				packet.setPort(Integer.parseInt(ipPort[1]));
				data = connection.sendRequest(packet, 500);
				if(data == null) {
					Logger.warning("Couldn't reach ip server: "+server);
				} else {
					verifyHeader(data, transactionID);
					String newIPPort = findIPPort(data);
					if(oldIPPort == null) {
						oldIPPort = newIPPort;
					} else if(oldIPPort.equals(newIPPort)) {
						return oldIPPort;
					} else {
						return oldIPPort.replaceAll(":", ":?"); // client is behind a symmetric NAT.
					}
				}
			} catch(UnknownHostException e) {
				Logger.warning("Couldn't reach ip server: "+server);
			} catch(Exception e) {
				Logger.warning("Server "+server+" send errornous response "+Arrays.toString(data));
				Logger.warning(e.getMessage());
			}
		}
		return "127.0.0.1:"+ Constants.DEFAULT_PORT; // TODO: Return ip address in LAN.
	}

	private static String findIPPort(byte[] data) throws Exception {
		int offset = 20;
		while(offset < data.length) {
			int type = (data[offset] & 0xff)*256 + (data[offset+1] & 0xff);
			offset += 2;
			int len = (data[offset] & 0xff)*256 + (data[offset+1] & 0xff);
			offset += 2;
			switch(type) {
				case XOR_MAPPED_ADDRESS:
				case MAPPED_ADDRESS: {
					byte xor = data[offset];
					if(type == MAPPED_ADDRESS && xor != 0x00) throw new Exception("Expected 0 as first byte of MAPPED_ADDRESS.");
					offset++;
					if(data[offset] == 0x01) {
						offset++;
						if(type == XOR_MAPPED_ADDRESS) {
							data[offset] ^= MAGIC_COOKIE[0];
							data[offset+1] ^= MAGIC_COOKIE[1];
							data[offset+2] ^= MAGIC_COOKIE[0];
							data[offset+3] ^= MAGIC_COOKIE[1];
							data[offset+4] ^= MAGIC_COOKIE[2];
							data[offset+5] ^= MAGIC_COOKIE[3];
						}
						int port = (data[offset] & 0xff)*256 + (data[offset + 1] & 0xff);
						offset += 2;
						String ip = (data[offset] & 0xff) + "." + (data[offset + 1] & 0xff) + "." + (data[offset + 2] & 0xff) + "." + (data[offset + 3] & 0xff);
						return ip+":"+port;
					} else if(data[offset] == 0x02) {
						offset += len - 1;
						offset = (offset + 3) & ~3; // Pad to 32 Bit.
						Logger.info("IPv6");
						continue; // I don't care about IPv6.
					} else {
						throw new Exception("Unknown address family in MAPPED_ADDRESS: "+data[offset]);
					}
					//break; Unreachable statement.
				}
				default: {
					offset += len;
					offset = (offset + 3) & ~3; // Pad to 32 Bit.
					break;
				}
			}
		}
		throw new Exception("Message didn't contain IP address.");
	}

	private static void verifyHeader(byte[] data, byte[] transactionID) throws Exception {
		if(data[0] != 0x01 || data[1] != 0x01) { // not a binding result.
			throw new Exception("not a binding");
		}
		if((data[2] & 0xff)*256 + (data[3] & 0xff) != data.length - 20) { // Bad size
			throw new Exception("Bad size: "+((data[2] & 0xff)*256 + (data[3] & 0xff))+" while package size is: "+(data.length - 20));
		}
		for(int i = 0; i < 4; i++) {
			if(data[i + 4] != MAGIC_COOKIE[i]) {
				throw new Exception("Wrong magic cookie.");
			}
		}
		for(int i = 0; i < 12; i++) {
			if(data[i+8] != transactionID[i]) {
				throw new Exception("Wrong transaction ID.");
			}
		}
	}
}
