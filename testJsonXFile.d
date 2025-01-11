//@exe
//@debug
//@release

import std.parallelism; 

version(all)
{
	/+
		ChatGPT query:
		In dlang I have an array of strings.
		The strings contain fully qualified names of an identifier, with the full path, separated by dot '.' character.
		The individual parts can contain a template parameter list after the identifier eg: "id!(1, 2)" These are part of the identifier, this specifies a single path location.
		After the last identifier with optional template parameters, there can be a parameter list, it that particular item is a function. Example: "fun(int param1, string param2) : string"
		Your task is to process the alphabetically ordered input string array with the fully qualified names and produce a hierarchical text output with visual block drawing characters. It should look like the result of the DOS tree command.
	+/
	
	
	import std.regex; 
	
	
	// Structure to represent a node in the hierarchy
	struct TreeNode(T)
	{
		T data; 
		TreeNode[] children; 
		
		this(T data) { this.data = data; } 
		
		void addChild(TreeNode node) { children ~= node; } 
	} 
	
	// Parse a fully qualified name into its components
	string[] parseQualifiedName(string fullyQualifiedName)
	{
		//auto regex = ctRegex!`(?<!\w)([a-zA-Z_][a-zA-Z0-9_]*!(\([^)]*\))?|[a-zA-Z_][a-zA-Z0-9_]*)(\([^)]*\)\s*:\s*[a-zA-Z_][a-zA-Z0-9_]*\s*)?`; 
		//auto regex = ctRegex!`([a-zA-Z_][a-zA-Z0-9_]*!(\\([^)]*\\))?|[a-zA-Z_][a-zA-Z0-9_]*)(\\([^)]*\\)\\s*:\\s*[a-zA-Z_][a-zA-Z0-9_]*|\\([^)]*\\))?`; 
		auto regex = ctRegex!`[a-zA-Z_][a-zA-Z0-9_]*(?:!(\\([^)]*\\)))?(?:\\([^)]*\\))?`; 
		return fullyQualifiedName.matchAll(regex).map!(m => m.hit).array; 
	} 
	
	// Add a fully qualified name to the tree
	void addQualifiedName(ref TreeNode!string root, string[] parts)
	{
		auto current = &root; 
		
		foreach(part; parts) {
			auto child = current.children.find!(c => c.data == part); 
			if(child.empty) {
				current.children ~= TreeNode!string(part); 
				current = &current.children[$ - 1]; 
			}else { current = &child.front; }
		}
	} 
	
	// Generate the hierarchical tree output
	static if(0)
	void printTree(TreeNode!string node, string prefix = "")
	{
		writeln(prefix, node.data); 
		
		foreach(i, child; node.children) {
			string newPrefix = prefix ~ (i == node.children.length - 1 ? "  └─" : "  ├─"); 
			printTree(child, newPrefix); 
		}
		
		/+
			- Thank you! There were some errors, but I was able to fix.  It was DLang specific stuff, I know your knowledge is mainly C++.  Dlang is an exotic language..
			GPT: You're welcome! I'm glad you could resolve the issues—it's always impressive to work with such a niche language like DLang. If you need help fine-tuning or exploring other ideas, just let me know!
			
			- But the result is not perfect:
			root
				 └─com
				 └─	 └─example
				 └─	 └─	 ├─Class!(int, string)
				 └─	 └─	 ├─  └─method(int x, int y) : void
				 └─	 └─	 └─OtherClass
				 └─	 └─	 └─  └─subMethod!(true)
			GPT: Thank you for pointing that out! The issue lies in the incorrect use of block-drawing characters in the tree output. Specifically, the prefixes (├─, └─, etc.) aren't being constructed properly when traversing multiple levels of the tree.
			
			Here's the fixed version of the printTree function that ensures the tree structure renders correctly:
		+/
	} 
	
	// Generate the hierarchical tree output
	void printTree(in TreeNode!string node, string prefix = "", bool isLast = true)
	{
		// Print the current node
		if(node.data != "root") { writeln(prefix ~ (isLast ? "└─ " : "├─ ") ~ node.data); }
		
		// Update the prefix for children
		auto newPrefix = prefix ~ (isLast ? "   " : "│  "); 
		
		foreach(i, child; node.children) { printTree(child, newPrefix, i == node.children.length - 1); }
	} 
	
	void treeFqn(string[] input)
	{
		// Input: Alphabetically sorted array of fully qualified names
		static if(0)
		input = [
			"com.example.Class!(int, string)",
			"com.example.Class!(int, string).method(int x, int y) : void",
			"com.example.OtherClass",
			"com.example.OtherClass.subMethod!(true)"
		]; 
		
		// Root of the tree
		auto root = TreeNode!string("root"); 
		
		// Build the tree
		foreach(name; input) {
			auto parts = parseQualifiedName(name); 
			addQualifiedName(root, parts); 
		}
		
		// Print the tree
		printTree(root); 
	} 
}

