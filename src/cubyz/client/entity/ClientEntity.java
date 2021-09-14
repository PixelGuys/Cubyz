package cubyz.client.entity;

import org.joml.Vector3f;

import cubyz.client.GameLauncher;
import cubyz.world.entity.EntityType;

public class ClientEntity {
	public Vector3f[] lastPosition = new Vector3f[8];
	public Vector3f rotation = new Vector3f();
	public int frontIndex = 0;
	public int currentIndex = 0;
	public float timeInCurrentFrame = 0;
	public float timeFactor = 1.0f;
	public Vector3f position = new Vector3f();
	public Vector3f velocity = new Vector3f();
	public float movementAnimation = 0; // Only used by mobs that actually move.

	public final float height;
	
	public final EntityType type;
	
	public Vector3f getRenderPosition() { // default method for render pos
		return new Vector3f(position.x, position.y + height/2, position.z);
	}

	public final int id;

	private long lastUpdate;

	public ClientEntity(Vector3f position, Vector3f rotation, int id, EntityType type, float height) {
		lastPosition[0] = position;
		this.rotation.set(rotation);
		this.position.set(position);
		this.id = id;
		this.type = type;
		this.height = height;
	}

	public void updatePosition(Vector3f position, Vector3f rotation) {
		frontIndex = (frontIndex + 1)%lastPosition.length;
		lastPosition[frontIndex] = position;
		rotation.set(rotation);
	}

	public void update() {
		long time = System.nanoTime();
		float deltaTime = (time - lastUpdate)/1e9f*timeFactor;
		lastUpdate = time;
		if(deltaTime > 0.5f) {
			// Skip the first call and lag spikes.
			return;
		}
		Vector3f nextPosition = new Vector3f(); // Position in 1 update.
		float timeStep = 0;
		if(currentIndex == frontIndex) {
			timeStep = (float)GameLauncher.instance.secsPerUpdate - timeInCurrentFrame;
			nextPosition.set(lastPosition[currentIndex]);
			// The local version is too fast!
			timeFactor *= 0.99f;
		} else {
			timeStep = (float)GameLauncher.instance.secsPerUpdate;
			int nextIndex = (currentIndex + 1)%lastPosition.length;
			nextPosition.x = lastPosition[nextIndex].x*timeInCurrentFrame/timeStep
							+ lastPosition[currentIndex].x*(timeStep - timeInCurrentFrame)/timeStep;
			nextPosition.y = lastPosition[nextIndex].y*timeInCurrentFrame/timeStep
							+ lastPosition[currentIndex].y*(timeStep - timeInCurrentFrame)/timeStep;
			nextPosition.z = lastPosition[nextIndex].z*timeInCurrentFrame/timeStep
							+ lastPosition[currentIndex].z*(timeStep - timeInCurrentFrame)/timeStep;
		}


		if(nextPosition.distance(position) > 2 || timeStep == 0) {
			// Teleport if it's too far away.
			position.set(nextPosition);
			velocity.set(0);
		} // Only update when the game is not lagging behind:
		else if(timeInCurrentFrame < GameLauncher.instance.secsPerUpdate) {
			// (v(t + timeStep) + v(t))/2 = (nextPosition.x - position.x)/timeStep
			// a(t)*timeStep = (nextPosition.x - position.x)/timeStep
			// Δv = Δt/timeStep*(2*dist/timeStep - 2*v(t))
			velocity.x += deltaTime/timeStep*(2*(nextPosition.x - position.x)/timeStep - 2*velocity.x);
			velocity.y += deltaTime/timeStep*(2*(nextPosition.y - position.y)/timeStep - 2*velocity.y);
			velocity.z += deltaTime/timeStep*(2*(nextPosition.z - position.z)/timeStep - 2*velocity.z);

			// Some random amount of friction:
			velocity.mul(0.99f);
			position.fma(deltaTime, velocity);

			if(frontIndex != currentIndex && (currentIndex + 1)%lastPosition.length != frontIndex) {
				// The local version is too slow!
				timeFactor *= 1.01f;
			}

			timeInCurrentFrame += deltaTime;
		}
		while(timeInCurrentFrame > GameLauncher.instance.secsPerUpdate && currentIndex != frontIndex) {
			timeInCurrentFrame -= GameLauncher.instance.secsPerUpdate;
			currentIndex = (currentIndex + 1)%lastPosition.length;
		}

		if(type.model != null)
			type.model.update(this, deltaTime);
	}
}
