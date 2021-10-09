package cubyz.world.items.tools;

import java.util.Stack;

import org.joml.Vector2f;
import org.joml.Vector3i;

import cubyz.world.ServerWorld;
import cubyz.world.items.Item;

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
	private static void determineSharpness(Tool tool, Vector3i point) {
		// A region is smooth(non-sharp) if a subset pixels can be divided into filled and emtpy using a single line.
		Item[][] subset = new Item[5][5];
		for(int x = 0; x < 5; x++) {
			for(int y = 0; y < 5; y++) {
				if(x + point.x - 2 >= 0 && x + point.x - 2 < 16) {
					if(y + point.y - 2 >= 0 && y + point.y - 2 < 16) {
						subset[x][y] = tool.materialGrid[x + point.x - 2][y + point.y - 2];
					}
				}
			}
		}
		// This line is determined using gradient descent.
		Vector2f base = new Vector2f();
		Vector2f direction = new Vector2f(1, 0);
		Vector2f position = new Vector2f();
		Vector2f deltaDir = new Vector2f();
		Vector2f deltaPos = new Vector2f();
		int wrongSidedThings = 0;
		for(float stepSize = 1; stepSize >= 0.01f; stepSize *= 0.8f) {
			for(int x = 0; x < 5; x++) {
				for(int y = 0; y < 5; y++) {
					position.set(x, y);
					position.sub(base);
					float projection = position.dot(direction);
					position.fma(projection, direction);
					float orthogonal = position.dot(new Vector2f(direction.y, -direction.x));
					if(orthogonal < 0 != (subset[x][y] != null)) {
						// That thing belongs on the other side.
						deltaPos.add(position.mul(stepSize));
						deltaDir.add(position.mul(projection * stepSize));
						if(stepSize*0.8f < 0.01f) {
							wrongSidedThings++;
						}
					}
				}
			}
			position.add(deltaPos);
			direction.add(deltaDir);
			deltaPos.set(0);
			deltaDir.set(0);
		}
		point.z = wrongSidedThings;
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
				float angle = (float) Math.atan2(y + 0.5f - center.y, x + 0.5f - center.x) - initialAngle;
				float distance = (float) Math.cos(angle) * center.distance(x + 0.5f, y + 0.5f);
				if(angle < 0) {
					if(angle < leftCollisionAngle) {
						leftCollisionAngle = angle;
						leftCollisionPoint.set(x, y, 0);
					}
				} else {
					if(angle > rightCollisionAngle) {
						rightCollisionAngle = angle;
						rightCollisionPoint.set(x, y, 0);
					}
				}
				if(distance > frontCollisionDistance) {
					frontCollisionDistance = angle;
					frontCollisionPoint.set(x, y, 0);
				}
			}
		}
		// sharpness is hard.
		determineSharpness(tool, leftCollisionPoint);
		determineSharpness(tool, rightCollisionPoint);
		determineSharpness(tool, frontCollisionPoint);
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
		tool.durability = tool.maxDurability = (int)(durability * 10); // TODO: Balancing.
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
		impactEnergy *= tool.materialGrid[collisionPoint.x][collisionPoint.y].material.power + tool.mass * ServerWorld.GRAVITY;

		return impactEnergy/100; // TODO: Balancing
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
		float sharpnessFactor = collisionPoint.z;

		return sharpnessFactor*calculateImpactEnergy(tool, collisionPoint);
	}

	/**
	 * Determines how good an axe this side of the tool would make.
	 * @param tool
	 * @param collisionPoint
	 * @return
	 */
	private static float evaluateAxePower(Tool tool, Vector3i collisionPoint) {
		// Axes are used for breaking up wood. This requires a larger area (= smooth tip) rather than a sharp tip.
		float areaFactor = 1.0f/collisionPoint.z;

		return areaFactor*calculateImpactEnergy(tool, collisionPoint);
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
					xStack.push(y - 1);
				}
			}
			if(x - 1 >= 0 && y + 1 < 16 && tool.materialGrid[x - 1][y + 1] != null) {
				if(sandPiles[x - 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x - 1][y + 1] = sandPiles[x][y] + 1;
					xStack.push(x - 1);
					xStack.push(y + 1);
				}
			}
			if(x + 1 < 16 && y - 1 >= 0 && tool.materialGrid[x + 1][y - 1] != null) {
				if(sandPiles[x + 1][y - 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y - 1] = sandPiles[x][y] + 1;
					xStack.push(x + 1);
					xStack.push(y - 1);
				}
			}
			if(x + 1 < 16 && y + 1 < 16 && tool.materialGrid[x + 1][y + 1] != null) {
				if(sandPiles[x + 1][y + 1] > sandPiles[x][y] + 1) {
					sandPiles[x + 1][y + 1] = sandPiles[x][y] + 1;
					xStack.push(x + 1);
					xStack.push(y + 1);
				}
			}
		}
		// Count the area:
		int area = 0;
		for(int x = 0; x < 16; x++) {
			for(int y = 0; y < 16; y++) {
				area += sandPiles[x][y];
			}
		}
		area /= 16*16; // TODO: Balancing
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
		tool.swingTime = (tool.mass + tool.inertiaHandle)/256; // TODO: Balancing

		// TODO: Swords and throwing weapons.

	}
}