import het, het.parser; 

static struct StructureStats
{ size_t moduleCount, structCount, sizeBytes; } 

void accumulateStructureStats(S)(const ref S structure, ref StructureStats st)
{
	st.structCount ++; 
	
	void addSize(size_t siz) { st.sizeBytes += siz; } 
	addSize(typeof(structure).sizeof); 
	
	static foreach(alias field; structure.tupleof)
	{
		{
			alias T = typeof(field); const ref f() => __traits(getMember, structure, field.stringof); 
			static if(is(T==S*))	{ if(f) accumulateStructureStats(*f, st); }
			else static if(is(T==string[]))	{ addSize(f.map!"16+a.length".sum); }
			else static if(is(T==string[string]))	{
				addSize(
					f.keys	.map!"16+a.length".sum +
					f.values	.map!"16+a.length".sum
				); 
			}
			else static if(is(T==string))	{ addSize(f.length); }
			else static if(isIntegral!T || isFloatingPoint!T)	{/+Already added on the surface of the struct.+/}
			else static if(isDynamicArray!T)	{ foreach(const ref a; f) accumulateStructureStats(a, st); }
			else	static assert(0, "Unhandled T "~T.stringof); 
		}
	}
} 

File[] listDLangFiles(Path path, Flag!"recursive" recursive = Yes.recursive)
=> listFiles(path, "*.d*", "name", Yes.onlyFiles, Yes.recursive).filter!((a)=>(a.file.extIs("d", "di"))).map!((a)=>(a.file)).array; 

void dumpDLangFile(F)(F moduleFile)
{
	File f = moduleFile.File; 
	with(new ModuleDeclarations(f)) dumpStr.sort.array/+.treeFqn+/; 
} 

string generateDLangXJson(File moduleFile)
{
	const tempPath = Path(`z:\temp`); 
	const libPath = Path(`c:\d\libs`); 
	const tempJson = File(tempPath, `DIDE_` ~ [QPS].xxh32.to!string(36) ~ ".json"); 
	scope(exit) tempJson.remove; 
	auto res = execute(
		[
			"ldc2", "-o-", 
			"-X", `--Xf`, tempJson.fullName, 
			`-I`, libPath.fullPath, 
			`-I`, moduleFile.fullPath, 
			moduleFile.fullName
		]
	); 
	if(res.status==0) return tempJson.readText(true); 
	else raise(i"Error: $(moduleFile.quoted('`')) Msg: $(res.output)"); 
	assert(0); 
} 

import std.demangle; 
string demangleType(string s)
{
	if(s=="") return s; 
	const s1 = "_D1_"~s; 
	const s2 = s1.demangle; 
	if(s==s2) return s; 
	return s2.withoutEnding(" _"); 
} 

class DDB
{
	static class ModuleDeclarations
	{
		@STORED {
			File moduleFile; 
			string moduleName; 
			Item[] items; 
		} 
		
