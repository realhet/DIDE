import std;

string transform(string a)
{
	auto b = cast(ubyte[])a.dup;
	foreach(ref ch; b) if(ch=='x') ch = 'y';
	return cast(string)b;
}

string doit(string data)()
{
	static foreach(i; 0..1)
	{
		//enum data2 = data.transform;
		pragma(msg, "Here goes lots of data: ", data);
	}
	return "dummy";
}

static immutable storedData = doit!("x".replicate(256*256*256));

void main(){ writeln(storedData.length, storedData.all!"a=='x'"); }

//ldc2 testPragma.d > a.txt 2>&1