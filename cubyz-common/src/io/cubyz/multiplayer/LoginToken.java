package io.cubyz.multiplayer;

import java.util.UUID;

public class LoginToken {

	private UUID uuid;
	private long expireTimestamp;
	private UUID playerUuid;
	
	public LoginToken(UUID token, UUID uuid, long expire) {
		expireTimestamp = expire;
		playerUuid = uuid;
		uuid = token;
	}
	
	public UUID getToken() {
		return uuid;
	}
	
	public boolean isExpired() {
		return System.currentTimeMillis() > expireTimestamp;
	}
	
	public UUID getUUID() {
		return playerUuid;
	}
	
}
