//@exe
//@debug
//@compile -J c:\d\projects\dide\

//Note: This is a test application for the automated, DIDE integrated shader compiler thing

import het, het.projectedfslib, testShaderSys; 

alias 碼(A...) = ExternalCode!(A); 
//Todo: vertical tab support in q{} iq{ } /++/ /**/

class Detector
{
	static immutable Parameter1 = 42; 
	//icon: 🧾📄🧩;
	enum shdr = (
		碼!	(
			iq{glslc}.text, iq{
				#version 430
				
				@vert: 
				layout(binding = 0) uniform UniformBufferObject { mat4 mvp; } ubo; 
				
				layout(location = 0) in vec3 inPosition; 
				layout(location = 1) in vec3 inColor; 
				
				layout(location = 0) out vec3 fragColor; 
				
				//test comment $(Parameter1)
				
				void main() {
					gl_Position = ubo.mvp * vec4(inPosition, 1.0); 
					fragColor = inColor; 
				} 
				
				@frag: 
				#version 430
				
				layout(location = 0) in vec3 fragColor; 
				
				layout(location = 0) out vec4 outColor; 
				
				void main() { outColor = vec4(fragColor, 1.0); } 
			}.text
		)
	); 
	
	this()
	{
		writeln("Shader created:"); 
		writeln(shdr); 
	} 
} 

void main() { console({ new Detector; }); } 