import std; 

template 碼/+ExternalCode+/(string args, string src, string FILE=__FILE__, int LINE=__LINE__)
{
	pragma(msg, "$DIDE_TEXTBLOCK_BEGIN$"); 
	pragma(msg, src /+Must not use transformation functions, because the CTFE interpreter is slow.+/); 
	pragma(msg, "$DIDE_TEXTBLOCK_END$"); 
	enum hash = /+src.hashOf(args.hashOf).to!string(26)+/"HHH" /+hashOf CTFE performance: 1.2ms / 1KB+/; 
	pragma(msg, FILE, "(", LINE, ",1): $DIDE_EXTERNAL_COMPILATION_REQUEST: ", only(args, hash).format!"%(%s%)"); 
	enum 碼 = (cast(immutable(ubyte)[])(/+import(hash)+/"OK\nhehh")); 
	static if(碼.startsWith(cast(ubyte[])("ERROR:")))
	{
		pragma(msg, (cast(string)(碼)).splitter('\n').drop(1).join('\n')); 
		static assert(false, "$DIDE_EXTERNAL_COMPILATION_"~(cast(string)(碼)).splitter('\n').front); 
	}
} 

auto 碼2/+ExternalCode+/(string args, string src, string FILE=__FILE__, int LINE=__LINE__)()
{
	__ctfeWrite("$DIDE_TEXTBLOCK_BEGIN$\n"); 
	__ctfeWrite(src /+Must not use transformation functions, because the CTFE interpreter is slow.+/); 
	__ctfeWrite("$DIDE_TEXTBLOCK_END$\n"); 
	enum hash = /+src.hashOf(args.hashOf).to!string(26)+/"HHH" /+hashOf CTFE performance: 1.2ms / 1KB+/; 
	__ctfeWrite(FILE~"("~LINE~",1): $DIDE_EXTERNAL_COMPILATION_REQUEST: "~only(args, hash).format!"%(%s%)"~"\n"); 
	enum 碼 = (cast(immutable(ubyte)[])(/+import(hash)+/"OK\nhehh")); 
	static if(碼.startsWith(cast(ubyte[])("ERROR:")))
	{
		__ctfeWrite((cast(string)(碼)).splitter('\n').drop(1).join('\n')~"\n"); 
		static assert(false, "$DIDE_EXTERNAL_COMPILATION_"~(cast(string)(碼)).splitter('\n').front); 
	}
	return 碼; 
} 

enum N = 10_000_000/7; 
enum a = 碼!("commandline", "program".replicate(N)); 
enum b = 碼!("commandline", "progra2".replicate(N)); 

void main() {
	writeln(a); 
	writeln((cast(string)(b))~".2"); 
} 

//ldc2 testPragma.d --enable-color=0 > a.txt 2>&1