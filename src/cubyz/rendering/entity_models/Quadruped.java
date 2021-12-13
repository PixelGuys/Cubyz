package cubyz.rendering.entity_models;

import org.joml.Intersectiond;
import org.joml.Matrix4f;
import org.joml.Vector2d;
import org.joml.Vector3d;
import org.joml.Vector3f;

import cubyz.api.Resource;
import cubyz.client.Cubyz;
import cubyz.client.entity.ClientEntity;
import cubyz.rendering.EntityRenderer;
import cubyz.rendering.Material;
import cubyz.rendering.Mesh;
import cubyz.rendering.ShaderProgram;
import cubyz.rendering.Texture;
import cubyz.rendering.Transformation;
import cubyz.rendering.models.Model;
import cubyz.world.entity.Entity;
import cubyz.world.entity.EntityModel;
import cubyz.world.entity.EntityType;
import cubyz.world.entity.Player;

/**
 * An entity model for all possible quadruped mobs that handles model creation and movement animation.<br>
 * TODO: Simplify this and allow for custom head/leg/body models.
 */

public class Quadruped implements EntityModel {
	private enum MovementPattern {
		STABLE, FAST,
	};
	// Registry stuff:
	Resource id = new Resource("cuybz:quadruped");
	public Quadruped() {}
	@Override
	public Resource getRegistryID() {
		return id;
	}
	@Override
	public EntityModel createInstance(String data, EntityType source) {
		
		return new Quadruped(data, source);
	}
	
	// Actual model stuff:
	private Mesh leg, body, head;
	float bodyWidth, bodyLength, bodyHeight, legWidth, legHeight, headWidth, headLength, headHeight;
	MovementPattern movementPattern;
	
