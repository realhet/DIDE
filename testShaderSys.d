module testShaderSys; 

import het; 

/+Link: https://forum.dlang.org/post/qvhuuvffecozcfcshhkf@forum.dlang.org+/

template ExteralCode(string spec, string src, string FILE=__FILE__, int LINE=__LINE__)
{
	pragma(msg, i"$(FILE)($(LINE),1): DIDE_ExternalCompilationRequest: $(spec.quoted),$(src.quoted)".text); 
	
	struct CompilationResult { mixin(import("testShaderResult.d")); }; 
	
	enum ExternalCode = src ~ CompilationResult.data; 
} 