		static struct Parameter
		{
			@STORED
			{
				Kind kind; enum Kind {param, type, value, tuple, alias_, this_ } 
				string name, type, deco; 
				version(/+$DIDE_REGION+/all) {
					string default_; 
					mixin RedirectJsonField!(default_, "defaultAlias"); 
					mixin RedirectJsonField!(default_, "defaultDeco"); 
					mixin RedirectJsonField!(default_, "defaultValue"); 
				}
				version(/+$DIDE_REGION+/all) {
					string spec; 
					mixin RedirectJsonField!(spec, "specValue"); 
					mixin RedirectJsonField!(spec, "specAlias"); 
				}
				string[] storageClass; //{ auto_, const_, immutable_, in_, inout_, lazy_, out_, ref_, return_, scope_, shared_}
			} 
			
			string type2() const /+...Because sometimes the type is only in mangled form.+/
			=> ((kind.among(Kind.param, Kind.value))?(((type!="")?(type) :(deco.demangleType))):(type)); 
			
			string toString() const
			=> chain(
				storageClass, only(
					(
						kind.predSwitch
						(
							Kind.this_, 	"this", 
							Kind.alias_, 	"alias", 
								""
						)
					), type2, name~(
						kind.predSwitch
						(
							Kind.tuple, 	"...", 
								""
						)
					), ((default_!="") ?("= "~default_) :("")), ((spec!="") ?(": "~spec) :(""))
				)
			)
			.filter!"a!=``".join(' '); 
			
			void afterLoad()
			{ synchronized { ((0x20028F6F833B).檢 ((kind==Kind.param ? this.text : "").COUNT)); } } 
			
			void dumpStr(alias pred="true")(ref string[] result, const ref Item item, string path="")
			{
				if(unaryFun!pred(item))
				{ result ~= path~"("~name~")"; }
			} 
		} 
		
		static struct Item
		{
			string name; 
			int line, char_, endline, endchar, offset, align_; 
			
			string[] storageClass, overrides; 
			
			string kind, protection, linkage, base, init_, type, originalType, file, constraint, deco, baseDeco, value; 
			
			//import:
			string alias_; 
			string[] selective; 
			string[string] renamed; 
			
			//classes, interfaces:
			string[] interfaces; 
			
			//recursive declarations ------------------------
			Parameter[] parameters; 
			Item[] members; 
			
			Item* in_, out_; //contract preconditions, postconditions
			
			void dumpStr(alias pred="true")(ref string[] result, const ref Item item, string path="")
			{
				//if(name=="") return; 
				
				if(unaryFun!pred(item))
				{
					auto p = parameters.map!"a.type~` `~a.name".join(", "); 
					//print(kind.padRight(' ', 20), path~name~((p!="")?("("~p~")"):(""))); 
					result ~= path~name/+~((p!="")?("("~p~")"):(""))+/; 
				}
				foreach(ref a; members) a.dumpStr!pred(result, a, path~name~"."); 
			} 
		} 
		
		this()
		{/+default constructor needed by Json loader.+/} 
		
		this(File moduleFile, string jsonText)
		{
			this.moduleFile=moduleFile; 
			enum verifyImport = (常!(bool)(1)) /+Note: Use this to detect new LDC2 XJson changes.+/; 
			items.fromJson(
				jsonText, mixin(體!((JsonDecoderOptions),q{
					moduleName	: moduleFile.fullName,
					errorHandling	: ErrorHandling.warn,
					checkIgnoredFields	: verifyImport
				}))
			); 
			enforce(items.length==1, "Only one module per XJson supported."); 
			enforce(items[0].kind=="module", "Unknown XJson module.kind: "~items[0].kind); 
			moduleName = items[0].name; 
		} 
		
		this(File moduleFile)
		{
			this.moduleFile=moduleFile; 
			items.fromJson(moduleFile.generateDLangXJson, moduleFile.fullName); 
		} 
		
		string[] dumpStr(alias pred="true")()
		{
			string[] result; 
			foreach(ref a; items) { a.dumpStr!pred(result, a, ""); }
			return result; 
		} 
		
		void accumulateStructureStats(ref StructureStats st) const
		{
			st.moduleCount++; 
			st.sizeBytes += typeid(this).initializer.length; 
			foreach(const ref item; items) .accumulateStructureStats(item, st); 
		} 
	} 
	Path workPath, stdPath, libPath; 
	
