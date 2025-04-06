module didemoduledecl;  /+This decodes xJson files produced by LDC2+/ 

import het; 

public {
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
} 
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
	
	void acquireMembers(bool isStd, ModuleDeclarations src, string[] srcPath)
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