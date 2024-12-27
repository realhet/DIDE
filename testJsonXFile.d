//@exe
//@debug
///@release

import het, het.parser; 


class ModuleJson
{
	static struct Item
	{
		string kind, name; 
		
		Item[] parameters, members; 
		string[] storageClass, overrides, selective/+import+/; 
		string protection, base, init_, type, originalType, file, deco, baseDeco, value, defaultValue, default_; 
		int line, char_, endline, endchar, offset; 
		
		void dump(alias pred="true")(const ref Item item, string path="")
		{
			if(name=="") return; 
			
			if(unaryFun!pred(item))
			{
				auto p = parameters.map!"a.type~` `~a.name".join(", "); 
				print(kind.padRight(' ', 20), path~name~((p!="")?("("~p~")"):(""))); 
			}
			foreach(ref a; members) a.dump!pred(a, path~name~"."); 
		} 
	} 
	
	void dump(alias pred="true")()
	{ foreach(ref a; items) a.dump!pred(a, path~a.name~"."); } 
	
	string path; 
	Item[] items; 
	
	this(string path, string moduleJson)
	{} 
} 


/+
	by kind
	module: name, file
	
+/

size_t calcMem(ModuleJson[] items)
{ return Item.sizeof*items.length + items.map!((a)=>(a.members.calcMem + a.parameters.calcMem)).sum; } 

void main()
{
	console(
		{
			auto _間=init間; 
			string txt; 
			Item[] i2; {
				if((常!(bool)(1))) txt = `c:\d\projects\karc\het.vulkan.json`.File.readText; 
				if((常!(bool)(0))) txt = `c:\d\projects\karc\het.vulkan.json`.File.readText; 
			}	((0x5658F6F833B).檢((update間(_間)))); 
			i2.fromJson(txt); 	((0x5A78F6F833B).檢((update間(_間)))); 
			((0x5D68F6F833B).檢(i2.calcMem)); 	((0x5FA8F6F833B).檢((update間(_間)))); 
			i2.each!(dump!`true`); 	((0x6418F6F833B).檢((update間(_間)))); 
		}
	); 
} 