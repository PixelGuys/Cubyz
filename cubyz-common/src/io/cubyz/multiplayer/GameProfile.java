package io.cubyz.multiplayer;

import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.UUID;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import io.cubyz.Constants;

/**
 * TODO make database for accounts and make login methods usable with it in online mode.
 * @author zenith391
 *
 */
public class GameProfile {

	private UUID uuid;
	private UUID loginUuid;
	private String username;
	
	private boolean online;
	private static String apiURL = "https://gamexmc.000webhostapp.com/api/";
	
	class LoginResponse {
		public String login_uuid;
		public String player_uuid;
		public boolean error;
		
		public String error_message;
	}
	
	public static LoginToken login(String username, char[] password) throws IOException {
		try {
			System.out.println("Login in..");
			URL login = new URL(apiURL + "login.php?username=" + username);
			HttpURLConnection con = (HttpURLConnection) login.openConnection();
			con.setRequestMethod("GET");
			con.connect();
			Gson gson = new GsonBuilder().create();
			LoginResponse resp = gson.fromJson(new InputStreamReader(con.getInputStream()), LoginResponse.class);
			System.out.println("Logged in!");
			if (resp.error) {
				throw new IOException("Login Error: " + resp.error_message);
			}
			return new LoginToken(UUID.fromString(resp.login_uuid), UUID.fromString(resp.player_uuid), username, System.currentTimeMillis() + (3600000));
		} catch (MalformedURLException e) {
			throw new IOException(e);
		}
	}
	
	/**
	 * Use a login UUID (last 1 hour) to retrieve the username and use it to be logged in as the profile.
	 * @param token
	 * @throws IOException
	 */
	public GameProfile(LoginToken token) {
		if (token.isExpired())
			throw new IllegalArgumentException("expired token");
		online = true;
		loginUuid = token.getToken();
		uuid = token.getUUID();
		username = token.getUsername();
	}
	
	/**
	 * Gets a GameProfile with a login UUID (last 1 hour) from the authentification servers with provided username and password.
	 * @param username
	 * @param password
	 * @throws IOException
	 */
	public GameProfile(String username, char[] password) throws IOException {
		this(login(username, password));
	}
	
	/**
	 * Offline mode. Generates a login UUID retrieved from username and mark the profile as non-online.
	 * @param username
	 */
	public GameProfile(String username) {
		online = false;
		loginUuid = UUID.randomUUID();
		uuid = UUID.nameUUIDFromBytes(username.getBytes(Constants.CHARSET_IMPL));
		this.username = username;
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
	
	public String getUsername() {
		return username;
	}
	
}
