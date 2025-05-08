module testShaderSys; 

import het; 

/+Link: https://forum.dlang.org/post/qvhuuvffecozcfcshhkf@forum.dlang.org+/

template 碼/+ExternalCode+/(string args, string src, string FILE=__FILE__, int LINE=__LINE__)
{
	pragma(msg, i"$(FILE)($(LINE+1),1): $DIDE_EXTERNAL_COMPILATION_REQUEST: [$(args.quoted),$(src.quoted)]".text); 
	const hash = src.hashOf(args.hashOf).to!string(26); 
	enum 碼 = (cast(immutable(ubyte)[])(import(hash))); 
	static if(碼.startsWith(cast(ubyte[])("ERROR:")))
	{
		pragma(msg, (cast(string)(碼)).splitter('\n').drop(1).join('\n')); 
		static assert(false, "$DIDE_EXTERNAL_COMPILATION_"~(cast(string)(碼)).splitter('\n').front); 
	}
} 