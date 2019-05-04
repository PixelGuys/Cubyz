package io.cubyz.multiplayer;

import java.util.UUID;

import io.cubyz.Constants;

/**
 * TODO make database for accounts and make login methods usable with it in online mode.
 * @author zenith391
 *
 */
public class GameProfile {

	private UUID uuid;
	private UUID loginUuid;
	private boolean online;
	
	public static boolean isExpired(UUID loginId) {
		return true;
	}
	
	/**
	 * Use a login UUID (last 24 hours) to retrieve the username and use it to be logged in as the profile.
	 * @param loginId
	 */
	public GameProfile(UUID loginId) {
		if (isExpired(loginId))
			throw new IllegalArgumentException("loginId: expired");
		online = true;
		throw new UnsupportedOperationException("online mode unsupported");
	}
	
	/**
	 * Gets a GameProfile with a login UUID (last 24 hours) from the authentification servers with provided username and password.
	 * @param username
	 * @param password
	 */
	public GameProfile(String username, char[] password) {
		online = true;
	}
	
	/**
	 * Offline mode. Generates a login UUID retrieved from username and mark the profile as non-online.
	 * @param username
	 */
	public GameProfile(String username) {
		online = false;
		loginUuid = UUID.randomUUID();
		uuid = UUID.nameUUIDFromBytes(username.getBytes(Constants.CHARSET_IMPL));
	}
	
	public boolean isOnline() {
		return online;
	}
	
	public UUID getLoginUUID() {
		return loginUuid;
	}
	
	public UUID getUUID() {
		return uuid;
	}
	
}
