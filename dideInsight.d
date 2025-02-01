module dideinsight; 

import het.ui, std.parallelism; 

private
{
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
	
	version(/+$DIDE_REGION+/all) {
		/+Todo: this is redundant. It's also in didemodule+/
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
		} 
		RGB structuredColor(string name, RGB def = clGray)
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
	}
	
	
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
		else	{ mixin(求each(q{f},q{files},q{importedModules ~= doit(f); })); }	((0x507783B10505).檢((update間(_間)))); 
		acquireMembers(isStd, importedModules); 	((0x50CF83B10505).檢((update間(_間)))); 
	} 
	
	void processIncomingProjectJsons(string[] xJsons)
	{
		if(xJsons.empty) return; 
		
		version(/+$DIDE_REGION Measure time+/all)
		{
			__gshared Time tSum=0*second; const t0 = now; 
			scope(exit) { tSum += now-t0; ((0x51E483B10505).檢(tSum)); }
			/+Opt: Cache jsons, Only call createFromJson() when really needed!+/
		}
		mixin(求each(q{json},q{xJsons},q{
			try { acquireMembers(isStd: false, ModuleDeclarations.createFromJson(json)); }
			catch(Exception e) { ERR(e.simpleMsg); }
		})); 
	} 
	
	void regenerateStd()
	{
		LOG(i"Importing std module declarations from $(stdPath.quoted('`'))..."); 
		auto _間=init間; 
		auto stdFiles = listDLangFiles(stdPath); 	((0x53B683B10505).檢((update間(_間)))); 
		regenerate_internal!true(true, stdFiles, []); 	((0x541483B10505).檢((update間(_間)))); 
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
			auto json = root.toJson(true, false, true); 	((0x567283B10505).檢((update間(_間)))); ((0x569D83B10505).檢(json.length)); 
			auto compr = json.compress; 	((0x56E483B10505).檢((update間(_間)))); ((0x570F83B10505).檢((((double(compr.length)))/(json.length)))); 
			stdCacheFile.write(compr); 	((0x577283B10505).檢((update間(_間)))); 
		}
		catch(Exception e) ERR(e.simpleMsg); 
	} 
	
	static ModuleDeclarations loadCache_static(File file)
	{
		ModuleDeclarations newRoot; 
		try {
			auto _間=init間; 
			auto compr = file.read; 	((0x586E83B10505).檢((update間(_間)))); 
			if(!compr.empty)
			{
				auto json = (cast(string)(compr.uncompress)); 	((0x58E983B10505).檢((update間(_間)))); 
				newRoot.fromJson(json, file.fullName); 	((0x594283B10505).檢((update間(_間)))); 
			}
		}
		catch(Exception e) { ERR(e.simpleMsg); }
		return newRoot; 
	} 
	
	void loadCache()
	{
		if(auto newRoot = loadCache_static(stdCacheFile))
		root = newRoot; 
	} 
	
	void startDelayedCacheLoader()
	{ future!loadCache_static(stdCacheFile);                   } 
	
	void updateDelayedCacheLoader()
	{ foreach(a; futureFetch!loadCache_static) if(a) root = a; } 
	
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
		PathNode[] subNodes; /+Todo: Find a way to detect the addition of new subNodes and reftesh this array+/
		
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
		
		@property structuredColor() 
		=> .structuredColor(
			_node.match!(
				((ModuleDeclarations m)=>("module")),
				((Member* m)=>(kindText[m.mKind])),
				((Parameter* p)=>("param"))
			)
		); 
		
		void UI()
		{
			with(im)
			{
				style.bold = !!asModule; 
				bkColor = style.bkColor = structuredColor; 
				style.fontColor = blackOrWhiteFor(bkColor); 
				Text(name); 
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
		visit([PathNode(root)], searchText.split('.')); 
		return res; 
	} 
	
	//fiber version
	auto search_yield(VirtualTreeView!PathNode res, string searchText, ref DateTime timeLimit)
	{
		res._root = PathNode(this.root); res.changed = now; 
		
		enum MeasureStack = (常!(bool)(0)); 
		static if(MeasureStack)
		{ static ulong baseSP; asm { mov baseSP, RSP; } }
		
		bool appendRes(PathNode[] nodes)
		{
			auto actDst = &res._root, anyChanged = false; 
			foreach(src; nodes[1..$]/+nodes[0] is root+/)
			{
				auto idx = actDst.subNodes.countUntil!((a)=>(a.name==src.name)); 
				if(idx<0) {
					idx = actDst.subNodes.length; 
					actDst.subNodes ~= src.copySearchResult; 
					anyChanged = true; 
				}
				actDst.opened = true; 
				
				/+advance+/actDst = &actDst.subNodes[idx]; 
			}
			return anyChanged; 
		} 
		
		void visit(PathNode[] nodes, string[] filters)
		{
			if(filters.empty || nodes.empty) return; 
			
			auto anyChanged = false; 
			
			if(nodes.back.name.isWild(filters.front))
			{
				if(filters.length==1)	{ if(appendRes(nodes)) anyChanged = true; }
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
			
			if(anyChanged) res.changed = now; 
			
			static if(MeasureStack)
			{
				{
					ulong actSP; asm { mov actSP, RSP; } 
					ulong actPos = baseSP - actSP; 
					static ulong maxPos; 
					if(maxPos.maximize(actPos)) { maxPos = actPos; print("STACK:", actPos, nodes.length); }
					
					/+
						Todo: Write a guard for this.  Get the cache size from the outside and 
						make an Exception when running low.
					+/
				}
			}
			
			if(now > timeLimit)
			{ import core.thread.fiber; Fiber.yield; /+Note: Fiber time limitation.+/}
		} 
		visit([PathNode(this.root)], searchText.split('.')); 
	} 
} 