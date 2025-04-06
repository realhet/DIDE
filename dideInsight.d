module dideinsight; 

import didebase, std.parallelism; 

import didetextselectionmanager : TextSelectionManager; 
import didemodulemanager : ModuleManager; 
import dideeditor : Editor; 

import didemoduledecl; 
public import didemoduledecl : ModuleDeclarations; 
class DDB
{
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
		else	{ mixin(求each(q{f},q{files},q{importedModules ~= doit(f); })); }	((0x643CB5BA4A0).檢((update間(_間)))); 
		acquireMembers(isStd, importedModules); 	((0x69ACB5BA4A0).檢((update間(_間)))); 
	} 
	
	void processIncomingProjectJson(string xJson)
	{
		if(xJson=="") return; 
		/+Opt: Cache jsons, Only call createFromJson() when really needed!+/
		try { acquireMembers(isStd: false, ModuleDeclarations.createFromJson(xJson)); }
		catch(Exception e) { ERR(e.simpleMsg); }
	} 
	
	void regenerateStd()
	{
		LOG(i"Importing std module declarations from $(stdPath.quoted('`'))..."); 
		auto _間=init間; 
		auto stdFiles = listDLangFiles(stdPath); 	((0x898CB5BA4A0).檢((update間(_間)))); 
		regenerate_internal!true(true, stdFiles, []); 	((0x8F5CB5BA4A0).檢((update間(_間)))); 
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
			auto json = root.toJson(true, false, true); 	((0xB52CB5BA4A0).檢((update間(_間)))); ((0xB7CCB5BA4A0).檢(json.length)); 
			auto compr = json.compress; 	((0xBC2CB5BA4A0).檢((update間(_間)))); ((0xBECCB5BA4A0).檢((((double(compr.length)))/(json.length)))); 
			stdCacheFile.write(compr); 	((0xC4ECB5BA4A0).檢((update間(_間)))); 
		}
		catch(Exception e) ERR(e.simpleMsg); 
	} 
	
	static ModuleDeclarations loadCache_static(File file)
	{
		ModuleDeclarations newRoot; 
		try {
			auto _間=init間; 
			auto compr = file.read; 	((0xD49CB5BA4A0).檢((update間(_間)))); 
			if(!compr.empty)
			{
				auto json = (cast(string)(compr.uncompress)); 	((0xDC3CB5BA4A0).檢((update間(_間)))); 
				newRoot.fromJson(json, file.fullName); 	((0xE1BCB5BA4A0).檢((update間(_間)))); 
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
		
		void visitM(ModuleDeclarations md)
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
	
} static struct Insight
{
	bool activateRequest; 
	@STORED
	{
		bool visible, setupVisible; 
		string searchText; 
	} 
	
	void activate(string s)
	{
		initialize; 
		activateRequest = true; searchText=s; 
	} 
	
	void deactivate()
	{ if(visible.chkClear) { searchText = ""; }} 
	
	
	DDB ddb; 
	VirtualTreeView!(DDB.PathNode) treeView, resultTreeView; 
	
	void initialize()
	{
		if(!ddb) {
			ddb = new DDB(
				Path(`z:\temp2`),
				Path(`c:\d\ldc2\import`),
				Path(`c:\d\libs`),
				File(appPath, `$stdlib_cache.dat`)
			); 
			treeView = new typeof(treeView); 
			resultTreeView = new typeof(resultTreeView); 
			
			ddb.startDelayedCacheLoader; 
		}
	} 
	
	import core.thread.fiber; 
	static class InsightFiber : Fiber
	{
		/+Todo: this fiber searcher looks common -> SearcFiber too.  Refactor it.+/
		mixin SmartChild!
		(
			q{
				DDB ddb, 
				string searchText,
				Object resultTreeView
			}, 
			q{
				super(
					&run, 16<<10/+measured stack: only 3840 Bytes+/
					/+
						Todo: Display a warning or error when the stack is not enough
						Manage the fiber stack safely! 
						It can't run out with access violation, that's totally unreliable.
					+/
				); 
			}
		); 
		
		DateTime timeLimit; 
		
		private void run()
		{
			auto res = (cast(
				VirtualTreeView!(DDB.PathNode)
				/+Todo: SmartClass can't handle this crap.+/
			)(resultTreeView)).enforce; 
			if(searchText!="")
			{ ddb.search_yield(res, searchText, timeLimit); }
			else
			{
				res._root = DDB.PathNode(ddb.root); 
				res.changed = now; 
			}
		} 
	} 
	InsightFiber insightFiber; 
	
	void updateInsightFiber()/+Todo: rename to update()+/
	{
		initialize; 
		ddb.updateDelayedCacheLoader; 
		
		if(insightFiber && !visible) { insightFiber.free; }
		
		if(insightFiber)
		{
			if(insightFiber.state==Fiber.State.TERM) insightFiber.free; 
			else {
				insightFiber.timeLimit = now + 10*milli(second); 
				insightFiber.call; 
			}
		}
	} 
	
	void processIncomingProjectJson(string xJson)
	{
		if(xJson!="") {
			initialize; 
			ddb.processIncomingProjectJson(xJson); 
		}
	} 
	
	
	static string decodeEasyWildcard(string s)
	{
		{
			//many spaces to one
			re: auto len = s.length; s = s.replace("  ", " "); 
			if(s.length<len) goto re; 
		}
		
		if(s=="" || s==" ") return ""; 
		
		if(s.canFind('*') || s.canFind('?') || s.canFind('.')) return s; 
		
		if(s.startsWith(" ")) s = s[1..$]; s = '*'~s; 
		if(s.endsWith(" ")) s = s[0..$-1]; s = s~'*'; 
		s = s.replace(" ", "*.*"); 
		return s; 
	} 
	
	bool UI(ModuleManager modules, TextSelectionManager textSelections, Editor editor, INavigator navig, View2D view)
	{
		initialize; 
		with(im)
		{
			{
				bool justActivated; 
				if(activateRequest.chkClear)
				{ visible = justActivated = true; }
				
				if(visible)
				{ UI_insightPanel(modules, textSelections, editor, navig, view, justActivated); }
				
				return visible; 
			}
		}
	} 
	
	void UI_insightPanel(ModuleManager modules, TextSelectionManager textSelections, Editor editor, INavigator navig, View2D view, bool justActivated)
	{
		enforce(ddb); 
		with(im)
		{
			void onClick(DDB.PathNode* node)
			{
				auto actTreeView() => searchText=="" ? treeView : resultTreeView; 
				auto getParent() => actTreeView.getParentItem(node); 
				
				void type(bool advanced=false)
				{
					if(!textSelections.empty)
					{
						auto s = node.name, pasted = false; 
						void pasteText(string s) { editor.pasteText(s); pasted = true; } 
						void pasteNode(string s) { editor.insertNode(s); pasted = true; } 
						
						if(advanced)
						{
							if(auto member = node.asMember)
							if(member.category==ModuleDeclarations.Member.Category.enum_member)
							{
								if(auto p = getParent)
								{
									auto t = p.name; 
									if(t!="")
									{ pasteNode(`mixin(舉!((`~t~`),q{`~member.name~`}))`); }
								}
							}
						}
						
						if(!pasted) pasteText(s); 
					}
					else im.flashWarning("Can't insert text. Place a cursor first!"); 
				} 
				
				void navigate()
				{
					void doit(File f, int line=0, int col=0)
					{
						if(f)
						{
							f = f.actualFile; 
							if(f.exists)
							{
								auto m = modules.findModule(f); 
								if(!m) { modules.loadModule(f); m = modules.findModule(f); }
								if(m) {
									if(!line) navig.jumpTo(m); 
									else { navig.jumpTo(CodeLocation(f.fullName, line.max(1), col.max(1))); }
								}
								else { flashWarning("Can't load module: "~f.quoted('`')); }
							}
							else { flashWarning("File not found: "~f.quoted('`')); }
						}
					} 
					
					int line, char_; 
					foreach_reverse(n; actTreeView.getAllParentItems(node) ~ node)
					if(n)
					{
						if(auto member = n.asMember)
						{
							if(!line && member.line)
							{
								line = member.line; 
								if(!char_ && member.char_) char_ = member.char_; 
								/+Todo: endline endchar for callable!+/
							}
						}
						else if(auto mod = n.asModule)
						{
							if(mod.file)
							{ doit(mod.file, line, char_); }
							break; /+Only the last module+/
						}
					}
				} 
				
				if(inputs.Ctrl.down)	navigate; 
				else	type(inputs.Alt.down); 
			} 
			Column(
				{
					//Keyboard shortcuts
					auto 	kcInsightType	= KeyCombo("Enter"), //only when edit is focused
						kcInsightClose	= KeyCombo("Esc"); //always
					
					void sw() { outerWidth = fh*18; } 
					
					Row(
						{
							sw; Text("Insight"); .Container editContainer; 
							
							const searcHash = searchText.hashOf; 
							static size_t lastSearchHash; //Todo: static is ugly. It's a workspace property
							const searchHashChanged = lastSearchHash.chkSet(searcHash); 
							
							
							if(
								Edit(searchText, ((justActivated).genericArg!q{focusEnter}), { flex = 1; editContainer = actContainer; })
								|| justActivated || searchHashChanged
							)
							{ insightFiber = new InsightFiber(ddb, decodeEasyWildcard(searchText), resultTreeView); }
							
							BtnRow(
								{
									if(Btn("⚙", hint("Setup"), selected(setupVisible)))
									setupVisible.toggle; 
								}
							); 
							if(
								Btn(
									bold(symbol("ChevronRight")), { innerWidth = fh; }, 
									kcInsightClose, hint("Close panel.")
								)
							)
							{ deactivate; }
						}
					); 
					if(setupVisible)
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
										/+
											if(Btn("hetLib")) regenerateLib(hetlibFiles)/+14.2MB+/; 
											if(Btn("dide")) regenerateProject(dideFiles, dideArgs)/+2.1MB+/; 
											if(Btn("karc")) regenerateProject(karcFiles, karcArgs)/+0.75MB+/; 
										+/
									} 
								); 
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
						Row(
							{
								Grp!Row("Mods", { Static(moduleCount, { width = 1.5f*fh; }); }); 
								Grp!Row("Members", { Static(memberCount, { width = 2.5f*fh; }); }); 
								Grp!Row("Rows", { Static(((searchText=="") ?(treeView):(resultTreeView)).rows.length, { width = 2.5f*fh; }); }); 
							}
						); 
						Grp!Row("Decoded EasyWildcard™", { Text(decodeEasyWildcard(searchText)); width = 16*fh; }); 
						Grp!Row(
							"Help", {
								Text(
									bold("LMB")	, " type | "	,
									bold("Alt+LMB")	, " adv.type | "	,
									bold("Ctrl+LMB")	, " navig."	
								); width = 16*fh; 
							}
						); 
					}
					
					actContainer.measure; 
					const treeHeight = mainWindow.clientHeight - outerHeight - 50; /+Todo: fucking lame. Fix aligning engine.+/
					
					void UI_node(DDB.PathNode* node)
					{
						with(im)
						{
							if(Btn({ node.UI; }, ((node.identityStr).genericArg!q{id})))
							{ onClick(node); }
						}
					} 
					
					if(searchText=="")
					{
						with(ddb) treeView.root = PathNode(root); /+Todo: this is misleading! It has internal change detection+/
						treeView.UI(
							{ sw; outerHeight = treeHeight; }, &UI_node
							
						); 
					}
					else
					{ resultTreeView.UI({ sw; outerHeight = treeHeight; }, &UI_node); }
				}
			); 
		}
	} 
} 