//@exe
//@debug
///@release

import het, het.parser; 

version(none)
{
	
	/+
		Note: MixinDeclaration:	mixin ( ArgumentList ) ;
		MixinType:    	mixin ( ArgumentList )
		MixinExpression:    	mixin ( ArgumentList )
		MixinStatement:    	mixin ( ArgumentList ) ;
		
		Detection:
			Detect "mixin" keyword before ()
			That CAN substituted into a niceExpression block.
			Must be processed inside Statements and Expressions. (goInside = Expression)
	+/
	
	/+0:+/mixin("string mixin as declaration"); 
	const mixin("string mixin as type") name; 
	const a =mixin("string mixin expression"); 
	const a =mixin("string mixin type")(mixin("string mixin expression1")+mixin("string mixin expression1")); 
	mixin 
	/+comment+/
	(); void f(mixin("arg"))
	{
		mixin("123").xyz; 
		(mixin("123").xyz); 
	} 
	/+
		Note: TemplateMixinDeclaration:  /+Link: -> DIDE.Declaration+/
		    mixin template Identifier TemplateParameters Constraintopt { DeclDefsopt }
		
		TemplateMixin: 
					 mixin MixinTemplateName TemplateArgumentsopt Identifieropt ;
					 mixin Identifier = MixinTemplateName TemplateArgumentsopt ;
		
		MixinTemplateName:  /+It NEVER starts with ()+/
					 . MixinQualifiedIdentifier
					 MixinQualifiedIdentifier
					 Typeof . MixinQualifiedIdentifier
		
		MixinQualifiedIdentifier:
					 Identifier
					 Identifier . MixinQualifiedIdentifier
					 TemplateInstance . MixinQualifiedIdentifier
	+/
	
	mixin SimpleTemplate; 
	mixin .modul.TemplateName!(arg1,mixin("arg2")); 
	mixin .modul.TemplateName!(arg1) instanceName2; 
	/+
		1.40 doesn't support this -> 
		/+Code: mixin instanceName3 = .modul.TemplateName!(arg1); +/
	+/
	
}
version(none)
{
	
	/+
		Note: MixinDeclaration:	mixin ( ArgumentList ) ;
		MixinType:    	mixin ( ArgumentList )
		MixinExpression:    	mixin ( ArgumentList )
		MixinStatement:    	mixin ( ArgumentList ) ;
		
		Detection:
			Detect "mixin" keyword before ()
			That CAN substituted into a niceExpression block.
			Must be processed inside Statements and Expressions. (goInside = Expression)
	+/
	
	/+0:+/mixin("string mixin as declaration"); 
	mixin("string mixin as declaration"); 
	const a =   mixin("string mixin as type")	name; 
	const a =  mixin("string mixin expression"); 	struct ; 
	const a =mixin("string mixin type")(mixin("string mixin expression1")+mixin("string mixin expression1")); 
	mixin /+comment+/
	(); void f(mixin("arg"))
	{
		mixin("123").xyz; 
		(mixin("123").xyz); 
	} 
	/+
		Note: TemplateMixinDeclaration:  /+Link: -> DIDE.Declaration+/
		    mixin template Identifier TemplateParameters Constraintopt { DeclDefsopt }
		
		TemplateMixin: 
					 mixin MixinTemplateName TemplateArgumentsopt Identifieropt ;
					 mixin Identifier = MixinTemplateName TemplateArgumentsopt ;
		
		MixinTemplateName:  /+It NEVER starts with ()+/
					 . MixinQualifiedIdentifier
					 MixinQualifiedIdentifier
					 Typeof . MixinQualifiedIdentifier
		
		MixinQualifiedIdentifier:
					 Identifier
					 Identifier . MixinQualifiedIdentifier
					 TemplateInstance . MixinQualifiedIdentifier
	+/
	
	public alias aliasStatement = aa; 
	static enum enumStatement; 
	mixin(blabla) name/+this is a string mixin, not a mixin template+/; 
	mixin mixinStatement/+this is a mixin template+/; 
	static immutable mixin SimpleTemplate /+this one is NOT detected+/; 
	mixin .modul.TemplateName!(arg1,mixin("arg2")); 
	mixin .modul.TemplateName!(arg1) instanceName2; 
	/+
		1.40 doesn't support this -> 
		/+Code: mixin instanceName3 = .modul.TemplateName!(arg1); +/
	+/
	{ pragma(msg, 123); }
	pragma(123) static	int i=5 ~ __traits(
		compiles, {
			int i = 123+256; 
			if(i>2) { beep; }
		}
	); 
	pragma(123) {} 
	
}
version(none)
{
	import std; 
	
	struct TABLE { int[][] rows; } 
	
	mixin template INJECT_DECLARATIONS(alias _data, string _script) { mixin(_script); } 
	
	alias /+ Chinese traditional <-> hetLib dictionary +/
		表 = TABLE,
		入 = INJECT_DECLARATIONS; 
	
	enum scopeValue = 1000; 
	
	const mixin 入!(
		(表([[q{
			[
				[1,2,3],
				[4,5,6],
				[7,8,9]
			]
		}],])),q{
			int injectedValue = 
				scopeValue 	//use any CT values from the scope
				+ _data.rows.map!"a.sum".sum	//work with the table struct (fast binary operations)
				+ ((){ int x = _data.rows[0][0] + 100_000; return x; }())	//do heavy calculations in a nested statement block
				+ mixin(iq{$( _data.rows[0][0] + scopeValue+10000 )}.text)	//last resort: inject any code as string (slow string operations!!!)
			; 
		}
	); 
	
	void main()
	{
		writeln(typeof(injectedValue).stringof, " ", injectedValue); 
		
		/+
			Pattern detected by DIDE:
				(表([[...],...]))			//TABLE
				mixin 入!((expr),q{expr});   //INJECT_DECLARATIONS
		+/
	} 
}
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
			mixin(求each(q{i=0},q{4},q{
				((0x17B98F6F833B).檢(mixin(指(q{x},q{0})) ~= a(mixin(界0(q{1},q{i},q{4 }))))),
				((0x18108F6F833B).檢(mixin(指(q{x},q{1})) ~= a(mixin(界1(q{1},q{i},q{4 }))))),
				((0x18678F6F833B).檢(mixin(指(q{x},q{2})) ~= a(mixin(界2(q{1},q{i},q{4 }))))),
				((0x18BE8F6F833B).檢(mixin(指(q{x},q{3})) ~= a(mixin(界3(q{1},q{i},q{4 }))))),
				((0x19158F6F833B).檢(mixin(指(q{x},q{4})) ~= a(mixin(等(q{2},q{i},q{4-i})))))
			})); 
			
			
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