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

string generateDLangXJson(File moduleFile, Path[] importPaths)
{
	const tempPath = Path(`z:\temp`); 
	const libPath = Path(`c:\d\libs`); 
	const tempJson = File(tempPath, `DIDE_` ~ [QPS].xxh32.to!string(36) ~ ".json"); 
	scope(exit) tempJson.forcedRemove; 
	auto res = execute(
		[
			"ldc2", "-o-", 
			"-X", `--Xf`, tempJson.fullName
		] ~
		chain(only(libPath), importPaths).map!((p)=>(["-I", p.fullPath])).join ~
		moduleFile.fullName
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
} string extractLastName(string s)
{
	if(s=="") return ""; 
	const idx = s.byChar.retro.countUntil('.'); 
	if(idx<=0) return s; 
	return s[$-idx..$]; 
} version(/+$DIDE_REGION+/all) {
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

__gshared globalCnt=0; 





class DDB
{
	static class ModuleDeclarations
	{
		@STORED {
			File file; 
			string name; 
			Member[] members; 
			ModuleDeclarations[] modules; 
		}  struct SourceTextOptions
		{
			bool 	recursive 	= true,
				lastNameOnly 	= true; 
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
					void deco(string s)/+param, value, type+/
					{ if(type!="") ERR("`type` is redefined by `deco`."); type = s.demangleType; } 
					void defaultDeco(string s)/+type+/
					{ if(type!="") ERR("`type` is redefined by `defaultDeco`."); type = s.demangleType; } 
				}
				version(/+$DIDE_REGION+/all) {
					string def; 
					static foreach(a; ["default_", "defaultAlias", "defaultValue"])
					mixin RedirectJsonField!(def, a); /+
						param, value,
						type, alias
					+/
				}
				version(/+$DIDE_REGION+/all) {
					string spec; 
					static foreach(a; ["specValue", "specAlias"])
					mixin RedirectJsonField!(spec, a); /+
						value
						alias
					+/
				}
				string[] storageClass; /+{ auto_, const_, immutable_, in_, inout_, lazy_, out_, ref_, return_, scope_, shared_}+/
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
						Kind mKind; 
						Protection protection; 
						uint line, char_; 
					}
					
					version(/+$DIDE_REGION aggregate+/all)
					{
						string base, constraint; 
						string[] interfaces; 
					}
					version(/+$DIDE_REGION callable+/all)
					{
						uint endline, endchar; 
						Member* in_, out_; 
						string[] overrides; 
					}
					
					version(/+$DIDE_REGION import+/all)
					{
						string alias_; 
						string[] selective; 
						string[string] renamed; 
					}
					version(/+$DIDE_REGION enum+/all)
					{/+string baseDeco->base+/}
					version(/+$DIDE_REGION enum member+/all)
					{ string value; }
					
					version(/+$DIDE_REGION variable+/all)
					{
						string init_; 
						uint offset, align_; 
					}
					
					version(/+$DIDE_REGION mixed: callable, variable+/all)
					{ Linkage linkage; }
					version(/+$DIDE_REGION mixed: callable, variable, alias+/all)
					{
						string /+deco->type+/type, originalType; 
						string[] storageClass; 
					}
					
					version(/+$DIDE_REGION mixed: aggregate, callable+/all)
					{ Parameter[] parameters; }
					version(/+$DIDE_REGION mixed: aggregate, enum+/all)
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
					
					@property file(string s) /+Ignore 'file' field,  occured only 2 times in callable and variable+/
					{ WARN("ModuleDeclaration.file ignored: "~s.quoted('`')~" kind: "~kindStr.quoted); } 
					
					@property void baseDeco(string s)/+enum+/
					{ if(base!="") ERR("`base` is redefined by `baseDeco`."); base = s.demangleType; /+Todo: RedirectJsonField -> alias this function!+/} 
					
					@property void deco(string s)/+enum+/
					{ if(type!="") ERR("`base` is redefined by `baseDeco`."); type = s.demangleType; } 
					
				}
			} 
			
			void afterLoad()
			{
				version(none)
				synchronized
				{
					if((常!(bool)(0)) && category==Category.enum_member)
					{
						((0x36BC8F6F833B).檢 (mKind.COUNT)),
						((0x36EA8F6F833B).檢 (protection.COUNT)),
						((0x371D8F6F833B).檢 (value.COUNT)); 
						print(this.sourceText); 
					}
					if((常!(bool)(0)) && category==Category.enum_member)
					{
						((0x37B78F6F833B).檢 (mKind.COUNT)),
						((0x37E58F6F833B).檢 ((name=="WM_CPL_LAUNCH"?sourceText:"").COUNT)); 
					}
					if((常!(bool)(0)) && mKind.among(mKind.template_, mKind.mixin_))
					{
						if(name=="AlignedStr")
						((0x38A98F6F833B).檢 (mKind.COUNT)),
						((0x38D78F6F833B).檢 ((sourceText).COUNT)),
						((0x390C8F6F833B).檢 ((this.text).COUNT)); 
					}
					if(
						(常!(bool)(0)) && category==Category.import_ && name=="std.internal.digest.sha_SSSE3"
						/+/+Code: import std.internal.digest.sha_SSSE3 : sse3_constants=constants, transformSSSE3;+/+/
					)
					{
						((0x3A268F6F833B).檢 (mKind.COUNT)),
						
						((0x3A5B8F6F833B).檢 (
							(
								(
									(!alias_.empty?"A":"")~
									(!selective.empty?"S":"")~
									(!renamed.empty?"R":"")
								).isWild("*SR") ? sourceText : ""
							)
							.COUNT
						)); 
					}
					if((常!(bool)(0)) && category==Category.alias_)
					{
						((0x3B8F8F6F833B).檢 (mKind.COUNT)),
						((0x3BBD8F6F833B).檢 ((((type!=""?"T":"")~(originalType!=""?"O":"")=="O")?type~"|"~originalType : "").COUNT)); 
					}
					if((常!(bool)(0)) && category==Category.variable)
					{
						((0x3C7E8F6F833B).檢 (mKind.COUNT)),
						((0x3CAC8F6F833B).檢 (linkage.COUNT)),
						((0x3CDC8F6F833B).檢 (protection.COUNT)),
						((0x3D0F8F6F833B).檢 (storageClass.text.COUNT)); 
					}
					if((常!(bool)(0)) && category==Category.callable)
					{
						((0x3D928F6F833B).檢 (mKind.COUNT)),
						((0x3DC08F6F833B).檢 (linkageStr.COUNT)),
						((0x3DF38F6F833B).檢 (protectionStr.COUNT)),
						((0x3E298F6F833B).檢 (storageClass.joinSentence.COUNT)),
						((0x3E6B8F6F833B).檢 (type.COUNT)),
						((0x3E988F6F833B).檢 (originalType.ifEmpty(type).COUNT)),
						((0x3EDB8F6F833B).檢 (overrides.text.COUNT)); 
					}
				} 
			} 
			
			Category category() const => kindCategory[mKind]; 
			string kindStr() const => kindText[mKind]; 
			string protectionStr() const => protectionText[protection]; 
			string linkageStr() const => ((linkage)?("extern("~linkageCaption[linkage]~")"):("")); 
			string constraintStr() const => constraint.enfoldNonEmpty!("if(", ")"); 
			string valueStr() const => value.prefixNonEmpty!"= "; 
			
			string sourceText() const { SourceTextOptions opt; return sourceText(opt); } 
			
			string sourceText(Flag!"parentIsEnum" parentIsEnum = No.parentIsEnum)(const ref SourceTextOptions opt) const
			{
				string lastName(string s)
				=> ((opt.lastNameOnly)?(s.extractLastName):(s)); 
				string baseStr() const
				=> base.prefixNonEmpty!": "; 
				string baseAndInterfacesStr() const
				=> chain(only(base), interfaces).cache.filter!"a!=``".map!lastName.join(", ").prefixNonEmpty!": "; 
				string templateParametersStr(Flag!"instantiate" instantiate = No.instantiate)() const
				=> parameters.map!text.join(", ").enfoldNonEmpty!(((instantiate)?("!("):("(")), ')'); 
				string membersStr() const
				=> members.map!((m)=>(m.sourceText(opt))).joinLines; 
				string membersList() const
				=> members.map!((m)=>(m.sourceText!(Yes.parentIsEnum)(opt))).join(",\n"); 
				
				if(category==Category.callable) globalCnt++; 
				
				switch(category)
				{
					case Category.aggregate: 	{
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
					}
					version(all)
					{
						case Category.enum_: 	return only(
							protectionStr, "enum", name, baseStr, 
							"{"~((opt.recursive)?(membersList):(""))~"}"
						).joinSentence; 
						case Category.enum_member: 	return ((parentIsEnum)?(joinWithTab(name, valueStr)) :(only(protectionStr, "enum", name, valueStr).joinSentence~';')); 
					}
					version(all)
					{
						case Category.import_: 	return only(
							protectionStr, kindStr, alias_.postfixNonEmpty!" =", name, 
							(
								chain(selective, renamed.byKeyValue.map!q{a.key~" = "~a.value})
								.array.sort.join(", ")/+Opt: Slow.  Should be cached...+/
								.prefixNonEmpty!": "
							)
						).joinSentence~';'; 
					}
					version(all)
					{
						case Category.alias_: 	return only(
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
						).joinSentence~';'; 
					}
					version(all)
					{
						case Category.variable: 	return only(
							protectionStr, linkageStr, storageClass.joinSentence, 
							originalType.ifEmpty(type), name, prefixNonEmpty!"= "(init_)
						).joinSentence~';'; 
					}
					version(all)
					{
						case Category.callable: 	{
							return only(
								protectionStr, name, //'('~parameters.map!text.join(", ")~')',
								"=", storageClass.joinSentence, /+linkageStr <- redundant+/ 
								originalType.ifEmpty(type)
							).joinSentence~';'; 
						}
					}
					default: 	return ""; 
				}
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
		
		void accumulateStructureStats(ref StructureStats st) const
		{
			st.moduleCount++; 
			st.sizeBytes += typeid(this).initializer.length; 
			foreach(const ref member; members) .accumulateStructureStats(member, st); 
			foreach(mod; modules) mod.accumulateStructureStats(st); 
		} 
		
		string sourceText() const
		=> "module "~name~" {"~chain(
			members.map!((m)=>(m.sourceText)),
			modules.map!((m)=>(m.sourceText))
		).joinLines~"}"; 
		
	} 
	Path workPath, stdPath, libPath; 
	ModuleDeclarations root; 
	
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
	
	void regenerateStd()
	{
		LOG(i"Importing std module declarations from $(stdPath.quoted('`'))..."); 
		ModuleDeclarations[] importedModules; 	auto _間=init間; 
		auto stdFiles = listDLangFiles(stdPath)[0..$]; 	((0x5B7E8F6F833B).檢((update間(_間)))); 
		mixin(求each(q{f},q{
			stdFiles
			.parallel
		},q{
			try
			{
				auto 	json 	= f.generateDLangXJson([]),
					mods 	= ModuleDeclarations.createFromJson(json); 
				synchronized importedModules ~= mods; 
			}
			catch(Exception e)	ERR(f, e.simpleMsg); 
		})); 	((0x5CC18F6F833B).檢((update間(_間)))); 
		((0x5CF08F6F833B).檢(makeStatistics(importedModules).toJson)); 	((0x5D318F6F833B).檢((update間(_間)))); 
		acquireMembers(importedModules); 
	} 
	
	void saveStd()
	{
		try {
			auto _間=init間; 
			auto json = root.toJson(true, false, true); 	((0x5DF18F6F833B).檢((update間(_間)))); ((0x5E1C8F6F833B).檢(json.length)); 
			auto compr = json.compress; 	((0x5E638F6F833B).檢((update間(_間)))); ((0x5E8E8F6F833B).檢((((double(compr.length)))/(json.length)))); 
			stdCacheFile.write(compr); 	((0x5EF18F6F833B).檢((update間(_間)))); 
		}
		catch(Exception e) ERR(e.simpleMsg); 
	} 
	
	void loadStd()
	{
		try {
			auto _間=init間; 
			auto compr = stdCacheFile.read; if(compr.empty) return; 	((0x5FC68F6F833B).檢((update間(_間)))); 
			auto json = (cast(string)(compr.uncompress)); 	((0x60258F6F833B).檢((update間(_間)))); 
			ModuleDeclarations newRoot; 	
			newRoot.fromJson(json, stdCacheFile.fullName); 	((0x60A78F6F833B).檢((update間(_間)))); 
			if(newRoot) root = newRoot; 
		}
		catch(Exception e) { ERR(e.simpleMsg); }
	} 
	
	auto makeStatistics(R)(R modules)
	{ StructureStats st; root.accumulateStructureStats(st); return st; } 
	
	
	auto search()
	{} 
} 


