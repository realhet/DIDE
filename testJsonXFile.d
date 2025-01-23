//@exe
//@debug
//@release

import het.ui; 

version(all)
{
	RGB brighter(RGB a, float f)
	{ return (a.from_unorm*(1+f)).to_unorm; } 
	
	enum clPiko : RGB
	{
		G940 	= (RGB(139,  59,  43)).brighter(.25f),
		G239 	= (RGB(245, 156,   0)),
		G231 	= (RGB(238, 114,   3)),
		G119 	= (RGB(221,  11,  47)).brighter(.35f),
		G115 	= (RGB(222,   0, 126)),
		G107 	= (RGB(158,  25, 129)).brighter(.125f),
		G62 	= (RGB( 92,  36, 131)).brighter(.25f),
		R1 	= (RGB( 22, 186, 231)),
		R2 	= (RGB(  0, 134, 192)),
		R3 	= (RGB(  0, 105, 180)),
		R4 	= (RGB(  0,  79, 159)),
		R9 	= (RGB(  0,  48,  93)),
		W 	= (RGB(134, 188,  37)),
		BW 	= (RGB(101, 179,  46)),
		W3 	= (RGB(  0, 120,  88)),
		WY 	= (RGB(  0, 169, 132)),
		K15 	= (RGB(255, 227, 126)),
		K30 	= (RGB(255, 237,   0)),
		DKW 	= (RGB(255, 204,   0)),
		GE31 	= (RGB(157, 157, 156)),
	} RGB structuredColor(string name, RGB def = clGray)
	{
		switch(name)
		{
			case "template": 	return clPiko.G940; 
			case "enum": 	return clPiko.G239; 
			case "alias": 	return clPiko.G231; 
			case "if", "switch", "final switch", "else": 	return clPiko.G119.brighter(.25f); 
			case "for", "do", "while", "foreach", "foreach_reverse": 	return mix(clOrange, RGB(221, 11, 47), .66f).brighter(.25f); 
			case "version", "debug", "static if", "static foreach", "static foreach_reverse", "static assert": 	return mix(clPiko.G115, clPiko.G119, .5f).brighter(.25f); 
			case "module", "import": 	return clPiko.G107; 
			case "unittest": 	return clPiko.G62; 
				
			case "section": 	return clPiko.R1; 
			case "with": 	return clPiko.R2; 
			case "__unused1": 	return clPiko.R4; 
				
			case "class": 	return clPiko.W; 
			case "interface": 	return clPiko.BW; 
			case "struct": 	return clPiko.W3; 
			case "union": 	return clPiko.WY; 
			case "mixin template": 	return clPiko.K15; 
			case "mixin": 	return mix(clPiko.DKW, clPiko.G119, .75f); 
			case "statement": 	return clGray; 
			case "function", "invariant": 	return clSilver; 
			case "__region": 	return clGray; 
				
			case "try": 	return RGB(200, 250, 189); 
			case "scope": 	return RGB(50, 250, 189); 
			case "assert", "break", "continue", "goto", "goto case", "return"	, "enforce": 	return mix(RGB(0x5C00F6/+skKeyword+/), clWhite, .5); 
			
			case "auto": 	return clAqua; 
			
			default: 	return def; 
		}
	} 
}version(all)
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