	public Quadruped(String data, EntityType source) {
		// Parse data:
		String[] lines = data.split("\n");
		for(String line : lines) {
			String[] parts = line.replaceAll("\\s", "").split(":");
			if (parts[0].equals("body")) {
				String[] arguments = parts[1].split("x");
				bodyWidth = Integer.parseInt(arguments[0])/16.0f;
				bodyLength = Integer.parseInt(arguments[1])/16.0f;
				bodyHeight = Integer.parseInt(arguments[2])/16.0f;
			} else if (parts[0].equals("head")) {
				String[] arguments = parts[1].split("x");
				headWidth = Integer.parseInt(arguments[0])/16.0f;
				headLength = Integer.parseInt(arguments[1])/16.0f;
				headHeight = Integer.parseInt(arguments[2])/16.0f;
			} else if (parts[0].equals("leg")) {
				String[] arguments = parts[1].split("x");
				legWidth = Integer.parseInt(arguments[0])/16.0f;
				legHeight = Integer.parseInt(arguments[1])/16.0f;
			} else if (parts[0].equals("movement")) {
				movementPattern = MovementPattern.valueOf(parts[1].toUpperCase());
			}
		}
		float textureWidth = Math.max(4*legWidth, headHeight + headLength) + bodyLength + bodyHeight;
		float textureHeight = Math.max(2*bodyWidth + 2*bodyHeight, legHeight + legWidth + 2*headWidth + 2*headLength);
		// leg obj:
		float legOffset = bodyLength + bodyHeight;
		float[] legPositions = new float[] {
				// Top(each vertex two times(the top face is not rendered)):
				-legWidth/2,		0,						-legWidth/2,	//0
				-legWidth/2,		0,						-legWidth/2,	//1
				-legWidth/2,		0,						legWidth/2,		//2
				-legWidth/2,		0,						legWidth/2,		//3
				legWidth/2,			0,						-legWidth/2,	//4
				legWidth/2,			0,						-legWidth/2,	//5
				legWidth/2,			0,						legWidth/2,		//6
				legWidth/2,			0,						legWidth/2,		//7
				// Bottom(each vertex three times):
				-legWidth/2,		-legHeight,			-legWidth/2,	//8
				-legWidth/2,		-legHeight,			-legWidth/2,	//9
				-legWidth/2,		-legHeight,			-legWidth/2,	//10
				-legWidth/2,		-legHeight,			legWidth/2,		//11
				-legWidth/2,		-legHeight,			legWidth/2,		//12
				-legWidth/2,		-legHeight,			legWidth/2,		//13
				legWidth/2.0f,		-legHeight,			-legWidth/2,	//14
				legWidth/2.0f,		-legHeight,			-legWidth/2,	//15
				legWidth/2.0f,		-legHeight,			-legWidth/2,	//16
				legWidth/2.0f,		-legHeight,			legWidth/2,		//17
				legWidth/2.0f,		-legHeight,			legWidth/2,		//18
				legWidth/2.0f,		-legHeight,			legWidth/2,		//19
		};
		float[] legTextCoords = new float[] {
				// Top:
				(legOffset + legWidth)/textureWidth, 0,		//-x
				(legOffset + legWidth)/textureWidth, 0,		//-z
				
				(legOffset)/textureWidth, 0,				//-x
				(legOffset + 4*legWidth)/textureWidth, 0,	//+z
				
				(legOffset + 2*legWidth)/textureWidth, 0,	//+x
				(legOffset + 2*legWidth)/textureWidth, 0,	//-z
				
				(legOffset + 3*legWidth)/textureWidth, 0,	//+x
				(legOffset + 3*legWidth)/textureWidth, 0,	//+z
				// Bottom:
				(legOffset)/textureWidth, (legHeight)/textureHeight,
				(legOffset + legWidth)/textureWidth, (legHeight)/textureHeight,
				(legOffset + legWidth)/textureWidth, (legHeight)/textureHeight,
				
				(legOffset + legWidth)/textureWidth, (legHeight)/textureHeight,
				(legOffset)/textureWidth, (legHeight)/textureHeight,
				(legOffset + 4*legWidth)/textureWidth, (legHeight)/textureHeight,
				(legOffset)/textureWidth, (legHeight + legWidth)/textureHeight,
				(legOffset + 2*legWidth)/textureWidth, (legHeight)/textureHeight,
				(legOffset + 2*legWidth)/textureWidth, (legHeight)/textureHeight,
				(legOffset + legWidth)/textureWidth, (legHeight + legWidth)/textureHeight,
				(legOffset + 3*legWidth)/textureWidth, (legHeight)/textureHeight,
				(legOffset + 3*legWidth)/textureWidth, (legHeight)/textureHeight,
		};
		float[] legNormals = new float[] {
				// Top:
				-1, 0, 0,
				0, 0, -1,
				-1, 0, 0,
				0, 0, 1,
				1, 0, 0,
				0, 0, -1,
				1, 0, 0,
				0, 0, 1,
				// Bottom:
				0, -1, 0,
				-1, 0, 0,
				0, 0, -1,
				0, -1, 0,
				-1, 0, 0,
				0, 0, 1,
				0, -1, 0,
				1, 0, 0,
				0, 0, -1,
				0, -1, 0,
				1, 0, 0,
				0, 0, 1,
		};
		int[] legIndices = new int[] {
				// Bottom:
				8, 14, 17,
				11, 8, 17,
				// -x:
				0, 9, 12,
				2, 0, 12,
				// +x:
				15, 4, 18,
				4, 6, 18,
				// -z:
				10, 1, 16,
				1, 5, 16,
				// +z:
				3, 13, 19,
				7, 3, 19,
		};
		// body obj:
		float[] bodyPositions = new float[] {
				// Top(each vertex two times(the top face is not rendered)):
				-bodyLength/2,	bodyHeight/2,		-bodyWidth/2,		//0
				-bodyLength/2,	bodyHeight/2,		-bodyWidth/2,		//1
				-bodyLength/2,	bodyHeight/2,		bodyWidth/2,		//2
				-bodyLength/2,	bodyHeight/2,		bodyWidth/2,		//3
				bodyLength/2,	bodyHeight/2,		-bodyWidth/2,		//4
				bodyLength/2,	bodyHeight/2,		-bodyWidth/2,		//5
				bodyLength/2,	bodyHeight/2,		bodyWidth/2,		//6
				bodyLength/2,	bodyHeight/2,		bodyWidth/2,		//7
				// Bottom(each vertex three times):
				-bodyLength/2,	-bodyHeight/2,		-bodyWidth/2,		//8
				-bodyLength/2,	-bodyHeight/2,		-bodyWidth/2,		//9
				-bodyLength/2,	-bodyHeight/2,		-bodyWidth/2,		//10
				-bodyLength/2,	-bodyHeight/2,		bodyWidth/2,		//11
				-bodyLength/2,	-bodyHeight/2,		bodyWidth/2,		//12
				-bodyLength/2,	-bodyHeight/2,		bodyWidth/2,		//13
				bodyLength/2,	-bodyHeight/2,		-bodyWidth/2,		//14
				bodyLength/2,	-bodyHeight/2,		-bodyWidth/2,		//15
				bodyLength/2,	-bodyHeight/2,		-bodyWidth/2,		//16
				bodyLength/2,	-bodyHeight/2,		bodyWidth/2,		//17
				bodyLength/2,	-bodyHeight/2,		bodyWidth/2,		//18
				bodyLength/2,	-bodyHeight/2,		bodyWidth/2,		//19
				// Top face:
				-bodyLength/2,	bodyHeight/2,		-bodyWidth/2,		//20
				-bodyLength/2,	bodyHeight/2,		bodyWidth/2,		//21
				bodyLength/2,	bodyHeight/2,		-bodyWidth/2,		//22
				bodyLength/2,	bodyHeight/2,		bodyWidth/2,		//23
		};
		float[] bodyTextCoords = new float[] {
				// Top:
				(bodyLength)/textureWidth, (bodyWidth)/textureHeight,		//-x
				(bodyLength)/textureWidth, (bodyWidth)/textureHeight,		//-z
				
				(bodyLength)/textureWidth, 0,					//-x
				0, (2*bodyWidth + bodyHeight)/textureHeight,	//+z
				
				(bodyLength)/textureWidth, (bodyWidth+bodyHeight)/textureHeight,	//+x
				0, (bodyWidth)/textureHeight,	//-z
				
				(bodyLength)/textureWidth, (2*bodyWidth+bodyHeight)/textureHeight,	//+x
				(bodyLength)/textureWidth, (2*bodyWidth+bodyHeight)/textureHeight,	//+z
				// Bottom:
				(bodyLength)/textureWidth, (bodyWidth + bodyHeight)/textureHeight,	//B
				(bodyLength + bodyHeight)/textureWidth, (bodyWidth)/textureHeight,		//-x
				(bodyLength)/textureWidth, (bodyWidth + bodyHeight)/textureHeight,		//-z

				(bodyLength)/textureWidth, (2*bodyWidth + bodyHeight)/textureHeight,	//B
				(bodyLength + bodyHeight)/textureWidth, 0,					//-x
				0, (2*bodyWidth + 2*bodyHeight)/textureHeight,	//+z

				0, (bodyWidth + bodyHeight)/textureHeight,	//B
				(bodyLength + bodyHeight)/textureWidth, (bodyWidth+bodyHeight)/textureHeight,	//+x
				0, (bodyWidth + bodyHeight)/textureHeight,	//-z

				0, (2*bodyWidth + bodyHeight)/textureHeight,	//B
				(bodyLength + bodyHeight)/textureWidth, (2*bodyWidth+bodyHeight)/textureHeight,	//+x
				(bodyLength)/textureWidth, (2*bodyWidth+2*bodyHeight)/textureHeight,	//+z
				// Top only:
				(bodyLength)/textureWidth, (bodyWidth)/textureHeight,	//T
				
				(bodyLength)/textureWidth, 0,	//T
				
				0, (bodyWidth)/textureHeight,	//T
				
				0, 0,	//T
		};
		float[] bodyNormals = new float[] {
				// Top:
				-1, 0, 0,
				0, 0, -1,
				-1, 0, 0,
				0, 0, 1,
				1, 0, 0,
				0, 0, -1,
				1, 0, 0,
				0, 0, 1,
				// Bottom:
				0, -1, 0,
				-1, 0, 0,
				0, 0, -1,
				0, -1, 0,
				-1, 0, 0,
				0, 0, 1,
				0, -1, 0,
				1, 0, 0,
				0, 0, -1,
				0, -1, 0,
				1, 0, 0,
				0, 0, 1,
		};
		int[] bodyIndices = new int[] {
				// Bottom:
				8, 14, 17,
				11, 8, 17,
				// -x:
				0, 9, 12,
				2, 0, 12,
				// +x:
				15, 4, 18,
				4, 6, 18,
				// -z:
				10, 1, 16,
				1, 5, 16,
				// +z:
				3, 13, 19,
				7, 3, 19,
				// Top:
				22, 20, 23,
				20, 21, 23,
		};
		// head obj:
		float[] headPositions = new float[] {
				// Top(each vertex two times(the top face is not rendered)):
				-headLength/2,	headHeight/2,		-headWidth/2,		//0
				-headLength/2,	headHeight/2,		-headWidth/2,		//1
				-headLength/2,	headHeight/2,		headWidth/2,		//2
				-headLength/2,	headHeight/2,		headWidth/2,		//3
				headLength/2,	headHeight/2,		-headWidth/2,		//4
				headLength/2,	headHeight/2,		-headWidth/2,		//5
				headLength/2,	headHeight/2,		headWidth/2,		//6
				headLength/2,	headHeight/2,		headWidth/2,		//7
				// Bottom(each vertex three times):
				-headLength/2,	-headHeight/2,		-headWidth/2,		//8
				-headLength/2,	-headHeight/2,		-headWidth/2,		//9
				-headLength/2,	-headHeight/2,		-headWidth/2,		//10
				-headLength/2,	-headHeight/2,		headWidth/2,		//11
				-headLength/2,	-headHeight/2,		headWidth/2,		//12
				-headLength/2,	-headHeight/2,		headWidth/2,		//13
				headLength/2,	-headHeight/2,		-headWidth/2,		//14
				headLength/2,	-headHeight/2,		-headWidth/2,		//15
				headLength/2,	-headHeight/2,		-headWidth/2,		//16
				headLength/2,	-headHeight/2,		headWidth/2,		//17
				headLength/2,	-headHeight/2,		headWidth/2,		//18
				headLength/2,	-headHeight/2,		headWidth/2,		//19
				// Top face:
				-headLength/2,	headHeight/2,		-headWidth/2,		//20
				-headLength/2,	headHeight/2,		headWidth/2,		//21
				headLength/2,	headHeight/2,		-headWidth/2,		//22
				headLength/2,	headHeight/2,		headWidth/2,		//23
		};
		float headOffsetX = bodyLength + bodyHeight;
		float headOffsetY = legWidth + legHeight;
		float[] headTextCoords = new float[] {
				// Top:
				(headOffsetX)/textureWidth, (headOffsetY + headWidth)/textureHeight,		//-x
				(headOffsetX)/textureWidth, (headOffsetY + headWidth)/textureHeight,		//-z

				(headOffsetX)/textureWidth, (headOffsetY)/textureHeight,		//-x
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + 2*headWidth + 2*headLength)/textureHeight,	//+z
				
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + headWidth + headLength)/textureHeight,	//+x
				(headOffsetX)/textureWidth, (headOffsetY + headWidth + headLength)/textureHeight,	//-z
				
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + 2*headWidth + headLength)/textureHeight,	//+x
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + 2*headWidth + headLength)/textureHeight,	//+z
				// Bottom:
				(headOffsetX + headHeight + headLength)/textureWidth, (headOffsetY + headWidth)/textureHeight,	//B
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + headWidth)/textureHeight,		//-x
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + headWidth)/textureHeight,		//-z

				(headOffsetX + headHeight + headLength)/textureWidth, (headOffsetY)/textureHeight,	//B
				(headOffsetX + headHeight)/textureWidth, (headOffsetY)/textureHeight,					//-x
				(headOffsetX)/textureWidth, (headOffsetY + 2*headWidth + 2*headLength)/textureHeight,	//+z

				(headOffsetX + headHeight)/textureWidth, (headOffsetY + headWidth)/textureHeight,	//B
				(headOffsetX)/textureWidth, (headOffsetY + headWidth + headLength)/textureHeight,	//+x
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + headWidth + headLength)/textureHeight,	//-z

				(headOffsetX + headHeight)/textureWidth, (headOffsetY)/textureHeight,	//B
				(headOffsetX)/textureWidth, (headOffsetY + 2*headWidth + headLength)/textureHeight,	//+x
				(headOffsetX)/textureWidth, (headOffsetY + 2*headWidth + headLength)/textureHeight,	//+z
				// Top only:
				(headOffsetX + headHeight + headLength)/textureWidth, (headOffsetY + headWidth + headLength)/textureHeight,	//T

				(headOffsetX + headHeight + headLength)/textureWidth, (headOffsetY + 2*headWidth + headLength)/textureHeight,	//T
				
				(headOffsetX + headHeight)/textureWidth, (headOffsetY + headWidth + headLength)/textureHeight,	//T

				(headOffsetX + headHeight)/textureWidth, (headOffsetY + 2*headWidth + headLength)/textureHeight,	//T
		};
		float[] headNormals = new float[] {
				// Top:
				-1, 0, 0,
				0, 0, -1,
				-1, 0, 0,
				0, 0, 1,
				1, 0, 0,
				0, 0, -1,
				1, 0, 0,
				0, 0, 1,
				// Bottom:
				0, -1, 0,
				-1, 0, 0,
				0, 0, -1,
				0, -1, 0,
				-1, 0, 0,
				0, 0, 1,
				0, -1, 0,
				1, 0, 0,
				0, 0, -1,
				0, -1, 0,
				1, 0, 0,
				0, 0, 1,
		};
		int[] headIndices = new int[] {
				// Bottom:
				8, 14, 17,
				11, 8, 17,
				// -x:
				0, 9, 12,
				2, 0, 12,
				// +x:
				15, 4, 18,
				4, 6, 18,
				// -z:
				10, 1, 16,
				1, 5, 16,
				// +z:
				3, 13, 19,
				7, 3, 19,
				// Top:
				22, 20, 23,
				20, 21, 23,
		};
		Cubyz.renderDeque.add(new Runnable() {
			@Override
			public void run() {
				Material mat = new Material(Texture.loadFromFile("assets/" + source.getRegistryID().getMod() + "/entities/textures/" + source.getRegistryID().getID() + ".png"));
				leg = new Mesh(new Model(source.getRegistryID(), legPositions, legTextCoords, legNormals, legIndices));
				leg.setMaterial(mat);
				body = new Mesh(new Model(source.getRegistryID(), bodyPositions, bodyTextCoords, bodyNormals, bodyIndices));
				body.setMaterial(mat);
				head = new Mesh(new Model(source.getRegistryID(), headPositions, headTextCoords, headNormals, headIndices));
				head.setMaterial(mat);
			}
			
		});
	}

	@Override
	public void render(Matrix4f viewMatrix, Object entityShader, ClientEntity ent) {
		Vector3d pos = new Vector3d(ent.getRenderPosition()).sub(Cubyz.player.getPosition());
		Vector3f rotation =  new Vector3f(ent.rotation);
		pos.y += legHeight/2; // Adjust the body position by the height of the legs.
		body.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)pos.x, (float)pos.y, (float)pos.z), rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
		});
		double xNorm = ent.velocity.x/Math.sqrt(ent.velocity.x*ent.velocity.x + ent.velocity.z*ent.velocity.z);
		double zNorm = ent.velocity.z/Math.sqrt(ent.velocity.x*ent.velocity.x + ent.velocity.z*ent.velocity.z);
		if (xNorm != xNorm) {
			xNorm = 1;
			zNorm = 0;
		}
		pos.y -= bodyHeight/2 - legWidth/2;
		float length = bodyLength - legWidth - 0.01f;
		float width = bodyWidth - legWidth - 0.01f;
		float legAngle1 = ent.movementAnimation;
		float legAngle2 = legAngle1 - legHeight;
		if (legAngle1 >= legHeight) {
			legAngle1 = 2*legHeight - legAngle1;
		} else {
			legAngle2 = -legAngle2;
		}
		legAngle1 -= legHeight/2;
		legAngle2 -= legHeight/2;
		// Front side1:
		pos.x += xNorm*length/2 - zNorm*width/2;
		pos.z += zNorm*length/2 + xNorm*width/2;
		rotation.z = legAngle1;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)pos.x, (float)pos.y, (float)pos.z), rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
		});
		// Front side2:
		pos.x += zNorm*width;
		pos.z += -xNorm*width;
		rotation.z = movementPattern == MovementPattern.STABLE ? legAngle2 : legAngle1;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)pos.x, (float)pos.y, (float)pos.z), rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
		});
		// Back side2:
		pos.x += -xNorm*length;
		pos.z += -zNorm*length;
		rotation.z = movementPattern == MovementPattern.STABLE ? legAngle1 : legAngle2;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)pos.x, (float)pos.y, (float)pos.z), rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
		});
		// Back side1:
		pos.x += -zNorm*width;
		pos.z += xNorm*width;
		rotation.z = legAngle2;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)pos.x, (float)pos.y, (float)pos.z), rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
		});
		
		// Head:
		pos.x += xNorm*length + xNorm*headLength/2 + zNorm*width/2;
		pos.y += bodyHeight/2 - legWidth/2;
		pos.z += zNorm*length + zNorm*headLength/2 - xNorm*width/2;
		head.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(new Vector3f((float)pos.x, (float)pos.y, (float)pos.z), rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform(EntityRenderer.loc_viewMatrix, modelViewMatrix);
		});
		
	}
	@Override
	public void update(ClientEntity ent, float deltaTime) {
		float v = (float)Math.sqrt(ent.velocity.x*ent.velocity.x + ent.velocity.z*ent.velocity.z);
		ent.movementAnimation += v*deltaTime;
		ent.movementAnimation %= 2*legHeight;
	}
	@Override
	public double getCollisionDistance(Vector3d playerPosition, Vector3f dir, Entity ent) {
		double xNorm = ent.targetVX/Math.sqrt(ent.targetVX*ent.targetVX + ent.targetVZ*ent.targetVZ);
		double zNorm = ent.targetVZ/Math.sqrt(ent.targetVX*ent.targetVX + ent.targetVZ*ent.targetVZ);
		Vector3d newDir = new Vector3d(dir);
		newDir.z = dir.x*xNorm + dir.z*zNorm;
		newDir.x = -dir.x*zNorm + dir.z*xNorm;
		double distanceZ = (ent.getPosition().x-playerPosition.x)*xNorm + (ent.getPosition().z-playerPosition.z)*zNorm;
		double distanceX = -(ent.getPosition().x-playerPosition.x)*zNorm + (ent.getPosition().z-playerPosition.z)*xNorm;
		Vector2d res = new Vector2d();
		boolean intersects = Intersectiond.intersectRayAab(0, Player.cameraHeight, 0, newDir.x, newDir.y, newDir.z, distanceX-bodyWidth/2, (float)(ent.getPosition().y - playerPosition.x), distanceZ-bodyLength/2, distanceX+bodyWidth/2, ent.getPosition().y+bodyHeight+legHeight, distanceZ+bodyLength/2+headLength-0.01f, res);
		return intersects ? res.x : Double.MAX_VALUE;
	}
	
}
