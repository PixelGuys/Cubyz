package cubyz.world.items.tools;

import java.util.Stack;

import org.joml.Vector2f;
import org.joml.Vector3i;

/**
 * Determines the physical properties of a tool to caclulate in-game parameters such as durability and speed.
 */
public class ToolPhysics {
	/**
	 * Finds the handle of the tool.
	 * Uses a quite simple algorithm:
	 * It just simply takes the lowest, right-most 2×2 grid of filled pixels.
	 * @param tool
	 */
	private static void findHandle(Tool tool) {
		for(int y = 14; y >= 0; y--) {
			for(int x = 14; x >= 0; x--) {
				// Check the 2×2 grid at this location:
				if(tool.materialGrid[x][y] != null &&
				   tool.materialGrid[x][y + 1] != null &&
				   tool.materialGrid[x + 1][y] != null &&
				   tool.materialGrid[x + 1][y + 1] != null) {
					
					tool.handlePosition.x = x + 0.5f;
					tool.handlePosition.y = y + 0.5f;
					return;
				}
			}
		}
	}

	/**
	 * Determines the mass and moment of inertia of handle and center of mass.
	 * @param tool
	 */
	private static void determineInertia(Tool tool) {
		// Determines mass and center of mass:
		double centerMassX = 0;
		double centerMassY = 0;
		double mass = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				if(tool.materialGrid[x][y] == null) continue;

				double localMass = tool.materialGrid[x][y].material.density;
				centerMassX += localMass*(x + 0.5);
				centerMassY += localMass*(y + 0.5);
				mass += localMass;
			}
		}
		tool.centerOfMass.x = (float) (centerMassX/mass);
		tool.centerOfMass.y = (float) (centerMassY/mass);
		tool.mass = (float) mass;

		// Determines moment of intertia relative to the center of mass:
		double inertia = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				if(tool.materialGrid[x][y] == null) continue;
				
				double localMass = tool.materialGrid[x][y].material.density;
				double dx = x + 0.5 - tool.centerOfMass.x;
				double dy = y + 0.5 - tool.centerOfMass.y;
				inertia += (dx * dx + dy * dy) * localMass;
			}
		}
		tool.inertiaCenterOfMass = (float) inertia;
		// Using the parallel axis theorem the inertia relative to the handle can be derived:
		tool.inertiaHandle = (float) (inertia + mass * tool.centerOfMass.distance(tool.handlePosition));
	}

	/**
	 * Determines the sharpness of a point on the tool.
	 * @param tool
	 * @param point
	 */
	private static void determineSharpness(Tool tool, Vector3i point, float initialAngle) {
		Vector2f center = new Vector2f(tool.handlePosition);
		center.sub(new Vector2f(tool.centerOfMass).sub(tool.handlePosition).normalize().mul(16));
		// A region is smooth if there is a lot of pixel within similar angle/distance:
		float originalAngle = (float) Math.atan2(point.y + 0.5f - center.y, point.x + 0.5f - center.x) - initialAngle;
		float originalDistance = (float) Math.cos(originalAngle) * center.distance(point.x + 0.5f, point.y + 0.5f);
		int numOfSmoothPixels = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				float angle = (float) Math.atan2(y + 0.5f - center.y, x + 0.5f - center.x) - initialAngle;
				float distance = (float) Math.cos(angle) * center.distance(x + 0.5f, y + 0.5f);
				float deltaAngle = Math.abs(angle - originalAngle);
				float deltaDist = Math.abs(distance - originalDistance);
				if(deltaAngle <= 0.2 && deltaDist <= 0.7f) {
					numOfSmoothPixels++;
				}
			}
		}
		point.z = numOfSmoothPixels;
	}

	/**
	 * Determines where the tool would collide with the terrain.
	 * Also evaluates the smoothness of the collision point and stores it in the z component.
	 * @param tool
	 * @param leftCollisionPoint
	 * @param rightCollisionPoint
	 * @param topCollisionPoint
	 */
	private static void determineCollisionPoints(Tool tool, Vector3i leftCollisionPoint, Vector3i rightCollisionPoint, Vector3i frontCollisionPoint) {
		// For finding that point the center of rotation is assumed to be 1 arm(16 pixel) begind the handle.
		// Additionally the handle is assumed to go towards the center of mass.
		Vector2f center = new Vector2f(tool.handlePosition);
		center.sub(new Vector2f(tool.centerOfMass).sub(tool.handlePosition).normalize().mul(16));
		// Angle of the handle.
		float initialAngle = (float) Math.atan2(tool.handlePosition.y - center.y, tool.handlePosition.x - center.x);
		float leftCollisionAngle = 0;
		float rightCollisionAngle = 0;
		float frontCollisionDistance = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				if(tool.materialGrid[x][y] == null) continue;

				float angle = (float) Math.atan2(y + 0.5f - center.y, x + 0.5f - center.x) - initialAngle;
				float distance = (float) Math.cos(angle) * center.distance(x + 0.5f, y + 0.5f);
				if(angle < leftCollisionAngle) {
					leftCollisionAngle = angle;
					leftCollisionPoint.set(x, y, 0);
				}
				if(angle > rightCollisionAngle) {
					rightCollisionAngle = angle;
					rightCollisionPoint.set(x, y, 0);
				}
				if(distance > frontCollisionDistance) {
					frontCollisionDistance = angle;
					frontCollisionPoint.set(x, y, 0);
				}
			}
		}
		// sharpness is hard.
		determineSharpness(tool, leftCollisionPoint, initialAngle);
		determineSharpness(tool, rightCollisionPoint, initialAngle);
		determineSharpness(tool, frontCollisionPoint, initialAngle);
	}

	private static void calculateDurability(Tool tool) {
		// Doesn't do much besides summing up the durability of all it's parts:
		float durability = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				if(tool.materialGrid[x][y] != null) {
					durability += tool.materialGrid[x][y].material.resistance;
				}
			}
		}
		tool.durability = tool.maxDurability = (int)(durability); // TODO: Balancing.
	}

	/**
	 * Determines how hard the tool hits the ground.
	 * @param tool
	 */
	private static float calculateImpactEnergy(Tool tool, Vector3i collisionPoint) {
		// Fun fact: Without gravity the impact energy is independent of the mass of the pickaxe(E = ∫ F⃗ ds⃗), but only on the length of the handle.
		float impactEnergy = tool.centerOfMass.distance(tool.handlePosition);

		// But when the pickaxe does get heaier 2 things happen:
		// 1. The player needs to lift a bigger weight, so the tool speed gets reduced(caclulated elsewhere).
		// 2. When travelling down the tool also gets additional energy from gravity, so the force is increased by m·g.
		impactEnergy *= tool.materialGrid[collisionPoint.x][collisionPoint.y].material.power + tool.mass / 128;

		return impactEnergy; // TODO: Balancing
	}

	/**
	 * Determines how good a pickaxe this side of the tool would make.
	 * @param tool
	 * @param collisionPoint
	 * @return
	 */
	private static float evaluatePickaxePower(Tool tool, Vector3i collisionPoint) {
		// Pickaxes are used for breaking up rocks. This requires a high energy in a small area.
		// So a tool is a good pickaxe, if it delivers a energy force and if it has a sharp tip.
		
		// TODO: Balance it.
		float sharpnessFactor = (float) Math.pow(6 - Math.abs(collisionPoint.z - 6), 1);

		return sharpnessFactor*calculateImpactEnergy(tool, collisionPoint)/4;
	}

	/**
	 * Determines how good an axe this side of the tool would make.
	 * @param tool
	 * @param collisionPoint
	 * @return
	 */
	private static float evaluateAxePower(Tool tool, Vector3i collisionPoint) {
		// Axes are used for breaking up wood. This requires a larger area (= smooth tip) rather than a sharp tip.
		float areaFactor = (float) Math.pow(Math.abs(collisionPoint.z - 6) + 1, 1);

		return areaFactor*calculateImpactEnergy(tool, collisionPoint)/8;
	}

	/**
	 * Determines how good a shovel this side of the tool would make.
	 * @param tool
	 * @param collisionPoint
	 * @return
	 */
	private static float evaluateShovelPower(Tool tool, Vector3i collisionPoint) {
		// Shovels require a large area to put all the sand on.
		// For the sake of simplicity I just assume that every part of the tool can contain sand and that sand piles up in a pyramidial shape.
		int[][] sandPiles = new int[16][16];
		Stack<Integer> xStack = new Stack<>();
		Stack<Integer> yStack = new Stack<>();
		// Uses a simple flood-fill algorithm equivalent to light calculation.
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				sandPiles[x][y] = Integer.MAX_VALUE;
				if(tool.materialGrid[x][y] == null) {
					sandPiles[x][y] = 0;
					xStack.push(x);
					yStack.push(y);
				} else if(x == 0 || x == 15 || y == 0 || y == 15) {
					sandPiles[x][y] = 1;
					xStack.push(x);
					yStack.push(y);
				}
			}
		}
		while(!xStack.isEmpty()) {
			int x = xStack.pop();
			int y = yStack.pop();
			if(x - 1 >= 0 && y - 1 >= 0 && tool.materialGrid[x - 1][y - 1] != null) {
				if(sandPiles[x - 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y - 1] = sandPiles[x][y] + 1;
					xStack.push(x - 1);
					yStack.push(y - 1);
				}
			}
			if(x - 1 >= 0 && y + 1 < 16 && tool.materialGrid[x - 1][y + 1] != null) {
				if(sandPiles[x - 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y + 1] = sandPiles[x][y] + 1;
					xStack.push(x - 1);
					yStack.push(y + 1);
				}
			}
			if(x + 1 < 16 && y - 1 >= 0 && tool.materialGrid[x + 1][y - 1] != null) {
				if(sandPiles[x + 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y - 1] = sandPiles[x][y] + 1;
					xStack.push(x + 1);
					yStack.push(y - 1);
				}
			}
			if(x + 1 < 16 && y + 1 < 16 && tool.materialGrid[x + 1][y + 1] != null) {
				if(sandPiles[x + 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y + 1] = sandPiles[x][y] + 1;
					xStack.push(x + 1);
					yStack.push(y + 1);
				}
			}
		}
		// Count the area:
		float area = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				area += sandPiles[x][y];
			}
		}
		area /= 512; // TODO: Balancing
		return area*calculateImpactEnergy(tool, collisionPoint);
	}


	/**
	 * Determines all the basic properties of the tool.
	 * @param tool
	 */
	public static void evaluateTool(Tool tool) {
		findHandle(tool);
		calculateDurability(tool);
		determineInertia(tool);
		Vector3i leftCollisionPoint = new Vector3i();
		Vector3i rightCollisionPoint = new Vector3i();
		Vector3i frontCollisionPoint = new Vector3i();
		determineCollisionPoints(tool, leftCollisionPoint, rightCollisionPoint, frontCollisionPoint);

		float leftPP = evaluatePickaxePower(tool, leftCollisionPoint);
		float rightPP = evaluatePickaxePower(tool, leftCollisionPoint);
		tool.pickaxePower = Math.max(leftPP, rightPP); // TODO: Adjust the swing direction.

		float leftAP = evaluateAxePower(tool, leftCollisionPoint);
		float rightAP = evaluateAxePower(tool, leftCollisionPoint);
		tool.axePower = Math.max(leftAP, rightAP); // TODO: Adjust the swing direction.

		tool.shovelPower = evaluateShovelPower(tool, leftCollisionPoint);

		// It takes longer to swing a heavy tool.
		tool.swingTime = (tool.mass + tool.inertiaHandle/8)/256; // TODO: Balancing

		// TODO: Swords and throwing weapons.

	}
}