string generateDLangXJson(File moduleFile, Path tempPath, in string[] extraArgs=[])
{
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
		} 	@property int	moduleCount() const
		=> 1 + mixin(求sum(q{mo},q{modules},q{mo.moduleCount})); 	@property int memberCount() const
		=> mixin(求sum(q{const ref me},q{members},q{me.memberCount})) + mixin(求sum(q{mo},q{modules},q{mo.memberCount})); 
		
		DateTime updated/+last time when the contents of this module was updated.+/; 
		
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
			
			@property int memberCount() const
			=> 1 + mixin(求sum(q{const ref me},q{members},q{me.memberCount})); 
			
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
					
					if(m.name==""/+main module file+/)
					m.name = m.file.nameWithoutExt.lc; 
					
					res ~= m; 
				}
				else
				WARN("Not a valid XJSon module."); 
			}
			return res; 
		} 
		
		auto findModule(string name)
		{ return modules.find!((m)=>(m.name==name)).frontOrNull; } 
		
		private void acquireMembers(bool isStd, ModuleDeclarations src, string[] srcPath)
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
				members = src.members; /+replace with new members+/
				if(isStd && !this.isStd)
				{ WARN("STD inconsistency. "~src.file.quoted); }
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
					nextModule.name 	= nextName,
					nextModule.isStd 	= isStd; 
					modules ~= nextModule; 
				}
				print("Doing recursion in:", nextName); 
				nextModule.acquireMembers(isStd, src, srcPath); 
			}
			
			updated = now; 
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
	File stdCacheFile; 
	ModuleDeclarations root; 
	
	alias SourceTextOptions = ModuleDeclarations.SourceTextOptions; 
	
	protected
	{
		void acquireMembers(bool isStd, ModuleDeclarations md)
		{ root.acquireMembers(isStd, md, md.name.split('.')); } 
		void acquireMembers(R)(bool isStd, R r) { mixin(求each(q{m},q{r},q{acquireMembers(isStd, m)})); } 
	} 
	
	this(Path workPath, Path stdPath, Path libPath, File stdCacheFile)
	{
		this.workPath 	= workPath,
		this.stdPath	= stdPath,
		this.libPath 	= libPath,
		this.stdCacheFile 	= stdCacheFile; 
		wipeAll/+creates a new root.+/; 
	} 
	
	protected void regenerate_internal(bool isParallel)(bool isStd, in File[] files, in string[] args)
	{
		ModuleDeclarations[] doit(File f)
		{
			try
			{
				const json = f.generateDLangXJson(workPath, args); 
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
		else	{ mixin(求each(q{f},q{files},q{importedModules ~= doit(f); })); }	((0x60F38F6F833B).檢((update間(_間)))); 
		acquireMembers(isStd, importedModules); 	((0x614B8F6F833B).檢((update間(_間)))); 
	} 
	
	void regenerateStd()
	{
		LOG(i"Importing std module declarations from $(stdPath.quoted('`'))..."); 
		auto _間=init間; 
		auto stdFiles = listDLangFiles(stdPath); 	((0x622C8F6F833B).檢((update間(_間)))); 
		regenerate_internal!true(true, stdFiles, []); 	((0x628A8F6F833B).檢((update間(_間)))); 
	} 
	
	void regenerateLib(in File[] files, in string[] args=[])
	{
		if(files.empty) return; 
		regenerate_internal!true(false, files, ["-I", libPath.fullPath]~args); 
	} 
	
	void regenerateProject(in File[] files, in string[] args=[])
	{
		if(files.empty) return; 
		const projectPath = files.front.path; 
		regenerate_internal!true(
			false, files, [
				"-I", projectPath	.fullPath,
				"-I", libPath	.fullPath
			]~args
		); 
	} 
	
	void saveCache()
	{
		try {
			auto _間=init間; 
			auto json = root.toJson(true, false, true); 	((0x64E88F6F833B).檢((update間(_間)))); ((0x65138F6F833B).檢(json.length)); 
			auto compr = json.compress; 	((0x655A8F6F833B).檢((update間(_間)))); ((0x65858F6F833B).檢((((double(compr.length)))/(json.length)))); 
			stdCacheFile.write(compr); 	((0x65E88F6F833B).檢((update間(_間)))); 
		}
		catch(Exception e) ERR(e.simpleMsg); 
	} 
	
	void loadCache()
	{
		try {
			auto _間=init間; 
			auto compr = stdCacheFile.read; if(compr.empty) return; 	((0x66BF8F6F833B).檢((update間(_間)))); 
			auto json = (cast(string)(compr.uncompress)); 	((0x671E8F6F833B).檢((update間(_間)))); 
			ModuleDeclarations newRoot; 	
			newRoot.fromJson(json, stdCacheFile.fullName); 	((0x67A08F6F833B).檢((update間(_間)))); 
			if(newRoot) root = newRoot; 
		}
		catch(Exception e) { ERR(e.simpleMsg); }
	} 
	
	void wipeAll()
	{ root = new ModuleDeclarations(); ; } 
	
	void wipeProject()
	{
		/+
			Note: Notes: 	• root is NOT std! It is always there. 
				• Main project file should have a name. -> fileNameWithoutExt.lc
				/+Todo: Decide if main module should be at root or not.+/
		+/
		root.modules = root.modules.remove!((m)=>(!m.isStd)); 
		root.members = []; //It wipes the unnamed module, just to be safe
	} 
	@property moduleCount()const => root.moduleCount; 
	@property memberCount()const => root.memberCount; 
	
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
	
	
	struct PathNode
	{
		import std.sumtype; alias Member = ModuleDeclarations.Member, Parameter = ModuleDeclarations.Parameter; 
		
		SumType!(ModuleDeclarations, Member*, Parameter*) _node; 
		
		bool opened; 
		PathNode[] subNodes; 
		
		this(ModuleDeclarations m)
		{ _node = m; } 	 this(Member* m)
		{ _node = m; } 	 this(Parameter* p)
		{ _node = p; } 
		
		auto copySearchResult()
		{ PathNode res; res._node = _node; res.opened = true; return res; } 
		
		@property string name() const
		=> _node.match!(
			((in ModuleDeclarations m)=>(m.name)), 
			((in Member* m)=>(m.name)), 
			((in Parameter* p)=>(p.name))
		); 
		
		bool opEquals(A)(A other) const
		=> _node.match!(
			((in ModuleDeclarations m)=>(m is other.asModule)), 
			((in Member* m)=>(m is other.asMember)), 
			((in Parameter* p)=>(p is other.asParameter))
		); 
		
		ModuleDeclarations asModule()
		=> _node.match!(((ModuleDeclarations m)=>(m)), ((void*)=>(null))); 
		Member* asMember()
		=> _node.match!(((Member* m)=>(m)), ((void*)=>(null)), ((ModuleDeclarations)=>(null))); 
		Parameter* asParameter()
		=> _node.match!(((Parameter* p)=>(p)), ((void*)=>(null)), ((ModuleDeclarations)=>(null))); 
		
		PathNode[] collectSubNodes()
		{
			auto sortedNodes(E)(E[] arr)
			{
				static if(is(E==class))	auto a = arr.map!PathNode.array; 
				else	auto a = arr.map!((ref a)=>(PathNode(&a))); 
				return a.array.sort!"a.name<b.name".array; 
			} 
			return _node.match!
			(
				((ModuleDeclarations m)=>(
					sortedNodes(m.modules) ~
					sortedNodes(m.members)
				)),
				((Member* m)=>(
					sortedNodes(m.members) ~
					sortedNodes(m.parameters)
				)),
				((Parameter* p)=>(null))
			); 
		} 
		
		@property canOpen()
		=> _node.match!(
			((ModuleDeclarations m)=>(!m.modules.empty || !m.members.empty)),
			((Member* m)=>(!m.members.empty)),
			((Parameter* p)=>(false))
		); 
		
		void open()
		{
			if(canOpen && opened.chkSet)
			subNodes = collectSubNodes; 
		} 	 void close()
		{
			opened = false; 
			/+
				remember
				opened items
			+/
		} 	 void toggle()
		{
			if(opened)	close; 
			else	open; 
		} 
		
		void UI()
		{
			with(im)
			{
				auto module_ = asModule, member = asMember, param = asParameter; 
				if(
					Btn(
						{
							style.bold = !!module_; 
							const stru = 	module_ 	? "module" : 
								member 	? kindText[member.mKind] : 
								param 	? "param" : ""; 
							bkColor = style.bkColor = structuredColor(stru, clWhite); 
							style.fontColor = blackOrWhiteFor(bkColor); 
							Text(name); 
						}
					)
				)
				{ beep; }
			}
		} 
	} 
	
	
	auto search(string searchText)
	{
		auto res = PathNode(root); 
		void appendRes(PathNode[] nodes)
		{
			//LOG(nodes.map!"a.name".join(".")); 
			
			auto actDst = &res; 
			foreach(src; nodes[1..$]/+nodes[0] is root+/)
			{
				auto idx = actDst.subNodes.countUntil!((a)=>(a.name==src.name)); 
				if(idx<0) {
					idx = actDst.subNodes.length; 
					actDst.subNodes ~= src.copySearchResult; 
				}
				actDst.opened = true; 
				
				/+advance+/actDst = &actDst.subNodes[idx]; 
			}
		} 
		
		void visit(PathNode[] nodes, string[] filters)
		{
			if(filters.empty || nodes.empty) return; 
			if(nodes.back.name.isWild(filters.front))
			{
				if(filters.length==1)	{ appendRes(nodes); }
				else	{
					foreach(
						sn; nodes.back.collectSubNodes
						/+Opt: make a functional visitSubnodes()+/
					)
					{ visit(nodes ~ sn, filters[1..$])/+recursion for this match!+/; }
				}
			}
			foreach(
				sn; nodes.back.collectSubNodes
				/+Opt: make a functional visitSubnodes()+/
			)
			{ visit(nodes ~ sn, filters)/+recursion for internal maches too!+/; }
		} 
		auto _間=init間; visit([PathNode(root)], searchText.split('.')); ((0x81DD8F6F833B).檢((update間(_間)))); 
		return res; 
	} 
} 

class VirtualTreeView(Item) if(is(Item==struct))
{
	Item root_; 
	@property root(Item a) { if(root_.chkSet(a)) changed = now; } 
	@property ref root() => root_; 
	
	struct TreeRow
	{
		Item* item; 
		string prefix; 
	} 
	TreeRow[] rows; 
	float maxRowWidth = 0; 
	DateTime rowsUpdated, changed; 
	bool showBullet=true; /+if there is no icon, a bullet mark looks nice in front of the item name+/
	
	void makeRows()
	{
		void doit(ref Item act, string prefix, bool isLast)
		{
			rows ~= TreeRow(&act, prefix ~ ((isLast)?('L'):('+'))); 
			if(act.opened /+recustion+/)
			{
				const newPrefix = (prefix ~ ((isLast)?(' '):('I'))).text; 
				foreach(i, ref a; act.subNodes) doit(a, newPrefix, (i+1==act.subNodes.length)); 
			}
		} 
		auto _間=init間; {
			rows = []; maxRowWidth = 0; 
			doit(root_, "", true); 
			rowsUpdated = now; 
		}((0x858B8F6F833B).檢((update間(_間)))); ((0x85B68F6F833B).檢(rows.length)); 
	} 
	
	this()
	{} 
	
	void UI(void delegate() setup/+must set outerSize in setup! Optionally can set fontHeight+/)
	{
		auto _間=init間; 
		with(im)
		{
			Container(
				((identityStr(this)).genericArg!q{id}),
				{
					theme = "tool"; 
					with(flags)
					vScrollState 	= ScrollState.auto_,
					hScrollState 	= ScrollState.auto_,
					clipSubCells 	= true; 
					
					if(rowsUpdated<changed) makeRows; 
					
					if(setup) setup(); 
					
					//total size placeholder
					const float 	fh 	= style.fontHeight/+For faster access. Many things depend on 'fh'.+/, 
						rowHeight 	= fh, 
						invRowHeight 	= 1/rowHeight; 
					Container({ outerPos = vec2(maxRowWidth, rows.length*rowHeight); outerSize = vec2(0); }); 
					
					flags.saveVisibleBounds = true; 
					if(const visibleBounds = imstVisibleBounds(actId))
					{
						{
							foreach(
								i; 	(ifloor(visibleBounds.top    * invRowHeight    )).max(0) ..
									(iceil(visibleBounds.bottom * invRowHeight + 1)).min(rows.length.to!int)
							)
							{
								auto r = &rows[i]; 
								Row(
									((identityStr(r.item)).genericArg!q{id}),
									{
										flags.wordWrap = false; outerPos = vec2(0, i*rowHeight); outerHeight = fh; 
										
										version(/+$DIDE_REGION Tree graphics+/all)
										{
											Row(
												{
													outerSize = vec2(r.prefix.length, 1)*fh; 
													{
														auto dr = new Drawing; 
														dr.color = clGray; dr.lineWidth = 1; 
														float x = fh*.5f; 
														foreach(ch; r.prefix.byChar)
														{
															if(ch.among('+', 'I')) dr.vLine(x, 0, fh); 
															if(ch.among('+', 'L')) dr.circle(x+.5*fh, 0, fh*.5f, -π/2, 0); 
															x += fh; 
														}
														addOverlayDrawing(dr); 
													}
												}
											); 
										}
										
										version(/+$DIDE_REGION Tree Open/Close Button+/all)
										{
											if(r.item.canOpen)
											{
												if(
													Btn(
														{
															margin = Margin.init; outerSize = vec2(fh); 
															Text(((r.item.opened)?("▼"):("▷"))); 
														}
													)
												) {
													r.item.toggle; 
													this.changed = now; 
												}
											}
											else
											{ if(showBullet) Row({ outerSize = vec2(fh); flags.hAlign = HAlign.center; Text("•"); }); }
										}
										
										r.item.UI; //the actual and responsive UI of the item
									}
								); 
							}
						}
					}
					
					//Arrange the visible rows
					auto rowCtrls() => actContainer.subCells.drop(1).map!((a)=>((cast(het.ui.Row)(a)))); 
					maxRowWidth = 0; 
					foreach(r; rowCtrls) { r.needMeasure; r.measure; maxRowWidth.maximize(r.outerWidth); }
					
					//foreach(r; rowCtrls) { r.outerWidth = maxRowWidth; }
				}
			); 
		}
		((0x91768F6F833B).檢((update間(_間)))); 
	} 
} 

struct DirNode
{
	import std.sumtype; 
	SumType!(File, Path) _node; 
	
	bool opened; 
	DirNode[] subNodes; 
	
	this(File f)
	{ _node = f; } 	 File asFile()
	=> _node.match!(
		((File f)=>(f)), 
		((Path)=>(File.init))
	); 	 	bool isFile()
	=> _node.match!(
		((File f)=>(true)), 
		((Path)=>(false))
	); 
	this(Path p)
	{ _node = p; } 	 Path asPath()
	=> _node.match!(
		((Path p)=>(p)), 
		((File)=>(Path.init))
	); 	 bool isPath()
	=> _node.match!(
		((Path p)=>(true)), 
		((File)=>(false))
	); 
	
	@property string name() const
	=> _node.match!(
		((in File f)=>(f.name)), 
		((in Path p)=>(p.name))
	); 	 bool opEquals(A)(A other) const
	=> _node.match!(
		((in File f)=>(other.isFile && f==other.asFile)), 
		((in Path p)=>(other.isPath && p==other.asPath))
	); 
	
	DirNode[] collectSubNodes()
	{
		return _node.match!(
			((Path p)=>(
				subNodes = chain(
					p.paths	.map!DirNode, 
					p.files	.map!DirNode
				).array
			)), ((File f)=>(null))
		); 
	} 
	
	@property canOpen()
	=> isPath; 
	
	void open()
	{
		if(canOpen && opened.chkSet)
		subNodes = collectSubNodes; 
	} 	 void close()
	{
		opened = false; 
		/+
			remember
			opened items
		+/
	} 	 void toggle()
	{
		if(opened)	close; 
		else	open; 
	} 
	
	void UI()
	{
		with(im)
		{
			void Img(string s) { Spacer(4); im.Img(`icon:\`~s~`&small`); Spacer(4); } 
			_node.match!
			(
				((in File  f){ Img('.'~f.ext); Text(f.name); }), 
				((in Path p){ Img(((p.fullPath.isWild("?:")) ?(p.fullPath):(`folder`))~'\\'); Text(bold(p.name)); })
			); 
		}
	} 
} 

class MainForm : GLWindow
{
	mixin autoCreate; 
	
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
		const dideArgs = ["--d-version=stringId"]; 
		
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
		const karcArgs = ["--d-version=VulkanHeadless"]; 
	}
	
	DDB ddb; 
	string searchText; 
	
	
	VirtualTreeView!(DDB.PathNode) treeView, resultTreeView; 
	
	VirtualTreeView!DirNode dirTreeView; 
	
	override void onCreate()
	{
		ddb = new DDB(
			Path(`z:\temp2`),
			Path(`c:\d\ldc2\import`),
			Path(`c:\d\libs`),
			File(`z:\temp2\$stdlib_cache.dat`)
		); 
		treeView = new typeof(treeView); 
		enforce(chain(hetlibFiles, dideFiles, karcFiles).all!"a.exists"); 
		
		resultTreeView = new typeof(resultTreeView); 
	} 
	
	override void onUpdate()
	{
		view.navigate(!im.wantKeys, !im.wantMouse); 
		invalidate; 
		
		with(im)
		{
			Panel(
				PanelPosition.topClient, 
				{
					with(ddb)
					{
						Row(
							{
								Grp!Row(
									"Wipe", {
										if(Btn("all")) wipeAll; 
										if(Btn("project")) wipeProject; 
									}
								); 
								Grp!Row(
									"Regenerate", {
										if(Btn("phobos")) regenerateStd/+75.8MB+/; 
										if(Btn("hetLib")) regenerateLib(hetlibFiles)/+14.2MB+/; 
										if(Btn("dide")) regenerateProject(dideFiles, dideArgs)/+2.1MB+/; 
										if(Btn("karc")) regenerateProject(karcFiles, karcArgs)/+0.75MB+/; 
									} 
								); 
								Grp!Row(
									"Operations", {
										if(Btn("Save cache")) saveCache; 
										if(Btn("Load cache")) loadCache; 
										if(Btn("Stats")) generateMemberStats.print; 
										if(Btn("Export source"))
										{
											SourceTextOptions so; 
											root.sourceText(so).saveTo(File(`z:\declarations.d`)); 
											so.toJson.print; 
										}
									}
								); 
								Grp!Row(
									"State",
									{
										Text("modules: "); Static(moduleCount, { width = 3*fh; }); Spacer; 
										Text("members: "); Static(memberCount, { width = 3*fh; }); 
									}
								); 
								Grp!Row(
									"Search",
									{
										Edit(searchText, { width = fh*22; }); 
										if(Btn("Go")) {
											resultTreeView.root_ = search(searchText); 
											resultTreeView.changed = now; 
											/+Todo: This change mechanic is not so clear.+/
										}
									}
								); 
							}
						); 
					}
				}
			); 
			
			Panel(
				PanelPosition.leftClient, 
				{
					with(ddb)
					{
						treeView.root = PathNode(root); 
						treeView.UI(
							{
								outerWidth = 400; 
								outerHeight = clientHeight - 100/+this is lame...+/; 
							}
						); 
					}
				}
			); 
			Panel(
				PanelPosition.leftClient, 
				{
					resultTreeView.UI(
						{
							outerWidth = 400; 
							outerHeight = clientHeight - 100/+this is lame...+/; 
						}
					); 
				}
			); 
			
			Panel(
				PanelPosition.rightClient, 
				{
					if(!dirTreeView)
					{
						dirTreeView = new typeof(dirTreeView); 
						with(dirTreeView)
						{
							root = DirNode(Path(`c:\windows`)); 
							showBullet = false; 
						}
					}
					dirTreeView.UI({ outerSize = vec2(300, clientHeight - 100/+this is lame...+/); }); 
				}
			); 
		}
		
	} 
} 