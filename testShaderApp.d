//@exe
//@debug
//@compile -J c:\d\projects\dide\

//Note: This is a test application for the automated, DIDE integrated shader compiler thing

import het, testShaderSys; 

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

void main() {
	console(
		{
			new Detector; 
			
			import projectedfslib; 
			
			const rootPath = Path(`z:\temp2\DIDE_projFS_`~now.raw.to!string(26)); 
			auto _間=init間; 
			auto pvd = new DynamicFileProvider(rootPath); 
			foreach(i; 0..60) sleep(1000); 
			pvd.free; 
			((0x3220D266E3E).檢((update間(_間)))); 
			
			
			
			
			
			
		}
	); 
} 