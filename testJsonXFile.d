//@exe
//@debug
//@release

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

import std.parallelism; 





File[] listDLangFiles(Path path, Flag!"recursive" recursive = Yes.recursive)
=> listFiles(path, "*.d*", "name", Yes.onlyFiles, Yes.recursive).filter!((a)=>(a.file.extIs("d", "di"))).map!((a)=>(a.file)).array; 

string generateDLangXJson(File moduleFile, in string[] extraArgs=[])
{
	const tempPath = Path(`z:\temp`)/+Todo: pull this constant outwards!+/; 
	const tempJson = File(tempPath, `DIDE_` ~ [QPS].xxh32.to!string(36) ~ ".json"); 
	scope(exit) tempJson.forcedRemove; 
	auto res = execute(
		["ldc2", "-o-", "-X", `--Xf`, tempJson.fullName] ~
		extraArgs ~
		moduleFile.fullName
	); 
	if(res.status==0) return tempJson.readText(true); 
	else raise(i"Error: $(moduleFile.quoted('`')) Msg: $(res.output)"); 
	assert(0); 
} 

version(/+$DIDE_REGION+/all) {
	import std.demangle; 
	string demangleType(string s)
	{
		if(s=="") return s; 
		const s1 = "_D1_"~s; 
		const s2 = s1.demangle; 
		if(s==s2) return s; 
		return s2.withoutEnding(" _"); 
	} 
	string extractLastName(string s)
	{
		if(s=="") return ""; 
		const idx = s.byChar.retro.countUntil('.'); 
		if(idx<=0) return s; 
		return s[$-idx..$]; 
	} 
	string prefixNonEmpty(alias prefix)(string s)
	=> ((s!="")?(prefix~s):("")); 
	string postfixNonEmpty(alias postfix)(string s)
	=> ((s!="")?(s~postfix):("")); 
	string enfoldNonEmpty(alias prefix, alias postfix)(string s)
	=> ((s!="")?(prefix~s~postfix):("")); 
	string joinNonEmpty(alias sep, R)(R r)
	=> r.cache.filter!"!a.empty".join(sep); 
	string joinLines(R)(R r) 
	=> r.joinNonEmpty!'\n'; 
	string joinSentence(R)(R r)
	=> r.joinNonEmpty!' '; 
	string joinWithTab(string a, string b)
	=> ((b=="")?(a):(a~'\t'~b)); 
}

