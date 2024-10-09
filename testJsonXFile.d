//@exe
//@debug
///@release

import het, het.parser; 
/+
	by kind
	module: name, file
	
+/
struct Item
{
	string kind, name; 
	
	Item[] parameters, members; 
	string[] storageClass, overrides; 
	string protection, base, init_, type, originalType, file, deco, baseDeco, value, defaultValue, default_; 
	int line, char_, endline, endchar, offset; 
} 

void dump(alias pred="true")(const ref Item item, string path="")
{
	if(item.name=="") return; 
	
	if(unaryFun!pred(item))
	{
		auto p = item.parameters.map!"a.type~` `~a.name".join(", "); 
		print(item.kind.padRight(' ', 20), path~item.name~((p!="")?("("~p~")"):(""))); 
	}
	foreach(a; item.members) dump!pred(a, path~item.name~"."); 
} 

size_t calcMem(Item[] items)
{ return Item.sizeof*items.length + items.map!((a)=>(a.members.calcMem + a.parameters.calcMem)).sum; } 

void main()
{
	console(
		{
			auto _間=init間; 
			Item[] i2; const txt = `c:\d\projects\karc\het.vulkan.json`.File.readText; 	((0x3E38F6F833B).檢((update間(_間)))); 
			i2.fromJson(txt); 	((0x4258F6F833B).檢((update間(_間)))); 
			((0x4548F6F833B).檢(i2.calcMem)); 	((0x4788F6F833B).檢((update間(_間)))); 
			i2.each!(dump!`true`); 	((0x4BF8F6F833B).檢((update間(_間)))); 
		}
	); 
} 