//@exe
//@debug
//@compile -J c:\d\projects\dide\

//Note: This is a test application for the automated, DIDE integrated shader compiler thing

import het, het.projectedfslib, testShaderSys; 

class Detector
{
	static immutable Parameter1 = 42; 
	
	enum shdr = (
		ShaderCode!	(
			"GLSL", iq{
				//test shader 🤓
				
				const parameter = $(Parameter1); 
				$(typeof(this).stringof)
				void main() {} 
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