version(/+$DIDE_REGION Enum declarations+/all)
{
	mixin((
		(表([
			[q{/+Note: MCat : ubyte+/}],
			[q{aggregate}],
			[q{callable}],
			[q{import_}],
			[q{alias_}],
			[q{enum_}],
			[q{enum_member}],
			[q{variable}],
		]))
	).調!(GEN_enumTable)); mixin((
		(表([
			[q{/+Note: Protection : ubyte+/},q{/+Note: Text#+/}],
			[q{none},q{/+Code:+/}],
			[q{public_},q{/+Code: public+/}],
			[q{private_},q{/+Code: private+/}],
			[q{package_},q{/+Code: package+/}],
			[q{protected_},q{/+Code: protected+/}],
			[q{export_ },q{/+Code: export+/}],
		]))
	).調!(GEN_enumTable)); mixin((
		(表([
			[q{/+Note: Linkage : ubyte+/},q{/+Note: Caption+/}],
			[q{none},q{""}],
			[q{c},q{"C"}],
			[q{cpp},q{"C++"}],
			[q{d},q{"D"}],
			[q{windows},q{"Windows"}],
			[q{system},q{"System"}],
			[q{objectivec},q{"Objective-C"}],
		]))
	).調!(GEN_enumTable)); 
	mixin 入 !((
		(表([
			[q{/+Note: MKind+/},q{/+Note: MCat+/}],
			[q{/+Code: class+/},q{aggregate}],
			[q{/+Code: interface+/},q{aggregate}],
			[q{/+Code: mixin+/},q{aggregate}],
			[q{/+Code: struct+/},q{aggregate}],
			[q{/+Code: template+/},q{aggregate}],
			[q{/+Code: union+/},q{aggregate}],
			[q{/+Code: function+/},q{callable}],
			[q{/+Code: generated function+/},q{callable}],
			[q{/+Code: constructor+/},q{callable}],
			[q{/+Code: static constructor+/},q{callable}],
			[q{/+Code: shared static constructor+/},q{callable}],
			[q{/+Code: destructor+/},q{callable}],
			[q{/+Code: static destructor+/},q{callable}],
			[q{/+Code: shared static destructor+/},q{callable}],
			[q{/+Code: import+/},q{import_}],
			[q{/+Code: static import+/},q{import_}],
			[q{/+Code: alias+/},q{alias_}],
			[q{/+Code: enum+/},q{enum_}],
			[q{/+Code: enum member+/},q{enum_member}],
			[q{/+Code: variable+/},q{variable}],
		]))
	),q{
		enum kindText = _data.rows.map!((r)=>(r[0].unpackDComment!"Code")).array; 
		enum kindCategory = _data.rows.map!((r)=>(r[1].to!MCat)).array; 
		mixin(iq{enum MKind : ubyte {$(kindText.map!((a)=>(a.replace(' ', '_').jsonFieldToIdentifier)).join(','))} }.text); 
	}); 
	//pragma(msg, kindCategory); pragma(msg, kindText); pragma(msg, EnumMembers!Kind); 
}

class DDB
{
	static class ModuleDeclarations
	{
		@STORED {
			File file; 	/+module file name+/
			string name; 	/+just the last module name, not FQN+/
			bool isStd; 	/+regenerateStd() sets this to true+/
			Member[] members; 	/+members of this module+/
			ModuleDeclarations[] modules; 	/+subModules of this module.+/
		}  struct SourceTextOptions
		{
			bool 	recursive 	= true,
				lastNameOnly 	= true; 
			uint moduleCount, memberCount, paramCount; 
		} 
		
		static struct Parameter
		{
			@STORED {
				Kind kind; enum Kind : ubyte {
					/+function:+/	parameter, 
					/+template:+/	type, value, tuple, alias_, this_ 
				} 
				string name; 
				version(/+$DIDE_REGION+/all) {
					string type; 
					
					mixin RedirectJsonField!(type, "deco", "a.demangleType"); 
					mixin RedirectJsonField!(type, "defaultDeco", "a.demangleType"); 
				}
				version(/+$DIDE_REGION+/all) {
					string def; 
					
					mixin RedirectJsonFields!(
						def, [
							"default_"/+kind: value+/, 
							"defaultAlias"/+kind: alias+/, 
							"defaultValue"/+kind: type+/
						]
					); 
				}
				version(/+$DIDE_REGION+/all) {
					string spec; 
					
					mixin RedirectJsonFields!(
						spec, [
							"specValue"/+kind: value+/, 
							"specAlias"/+kind: alias_+/
						]
					); 
				}
				string[] storageClass; /+
					{ auto_, const_, immutable_, in_, inout_, lazy_, 
					out_, ref_, return_, scope_, shared_}
				+/
			} 
			string keyword() const => kind.predSwitch(Kind.alias_, "alias", Kind.this_, "this", ""); 
			string tupleEllipsis() const => kind.predSwitch(Kind.tuple, "...", ""); 
			string fullDef() const => def.prefixNonEmpty!"= "; 
			string fullSpec() const => spec.prefixNonEmpty!": "; 
			
			string toString() const => chain(storageClass, only(keyword, type, name~tupleEllipsis, fullDef, fullSpec)).joinSentence; 
		} 
		
		static struct Member
		{
			alias Category = MCat, Kind = MKind/+That complicated mixin table injector fails this scope... needs `this` to access `.map!()` o.O+/; 
			@STORED {
				version(/+$DIDE_REGION+/all) {
					version(/+$DIDE_REGION All members+/all)
					{
						string name; 
						uint line, char_; 
						Kind mKind; 
						Protection protection; 
						/+string mixinFile+/
					}
					
					version(/+$DIDE_REGION mixed: callable, variable+/all)
					{ Linkage linkage; }
					
					version(/+$DIDE_REGION aggregate+/all)
					{
						/+string aggregateBase;+/
						/+string aggregateConstraint; +/
						/+string[] aggregateInterfaces; +/
					}
					
					version(/+$DIDE_REGION callable+/all)
					{
						uint endline, endchar; 
						Member* in_, out_; 
						/+Opt: in_ and out_ -> are wasteful.+/
						string[] overrides; 
					}
					version(/+$DIDE_REGION import_+/all)
					{
						/+string importAlias; +/
						/+string[] importSelective; +/
						string[string] renamed; 
					}
					
					version(/+$DIDE_REGION enum_+/all)
					{/+string baseDeco->base+/}
					version(/+$DIDE_REGION enum_member+/all)
					{/+string enumMemberValue; +/}
					
					version(/+$DIDE_REGION variable+/all)
					{
						string init_; 
						/+
							uint 	variableOffset, 
								variableAlign; 
						+/
					}
					version(/+$DIDE_REGION mixed: callable, variable, alias_+/all)
					{
						string /+deco->type+/type, originalType; 
						string[] storageClass; 
					}
					
					version(/+$DIDE_REGION mixed: aggregate, callable+/all)
					{ Parameter[] parameters; }
					
					version(/+$DIDE_REGION mixed: aggregate, enum_+/all)
					{ Member[] members; }
				}
				
				version(/+$DIDE_REGION Converted/processed fields+/all)
				{
					@property void kind(string s)
					{
						//This is an importer/converter property.  Only a setter.
						static Kind[string] kindByName; 
						if(kindByName.empty) kindByName = assocArray(kindText, [EnumMembers!Kind]); 
						mKind = *(s in kindByName).enforce("Unknown ModuleDeclarations.kind: "~s.quoted); 
					} 
					
					/+combine mutually exclusive fields to lower memory usage+/
					version(/+$DIDE_REGION+/all) {
						/+type comes from many sources.+/	mixin RedirectJsonField!(type, "deco", q{a.demangleType}); 
						alias enumBase = type; 	mixin RedirectJsonField!(enumBase, "baseDeco", q{a.demangleType}); 
						alias aggregateBase = type; 	mixin RedirectJsonField!(type, "base"); 
						alias enumMemberValue = type; 	mixin RedirectJsonField!(type, "value"); 
						alias importAlias = type; 	mixin RedirectJsonField!(type, "alias_"); 
					}
					
					version(/+$DIDE_REGION+/all) { alias importSelective = storageClass; 	mixin RedirectJsonField!(storageClass, "selective"); }
					
					version(/+$DIDE_REGION+/all) { alias aggregateInterfaces = overrides; 	mixin RedirectJsonField!(overrides, "interfaces"); }
					
					version(/+$DIDE_REGION+/all) { alias variableOffset = endline; 	mixin RedirectJsonField!(endline, "offset"); }
					version(/+$DIDE_REGION+/all) { alias variableAlign = endchar; 	mixin RedirectJsonField!(endchar, "align_"); }
					
					version(/+$DIDE_REGION+/all) { alias aggregateConstraint = init_; 	mixin RedirectJsonField!(init_, "constraint"); }
					
					version(/+$DIDE_REGION+/all) { @property file(string s) { renamed["file"] = s; /+mixinFile, if something was mixed in.+/} }
				}
			} 
			
			Category category() const => kindCategory[mKind]; 
			string kindStr() const => kindText[mKind]; 
			string protectionStr() const => protectionText[protection]; 
			string linkageStr() const => ((linkage)?("extern("~linkageCaption[linkage]~")"):("")); 
			string constraintStr() const => aggregateConstraint.enfoldNonEmpty!("if(", ")"); 
			string valueStr() const => enumMemberValue.prefixNonEmpty!"= "; 
			
			
			string mixinFile() const => ((mKind==Kind.import_)?(""):(renamed.get("file", ""))); 
			
			string sourceText() const { SourceTextOptions opt; return sourceText(opt); } 
			string sourceText(Flag!"parentIsEnum" parentIsEnum = No.parentIsEnum)(ref SourceTextOptions opt) const
			{
				string lastName(string s)
				=> ((opt.lastNameOnly)?(s.extractLastName):(s)); 
				string enumBaseStr() const
				=> enumBase.prefixNonEmpty!": "; 
				string baseAndInterfacesStr() const
				=> chain(only(aggregateBase), aggregateInterfaces).cache.filter!"a!=``".map!lastName.join(", ").prefixNonEmpty!": "; 
				string templateParametersStr(Flag!"instantiate" instantiate = No.instantiate)() const
				=> parameters.map!text.join(", ").enfoldNonEmpty!(((instantiate)?("!("):("(")), ')'); 
				string membersStr() const
				=> members.map!((m)=>(m.sourceText(opt))).joinLines; 
				string membersList() const
				=> members.map!((m)=>(m.sourceText!(Yes.parentIsEnum)(opt))).join(",\n"); 
				
				version(/+$DIDE_REGION Update statistics+/all)
				{ opt.memberCount ++; opt.paramCount += (cast(uint)(parameters.length)); }
				
				return category.predSwitch
				(
					mixin(舉!((Category),q{aggregate}))	, (
						(){
							const isMixin = mKind==Kind.mixin_/+Todo: Make template mixin a distinct category!+/; 
							//Note: In the JSON, no way to tell if a template is a mixin template or not.
							if(isMixin && members.length)
							WARN("template mixin instantiation "~name.quoted~"has unhandled members."); 
							return only(
								protectionStr, kindStr, 
								(
									only(name, baseAndInterfacesStr).joinSentence
									~((isMixin)?(templateParametersStr!(Yes.instantiate)) :(templateParametersStr))
								), 
								constraintStr, 
								((isMixin)?(";") :("{"~((opt.recursive)?(membersStr):(""))~"}"))
							).joinSentence; 
						}()
					),
					mixin(舉!((Category),q{enum_}))	, (
						only(
							protectionStr, "enum", name, enumBaseStr, 
							"{"~((opt.recursive)?(membersList):(""))~"}"
						).joinSentence
					),
					mixin(舉!((Category),q{enum_member}))	, ((parentIsEnum)?(joinWithTab(name, valueStr)) :(only(protectionStr, "enum", name, valueStr).joinSentence~';')),
					mixin(舉!((Category),q{import_}))	, (
						only(
							protectionStr, kindStr, importAlias.postfixNonEmpty!" =", name, 
							(
								chain(importSelective, renamed.byKeyValue.map!q{a.key~" = "~a.value})
								.array.sort.join(", ")/+Opt: Slow.  Should be cached...+/
								.prefixNonEmpty!": "
							)
						).joinSentence~';'
					),
					mixin(舉!((Category),q{alias_}))	, (
						only(
							protectionStr, storageClass.joinSentence, "alias", name, "=",
							linkageStr, originalType.ifEmpty(type)
							/+
								-	type is fullyQualified, has no param names.
								-	originalType has parameter names too, it's nicer, 
									it's not always present.
							+/
							/+
								Todo: remove fullyQualifiedPath from type if it's in the 
								same module. Example: /+Code: LPNMLVODSTATECHANGE+/
							+/
						).joinSentence~';'
					),
					mixin(舉!((Category),q{variable}))	, (
						only(
							protectionStr, linkageStr, storageClass.joinSentence, 
							originalType.ifEmpty(type), name, prefixNonEmpty!"= "(init_)
							/+more fields: variableOffset, variableAlign+/
						).joinSentence~';'
					),
					mixin(舉!((Category),q{callable}))	, (
						only(
							protectionStr, name, //'('~parameters.map!text.join(", ")~')',
							"=", storageClass.joinSentence, /+linkageStr <- redundant+/ 
							originalType.ifEmpty(type)
							/+more fields: endline, endchar, in_, out_+/
						).joinSentence~';'
					),
					""
				); 
			} 
		} 
		this()
		{/+default constructor needed by Json loader.+/} 
		
		static createFromJson(string jsonText)
		{
			enum verifyImport = (常!(bool)(1)) /+Note: Use this to detect new LDC2 XJson changes.+/; 
			
			/+The outmost Json object. LDC2 generates an array of this.+/
			static struct Module
			{ string kind, name, file; Member[] members; } 
			Module[] mods; 
			mods.fromJson(
				jsonText, mixin(體!((JsonDecoderOptions),q{
					moduleName	: "LDC2 XJson loader",
					errorHandling	: ErrorHandling.warn,
					checkIgnoredFields	: verifyImport
				}))
			); 
			ModuleDeclarations[] res; 
			foreach(ref mod; mods)
			{
				if(mod.kind=="module" && mod.file!="")
				{
					auto m = new ModuleDeclarations; 
					with(m)
					file 	= File(mod.file),
					name 	= mod.name/+absolute full name-path+/,
					members 	= mod.members; 
					
					static if(true)
					if(m.name=="") m.name = m.file.nameWithoutExt.lc; 
					
					res ~= m; 
				}
				else
				WARN("Not a valid XJSon module."); 
			}
			return res; 
		} 
		
		auto findModule(string name)
		{ return modules.find!((m)=>(m.name==name)).frontOrNull; } 
		
		private void acquireMembers(ModuleDeclarations src, string[] srcPath)
		{
			//this module has only a single name refering to this level only.
			//src module has a full name starting with point.
			void print(A...)(A a) { static if((常!(bool)(0))/+Note: debug+/) .print(a); } 
			
			
			print("Current src path:", srcPath); 
			print("Src.name:", src.name); 
			if(srcPath.empty/+Note: This is it+/)
			{
				print("SUCCESS Exact name found:", name); 
				file = src.file; 
				members = src.members; 
			}
			else
			{
				const nextName = srcPath.fetchFront; 
				print("Looking for next name:", nextName); 
				auto nextModule = findModule(nextName); 
				if(!nextModule)
				{
					print("Creating the next module:", nextName); 
					nextModule = new ModuleDeclarations; 
					nextModule.name = nextName; 
					modules ~= nextModule; 
				}
				print("Doing recursion in:", nextName); 
				nextModule.acquireMembers(src, srcPath); 
			}
		} 
		
		string sourceText() const { SourceTextOptions opt; return sourceText(opt); } 
		string sourceText(ref SourceTextOptions opt) const
		{
			opt.moduleCount++; 
			return"module "~name~" {"~chain(
				members.map!((m)=>(m.sourceText(opt))),
				modules.map!((m)=>(m.sourceText(opt)))
			).joinLines~"}"; 
		} 
	} 
	Path workPath, stdPath, libPath; 
	ModuleDeclarations root; 
	
	alias SourceTextOptions = ModuleDeclarations.SourceTextOptions; 
	
	protected
	{
		void acquireMembers(ModuleDeclarations md)
		{ root.acquireMembers(md, md.name.split('.')); } 
		void acquireMembers(R)(R r) { mixin(求each(q{m},q{r},q{acquireMembers(m)})); } 
		@property stdCacheFile() const 
		=> /+appFile.otherExt("$stdlib_cache.dat")+/
		`z:\temp2\$stdlib_cache.dat`.File; 
	} 
	
	this()
	{
		workPath 	= `z:\temp2`,
		stdPath	= `c:\d\ldc2\import`,
		libPath 	= `c:\d\libs`
		/+Todo: These must come from outside!+/; 
		root = new ModuleDeclarations; 
	} 
	
	protected void regenerate_internal(bool isParallel)(bool isStd, in File[] files, in string[] args)
	{
		ModuleDeclarations[] doit(File f)
		{
			try
			{
				const json = f.generateDLangXJson(args); 
				return ModuleDeclarations.createFromJson(json); 
			}
			catch(Exception e)	ERR(f, e.simpleMsg); return []; 
		} 
		ModuleDeclarations[] importedModules; 	auto _間=init間; 
		static if(isParallel)	{
			mixin(求each(q{f},q{
				files
				.parallel
			},q{
				{
					auto mods = doit(f); 
					synchronized importedModules ~= mods; 
				}
			})); 
		}
		else	{ mixin(求each(q{f},q{files},q{importedModules ~= doit(f); })); }	((0x557A8F6F833B).檢((update間(_間)))); 
		mixin(求each(q{m},q{importedModules},q{m.isStd = isStd})); acquireMembers(importedModules); 	((0x56078F6F833B).檢((update間(_間)))); 
		((0x56368F6F833B).檢(importedModules.length)); 
	} 
	
	void regenerate(in File[] files, in string[] args)
	{ regenerate_internal!true(false, files, args); } 
	
	void regenerateStd()
	{
		LOG(i"Importing std module declarations from $(stdPath.quoted('`'))..."); 
		auto _間=init間; 
		auto stdFiles = listDLangFiles(stdPath); 	((0x57898F6F833B).檢((update間(_間)))); 
		regenerate_internal!true(true, stdFiles, []); 	((0x57E78F6F833B).檢((update間(_間)))); 
	} 
	
	void save()
	{
		try {
			auto _間=init間; 
			auto json = root.toJson(true, false, true); 	((0x587F8F6F833B).檢((update間(_間)))); ((0x58AA8F6F833B).檢(json.length)); 
			auto compr = json.compress; 	((0x58F18F6F833B).檢((update間(_間)))); ((0x591C8F6F833B).檢((((double(compr.length)))/(json.length)))); 
			stdCacheFile.write(compr); 	((0x597F8F6F833B).檢((update間(_間)))); 
		}
		catch(Exception e) ERR(e.simpleMsg); 
	} 
	
	void load()
	{
		try {
			auto _間=init間; 
			auto compr = stdCacheFile.read; if(compr.empty) return; 	((0x5A518F6F833B).檢((update間(_間)))); 
			auto json = (cast(string)(compr.uncompress)); 	((0x5AB08F6F833B).檢((update間(_間)))); 
			ModuleDeclarations newRoot; 	
			newRoot.fromJson(json, stdCacheFile.fullName); 	((0x5B328F6F833B).檢((update間(_間)))); 
			if(newRoot) root = newRoot; 
		}
		catch(Exception e) { ERR(e.simpleMsg); }
	} 
	
	string generateMemberStats()
	{
		string res; void re(string s) { res ~= s~"\r\n"; } 
		
		uint[string] kindCount, kindSize; 
		uint[string] nonzeroFieldCount; 
		
		void visit(S)(const ref S structure, string parentField="")
		{
			string kind2()
			{
				static if(__traits(compiles, structure.category))	return "_"~structure.category.text; 
				else	return structure.kind.text; 
			} 
			
			size_t dynSize; 
			static foreach(alias field; structure.tupleof)
			{
				{
					alias T = typeof(field); const ref f() => __traits(getMember, structure, field.stringof); 
					
					const faddr = ((kind2!="")?(kind2):(parentField))~'.'~field.stringof; 
					void incr(size_t ds=0) { dynSize += ds; if(parentField!="_parameters") nonzeroFieldCount[faddr]++; } 
					static if(is(T==S*))	{ if(f) { incr; visit(*f, "_"~field.stringof); }}
					else static if(is(T==string[]))	{ if(!f.empty) incr(f.length*16 + f.map!sizeBytes.sum); }
					else static if(is(T==string[string]))	{
						if(!f.empty)
						incr(
							f.length*16*2 	+ f.keys.map!sizeBytes.sum 
								+ f.values.map!sizeBytes.sum
						); 
						
					}
					else static if(is(T==string))	{ if(!f.empty) incr(16+f.sizeBytes); }
					else static if(isIntegral!T || isFloatingPoint!T)	{ if(f!=0) incr; }
					else static if(isDynamicArray!T)	{
						if(!f.empty) incr(f.sizeBytes); 
						foreach(const ref a; f) visit(a, "_"~field.stringof); 
					}
					else	static assert(0, "Unhandled T "~T.stringof); 
				}
			}
			
			//accumulate stats
			kindCount[kind2]++; 
			kindSize[kind2] += S.sizeof + dynSize; 
		} 
		
		void visitM(DDB.ModuleDeclarations md)
		{
			foreach(ref const member; md.members) visit(member); 
			foreach(module_; md.modules) visitM(module_); 
		} 
		
		visitM(root); 
		
		void printMap(alias m)()
		{
			re(m.stringof ~ "-----------------------------"); 
			m.keys.sort.each!((k){ re(format!"%-9s  %s"(m[k], k.splitter(".").map!"a.format!`%-32s`".join)); }); 
			re(""); re("Total: "~ m.byValue.sum.text); re(""); 
		} 
		
		printMap!kindCount; 
		printMap!kindSize; 
		printMap!nonzeroFieldCount; 
		
		return res; 
	} 
	
	
	auto search()
	{} 
} 


void main()
{
	console(
		{
			static if((常!(bool)(1)))
			{
				//Only the inherited classes -> registerStoredClass!(DDB.ModuleDeclarations); 
				
				with(new DDB)
				{
					version(/+$DIDE_REGION+/all) {
						const hetlibFiles = 
						[
							`c:\d\libs\het\package.d`,
							`c:\d\libs\het\quantities.d`,
							`c:\d\libs\het\math.d`,
							`c:\d\libs\het\inputs.d`,
							`c:\d\libs\het\parser.d`,
							`c:\d\libs\het\ui.d`,
							`c:\d\libs\het\opengl.d`,
							`c:\d\libs\het\win.d`,
							`c:\d\libs\het\algorithm.d`,
							`c:\d\libs\het\draw2d.d`,
							`c:\d\libs\het\bitmap.d`,
							`c:\d\libs\het\http.d`,
							`c:\d\libs\het\db.d`,
							`c:\d\libs\het\mcu.d`,
							`c:\d\libs\het\com.d`,
							`c:\d\libs\het\vulkan.d`,
							`c:\d\libs\common\libueye.d`,
						]
						.map!File.array; 
						const dideFiles = 
						[
							`c:\d\projects\dide\dide2.d`,
							`c:\d\projects\dide\buildsys.d`,
							`c:\d\projects\dide\didemodule.d`,
						]
						.map!File.array; 
						const dideArgs = [
							"--d-version=stringId",
							"-I", `c:\d\projects\dide`
						]; 
						
						const karcFiles = 
						[
							`c:\d\projects\karc\karc.d`,
							`c:\d\projects\karc\karcbox.d`,
							`c:\d\projects\karc\karcpneumatic.d`,
							`c:\d\projects\karc\karctrigger.d`,
							`c:\d\projects\karc\karclogger.d`,
							`c:\d\projects\karc\karcdetect.d`,
							`c:\d\projects\karc\karcthreshold.d`,
							`c:\d\projects\karc\karcocr.d`,
						]
						.map!File.array; 
						const karcArgs = [
							"--d-version=VulkanHeadless",
							"-I", `c:\d\projects\karc`
						]; 
					}
					
					enforce(chain(hetlibFiles, dideFiles, karcFiles).all!"a.exists"); 
					
					static if((常!(bool)(0))) regenerateStd/+75.8MB+/; 
					static if((常!(bool)(0))) regenerate(hetlibFiles, ["-I", `c:\d\libs`])/+14.2MB+/; 
					static if((常!(bool)(0))) regenerate(dideFiles, ["-I", `c:\d\libs`]~dideArgs)/+2.1MB+/; 
					static if((常!(bool)(1))) regenerate(karcFiles, ["-I", `c:\d\libs`]~karcArgs)/+0.75MB+/; 
					/+all: 92.2MB+/
					save; 
					load; 
					
					SourceTextOptions so; 
					root.sourceText(so).saveTo(File(`z:\declarations.d`)); 
					so.toJson.print; 
					
					generateMemberStats.print; 
					/+
						Code: 2025.01.16. Full std library stats:
						
						kindCount-----------------------------
						7289		 _aggregate
						7696		 _alias_
						26615	  _callable
						354		  _enum_
						17033		 _enum_member
						2135			 _import_
						32665		 _variable
						421		  alias_
						41600	  parameter
						81		  this_
						462			tuple
						3728			type
						1085			value
						
						Total: 141164
						
						kindSize-----------------------------
						11647576	  _aggregate
						4084824	  _alias_
						20886756	  _callable
						919008	  _enum_
						6967664	  _enum_member
						874400	  _import_
						22985108	  _variable
						55736	  alias_
						6722440	  parameter
						9160	  this_
						54592	  tuple
						438880		 type
						234652		 value
						
						Total: 75880796
					+/
				}
			}
		}
	); 
} 