void main()
{
	console(
		{
			static if((常!(bool)(1)))
			{
				//unittest_stream; 
				//unittest_JsonClassInheritance; 
				
				registerStoredClass!(DDB.ModuleDeclarations); 
				
				auto ddb = new DDB; 
				ddb.regenerateStd; 
				ddb.saveStd; 
				ddb.loadStd; 
				
				
				((0x62EE8F6F833B).檢 (globalCnt)); 
				globalCnt=0; 
				ddb.root.sourceText.saveTo(File(`z:\declarations.d`)); 
				((0x63688F6F833B).檢 (globalCnt)); 
				
				//ddb.dumpAllMembers; 
				
				
				uint[string] kindCount; 
				uint[string] nonzeroFieldCount; 
				
				void visit(S)(const ref S structure, string parentField="")
				{
					string kind2()
					{
						static if(__traits(compiles, structure.category))
						return "_"~structure.category.text; 
						else
						return structure.kind.text; 
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
				
				void visitM(DDB.ModuleDeclarations md)
				{
					foreach(ref const member; md.members) visit(member); 
					foreach(module_; md.modules) visitM(module_); 
				} 
				
				visitM(ddb.root); 
				
				void printMap(alias m)()
				{
					print(m.stringof, "-----------------------------"); 
					m.keys.sort.each!((k){ print(format!"%-9s  %s"(m[k], k.splitter(".").map!"a.format!`%-32s`".join)); }); 
					print; 
				} 
				
				printMap!kindCount; 
				printMap!nonzeroFieldCount; 
				
			}
			
			
		}
	); 
} 