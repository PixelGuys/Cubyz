package io.cubyz.base.entity_models;

import java.io.IOException;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import io.cubyz.CubyzLogger;
import io.cubyz.api.Resource;
import io.cubyz.client.Cubyz;
import io.cubyz.entity.Entity;
import io.cubyz.entity.EntityModel;
import io.cubyz.entity.EntityType;
import io.jungle.Mesh;
import io.jungle.Texture;
import io.jungle.renderers.Transformation;
import io.jungle.util.Material;
import io.jungle.util.ShaderProgram;

public class Quadruped implements EntityModel {
	// Registry stuff:
	Resource id = new Resource("cuybz:quadruped");
	public Quadruped() {}
	@Override
	public Resource getRegistryID() {
		return id;
	}
	@Override
	public EntityModel createInstance(int[] args, EntityType source) {
		if(args.length != 7) {
			CubyzLogger.instance.warning("Wrong data for entity model "+id+": Found "+args.length+" ints but requiered "+7+". Skipping model.");
			return this;
		}
		
		return new Quadruped(args[0], args[1], args[2], args[3], args[4], args[5], args[6], source);
	}
	
	// Actual model stuff:
	private Mesh leg, body, head;
	float bodyWidth, bodyLength, bodyHeight, legHeight, legWidth, headHeight, headWidth;
	
