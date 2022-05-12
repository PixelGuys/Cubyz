package cubyz.multiplayer;

/**
 * A simple message that gets send regularly.
 */
class KeepAliveProtocol extends Protocol {

	public KeepAliveProtocol() {
		super((byte)0, false);
	}

	@Override
	public void receive(UDPConnection conn, byte[] data, int offset, int length) {
		conn.receiveKeepAlive(data, offset, length);
	}
}
