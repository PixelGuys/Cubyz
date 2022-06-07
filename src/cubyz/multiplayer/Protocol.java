package cubyz.multiplayer;

public abstract class Protocol {
	public final byte id;
	public final boolean isImportant;

	public Protocol(byte id, boolean isImportant) {
		assert Protocols.list[id & 0xff] == null : "Protocols have duplicate id : " + this.getClass() + " " + Protocols.list[id & 0xff].getClass();
		this.id = id;
		this.isImportant = isImportant;
		Protocols.list[id & 0xff] = this;
	}

	public abstract void receive(UDPConnection conn, byte[] data, int offset, int length);
}