	public Quadruped(int bodyWidth, int bodyLength, int bodyHeight, int legHeight, int legWidth, int headHeight, int headWidth, EntityType source) {
		this.bodyWidth = bodyWidth/16.0f;
		this.bodyLength = bodyLength/16.0f;
		this.bodyHeight = bodyHeight/16.0f;
		this.legHeight = legHeight/16.0f;
		this.legWidth = legWidth/16.0f;
		this.headHeight = headHeight/16.0f;
		this.headWidth = headWidth/16.0f;
		float textureWidth = 4*legWidth + bodyLength + bodyHeight;
		float textureHeight = Math.max(2*bodyWidth + 2*bodyHeight, legHeight + legWidth);
		// leg obj:
		int legOffset = bodyLength + bodyHeight;
		float[] legPositions = new float[] {
				// Top(each vertex two times(the top face is not rendered)):
				-legWidth/32.0f,	0,						-legWidth/32.0f,	//0
				-legWidth/32.0f,	0,						-legWidth/32.0f,	//1
				-legWidth/32.0f,	0,						legWidth/32.0f,		//2
				-legWidth/32.0f,	0,						legWidth/32.0f,		//3
				legWidth/32.0f,		0,						-legWidth/32.0f,	//4
				legWidth/32.0f,		0,						-legWidth/32.0f,	//5
				legWidth/32.0f,		0,						legWidth/32.0f,		//6
				legWidth/32.0f,		0,						legWidth/32.0f,		//7
				// Bottom(each vertex three times):
				-legWidth/32.0f,	-legHeight/16.0f,		-legWidth/32.0f,	//8
				-legWidth/32.0f,	-legHeight/16.0f,		-legWidth/32.0f,	//9
				-legWidth/32.0f,	-legHeight/16.0f,		-legWidth/32.0f,	//10
				-legWidth/32.0f,	-legHeight/16.0f,		legWidth/32.0f,		//11
				-legWidth/32.0f,	-legHeight/16.0f,		legWidth/32.0f,		//12
				-legWidth/32.0f,	-legHeight/16.0f,		legWidth/32.0f,		//13
				legWidth/32.0f,		-legHeight/16.0f,		-legWidth/32.0f,	//14
				legWidth/32.0f,		-legHeight/16.0f,		-legWidth/32.0f,	//15
				legWidth/32.0f,		-legHeight/16.0f,		-legWidth/32.0f,	//16
				legWidth/32.0f,		-legHeight/16.0f,		legWidth/32.0f,		//17
				legWidth/32.0f,		-legHeight/16.0f,		legWidth/32.0f,		//18
				legWidth/32.0f,		-legHeight/16.0f,		legWidth/32.0f,		//19
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
				-bodyLength/32.0f,	bodyHeight/32.0f,		-bodyWidth/32.0f,		//0
				-bodyLength/32.0f,	bodyHeight/32.0f,		-bodyWidth/32.0f,		//1
				-bodyLength/32.0f,	bodyHeight/32.0f,		bodyWidth/32.0f,		//2
				-bodyLength/32.0f,	bodyHeight/32.0f,		bodyWidth/32.0f,		//3
				bodyLength/32.0f,	bodyHeight/32.0f,		-bodyWidth/32.0f,		//4
				bodyLength/32.0f,	bodyHeight/32.0f,		-bodyWidth/32.0f,		//5
				bodyLength/32.0f,	bodyHeight/32.0f,		bodyWidth/32.0f,		//6
				bodyLength/32.0f,	bodyHeight/32.0f,		bodyWidth/32.0f,		//7
				// Bottom(each vertex three times):
				-bodyLength/32.0f,	-bodyHeight/32.0f,		-bodyWidth/32.0f,		//8
				-bodyLength/32.0f,	-bodyHeight/32.0f,		-bodyWidth/32.0f,		//9
				-bodyLength/32.0f,	-bodyHeight/32.0f,		-bodyWidth/32.0f,		//10
				-bodyLength/32.0f,	-bodyHeight/32.0f,		bodyWidth/32.0f,		//11
				-bodyLength/32.0f,	-bodyHeight/32.0f,		bodyWidth/32.0f,		//12
				-bodyLength/32.0f,	-bodyHeight/32.0f,		bodyWidth/32.0f,		//13
				bodyLength/32.0f,	-bodyHeight/32.0f,		-bodyWidth/32.0f,		//14
				bodyLength/32.0f,	-bodyHeight/32.0f,		-bodyWidth/32.0f,		//15
				bodyLength/32.0f,	-bodyHeight/32.0f,		-bodyWidth/32.0f,		//16
				bodyLength/32.0f,	-bodyHeight/32.0f,		bodyWidth/32.0f,		//17
				bodyLength/32.0f,	-bodyHeight/32.0f,		bodyWidth/32.0f,		//18
				bodyLength/32.0f,	-bodyHeight/32.0f,		bodyWidth/32.0f,		//19
				// Top face:
				-bodyLength/32.0f,	bodyHeight/32.0f,		-bodyWidth/32.0f,		//20
				-bodyLength/32.0f,	bodyHeight/32.0f,		bodyWidth/32.0f,		//21
				bodyLength/32.0f,	bodyHeight/32.0f,		-bodyWidth/32.0f,		//22
				bodyLength/32.0f,	bodyHeight/32.0f,		bodyWidth/32.0f,		//23
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
		Cubyz.renderDeque.add(new Runnable() { // TODO: Why is this so complex?
			@Override
			public void run() {
				try {
					Material mat = new Material(new Texture("addons/" + source.getRegistryID().getMod() + "/entities/textures/" + source.getRegistryID().getID() + ".png"));
					leg = new Mesh(legPositions, legTextCoords, legNormals, legIndices);
					leg.setMaterial(mat);
					body = new Mesh(bodyPositions, bodyTextCoords, bodyNormals, bodyIndices);
					body.setMaterial(mat);
					head = body; // TODO: Head model.
				} catch (IOException e) {
					e.printStackTrace();
				}
			}
			
		});
	}

	@Override
	public void render(Matrix4f viewMatrix, Object entityShader, Entity ent) {
		Vector3f pos = new Vector3f(ent.getRenderPosition());
		Vector3f rotation =  new Vector3f(ent.getRotation());
		pos.y += legHeight/2; // Adjust the body position by the height of the legs.
		body.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(pos, rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform("modelViewMatrix", modelViewMatrix);
		});
		float xNorm = ent.vx/(float)Math.sqrt(ent.vx*ent.vx + ent.vz*ent.vz);
		float zNorm = ent.vz/(float)Math.sqrt(ent.vx*ent.vx + ent.vz*ent.vz);
		pos.y -= bodyHeight/2 - legWidth/2;
		float length = bodyLength - legWidth - 0.01f;
		float width = bodyWidth - legWidth - 0.01f;
		float legAngle1 = ent.movementAnimation;
		float legAngle2 = legAngle1 - legHeight;
		if(legAngle1 >= legHeight) {
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
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(pos, rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform("modelViewMatrix", modelViewMatrix);
		});
		// Front side2:
		pos.x += zNorm*width;
		pos.z += -xNorm*width;
		rotation.z = legAngle2;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(pos, rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform("modelViewMatrix", modelViewMatrix);
		});
		// Back side2:
		pos.x += -xNorm*length;
		pos.z += -zNorm*length;
		rotation.z = legAngle1;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(pos, rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform("modelViewMatrix", modelViewMatrix);
		});
		// Back side1:
		pos.x += -zNorm*width;
		pos.z += xNorm*width;
		rotation.z = legAngle2;
		leg.renderOne(() -> {
			Matrix4f modelViewMatrix = Transformation.getModelViewMatrix(Transformation.getModelMatrix(pos, rotation, 1), viewMatrix);
			((ShaderProgram)entityShader).setUniform("modelViewMatrix", modelViewMatrix);
		});
		
	}
	@Override
	public void update(Entity ent) {
		float v = (float)Math.sqrt(ent.vx*ent.vx + ent.vz*ent.vz);
		ent.movementAnimation += v;
		ent.movementAnimation %= 2*legHeight;
	}
	
}
