//@exe
//@debug

//Note: This is a test application for the automated, DIDE integrated shader compiler thing

import het; void main() { console({ new Detector; }); } 

class Detector
{
	static immutable shader = 
	(碼!(iq{glslc -D="define1"}.text,iq{
		#version 430
		
		@vert: 
		layout(binding = 0) uniform UniformBufferObject { mat4 mvp; } ubo; 
		layout(location = 0) 
		in vec3 inPosition; layout(location = 1)
		in vec3 inColor; layout(location = 0)
		out vec3 fragColor; 
		
		#ifdef define1
		int x = fuck * off; 
		#endif
		
		void main() {
			int unusedVar = 5; 
			gl_Position = ubo.mvp * vec4(inPosition, 1.0); 
			fragColor = inColor; 
		} 
		
		@frag: 
		layout(location = 0)
		in vec3 fragColor; layout(location = 0)
		out vec4 outColor; 
		
		void main() { outColor = vec4(fragColor, 1.0); } 
	}.text)); 
	
	this()
	{ shader.hexDump; } 
} 