	@property stdCacheFile() const 
	=> appFile.otherExt("$stdlib_cache.dat"); 
	
	
	ModuleDeclarations[string] 
		stdModules /+These modules are cached next to the dide.exe file.+/, 
		projectModules,
		modules /+This is both combined. Must be maintained properly!!!+/; 
	
	protected void addStdModule(ModuleDeclarations md)
	{ if(md) { mixin(指(q{stdModules},q{md.moduleName})) = md; mixin(指(q{modules},q{md.moduleName})) = md; }} 
	protected void addProjectModule(ModuleDeclarations md)
	{ mixin(指(q{projectModules},q{md.moduleName})) = md; mixin(指(q{modules},q{md.moduleName})) = md; } 
	protected void removeStdModules()
	{
		foreach(md; stdModules) modules.remove(md.moduleName); 
		stdModules.clear; 
	} 
	
	this()
	{
		workPath 	= `z:\temp2`,
		stdPath	= `c:\d\ldc2\import`,
		libPath 	= `c:\d\libs`
		/+Todo: These must come from outside!+/; 
	} 
	
	void regenerateStd()
	{
		LOG(i"Importing std module declarations from $(stdPath.quoted('`'))..."); 
		ModuleDeclarations[] importedModules; 	auto _間=init間; 
		auto stdFiles = listDLangFiles(stdPath)[0..$]; 	((0x2E478F6F833B).檢((update間(_間)))); 
		mixin(求each(q{f},q{
			stdFiles
			.parallel
		},q{
			try
			{
				auto 	json 	= f.generateDLangXJson,
					md 	= new ModuleDeclarations(f, json); 
				synchronized importedModules ~= md; 
			}
			catch(Exception e)	ERR(f, e.simpleMsg); 
		})); 	((0x2F7A8F6F833B).檢((update間(_間)))); 
		((0x2FA98F6F833B).檢(makeStatistics(importedModules).toJson)); 	((0x2FEA8F6F833B).檢((update間(_間)))); 
		
		removeStdModules; mixin(求each(q{m},q{importedModules},q{addStdModule(m)})); 
	} 
	
	void saveStd()
	{
		try {
			auto mods = stdModules.values; 	auto _間=init間; 
			auto json = mods.toJson(false, false, true); 	((0x30FC8F6F833B).檢((update間(_間)))); ((0x31278F6F833B).檢(json.length)); 
			auto compr = json/+.compress+/; 	((0x31728F6F833B).檢((update間(_間)))); ((0x319D8F6F833B).檢((((double(compr.length)))/(json.length)))); 
			stdCacheFile.write(compr); 	((0x32008F6F833B).檢((update間(_間)))); 
		}
		catch(Exception e) ERR(e.simpleMsg); 
	} 
	
	void loadStd()
	{
		try {
			ModuleDeclarations[] loadedModules; 	auto _間=init間; 
			auto compr = stdCacheFile.read; if(compr.empty) return; 	((0x32FA8F6F833B).檢((update間(_間)))); 
			auto json = (cast(string)(compr.uncompress)); 	((0x33598F6F833B).檢((update間(_間)))); 
			loadedModules.fromJson(json, stdCacheFile.fullName); 	((0x33BF8F6F833B).檢((update間(_間)))); 
			
			/+success+/removeStdModules; mixin(求each(q{m},q{loadedModules},q{addStdModule(m)})); 
		}
		catch(Exception e) { ERR(e.simpleMsg); }
	} 
	
	auto makeStatistics(R)(R modules)
	{ StructureStats st; mixin(求each(q{m},q{modules},q{m.accumulateStructureStats(st)})); return st; } 
	
	void dumpAllMembers()
	{ mixin(求map(q{k},q{modules.keys.sort},q{mixin(指(q{modules},q{k})).dumpStr})).join.sort.array.treeFqn; } 
	
	
	auto search()
	{} 
} 


