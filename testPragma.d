import std; 

template 碼/+ExternalCode+/(string args, string src, string FILE=__FILE__, int LINE=__LINE__)
{
	pragma(msg, FILE, "(", LINE, ",1): $DIDE_EXTERNAL_COMPILATION_REQUEST: ", args.only.format!"%(%s%)"); 
	pragma(msg, src /+Must not use transformation functions, because the CTFE interpreter is slow.+/); 
	enum hash = src.hashOf(args.hashOf).to!string(26) /+hashOf CTFE performance: 1.2ms / 1KB+/; 
	pragma(msg, FILE, "(", LINE, ",1): $DIDE_EXTERNAL_COMPILATION_REQUEST: END(", hash, ")"); 
	enum 碼 = (cast(immutable(ubyte)[])(import(hash))); 
	static if(碼.startsWith(cast(ubyte[])("ERROR:")))
	{
		pragma(msg, (cast(string)(碼)).splitter('\n').drop(1).join('\n')); 
		static assert(false, "$DIDE_EXTERNAL_COMPILATION_"~(cast(string)(碼)).splitter('\n').front); 
	}
} 

enum N = 600_000/7; 
enum a = 碼!("commandline", "program".replicate(N)); 
enum b = 碼!("commandline", "progra2".replicate(N)); 

void main() {
	writeln(a); 
	writeln((cast(string)(b))~".2"); 
} 

//ldc2 testPragma.d > a.txt 2>&1