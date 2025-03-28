module dideworkspace; 

import het.ui, dideui, didebase; 

import het.parser : CodeLocation, SyntaxKind, syntaxFontColor, syntaxBkColor; 
import buildsys : DMDMessage, decodeDMDMessages, BuildSettings, BuildSystem, BuildResult, ModuleBuildState, moduleBuildStateColors; 

import diderow : CodeRow, sourceText, hitTest; 
import didecolumn : CodeColumn; 
import didenode : CodeNode, CodeComment, StructureMap, visitNestedCodeColumns, visitNestedCodeNodes; 
import didedecl : Declaration, 	/+these are for statistics only ->+/dDeclarationRecords, processHighLevelPatterns_block; 
import didemodule : Module, moduleOf, WorkspaceInterface, StructureLevel, TextFormat, TextModification, addInspectorParticle, TextModificationRecord, cachedFolderLabel, Breadcrumb, toBreadcrumbs, nearestDeclarationBlock, DefaultNewLine, compoundObjectChar, AnimatedCursors, MaxAnimatedCursors, rearrangeLOG, drawChangeIndicators, globalChangeindicatorsAppender, globalVisualizeSpacesAndTabs, inspectorParticles, ScrumTable, ScrumSticker; 
import dideinsight : DDB, Insight; 
import dideai : AiModel, AiChat; 
alias blink = dideui.blink; 