void main()
{
	console(
		{
			//treeFqn; 
			static if((常!(bool)(0)))
			{
				static struct S
				{
					@STORED int def; 
					@STORED def1(int a) { def = a; } 
					//@STORED def1()const => def; 
				} 
				
				S s; 
				
				s.fromJson(`{ "def" : 123 }`); ((0x36DA8F6F833B).檢(s)); 
				s.fromJson(`{ "def1" : 456 }`); ((0x371B8F6F833B).檢(s)); 
				((0x373C8F6F833B).檢(s.toJson)); 
				
			}
			
			
			static if((常!(bool)(1)))
			{
				//unittest_stream; 
				//unittest_JsonClassInheritance; 
				
				registerStoredClass!(DDB.ModuleDeclarations); 
				
				auto ddb = new DDB; 
				ddb.regenerateStd; 
				ddb.saveStd; 
				ddb.loadStd; 
				//ddb.dumpAllMembers; 
				
				uint[string] kindCount; 
				uint[string] nonzeroFieldCount; 
				
				void visit(S)(const ref S structure, string parentField="")
				{
					string kind2()
					{
						const kt = structure.kind.text; auto doit(A...)(A args) => kt.among(args); 
						if(
							doit(
								"constructor", "destructor", "function", "generated function", 
								"shared static constructor", "shared static destructor", 
								"static constructor", "static destructor"
							)
						) return "_callable"; 
						if(doit("class", "interface", "mixin", "struct", "template", "union")) return "_aggregate"; 
						if(doit("import", "static import")) return "_import"; 
						return kt; 
					} 
					
					
					
					kindCount[kind2]++; 
					
					static foreach(alias field; structure.tupleof)
					{
						{
							alias T = typeof(field); const ref f() => __traits(getMember, structure, field.stringof); 
							
							const faddr = ((kind2!="")?(kind2):(parentField))~'.'~field.stringof; 
							void incr() { if(parentField!="_parameters") nonzeroFieldCount[faddr]++; } 
							static if(is(T==S*))	{ if(f) incr; if(f) visit(*f, "_"~field.stringof); }
							else static if(is(T==string[]))	{ if(!f.empty) incr; }
							else static if(is(T==string[string]))	{ if(!f.empty) incr; }
							else static if(is(T==string))	{ if(!f.empty) incr; }
							else static if(isIntegral!T || isFloatingPoint!T)	{ if(f!=0) incr; }
							else static if(isDynamicArray!T)	{ if(!f.empty) incr; foreach(const ref a; f) visit(a, "_"~field.stringof); }
							else	static assert(0, "Unhandled T "~T.stringof); 
						}
					}
				} 
				
				foreach(i, m; ddb.modules.values) { foreach(const ref item; m.items) visit(item); }
				
				void printMap(alias m)()
				{
					print(m.stringof, "-----------------------------"); 
					m.keys.sort.each!((k){ print(format!"%-9s  %s"(m[k], k.splitter(".").map!"a.format!`%-32s`".join)); }); 
					print; 
				} 
				
				printMap!kindCount; 
				printMap!nonzeroFieldCount; 
				
			}
			
			static if((常!(bool)(0)))
			{
				auto f = "c:\\d\\ldc2\\import\\std\\traits.d".File; 
				auto json = f.generateDLangXJson; 
				json.saveTo(`z:\temp\a.json`); 
				auto m = new ModuleDeclarations(f, json); 
				m.dumpStr.sort.array/+.treeFqn+/; 
			}
			
			static if((常!(bool)(0)))
			foreach(f; ((0)?(listFiles(Path(`c:\d\ldc2\import`), "*.*", "name", Yes.onlyFiles, Yes.recursive).map!"a.file".array):([`c:\d\libs\het\package.d`.File])))
			{
				auto res = execute(["ldc2", "-o-", "-X" ,`--Xf=z:\temp\json.txt`, `-Ic:\d\libs`, f.fullName]); 
				
				if(res.status==0)
				{
					auto m = new ModuleJson(`z:\temp\json.txt`.File); 
					m.dumpStr.sort.array.treeFqn; 
				}
				else print("ERROR:", res.output); 
			}
		}
	); 
} 