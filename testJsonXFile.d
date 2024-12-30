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

/+
	size_t calcMem(ModuleJson[] items)
	{ return Item.sizeof*items.length + items.map!((a)=>(a.members.calcMem + a.parameters.calcMem)).sum; } 
+/

void main()
{
	console(
		{
			
			/+(等!((2),(i),(4-i))).print;+/
			
			string[5] x; auto a(bool b) => ((b)?('✅'):('❌')); 
			(mixin(求each(q{i=0},q{4},q{
				((0x5188F6F833B).檢((mixin(指(q{x},q{0}))) ~= a(mixin(界0(q{1},q{i},q{4 }))))),
				((0x5708F6F833B).檢((mixin(指(q{x},q{1}))) ~= a(mixin(界1(q{1},q{i},q{4 }))))),
				((0x5C88F6F833B).檢((mixin(指(q{x},q{2}))) ~= a(mixin(界2(q{1},q{i},q{4 }))))),
				((0x6208F6F833B).檢((mixin(指(q{x},q{3}))) ~= a(mixin(界3(q{1},q{i},q{4 }))))),
				((0x6788F6F833B).檢((mixin(指(q{x},q{4}))) ~= a(mixin(等(q{2},q{i},q{4-i})))))
			}))); 
			
			/+
				Code: //first version.	Flaw: aliases can't hold expressions.
				(mixin(求each(q{i=0},q{4},q{
					((0x4EE8F6F833B).檢((mixin(指(q{x},q{0}))) ~= a(界0!((1),(i),(4))))),
					((0x53C8F6F833B).檢((mixin(指(q{x},q{1}))) ~= a(界1!((1),(i),(4))))),
					((0x58A8F6F833B).檢((mixin(指(q{x},q{2}))) ~= a(界2!((1),(i),(4))))),
					((0x5D88F6F833B).檢((mixin(指(q{x},q{3}))) ~= a(界3!((1),(i),(4)))))
				}))); 
				
				//2nd version with string mixins.
				(mixin(求each(q{i=0},q{4},q{
					((0x5198F6F833B).檢((mixin(指(q{x},q{0}))) ~= a(mixin(界0(q{1},q{i},q{4}))))),
					((0x5708F6F833B).檢((mixin(指(q{x},q{1}))) ~= a(mixin(界1(q{1},q{i},q{4}))))),
					((0x5C78F6F833B).檢((mixin(指(q{x},q{2}))) ~= a(mixin(界2(q{1},q{i},q{4}))))),
					((0x61E8F6F833B).檢((mixin(指(q{x},q{3}))) ~= a(mixin(界3(q{1},q{i},q{4}))))),
					((0x6758F6F833B).檢((mixin(指(q{x},q{4}))) ~= a(mixin(等(q{2},q{i},q{4})))))
				}))); 
			+/
			
			
			auto _間=init間; 
			/+
				string txt; 
				Item[] i2; {
					if((常!(bool)(1))) txt = `c:\d\projects\karc\het.vulkan.json`.File.readText; 
					if((常!(bool)(0))) txt = `c:\d\projects\karc\het.vulkan.json`.File.readText; 
				}	((0x6F58F6F833B).檢((update間(_間)))); 
				i2.fromJson(txt); 	((0x7378F6F833B).檢((update間(_間)))); 
				((0x7668F6F833B).檢(i2.calcMem)); 	((0x78A8F6F833B).檢((update間(_間)))); 
				i2.each!(dump!`true`); 	((0x7D18F6F833B).檢((update間(_間)))); 
			+/
		}
	); 
} 