class Workspace : Container, WorkspaceInterface
{
	interface IBuildServices
	{
		@property
		{
			bool building(); 
			bool ready(); 
			bool cancelling(); 
			bool running(); 
			bool running_console(); 
			bool canKillCompilers(); 
			bool canKillRunningProcess(); 
			bool canKillRunningConsole(); 
			bool canCloseRunningWindow(); 
			bool canTryCloseProcess(); 
		} 
		void run(); 
		void rebuild(); 
		void cancelBuild(); 
		void killCompilers(); 
		void killRunningProcess(); 
		void killRunningConsole(); 
		void closeRunningWindow(); 
		void closeOrKillProcess(); 
	} version(/+$DIDE_REGION Workspace things+/all)
	{
		//A workspace is a collection of opened modules
		
		enum CodeLocationPrefix 	= "CodeLocation:",
		MatchPrefix	= "Match:"; 
		
		enum defaultExt = ".dide"; 
		
		File file; //frmMain uses and maintains this. 
		View2D mainView; //Now it is only mainView, later multiple views must be supported per workspace.
		bool mainIsForeground; //frmMain must update this!!
		IBuildServices buildServices; //this lets access the main form's project builder.
		//there are mainWindow dependencies
		
		File[] openQueue; 
		Module[] modules; 
		Module[uint] moduleByHash; 
		
		@STORED File mainModuleFile; 
		@property
		{
			Module mainModule()
			{ return findModule(mainModuleFile); } void mainModule(Module m)
			{
				enforce(modules.canFind(m), "Invalid module."); 
				enforce(m.isMain, "This module can't be selected as main module."); 
				mainModuleFile = m.file; 
			} 
		} 
		
		ContainerSelectionManager!Module moduleSelectionManager; 
		TextSelectionManager textSelectionManager; 
		
		protected TextSelection[] textSelections_internal; 
		bool mustValidateTextSelections; 
		@property
		{
			auto textSelections()
			{
				validateTextSelectionsIfNeeded; 
				return textSelections_internal; 
			} void textSelections()(TextSelection[] ts)
			{
				textSelections_internal = ts; 
				invalidateTextSelections; 
			} 
		} 
		
		size_t textSelectionsHash; 
		
		string[] extendSelectionStack; 
		
		struct MarkerLayerSettings {
			const DMDMessage.Type type; //this is the identity
			bool visible = true; //this is the settings
			bounds2 btnWorldBounds; //Screen bounds of the button, for particle effect.
		} 
		
		auto markerLayerSettings = [EnumMembers!(DMDMessage.Type)].map!MarkerLayerSettings.array; 
		
		@STORED vec2[size_t] lastModulePositions; 
		
		
		//Restrict convertBuildResultToSearchResults calls.
		size_t lastBuildStateHash; 
		bool buildStateChanged; 
		
		FileDialog fileDialog; 
		
		Nullable!bounds2 scrollInBoundsRequest; 
		
		struct ResyntaxEntry {
			CodeColumn what; 
			DateTime when; 
		} 
		ResyntaxEntry[] resyntaxQueue; 
		
		SyntaxHighlightWorker syntaxHighlightWorker; 
		
		StructureMap structureMap; 
		
		@STORED StructureLevel desiredStructureLevel = StructureLevel.highlighted; 
		
		struct AutoReloader
		{
			@STORED bool enabled; 
			
			size_t idx; 
			
			void update(Module[] modules)
			{
				if(!enabled) return; 
				if(modules.empty) return; 
				
				version(/+$DIDE_REGION advance idx+/all)
				{ idx ++;  if(idx>=modules.length) idx = 0; }
				
				auto m = modules[idx]; 
				if(typeid(m) is typeid(Module) /+Opt: It takes 120us for a file.  It is problematic with the stickers...+/)
				if(!m.changed && m.fileModified < m.file.modified)
				m.reload(m.structureLevel); 
			} 
		} 
		
		@STORED AutoReloader autoReloader; 
		
		this()
		{
			flags.targetSurface = 0; 
			flags.noBackground = true; 
			fileDialog = new FileDialog(mainWindow.hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)"); 
			syntaxHighlightWorker = new SyntaxHighlightWorker; 
			structureMap = new StructureMap; 
			needMeasure; 
		} 
		
		~this()
		{ syntaxHighlightWorker.destroy; } 
		
		override @property bool isReadOnly()
		{
			return false; 
			//Note: it's making me angly if I can't modify while it's compiling.
			//Bug: deleting from a readonly module loses its selections.
		} 
		
		override void rearrange()
		{
			super.rearrange; 
			static if(rearrangeLOG)
			LOG("rearranging", this); 
		} 
		
		@STORED @property
		{
			//Note: toJson: this can't be protected. But an array can (mixin() vs. __traits(member, ...).
			size_t markerLayerHideMask() const
			{
				size_t res; 
				foreach(idx, const layer; markerLayerSettings) if(!layer.visible) res |= 1 << idx; 
				return res; 
			} 
			void markerLayerHideMask(size_t v)
			{ foreach(idx, ref layer; markerLayerSettings) layer.visible = ((1<<idx)&v)==0; } 
		} 
	}version(/+$DIDE_REGION Module handling+/all)
	{
		//! Module handling ///////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			version(/+$DIDE_REGION ModuleSettings+/all)
			{
				protected
				{
					//ModuleSettings is a temporal storage for saving and loading the workspace.
					struct ModuleSettings {
						string fileName; 
						vec2 pos; 
					} 
					@STORED ModuleSettings[] moduleSettings; 
					
					void toModuleSettings()
					{ moduleSettings = modules.map!(m => ModuleSettings(m.file.fullName, m.outerPos)).array; } 
					
					void fromModuleSettings()
					{
						clear; 
						
						foreach(ms; moduleSettings)
						{
							try
							{ loadModule(File(ms.fileName), ms.pos); }
							catch(Exception e)
							{ WARN(e.simpleMsg); }
						}
						
						updateSubCells; 
					} 
					
					void updateSubCells()
					{
						invalidateTextSelections; 
						moduleSelectionManager.validateItemReferences(modules); 
						subCells = cast(Cell[])modules; 
					} 
				} 
			}
			
			
			auto calcBounds()
			{ return modules.fold!((a, b)=> a|b.outerBounds)(bounds2.init); } 
			
			void clear()
			{
				modules = []; 
				moduleByHash.clear; 
				textSelections = []; 
				updateSubCells; 
			} 
			
			void loadWorkspace(string jsonData)
			{
				auto fuck = this; fuck.fromJson(jsonData); 
				fromModuleSettings; 
			} 
			
			string saveWorkspace()
			{
				toModuleSettings; 
				return this.toJson; 
			} 
			
			void loadWorkspace(File f)
			{ loadWorkspace(f.readText(true)); } 
			
			void saveWorkspace(File f)
			{ f.write(saveWorkspace); } 
			
			Module findModule(File file)
			{
				if(auto m = file.fullName.xxh32 in moduleByHash)
				return *m; 
				
				foreach(m; modules)
				if(sameText(m.file.fullName, file.fullName))
				{ WARN("slow find", "\n"~file.fullName, "\n"~m.file.fullName); return m; }
				//Opt: hash table with fileName.lc...
				
				return null; 
			} 
		}version(/+$DIDE_REGION+/all)
		{
			void closeModule(File file)
			{
				//Todo: ask user to save if needed
				if(!file) return; 
				const idx = modules.map!(m => m.file).countUntil(file); 
				if(idx<0) return; 
				
				const h = modules[idx].fileNameHash; 
				if(h in moduleByHash) moduleByHash.remove(h); 
				
				modules = modules.remove(idx); 
				updateSubCells; 
			} 
			
			auto selectedModules()
			{ return modules.filter!(m => m.flags.selected).array; } 
			auto unselectedModules()
			{ return modules.filter!(m => !m.flags.selected).array; } 
			auto hoveredModule()
			{ return moduleSelectionManager.hoveredItem; } 
			auto modulesWithTextSelection()
			{ return textSelections.map!(s => s.moduleOf).nonNulls.uniq; } 
			
			auto primaryTextSelection()
			{
				{
					auto a = textSelections.filter!"a.primary"; 
					if(!a.empty) return a.front; 
				}
				
				{
					auto a = textSelections; //choose the first if none is marked with the primary flag.
					if(!a.empty) return a.front; 
				}
				
				return TextSelection.init; 
			} 
			
			auto primaryCaret()
			{ return primaryTextSelection.caret; } 
			
			auto moduleWithPrimaryTextSelection()
			{
				auto res = textSelections.filter!"a.primary".map!moduleOf.frontOrNull; 
				if(!res) res = textSelections.map!moduleOf.frontOrNull; //if there is no Primary, pick the front one
				return res; 
			} 
			
			alias primaryModule = moduleWithPrimaryTextSelection; 
			
			Module oneSelectedModule()
			{
				if(selectedModules.take(2).walkLength==1)
				return selectedModules.front; 
				return null; 
			} 
			
			Module singleSelectedModule()
			{ return oneSelectedModule.ifz(primaryModule); } 
			
			Module expectOneSelectedModule()
			{
				auto m = oneSelectedModule; 
				if(!m)
				im.flashWarning("This operation requires a single selected module."); 
				//Todo: put the operation's name in the message.
				
				return m; 
			} 
			
			Module[] selectedModulesOrAll()
			{
				auto res = selectedModules.array; 
				if(res.empty) res = modules; 
				return res; 
			} 
			
			/+
				+Selects all the CodeColumns under the cursors. 
				If there is none, selects all the modules' content CodeColumns.
			+/
			CodeColumn[] selectedOuterColumns()
			{
				CodeColumn[] cols; 
				
				foreach(c; textSelections.map!"a.codeColumn")
				if(!cols.canFind(c)) cols ~= c; 
				if(cols.empty)
				foreach(c; selectedModules.map!"a.content")
				cols ~= c; 
				
				return cols; 
			} 
			
			auto selectedStickers()
			{ return selectedModules.map!(m => cast(ScrumSticker) m).filter!"a"; } 
			
			auto changedModules()
			{ modules.filter!"a.changed"; } 
			auto projectModules()
			{ return mainModule ? allFilesFromModule(mainModule.file).map!(f => findModule(f)).nonNulls.array : []; } 
			auto changedProjectModules()
			{ return projectModules.filter!"a.changed"; } 
			void saveChangedProjectModules()
			{ changedProjectModules.each!"a.save"; } 
			
			
			private void closeSelectedModules_impl()
			{
				//Todo: ask user to save if needed
				modules = unselectedModules; 
				moduleByHash = assocArray(modules.map!"a.fileNameHash".array, modules); 
				updateSubCells; 
				invalidateTextSelections; 
			} 
			
			private void closeAllModules_impl()
			{
				//Todo: ask user to save if needed
				clear; 
				invalidateTextSelections; 
			} 
			
			private void bringToFrontSelectedModules()
			{
				//Not: Do not raise alwaysOnBottom modules to the top.
				static isSel(Module m)
				{ return m.flags.selected && !m.alwaysOnBottom; } 
				
				modules = chain(
					modules.filter!(m=>!isSel(m)), 
					modules.filter!isSel
				).array; 
				updateSubCells; 
			} 
			
			bool loadModule(in File file)
			{
				const vec2 targetPos = lastModulePositions.get(file.actualFile.hashOf, vec2(calcBounds.right+24, 0)); 
				return loadModule(file, targetPos); //default position
			} 
			
			bool loadModule(in File file, vec2 targetPos)
			{
				if(!file.exists) return false; 
				if(auto m = findModule(file))
				{
					m.fileLoaded = now; //it's just a flash indicator
					mainView.smartScrollTo(m.outerBounds); 
					return false; //no loading was issued
				}
				
				Module m; 
				if(file.extIs("scrum"))	m = new ScrumTable(this, file, desiredStructureLevel); 
				else if(file.extIs("sticker"))	m = new ScrumSticker(this, file, desiredStructureLevel); 
				else	m = new Module(this, file, desiredStructureLevel); 
				
				//m.flags.targetSurface = 0; not needed, workspace is on s0 already
				m.measure; 
				m.outerPos = targetPos; 
				modules ~= m; 
				moduleByHash[m.fileNameHash] = m; 
				updateSubCells; 
				
				/+
					justLoadedSomething |= true;
					justLoadedBounds |= m.outerBounds; 
				+/
				
				mainView.smartScrollTo(m.outerBounds); 
				
				return true; 
			} 
			
			File[] allFilesFromModule(File file)
			{
				if(!file.exists) return []; 
				//Todo: not just for //@exe of //@dll
				BuildSettings settings = {verbose : false}; 
				BuildSystem buildSystem; 
				return buildSystem.findDependencies(file, settings).map!(m => m.file).array; 
			} 
			
			auto loadModuleRecursive(File file)
			{ allFilesFromModule(file).each!(f => loadModule(f)); } 
			
			void queueModule(File f)
			{
				/+
					Todo: this workaround is there to let the filedialog handle 
					virtual files like: virtual:\clipboard.txt.  This should be put inside openDialog class.
				+/
				if(f.fullName.isWild(`*\?*:*`)) f.fullName = wild[1].split('\\').back~':'~wild[2]; 
				openQueue ~= f; 
			} 
			void queueModuleRecursive(File f)
			{ if(f.exists) openQueue ~= allFilesFromModule(f); } 
			
			void updateOpenQueue(int maxWork)
			{
				while(openQueue.length)
				{
					auto f = openQueue.fetchFront; 
					if(loadModule(f))
					{
						maxWork--; 
						if(maxWork<=0) return; 
					}
				}
			} 
			
			void updateModuleBuildStates(in BuildResult buildResult)
			{
				foreach(m; modules)
				{ m.buildState = buildResult.getBuildStateOfFile(m.file); }
			} 
			
			void updateLastKnownModulePositions()
			{
				foreach(m; modules)
				lastModulePositions[m.file.hashOf] = m.outerPos; 
			} 
			
		}
	}version(/+$DIDE_REGION+/all)
	{
		
		struct LineIdxLocator
		{
			int lineIdx; 
			Object reference; 
			bool optimized = true; 
			
			Container.SearchResult[] searchResults; 
			Container.SearchResult[] searchResults_nodes;  //Fallback to nodes when there is no glyps on line
			
			void visitNode(CodeNode node)
			{
				foreach(col; node.subCells.map!((a)=>((cast(CodeColumn)(a)))).filter!"a")
				visitColumn(col); 
			} 
			
			void visitColumn(CodeColumn col)
			{
				if(col.containsBuildMessages) return; 
				
				auto rows = col.rows; 
				
				//ignore trailing empty rows
				while(rows.length && !rows.back.lineIdx)
				rows.popBack; 
				
				//Todo: must do something with the fucking lineIdx==0 rows at the end...
				
				if(optimized)
				{
					//ignore all rows higher than lineIdx
					rows = rows[0 .. rows.map!"a.lineIdx".assumeSorted.lowerBound(lineIdx+1).length]; 
					
					//process same lines
					while(rows.length && rows.back.lineIdx==lineIdx)
					{
						visitRow(rows.back); 
						rows.popBack; 
					}
					
					//process one more row which can contain lineIdx, but starts earlier
					if(rows.length) visitRow(rows.back); 
				}
				else
				{
					static if((常!(bool)(0))/+Note: verify sort order+/)
					if(!rows.map!"a.lineIdx".isSorted)
					ERR("LineIdx is NOT sorted: ", rows.map!"a.lineIdx"); 
					
					mixin(求each(q{r},q{rows},q{visitRow(r)})); 
				}
			} 
			
			void visitRow(CodeRow row)
			{
				void collectCells(T, R)(ref R res)
				{
					auto cells = row.subCells.filter!((cell){
						if(auto a = (cast(T)(cell)))
						return a.lineIdx == lineIdx; 
						else return false; 
					}).array; 
					/+Opt: binary search+/
					if(cells.length)
					{
						res ~= (
							mixin(體!((Container.SearchResult),q{
								cells 	: cells,
								container	: row,
								absInnerPos	: row.worldInnerPos,
								reference	: reference
							}))
						); 
						//Opt: appender
					}
				} 
				
				collectCells!Glyph(searchResults); 
				if(searchResults.empty) collectCells!CodeNode(searchResults_nodes); 
				
				row.byNode.each!((n){ visitNode(n); }); /+Opt: early exit+/
			} 
		} 
		
		Container.SearchResult[] codeLocationToSearchResults(CodeLocation loc, bool optimized = true)
		{
			//Opt: unoptimal to return a dynamic array
			
			if(!loc) return []; 
			
			if(auto mod = findModule(loc.file))
			{
				Container.SearchResult[] doit()
				{
					//Opt: bottleneck! linear search
					//Todo: return the whole module if the line is unspecified, or unable to find
					
					if(!loc.lineIdx)
					{
						//Todo: mark the whole module
						return []; 
					}
					
					auto locator = LineIdxLocator(loc.lineIdx, null); 
					locator.optimized = optimized; 
					locator.visitNode(mod); 
					
					auto res = ((locator.searchResults.length) ?(locator.searchResults) :(
						locator.searchResults_nodes /+
							Note: When no glyphs at all, fallback to nodes.
							This founds multiline messages.
						+/
					)); 
					
					static if((常!(bool)(0))/+Note: Do unotpimized search for debug.+/)
					if(res.empty)
					{
						if(optimized)
						{
							WARN("Optimized LineIdxLocator failed:", loc); 
							return codeLocationToSearchResults(loc, reference, false); 
						}
						else
						{ ERR("Standard LineLocator failed:", loc); }
					}
					
					if(res.length>1) mixin(求each(q{ref a},q{res[1..$]},q{a.showArrow = false})); 
					
					return res; 
				} 
				
				if(auto a = loc in mod.searchResultsByCodeLocation) return *a; 
				else return mod.searchResultsByCodeLocation[loc] = doit; 
			}
			else
			{
				//module not loaded
				//LOG(msg);
				//if(msg.location.file.exists) queueModule(msg.location.file);
				return []; 
			}
		} 
		
		
		auto nodeToSearchResult(CodeNode node, Object reference)
		{
			return (
				mixin(體!((Container.SearchResult),q{
					cells 	: [node],
					container	: node.parent,
					absInnerPos	: node.parent.worldInnerPos,
					reference	: reference
				}))
			); 
		} 
		
		CodeRow[string] messageUICache; 
		string[string] messageSourceTextByLocation; 
		
		static struct MessageConnectionArrow
		{
			vec2 p1, p2; 
			DMDMessage.Type type; 
			bool isException; //a side-information for type
		} 
		bool[MessageConnectionArrow] messageConnectionArrows; 
		
		void buildMessageConnectionArrows(DMDMessage rootMessage)
		{
			void visit(DMDMessage[] path)
			{
				if(path.back.subMessages.length)
				{
					foreach(sm; path.back.subMessages)
					visit(path ~ sm); 
				}
				else
				{
					auto conv(DMDMessage msg)
					{
						auto sr = codeLocationToSearchResults(msg.location); 
						if(sr.empty) return vec2(0); 
						return 	/+sum(sr.map!(s => s.bounds.center))/sr.length+/
							sr.front.bounds.leftCenter + vec2(-6, 0); ; 
					} 
					
					auto segments = path.map!((a)=>(conv(a))).filter!"a".cache.uniq.array.slide!(No.withPartial)(2); 
					foreach(a; segments)
					{
						auto mca = MessageConnectionArrow(a[1], a[0], rootMessage.type, rootMessage.isException); 
						messageConnectionArrows[mca] = true; 
					}
				}
			} 
			visit([rootMessage]); 
		} 
		
		
		void processBuildMessages(DMDMessage[] messages)
		{ mixin(求each(q{m},q{messages},q{processBuildMessage(m)})); } 
		
		static CodeNode renderBuildMessage(DMDMessage msg)
		{
			/+
				Todo: An option to not render all codeLocations.
				- When the next line's location is same as the precceding line's.
				- When the message is at it's designated location.
			+/
			
			auto 	msgCol	= new CodeColumn(null, msg.sourceText, TextFormat.managed_block),
				msgRow	= msgCol.rows.frontOrNull.enforce("Can't get builMessageRow."),
				msgNode 	= (cast(CodeNode)(msgRow.subCells.frontOrNull)).enforce("Can't get buildMessageNode."); 
			msgNode.buildMessageHash = msg.hash; 
			msgNode.measure; /+
				It's required to initialize bkColor. 
				For example: Animation effect needs to know the color.
			+/
			return msgNode; 
		} 
		
		Module.Message[] incomingVisibleModuleMessageQueue; 
		bool firstErrorMessageArrived; 
		
		void processBuildMessage(DMDMessage msg)
		{
			if(!mainModule) return; 
			
			static bool disable = false; 
			
			try
			{
				auto 	msgNode 	= renderBuildMessage(msg),
					layer 	= &markerLayerSettings[msg.type]; 
				
				
				Container.SearchResult[] searchResults; 
				
				CodeNode getContainerNode(lazy CodeNode fallbackNode=null)
				{
					searchResults = codeLocationToSearchResults(msg.location); 
					
					if(
						/+Note: Special case: There's only one node is in the searchresults.+/
						searchResults.length==1 && searchResults[0].cells.length==1
					)
					if(auto n = (cast(CodeNode)(searchResults[0].cells[0])))
					if(n.canAcceptBuildMessages)
					{ return n; }
					
					
					CodeNode[] getNodePath(Container.SearchResult sr)
					{
						return sr.container.thisAndAllParents	.map!((a)=>((cast(CodeNode)(a))))
							.filter!((a)=>(a && a.canAcceptBuildMessages))
							.array.retro.array; 
					} 
					auto paths = searchResults.map!((a)=>(getNodePath(a))); 
					if(!paths.empty) return paths.fold!commonPrefix.backOrNull; 
					return fallbackNode; 
				} 
				
				auto containerModule = findModule(msg.location.file).ifNull(mainModule); 
				if(auto containerNode = getContainerNode(containerModule))
				{
					void addMessageToModule(bool isNew)
					{
						auto mm = containerModule.addModuleMessage(isNew, msg, msgNode, searchResults); 
						
						if(layer.visible && isNew) incomingVisibleModuleMessageQueue ~= mm; 
					} 
					
					if(msg.isPersistent && !(cast(Module)(containerNode)))
					{
						//persistent message at it's designated place. -> no need to insert anywhere.
						
						CodeComment locateActualComment()
						{
							//find the actual comment in searchResults
							bool isMatchingComment(CodeComment cmt)
							{
								return cmt && (cmt.customPrefix==msg.type.text.capitalize~':') && 
									equal(
									cmt.content.rows[0].chars!'`'	.until!((ch)=>(!ch.among('`'))),
									msg.content	.until!((ch)=>(!ch.among('`', '\r', '\n')))
								); 
								/+It's not perfect, it only checks the first line before any `code` references.+/
							} 
							
							foreach(sr; searchResults)
							if(auto row = (cast(CodeRow)(sr.container)) /+multiline messages can be found in rows+/)
							{
								
								//single line comments
								if(auto col = row.parent)
								if(auto cmt = (cast(CodeComment)(col.parent)))
								if(isMatchingComment(cmt))
								{ return cmt; }
								
								/+multiline comments+/
								if(sr.cells.length==1)
								if(auto cmt = (cast(CodeComment)(sr.cells[0])))
								if(isMatchingComment(cmt))
								{ return cmt; }
								
								//problematic: The message is at the very end of a line. It tries to escape 2 times.
								/+
									Todo: This is a bug in the LineIdxLocator. It should be fixed there.
									The LineIdxLocator only finds other cells on the line, but not the comment itself.
									If it's fixet there, this workaround is not needed anymore.
								+/
								foreach(r; row.allParents!CodeRow.take(2))
								foreach(cmt; r.subCells.map!((c)=>((cast(CodeComment)(c)))))
								if(isMatchingComment(cmt))
								return cmt; 
							}
							
							WARN("Can't find buildMessage in code:\n"~msg.text~"\n"~searchResults.text); 
							return null; 
						} 
						
						if(auto cmt = locateActualComment)
						{
							//only a single searchResult remains, and with the actual persistent message
							msgNode = cmt; 
							searchResults = [nodeToSearchResult(cmt, null)]; 
						}
						
						addMessageToModule(true); 
						//Todo: firework effect
					}
					else
					{
						//This buildMessage is injected at the bottom of a node.
						const isNewMessage = containerNode.addBuildMessage(msgNode); 
						searchResults = searchResults ~ nodeToSearchResult(msgNode, null); 
						addMessageToModule(isNewMessage); 
					}
				}
				else
				raise(i"Failed to find module  $(msg.location.file), also no MainModule.".text); 
				
			}
			catch(Exception e) { ERR(e.text~"\n"~msg.text); }
		} 
		
		auto getMarkerLayerCount(DMDMessage.Type type)
		{ return (mixin(求sum(q{mod},q{modules},q{((type==DMDMessage.Type.find)?(mod.findSearchResults.length) :(mod.messagesByType[type].length))}))); } 
		
		auto getMarkerLayer_find()
		{ return modules.map!((m)=>(m.findSearchResults)).joiner; } 
		
		auto getMarkerLayer(DMDMessage.Type type)
		{
			enforce(type!=DMDMessage.Type.find); 
			return modules.map!((m)=>(m.messagesByType[type].map!((msg)=>(msg.searchResults)).joiner)).joiner; 
		} 
		
		auto clearMarkerLayer_find()
		{ foreach(m; modules) m.findSearchResults = []; } 
		
		
		
		
		
		//Todo: since all the code containers have parents, location() is not needed anymore
		
		override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0))
		{
			ofs += innerPos; 
			foreach_reverse(m; modules) {
				auto st = m.locate(mouse, ofs); 
				if(st.length) return st; 
			}
			return []; 
		} 
		
		CellLocation[] locate_snapToRow(vec2 mouse, float epsilon = .5f)
		{
			auto st = locate(mouse); 
			
			auto getLastCol() { return cast(CodeColumn) st.map!"a.cell".backOrNull; } 
			
			//try snap it from the edge
			if(auto col = getLastCol)
			{
				const ofs = st.back.calcSnapOffsetFromPadding(epsilon); 
				if(ofs)
				{ mouse += ofs;  st = locate(mouse); }
			}
			
			//try to avoid the gaps if it is a multiPage Column
			if(auto col = getLastCol)
			{
				auto pages = col.getPageRowRanges; 
				if(pages.length>1)
				{
					const p = st.back.localPos; 
					auto xStarts = pages.map!(p => p.front.outerLeft).assumeSorted; 
					size_t idx = (xStarts.length - xStarts.upperBound(p.x).length - 1); 
					if(idx<pages.length-1)
					{
						const 	xLeft	= pages[idx].front.outerRight - epsilon,
							xRight 	= pages[idx+1].front.outerLeft + epsilon,
							xMid	= avg(xLeft, xRight); 
						
						if(p.x.inRange(xLeft, xRight))
						{
							mouse += (p.x<xMid ? xLeft : xRight) - p.x; 
							st = locate(mouse); 
						}
					}
				}
			}
			
			//try to snap up from the bottom of a page
			if(auto col = getLastCol)
			{
				auto pages = col.getPageRowRanges; 
				if(pages.length>1)
				{
					const p = st.back.localPos; 
					auto xStarts = pages.map!(p => p.front.outerLeft).assumeSorted; 
					size_t idx = (xStarts.length - xStarts.upperBound(p.x).length - 1); 
					//Todo: too much copy paste. Must refactor these ifs.
					
					if(idx<pages.length/+it needs only one page, not two+/)
					{
						const limit = pages[idx].back.outerBottom - epsilon; 
						
						if(p.y > limit)
						{
							mouse.y += limit - p.y; 
							st = locate(mouse); 
						}
					}
				}
			}
			
			
			return st; 
		} 
		
		CodeLocation cellLocationToCodeLocation(CellLocation[] st)
		{
			CodeLocation res; 
			
			//Todo: it's only detects the lineIdx
			while(st.length) {
				void setLineIdx(int i) { if(!res.lineIdx) res.lineIdx = i; } 
				auto cell = st.back.cell; 
				
				if(auto glyph = cast(Glyph)cell)
				setLineIdx(glyph.lineIdx); 
				else if(auto node = cast(CodeNode)cell)
				setLineIdx(node.lineIdx); 
				else if(auto row = cast(CodeRow)cell)
				{
					setLineIdx(row.lineIdx); 
					/+
						Todo: this should be row.findLineIdx_max,
						because the mouse is at the end of the row
					+/
					
					if(auto mod = moduleOf(row))
					res.file = mod.file; 
					break; 
				}
				//Todo: Tabs would look better in this if chain.
				
				st.popBack; 
			}
			
			return res; 
		} 
		
		CellLocation[] cursorToCellLocations(TextCursor cr)
		{
			//Note: it does not return local/global positions, just the cell chain.
			if(auto row = rowAt(cr))
			{
				auto res = row.thisAndAllParents.array.retro.map!((a)=>(CellLocation(a))).array; 
				if(cr.isAtLineEnd) cr.pos.x--; 
				if(auto cell = cellAt(cr)) res ~= CellLocation(cell); 
				return res; 
			}
			return []; 
		} 
		
		CodeLocation cursorToCodeLocation(TextCursor cr)
		{ return cellLocationToCodeLocation(cursorToCellLocations(cr)); } 
		
		static CellLocation[] findLastCodeRow(CellLocation[] st)
		{
			foreach_reverse(i; 0..st.length) {
				//Todo: functinal
				auto row = cast(CodeRow)st[i].cell; 
				if(row) return st[i..$]; 
			}
			return []; 
		} 
		
		TextCursor cellLocationToTextCursor(CellLocation[] st)
		{
			TextCursor res; 
			st = findLastCodeRow(st); 
			if(auto row = cast(CodeRow)st.get(0).cell)
			{
				auto cell = st.get(1).cell; 
				
				//try to find cell with smaller height than the row, vertically at x,
				//   if the mouse is not exactly inside the cell. Also snap from the sides.
				if(!cell) {
					cell = row.subCellAtX(st[0].localPos.x, Yes.snapToNearest); 
					if(cell) {
						st  ~= CellLocation(cell, st[0].localPos-cell.innerPos); 
						//pass in localPos inside the cell
					}
				}
				
				res.codeColumn = row.parent; 
				
				res.desiredX = st[0].localPos.x; 
				res.pos.y = row.index; 
				
				//find x character index
				int x; 
				if(cell)
				{
					x = row.subCellIndex(cell); 
					assert(x>=0); 
					if(st[1].localPos.x>cell.innerWidth/2) x++; 
				}
				else
				{ x = res.desiredX<0 ? 0 : row.cellCount; }
				assert(x.inRange(0, row.cellCount)); 
				res.pos.x = x; 
			}
			
			return validate(res); 
		} 
		
		string wordAt(CellLocation[] st, bool canStepLeft = false/+can see one cell to the left+/, bounds2* globalBounds, TextSelection* ts)
		{
			if(globalBounds) *globalBounds = bounds2.init; 
			if(ts) *ts = TextSelection.init; //Todo: refactor these wordat() results to a struct
			
			static isWordGlyph(Cell c)
			{
				if(auto g = (cast(Glyph)(c))) return g.ch.isDLangIdentifierCont /+|| g.ch=='.'+/; 
				return false; 
			} 
			if(st.length>=2)
			if(auto row = (cast(CodeRow)(st[$-2].cell)))
			{
				auto idx = row.subCells.countUntil(st.back.cell); 
				
				//optionally it can step back a cell
				if(canStepLeft && !isWordGlyph(row.subCells[idx]) && idx>0) idx--; 
				
				if(idx>=0 && isWordGlyph(row.subCells[idx]))
				{
					auto fw() => row.subCells[idx..$].until!(not!isWordGlyph); 
					auto bk() => row.subCells[0..idx].retro.until!(not!isWordGlyph); 
					bounds2 bnd; 
					auto res = chain(bk.array.retro, fw)	.map	!((n)=>((cast(Glyph)(n))))
						.tee	!((g){ bnd |= g.outerBounds; })
						.map	!((g)=>(g.ch)).text; 
					bnd += row.worldInnerPos; 
					
					if(globalBounds) *globalBounds = bnd; 
					if(ts)
					{
						const fwCnt = (cast(int)(fw.walkLength)); 
						const bkCnt = (cast(int)(bk.walkLength)); 
						const rowIdx = row.index; 
						*ts = TextSelection(
							TextCursor(row.parent, ivec2(idx-bkCnt, rowIdx)),
							TextCursor(row.parent, ivec2(idx+fwCnt, rowIdx)), false
						); 
					}
					
					return res; 
				}
			}
			return ""; 
		} 
	}version(/+$DIDE_REGION Cursor/Selection stuff+/all)
	{
		TextCursor createCursorAt(vec2 p)
		{ return cellLocationToTextCursor(locate_snapToRow(p)); } 
		
		//textSelection, cursor movements /////////////////////////////
		
		int lineSize()
		{ return DefaultFontHeight; } 
		int pageSize()
		{ return (mainView.subScreenBounds_anim.height/lineSize*.9f).iround.clamp(2, 100); } 
		
		void cursorOp(ivec2 dir, bool select, bool stepInOut=false)
		{
			const stepOut = stepInOut; 
			const stepIn = stepInOut; 
			
			auto arr = textSelections; 
			
			void dump(string title)
			{
				static if(0)
				if(arr.length)
				{
					LOG(title, arr[0], arr[0].valid, arr[0].toReference.valid); 
					TextCursorReference res; 
					with(arr[0].cursors[0])
					if(valid)
					{
						auto row = codeColumn.getRow(pos.y); 
						LOG("ROW", row); 
						if(row)
						{
							LOG("parents", row.thisAndAllParents.array.retro.array); 
							res.path = CellPath(row); 
							res.left	= row.subCells.get(pos.x-1); 
							res.right	= row.subCells.get(pos.x); 
						}
					}
					LOG("refCursor",res.path, res.left, res.right); 
				}
			} 
			
			dump("BEFORE"); 
			
			foreach(ref ts; arr)
			if(!stepInOut)
			{ ts.move(dir, select); }
			else
			{
				const fwd = dir.x>0 || dir.y>0; 
				
				auto prev = ts; 
				
				scope(exit)
				{
					//Adjust the local positions when the codeColumn changes.
					version(AnimatedCursors)
					if(prev.valid && ts.valid && prev.codeColumn != ts.codeColumn)
					{
						const delta = prev.codeColumn.worldInnerPos - ts.codeColumn.worldInnerPos; 
						
						foreach(ref c; ts.cursors[])
						{
							if(!c.animatedPos.x.isnan) c.animatedPos += delta; 
							if(!c.targetPos.x.isnan) c.targetPos += delta; 
						}
					}
				}
				
				ts.move(dir, select); 
				
				//step into the first node that has any subColumns
				if(stepIn && !select && prev!=ts && prev.valid && prev.isZeroLength)
				{
					auto nodes = TextSelection(prev.cursors[0], ts.cursors[0], prev.primary).cells!CodeNode; 
					if(
						auto nearestNode = fwd 	? nodes.frontOrNull
							: nodes.backOrNull
					)
					if(
						auto subCol = fwd 	? nearestNode.firstSubColumn 
							: nearestNode.lastSubColumn
					)
					{
						//Todo: It will miss nodes that has no subColumns
						ts.cursors[] = fwd ? subCol.homeCursor : subCol.endCursor; 
						continue; 
					}
				}
				
				//step out because the it reached the end (was unable to move)
				if(ts.valid && prev==ts)
				{
					//step into the next codeColumn inside a codeNode
					if(stepIn && ts.valid && !select)
					if(auto node = cast(CodeNode) ts.codeColumn.getParent)
					if(
						auto nextCol = fwd 	? node.columnAfter(ts.codeColumn)
							: node.columnBefore(ts.codeColumn)
					)
					{
						if(fwd)	ts.cursors[] = nextCol.homeCursor; 
						else	ts.cursors[] = nextCol.endCursor; 
						continue; 
					}
					
					//step out
					auto ext = extendOut(ts); 
					if(ext.valid)
					{
						ts = ext; 
						if(select)
						{/+if(!fwd) swap(ts.cursors[0], ts.cursors[1]); +/}
						else
						{
							if(fwd)	ts.cursors[0] = ts.cursors[1]; 
							else	ts.cursors[1] = ts.cursors[0]; 
						}
					}
				}
			}
			
			dump("AFTER"); 
			
			textSelections = merge(arr); //Todo: maybe merge should reside in validateTextSelections
		} 
		
		version(/+$DIDE_REGION Scrolling+/all)
		{
			void scrollV(float dy)
			{ mainView.scrollV(dy); } 
			void scrollH(float dx)
			{ mainView.scrollH(dx); } 
			void zoom(float log)
			{ mainView.zoom(log); } //Todo: Only zoom when window is foreground
				
			float scrollSpeed()
			=> application.deltaTime.value(second)*2000; 
			float zoomSpeed()
			=> application.deltaTime.value(second)*8; 
			float wheelSpeed = 0.375f; 
				
			void insertCursor(int dir)
			{
				auto 	prev = textSelections,
					next = prev.dup; 
				
				foreach(ref ts; next)
				foreach(
					ref tc; ts.cursors
					/+
						Note: It is important to move the cursors separately here.
						Don't let TextSelection.move do cursor collapsing.
					+/
				)
				tc.move(ivec2(0, dir)); 
				
				textSelections = merge(prev ~ next); 
			} 
			
			void scrollInModules(Module[] m)
			{ if(m.length) scrollInBoundsRequest = m.map!"a.outerBounds".fold!"a|b"; } 
			
			void scrollInAllModules()
			{ scrollInModules(modules); } 
			
			void scrollInModule(Module m)
			{ if(m) scrollInModules([m]); } 
		}
		
		
		version(/+$DIDE_REGION Validate+/all)
		{
			void invalidateTextSelections()
			{
				mustValidateTextSelections = true; 
				textSelectionManager.invalidateInternalSelections; 
			} 
			
			void validateTextSelectionsIfNeeded()
			{
				if(mustValidateTextSelections.chkClear)
				{ textSelections_internal = validate(textSelections_internal); }
			} 
			
			auto validate(TextCursor c)
			{ return validate(TextSelection(c, c, false)).cursors[0]; } 
			
			auto validate(TextSelection s)
			{
				auto ts = validate([s]); 
				return ts.empty ? TextSelection.init : ts[0]; 
			} 
			
			auto validate(TextSelection[] arr)
			{
				Cell cachedExistingModule; 
				
				bool isExistingModule(Cell c)
				{
					if(c is cachedExistingModule) return true; 
					//Opt: this is helping nothing compared to
					
					if(auto m = cast(Module)c)
					if(modules.canFind(m))
					{
						cachedExistingModule = c; 
						return true; 
					}
					return false; 
				} 
				
				bool validate(TextSelection sel)
				{
					if(!sel.valid) return false; 
					auto r = sel.toReference; 
					if(!r.valid) return false; 
					
					auto p = r.cursors[0].path; 
					if(p[0] !is this) return false; 	//not this workspace
					if(!isExistingModule(p[1])) return false; 	//module died
					
					//Todo: check if selection is inside row boundaries.
					return true; 
				} 
				
				auto res = arr.filter!((a)=>(validate(a))).array; 
				return res; 
				//Todo: try to fix partially broken selections
			} 
		}
		
		void preserveTextSelections(void delegate() fun)
		{
			//Todo: preserve module selections too
			const savedTextSelections = textSelections.map!(a => a.toReference.text).array; 
			scope(exit)
			{ textSelections = savedTextSelections.map!(a => TextSelection(a, &findModule)).array; }
			if(fun) fun(); 
		} 
		
		auto insertCursorAtEachLineSelected_impl(R)(R textSelections, Flag!"toTheEnd" toTheEnd = Yes.toTheEnd)
		{
			auto res = 	textSelections
				.filter!"a.valid"  //just to make sure
				.map!(
				//create cursors in every lines at the start of the line
				sel => 	iota(sel.start.pos.y, sel.end.pos.y+1)
					.map!((y)=>(TextCursor(sel.codeColumn, ivec2(0, y))))
			)
				.joiner
				.map!((c){
				//move the cursor to the end or home of the line
				if(toTheEnd) c.moveToLineEnd; 
				else c.moveToLineStart; //Todo: it's not functional yet
				return TextSelection(c, c, false); //make a selection out of them
			})
				.merge /+merge it, because there can be duplicates+/; 
			
			if(res.length) res[0].primary = true; //Todo: primary selection is inconsistent when multiselect
			
			return res; 
		} 
		
		auto insertCursorAtStartOfEachLineSelected_impl(R)(R textSelections)
		{ return insertCursorAtEachLineSelected_impl(textSelections, No.toTheEnd); } 
		
		auto insertCursorAtEndOfEachLineSelected_impl(R)(R textSelections)
		{ return insertCursorAtEachLineSelected_impl(textSelections, Yes.toTheEnd); } 
		
		auto selectCharAtEachSelection(R)(R textSelections, dchar ch)
		{
			TextSelection transform(TextSelection sel)
			{
				TextSelection res; 
				if(sel.cursors[0].charAt == ch)
				{
					res = sel.dup; 
					res.cursors[1] = res.cursors[0]; 
					res.cursors[1].moveRight(1); 
				}
				return res; 
			} 
			
			return 	textSelections
				.map!(a => transform(a))
				.cache
				.filter!"a.valid"
				.merge; 
		} 
		
		TextSelection searchResultToTextSelection(SearchResult sr)
		{
			if(sr.cells.length)
			if(auto row = cast(CodeRow)sr.container)
			if(auto col = row.parent)
			{
				auto 	rowIdx = row.index,
					//Todo: could find other cells as well.
					//If the user edits the document for example.
					st = row.subCellIndex(sr.cells.front),
					en = row.subCellIndex(sr.cells.back); 
				if(rowIdx>=0 && st>=0 && en>=0)
				{
					auto ts = TextSelection
					(
						TextCursor(col, ivec2(st, rowIdx)), 
						TextCursor(col, ivec2(en+1, rowIdx)),
						false
					); 
					return validate(ts); 
				}
			}
			
			return TextSelection.init; 
		} 
		
		void selectSearchResults(R)(R arr)
		if(isInputRange!(R, Container.SearchResult))
		{
			//selectSearchResults ///////////////////////////
			//Todo: use this as a revalidator after the modules were changed under the search results.
			//Maybe verify the search results while drawing. Cache the last change or something.
			
			//T0; scope(exit) DT.LOG;
			
			//Todo: restrict to the current selection!
			
			//Todo: dont select text inside error messages!
			textSelections = merge(arr.map!((a)=>(searchResultToTextSelection(a))).filter!"a.valid".array); 
		} 
		
		void cancelSelection_impl()
		{
			//cancelSelection_impl //////////////////////////////////////
			auto ts = textSelections; 
			auto mp = moduleWithPrimaryTextSelection; 
			
			void selectPrimaryModule()
			{
				textSelections = []; 
				foreach(m; modules) m.flags.selected = m is mp; 
				scrollInModule(mp); 
			} 
			
			//multiTextSelect -> primaryTextSelect
			if(ts.length>1)
			{
				if(auto pts = primaryTextSelection)
				{ textSelections = [pts]; return; }
			}
			
			void deselectAllModules() {
				modules.each!(m => m.flags.selected = false); 
				/+Todo: It is declared in workspace+/
			} 
			
			if(ts.length>0)
			{ textSelections = []; deselectAllModules; return; }
			
			//as a final act, zoom all
			deselectAllModules; scrollInAllModules; 
		} 
		
		auto extend(TextSelection sel)
		{
			if(sel.valid)
			{
				const fwd = sel.cursors[0]<=sel.cursors[1]; 
				
				auto home = sel.start; home.move(TextCursor.home.ivec2); 
				auto end = sel.end; end.move(TextCursor.end.ivec2); 
				
				if(home!=sel.start || end!=sel.end)
				{
					sel.cursors[0] = home; 
					sel.cursors[1] = end; 
				}
				else
				{
					auto parents = sel.codeColumn.allParents.take(3).array; 
					if(parents.length==3)
					if(auto parentNode = cast(CodeNode) parents[0])
					if(auto parentRow = cast(CodeRow) parents[1])
					if(auto parentCol = cast(CodeColumn) parents[2])
					{
						const 	x = parentRow.subCellIndex(parentNode),
							y = parentCol.subCellIndex(parentRow); 
						if(x>=0 && y>=0)
						{
							void set(C)(ref C c, int x)
							{
								c.codeColumn = parentCol; 
								c.pos = ivec2(x, y); 
								c.calcDesiredX_unsafe; 
							} 
							set(sel.cursors[0], x); 
							set(sel.cursors[1], x+1); 
						}
					}
				}
				
				//preserve selection direction
				if(fwd != (sel.cursors[0]<=sel.cursors[1]))
				swap(sel.cursors[0], sel.cursors[1]); 
			}
			return sel; 
		} 
		
		protected auto _extendTwice(bool eq)(TextSelection ts)
		{
			auto ext = extend(ts); 
			if(ext.valid && (ext.codeColumn==ts.codeColumn)==eq)
			ext = extend(ext); 
			return ext; 
		} 
		
		///steps out from the current codeColumn
		auto extendOut(TextSelection ts)
		{
			if(!ts.valid || ts.codeColumn.allParents!CodeColumn.empty) return ts; 
			return _extendTwice!true(ts); 
		} 
		
		///extends selection to the an codeColumn
		auto extendAll(TextSelection ts)
		{
			if(!ts.valid) return ts; 
			return _extendTwice!false(ts); 
		} 
		
		auto extend(TextSelection[] sels)
		{ return sels.map!(ts=>extend(ts)).merge; } 
		auto extendOut(TextSelection[] sels)
		{ return sels.map!(ts=>extendOut(ts)).merge; } 
		auto extendAll(TextSelection[] sels)
		{ return sels.map!(ts=>extendAll(ts)).merge; } 
		
		
		
		
		string exportTextSelections(TextSelection[] ts)
		{ return ts.map!(a=>a.toReference.text).join(';'); } 
		
		TextSelection[] importTextSelections(string s)
		{ return s.splitter(';').map!(s=>s.TextSelectionReference(&findModule).fromReference).array; } 
		
		bool verifyTextSelections(string s)
		{ return s == exportTextSelections(validate(importTextSelections(s))); } 
		
		bool extendSelection_impl(Flag!"selectAll" selectAll=No.selectAll)
		{
			const s0 = exportTextSelections(textSelections); 
			textSelections = selectAll ? extendAll(textSelections) : extend(textSelections); 
			const s1 = exportTextSelections(textSelections); 
			
			if(s0!="" && s1!="" && s0!=s1)
			{
				if(extendSelectionStack.length && extendSelectionStack.back==s0)
				extendSelectionStack ~= s1; 
				else
				extendSelectionStack = [s0, s1]; 
				return true; 
			}
			else
			return false; 
		} 
		
		bool shrinkSelection_impl()
		{
			if(extendSelectionStack.length>=2)
			{
				const 	act = extendSelectionStack[$-1],
					prev = extendSelectionStack[$-2]; 
				if(act==exportTextSelections(textSelections) && verifyTextSelections(prev))
				{
					textSelections = importTextSelections(prev); 
					extendSelectionStack = extendSelectionStack[0..$-1]; 
					return true; //success
				}
			}
			return false; 
		} 
		
		bool selectAll_impl()
		{ return extendSelection_impl(Yes.selectAll); } 
	}version(/+$DIDE_REGION Permissions+/all)
	{
		protected
		{
			enum LogRequestPermissions = (常!(bool)(0)); 
			
			/+
				+ this value is incremented by every cut or paste batch operation.
						This controls undoOperation fuson, in order to preserve the order of
						multiselect cut and paste operations. (cursors are only vanid if they are in order.) 
			+/
			uint undoGroupId; 
			
			bool requestModifyPermission(CodeColumn col)
			{
				//Todo: constness
				assert(col); 
				if(isReadOnly) return false; 
				foreach(a; col.thisAndAllParents)
				{
					if(auto c = (cast(CodeColumn)(a))) if(c.containsBuildMessages) return false; 
					if(auto m = (cast(Module)(a))) return !m.isReadOnly; 
				}
				return false; 
			} 
			
			bool requestDeletePermission(TextSelection ts)
			{
				auto s = ts.sourceText; 
				/+
					this can throw if the structured contents are invalid. 
					If that goes into the undo, it would not be redo'd.
				+/
				
				auto res = requestModifyPermission(ts.codeColumn); 
				if(res)
				{
					static if(LogRequestPermissions)
					print(EgaColor.ltRed("DEL"), ts.toReference.text, s.quoted); 
					
					auto m = moduleOf(ts).enforce; 
					m.undoManager.justRemoved(undoGroupId, ts.toReference.text, s); 
				}
				return res; 
			} 
			
			struct CollectedInsertRecord
			{
				int stage; 
				TextSelection textSelection; 
				string contents; 
				void reset()
				{ this = typeof(this).init; }                                                     
			} 
			CollectedInsertRecord collectedInsertRecord; 
			
			bool requestInsertPermission_prepare(TextSelection ts, string str)
			{
				auto res = requestModifyPermission(ts.codeColumn); 
				
				if(res) {
					auto m = moduleOf(ts).enforce; 
					static if(LogRequestPermissions)
					print(EgaColor.ltGreen("INS0"), ts.toReference, str.quoted); 
					with(collectedInsertRecord)
					{
						enforce(stage==0, "collectedInsertRecord.stage inconsistency 1"); 
						stage = 1; 
						textSelection = ts; 
						contents = str; 
					}
				}
				return res; 
			} 
			
			void requestInsertPermission_finish(TextSelection ts)
			{
				auto m = moduleOf(ts).enforce; 
				with(collectedInsertRecord)
				{
					enforce(stage==1, "collectedInsertRecord.stage inconsistency 2"); 
					static if(LogRequestPermissions)
					print(EgaColor.ltCyan("INS1"), ts.toReference); 
					
					textSelection.cursors[1] = ts.cursors[1]; 
					m.undoManager.justInserted(undoGroupId, textSelection.toReference.text, contents); 
					reset; 
				}
			} 
		} 
	}version(/+$DIDE_REGION Undo/Redo+/all)
	{
		//Undo/Redo
		
		/+
			3 levels
				1. Save, SaveAll (ehhez csak egy olyan kell, hogy a legutolso save/load ota a user 
							 beleirt-e valamit.   Hierarhikus formaban lennenek a changed flag-ek, a soroknal 
							 meg lenne 2 extra: removedNextRow, removedPrevRow)
				2. Opcionalis Undo: ez csak 2 save kozott mukodhetne. Viszont a redo utani modositas
							 nem semmisitene meg az utana levo undokat, hanem csak becsatlakoztatna a graph-ba. 
							 Innentol nem idovonal van, hanem graph.
				3.	Opcionalis history: Egy kulon konyvtarba behany minden menteskori es betolteskori 
					allapotot. Ezt kesobb delta codinggal tomoriteni kell. 
		+/
		
		protected void executeUndoRedoRecord(in bool isUndo, in bool isInsert, in TextModificationRecord rec)
		{
			TextSelection ts; 
			bool decodeTs(bool reduceToStart)
			{
				string where = rec.where; 
				if(reduceToStart) where = where.reduceTextSelectionReferenceStringToStart; 
				ts = TextSelection(where, &findModule); 
				bool res = ts.valid; 
				if(!res) WARN("Invalid ts: "~where); 
				return res; 
			} 
			
			const isCut = isUndo==isInsert; 
			
			if(decodeTs(!isCut))
			{
				if(isCut)
				cut_impl!true([ts]); 
				else
				paste_impl!true([ts], rec.what); 
				
				if(decodeTs(isCut))
				textSelections = [ts]; 
			}
		} 
		
		protected void executeUndoRedo(bool isUndo)(in TextModification tm)
		{
			static if(isUndo) auto r = tm.modifications.retro; else auto r = tm.modifications; 
			r.each!(m => executeUndoRedoRecord(isUndo, tm.isInsert, m)); 
		} 
		
		protected void execute_undo(in TextModification tm)
		{ executeUndoRedo!true (tm); } protected void execute_redo(in TextModification tm)
		{ executeUndoRedo!false(tm); } 
		
		protected void execute_reload(string where, string what)
		{
			if(auto m=findModule(File(where)))
			{
				m.reload(desiredStructureLevel, nullable(what)); 
				//selectAll
				textSelections = [m.content.allSelection(true)]; 
				//Todo: refactor codeColumn.allTextSelection(bool primary or not)
			}
			else
			assert(0, "execute_reload: module lost: "~where.quoted); 
			//Todo: somehow signal bact to the undo manager, if an undo operation is failed
		} 
		
		void undoRedo_impl(string what)()
		{
			//Todo: select the latest undo/redo operation if there are more than 
			//one modules selected. If no modules selected: select from all of them.
			if(auto m = moduleWithPrimaryTextSelection)
			{
				//Todo: undo should not remove textSelections on other modules.
				mixin(q{m.undoManager.$(&execute_$, &execute_reload); }.replace("$", what)); 
				invalidateTextSelections; //because executeUndo don't call measure() so desiredX's are invalid.
			}
		} 
	}
	version(/+$DIDE_REGION Cut   +/all)
	{
		///All operations must go through copy_impl or cut_impl. Those are calling 
		///requestModifyPermission and blocks modifications when the module is readonly. Also that is needed for UNDO.
		bool copy_impl(TextSelection[] textSelections)
		{
			//copy_impl ///////////////////////////////////////
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			auto s = textSelections.sourceText; //this can throw if structured declarations has invalid contents
			
			//Bug: Two adjacent slashComnments are not emit a newLine in between them
			
			bool valid = s.length>0; 
			if(valid) clipboard.text = s; 
			return valid; 
		} 
		
		///Ditto
		auto cut_impl(bool dontMeasure=false)(TextSelection[] textSelections, bool* returnSuccess=null)
		{
			undoGroupId++; 
			
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			auto savedSelections = textSelections.map!"a.toReference".array; 
			
			if(returnSuccess !is null) *returnSuccess = true; //Todo: terrible way to
			
			void cutOne(TextSelection sel)
			{
				if(sel.isZeroLength) return; //nothing to do with empty selection
				if(auto col = sel.codeColumn)
				{
					const st = sel.start, en = sel.end; 
					
					foreach_reverse(y; st.pos.y..en.pos.y+1)
					{
						//Todo: this loop is in the draw routine as well. Must refactor and reuse
						if(auto row = col.getRow(y))
						{
							const rowCellCount = row.cellCount; 
							
							const 	isFirstRow	= y==st.pos.y,
								isLastRow	= y==en.pos.y,
								isMidRow	= !isFirstRow && !isLastRow; 
							if(isMidRow)
							{
								//delete whole row
								col.rows[y].setRemoved; 
								
								col.subCells = col.subCells.remove(y); 
								//Opt: do this in a one run batch operation.
							}
							else
							{
								//delete partial row
								const	x0 = isFirstRow	? st.pos.x	: 0,
									x1 = isLastRow 	? en.pos.x 	: rowCellCount+1; 
								
								foreach_reverse(x; x0..x1)
								{
									if(x>=0 && x<rowCellCount)
									{
										if(auto cntr = (cast(Container)(row.subCells[x]))) cntr.setRemoved; 
										
										row.subCells = row.subCells.remove(x); 
										//Opt: this is not so fast. It removes 1 by 1.
									}
									else if(x==rowCellCount)
									{
										//newLine
										if(auto nextRow = col.getRow(y+1))
										{
											foreach(ref ss; savedSelections)
											{
												//Opt: must not go througn all selection.
												//It could binary search the start position to iterate.
												ss.replaceLatestRow(nextRow, row); 
											}
											
											if(nextRow.subCells.length)
											{
												row.append(nextRow.subCells); 
												row.adoptSubCells; 
												//Note: it seems logical, but not help in tracking.
												//Always mark a cut with changedRemoved: row.setChangedCreated;
											}
											
											nextRow.subCells = []; 
											col.subCells = col.subCells.remove(y+1); 
										}
										else
										assert(0, "TextSelection out of range NL"); 
									}
									else
									assert(0, "TextSelection out of range X"); 
								}
								
								row.refreshTabIdx; 
								row.spreadElasticNeedMeasure; 
								row.setChangedRemoved; 
							}
						}
						else
						assert(0, "TextSelection out of range Y"); 
					}
					
					needResyntax(col); 
					col.edited = true; 
				}
				else
				assert(0, "TextSelection invalid CodeColumn"); 
			} 
			
			foreach_reverse(sel; textSelections)
			{
				if(!sel.isZeroLength)
				{
					if(requestDeletePermission(sel))
					{ cutOne(sel); }
					else
					{
						if(returnSuccess !is null) {
							//Todo: maybe it would be better to handle readOnlyness with an exception...
							*returnSuccess = false; 
						}
					}
				}
			}
			
			static if(!dontMeasure)
			measure; //It's needed to calculate TextCursor.desiredX
			//Opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.
			
			return savedSelections.map!"a.fromReference".filter!"a.valid".array; 
			
			/+Bug: must not fail when text selected inside error messages!+/
		} 
		
		bool cut_impl2(bool dontMeasure=false)(TextSelection[] sel, ref TextSelection[] res)
		{
			//Todo: constness for input
			bool success; 
			auto tmp = cut_impl!dontMeasure(sel, &success); 
			if(success) res = tmp; 
			return success; 
		} 
	}version(/+$DIDE_REGION Paste +/all)
	{
		//Todo: Make a version of copy/cut/paste that works with CodeColumns (multiple rows)
		//Todo: For this CodeColumn deep copy must be implemented somehow.  //Maybe by exporting and rendering it again. Speed is not important
		auto paste_impl(bool dontMeasure=false)(
			TextSelection[] textSelections,
			string input,
			Flag!"duplicateTabs" duplicateTabs = No.duplicateTabs,
			Flag!"isObject" isObject = No.isObject,
			int objectSubColumnIdx = 0,
			TextFormat objectTextFormat = TextFormat.managed_block
		)
		{
			if(input=="" || textSelections.empty) return textSelections; //no target
			
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			//Todo: BOM handling
			
			string[] lines; 
			
			if(isObject)
			{
				const source = input.replace("\0", ""); 
				//syntaxCheck(source);   not good for expressions, only good for blocks.
				auto testCol = new CodeColumn(null, source, objectTextFormat); 
				enforce(testCol.byCell.drop(1).empty, "Object insert: Column must have only 1 object. "~source.quoted~" "~objectTextFormat.text); 
				auto testNode = cast(CodeNode) testCol.byCell.frontOrNull; 
				auto testGlyph = cast(Glyph) testCol.byCell.frontOrNull; 
				enforce(testNode || testGlyph, "Object insert: CodeNode expected."); 
				//Todo: clean this mess up, allow multiple glyphs and later multiline glyphs!
				
				lines = textSelections.map!"a.sourceText".array; 
				//this will be the content inserted into the object
			}
			else
			{ lines = input.splitLines; }
			
			if(lines.empty) return textSelections; //nothing to do with an empty clipboard
			
			if(!cut_impl2!dontMeasure(textSelections, /+writes into this if successful -> +/textSelections))
			{
				//Todo: this is terrible. Must refactor.
				return textSelections; 
			}
			
			//from here it's paste -------------------------------------------------
			undoGroupId++; 
			
			TextSelectionReference[] savedSelections; 
			
			//Todo: insertText with fake local syntax highlighting. until the background syntax highlighter finishes.
			
			///inserts text at cursor, moves the corsor to the end of the text
			
			void insertSingleLine(ref TextSelection ts, string str)
			{
				assert(ts.valid); 
				assert(ts.isZeroLength); 
				assert(ts.caret.pos.y.inRange(ts.codeColumn.subCells)); 
				
				if(auto row = ts.codeColumn.getRow(ts.caret.pos.y))
				{
					if(requestInsertPermission_prepare(ts, str))
					{
						int insertedCnt; 
						TextCursor updatedCursor; 
						
						if(isObject)
						{
							const source = input.replace("\0", str); 
							try
							{
								auto col = new CodeColumn(null, source, objectTextFormat); 
								
								if(auto node = col.extractSingleNode.ifThrown(null))
								{
									insertedCnt = row.insertSomething(
										ts.caret.pos.x, {
											node.setParent(row); 
											row.append(node); 
										}
									); 
									
									node.measure; //regenerates subColumns
									if(objectSubColumnIdx>=0)
									if(auto subCol = node.subColumns.array.get(objectSubColumnIdx))
									updatedCursor = subCol.endCursor; 
								}
								else if(auto glyph = (cast(Glyph)(col.byCell.frontOrNull)))
								{
									//Todo: support multiple glyphs AKA source text
									insertedCnt = row.insertSomething(ts.caret.pos.x, { row.append(glyph); }); 
								}
								else raise("Unhandled sourceCone node template"); 
							}
							catch(Exception e)
							{
								im.flashWarning("Error inserting CodeNode:"~e.simpleMsg); 
								insertedCnt = row.insertText(ts.caret.pos.x, source); 
							}
						}
						else
						{ insertedCnt = row.insertText(ts.caret.pos.x, str); }
						//INS
						
						
						//adjust caret and save
						ts.cursors[0].moveRight(insertedCnt); 
						ts.cursors[1] = ts.cursors[0]; 
						
						requestInsertPermission_finish(ts); 
						needResyntax(ts.codeColumn); 
						ts.codeColumn.edited = true; 
						
						if(updatedCursor.valid)
						{ ts.cursors[] = updatedCursor; }
					}
					
					savedSelections ~= ts.toReference; 
				}
				else
				assert(0, "Row out if range"); 
			} 
			
			void insertMultiLine(ref TextSelection ts, string[] lines )
			{
				assert(ts.valid); 
				assert(ts.isZeroLength); 
				assert(lines.length>=2); 
				
				if(auto row = ts.codeColumn.getRow(ts.caret.pos.y))
				{
					assert(ts.caret.pos.x>=0 && ts.caret.pos.x<=row.subCells.length); 
					
					//handle leadingTab duplication
					if(duplicateTabs && row.leadingCodeTabCount)
					{
						const newTabCnt = min(row.leadingCodeTabCount, ts.caret.pos.x); 
						
						lines = lines.dup; 
						lines.back = "\t".replicate(newTabCnt) ~ lines.back; 
					}
					
					if(requestInsertPermission_prepare(ts, lines.join(DefaultNewLine)))
					{
						//break the row into 2 parts
						//transfer the end of (first)row into a lastRow
						auto lastRow = row.splitRow(ts.caret.pos.x); 
						
						//insert at the end of the first row
						row.insertText(row.cellCount, lines.front);  //INS
						
						//create extra rows in the middle
						Cell[] midRows; 
						foreach(line; lines[1..$-1])
						{
							auto r = new CodeRow(ts.codeColumn, line);  //INS
							//Todo: this should be insertText
							r.setChangedCreated; 
							midRows ~= r; 
						}
						
						//insert at the beginning of the last row
						const insertedCnt = lastRow.insertText(0, lines.back);  //INS
						
						//insert modified rows into column
						ts.codeColumn.subCells 	= ts.codeColumn.subCells[0..ts.caret.pos.y+1]
							~ midRows
							~ lastRow
							~ ts.codeColumn.subCells[ts.caret.pos.y+1..$]; 
						
						//adjust caret and save as reference
						ts.cursors[0].pos.y += lines.length.to!int-1; 
						ts.cursors[0].pos.x = insertedCnt; 
						ts.cursors[1] = ts.cursors[0]; 
						
						requestInsertPermission_finish(ts); 
						needResyntax(ts.codeColumn); 
						ts.codeColumn.edited = true; 
					}
					
					savedSelections ~= ts.toReference; 
					
					//Todo: update caret
				}
				else
				assert(0, "Row out if range"); 
			} 
			
			///insert all lines into the selection
			void fullInsert(ref TextSelection ts)
			{
				if(lines.length==1)
				{
					//simple text without newline
					insertSingleLine(ts, lines[0]); 
				}
				else if(lines.length>1)
				{
					//insert multiline text
					insertMultiLine(ts, lines); 
				}
			} 
			
			if(textSelections.length==1)
			{
				//put all the clipboard into one place
				fullInsert(textSelections[0]); 
			}
			else if(textSelections.length>1)
			{
				if(lines.length>textSelections.length || duplicateTabs/+this means it is pasting newlines+/)
				{
					//clone the full clipboard into all selections.
					foreach_reverse(ref ts; textSelections)
					fullInsert(ts); 
				}
				else
				{
					//cyclically paste the lines of the clipboard
					foreach_reverse(ref ts, line; lockstep(textSelections, lines.cycle.take(textSelections.length)))
					insertSingleLine(ts, line); 
				}
			}
			
			static if(!dontMeasure)
			measure; //It's needed to calculate TextCursor.desiredX
			//Opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.
			
			return savedSelections.retro.map!"a.fromReference".filter!"a.valid".array; 
			
			/+Bug: must not fail when text selected inside error messages!+/
		} 
		
		void pasteText(string s)
		{ if(s!="") textSelections = paste_impl(textSelections, s); }  void insertNode(string source, int subColumnIdx=-1)
		{
			textSelections = paste_impl(
				textSelections, source, No.duplicateTabs, 
				Yes.isObject, subColumnIdx, TextFormat.managed_optionalBlock
			); 
		} 
		
	}struct ContainerSelectionManager(T : Container)
	{
		version(/+$DIDE_REGION+/all)
		{
			//Todo: Combine and refactor this with the one inside het.ui
			
			//T must have some bool properties:
			static if(1)
			static assert(
				__traits(
					compiles, {
						T a; 
						a.setSelected(a.getSelected); 
						a.setOldSelected(a.getOldSelected); 
						bounds2 b = a.getBounds; 
					}
				), "Field requirements not met."
			); 
			
			enum MouseOp
			{ idle, beforeMove, move, rectSelect} 
			MouseOp mouseOp; 
			
			enum SelectOp
			{ none, add, sub, toggle, clearAdd} 
			SelectOp selectOp; 
			
			vec2 dragSource; 
			bounds2 dragBounds;   //Todo: rect selection: if start.x>end.x then touching_select, not contain_select
			
			//these are calculated after update. No notifications, just keep calling update frequently
			T hoveredItem; 
			
			private float mouseTravelDistance = 0; 
			private vec2 accumulatedMoveStartDelta, mouseLast; 
			
			///must be called after an items removed
			void validateItemReferences(T[] items)
			{
				if(
					!items.canFind(hoveredItem)//Opt: slow linear search
				)
				hoveredItem = null; 
				//Todo: maybe use a hovered containerflag.
			}  
			
			 private static void select(alias op)(T[] items, T selectItem=null)
			{
				foreach(a; items)
				a.setSelected = a.getSelected.unaryFun!op; 
				if(selectItem) select!"true"([selectItem]); 
			}   
			
			bounds2 selectionBounds()
			{
				if(mouseOp == MouseOp.rectSelect)
				return dragBounds /+Note: It's sorted.+/; 
				else
				return bounds2.init; 
			} 
			
		}
		void update(
			bool 	mouseEnabled, 
			View2D 	view, 
			T[] 	items, 
			bool 	anyTextSelected, 
			void delegate() 	onResetTextSelection,
			void delegate() 	onMoveStarted
		)
		{
			version(/+$DIDE_REGION detect mouse travel+/all) {
				if(inputs.LMB.down)
				mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta); 
				else
				mouseTravelDistance = 0; 
			}
			
			void selectNone()
			{ select!"false"(items); } 
			void selectOnly(T item)
			{ select!"false"(items, item); } 
			void saveOldSelected()
			{ foreach(a; items) a.setOldSelected = a.getSelected; } 
			
			auto mouseAct = view.mousePos.vec2; 
			//view.invTrans(frmMain.mouse.act.screen.vec2, false/+non animated!!!+/); //note: non animeted view for mouse is better.
			
			auto mouseDelta = mouseAct-mouseLast; 
			mouseLast = mouseAct; 
			
			const 	LMB	= inputs.LMB.down,
				LMB_pressed	= inputs.LMB.pressed,
				LMB_released	= inputs.LMB.released,
				Shift	= inputs.Shift.down,
				Ctrl	= inputs.Ctrl.down,
				Alt	= inputs.Alt.down; 
			
			const 	modNone	 = !Shift 	&& !Ctrl,
				modShift	 = Shift 	&& !Ctrl,
				modCtrl	 = !Shift 	&& Ctrl,
				modShiftCtrl	 = Shift 	&& Ctrl; 
			
			const inputChanged = mouseDelta || inputs.LMB.changed || inputs.Shift.changed || inputs.Ctrl.changed; 
			
			version(/+$DIDE_REGION update current selection mode+/all) {
				if(modNone) selectOp = SelectOp.clearAdd; 
				if(modShift) selectOp = SelectOp.add; 
				if(modCtrl) selectOp = SelectOp.sub; 
				if(modShiftCtrl) selectOp = SelectOp.toggle; 
			}
			
			version(/+$DIDE_REGION update dragBounds+/all) {
				if(LMB_pressed) dragSource = mouseAct; 
				if(LMB) dragBounds = bounds2(dragSource, mouseAct).sorted; 
			}
			
			version(/+$DIDE_REGION update hovered item+/all) {
				hoveredItem = null; 
				if(mouseEnabled)
				foreach(item; items)
				if(item.getBounds.contains!"[)"(mouseAct))
				hoveredItem = item; 
			}
			version(/+$DIDE_REGION LMB was pressed+/all)
			{
				if(LMB_pressed && mouseEnabled)
				{
					if(
						hoveredItem && 
						(
							!hoveredItem.alwaysOnBottom || Alt || hoveredItem.flags.selected
							/+
								do rectSelect on alwaysOnBottom modules 
								except when Alt is pressed.
							+/
						)
					)
					{
						if(!anyTextSelected)
						{
							if(modNone)
							{
								if(!hoveredItem.flags.selected)
								selectOnly(hoveredItem); 
								accumulatedMoveStartDelta = 0; 
								mouseOp = MouseOp.beforeMove; 
							}
							if(modShift || modCtrl || modShiftCtrl)
							hoveredItem.flags.selected = !hoveredItem.flags.selected; 
						}
						else
						{
							//any mouse operation goes to text selection
						}
					}
					else
					{
						mouseOp = MouseOp.rectSelect; 
						saveOldSelected; 
					}
				}
			}
			
			version(/+$DIDE_REGION Update ongoing operations+/all)
			{
				
				
				version(/+$DIDE_REGION update rectangle selection+/all)
				{
					if(mouseOp == MouseOp.rectSelect && inputChanged)
					{
						foreach(a; items)
						if(dragBounds.contains!"[]"(a.getBounds))
						{
							final switch(selectOp)
							{
								case 	SelectOp.add, 
									SelectOp.clearAdd: 	a.flags.selected = true; 	break; 
								case SelectOp.sub: 	a.flags.selected = false; 	break; 
								case SelectOp.toggle: 	a.flags.selected = !a.flags.oldSelected; 	break; 
								case SelectOp.none: 		break; 
							}
						}
						else
						{ a.flags.selected = (selectOp == SelectOp.clearAdd) ? false : a.flags.selected; }
					}
				}
				
				version(/+$DIDE_REGION trigger selection dragging+/all) {
					if(mouseOp == MouseOp.beforeMove && mouseTravelDistance>4)
					{
						mouseOp = MouseOp.move; 
						if(onMoveStarted)
						onMoveStarted(); 
					}
					
					if(mouseOp == MouseOp.beforeMove && mouseDelta)
					accumulatedMoveStartDelta += mouseDelta; 
				}
				
				version(/+$DIDE_REGION drag the selection+/all)
				{
					if(mouseOp == MouseOp.move && mouseDelta)
					{
						foreach(a; items)
						if(a.flags.selected)
						{
							a.outerPos += mouseDelta + accumulatedMoveStartDelta; 
							
							accumulatedMoveStartDelta = 0; 
							
							//Todo: jelezni kell valahogy az elmozdulast!!!
							version(/+$DIDE_REGION+/none)
							{
								//this is a good example of a disabled DIDE region
								static if(is(a.cachedDrawing))
								a.cachedDrawing.free; 
							}
						}
					}
				}
			}
			version(/+$DIDE_REGION LMB was released+/all)
			{
				if(LMB_released) {
					if(mouseOp == MouseOp.rectSelect) { onResetTextSelection(); }
					//...                                               ou
					
					mouseOp = MouseOp.idle; 
					accumulatedMoveStartDelta = 0; 
				}
			}
		} 
	} struct TextSelectionManager
	{
		
		struct SELECTIONS; 
		@SELECTIONS
		{
			//Note: these cursors MUST BE validated!!!!!
			TextCursor cursorAtMouse, cursorToExtend; 
			TextSelection	selectionAtMouse; 
			TextSelection[] 	selectionsWhenMouseWasPressed; 
		} 
		
		bool 	mouseScrolling,
			wordSelecting,
			cursorToExtend_primary; 
		
		Nullable!vec2 	scrollInRequest; 
		
		version(/+$DIDE_REGION validation of textSelections+/all)
		{
			bool mustValidateInternalSelections; 
			
			
			public void invalidateInternalSelections()
			{ mustValidateInternalSelections = true; } 
			
			void validateInternalSelections(Workspace workspace)
			{
				if(mustValidateInternalSelections.chkClear)
				{
					//validate all the cursors market with @SELECTIONS UDA
					static foreach(f; FieldNamesWithUDA!(typeof(this), SELECTIONS, false))
					mixin(format!"%s = workspace.validate(%s);"(f, f)); 
					PING2; 
				}
			} 
		}
		
		version(/+$DIDE_REGION preprocess mouse input+/all)
		{
			private
			{
				bool 	opSelectColumn,
					opSelectColumnAdd,
					opSelectAdd,
					opSelectExtend; 
				
				DateTime lastMainMousePressTime; 
				ClickDetector cdMainMouseButton; 
				float mouseTravelDistance = 0; 
				bool doubleClick; 
				
				void updateInputs(in Workspace.MouseMappings mouseMappings)
				{
					//detectMouseTravel
					if(inputs[mouseMappings.main].down)
					{
						//Todo: copy/paste
						mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta); 
					}
					else
					{ mouseTravelDistance = 0; }
					
					cdMainMouseButton.update(inputs[mouseMappings.main].down); 
					doubleClick = cdMainMouseButton.doubleClicked; 
					
					//check if a keycombo modifier with the main mouse button isactive
					bool _kc(string sh) { return KeyCombo([sh, mouseMappings.main].join("+")).active; } 
					opSelectColumn = _kc(mouseMappings.selectColumn	); 
					opSelectColumnAdd = _kc(mouseMappings.selectColumnAdd	); 
					opSelectAdd = _kc(mouseMappings.selectAdd	); 
					opSelectExtend = _kc(mouseMappings.selectExtend	); 
					
				} 
			} 
		}
		
		void update(
			View2D 	view	, //input: mouse position,  output: zoom/scroll.
			Workspace 	workspace	, //used to access and modify textSelection, create tectCursor at mouse.
			in Workspace.MouseMappings 	mouseMappings	, //mouse buttons, shift modifier settings.
		)
		{
			//Todo: make textSelection functional, not a ref
			//Opt: only call this when the workspace changed (remove module, cut, paste)
			
			validateInternalSelections(workspace); 
			cursorAtMouse = workspace.createCursorAt(view.mousePos.vec2); 
			
			updateInputs(mouseMappings); 
			scrollInRequest.nullify; 
			if(doubleClick) wordSelecting = true; 
			
			void initiateMouseOperations()
			{
				if(auto dw = inputs[mouseMappings.zoom].delta) view.zoomAroundMouse(dw*workspace.wheelSpeed); 
				if(inputs[mouseMappings.zoomInHold].down) view.zoomAroundMouse(.125); 
				if(inputs[mouseMappings.zoomOutHold].down) view.zoom/+AroundMouse+/(-.125); 
				
				if(inputs[mouseMappings.scroll].pressed) mouseScrolling = true; 
				
				if(inputs[mouseMappings.main].pressed)
				{
					if(workspace.textSelections.hitTest(view.mousePos.vec2))
					{
						//Todo: start dragging the selection contents and paste on mouse button release
					}
					else if(cursorAtMouse.valid)
					{
						//start selecting with mouse
						selectionsWhenMouseWasPressed = workspace.textSelections.dup; 
						
						if(workspace.textSelections.empty)
						{
							if(doubleClick)
							{
								selectionAtMouse = TextSelection(cursorAtMouse, false); 
								wordSelecting = false; 
							}else {
								//single click goes to module selection
							}
						}
						else
						{
							//extension cursor is the nearest selection.cursors[0]
							if(!doubleClick)
							{
								auto selectionToExtend = 	selectionsWhenMouseWasPressed
									.filter!(a => a.codeColumn is cursorAtMouse.codeColumn)
									.minElement!(a => distance(a, cursorAtMouse))(TextSelection.init); 
								
								cursorToExtend = selectionToExtend.cursors[0]; 
								cursorToExtend_primary = selectionToExtend.primary; 
							}
							
							if(!cursorToExtend.valid)
							{
								cursorToExtend = cursorAtMouse; //defaults extension pos is mouse press pos.
								cursorToExtend_primary = false; 
							}
							
							selectionAtMouse = TextSelection(cursorAtMouse, false); 
						}
					}
				}
			} 
			
			void updateMouseScrolling() //(middle button panning)
			{
				if(mouseScrolling)
				{
					if(!inputs[mouseMappings.scroll])
					mouseScrolling = false; 
					else if(const delta = inputs.mouseDelta)
					view.scroll(delta); 
				}
			} 
			
			void restrictDraggedMousePos()
			{
				//restrict dragged mousePos to the bounds of the current codeColumn
				if(selectionAtMouse.valid && workspace.mainIsForeground && inputs[mouseMappings.main])
				{
					auto bnd = worldInnerBounds(selectionAtMouse.codeColumn); 
					bnd.high = nextDown(bnd.high); //make sure it's inside
					
					const restrictedMousePos = opSelectColumn || opSelectColumnAdd 	? restrictPos_normal(view.mousePos.vec2, bnd) //normal clamping for columnSelect
						: restrictPos_editor(view.mousePos.vec2, bnd) /+text editor clamping for normal select+/; 
					
					auto restrictedCursorAtMouse = workspace.createCursorAt(restrictedMousePos); 
					
					if(restrictedCursorAtMouse.valid && restrictedCursorAtMouse.codeColumn==selectionAtMouse.codeColumn)
					selectionAtMouse.cursors[1] = restrictedCursorAtMouse; 
					
					if(mouseTravelDistance>4)
					{
						scrollInRequest = restrictPos_normal(view.mousePos.vec2, bnd); 
						//always normal clipping for mouse focus point
					}
				}
			} 
			
			void handleReleasedSelectionButton()
			{
				//resets mouse selection when the button is released
				if(selectionAtMouse.valid && !inputs[mouseMappings.main])
				{
					selectionAtMouse = TextSelection.init; 
					selectionsWhenMouseWasPressed = []; 
					wordSelecting = false; 
				}
			} 
			void combineFinalSelection()
			{
				//combine previous selection with the current mouse selection
				
				if(!selectionAtMouse.valid) return; //nothing to do with an empty selection
				
				//Todo: for additive operations, only the selections on the most recent
				
				auto applyWordSelect(TextSelection s) { return wordSelecting ? s.extendToWordsOrSpaces : s; } 
				auto applyWordSelectArr(TextSelection[] s) { return wordSelecting ? s.map!(a => a.extendToWordsOrSpaces).array : s; } 
				
				TextSelection[] ts; //the new text selection
				
				if(opSelectColumn || opSelectColumnAdd)
				{
					auto getPrimaryCursor()
					{
						auto a = selectionsWhenMouseWasPressed.filter!"a.primary"; 
						if(!a.empty) return a.front.cursors[0]; 
						return cursorToExtend; 
					} 
					
					//Column select
					auto 	c0	= opSelectColumnAdd 	? selectionAtMouse.cursors[0] 
								: getPrimaryCursor,  //Bug: what if primary cursor is on another module
						c1	= selectionAtMouse.cursors[1]; 
					
					const 	downward 	= c0.pos.y<c1.pos.y,
						dir	= downward ? 1 : -1,
						count	= abs(c0.pos.y-c1.pos.y)+1; 
					
					auto 	a0 = iota(count).map!((i){ auto res = c0; c0.move(ivec2(0,  dir)); return res; }).array,
						a1 = iota(count).map!((i){ auto res = c1; c1.move(ivec2(0, -dir)); return res; }).array; 
					
					if(downward) a1 = a1.retro.array; else a0 = a0.retro.array; 
					
					ts = iota(count).map!(i => TextSelection(a0[i], a1[i], false)).array; 
					assert(ts.isSorted); 
					
					if(opSelectColumn)
					{
						//the first selection created is at the mosue, it must be the primary
						(downward ? ts.front : ts.back).primary = true; 
					}
					
					//if there are any nonZeroLength selections, remove all zeroLength carets
					if(ts.any!"!a.isZeroLength")
					ts = ts.remove!"a.isZeroLength"; 
					
					//if all are carets, remove those at line ends
					if(ts.all!"a.isZeroLength" && !ts.all!"a.isAtLineStart" && !ts.all!"a.isAtLineEnd")
					{
						/+
							Todo: Shift+Alt+LMB multicursor bug
							01,
							
							02,
							03
							Can't put 3 cursors after the numbers, only 2.
						+/
						ts = ts.remove!"a.isAtLineEnd"; 
					}
					
					ts = applyWordSelectArr(ts); 
					
					if(
						opSelectColumnAdd//Ctrl+Alt+Shift = add column selection
					)
					ts = merge(selectionsWhenMouseWasPressed ~ ts); 
					
				}
				else if(opSelectAdd || opSelectExtend)
				{
					auto actSelection = applyWordSelect(
						opSelectAdd 	? selectionAtMouse
							: TextSelection(
							cursorToExtend, 
							selectionAtMouse.caret, 
							cursorToExtend_primary
						)
							//Bug: what if primary cursor to extend is on another module
					); 
					//remove touched existing selections first.
					auto baseSelections = selectionsWhenMouseWasPressed.remove!(a => touches(a, actSelection)); 
					ts = merge(baseSelections ~ actSelection); 
				}
				else
				{
					auto s = applyWordSelect(selectionAtMouse); 
					ts = [s]; 
				}
				
				//Todo: some selection operations may need 'overlaps' instead of 'touches'. Overlap only touch when on operand is a zeroLength selection.
				//automatically mark primary for single selections
				if(ts.length==1)
				ts[0].primary = true; 
				
				workspace.textSelections = ts; 
			} 
			
			
			//selection bussiness logic
			if(!im.wantMouse && workspace.mainIsForeground && view.isMouseInside) initiateMouseOperations; 
			updateMouseScrolling; 
			restrictDraggedMousePos; 
			handleReleasedSelectionButton; 
			combineFinalSelection; 
			
		} 
		
	} version(/+$DIDE_REGION Resyntax+/all)
	{
		class SyntaxHighlightWorker
		{
			//Todo: Make a BackgroundWorker pattern template
			static struct Job
			{
				DateTime changeId; //must be a globally unique id, also sorted by chronology
				CodeColumn col; //only one object allowed with the same referenceId
				
				bool valid; 
				bool opCast(b:bool)() const { return valid; } 
			} 
			
			private int destroyLevel; 
			private Job[] inputQueue, outputQueue; 
			
			void put(DateTime changeId, CodeColumn col)
			{
				synchronized(this)
					inputQueue = 	inputQueue.remove!(j => j.col is col) 
						~ Job(changeId, col); 
			} 
			
			Job getResult()
			{
				Job res; 
				synchronized(this)
					if(outputQueue.length)
						res = outputQueue.fetchFront; 
				return res; 
			} 
			
			private Job _workerGetJob()
			{
				Job res; 
				synchronized(this)
					if(inputQueue.length) {
					res = inputQueue.fetchBack; 
					res.valid = true; 
				} 
				return res; 
			} 
			
			private void _workerCompleteJob(Job job)
			{
				synchronized(this)
					outputQueue ~= job; 
			} 
			
			static private void worker(shared SyntaxHighlightWorker shw_)
			{
				auto shw = cast()shw_; 
				while(shw.destroyLevel==0)
				{
					if(auto job = shw._workerGetJob)
					{
						//actual work comes here
						shw._workerCompleteJob(job); 
					}
					else
					{
						//LOG("Worker Idling");
						sleep(10); 
					}
				}
				shw.destroyLevel = 2; 
				//LOG("Worker finished");
			} 
			
			this()
			{ spawn(&worker, cast(shared)this); } 
			
			~this()
			{
				destroyLevel = 1; 
				while(destroyLevel==1)
				{
					//LOG("Waiting for worker thread to finish");
					sleep(10); //Todo: it's slow... rewrite to message based
				}
			} 
		} version(/+$DIDE_REGION Resyntax+/all)
		{
			void needResyntax(CodeColumn col)
			{
				static DateTime uniqueTime; 
				uniqueTime.actualize; 
				scope(exit) col.lastResyntaxTime = uniqueTime; 
				
				const doItRightNow = (col.flags.columnIsTable && col.rowCount<1000); 
				if(doItRightNow)
				{
					/+
						Note: Immediate resyntax for smaller tables.
						It's annoying when the arrangement of the table cells are shifting.
					+/
					resyntaxNow(col); 
				}
				else
				{
					//Note: Delayed resyntax.  It's needed for large highlighted texts.
					if(
						//fast-update last item if possible
						resyntaxQueue.map!"a.what".backOrNull is col
					)
					{ resyntaxQueue.back.when = uniqueTime; }
					else
					{
						//remove if alreay exists
						resyntaxQueue = resyntaxQueue.remove!(e => e.what is col); 
						//add
						resyntaxQueue ~= ResyntaxEntry(col, uniqueTime); 
					}
				}
			} 
			
			void UI_ResyntaxQueue()
			{
				with(im) {
					foreach(e; resyntaxQueue)
					Row(
						{
							Row(e.when.text, { width = fh*9; }); 
							if(auto col = cast(CodeColumn)e.what)
							{
								auto tc = TextCursor(col, ivec2(0, 0)); 
								Row(tc.toReference.text); 
							}
						}
					); 
				}
			} 
			
			void resyntaxNow(CodeColumn col)
			{ col.resyntax; } 
			
			void resyntaxLater(CodeColumn col, DateTime changedId)
			{ syntaxHighlightWorker.put(changedId, col); } 
			
			/// returns true if any work done or queued
			bool updateResyntaxQueue()
			{
				if(auto job = syntaxHighlightWorker.getResult)
				{
					auto col = job.col; 
					if(col.getStructureLevel >= StructureLevel.highlighted)
					{
						static DateTime lastOutdatedResyncTime; 
						if(
							col.lastResyntaxTime==job.changeId || 
							now-lastOutdatedResyncTime > .25*second
						)
						{
							//mod.resyntax_src(job.sourceCode);
							resyntaxNow(col); 
							lastOutdatedResyncTime = now; 
						}
					}
				}
				
				if(resyntaxQueue.empty) return false; 
				
				//limit the frequency of slow sourceText() calls
				static DateTime lastResyntaxLaterTime; 
				if(now-lastResyntaxLaterTime < .25*second) return false; 
				lastResyntaxLaterTime = now; 
				
				auto act = resyntaxQueue.fetchBack; 
				resyntaxLater(act.what, act.when); 
				return true; 
			} 
		}
	}version(/+$DIDE_REGION Update+/all)
	{
		
		
		//Todo: Ctrl+D word select and find
		
		//Mouse ---------------------------------------------------
		
		struct MouseMappings
		{
			string 	main	= "LMB",
				scroll	= "MMB", //Todo: soft scroll/zoom, fast scroll
				menu	= "RMB",
				zoom	= "MW",
				zoomInHold	= "MB5",
				zoomOutHold	= "MB4",
				selectAdd	= "Alt",
				selectExtend	= "Shift",
				selectColumn	= "Shift+Alt",
				selectColumnAdd 	= "Ctrl+Shift+Alt"; 
		} 
		
		private bool MMBReleasedWithoutScrolling()
		{
			return inputs.MMB.released && (cast(GLWindow)(mainWindow)).mouse.hoverMax.screen.manhattanLength<=2; 
			//Todo: Ctrl+left click should be better. I think it will not conflict with the textSelection, only with module selection.
		} 
		
		void handleKeyboard()
		{
			if(mainWindow.canProcessUserInput)
			{
				if(!im.wantKeys)
				{
					this.callVerbs; 
					
					if(textSelections.empty)
					{ mainWindow.inputChars = []; }
					else
					{
						//Todo: single window only
						string unprocessed; 
						foreach(ch; mainWindow.inputChars.unTag.byDchar)
						{
							if(ch==9 && ch==10)
							{
								//if(flags.acceptEditorKeys) cmdQueue ~= EditCmd(cInsert, [ch].to!string);
							}
							else if(ch>=32)
							{
								//cmdQueue ~= EditCmd(cInsert, [ch].to!string);
								try
								{
									/+
										if(ch=='`') ch = '\U0001F4A9'; //todo: unable to input emojis
										from keyboard or clipboard! Maybe it's a bug.
									+/
									pasteText(ch.to!string); 
								}
								catch(Exception)
								{ unprocessed ~= ch; }
							}
							else
							{ unprocessed ~= ch; }
						}
						mainWindow.inputChars = unprocessed; 
					}
				}
				else
				{
					/+The im wants keyboard input.  Here handle only a few global verbs.+/
					alias globalVerbs = AliasSeq!(
						kill, rebuild, run, gotoLine, 
						searchBoxActivate, searchBoxActivateGlobal,
						outlineActivate, insightActivate
					); 
					static foreach(v; globalVerbs) this.callVerb!v; 
				}
			}
		} 
		
		void handleXBox()
		{
			static DateTime t0; 
			const df = (now - t0).value((1.0f/60)*second).clamp(0, 10); //1 = 60FPS
			t0 = now; 
			
			if(!mainIsForeground) return; 
			
			const ss = df*32, zs = df*.18f; 
			if(auto a = inputs.xiRX.value) scrollH	(-a*ss); 
			if(auto a = inputs.xiRY.value) scrollV	(a*ss); 
			if(auto a = inputs.xiLY.value)
			{
				version(/+$DIDE_REGION move mosuse to subScreen center+/all)
				{
					{
						const p = mainView.subScreenClientCenter; 
						mouseLock(mix(desktopMousePos, mainWindow.clientToScreen(p), .125f)); 
						mouseUnlock; 
					}
				}
				
				version(/+$DIDE_REGION zoom around mouse+/all)
				{
					{
						//const p = mainView.subScreenClientCenter;
						const p = mainWindow.screenToClient(desktopMousePos); 
						mainView.zoomAround(vec2(p), a*zs); //Todo: ivec2 is not implicitly converted to vec2
					}
				}
			}
		} 
		
		
		
		Nullable!vec2 jumpRequest; 
		
		void jumpTo(vec2 pos)
		{
			with(mainView) if(scale<0.3f) scale = 1; 
			jumpRequest = nullable(vec2(pos)); 
		} 
		
		void jumpTo(bounds2 bnd)
		{
			//if(bnd) jumpTo(bnd.center); 
			if(bnd)
			{
				mainView.scale = 1; 
				mainView.smartScrollTo(bnd); 
			}
		} 
		
		void jumpTo(R)(R searchResults)
		if(isInputRange!(R, SearchResult))
		{ if(!searchResults.empty) jumpTo(searchResults.map!((r)=>(r.bounds)).fold!"a|b"); } 
		
		void jumpTo(Object obj)
		{
			if(!obj) return; 
			if(auto mm = (cast(Module.Message)(obj)))
			{
				if(mm.searchResults.length)	jumpTo(mm.searchResults); 
				else	jumpTo(mm.node.worldOuterBounds); 
			}
			else if(auto node = (cast(CodeNode)(obj)))
			{ jumpTo(node.worldOuterBounds); }
		} 
		
		void jumpTo(in CodeLocation loc)
		{
			if(!loc) return; 
			
			if(auto mod = findModule(loc.file))
			{
				/+
					Todo: load the module automatically, 
					focus on module if no line number.  -> Insight
				+/
				
				
				auto searchResults = codeLocationToSearchResults(loc); 
				if(searchResults.length)
				{
					if(const bnd = searchResults.map!(r => r.bounds).fold!"a|b")
					{ jumpTo(bnd.center); return; }
				}
			}
			
			im.flashWarning("Unable to jump to: "~loc.text); 
		} 
		
		void jumpTo(string id)
		{
			if(id.empty) return; 
			
			if(id.startsWith(CodeLocationPrefix))
			{ jumpTo(CodeLocation(id.withoutStarting(CodeLocationPrefix))); }
			else if(id.startsWith(MatchPrefix))
			{ NOTIMPL; }
		} 
		
		void handleJumps(View2D view)
		{
			if(MMBReleasedWithoutScrolling)
			{
				void doit()
				{
					//check something in the IMGUI that has a codeLocation id.
					{
						auto hs = hitTestManager.lastHitStack; 
						if(!hs.empty && hs.back.id.startsWith(CodeLocationPrefix))
						{ jumpTo(hs.back.id); return; }
					}
					
					//check a codeLocation CodeComment under mouse
					if(view.isMouseInside)
					{
						auto st = locate(view.mousePos.vec2); 
						//last thing can be a Glyph or an Img. Just skip it.
						if(st.length && !(cast(CodeComment)(st.back.cell))) st = st[0..$-1]; 
						if(st.length)
						if(auto cmt = (cast(CodeComment)(st.back.cell)))
						if(cmt.isCodeLocationComment)
						{
							if(auto loc = cmt.content.sourceText.withoutStarting("$DIDE_LOC ").CodeLocation)
							{
								if(!findModule(loc.file) && inputs["Shift"].down)
								{
									if(!loc.file.exists)
									{ im.flashWarning(i"File not found $(loc.file.fullName.quoted).".text); return; }
									loadModule(loc.file); 
									//Todo: move all buildMessages from mainFile to the newly opened file.
								}
								jumpTo(loc); return; 
							}
						}
					}
					
					//check the nearest searchresult
					if(view.isMouseInside)
					jumpTo(nearestSearchResult.reference); 
				} 
				doit; 
			}
		} 
		
		
		void updateMessageConnectionArrows()
		{
			if(_messageConnectionArrows_hash.chkSet(mixin(求sum(q{m},q{modules},q{m._updateSearchResults_state}))))
			{
				messageConnectionArrows.clear; 
				foreach(t; [EnumMembers!(DMDMessage.Type)])
				if(!t.among(DMDMessage.Type.find, DMDMessage.Type.console))
				{
					foreach(mod; modules)
					foreach(mm; mod.messagesByType[t])
					buildMessageConnectionArrows(mm.message); 
				}
				//5.6ms, not bad
			}
		} 
		
		const mouseMappings = MouseMappings.init; 
		uint _messageConnectionArrows_hash; 
		
		void update(
			View2D view, 
			ref BuildResult buildResult/+
				Must be a ref because there is 
				an internal file name correction cache.
			+/
		)
		{
			//update ////////////////////////////////////
			try
			{
				//textSelections = validTextSelections;  //just to make sure. (all verbs can validate by their own will)
				
				//Note: all verbs can optonally validate textSelections by accessing them from validTextSelections
				//all verbs can call invalidateTextSelections if it does something that affects them
				handleXBox; 
				handleKeyboard; 
				
				{ autoReloader.enabled = true; autoReloader.update(modules); }
				
				updateOpenQueue(1); 
				updateResyntaxQueue; 
				
				measure; //measures all containers if needed, updates ElasticTabstops
				//textSelections = validTextSelections;  //this validation is required for the upcoming mouse handling
				//and scene drawing routines.
				
				//From here every positions and sizes are correct -----------------------------------------
				
				
				//particle effects for incoming messages
				foreach(mm; incomingVisibleModuleMessageQueue.fetchAll)
				{
					auto layer = &markerLayerSettings[mm.type]; 
					addInspectorParticle(mm.node, mm.node.bkColor, layer.btnWorldBounds); 
					if(
						mm.type==DMDMessage.Type.error && !mm.isException
						&& firstErrorMessageArrived.chkSet
						/+
							Note: Catch the first compile error
							(Exceptions are always shown.)
						+/
					)
					{
						view.animSpeed = .96f; 
						jumpTo(mm); 
						im.flashError(mm.message.oneLineText); 
						bloodScreenEffect.activate; 
					}
				}
				
				handleJumps(view); //jumping to locations with MMB 
				
				//Ctrl+Click handling
				if(!im.wantMouse && view.isMouseInside && KeyCombo("Ctrl+LMB").pressed)
				{}
				
				moduleSelectionManager.update(
					!im.wantMouse && mainWindow.canProcessUserInput
					&& view.isMouseInside /+&& lod.moduleLevel+/,
					view, modules, textSelections.length>0, 
					{ textSelections = []; },
					{ bringToFrontSelectedModules; }
				); 
				textSelectionManager.update(view, this, mouseMappings); 
				
				//detect textSelection change
				const textSelectionChanged = textSelectionsHash.chkSet(textSelections.hashOf); 
				
				//if there are any cursors, module selection if forced to modules with textSelections
				if(textSelectionChanged && textSelections.length)
				{
					foreach(m; modules) m.flags.selected = false; 
					foreach(m; modulesWithTextSelection) m.flags.selected = true; 
				}
				
				//focus at selection
				if(!jumpRequest.isNull)
				{ with(mainView) origin = jumpRequest.get - (subScreenOrigin-origin); }
				else if(!scrollInBoundsRequest.isNull)
				{
					const b = scrollInBoundsRequest.get; 
					mainView.scrollZoom(b); 
				}
				else if(!textSelectionManager.scrollInRequest.isNull)
				{
					const p = textSelectionManager.scrollInRequest.get; 
					mainView.scrollZoom(bounds2(p, p)); 
				}
				else if(textSelectionChanged)
				{
					if(!inputs[mouseMappings.main].down)
					{
						//don't focus to changed selection when the main mouse button is held down
						
						//mainView.scrollZoom(worldBounds(textSelections)); <- this is bad when editing. It zooms out.
						//Todo: maybe it is problematic when the selection can't fit on the current screen
						
						//this is better.
						if(primaryTextSelection) mainView.scrollZoom(worldBounds(primaryTextSelection)); 
						//Todo: what about latestSelection: the selection that was added recently...
					}
				}
				scrollInBoundsRequest.nullify; 
				jumpRequest.nullify; 
				
				//animate cursors
				static if(AnimatedCursors)
				{
					if(textSelections.length<=MaxAnimatedCursors)
					{
						const 	animT	= calcAnimationT(application.deltaTime.value(second), .6, .25),
							maxDist 	= 1.0f; 
						
						foreach(ref ts; textSelections)
						{
							foreach(ref cr; ts.cursors[])
							with(cr)
							{
								const lp = localPos; 
								targetPos = lp.pos; 
								targetHeight = lp.height; 
								if(animatedPos.x.isnan)
								{
									animatedPos = targetPos; 
									animatedHeight = targetHeight; 
								}
								else
								{
									animatedPos.follow(targetPos, animT, maxDist); 
									animatedHeight.follow(targetHeight, animT, maxDist); 
								}
							}
						}
					}
				}
				
				//update buildresults if needed (compilation progress or layer mask change)
				size_t calcBuildStateHash()
				{
					return modules	.map!"tuple(a.file, a.outerPos)"
						.array
						.hashOf(
						buildResult.lastUpdateTime.hashOf(
							markerLayerHideMask
							/+to filter compile.err+/
						)
					); 
				} 
				/+
					Opt: outerPos is tracked to detect if a module was moved. It is wastefull to rebuild 
					all the layers with all the info, only move the affected layer items.
				+/
				buildStateChanged = lastBuildStateHash.chkSet(calcBuildStateHash); 
				if(buildStateChanged)
				{ updateModuleBuildStates(buildResult); }
				
				updateLastKnownModulePositions; 
				
				insight.updateInsightFiber; 
				search.updateSearchFiber; 
				foreach(m; modules) m.updateSearchResults; 
				updateMessageConnectionArrows; 
				
				updateAi; 
			}
			catch(Exception e)
			{ im.flashError(e.simpleMsg); }
		} 
	}version(/+$DIDE_REGION Help+/all)
	{
		string actHelpQuery, actSearchKeyword; 
		bounds2 actSearchKeywordBounds; 
		TextSelection actSearchKeywordSelection; 
		
		void prepareHelpQuery(ref string s)
		{
			//Todo: this is kinda lame: It avoids getting the actual textSelection until the last moment.
			if(s.canFind("$DIDE_PRIMARY_SELECTION$"))
			{ s = s.replace("$DIDE_PRIMARY_SELECTION$", primaryTextSelection.sourceText.replace("\n", " ")); }
		} 
		
		string extractHelpQuery(Breadcrumb[] breadcrumbs, string word)
		{
			//filter out breadcrumbs
			static bool validBreadcrumb(Breadcrumb bc)
			{
				if(auto decl = (cast(Declaration)(bc.node)))
				return 	decl.identifier!="" && 
					decl.keyword.among("struct", "union", "enum", "class", "interface"); 
				if(auto mod = (cast(Module)(bc.node)))
				return bc.text!=""; 
				return false; 
			} 
			breadcrumbs = breadcrumbs.filter!validBreadcrumb.array; 
			
			string[] s; if(breadcrumbs.length) s ~= breadcrumbs.back.text; 
			if(word!="" && word!=s.get(0)) s ~= word; 
			if(s.length==2) s.back = '+'~s.back; 
			auto query = s.join(' '); 
			
			return query; 
		} 
		
		string[] scrapeLinks_bing(string query)
		{
			prepareHelpQuery(query); 
			import het.http; 
			if(query=="") return []; 
			auto 	bloatml = curlGet(`https://bing.com/search?q=`~urlEncode(query)),
				links = bloatml	.splitter(`href="`).drop(1)
					.map!(s=>s.splitter(`"`).frontOr("")).filter!"a!=``".array; 
			links = links.filter!((a)=>(a.startsWith("https://") && !a.canFind(".bing.com"))).array; 
			
			immutable helpProviders = [
				`https://learn.microsoft.com/`,
				`https://registry.khronos.org/vulkan/specs/`,
				`https://registry.khronos.org/OpenGL-Refpages/`
			]; 
			
			string[] preferred; 
			foreach(link; links) foreach(a; helpProviders) if(link.startsWith(a)) preferred ~= link; 
			
			if(preferred.empty) {
				print("----------- Can't choose helpful link from: -----------------"); 
				links.each!print; beep; 
			}
			
			return preferred; 
		} 
		
		string[] scrapeLinks_dpldocs(string query)
		{
			prepareHelpQuery(query); 
			
			import het.http; 
			if(query=="") return []; 
			auto queryUrl = `https://search.dpldocs.info/?q=`~urlEncode(query); 
			auto 	bloatml = curlGet(queryUrl); 
			
			auto extractLinks(string addr)
			=> bloatml	.splitter(`<a href="//`~addr~`/`).drop(1)
				.map!(s=>s.splitter(`"`).frontOr("")).filter!"a!=``"
				.map!((a)=>(`https://`~addr~`/`~a)).array; 
			
			auto links = 	extractLinks("phobos.dpldocs.info") ~
				extractLinks("druntime.dpldocs.info"); 
			
			if(links.empty) {
				print("----------- Can't choose helpful link from: -----------------"); 
				bloatml.print; beep; 
			}
			
			if(links.length<=1) return links.take(1).array; 
			return [queryUrl]; 
		} 
		
		void startChrome(string url, string keyword="")
		{
			if(url==``) return; 
			try {
				prepareHelpQuery(keyword); 
				
				mainWindow.setForegroundWindow; //just to make sure
				executeShell(joinCommandLine(["start", "chrome", url])); 
				auto wi = waitWindow("Chrome_WidgetWin_1", "* - Google Chrome", 2*second); 
				
				if(keyword!="")
				{
					const 	clipboardHadText = clipboard.hasText,
						savedClipboardText = clipboardHadText ? clipboard.text : ""; 
					scope(exit) if(clipboardHadText) clipboard.text = savedClipboardText; 
					
					clipboard.text = keyword; 	
					
					int bail = 10; 
					foreach(i; 0..100) {
						const title = getWindowInfo(wi.handle).title; 
						if(title!=`Untitled - Google Chrome` && (--bail<=0)) break; 
						sleep(100); 
					}
					inputs.pressCombo("Ctrl+F"); 	sleep(50); 
					inputs.pressCombo("Ctrl+V"); 	sleep(50); 
					
					const needEnter = [`https://registry.khronos.org/vulkan/specs/`].any!((a)=>(url.startsWith(a))); 
					if(needEnter /+Note: This skips to the second match.+/)
					{ inputs.pressCombo("Enter"); 	sleep(50); }
				}
			}
			catch(Exception e) {}
		} 
		CodeComment activeAiNode; 
		string[] aiSnippets; 
		
		AiModel aiModel; 
		
		AiChat[CodeComment] pendingAiChatByAiAssistantNode; 
		
		void updateAi()
		{
			//Todo: check if activeAiNode was deleted...
			CodeComment[] toRemove; 
			foreach(node, chat; pendingAiChatByAiAssistantNode)
			{
				//Todo: check if the node was deleted...
				
				with(chat)
				{
					update(
						(Event event, string s)
						{
							final switch(event)
							{
								case Event.text: 	preserveTextSelections
								(
									{
										textSelections = [node.content.endSelection(true)]; 
										pasteText(s); 
									}
								); 	break; 
								case Event.error: 	print(EgaColor.ltRed("\nError: "~s)); 	break; 
								case Event.warning: 	print(EgaColor.yellow("\nWarning: "~s)); 	break; 
								case Event.done: 	print(EgaColor.ltGreen("\nDone: "~s)); 	break; 
							}
						}
					); 
					if(!running) toRemove ~= node; 
				}
			}
			
			foreach(node; toRemove)
			{
				auto chat = pendingAiChatByAiAssistantNode[node]; 
				pendingAiChatByAiAssistantNode.remove(node); 
				im.flashInfo("AiChat removed: "~chat.identityStr); 
			}
		} 
		
		CodeComment getSurroundingAiNode()
		{
			auto s = primaryTextSelection; 
			return ((s)?(s.codeColumn.allParents!CodeComment.filter!((a)=>(a.isAi)).frontOrNull):(null)); 
		} 
		
		void initiateAi_impl()
		{
			//Todo: activeAiNode must be validated in update()
			
			/+
				This is a one-button function for initiating an AI chat:
				- Memorizes selected code snippets if there is no active aiNode.
				- Attach selected code snippets to active aiNode.
				- Creates a new AI prompt if selection is a single cursor.
				- Selectes the active aiNode if inside one.
				(aiNode is CodeComment where customPrefix = "AI:")
			+/
			
			void copySnippets()
			{
				aiSnippets = textSelections.map!((a)=>(a.sourceText)).filter!"a!=``".array; 
				textSelections = []; 
			} 
			
			void insertSnippets()
			{
				auto col = activeAiNode.content; 
				foreach(src; aiSnippets)
				{
					textSelections = [col.endSelection(true)]; 
					if(!col.rows.back.empty) pasteText("\n"); 
					insertNode("/+code:\0+/", 0); 
					pasteText(src); 
					textSelections = [col.endSelection(true)]; 
				}
				im.flashInfo(i"Added $(aiSnippets.length) snippets to AI prompt.".text); 
				aiSnippets.clear; //one time use only
			} 
			
			void createAiNode()
			{
				insertNode("/+AI:\0+/", 0); 
				activeAiNode = getSurroundingAiNode; 
				im.flashInfo("Type AI prompt, press [Ctrl+Enter] to send."); 
				
				if(aiSnippets.length) insertSnippets; 
			} 
			
			auto ts = textSelections; 
			
			if(ts.empty) { im.flashWarning("Call AI: must have a a cursor or text selection first!"); return; }
			
			if(ts.length==1 && ts[0].valid && ts[0].isZeroLength)
			{
				//create/select active ai node
				auto aiNode = getSurroundingAiNode; 
				if(aiNode)
				{
					activeAiNode = aiNode; 
					im.flashWarning("This is the active AI prompt.  [Alt+A] will copy selection to here."); 
				}
				else
				{ createAiNode; }
			}
			else
			{
				//attach copy code snippets to ai prompt
				copySnippets; 
				if(activeAiNode)
				{ insertSnippets; }
				else
				{ im.flashInfo(i"$(aiSnippets.length) snippets collected for new AI prompt.".text); }
			}
			
		} 
		
		void launchAi_impl()
		{
			{
				auto n = getSurroundingAiNode; 
				if(!n) { im.flashWarning("Can't launch AI prompt.  Cursor must be inside an AI Node.".text); return; }
				activeAiNode = n; 
			}
			
			auto col = activeAiNode.content; 
			static bool isWhite(Cell c)
			{
				if(!c /+null: NewLine+/) return true; 
				if(auto g = (cast(Glyph)(c))) return g.ch.isDLangWhitespace; 
				return false; 
			} 
			static isAi(Cell cell)
			{
				if(isWhite(cell)) return false; 
				if(auto cmt = (cast(CodeComment)(cell))) return cmt.isAiRelated; 
				return false; 
			} 
			static isAssistant(Cell cell)
			=> isAi(cell) && (cast(CodeComment)(cell)).isAssistant; 
			
			static sourceText(Cell c)
			{
				if(!c) return "\n"; 
				if(auto g = (cast(Glyph)(c))) return g.ch.text; 
				if(auto n = (cast(CodeNode)(c))) return n.sourceText; 
				return "?"; 
			} 
			
			TextSelection[] userRanges; 
			foreach(grp; col.byCell.chunkBy!((a)=>(isAi(a))))
			{
				if(!grp[0])
				{
					auto nodes = grp[1].array; 
					while(nodes.length && isWhite(nodes.front)) nodes.popFront; 
					while(nodes.length && isWhite(nodes.back)) nodes.popBack; 
					if(nodes.length)
					{ userRanges ~= col.selectionOf(nodes.front, nodes.back, false); }
				}
			}
			
			//Elfold new user contents
			textSelections = userRanges; 
			insertNode("/+User:\0+/"); 
			
			{
				//Put cursor to the end and remove trailing whitespace and all the assistant contents
				textSelections = [col.endSelection(true)]; 
				auto cells = col.byCell.array; 
				const trailingWhiteCnt = cells.retro.countUntil!((a)=>(!(isWhite(a) || isAssistant(a)))).to!int; 
				if(trailingWhiteCnt>0)
				{
					foreach(i; 0..trailingWhiteCnt) cursorLeftSelect; 
					deleteToLeft; 
				}
			}
			
			
			{
				//Put all the ai contents into new lines
				auto sel = chain(only(Cell.init), col.byCell)
					.array.slide!(No.withPartial)(2)
					.filter!((a)=>(a[0] && isAi(a[1])))//if there's something before the ai node
					.map!((a)=>(col.cursorOf(a[1])))
					.map!((a)=>(TextSelection(a, a, false)))
					.array; 
				if(sel.length) { textSelections = sel; insertNewLine; }
			}
			
			string[][] messages; 
			{
				//Gather the prompt
				messages = 	col.byNode!CodeComment.filter!((a)=>(isAi(a)))
					.map!((a)=>(
					[
						/+role+/	a.customPrefix.wordAt(0).decapitalize, 
						/+content+/	a.content.sourceText/+Todo: process code snippets!+/
					]
				)).array; 
			}
			
			//Select the very end
			textSelections = [col.endSelection(true)]; 
			
			//create a new assistant node.
			insertNewLine; 
			insertNode("/+Assistant:\0+/", 0); 
			auto assistantNode = (cast(CodeComment)(textSelections.front.codeColumn.parent)); 
			
			if(!aiModel)
			{
				aiModel = new AiModel
				(
					"https://api.deepseek.com/v1/chat/completions", "deepseek-chat", 
					`You are a helpful assistant.
I don't want you to reformat my code, keep all whitespace as is.
For newly generated code use TAB to indent.
For multiline blocks like {} and comments /+ +/, put the opening and closing symbols into their own lines.
Use higher level DLang functional constructs when possible: ranges, etc.
Use GLSL-like vector/matrix operations, the user's framework supports that.
Technologies preferred: Win32 64bit platform, OpenGL GLSL for graphics, Vulkan GLSL for compute.

When communicating in expressions or one line code, use this form: /+Code: code+/
When inserting multiline code, use form:
/+Code:
	multiline
	source code goes here
+/

Put yout paragraphs into /+Note: text goes here+/ blocks!
You can do multiline paragrphs like this:
/+Note:
	line1
	line2
+/

Put bullet paragraphs into /+Bullet: text goes here+/ blocks!
It has a multiline variant too:
/+Bullet:
	line1
	line2
+/
Use one bullet paragraph for each bullet item!

Word wrap every paragraphs and bullet paragraphs to around 100 characters!

Put bold text inside /+Bold: text goes here+/ blocks! 

Put italic text inside /+Italic: text goes here+/ blocks! 

Put heading text inside /+Hn: text goes here+/ blocks, where n is in range 1 to 6! 

Sometimes I will give or ask the results in a "table", this is my table format, please preserve this exact format and whitespaces when you are communicating with it: `
					~"\n/+Code:\n"
					~q{
						(表([
							[q{/+Note: Header+/},q{/+Note: 2nd column+/},q{/+Note: 3rd column+/}],
							[q{normal cell},q{"string cell"},q{/+comment cell+/}],
							[q{/+If the whole row is a comment, it's ignored+/}],
							[],
							[q{/+also empty rows are ignored, they are just there for formatting+/}],
							[q{
								another cell 1+1=2
								/+anything D syntax can go here.+/
							},q{`Another string.
This one is multiline and without escapes.`}],
						]))
					}.splitLines[1..$-1].join('\n').outdent
					~"\n+/\n"
				); 
				aiModel.apiKey = File(appPath, "a.a").readStr; 
				NOTIMPL("Ini file for settings!"); 
			}
			
			
			{
				//launch ai query
				if(auto a = assistantNode in pendingAiChatByAiAssistantNode)
				{
					//stop the already running query
					(*a).stop; 
					pendingAiChatByAiAssistantNode.remove(assistantNode); 
				}
				
				auto chat = aiModel.newChat; 
				chat.ask(messages); 
				pendingAiChatByAiAssistantNode[assistantNode] = chat; 
				
				im.flashInfo("AiChat launched: "~chat.identityStr); 
			}
		} 
	}
	version(/+$DIDE_REGION+/all)
	{
		@STORED SearchBox search;  
		static struct SearchBox
		{
			bool searchBoxActivate_request; 
			@STORED
			{
				bool 	searchBoxVisible, 
					advancedSearchOptionsVisible, 
					lookInAllModules; 
				string searchText; 
				.Container.SearchOptions searchOptions; 
			} 
			
			void activate(string s, bool global=false)
			{
				searchBoxActivate_request = true; searchText = s; 
				lookInAllModules = global; 
			} 
			
			void deactivate(Workspace workspace)
			{ if(searchBoxVisible.chkClear) { searchText = ""; workspace.clearMarkerLayer_find; }} 
			
			import core.thread.fiber; 
			static class SearchFiber : Fiber
			{
				mixin SmartChild!
				(
					q{
						Module[] modules, 
						string searchText,
						Container.SearchOptions searchOptions,
						Workspace.SearchBox.SearchStats* stats
					}, 
					q{super(&run, 256<<10/+measured stack: level 84, 24K+/); }
				); 
				
				DateTime timeLimit; 
				
				private void run()
				{
					foreach(m; modules)
					{
						m.search(
							searchText, searchOptions, vec2(0), 
							((sr){
								m.findSearchResults ~= sr; 
								if(stats)
								{ stats.process(sr); }
							}), &timeLimit
						); 
						static if((常!(bool)(0))) if(stats) print((*stats).toJson); 
					}
				} 
			} 
			SearchFiber searchFiber; 
			
			void updateSearchFiber()
			{
				if(searchFiber && !searchBoxVisible) { searchFiber.free; }
				
				if(searchFiber)
				{
					if(searchFiber.state==Fiber.State.TERM) searchFiber.free; 
					else {
						searchFiber.timeLimit = now + 10*milli(second); 
						searchFiber.call; 
					}
				}
			} 
			
			static struct SearchStats
			{
				uint count; 
				uint[string] matches, wholeWords; 
				uint[SyntaxKind] syntaxes; 
				
				void process(in .Container.SearchResult sr)
				{
					static searchResultInfo(in .Container.SearchResult sr)
					{
						struct Res { string match, wholeWord; SyntaxKind syntax; } Res res; 
						if(auto cntr = (cast(.Container)(sr.container)))
						if(const len = (cast(int)(sr.cells.length)))
						{
							const idx = cntr.subCells.countUntil(mixin(指(q{sr.cells},q{0}))); 
							if(idx>=0)
							{
								auto 	glyphs 	= cntr.subCells.map!((a)=>((cast(Glyph)(a)))),
									chars 	= glyphs.map!((g)=>(((g)?(g.ch):(compoundObjectChar)))); 
								
								auto match = chars[idx .. idx+len].text; 
								res.match = match; 
								
								static isW(dchar ch) => isDLangIdentifierCont(ch); 
								if(isW(mixin(指(q{chars},q{idx})))/+Note: extend start+/)
								mixin("chars[0..idx]").retro.until!(not!isW)
								.each!((a){ match = a.text ~ match; }); if(isW(mixin(指(q{chars},q{idx+len-1})))/+Note: extend end+/)
								chars[idx+len..$].until!(not!isW)
								.each!((a){ match ~= a.text; }); 
								res.wholeWord = match; 
								/+Todo: Fix niceExpression mixin() subscript range indexing. After the mixin Declaration works.+/
								
								if(auto g = (mixin(指(q{glyphs},q{idx})))) res.syntax = (cast(SyntaxKind)(g.syntax)); 
							}
						}
						
						if(res.wholeWord=="") {
							print(res.toJson); 
							print(sr); 
							print((cast(CodeRow)(sr.container))); 
						}
						return res; 
					} 
					
					with(searchResultInfo(sr))
					{
						this.count++; 
						mixin(指(q{this.matches},q{match}))++; 
						mixin(指(q{this.wholeWords},q{wholeWord}))++; 
						mixin(指(q{this.syntaxes},q{syntax}))++; 
						/+Todo: Fix niceExpression mixin() subscript range indexing.+/
					}
				} 
			} 
			SearchStats searchStats; 
			
			
			void UI_searchBox(Workspace workspace, View2D view, bool justActivated)
			{
				with(im)
				{
					Column(
						{
							//Keyboard shortcuts
							auto 	kcFindZoom	= KeyCombo("Enter"), //only when edit is focused
								kcFindToSelection 	= KeyCombo("Ctrl+Shift+L Alt+Enter"),
								kcFindClose	= KeyCombo("Esc"); //always
							
							void sw() { outerWidth = fh*22; } 
							
							Row(
								{
									sw; 
									Text("Find "); 
									.Container editContainer; 
									
									const searcHash = searchText.hashOf(searchOptions.hashOf([lookInAllModules].hashOf)); 
									static size_t lastSearchHash; //Todo: static is ugly. It's a workspace property
									const searchHashChanged = lastSearchHash.chkSet(searcHash); 
									
									
									if(
										Edit(searchText, ((justActivated).genericArg!q{focusEnter}), { flex = 1; editContainer = actContainer; })
										|| justActivated || searchHashChanged
									)
									{
										//refresh search results
										workspace.clearMarkerLayer_find; 
										searchStats = SearchStats.init; 
										
										if(searchText.startsWith(':'))
										{
											//goto line
											//Todo: Ctrl+G not works inside Edit
											//Todo: Ctrl+F not works inside Edit
											/+
												Todo: hint text: Enter line number. 
												Negative line number starts from the end of the module.
											+/
											//Todo: ez ugorhatna regionra is.
											
											workspace.textSelections = []; 
											if(auto mod = workspace.expectOneSelectedModule)
											if(auto line = searchText[1..$].to!int.ifThrown(0))
											{
												workspace.jumpTo(format!"%s%s(%d,1)"(CodeLocationPrefix, mod.file.fullName, line)); 
												//Todo: show a highlight on that row...
											}
											
										}
										else
										{
											auto mods = lookInAllModules ? workspace.modules : workspace.selectedModules; 
											if(mods.empty && lookInAllModules.chkSet) { mods = workspace.modules; }
											searchFiber = new SearchFiber(mods, searchText, searchOptions, &searchStats); 
											/+Note: the old searchFiber stops because it loses all references and will not be called again.+/
										}
									}
									//display the number of matches. Also save the location of that number on the screen.
									const matchCnt = workspace.getMarkerLayerCount(DMDMessage.Type.find); 
									Row({ if(matchCnt) Text(" ", clGray, matchCnt.text, " "); }); 
									
									BtnRow(
										{
											if(
												Btn(
													"🔍", isFocused(editContainer) ? kcFindZoom : KeyCombo(""),
													enable(matchCnt>0), hint("Zoom screen on search results.")
												)
											)
											{ workspace.zoomAt(view, workspace.getMarkerLayer_find); }
											if(
												Btn(
													"Sel", isFocused(editContainer) ? kcFindToSelection : KeyCombo(""),
													enable(matchCnt>0), hint("Select search results.")
												)
											)
											{ workspace.selectSearchResults(workspace.getMarkerLayer_find); }
										}
									); 
									
									BtnRow(
										{
											if(
												Btn(
													"aA", hint("Case Sensitive"),
													selected(searchOptions.caseSensitive)
												)
											) searchOptions.caseSensitive.toggle; 
											if(
												Btn(
													"ww", hint("Whole Words"),
													selected(searchOptions.wholeWords)
												)
											) searchOptions.wholeWords_toggle; 
											if(
												Btn(
													"all", hint("All modules"),
													selected(lookInAllModules)
												)
											) lookInAllModules.toggle; 
										}
									); 
									
									if(
										Btn(
											"⚙", hint("Advanced search options"),
											selected(advancedSearchOptionsVisible)
										)
									) advancedSearchOptionsVisible.toggle; 
									
									if(
										Btn(
											bold(symbol("ChevronRight")), { innerWidth = fh; }, 
											kcFindClose, hint("Close panel.")
										)
									)
									{ deactivate(workspace); }
								}
							); 
							
							if(advancedSearchOptionsVisible)
							{
								Column(
									{
										sw; 
										Grp!Row("Boundary conditions", { sw; Text("start: "); BtnRow(searchOptions.boundaryTypeStart, (("st").genericArg!q{id})); Text(" end: "); BtnRow(searchOptions.boundaryTypeEnd, (("en").genericArg!q{id})); }); 
										Grp!Row(
											"Syntaxes: ", {
												sw; foreach(const a; searchStats.syntaxes.byKeyValue.array.sort!"a.value>b.value")
												{
													Btn(
														i"$(a.value)× ".text, {
															style.fontColor = syntaxFontColor(a.key); 
															style.bkColor = syntaxBkColor(a.key); 
															Text(a.key.text); 
														}, ((a.key).genericArg!q{id})
													); 
												}
											}
										); 
										Grp!Row(
											"Words: ", {
												sw; foreach(const a; searchStats.wholeWords.byKeyValue.array.sort!"a.value>b.value".take(30))
												{ Btn(i"$(a.value)× $(a.key)".text, ((a.key).genericArg!q{id})); }
											}
										); 
									}
								); 
							}
						}
					); 
				}
				
			} 
			
			bool UI(Workspace workspace, View2D view)
			{
				with(im)
				{
					{
						bool justActivated; 
						if(searchBoxActivate_request.chkClear)
						{ searchBoxVisible = justActivated = true; }
						
						if(searchBoxVisible)
						{ UI_searchBox(workspace, view, justActivated); }
						
						return searchBoxVisible; 
					}
				}
			} 
		} 
	}version(/+$DIDE_REGION+/all)
	{
		@STORED Outline outline; 
		static struct Outline
		{
			bool activateRequest; 
			@STORED
			{
				bool visible, setupVisible; 
				string searchText; 
				string extensions = "d di glsl comp"; 
				
				
				@property string rootPaths() const
				=> (cast()(this)).treeView.root.subNodes.filter!((a)=>(a.isPath)).map!((a)=>(a.asPath.fullPath)).join(';'); 
				@property rootPaths(string s)
				{ foreach(p; s.splitter(';').map!Path) addRootPath(p); } 
			} 
			
			version(/+$DIDE_REGION Manage treeView instance+/all)
			{
				alias TreeView = VirtualTreeView!DirNode; 
				private TreeView _treeView; 
				
				
				
				auto treeView()
				{
					if(!_treeView)
					{
						_treeView = new TreeView; 
						with(_treeView)
						{
							showBullet = false; showRoot = false; 
							root = DirNode(Path.init); root.open; 
						}
					}
					return _treeView; 
				} 
				
				auto indexOfRootPath(Path p)
				=> treeView.root.subNodes.map!((a)=>(a.asPath)).countUntil(p); 
				
				void addRootPath(Path p)
				{
					if(p && p.exists)
					{
						p = p.actualPath; 
						if(indexOfRootPath(p)<0)
						with(treeView.root)
						{
							subNodes ~= DirNode(p); 
							subNodes = subNodes.sort!((a, b)=>(a.asPath < b.asPath)).array; 
							treeView.changed = now; 
						}
					}
				} 
				
				void removeRootPath(Path p)
				{
					const idx = indexOfRootPath(p); 
					if(idx>=0)
					with(treeView.root)
					{
						subNodes = subNodes.remove(idx); 
						treeView.changed = now; 
					}
				} 
				
				string lastExtensions; 
				void updateTreeView()
				{
					if(lastExtensions.chkSet(extensions))
					DirNode.pattern = extensions.splitter(' ').map!"`*.`~a".join(';'); 
				} 
			}
			
			void activate()
			{ activateRequest = true; } 
			
			void deactivate()
			{ if(visible.chkClear) { searchText = ""; }} 
			
			DirNode* focusedNode; 
			
			bool UI(Workspace workspace, View2D view)
			{
				with(im)
				{
					{
						bool justActivated; 
						if(activateRequest.chkClear)
						{ visible = justActivated = true; }
						
						if(visible)
						{ UI_outlinePanel(workspace, view, justActivated); }
						
						return visible; 
					}
				}
			} 
			
			
			static struct DirNode
			{
				import std.sumtype; 
				SumType!(File, Path) _node; 
				
				bool opened; 
				DirNode[] subNodes; 
				
				__gshared string rootPaths, pattern="*"; /+Todo: It's lame, but there is only a single workspace.+/
				
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
					return _node.match!
					(
						((Path p){
							if(p)
							{
								subNodes = chain(
									p.paths.filter!((a)=>(
										!a.name.startsWith('.')
										/+exclude ".git" and alike+/
									))	.map!DirNode, 
									p.files(pattern)	.map!DirNode
								).array; 
							}
							else
							{/+Do nothing. root paths are managed from the outside.+/}
							return subNodes; 
						}), 
						((File f)=>(null))
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
					subNodes = []; 
				} 	 void toggle()
				{
					if(opened)	close; 
					else	open; 
				} 
				
				void UI(void delegate() fun=null)
				{
					with(im)
					{
						void Img(string s) { Spacer(4); im.Img(`icon:\`~s~`&small`); Spacer(4); } 
						_node.match!
						(
							((in File  f){ Img('.'~f.ext); if(fun) fun(); Text(f.name); }), 
							((in Path p){ Img(((p.fullPath.isWild("?:")) ?(p.fullPath):(`folder`))~'\\'); if(fun) fun(); Text(bold(p.name)); })
						); 
					}
				} 
			} 
			void UI_outlinePanel(Workspace workspace, View2D view, bool justActivated)
			{
				with(im)
				{
					Column
					(
						{
							//Keyboard shortcuts
							auto 	kcOutlineZoom	= KeyCombo("Enter"), //only when edit is focused
								kcOutlineClose	= KeyCombo("Esc"); //always
							
							void sw() { outerWidth = fh*16; } 
							
							Row(
								{
									sw; Text("Outline"); .Container editContainer; 
									
									const searcHash = searchText.hashOf; 
									static size_t lastSearchHash; //Todo: static is ugly. It's a workspace property
									const searchHashChanged = lastSearchHash.chkSet(searcHash); 
									
									
									if(
										Edit(searchText, ((justActivated).genericArg!q{focusEnter}), { flex = 1; editContainer = actContainer; })
										|| justActivated || searchHashChanged
									)
									{ NOTIMPL; }
									
									BtnRow(
										{
											if(Btn("⚙", hint("Setup"), selected(setupVisible)))
											setupVisible.toggle; 
										}
									); 
									
									if(
										Btn(
											bold(symbol("ChevronRight")), { innerWidth = fh; }, 
											kcOutlineClose, hint("Close panel.")
										)
									)
									{ deactivate; }
								}
							); 
							
							updateTreeView; 
							
							const treeIsEmpty = treeView.root.subNodes.empty; 
							
							if(treeIsEmpty) setupVisible = true; 
							
							if(setupVisible)
							{
								Row(
									{
										sw; Text("Exts: "); 
										Edit(extensions, { flex = 1; }); 
									}
								); 
								Row(
									{
										sw; Text("Paths: "); 
										if(Btn("Add", selected(treeIsEmpty ? blink>.5f : false)))
										{
											static Path lastPath; 
											auto p = browseForFolder(mainWindow.hwnd, "Add path to Outline.", lastPath); 
											if(p) { lastPath = p; addRootPath(p); }
										}
										
										const canRemove = 	focusedNode && focusedNode.isPath && 
											indexOfRootPath(focusedNode.asPath)>=0; 
										if(Btn("Remove", enable(canRemove)))
										{
											removeRootPath(focusedNode.asPath); 
											focusedNode = null; 
										}
									}
								); 
							}
							
							
							actContainer.measure; 
							const treeHeight = mainWindow.clientHeight - outerHeight - 50; /+Todo: fucking lame. Fix aligning engine.+/
							
							treeView.UI
							(
								{
									sw; outerHeight = treeHeight; 
									/+Bug: When lots of items in the tree, moving the window by mouse become fucking slow. <1FPS 🤬 -> bitmaps()+/
								},
								((DirNode* n) {
									const 	isFile = n.isFile, 
										isPath = n.isPath,
									fullName = 	isFile 	? n.asFile.fullName : 
										isPath 	? n.asPath.fullPath : ""; 
									auto ws = workspace; 
									Module mod; if(isFile && fullName!="")
									mod = ws.findModule(fullName.File/+Opt: this is a slow query+/); 
									const canSelectModules = ws.textSelections.empty /+Only synch module selection when no text selected.+/; 
									
									if(
										WhiteBtn
										(
											{
												border.width = 0; padding = "0 4 0 0"; margin = "0"; 
												if(mod && mod.flags.selected) style.bkColor = bkColor = mix(bkColor, clAccent, .25f); 
												n.UI(
													{
														if(isFile)
														{
															float spc = 1; 
															if(mod)	{ Led(true, ((mod.changed)?(clYellow):(clLime))); spc -= .7; }
															
															/+Todo: not works -> Spacer(spc); +/
															Text(' '); actContainer.subCells.back.outerWidth = fh*spc; 
														}
													}
												); 
												if(auto img = (cast(.Img)(actContainer.subCells.frontOrNull)))
												{
													img.flags.clickable = false; 
													img.bkColor = bkColor; 
												}
											}, 
											((n.identityStr).genericArg!q{id}), selected(focusedNode==n)
										)
									)
									{
										version(/+$DIDE_REGION onClick+/all)
										{
											focusedNode=n; 
											
											auto matchingModules(string prefix)
											{
												auto p = prefix.lc; 
												return ws.modules.filter!((m)=>(m.file.fullName.map!toLower.startsWith(p))).cache; 
											} 
											
											auto calcBounds(A)(A a)
											=> a.map!((m)=>(m.outerBounds)).fold!"a|b"(bounds2.init); 
											
											void jumpTo(string prefix, bool doZoom=false)
											{
												if(const bnd = calcBounds(matchingModules(prefix)))
												{
													addInspectorParticle(bnd, clWhite, bounds2(bnd.center, ((1).genericArg!q{radius})), .125f); 
													
													with(view)
													{
														if(doZoom)	{ scrollZoomIn(bnd); }
														else	{ scrollZoom(bnd); }
													}
												}
											} 
											
											version(/+$DIDE_REGION Detect doubleClick+/all)
											{ static string lastFullName; static DateTime lastClickTime; /+Todo: nasty static+/}
											
											
											if(fullName!="")
											{
												const isDoubleClick = lastFullName==fullName && now-lastClickTime < 0.4*second; 
												lastClickTime = now; 	lastFullName = fullName; 
												
												if(isFile && isDoubleClick && !mod)
												{
													const f = fullName.File; 
													ws.loadModule(f); 
													if(inputs.Alt.down)
													ws.queueModuleRecursive(f); 
												}else { jumpTo(fullName, isDoubleClick); }
												
												if(canSelectModules)
												{
													foreach(m; ws.modules) m.flags.selected = false; 
													foreach(m; matchingModules(fullName)) m.flags.selected = true; 
												}
											}
										}
									}
								})
							); 
						}
					); 
				}
				
			} 
		} 
	}version(/+$DIDE_REGION+/all)
	{
		@STORED Insight insight; 
		
		void onInsightClick(DDB.PathNode* node)
		{
			with(insight)
			{
				auto ws = this; 
				
				auto actTreeView() => searchText=="" ? treeView : resultTreeView; 
				auto getParent() => actTreeView.getParentItem(node); 
				
				void type(bool advanced=false)
				{
					if(!ws.textSelections.empty)
					{
						auto s = node.name, pasted = false; 
						void pasteText(string s) { ws.pasteText(s); pasted = true; } 
						void pasteNode(string s) { ws.insertNode(s); pasted = true; } 
						
						if(advanced)
						{
							if(auto member = node.asMember)
							if(member.category==DDB.ModuleDeclarations.Member.Category.enum_member)
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
								auto m = ws.findModule(f); 
								if(!m) { ws.loadModule(f);  m = ws.findModule(f); }
								if(m) {
									if(!line) ws.jumpTo(m); 
									else {
										import het.parser : CodeLocation; 
										ws.jumpTo(CodeLocation(f.fullName, line.max(1), col.max(1))); 
									}
								}
								else { im.flashWarning("Can't load module: "~f.quoted('`')); }
							}
							else { im.flashWarning("File not found: "~f.quoted('`')); }
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
		} 
	}version(/+$DIDE_REGION Location/Clipbrd slots+/all)
	{
		struct Location
		{
			vec2 origin = vec2(0); 
			float zoomFactor = 1; 
		} 
		
		@STORED Location[10] storedLocations; 
		
		void enforceLocationIndex(int n)
		{
			enforce(
				n.inRange(storedLocations),
				n.format!"Location index out of range: %s"
			); 
		} 
		
		void storeLocation(int n)
		{
			enforceLocationIndex(n); 
			with(storedLocations[n])
			{
				origin	= mainView.origin.vec2,
				zoomFactor 	= mainView.scale; 
			}
			im.flashInfo(n.format!"Location %s stored."); 
		} 
		
		void jumpToLocation(int n)
		{
			enforceLocationIndex(n); 
			if(storedLocations[n] == Location.init)
			{
				im.flashWarning(n.format!"Location %s is uninitialized."); 
				return; 
			}
			with(storedLocations[n])
			{
				mainView.origin	= origin.dvec2,
				mainView.scale 	= zoomFactor; 
			}
		} 
		
		@STORED string[10] storedMemSlots; 
		
		void enforceMemSlotIndex(int n)
		{
			enforce(
				n.inRange(storedMemSlots),
				n.format!"MemSlot index out of range: %s"
			); 
		} 
		
		void copyMemSlot(int n)
		{
			enforceMemSlotIndex(n); 
			auto s = textSelections.sourceText; 
			storedMemSlots[n] = s; 
			im.flashInfo(format!"MemSlot %s %s."(n, s.empty ? "cleared" : "stored")); 
		} 
		
		void pasteMemSlot(int n)
		{
			enforceMemSlotIndex(n); 
			if(storedMemSlots[n].empty)
			{
				im.flashWarning(n.format!"MemSlot %s is empty."); 
				return; 
			}
			textSelections = paste_impl(textSelections, storedMemSlots[n]); 
		} 
		
	}version(/+$DIDE_REGION Refactor+/all)
	{
		void visitSelectedNestedCodeColumns(void delegate(CodeColumn) fun)
		{
			foreach_reverse(col; selectedOuterColumns)
			visitNestedCodeColumns(col, fun); 
		} 
		
		void visitSelectedNestedCodeNodes(void delegate(CodeNode) fun)
		{
			foreach_reverse(col; selectedOuterColumns)
			visitNestedCodeNodes(col, fun); 
		} 
		
		void visitSelectedNestedDeclarations(void delegate(Declaration) fun)
		{ visitSelectedNestedCodeNodes((node){ if(auto decl = cast(Declaration) node) fun(decl); }); } 
		
		
		enum syntaxCheckTempFile = File(`z:\temp\__syntax.d`); //Todo: to settings!
		
		void syntaxCheck(File moduleFile, string source, int lineIdx=1)
		{
			{
				/+
					Todo: The error can be in another imported module too, not just this module. 
					But the error file is wrongly renamed to this file.
				+/
				
				static bool[string] simpleValids; 
				if(simpleValids.empty)
				["{}", "q{}", "[]", "()", "``", "''", `""`].each!((s){ simpleValids[s]=true; }); 
				
				if(source in simpleValids) return; 
			}
			
			auto f = syntaxCheckTempFile; 
			f.write(format!"#line %d\nversion(none):%s"(max(lineIdx, 1), source)); 
			auto cmd = ["ldc2", "-c", "-o-", "-vcolumns", "-verrors-context", f.fullName]; 
			auto ex = executeShell(cmd.joinCommandLine, null, ExecuteConfig.suppressConsole); 
			f.remove; 
			if(ex.status!=0)
			{
				string output = ex.output; 
				
				{
					//replace filenames
					const fOld = f.fullName.toLower~"("; 
					const fNew = moduleFile.fullName~"("; 
					output = output	.splitLines
						.map!(s=>((s.map!toLower.startsWith(fOld)) ?(fNew~s[fOld.length..$]) :(s)))
						.filter!(s=>!s.endsWith("): Error: declaration expected, not `module`"))
						.join('\n'); 
					//LOG(output); 
				}
				
				assert(buildServices.ready); 
				auto messages = decodeDMDMessages(output, moduleFile); 
				processBuildMessages(messages); 
				
				const errIdx = messages.countUntil!((m)=>(m.type==DMDMessage.Type.error)); 
				if(errIdx>0)
				raise(messages[errIdx].oneLineText); 
			}
		} 
		
		void syntaxCheck(string source, int lineIdx=1)
		{ syntaxCheck(File(`c:\$unknown$.d`), source, lineIdx); } 
		
		CodeNode[] editedBreadcrumbNodes(CodeNode rootNode)
		{
			CodeNode[] res; 
			bool[CodeNode] added; 
			void visit(CodeNode node)
			{
				if(!node) return; 
				//visit all [changed] and collect the [edited] ones.
				//Forward order, root nodes at the front.
				if(!node.changed) return; 
				bool anyColEdited = node.subColumns.map!(a=>a.edited).any; 
				if(anyColEdited)
				{
					if(auto n = node.nearestDeclarationBlock)
					if(n !in added)
					{
						res ~= n; 
						added[n]=true; 
					}
				}
				foreach(col; node.subColumns.filter!(a=>a && a.changed))
				{
					anyColEdited |= col.edited; 
					foreach(row; col.rows.filter!(a=>a && a.changed))
					foreach(
						subNode; row.subCells	.map!(a=>cast(CodeNode)a)
							.filter!(a=>a && a.changed)
					)
					visit(subNode); 
				}
			} 
			
			visit(rootNode); 
			if(res.length<=1) return res; 
			
			res = res.retro.array; 
			//root is at the end of list.
			//filter redundant leafs
			const len = res.length.to!int; 
			foreach(i; 0..len-1)
			inner: foreach(j; i+1..len)
			if(res[i].allParents!CodeNode.canFind(res[j]))
			{ res[i] = null;  break inner; }
			
			res = res.filter!"a".array; 
			
			return res; 
		} 
		
		void feedChangedModule(Module mod, Flag!"syntaxCheck" enableSyntaxCheck = Yes.syntaxCheck)
		{
			if(!mod) return; 
			if(!mod.changed) return; 
			if(!mod.isManaged) return; 
			enforce(buildServices.ready, "BuildSystem is currently working."); 
			
			//reset all caches in Module
			mod.resetBuildMessages; 
			mod.resetSearchResults; 
			firstErrorMessageArrived = true; 
			
			void feedNode(CodeNode oldNode)
			{
				oldNode.enforce("Unable to reach node."); 
				auto mod = (cast(Module)(oldNode)); 
				if(!mod) mod = moduleOf(oldNode); 
				mod.enforce("Unable to reach module."); 
				enforce(!mod.isReadOnly, "Module is readonly"); 
				enforce(mod.isManaged, "Module Structure Level must be Managed."); 
				
				const source = oldNode.sourceText; 
				
				if(enableSyntaxCheck) syntaxCheck(mod.file, source, oldNode.lineIdx); 
				auto newCol = new CodeColumn(mod, source, TextFormat.managed_block); 
				
				if(mod is oldNode)
				{
					mod.content.setParent = null; 
					mod.content = newCol; 
					mod.content.setParent = mod; //Todo: Safe parent/child reowning system.
					
					mod.setChanged; 
					mod.measure;  //this will rebuild subCells
				}
				else
				{
					//reload an internal structured object only.
					auto newNode = newCol.extractSingleNode; 
					
					enforce(
						typeid(oldNode)==typeid(newNode), 
						format!"Node typeid mismatch (old:%s, new:%s)"(typeid(oldNode), typeid(newNode))
					); 
					
					auto row = (cast(CodeRow)(oldNode.parent)).enforce("Can't get Node's Row"); 
					const charIdx = row.subCells.countUntil(oldNode); enforce(charIdx>=0, "Can't find Node in Row."); 
					
					oldNode.setParent = null; 
					newNode.setParent(row); 
					row.subCells[charIdx] = newNode; 
					
					row.setChanged; 
					row.measure; //this will rebuild subCells
					row.refreshTabIdx; 
					row.spreadElasticNeedMeasure; 
				}
			} 
			
			foreach(n; editedBreadcrumbNodes(mod)) feedNode(n); 
		} 
		
		void feedAndSaveModules(R)(R modules, Flag!"syntaxCheck" syntaxCheck = Yes.syntaxCheck)
		{
			preserveTextSelections(
				{
					modules.each!((m){ feedChangedModule(m, syntaxCheck); }); 
					modules.each!"a.save"; 
				}
			); 
		} 
		
		void declarationStatistics_impl()
		{
			auto files = dirPerS(Path(`c:\d\libs`), "*.d").files.map!"a.file".array; 
			//auto files = [File(`c:\d\libs\het\test\testTokenizerData\CompilerTester.d`)];
			dDeclarationRecords.clear; 
			foreach(i, f; files)
			{
				try
				{
					print(i, files.length, dDeclarationRecords.length, f); 
					auto m = scoped!Module(this, f, StructureLevel.structured); 
					if(m.isStructured) { m.content.processHighLevelPatterns_block; }else { print("Is not structured"); beep; }
				}
				catch(Exception e)
				{ WARN(e.simpleMsg); }
			}
			const fnOut = `c:\D\projects\DIDE\DLangStatistics\dDeclarationRecords.json`; 
			dDeclarationRecords.toJson.saveTo(fnOut); 
			print("DONE. DeclarationStatistics written to:", fnOut); 
			
			/+
				Todo: implement identifier qString  
									 File(`c:\D\ldc2\import\std\json.d`)
									 File(`c:\D\ldc2\import\std\xml.d`)
									 File(`c:\D\ldc-master\tools\ldc-prune-cache.d`) Invalid block closing token
								bad tokenString, not my bad...
									 File(`c:\D\ldc-master\dmd\iasmgcc.d`)
									 File(`c:\D\ldc-master\dmd\mars.d`) Invalid block closing token 
			+/
		} 
		
		void UI_refactor()
		{
			void debugLineIndices()
			{
				void visit(Container cntr, int level=0)
				{
					/+
						if(auto r = cast(CodeRow) cntr) if(r.lineIdx) print(r.lineIdx.format!"%5d", " ".replicate(level), r); 
						
						foreach(c; cntr.subCells)
						{
							c.castSwitch!(
								(Glyph g){ if(g.lineIdx) print(g.lineIdx.format!"%5d", " ".replicate(level), g); },
								(Container c){ visit(c, level+1); },
								(Cell c){}
							); 
						}
					+/
					
				} 
				
				if(auto mod = singleSelectedModule)
				{
					auto locator = LineIdxLocator(3050); 
					
					locator.visitNode(mod); 
					
					print("searchResults:", locator.searchResults); 
				}
			} 
			
			with(im)
			{
				Grp!Row(
					"Vertical Tabs in CodeColumns (␋)", 
					{
						if(KeyBtn("", "Add")) realignVerticalTabs; 
						if(KeyBtn("", "Remove")) removeVerticalTabs; 
					}
				); 
				
				Grp!Row(
					"Internal NewLines in Declarations (␊)",
					{
						if(KeyBtn("", "Add")) addInternalNewLines; 
						if(KeyBtn("", "Remove")) removeInternalNewLines; 
					}
				); 
				
				
				Grp!Row(
					"Statistics",
					{
						if(KeyBtn("", "Declaration Statistics of all D codebase")) declarationStatistics; 
						if(KeyBtn("", "Debug line indices")) debugLineIndices; 
					}
				); 
				
			}
		} 
		void selectAdjacentWord_impl(bool isPrev)()
		{
			auto ts = textSelections; ref actSel() => isPrev ? ts.front : ts.back; 
			if(!ts.empty && !actSel.isZeroLength)
			{
				if(auto mod = actSel.moduleOf)
				{
					import std.algorithm : cmp; 
					auto dissect(TextSelection s)
					=> s.start.toReference.text.splitter('|').enumerate.map!((a)=>(((a.index)?(a.value[1..$].to!uint) :(a.value.xxh32)))); 
					
					auto srs = mod	.search(actSel.sourceText, mod.worldInnerPos, Yes.caseSensitive, Yes.wholeWords)
						.map!((sr)=>(searchResultToTextSelection(sr)))
						.filter!((ts)=>(ts.valid && ts.codeColumn.isPartOfSourceCode)).array; 
					static if(isPrev) srs = srs.retro.array; 
					auto act = dissect(actSel); 
					const idx = srs.countUntil!((a)=>(cmp(act, dissect(a))*((isPrev)?(-1):(1))<0)); 
					if(idx.inRange(srs))
					{
						auto newSel = srs[idx]; 
						textSelections = ((isPrev)?(newSel~ts):(ts~newSel)); 
						addInspectorParticle(newSel.worldBounds, clWhite, actSel.worldBounds); 
					}
					else
					im.flashWarning("No more matches."); 
					
					//Todo: must not select text inside error messages!
					
					return; 
				}
			}
			
			//When there is no selection, try to make it from the hovered keyword
			if(!actSearchKeywordSelection.isZeroLength)
			{
				textSelections = [actSearchKeywordSelection]; 
				addInspectorParticle(actSearchKeywordSelection.worldBounds, clWhite, bounds2.init); 
			}
			else im.flashWarning("Nothing to select."); 
		} 
	}
	version(/+$DIDE_REGION Keyboard    +/all)
	{
		@property SEL() => !textSelections.empty; @property NOSEL() => !SEL; 
		version(/+$DIDE_REGION Scroll and zoom view+/all)
		{
			version(/+$DIDE_REGION Press          +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Ctrl+Up"},q{scrollLineUp},q{scrollV(DefaultFontHeight); }],
						[q{"Ctrl+Down"},q{scrollLineDown},q{scrollV(-DefaultFontHeight); }],
						[q{"Alt+PgUp"},q{scrollPageUp},q{scrollV(mainWindow.clientHeight*.9); }],
						[q{"Alt+PgDn"},q{scrollPageDown},q{scrollV(-mainWindow.clientHeight*.9); }],
						[q{"Ctrl+="},q{zoomIn},q{zoom (.5); }],
						[q{"Ctrl+-"},q{zoomOut},q{zoom (-.5); }],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Conflicts with stored location slots+/none)
			{
				version(/+$DIDE_REGION Hold          +/all)
				{
					mixin((
						(表([
							[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
							[q{"Ctrl+Alt+Num8"},q{holdScrollUp},q{scrollV(scrollSpeed); }],
							[q{"Ctrl+Alt+Num2"},q{holdScrollDown},q{scrollV(-scrollSpeed); }],
							[q{"Ctrl+Alt+Num4"},q{holdScrollLeft},q{scrollH(scrollSpeed); }],
							[q{"Ctrl+Alt+Num6"},q{holdScrollRight},q{scrollH(-scrollSpeed); }],
							[q{"Ctrl+Alt+Num+"},q{holdZoomIn},q{zoom (zoomSpeed); }],
							[q{"Ctrl+Alt+Num-"},q{holdZoomOut},q{zoom (-zoomSpeed); }],
							[],
							[],
							[],
							[],
						]))
					) .GEN!q{GEN_verbs(Yes.hold)}); 
				}version(/+$DIDE_REGION Hold slow      +/all)
				{
					mixin((
						(表([
							[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
							[q{"Ctrl+Alt+Num8"},q{holdScrollUp_slow},q{scrollV(scrollSpeed/8); }],
							[q{"Ctrl+Alt+Num2"},q{holdScrollDown_slow},q{scrollV(-scrollSpeed/8); }],
							[q{"Ctrl+Alt+Num4"},q{holdScrollLeft_slow},q{scrollH(scrollSpeed/8); }],
							[q{"Ctrl+Alt+Num6"},q{holdScrollRight_slow},q{scrollH(-scrollSpeed/8); }],
							[q{"Ctrl+Alt+Num+"},q{holdZoomIn_slow},q{zoom (zoomSpeed/8); }],
							[q{"Ctrl+Alt+Num-"},q{holdZoomOut_slow},q{zoom (-zoomSpeed/8); }],
							[q{/+
								Note: No keys for this. 
								Ctrl+Alt+Num is used for normal speed scrolling.
							+/}],
						]))
					) .GEN!q{GEN_verbs(Yes.hold)}); 
				}
			}
			version(/+$DIDE_REGION Hold NoSel   +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{//Navigation when there is no textSelection
						}],
						[],
						[],
						[q{"W Num8 Up"},q{holdScrollUp2},q{if(NOSEL) scrollV(scrollSpeed); }],
						[q{"S Num2 Down"},q{holdScrollDown2},q{if(NOSEL) scrollV(-scrollSpeed); }],
						[q{"A Num4 Left"},q{holdScrollLeft2},q{if(NOSEL) scrollH(scrollSpeed); }],
						[q{"D Num6 Right"},q{holdScrollRight2},q{if(NOSEL) scrollH(-scrollSpeed); }],
						[q{"E Num+ PgUp"},q{holdZoomIn2},q{if(NOSEL) zoom (zoomSpeed); }],
						[q{"Q Num- PgDn"},q{holdZoomOut2},q{if(NOSEL) zoom (-zoomSpeed); }],
					]))
				) .GEN!q{GEN_verbs(Yes.hold)}); 
			}version(/+$DIDE_REGION hold slow NoSel+/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{/+
							Bug: When NumLockState=true && key==Num8: if the modifier is released
							after the key, KeyCombo will NEVER detect the release and is stuck!!!
						+/}],
						[q{"Shift+W Shift+Up"},q{holdScrollUp_slow2},q{if(NOSEL) scrollV(scrollSpeed/8); }],
						[q{"Shift+S Shift+Down"},q{holdScrollDown_slow2},q{if(NOSEL) scrollV(-scrollSpeed/8); }],
						[q{"Shift+A Shift+Left"},q{holdScrollLeft_slow2},q{if(NOSEL) scrollH(scrollSpeed/8); }],
						[q{"Shift+D Shift+Right"},q{holdScrollRight_slow2},q{if(NOSEL) scrollH(-scrollSpeed/8); }],
						[q{"Shift+E Shift+PgUp"},q{holdZoomIn_slow2},q{if(NOSEL) zoom (zoomSpeed/8); }],
						[q{"Shift+Q Shift+PgDn"},q{holdZoomOut_slow2},q{if(NOSEL) zoom (-zoomSpeed/8); }],
					]))
				) .GEN!q{GEN_verbs(Yes.hold)}); 
			}
			version(/+$DIDE_REGION ZoomAll/Close          +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Home"},q{zoomAll2},q{if(NOSEL) scrollInAllModules; }],
						[q{"Alt+Home"},q{zoomClose2},q{
							mainView.scale = 1; 
							
							if(primaryCaret.valid)
							mainView.origin = primaryCaret.worldBounds.center.dvec2; 
						}],
						[],
					]))
				) .GEN!q{GEN_verbs}); 
			}
		}version(/+$DIDE_REGION+/all)
		{
			version(/+$DIDE_REGION Cursor  movement+/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Left"},q{cursorLeft(bool sel=false)},q{cursorOp(ivec2(-1, 0), sel); }],
						[q{"Right"},q{cursorRight(bool sel=false)},q{cursorOp(ivec2(1, 0), sel); }],
						[],
						[q{"Ctrl+Left"},q{cursorWordLeft(bool sel=false)},q{cursorOp(ivec2(TextCursor.wordLeft, 0), sel, true); }],
						[q{"Ctrl+Right"},q{cursorWordRight(bool sel=false)},q{cursorOp(ivec2(TextCursor.wordRight, 0), sel, true); }],
						[],
						[q{"Home"},q{cursorHome(bool sel=false)},q{cursorOp(ivec2(TextCursor.home, 0), sel); }],
						[q{"End"},q{cursorEnd(bool sel=false)},q{cursorOp(ivec2(TextCursor.end, 0), sel); }],
						[q{"Up"},q{cursorUp(bool sel=false)},q{cursorOp(ivec2(0,-1), sel); }],
						[q{"Down"},q{cursorDown(bool sel=false)},q{cursorOp(ivec2(0, 1), sel); }],
						[],
						[q{"PgUp"},q{cursorPageUp(bool sel=false)},q{cursorOp(ivec2(0,-pageSize), sel); }],
						[q{"PgDn"},q{cursorPageDown(bool sel=false)},q{cursorOp(ivec2(0, pageSize), sel); }],
						[q{"Ctrl+Home"},q{cursorTop(bool sel=false)},q{cursorOp(ivec2(TextCursor.home), sel); }],
						[q{"Ctrl+End"},q{cursorBottom(bool sel=false)},q{cursorOp(ivec2(TextCursor.end), sel); }],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Cursor selection+/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Shift+Left"},q{cursorLeftSelect},q{cursorLeft(true); }],
						[q{"Shift+Right"},q{cursorRightSelect},q{cursorRight(true); }],
						[],
						[q{"Shift+Ctrl+Left"},q{cursorWordLeftSelect},q{cursorWordLeft(true); }],
						[q{"Shift+Ctrl+Right"},q{cursorWordRightSelect},q{cursorWordRight(true); }],
						[],
						[q{"Shift+Home"},q{cursorHomeSelect},q{cursorHome(true); }],
						[q{"Shift+End"},q{cursorEndSelect},q{cursorEnd(true); }],
						[q{"Shift+Up Shift+Ctrl+Up"},q{cursorUpSelect},q{cursorUp(true); }],
						[q{"Shift+Down Shift+Ctrl+Down"},q{cursorDownSelect},q{cursorDown(true); }],
						[],
						[q{"Shift+PgUp"},q{cursorPageUpSelect},q{cursorPageUp(true); }],
						[q{"Shift+PgDn"},q{cursorPageDownSelect},q{cursorPageDown(true); }],
						[q{"Shift+Ctrl+Home"},q{cursorTopSelect},q{cursorTop(true); }],
						[q{"Shift+Ctrl+End"},q{cursorBottomSelect},q{cursorBottom(true); }],
						[],
						[q{"Ctrl+Alt+Up"},q{insertCursorAbove},q{insertCursor(-1); }],
						[q{"Ctrl+Alt+Down"},q{insertCursorBelow},q{insertCursor(1); }],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Cursor through blocks+/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Alt+Left"},q{cursorLeftOut(bool sel=false)},q{cursorOp(ivec2(-1, 0), sel, true); }],
						[q{"Alt+Right"},q{cursorRightOut(bool sel=false)},q{cursorOp(ivec2( 1, 0), sel, true); }],
						[q{"Ctrl+Alt+Left"},q{cursorWordLeftOut(bool sel=false)},q{cursorOp(ivec2(TextCursor.wordLeft, 0), sel, true); }],
						[q{"Ctrl+Alt+Right"},q{cursorWordRightOut(bool sel=false)},q{cursorOp(ivec2(TextCursor.wordRight, 0), sel, true); }],
						[q{"Shift+Alt+Left"},q{cursorLeftSelectOut},q{cursorLeftOut(true); }],
						[q{"Shift+Alt+Right"},q{cursorRightSelectOut},q{cursorRightOut(true); }],
						[q{"Shift+Ctrl+Alt+Left"},q{cursorWordLeftSelectOut},q{cursorWordLeftOut(true); }],
						[q{"Shift+Ctrl+Alt+Right"},q{cursorWordRightSelectOut},q{cursorWordRightOut(true); }],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION More text selection  +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Shift+Alt+Right"},q{extendSelection},q{if(!extendSelection_impl) { if(0) im.flashWarning("Unable to extend selection."); }}],
						[q{"Shift+Alt+Left"},q{shrinkSelection},q{if(!shrinkSelection_impl) { if(0) im.flashWarning("Unable to shrink selection."); }}],
						[q{"Shift+Alt+U"},q{insertCursorAtStartOfEachLineSelected},q{textSelections = insertCursorAtStartOfEachLineSelected_impl(textSelections); }],
						[q{"Shift+Alt+I"},q{insertCursorAtEndOfEachLineSelected},q{textSelections = insertCursorAtEndOfEachLineSelected_impl(textSelections); }],
						[q{"Ctrl+A"},q{selectAll},q{
							selectAll_impl; 
							//textSelections = extendAll(textSelections); 
							/+
								textSelections = modulesWithTextSelection
								.map!(m => m.content.allSelection(textSelections.any!(s => s.primary && s.moduleOf is m))).array; 
							+/
						}],
						[q{"Ctrl+Shift+A"},q{selectAllModules},q{textSelections = []; modules.each!(m => m.flags.selected = true); scrollInAllModules; }],
						[q{""},q{deselectAllModules},q{
							modules.each!(m => m.flags.selected = false); 
							//Note: left clicking on emptyness does this too.
						}],
						[q{"Esc"},q{cancelSelection},q{
							if(!im.wantKeys) cancelSelection_impl; 
							/+Todo: it closes the search box AND clears the selection too.+/
						}],
						[],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Text editing      +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Ctrl+C Ctrl+Ins"},q{copy},q{
							copy_impl(textSelections.zeroLengthSelectionsToFullRows); 
							/+
								Bug: selection.isZeroLength Ctrl+C then Ctrl+V	It breaks the line. 
								Ez megjegyzi, hogy volt-e selection extension es	ha igen, akkor sorokon dolgozik. 
								A sorokon dolgozas feltetele az, hogy a target is zeroLength legyen. 
							+/
						}],
						[q{"Ctrl+X Shift+Del"},q{cut},q{
							TextSelection[] s1 = textSelections.zeroLengthSelectionsToFullRows, s2; 
							copy_impl(s1); cut_impl2(s1, s2); textSelections = s2; 
						}],
						[q{"Backspace"},q{deleteToLeft},q{
							TextSelection[] s1 = textSelections.zeroLengthSelectionsToOneLeft , s2; 
							cut_impl2(s1, s2); textSelections = s2; 
							//Todo: delete all leading tabs when the cursor is right after them
							/+Todo: Ctrl+Backspace = deletes words+/
						}],
						[q{"Del"},q{deleteFromRight},q{
							TextSelection[] s1 = textSelections.zeroLengthSelectionsToOneRight, s2; 
							cut_impl2(s1, s2); textSelections = s2; 
							/+
								Bug: ha readonly, akkor NE tunjon el a kurzor! Sot, 
								ha van non-readonly selecton is, akkor azt meg el is bassza. 
							+/
							//Bug: delete should remove the leading tabs.
							/+Todo: Ctrl+Del = deletes words+/
						}],
						[q{"Ctrl+V Shift+Ins"},q{paste},q{textSelections = paste_impl(textSelections, clipboard.text); }],
						[q{"Tab"},q{insertTab},q{textSelections = paste_impl(textSelections, "\t"); }],
						[q{"Enter"},q{insertNewLine},q{
							textSelections = paste_impl(textSelections, "\n", Yes.duplicateTabs); 
							//Todo: Must fix the tabCount on the current line first, and after that it can duplicate.
						}],
						[q{"Shift+Enter"},q{insertNewPage},q{
							/+
								Todo: it should automatically insert at the end of the selected rows.
								But what if the selection spans across multiple rows...
							+/
							textSelections = paste_impl(textSelections, "\v"); 
							//Vertical Tab -> MultiColumn
						}],
						[],
						[q{"Ctrl+]"},q{indent},q{
							insertCursorAtStartOfEachLineSelected; 
							paste_impl(textSelections, "\t"); 
						}],
						[q{"Ctrl+["},q{outdent},q{
							insertCursorAtStartOfEachLineSelected; 
							auto ts = selectCharAtEachSelection(textSelections, '\t'); 
							if(!ts.empty)
							{
								textSelections = ts; 
								deleteToLeft; 
							}
							else
							{ im.flashWarning("Unable to outdent."); }
						}],
						[q{"Alt+Up"},q{moveLineUp},q{
							//TextSelection[] s1 = textSelections.zeroLengthSelectionsToFullRows, s2;
							//copy_impl(s1); cut_impl2(s1, s2); textSelections = s2;
							//Todo: moveLineUp
						}],
						[q{"Alt+Down"},q{moveLineDown},q{/+Todo: moveLineDown+/}],
						[q{"Ctrl+Z"},q{undo},q{if(expectOneSelectedModule) undoRedo_impl!"undo"; }],
						[q{"Ctrl+Y"},q{redo},q{if(expectOneSelectedModule) undoRedo_impl!"redo"; }],
						[],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Operations       +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Alt+O"},q{openModule},q{fileDialog.openMulti.each!(f => queueModule(f)); }],
						[q{"Alt+Shift+O"},q{openModuleRecursive},q{fileDialog.openMulti.each!(f => queueModuleRecursive(f)); }],
						[q{"Ctrl+R"},q{revertSelectedModules},q{
							preserveTextSelections
							(
								{
									foreach(m; selectedModules)
									{ m.reload(desiredStructureLevel); m.fileLoaded = now; }
								}
							); 
						}],
						[],
						[q{"Alt+S"},q{saveSelectedModules},q{feedAndSaveModules(selectedModules); }],
						[q{"Ctrl+S"},q{saveSelectedModulesIfChanged},q{feedAndSaveModules(selectedModules.filter!"a.changed"); }],
						[q{"Ctrl+Alt+S"},q{saveSelectedModulesIfChanged_noSyntaxCheck},q{feedAndSaveModules(selectedModules.filter!"a.changed", No.syntaxCheck); }],
						[q{"Ctrl+Shift+S"},q{saveAllModulesIfChanged},q{feedAndSaveModules(modules.filter!"a.changed"); }],
						[],
						[q{"Ctrl+W"},q{closeSelectedModules},q{
							closeSelectedModules_impl; 
							//Todo: this hsould work for selections and modules based on textSelections.empty
						}],
						[q{"Ctrl+Shift+W"},q{closeAllModules},q{closeAllModules_impl; }],
						[],
						[q{"Ctrl+F"},q{searchBoxActivate(bool global=false)},q{
							insight.deactivate; outline.deactivate; /+Todo: motherfucking lame+/
							search.activate(((actSearchKeyword=="$DIDE_PRIMARY_SELECTION$") ?(primaryTextSelection.sourceText) :(actSearchKeyword)), global); 
							/+Todo: Does nothing, then the search Edit is in focus.+/
						}],
						[q{"Ctrl+Shift+F"},q{searchBoxActivateGlobal},q{searchBoxActivate(true); }],
						[q{"Ctrl+D"},q{selectNextWord},q{selectAdjacentWord_impl!false; }],
						[q{"Ctrl+Shift+D"},q{selectPrevWord},q{selectAdjacentWord_impl!true; }],
						[q{"Ctrl+Shift+L"},q{selectSearchResults},q{selectSearchResults(getMarkerLayer(DMDMessage.Type.find)); }],
						[q{"F3"},q{gotoNextFind},q{NOTIMPL; }],
						[q{"Shift+F3"},q{gotoPrevFind},q{NOTIMPL; }],
						[q{"Ctrl+G"},q{gotoLine},q{
							if(auto m = expectOneSelectedModule)
							{ search.activate(":"); }
						}],
						[q{"F8"},q{gotoNextError},q{NOTIMPL; }],
						[q{"Shift+F8"},q{gotoPrevError},q{NOTIMPL; }],
						[],
						[q{"Ctrl+O"},q{outlineActivate},q{
							search.deactivate(this); insight.deactivate; /+Todo: motherfucking lame+/
							outline.activate; 
						}],
						[q{"Ctrl+Space"},q{insightActivate},q{
							search.deactivate(this); outline.deactivate; /+Todo: motherfucking lame+/
							insight.activate(
								/+Todo: a szonak csak az elejet kene kimasolni!+/
								((actSearchKeyword=="$DIDE_PRIMARY_SELECTION$") ?(primaryTextSelection.sourceText) :(actSearchKeyword))
							); 
						}],
						[],
						[q{""},q{feed},q{
							enforce(buildServices.ready, "BuildSystem is working."); 
							preserveTextSelections({ feedChangedModule(primaryCaret.moduleOf); }); 
						}],
						[],
						[q{"F9"},q{run},q{
							with(buildServices)
							if(ready && !running)
							{
								feedAndSaveModules(changedProjectModules); 
								run; 
							}
						}],
						[q{"Shift+F9"},q{rebuild},q{
							with(buildServices)
							if(ready && !running)
							{
								feedAndSaveModules(changedProjectModules); 
								messageUICache.clear; //Todo: This UI cache should be emptied automatically.
								rebuild; 
							}
						}],
						[q{"Ctrl+F2"},q{kill},q{
							with(buildServices)
							{
								if(cancelling)	{
									killCompilers; 
									/+
										Must check 'cancelling' 
										right before checking 'building'!
									+/
								}
								else if(building)	{ cancelBuild; }
								else if(running)	{ closeOrKillProcess; }
								else if(canKillRunningConsole)	{ killRunningConsole; }
								else	{/+resetBuildState; +/}
							}
						}],
						[q{//@VERB("F5") void toggleBreakpoint() { NOTIMPL; }
						}],
						[q{//@VERB("F10") void stepOver() { NOTIMPL; }
						}],
						[q{//@VERB("F11") void stepInto() { NOTIMPL; }
						}],
						[],
						[q{"F1"},q{help_bing},q{startChrome(scrapeLinks_bing(actHelpQuery).get(0), actSearchKeyword); }],
						[q{"Ctrl+F1"},q{help_dlang},q{startChrome(scrapeLinks_dpldocs(actSearchKeyword).get(0), actSearchKeyword); }],
						[q{"Alt+A"},q{initiateAi},q{initiateAi_impl; }],
						[q{"Ctrl+Enter"},q{launchAi},q{launchAi_impl; }],
						[],
						[q{//Experimental
						}],
						[q{"F1"},q{function1},q{}],
						[q{"F2"},q{function2},q{}],
						[q{"F3"},q{function3},q{}],
						[q{"F4"},q{function4},q{}],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Stored slots+/all)
			{
				static foreach(idx; iota(10))
				mixin(
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Ctrl+Alt+Numₙ"},q{storeLocationₙ},q{storeLocation(ₙ); }],
						[q{"Ctrl+Numₙ"},q{jumpToLocationₙ},q{jumpToLocation(ₙ); }],
						[],
						[q{"Ctrl+Alt+ₙ"},q{copyMemSlotₙ},q{copyMemSlot(ₙ); }],
						[q{"Ctrl+ₙ"},q{pasteMemSlotₙ},q{pasteMemSlot(ₙ); }],
					]))
					.GEN_verbs.replace("ₙ", idx.text)
				); 
			}
			
			version(/+$DIDE_REGION Refactor     +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{""},q{realignVerticalTabs},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							preserveTextSelections
							(
								{
									visitSelectedNestedCodeColumns((col){ col.removeVerticalTabs; }); 
									visitSelectedNestedCodeColumns((col){ col.addVerticalTabs(1400); }); 
								}
							); 
						}],
						[q{""},q{removeVerticalTabs},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							preserveTextSelections
							({ visitSelectedNestedCodeColumns((col){ col.removeVerticalTabs; }); }); 
						}],
						[q{""},q{addInternalNewLines},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							visitSelectedNestedDeclarations((decl){ decl.internalNewLineCount = 1; decl.needMeasure; }); 
						}],
						[q{""},q{removeInternalNewLines},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							visitSelectedNestedDeclarations((decl){ decl.internalNewLineCount = 0; decl.needMeasure; }); 
						}],
						[q{""},q{declarationStatistics},q{declarationStatistics_impl; }],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			
			version(/+$DIDE_REGION Rich editing+/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Shift+Alt+9"},q{insertBraceBlock},q{insertNode("(\0)", 0); }],
						[q{"Shift+Alt+0"},q{insertBraceBlock_closing},q{insertNode("(\0)"); }],
						[q{"Alt+["},q{insertSquareBlock},q{insertNode("[\0]", 0); }],
						[q{"Alt+]"},q{insertSquareBlock_closing},q{insertNode("[\0]"); }],
						[q{"Shift+Alt+["},q{insertCurlyBlock},q{insertNode("{\0}", 0); }],
						[q{"Shift+Alt+]"},q{insertCurlyBlock_closing},q{insertNode("{\0}"); }],
						[q{"Alt+`"},q{insertDString},q{insertNode("`\0`", 0); }],
						[q{"Alt+'"},q{insertCChar},q{insertNode("'\0'"); }],
						[q{"Shift+Alt+'"},q{insertCString},q{insertNode("\"\0\"", 0); }],
						[q{/+"Shift+Alt+I+'"q{insertInterpolatedCString}q{insertNode("i\"\0\"", 0); }+/}],
						[q{/+"Alt+I+`"q{insertInterpolatedDString}q{insertNode("i`\0`", 0); }+/}],
						[q{"Shift+Alt+4"},q{insertStringExpression},q{insertNode("$(\0)", 0); }],
						[q{"Alt+/"},q{insertDComment},q{insertNode("/+\0+/", 0); }],
						[q{"Shift+Alt+/"},q{insertTenary},q{
							insertNode("((\0)?():())", 0); 
							//Todo: must be inserted as an expression!!!
						}],
						[q{"Shift+Alt+;"},q{insertGenericArg},q{
							insertNode("((\0).genericArg!q{})", 0); 
							//Todo: must be inserted as an expression!!!
						}],
					]))
				) .GEN!q{GEN_verbs}); 
			}
		}
	}version(/+$DIDE_REGION UI      +/all)
	{
		void UI_ModuleBtns()
		{
			with(im) {
				File fileToClose; 
				foreach(m; modules)
				{
					if(
						Btn(
							m.file.name,
							hint(m.file.fullName),
							genericId(m.file.fullName),
							selected(0),
							{
								fh = 12; theme="tool"; 
								if(Btn(symbol("Cancel")))
								fileToClose = m.file; 
							}
						)
					) {}
				}
				if(Btn(symbol("Add"))) openModule; 
				
				if(Btn("Close All", KeyCombo("Ctrl+Shift+W"))) { closeAllModules; }
				
				if(fileToClose) closeModule(fileToClose); 
			}
		} 
		
		void UI_structureLevel()
		{
			with(im) {
				BtnRow(
					{
						Module[] modules = selectedModules; 
						if(modules.empty) modules = modulesWithTextSelection.array; 
						
						static foreach(lvl; EnumMembers!StructureLevel)
						{
							{
								const capt = lvl.text[0..1].capitalize; 
								if(
									Btn(
										{
											style.bold = modules.any!(m => m.structureLevel==lvl); 
											Text(capt); 
										}, 
										genericId(capt), 
										selected(desiredStructureLevel==lvl), 
										{ width = fh/4; },
										hint("Select desired StructureLevel.\n(Ctrl = reload and apply)")
									)
								)
								{
									desiredStructureLevel = lvl; 
									
									if(
										inputs.Ctrl.down//apply
									)
									preserveTextSelections
									(
										{
											Module[] cantReload; 
											foreach(m; modules)
											if(m.structureLevel != desiredStructureLevel)
											{
												if(m.changed)	{ cantReload ~= m; }
												else	{ m.reload(desiredStructureLevel); }
											}
											
											if(!cantReload.empty)
											{
												beep; 
												WARN(
													"Unable to reload modules because they has unsaved changes. ", 
													cantReload.map!"a.file.name"
												); 
											}
										}
									); 
								}
							}
						}
					}
				); 
			}
		} 
		
		void UI_BuildMessageType(DMDMessage.Type bmt, View2D view)
		{
			with(im) {
				if(
					Btn(
						{
							const hidden = markerLayerSettings[bmt].visible ? 0 : .75f; 
							
							auto fade(RGB c) { return c.mix(clSilver, hidden); } 
							
							const syntax = DMDMessage.typeSyntax[bmt]; 
							style.bkColor = bkColor = fade(syntax.syntaxBkColor); 
							const highContrastFontColor = syntax.syntaxFontColor; 
							style.fontColor = fade(highContrastFontColor); 
							
							Row(
								{
									flags.hAlign = HAlign.center; 
									//innerWidth = ceil(fh*2); 
									innerHeight = ceil(fh*1.66f); 
									flags.clickable = false; 
									Text(DMDMessage.typeShortCaption[bmt]); NL; 
									fh = ceil(fh*.66f); 
									
									theme = "tool"; 
									const m = Margin(0, .5, 0, .5); 
									
									if(const len = getMarkerLayerCount(bmt))
									{
										if(Btn(len.text))
										{
											markerLayerSettings[bmt].visible = true; 
											if(bmt==DMDMessage.Type.find)	zoomAt(view, getMarkerLayer_find); 
											else	zoomAt(view, getMarkerLayer(bmt)); 
										}
									}
								}
							); 
							
							markerLayerSettings[bmt].btnWorldBounds = view.invTrans(actContainerBounds); 
						},
						((bmt).genericArg!q{id})
					)
				)
				markerLayerSettings[bmt].visible.toggle; 
			}
		} 
		
		void zoomAt(R)(View2D view, R searchResults)
		if(isInputRange!(R, Container.SearchResult))
		{
			if(searchResults.empty) return; 
			const maxScale = max(view.scale, 1); 
			view.zoom(searchResults.map!(r => r.bounds).fold!"a|b", 12); 
			view.scale = min(view.scale, maxScale); 
		} 
		
		void UI_selectedModulesHint()
		{
			with(im) {
				auto sm = selectedModules; 
				void stats()
				{
					Row(
						format!"(%d LOC, %sB)"(
							sm.map!(m => m.linesOfCode).sum,
							shortSizeText!(1024, " ")(sm.map!(m => m.sizeBytes).sum)
						)
					); 
				} 
				if(sm.length==1)
				{
					auto m = sm.front; 
					Row(
						{ padding="0 8"; }, 
						"Selected module: ", 
						{ CodeLocation(m.file.fullName).UI; },
						{
							if(sameText(m.file.fullName, mainModuleFile.fullName))
							{ Btn("Main", enable(false)); }
							else
							{
								if(m.isMain)
								{ if(Btn("Set Main")) mainModule = m; }
							}
							stats; 
						}
					); 
				}
				else if(sm.length>1)
				{ Row({ padding="0 8"; }, sm.length.text, " modules selected ", { stats; }); }
				else
				{ Row({ padding="0 8"; }, "No modules selected."); }
			}
		} 
		
		void UI_mouseLocationHint(View2D view)
		{
			with(im) {
				//Todo: This UI thing updated internal state. Not good...
				actSearchKeyword = ""; 
				actSearchKeywordBounds = bounds2.init; 
				actHelpQuery = ""; 
				
				bool isCaret, isAtLineEnd, wordIsSelectedText; 
				CellLocation[] st; 
				
				if(primaryCaret.valid)
				{
					isCaret = true; 
					
					if(textSelections.length==1)
					{
						if(primaryTextSelection.isZeroLength)
						{
							isAtLineEnd = primaryCaret.isAtLineEnd; 
							st = cursorToCellLocations(primaryCaret); 
						}
						else if(primaryTextSelection.isSingleLine)
						{
							st = cursorToCellLocations(primaryTextSelection.start); 
							wordIsSelectedText = true; 
						}
					}
				}
				else
				{ if(view.isMouseInside) st = locate_snapToRow(view.mousePos.vec2); }
				
				if(st.length)
				{
					auto 	loc 	= cellLocationToCodeLocation(st),
						breadcrumbs 	= st.toBreadcrumbs; 
					if(wordIsSelectedText)
					{
						actSearchKeyword = "$DIDE_PRIMARY_SELECTION$"; 
						actSearchKeywordBounds = primaryTextSelection.worldBounds; 
						//Todo: Don't get the actual source text becaus it can be very large.  Needs a size estimation first.
					}
					else
					{ actSearchKeyword = wordAt(st, isCaret && !isAtLineEnd, &actSearchKeywordBounds, &actSearchKeywordSelection); }
					actHelpQuery = extractHelpQuery(breadcrumbs, actSearchKeyword); 
					
					
					Row(
						{ padding="0 8"; }, ((isCaret)?("Ꮖ"):("⌖")), " ",
						{
							theme = "tool"; 
							loc.UI; NL; 
							foreach(i, b; breadcrumbs)
							{
								if(
									Btn(
										{
											style.bkColor = bkColor = b.node.bkColor; 
											style.fontColor = blackOrWhiteFor(bkColor); 
											Text(b.text); 
										},
										(("Breadcrumb:"~i.text).genericArg!q{id})
									)
								)
								{ jumpTo(b.node); }
							}
							
							if(actHelpQuery!="")
							if(Btn("Search: "~actHelpQuery))
							{/+Todo: bing.com?q=query+string -> shellExecute start chrome ...+/}
						}
					); 
				}
			}
		} 
		
		
		string lastNearestSearchResultReference; 
		
		Container mouseOverHintCntr; 
		
		///must be called from root level
		void UI_mouseOverHint()
		{
			with(im) {
				if(lastNearestSearchResultReference.chkSet((cast(size_t)((cast(void*)(nearestSearchResult.reference)))).text))
				{
					mouseOverHintCntr = null; 
					
					if(nearestSearchResult.reference)
					{
						if(!mouseOverHintCntr)
						if(auto mm = (cast(Module.Message)(nearestSearchResult.reference)))
						{
							auto msgNode = renderBuildMessage(mm.message); 
							with(msgNode) {
								outerWidth 	= min(outerWidth, max(this.outerWidth-50, 50)),
								outerHeight 	= min(outerHeight, DefaultFontHeight * 3); 
							}
							if(0/+Todo: most letiltom a hintet, de optionsba ki kell rakni...+/) mouseOverHintCntr = msgNode; 
							
							/+
								auto msgSrc = messageSourceTextByLocation[wild[0]]; 
								if(msgSrc in messageUICache)
								{
									mouseOverHintCntr = cast(.Container)(messageUICache[msgSrc].subCells[0]); 
									//Todo: Highlight the CodeLocation comment which is nerest to the mouse
									//Todo: show bezier arrows from the message hint's codelocations
									//Todo: a way to lock the message hint to be able to interact with it using the mouse
									//Todo: a way to scroll errorlist over the hovered item
								}
							+/
						}
						
						//if unable to generate a hint, display the SearchResult.reference:
						static if(0)
						if(!mouseOverHintCntr) {
							Text(nearestSearchResult.reference); 
							mouseOverHintCntr = removeLastContainer; 
						}
						
					}
				}
				
				if(mouseOverHintCntr)
				actContainer.append(mouseOverHintCntr); 
			}
		} 
		
		void UI_Popup()
		{
			version(/+$DIDE_REGION Popup menu+/all)
			{
				static Module popupModule; 
				static vec2 popupGuiPos, popupWorldPos; 
				bool justPopped; 
				
				if(inputs.RMB.pressed)
				if(auto tbl = cast(ScrumTable) moduleSelectionManager.hoveredItem)
				{
					popupModule = tbl; 
					popupGuiPos = (cast(GLWindow)(mainWindow)).viewGUI.mousePos.vec2; 
					popupWorldPos = mainView.mousePos.vec2; 
					justPopped = true; 
				}
				
				if(popupModule)
				{
					with(im)
					{
						Column(
							{
								outerPos = popupGuiPos; 
								border = "1 normal black"; padding = "4"; theme = "tool"; 
								Row(
									{
										Text("ScrumTable Menu"); 
										if(Btn(symbol("ChromeClose"))) popupModule = null; 
									}
								); 
								Spacer; 
								if(!modules.canFind(popupModule)) popupModule = null; 
								if(popupModule)
								{
									if(Btn("New Sticker", genericId("New Sticker")).clicked)
									{
										scope(exit) popupModule = null; 
										
										const f = File(popupModule.file.path, now.timestamp ~ `.sticker`); 
										format	!`/+Note:+/
	/+{  "color": "StickyBlue",  "pos": [%.3f, %.3f]}+/`
											(popupWorldPos.x, popupWorldPos.y)
											.saveTo(f); 
										
										//Ez felesleges volt!!! -> A loadModule() direkt fogadja a poziciot.
										version(/+$DIDE_REGION+/none)
										{
											const ms = ModuleSettings(f.fullName, popupWorldPos); 
											const idx = moduleSettings.map!"a.fileName".countUntil(ms.fileName); 
											if(idx>=0)	moduleSettings[idx] = ms; 
											else	moduleSettings ~= ms; 
										}
										
										loadModule(f, popupWorldPos); 
										
										textSelections([TextSelectionReference(f.fullName~`|C0|R0|N0|C0|R0|X0*`, &findModule).fromReference]); 
										//Miért kell egy ilyen hosszú izét beírni, hogy beleugorjon a kurzor az új dokumentumba????!!!!!!!!
										
									}
								}
							}
						); 
					}
					
					if(
						inputs.Esc.pressed 
						|| inputs.RMB.pressed && !justPopped 
						|| inputs.LMB.released && false//Todo: MUST NOT!!! Btn can't catch it in the next frame. -> LAME
						|| inputs.MMB.pressed || inputs.MB4.pressed || inputs.MB4.pressed
					)
					popupModule = null; 
				}
			}
		} 
	}version(/+$DIDE_REGION Draw     +/all)
	{
		
		SearchResult nearestSearchResult;  //Todo: MMB jumps to nearestSearchResult
		float nearestSearchResult_dist; 
		RGB nearestSearchResult_color, _nearestSearchResult_ActColor; 
		
		void resetNearestSearchResult()
		{
			nearestSearchResult = SearchResult.init; 
			nearestSearchResult_dist = 1e30; 
		} 
		
		void updateNearestSearchResult(float dist, lazy const SearchResult sr)
		{
			if(dist<nearestSearchResult_dist)
			{
				nearestSearchResult_dist = dist; 
				nearestSearchResult = cast()sr; //Todo: constness
				nearestSearchResult_color = _nearestSearchResult_ActColor; 
			}
		} 
		
		void drawSearchResults(R)(
			Drawing dr, R searchResults, 
			RGB clSearchHighLight, float extraThickness = 0
		)
		if(isInputRange!(R, Container.SearchResult))
		{
			with(dr) {
				const 	arrowSize = 12+3*blink,
					arrowThickness = arrowSize*.2f,
					
					far = lod.level>1,
					extra = lod.pixelSize* (2.5f*blink+.5f + extraThickness),
					
					clamper = RectClamperF(im.getView, arrowThickness*2); 
				
				bool isVisible(in bounds2 b)
				{ return clamper.overlaps(b); } 
				
				//always draw these
				color = clSearchHighLight; 
				_nearestSearchResult_ActColor = clSearchHighLight; 
				
				auto mp = mainView.mousePos.vec2; 
				
				static float distanceB(in vec2 p, in bounds2 b)
				{
					const 	dx = max(b.low.x - p.x, 0, p.x - b.high.x),
						dy = max(b.low.y - p.y, 0, p.y - b.high.y); 
					return sqrt(dx*dx + dy*dy); 
				} 
				
				foreach(sr; searchResults)
				if(auto b = sr.bounds)
				{
					if(sr.container && !sr.container.flags.removed)
					{
						if(isVisible(b))
						{
							updateNearestSearchResult(distanceB(mp, b), sr); 
							if(far)
							{ fillRect(b.inflated(extra)); }
							else
							{
								lineWidth = extra; 
								arrowStyle = ArrowStyle.none; 
								drawRect(b); 
							}
						}
						else
						{
							if(sr.showArrow)
							{
								lineWidth = -arrowThickness -extraThickness; 
								arrowStyle = ArrowStyle.arrow; 
								
								const p = clamper.clampArrow(b.center); 
								line(p); 
								updateNearestSearchResult(distance(mp, p[1]), sr); 
							}
						}
					}
				}
				
				
				
				arrowStyle = ArrowStyle.none; 
				
				//later pass, draw the columns as highlighted so this will always visible
				/*
					if(!far){
						foreach(sr; searchResults)
							if(isVisible(sr.bounds)){
								dr.alpha = .5*blink;
								sr.drawHighlighted(dr, clSearchHighLight); //close lod
							}
					}
					dr.alpha = 1;
				*/
			}
		} 
		
		/// A flashing effect, when right after the module was loaded.
		void drawModuleLoadingHighlights(string field)(Drawing dr, RGB c)
		{
			const t0 = now; 
			foreach(m; modules)
			{
				const dt = (t0-mixin("m."~field)).value(2.5f*second); 
				if(dt<1)
				drawHighlight(dr, m, c, sqr(1-dt)); 
			}
		} 
		
		/*
			protected void drawSelectedModules(
				Drawing dr, RGB clSelected, float selectedAlpha, 
				RGB clHovered, float hoveredAlpha
			){ with(dr){
				selectedModules.each!(m => drawHighlight(dr, m, clSelected, selectedAlpha));
				drawHighlight(dr, hoveredModule, clHovered, hoveredAlpha);
			}}
		*/
		
		protected void drawSelectionRect(Drawing dr, RGB clRect)
		{
			if(auto bnd = moduleSelectionManager.selectionBounds)
			with(dr) {
				lineWidth = -1; 
				lineStyle = LineStyle.dash; 
				color = clRect; 
				drawRect(bnd); 
				lineStyle = LineStyle.normal; 
			}
		} 
		
		
		void drawMessageConnectionArrows(Drawing dr)
		{
			enum sc = 1.5f; 
			
			dr.lineWidth = -1.5f*sc; 
			dr.pointSize = -5*sc; 
			//dr.lineStyle = LineStyle.dash; 
			/+
				Todo: animated dashed line is only going one direction on the screen. 
				Must rewrite that part completely.
			+/
			dr.arrowStyle = ArrowStyle.arrow; 
			dr.alpha = blink.remap(0, 1, .5, 1); 
			
			const pixelSize = mainView.invScale_anim; 
			
			foreach(const ref a; messageConnectionArrows.keys)
			{
				with(a)
				{
					auto layer = &markerLayerSettings[type]; 
					if(layer.visible)
					{
						dr.color = DMDMessage.typeColor[type]; 
						static if((常!(bool)(0))) dr.line(p1, p2); 
						static if((常!(bool)(1))) {
							auto pc = mix(p1, p2, .5f) + vec2(0, -(magnitude(p2-p1)))*(.125f*sc); 
							
							const d = (normalize(p2-pc))*pixelSize; 
							
							static if((常!(bool)(1))/+Note: shadow/outline+/)
							{
								version(/+$DIDE_REGION Save state+/all) { const c = dr.color; const lw = dr.lineWidth; }
								version(/+$DIDE_REGION Alter state+/all) { dr.color = isException ? clYellow : blackOrWhiteFor(dr.color); dr.lineWidth = -2.7*sc; }
								
								dr.bezier2(p1, pc, p2); 
								
								dr.lineWidth = -1.95*sc; 
								dr.line(p2, p2 + d*(2.35f*sc)); 
								
								version(/+$DIDE_REGION Restore state+/all) { dr.color = c; dr.lineWidth = lw; }
							}
							
							dr.bezier2(p1, pc, p2); dr.line(p2 - d, p2); 
							//lame: arrow not included in bezier
						}
						static if((常!(bool)(0))) dr.bezier2(p1, p2 - vec2((magnitude(p2-p1))*(.125f*sc), 0), p2); 
					}
				}
			}
			//dr.lineStyle = LineStyle.normal; 
			dr.arrowStyle = ArrowStyle.none; 
			dr.alpha = 1; 
		} 
		
		void drawTextSelections(Drawing dr, View2D view)
		{
			version(/+$DIDE_REGION+/all)
			{
				scope(exit) dr.alpha = 1; 
				
				const 	near	= lod.zoomFactor.smoothstep(0.02, 0.1),
					clSelected	= mix(
					mix(RGB(0x404040), clGray, near*.66f),
					mix(clWhite, clGray, near*.66f), blink
				),
					clCaret	= clSilver,
					clPrimaryCaret 	= clWhite,
					alpha	= mix(0.75f, .4f, near); 
				
				const cullBounds = view.subScreenBounds_anim; 
				
				dr.color = clSelected; 
				dr.alpha = alpha; 
				foreach(sel; textSelections)
				if(!sel.isZeroLength)
				{
					auto col = sel.codeColumn; 
					const 	colInnerPos	= worldInnerPos(col), //Opt: group selections by codeColumn.
						colInnerBounds 	= bounds2(colInnerPos, colInnerPos+col.innerSize); 
					if(cullBounds.overlaps(colInnerBounds))
					{
						const localCullBounds = cullBounds - colInnerPos; 
						auto 	st	= sel.start,
							en 	= sel.end; 
						
						const 	pages = col.getPageRowRanges,
							singlePage = pages.length==1; 
						
						foreach(y; st.pos.y..en.pos.y+1)
						{
							//Todo: this loop is in the copy routine as well. Must refactor and reuse
							auto row = col.rows[y]; 
							const rowCellCount = row.cellCount; 
							
							//culling
							if(row.outerBottom < localCullBounds.top) continue;  //Opt: trisect
							if(singlePage)
							{ if(row.outerTop > localCullBounds.bottom) break; }
							else
							{
								if(row.outerTop > localCullBounds.bottom) continue; //next page can follow
								if(row.outerLeft > localCullBounds.right) break; 
							}
							
							const 	isFirstRow 	= y==st.pos.y,
								isLastRow	= y==en.pos.y; 
							const 	x0 	= isFirstRow ? st.pos.x : 0,
								x1	= isLastRow ? en.pos.x : rowCellCount+1; 
							const 	rowInnerPos 	= colInnerPos + row.innerPos; 
							
							dr.translate(rowInnerPos); scope(exit) dr.pop; 
							
							if(lod.level<=1)
							{
								foreach(x; x0..x1)
								{
									
									void fade(bounds2 bnd)
									{
										dr.color = clSelected; 
										dr.alpha = alpha; 
										
										enum gap = .5f; 
										if(isFirstRow)
										{
											bnd.top += gap; 
											if(x==x0) bnd.left += gap; 
										}
										if(isLastRow)
										{
											bnd.bottom -= gap; 
											if(x==x1-1) bnd.right -= gap; 
										}
										dr.fillRect(bnd); 
									} 
									
									assert(x.inRange(0, rowCellCount), "out of range"); 
									if(x<rowCellCount)
									{
										/+
											Todo: make the nice version: the font will be NOT blended to gray, 
											but it hides the markerLayers completely. Should make a 
											text drawer that uses alpha on the background and leaves 
											the font color as is.
										+/
										/+
											if(auto g = row.glyphs[x]){
												const old = tuple(g.bkColor, g.fontColor);
												g.bkColor = mix(g.bkColor, clSelected, alpha);// g.fontColor = clBlack;
												dr.alpha = 1;
												g.draw(dr);
												g.bkColor = old[0]; g.fontColor = old[1];
											}else
										+/
										{ fade(row.subCells[x].outerBounds); }
									}
									else
									{
										//newLine
										auto g = newLineGlyph; 
										const originalSize = g.outerSize; 
										const mustShrink = g.outerHeight>row.outerHeight+.125f; 
										if(mustShrink) g.outerSize = originalSize * (row.outerHeight / g.outerHeight); 
										scope(exit) if(mustShrink) g.outerSize = originalSize; 
										
										g.bkColor = row.bkColor;  g.fontColor = clGray; 
										dr.alpha = 1; 
										g.outerPos = row.newLinePos; 
										g.draw(dr); 
										
										fade(g.outerBounds); 
									}
								}
								
							}
							else
							{
								if(!isFirstRow && !isLastRow)
								{
									if(row.cellCount)
									dr.fillRect(bounds2(0, 0, row.subCells.back.outerRight, row.innerHeight)); 
								}
								else
								{
									dr.fillRect(
										bounds2(
											row.localCaretPos(x0).pos.x, 0, 
											row.localCaretPos(x1).pos.x, row.innerHeight
										)
									); 
								}
							}
						}
						
					}
				}
			}version(/+$DIDE_REGION+/all)
			{
				//caret trail
				static if(AnimatedCursors)
				{
					if(textSelections.length <= MaxAnimatedCursors)
					{
						dr.alpha = blink/2; 
						dr.lineWidth = -1-(blink)*3; 
						dr.color = clCaret; 
						//Opt: culling
						//Opt: limit max munber of animated cursors
						foreach(s; textSelections)
						{
							CaretPos[3] cp; 
							cp[0] = s.caret.worldPos; 
							cp[1..3] = cp[0]; 
							cp[2].pos += s.caret.animatedPos - s.caret.targetPos; 
							cp[2].height = s.caret.animatedHeight; 
							cp[1].pos = mix(cp[0].pos, cp[2].pos, .25f); 
							
							auto dir = cp[1].pos-cp[2].pos; 
							if(dir)
							{
								if(dir.normalize.x.abs<0.05f)
								{
									//vertical line
									vec2[2] p = [cp[1].pos, cp[2].pos]; 
									if(p[0].y<p[1].y) p[1].y += cp[2].height; 
									else p[0].y += cp[1].height; 
									dr.line(p[0], p[1]); 
								}
								else
								{
									//horizontal bar
									vec2[4] p; 
									p[0] = cp[1].pos; 
									p[1] = cp[1].pos + vec2(0, cp[1].height); 
									p[2] = cp[2].pos + vec2(0, cp[2].height); 
									p[3] = cp[2].pos; 
									
									if(p[0].x<p[3].x)
									{
										dr.fillTriangle(p[0], p[1], p[3]); 
										dr.fillTriangle(p[1], p[2], p[3]); 
									}
									else
									{
										dr.fillTriangle(p[3], p[2], p[0]); 
										dr.fillTriangle(p[2], p[1], p[0]); 
									}
								}
							}
						}
					}
				}
				
				
				{
					const clamper = RectClamperF(view, 7*blink+2); 
					
					auto getCaretWorldPos(TextSelection ts)
					{
						CaretPos res = ts.caret.worldPos; 
						
						if(!clamper.overlaps(res.bounds))
						{
							res.pos = clamper.clamp(res.center); 
							res.height = lod.pixelSize; 
						}
						
						return res; 
					} 
					
					auto carets = textSelections.map!getCaretWorldPos.array; 
					
					void drawCarets(RGB c, float shadow=0)
					{
						dr.alpha = blink; 
						dr.lineWidth = -1-(blink)*3 -shadow; 
						dr.color = c; 
						foreach(cwp; carets) cwp.draw(dr); 
					} 
					
					drawCarets(clBlack, 3); 	//shadow
					drawCarets(clCaret); 	//inner
					
					//primary
					if(auto ts = primaryTextSelection)
					{
						dr.color = clPrimaryCaret; 
						getCaretWorldPos(ts).draw(dr); 
					}
				}
			}
		} 
		
		
		protected void drawMainModuleOutlines(Drawing dr)
		{
			auto mm=mainModule; 
			foreach(m; modules)
			{
				if(m==mm) { dr.color = RGB(0xFF, 0xD7, 0x00); dr.lineWidth = -2.5f; dr.drawRect(m.outerBounds); }
				else if(m.isMain) { dr.color = clSilver; dr.lineWidth = -1.5f; dr.drawRect(m.outerBounds); }
				//else if(m.file.extIs(".d")){ dr.color = clSilver; dr.lineWidth = 12; dr.drawRect(m.outerBounds); }
			}
		} 
		
		protected void drawFolders(Drawing dr, RGB clFrame, RGB clText)
		{
			//Opt: detect changes and only collect info when changed.
			auto _間=init間; scope(exit) ((0x2DC7471008CF4).檢((update間(_間)))); 
			
			const paths = modules.map!(m => m.file.path.fullPath).array.sort.uniq.array; 
			
			foreach(folderPath; paths)
			{
				bounds2 bnd; 
				foreach(m; modules)
				{
					const modulePath = m.file.path.fullPath; 
					if(modulePath.startsWith(folderPath))
					{
						const intermediateFolderCount = modulePath[folderPath.length..$].filter!`a=='\\'`.walkLength; 
						
						bnd |= m.outerBounds.inflated((1+intermediateFolderCount)*255.0f/*max font size ATM*/); 
					}
				}
				
				if(bnd) {
					dr.lineWidth = -1; 
					dr.color = clFrame; 
					dr.drawRect(bnd); 
				}
				
				with(cachedFolderLabel(folderPath))
				{
					outerPos = bnd.topLeft - vec2(0, 255); 
					draw(dr); 
				}
			}
		} 
		
		void drawModuleBuildStates(Drawing dr)
		{
			with(ModuleBuildState)
			foreach(m; modules)
			if(m.buildState!=notInProject)
			{
				dr.color = moduleBuildStateColors[m.buildState]; 
				dr.lineWidth = -4; 
				//if(m.buildState==compiling) dr.drawRect(m.outerBounds);
				dr.alpha = m.buildState==compiling ? mix(.15f, .55f, blink) : .15f; 
				dr.fillRect(m.outerBounds); 
			}
			dr.alpha = 1; 
		} 
		
		void customDraw(Drawing dr)
		{
			//customDraw //////////////////////////////
			if(textSelections.empty)
			{
				//select means module selection
				foreach(m; modules)
				if(m.flags.selected)
				drawHighlight(dr, m, clAccent, .25); 
				if(!lod.codeLevel)
				{
					if(0/+It's annoying, so I disabled it.+/)
					drawHighlight(dr, hoveredModule, clWhite, .125); 
				}
			}
			else
			{
				//select means text editing
				foreach(m; modules)
				if(!m.flags.selected)
				drawHighlight(dr, m, clGray, .25); 
			}
			
			if(lod.moduleLevel || buildServices.building) drawModuleBuildStates(dr); 
			
			drawModuleLoadingHighlights!"fileLoaded"(dr, clAqua  ); 
			drawModuleLoadingHighlights!"fileSaved" (dr, clYellow); 
			
			drawMainModuleOutlines(dr); 
			drawFolders(dr, clGray, clWhite); 
			drawSelectionRect(dr, clAccent); 
			
			if(auto b = actSearchKeywordBounds) {
				dr.color = clWhite; dr.alpha = .6*blink; dr.lineWidth = 2; dr.lineStyle = LineStyle.dot; 
				dr.drawRect(b); 
				dr.lineStyle = LineStyle.normal; 
				dr.alpha = 1; 
			}
			
			resetNearestSearchResult; 
			
			markerLayerSettings[DMDMessage.Type.unknown].visible = false; 
			//markerLayerSettings[DMDMessage.Type.console].visible = true; 
			
			foreach_reverse(t; [EnumMembers!(DMDMessage.Type)])
			if(markerLayerSettings[t].visible)
			{
				void doit(R)(R sr) { drawSearchResults(dr, sr, DMDMessage.typeSyntax[t].syntaxBkColor); } 
				if(t==DMDMessage.Type.find)	doit(getMarkerLayer_find); 
				else	doit(getMarkerLayer(t)); 
			}
			
			if(nearestSearchResult_dist > mainView.invScale*24)
			nearestSearchResult = SearchResult.init; 
			
			if(nearestSearchResult.bounds)
			{ drawSearchResults(dr, [nearestSearchResult], nearestSearchResult_color.mix(clWhite, .5f)); }
			
			drawChangeIndicators(dr, globalChangeindicatorsAppender[]); globalChangeindicatorsAppender.clear; 
			
			drawMessageConnectionArrows(dr); 
			
			mixin(求each(q{ref p},q{inspectorParticles},q{p.updateAndDraw(dr)})); 
			
			drawTextSelections(dr, mainView); //Bug: this will not work for multiple workspace views!!!
			
			void drawProgressBalls()
			{
				//Todo: put this into the drawing module
				dr.pointSize = 25; 
				dr.color = clBlue; 
				foreach(i; -10..10)
				{
					const t = (i + QPS.value(0.5 * second).fract) / 3; 
					dr.point((t+t^^5)*100, 0); 
				}
			} 
		} 
		
		override void onDraw(Drawing dr)
		{} 
		
		override void draw(Drawing dr)
		{
			globalVisualizeSpacesAndTabs = !textSelections_internal.empty; 
			
			globalChangeindicatorsAppender.clear; 
			mixin(求each(q{m},q{modules},q{m.visibleConstantNodes.clear})); 
			
			structureMap.beginCollect; 
			super.draw(dr); 
			structureMap.endCollect(dr); 
			//customDraw(dr); 
		} 
	}
} 