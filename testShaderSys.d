module testShaderSys; 

import het; 

/+Link: https://forum.dlang.org/post/qvhuuvffecozcfcshhkf@forum.dlang.org+/

template ShaderCode(string lang, string src, string FILE=__FILE__, int LINE=__LINE__)
{
	//enum src = A.text;  
	pragma(msg, i"$(FILE)($(LINE),1): ExtSrc: $(src.quoted)".text); 
	
	struct CompilationResult { mixin(import("testShaderResult.d")); }; 
	
	enum ShaderCode = src ~ CompilationResult.data; 
} 