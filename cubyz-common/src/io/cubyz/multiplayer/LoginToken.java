package io.cubyz.multiplayer;

import java.util.UUID;

public class LoginToken {

	private UUID uuid;
	private long expireTimestamp;
	private UUID playerUuid;
	private String username;
	
	public LoginToken(UUID token, UUID uuid, String username, long expire) {
		expireTimestamp = expire;
		playerUuid = uuid;
		this.username = username;
		this.uuid = token;
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
	
	public String getUsername() {
		return username;
	}
	
}
