module dideworkspace;    

import didebase; 
import buildsys : BuildResult; 
import didenode : CodeComment, StructureMap, visitNestedCodeColumns, visitNestedCodeNodes; 
import didedecl : Declaration, 	/+these are for statistics only ->+/dDeclarationRecords, processHighLevelPatterns_block; 
import didemodule : addInspectorParticle, Breadcrumb, toBreadcrumbs, nearestDeclarationBlock, drawChangeIndicators, globalChangeindicatorsAppender, inspectorParticles; 
import didemodulemanager : ModuleManager; 
import didebuildmessagemanager : BuildMessageManager; 
import didetextselectionmanager : TextSelectionManager; 
import dideeditor : Editor; 
import didenavigator : Navigator; 
import dideinsight : ModuleDeclarations, DDB, Insight; 
import didehelp : HelpManager; 
import dideai : AiManager; 
import didesearch : SearchBox; 
import dideoutline : Outline; 

class Workspace : Container, IWorkspace
{
	version(/+$DIDE_REGION Workspace things+/all)
	{
		//A workspace is a collection of opened modules
		
		enum defaultExt = ".dide"; 
		
		File file; //frmMain uses and maintains this. 
		View2D mainView; //Now it is only mainView, later multiple views must be supported per workspace.
		bool mainIsForeground; //frmMain must update this!!
		IBuildServices buildServices; //this lets access the main form's project builder.
		//there are mainWindow dependencies
		
		@STORED ModuleManager modules; 
		@STORED TextSelectionManager textSelections; 
		@STORED BuildMessageManager buildMessages; 
		@STORED Editor editor; 
		@STORED Navigator navig; 
		HelpManager help; 
		AiManager aiManager; 
		@STORED SearchBox search; 
		@STORED Outline outline; 
		@STORED Insight insight; 
		
		
		//Restrict convertBuildResultToSearchResults calls.
		size_t lastBuildStateHash; 
		bool buildStateChanged; 
		
		StructureMap structureMap; 
		
		void smartScrollTo(bounds2 b)
		{ mainView.smartScrollTo(b); } 
		
		ref desiredStructureLevel()
		=> modules.desiredStructureLevel; 
		
		void setTextSelectionReference(string s)
		{ textSelections.items = [TextSelectionReference(s, &modules.findModule).fromReference]; } 
		
		Container workspaceContainer()
		=> this/+safe access to functions needeng a workspace. 'this' would be unsafe.+/; 
		
		override @property bool isReadOnly()
		=> editor.isReadOnly; 
		
		override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0))
		=> navig.locate(mouse, ofs); 
		
		this(View2D mainView, IBuildServices buildServices)
		{
			this.mainView 	= mainView,
			this.buildServices 	= buildServices; 
			
			modules = new ModuleManager; 
			modules.workspaceContainer = this/+workspaceContainer+/; 
			modules.afterModulesChanged = &updateSubCells; 
			modules.onSmartScrollTo = &smartScrollTo; 
			modules.onGetPrimaryModule = &primaryModule; 
			modules.onSetTextSelectionReference = &setTextSelectionReference; 
			
			textSelections = new TextSelectionManager(this/+workspaceContainer+/, modules); 
			
			buildMessages = new BuildMessageManager(modules); 
			
			navig = new Navigator(this/+workspaceContainer+/, modules, buildMessages, mainView); 
			
			
			editor = new Editor(modules, textSelections, buildServices, buildMessages); 
			
			aiManager.textSelections = textSelections; 
			aiManager.insertNewLine = &insertNewLine; 
			aiManager.cursorLeftSelect = &cursorLeftSelect; 
			aiManager.deleteToLeft = &deleteToLeft; 
			aiManager.pasteText = &editor.pasteText; 
			aiManager.insertNode = &editor.insertNode; 
			
			help.textSelections = textSelections; 
			
			flags.targetSurface = 0; 
			flags.noBackground = true; 
			
			structureMap = new StructureMap; 
			needMeasure; 
		} 
		
		~this()
		{
			editor.free; 
			textSelections.free; 
			buildMessages.free; 
			modules.free; 
		} 
		
		override void rearrange()
		{
			super.rearrange; 
			static if(rearrangeLOG)
			LOG("rearranging", this); 
		} 
	}version(/+$DIDE_REGION Module handling+/all)
	{
		//! Module handling ///////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			protected void updateSubCells()
			{
				textSelections.invalidateTextSelections; 
				subCells = (cast(Cell[])(modules.modules)); 
			} 
			
			void clear()
			{
				modules.closeAllModules; 
				textSelections.clear; 
				updateSubCells; 
			} 
			
			void loadWorkspace(string jsonData)
			{
				//Todo: don't need to fuck here
				auto fuck = this; fuck.fromJson(jsonData); 
				modules.fromModuleSettings; 
			} 
			
			string saveWorkspace()
			{
				modules.toModuleSettings; 
				return this.toJson; 
			} 
			
			void loadWorkspace(File f)
			{ loadWorkspace(f.readText(true)); } 
			
			void saveWorkspace(File f)
			{ f.write(saveWorkspace); } 
		}
		
		
		version(/+$DIDE_REGION+/all)
		{
			auto primaryTextSelection()
			=> textSelections.primary; 
			
			auto primaryCaret()
			=> primaryTextSelection.caret; 
			
			auto primaryModule()
			=> primaryTextSelection.moduleOf; 
			
			auto modulesWithTextSelection()
			=> textSelections.modulesWithTextSelection; 
			
			
			
			
		}
	}version(/+$DIDE_REGION Cursor/Selection stuff+/all)
	{
		
		
		//textSelection, cursor movements /////////////////////////////
		
		int lineSize()
		{ return DefaultFontHeight; } 
		int pageSize()
		{ return (mainView.subScreenBounds_anim.height/lineSize*.9f).iround.clamp(2, 100); } 
		
		
		void cursorOp(ivec2 dir, bool select, bool stepInOut=false)
		{ auto ts = textSelections[]; applyCursorOp(ts, dir, select, stepInOut); textSelections.items = ts; } 
		
		void cancelSelection_impl()
		{
			auto pm = modules.primaryModule; 
			
			void selectPrimaryModule()
			{ textSelections.clear; modules.select(pm); navig.scrollInModule(pm); } 
			
			//multiTextSelect -> primaryTextSelect
			if(textSelections.length>1)
			if(auto pts = primaryTextSelection)
			{ textSelections.items = pts; return; }
			
			void deselectAllModules()
			{ modules.modules.each!((m)=>(m.flags.selected = false)); } 
			
			if(!textSelections.empty)
			{ textSelections.clear; deselectAllModules; return; }
			
			//as a final act, zoom all
			deselectAllModules; navig.scrollInAllModules; 
		} 
	}version(/+$DIDE_REGION Update+/all)
	{
		
		
		//Todo: Ctrl+D word select and find
		
		//Mouse ---------------------------------------------------
		
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
									editor.pasteText(ch.to!string); 
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
			if(auto a = inputs.xiRX.value) navig.scrollH	(-a*ss); 
			if(auto a = inputs.xiRY.value) navig.scrollV	(a*ss); 
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
				
				modules.updateAutoReload; 
				modules.updateLoadQueue(1); 
				editor.updateResyntaxQueue; 
				
				measure; //measures all containers if needed, updates ElasticTabstops
				//textSelections = validTextSelections;  //this validation is required for the upcoming mouse handling
				//and scene drawing routines.
				
				//From here every positions and sizes are correct -----------------------------------------
				
				
				//particle effects for incoming messages
				foreach(mm; buildMessages.incomingVisibleModuleMessageQueue.fetchAll)
				{
					auto layer = &buildMessages.layers[mm.type]; 
					addInspectorParticle(mm.node, mm.node.bkColor, layer.btnWorldBounds); 
					if(
						mm.type==DMDMessage.Type.error && !mm.isException
						&& buildMessages.firstErrorMessageArrived.chkSet
						/+
							Note: Catch the first compile error
							(Exceptions are always shown.)
						+/
					)
					{
						view.animSpeed = .96f; 
						navig.jumpTo(mm); 
						im.flashError(mm.message.oneLineText); 
						bloodScreenEffect.activate; 
					}
				}
				
				navig.updateJumps; //jumping to locations with MMB 
				
				//Ctrl+Click handling
				if(!im.wantMouse && view.isMouseInside && KeyCombo("Ctrl+LMB").pressed)
				{}
				
				modules.moduleSelectionManager.update(
					!im.wantMouse && mainWindow.canProcessUserInput
					&& view.isMouseInside /+&& lod.moduleLevel+/,
					view, modules.modules, textSelections.length>0, 
					{ textSelections.clear; },
					{ modules.bringToFrontSelectedModules; }
				); 
				const textSelectionChanged = textSelections.update(view, &navig.createCursorAt, mainIsForeground, navig.wheelSpeed); 
				
				//Only if there are any cursors, module selection is forced to modules with textSelections
				if(textSelectionChanged && textSelections.length)
				{
					foreach(m; modules.modules) m.flags.selected = false; 
					foreach(m; modulesWithTextSelection) m.flags.selected = true; 
				}
				
				navig.updateScrollRequests; 
				
				//focus at updated selection
				if(!textSelections.scrollInRequest.isNull)
				{
					const p = textSelections.scrollInRequest.get; 
					mainView.scrollZoom(bounds2(p, p)); 
					textSelections.scrollInRequest.nullify; 
				}
				
				//focus at changed selection
				if(textSelectionChanged)
				{
					if(!inputs[textSelections.mouseMappings.main].down)
					{
						//don't focus to changed selection when the main mouse button is held down
						
						//mainView.scrollZoom(worldBounds(textSelections)); <- this is bad when editing. It zooms out.
						//Todo: maybe it is problematic when the selection can't fit on the current screen
						
						//this is better.
						if(primaryTextSelection) mainView.scrollZoom(worldBounds(primaryTextSelection)); 
						//Todo: what about latestSelection: the selection that was added recently...
					}
				}
				
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
					return modules.modules	.map!"tuple(a.file, a.outerPos)"
						.array
						.hashOf(
						buildResult.lastUpdateTime.hashOf(
							buildMessages.layerVisibilityMask
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
				{ modules.updateModuleBuildStates(buildResult); }
				
				modules.updateLastKnownModulePositions; 
				
				insight.updateInsightFiber; 
				search.updateSearchFiber; 
				foreach(m; modules.modules) m.updateSearchResults; 
				buildMessages.updateMessageConnectionArrows; 
				
				aiManager.update; 
			}
			catch(Exception e)
			{ im.flashError(e.simpleMsg); }
		} 
	}version(/+$DIDE_REGION Refactor+/all)
	{
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
				
				if(auto mod = modules.singleSelectedModule)
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
			//Todo: put this into TextSelectionManager
			auto ts = textSelections[]; ref actSel() => isPrev ? ts.front : ts.back; 
			if(!ts.empty && !actSel.isZeroLength)
			{
				if(auto mod = actSel.moduleOf)
				{
					import std.algorithm : cmp; 
					auto dissect(TextSelection s)
					=> s.start.toReference.text.splitter('|').enumerate.map!((a)=>(((a.index)?(a.value[1..$].to!uint) :(a.value.xxh32)))); 
					
					auto srs = mod	.search(actSel.sourceText, mod.worldInnerPos, Yes.caseSensitive, Yes.wholeWords)
						.map!((sr)=>(searchResultToTextSelection(sr, workspaceContainer)))
						.filter!((ts)=>(ts.valid && ts.codeColumn.isPartOfSourceCode)).array; 
					static if(isPrev) srs = srs.retro.array; 
					auto act = dissect(actSel); 
					const idx = srs.countUntil!((a)=>(cmp(act, dissect(a))*((isPrev)?(-1):(1))<0)); 
					if(idx.inRange(srs))
					{
						auto newSel = srs[idx]; 
						textSelections.items = ((isPrev)?(newSel~ts):(ts~newSel)); 
						addInspectorParticle(newSel.worldBounds, clWhite, actSel.worldBounds); 
					}
					else
					im.flashWarning("No more matches."); 
					
					//Todo: must not select text inside error messages!
					
					return; 
				}
			}
			
			//When there is no selection, try to make it from the hovered keyword
			if(!help.actSearchKeywordSelection.isZeroLength)
			{
				textSelections.items = help.actSearchKeywordSelection; 
				addInspectorParticle(help.actSearchKeywordSelection.worldBounds, clWhite, bounds2.init); 
			}
			else im.flashWarning("Nothing to select."); 
		} 
		
		void makeModuleDependencyGraph()
		{
			insight.initialize; auto ddb = insight.ddb; 
			
			string lastFQN; 
			auto findModuleDeclarationsByFile(ModuleDeclarations md, File f, string path="")
			{
				path ~= '.' ~ md.name; 
				if(sameFile(md.file, f)) { lastFQN = path.withoutStarting(".."); return md; }
				foreach(a; md.modules)
				{ if(auto res = findModuleDeclarationsByFile(a, f, path)) return res; }
				lastFQN = ""; return null; 
			}; 
			
			version(/+$DIDE_REGION Collect selected modules and moduleDeclarations+/all)
			{
				Module[string] moduleByName; 
				ModuleDeclarations[string] moduleDeclarationsByName; 
				
				foreach(m; modules.selectedModules/+OrAll+/)
				if(auto md = findModuleDeclarationsByFile(ddb.root, m.file))
				{
					moduleByName[lastFQN] = m; 
					moduleDeclarationsByName[lastFQN] = md; 
				}
			}
			
			version(/+$DIDE_REGION Build import dependency graph+/all)
			{
				bool[Module][Module] moduleImportGraph; 
				foreach(name, m; moduleByName)
				{
					auto md = moduleDeclarationsByName[name]; 
					foreach(const ref member; md.members)
					with(member)
					if(category==Category.import_)
					if(auto im = moduleByName.get(member.name))
					moduleImportGraph[m][im] = true; 
				}
			}
			
			version(/+$DIDE_REGION Apply import info to the actual modules+/all)
			{
				foreach(m; modules.modules) m.importedModules = []; 
				foreach(importer, imports; moduleImportGraph)
				{
					importer.importedModules = imports.keys; 
					
					static if((常!(bool)(0))/+dump import graph+/)
					{
						print(importer.file.name~':'); 
						foreach(imported; imports.byKey) print("  "~imported.file.name); 
					}
				}
			}
			
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
						[q{"Ctrl+Up"},q{scrollLineUp},q{navig.scrollV(DefaultFontHeight); }],
						[q{"Ctrl+Down"},q{scrollLineDown},q{navig.scrollV(-DefaultFontHeight); }],
						[q{"Alt+PgUp"},q{scrollPageUp},q{navig.scrollV(mainWindow.clientHeight*.9); }],
						[q{"Alt+PgDn"},q{scrollPageDown},q{navig.scrollV(-mainWindow.clientHeight*.9); }],
						[q{"Ctrl+="},q{zoomIn},q{navig.zoom (.5); }],
						[q{"Ctrl+-"},q{zoomOut},q{navig.zoom (-.5); }],
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
						[q{"W Num8 Up"},q{holdScrollUp2},q{if(NOSEL) navig.scrollV(navig.scrollSpeed); }],
						[q{"S Num2 Down"},q{holdScrollDown2},q{if(NOSEL) navig.scrollV(-navig.scrollSpeed); }],
						[q{"A Num4 Left"},q{holdScrollLeft2},q{if(NOSEL) navig.scrollH(navig.scrollSpeed); }],
						[q{"D Num6 Right"},q{holdScrollRight2},q{if(NOSEL) navig.scrollH(-navig.scrollSpeed); }],
						[q{"E Num+ PgUp"},q{holdZoomIn2},q{if(NOSEL) navig.zoom (navig.zoomSpeed); }],
						[q{"Q Num- PgDn"},q{holdZoomOut2},q{if(NOSEL) navig.zoom (-navig.zoomSpeed); }],
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
						[q{"Shift+W Shift+Up"},q{holdScrollUp_slow2},q{if(NOSEL) navig.scrollV(navig.scrollSpeed/8); }],
						[q{"Shift+S Shift+Down"},q{holdScrollDown_slow2},q{if(NOSEL) navig.scrollV(-navig.scrollSpeed/8); }],
						[q{"Shift+A Shift+Left"},q{holdScrollLeft_slow2},q{if(NOSEL) navig.scrollH(navig.scrollSpeed/8); }],
						[q{"Shift+D Shift+Right"},q{holdScrollRight_slow2},q{if(NOSEL) navig.scrollH(-navig.scrollSpeed/8); }],
						[q{"Shift+E Shift+PgUp"},q{holdZoomIn_slow2},q{if(NOSEL) navig.zoom (navig.zoomSpeed/8); }],
						[q{"Shift+Q Shift+PgDn"},q{holdZoomOut_slow2},q{if(NOSEL) navig.zoom (-navig.zoomSpeed/8); }],
					]))
				) .GEN!q{GEN_verbs(Yes.hold)}); 
			}
			version(/+$DIDE_REGION ZoomAll/Close          +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Home"},q{zoomAll2},q{if(NOSEL) navig.scrollInAllModules; }],
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
						[q{"Ctrl+Alt+Up"},q{insertCursorAbove},q{textSelections.insertCursorAbove; }],
						[q{"Ctrl+Alt+Down"},q{insertCursorBelow},q{textSelections.insertCursorBelow; }],
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
						[q{"Shift+Alt+Up"},q{extendSelection},q{if(!textSelections.extend) { if((常!(bool)(0))) im.flashWarning("Unable to extend selection."); }}],
						[q{"Shift+Alt+Down"},q{shrinkSelection},q{if(!textSelections.shrink) { if((常!(bool)(0))) im.flashWarning("Unable to shrink selection."); }}],
						[q{"Shift+Alt+U"},q{insertCursorAtStartOfEachLineSelected},q{textSelections.insertCursorAtStartOfEachLineSelected; }],
						[q{"Shift+Alt+I"},q{insertCursorAtEndOfEachLineSelected},q{textSelections.insertCursorAtEndOfEachLineSelected; }],
						[q{"Ctrl+A"},q{selectAll},q{
							textSelections.selectAll; 
							//textSelections.items = extendAll(textSelections[]); 
							/+
								textSelections.items = modulesWithTextSelection
								.map!(m => m.content.allSelection(textSelections[].any!(s => s.primary && s.moduleOf is m))).array; 
							+/
						}],
						[q{"Ctrl+Shift+A"},q{selectAllModules},q{textSelections.clear; modules.modules.each!(m => m.flags.selected = true); navig.scrollInAllModules; }],
						[q{""},q{deselectAllModules},q{
							modules.modules.each!(m => m.flags.selected = false); 
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
							editor.copy_impl(textSelections[].zeroLengthSelectionsToFullRows); 
							/+
								Bug: selection.isZeroLength Ctrl+C then Ctrl+V	It breaks the line. 
								Ez megjegyzi, hogy volt-e selection extension es	ha igen, akkor sorokon dolgozik. 
								A sorokon dolgozas feltetele az, hogy a target is zeroLength legyen. 
							+/
						}],
						[q{"Ctrl+X Shift+Del"},q{cut},q{
							TextSelection[] s1 = textSelections[].zeroLengthSelectionsToFullRows, s2; 
							editor.copy_impl(s1); editor.cut_impl2(s1, s2); textSelections.items = s2; 
						}],
						[q{"Backspace"},q{deleteToLeft},q{
							TextSelection[] s1 = textSelections[].zeroLengthSelectionsToOneLeft , s2; 
							editor.cut_impl2(s1, s2); textSelections.items = s2; 
							//Todo: delete all leading tabs when the cursor is right after them
							/+Todo: Ctrl+Backspace = deletes words+/
						}],
						[q{"Del"},q{deleteFromRight},q{
							TextSelection[] s1 = textSelections[].zeroLengthSelectionsToOneRight, s2; 
							editor.cut_impl2(s1, s2); textSelections.items = s2; 
							/+
								Bug: ha readonly, akkor NE tunjon el a kurzor! Sot, 
								ha van non-readonly selecton is, akkor azt meg el is bassza. 
							+/
							//Bug: delete should remove the leading tabs.
							/+Todo: Ctrl+Del = deletes words+/
						}],
						[q{"Ctrl+V Shift+Ins"},q{paste},q{textSelections.items = editor.paste_impl(textSelections[], clipboard.text); }],
						[q{"Tab"},q{insertTab},q{textSelections.items = editor.paste_impl(textSelections[], "\t"); }],
						[q{"Enter"},q{insertNewLine},q{
							textSelections.items = editor.paste_impl(textSelections[], "\n", Yes.duplicateTabs); 
							//Todo: Must fix the tabCount on the current line first, and after that it can duplicate.
						}],
						[q{"Shift+Enter"},q{insertNewPage},q{
							/+
								Todo: it should automatically insert at the end of the selected rows.
								But what if the selection spans across multiple rows...
							+/
							textSelections.items = editor.paste_impl(textSelections[], "\v"); 
							//Vertical Tab -> MultiColumn
						}],
						[],
						[q{"Ctrl+]"},q{indent},q{
							insertCursorAtStartOfEachLineSelected; 
							editor.paste_impl(textSelections[], "\t"); 
						}],
						[q{"Ctrl+["},q{outdent},q{
							insertCursorAtStartOfEachLineSelected; 
							auto ts = selectCharAtEachSelection(textSelections[], '\t'); 
							if(!ts.empty)
							{
								textSelections.items = ts; 
								deleteToLeft; 
							}
							else
							{ im.flashWarning("Unable to outdent."); }
						}],
						[q{"Alt+Up"},q{moveLineUp},q{
							//TextSelection[] s1 = textSelections[].zeroLengthSelectionsToFullRows, s2;
							//editor.copy_impl(s1); editor.cut_impl2(s1, s2); textSelections.items = s2;
							//Todo: moveLineUp
						}],
						[q{"Alt+Down"},q{moveLineDown},q{/+Todo: moveLineDown+/}],
						[q{"Ctrl+Z"},q{undo},q{if(modules.expectOneSelectedModule) editor.undoRedo_impl!"undo"; }],
						[q{"Ctrl+Y"},q{redo},q{if(modules.expectOneSelectedModule) editor.undoRedo_impl!"redo"; }],
						[],
					]))
				) .GEN!q{GEN_verbs}); 
			}
			version(/+$DIDE_REGION Operations       +/all)
			{
				mixin((
					(表([
						[q{/+Note: Key+/},q{/+Note: Name+/},q{/+Note: Script+/}],
						[q{"Alt+O"},q{openModule},q{modules.openModule; }],
						[q{"Alt+Shift+O"},q{openModuleRecursive},q{modules.openModuleRecursive; }],
						[q{"Ctrl+R"},q{revertSelectedModules},q{
							textSelections.preserve
							(
								{
									foreach(m; modules.selectedModules)
									{ m.reload(desiredStructureLevel); m.fileLoaded = now; }
								}
							); 
						}],
						[],
						[q{"Alt+S"},q{saveSelectedModules},q{editor.feedAndSaveModules(modules.selectedModules); }],
						[q{"Ctrl+S"},q{saveSelectedModulesIfChanged},q{editor.feedAndSaveModules(modules.selectedModules.filter!"a.changed"); }],
						[q{"Ctrl+Alt+S"},q{saveSelectedModulesIfChanged_noSyntaxCheck},q{editor.feedAndSaveModules(modules.selectedModules.filter!"a.changed", No.syntaxCheck); }],
						[q{"Ctrl+Shift+S"},q{saveAllModulesIfChanged},q{editor.feedAndSaveModules(modules.modules.filter!"a.changed"); }],
						[],
						[q{"Ctrl+W"},q{closeSelectedModules},q{
							modules.closeSelectedModules; 
							//Todo: this hsould work for selections and modules based on textSelections.empty
						}],
						[q{"Ctrl+Shift+W"},q{closeAllModules},q{modules.closeAllModules; }],
						[],
						[q{"Ctrl+F"},q{searchBoxActivate(bool global=false)},q{
							insight.deactivate; outline.deactivate; /+Todo: motherfucking lame+/
							search.activate(((help.actSearchKeyword=="$DIDE_PRIMARY_SELECTION$") ?(primaryTextSelection.sourceText) :(help.actSearchKeyword)), global); 
							/+Todo: Does nothing, then the search Edit is in focus.+/
						}],
						[q{"Ctrl+Shift+F"},q{searchBoxActivateGlobal},q{searchBoxActivate(true); }],
						[q{"Ctrl+D"},q{selectNextWord},q{selectAdjacentWord_impl!false; }],
						[q{"Ctrl+Shift+D"},q{selectPrevWord},q{selectAdjacentWord_impl!true; }],
						[q{"Ctrl+Shift+L"},q{selectSearchResults},q{textSelections.select(buildMessages.findResultLayer.searchResults); }],
						[q{"F3"},q{gotoNextFind},q{NOTIMPL; }],
						[q{"Shift+F3"},q{gotoPrevFind},q{NOTIMPL; }],
						[q{"Ctrl+G"},q{gotoLine},q{
							if(auto m = modules.expectOneSelectedModule)
							{ search.activate(":"); }
						}],
						[q{"F8"},q{gotoNextError},q{NOTIMPL; }],
						[q{"Shift+F8"},q{gotoPrevError},q{NOTIMPL; }],
						[],
						[q{"Ctrl+O"},q{outlineActivate},q{
							search.deactivate(this.buildMessages); insight.deactivate; /+Todo: motherfucking lame+/
							outline.activate; 
						}],
						[q{"Ctrl+Space"},q{insightActivate},q{
							search.deactivate(this.buildMessages); outline.deactivate; /+Todo: motherfucking lame+/
							insight.activate(
								/+Todo: a szonak csak az elejet kene kimasolni!+/
								((help.actSearchKeyword=="$DIDE_PRIMARY_SELECTION$") ?(primaryTextSelection.sourceText) :(help.actSearchKeyword))
							); 
						}],
						[],
						[q{""},q{feed},q{
							enforce(buildServices.ready, "BuildSystem is working."); 
							textSelections.preserve({ editor.feedChangedModule(primaryModule); }); 
						}],
						[],
						[q{"F9"},q{run},q{
							with(buildServices)
							if(ready && !running)
							{
								editor.feedAndSaveModules(modules.changedProjectModules); 
								run; 
							}
						}],
						[q{"Shift+F9"},q{rebuild},q{
							with(buildServices)
							if(ready && !running)
							{
								editor.feedAndSaveModules(modules.changedProjectModules); 
								buildMessages.messageUICache.clear; //Todo: This UI cache should be emptied automatically.
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
						[q{"F1"},q{help_combined},q{help.combinedSearch; }],
						[q{"Shift+F1"},q{help_bing},q{help.bing; }],
						[q{"Ctrl+F1"},q{help_dlang},q{help.dpldocs; }],
						[q{"Alt+F1"},q{help_deepsearch},q{help.deepsearch; }],
						[q{"Alt+A"},q{initiateAi},q{aiManager.initiate; }],
						[q{"Ctrl+Enter"},q{launchAi},q{aiManager.launch; }],
						[],
						[q{//Experimental
						}],
						[q{"F1"},q{function1},q{/+it's the help+/ }],
						[q{"F2"},q{function2},q{}],
						[q{"F3"},q{function3},q{makeModuleDependencyGraph; }],
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
						[q{"Ctrl+Alt+Numₙ"},q{storeLocationₙ},q{navig.storeLocation(ₙ); }],
						[q{"Ctrl+Numₙ"},q{jumpToLocationₙ},q{navig.jumpToLocation(ₙ); }],
						[],
						[q{"Ctrl+Alt+ₙ"},q{copyMemSlotₙ},q{editor.copyMemSlot(ₙ); }],
						[q{"Ctrl+ₙ"},q{pasteMemSlotₙ},q{editor.pasteMemSlot(ₙ); }],
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
							textSelections.preserve
							(
								{
									textSelections.visitSelectedNestedCodeColumns((col){ col.removeVerticalTabs; }); 
									textSelections.visitSelectedNestedCodeColumns((col){ col.addVerticalTabs(1400); }); 
								}
							); 
						}],
						[q{""},q{removeVerticalTabs},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							textSelections.preserve
							({ textSelections.visitSelectedNestedCodeColumns((col){ col.removeVerticalTabs; }); }); 
						}],
						[q{""},q{addInternalNewLines},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							textSelections.visitSelectedNestedDeclarations((decl){ decl.internalNewLineCount = 1; decl.needMeasure; }); 
						}],
						[q{""},q{removeInternalNewLines},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							textSelections.visitSelectedNestedDeclarations((decl){ decl.internalNewLineCount = 0; decl.needMeasure; }); 
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
						[q{"Shift+Alt+9"},q{insertBraceBlock},q{editor.insertNode("(\0)", 0); }],
						[q{"Shift+Alt+0"},q{insertBraceBlock_closing},q{editor.insertNode("(\0)"); }],
						[q{"Alt+["},q{insertSquareBlock},q{editor.insertNode("[\0]", 0); }],
						[q{"Alt+]"},q{insertSquareBlock_closing},q{editor.insertNode("[\0]"); }],
						[q{"Shift+Alt+["},q{insertCurlyBlock},q{editor.insertNode("{\0}", 0); }],
						[q{"Shift+Alt+]"},q{insertCurlyBlock_closing},q{editor.insertNode("{\0}"); }],
						[q{"Alt+`"},q{insertDString},q{editor.insertNode("`\0`", 0); }],
						[q{"Alt+'"},q{insertCChar},q{editor.insertNode("'\0'"); }],
						[q{"Shift+Alt+'"},q{insertCString},q{editor.insertNode("\"\0\"", 0); }],
						[q{/+"Shift+Alt+I+'"q{insertInterpolatedCString}q{editor.insertNode("i\"\0\"", 0); }+/}],
						[q{/+"Alt+I+`"q{insertInterpolatedDString}q{editor.insertNode("i`\0`", 0); }+/}],
						[q{"Shift+Alt+4"},q{insertStringExpression},q{editor.insertNode("$(\0)", 0); }],
						[q{"Alt+/"},q{insertDComment},q{editor.insertNode("/+\0+/", 0); }],
						[q{"Shift+Alt+/"},q{insertTenary},q{
							editor.insertNode("((\0)?():())", 0); 
							//Todo: must be inserted as an expression!!!
						}],
						[q{"Shift+Alt+;"},q{insertGenericArg},q{
							editor.insertNode("((\0).genericArg!q{})", 0); 
							//Todo: must be inserted as an expression!!!
						}],
					]))
				) .GEN!q{GEN_verbs}); 
			}
		}
	}version(/+$DIDE_REGION Draw     +/all)
	{
		void customDraw(Drawing dr)
		{
			//customDraw //////////////////////////////
			if(textSelections.empty)
			{
				//select means module selection
				foreach(m; modules.modules)
				if(m.flags.selected)
				drawHighlight(dr, m, clAccent, .25); 
				if(!lod.codeLevel)
				{
					if(0/+It's annoying, so I disabled it.+/)
					drawHighlight(dr, modules.hoveredModule, clWhite, .125); 
				}
			}
			else
			{
				//select means text editing
				foreach(m; modules.modules)
				if(!m.flags.selected)
				drawHighlight(dr, m, clGray, .25); 
			}
			
			if(lod.moduleLevel || buildServices.building) modules.drawModuleBuildStates(dr); 
			
			modules.drawModuleLoadingHighlights!"fileLoaded"(dr, clAqua  ); 
			modules.drawModuleLoadingHighlights!"fileSaved" (dr, clYellow); 
			
			modules.drawMainModuleOutlines(dr); 
			modules.drawFolders(dr, clGray, clWhite); 
			modules.drawSelectionRect(dr, clAccent); 
			
			if(auto b = help.actSearchKeywordBounds)
			{
				dr.color = clWhite; dr.alpha = .6*blink; dr.lineWidth = 2; dr.lineStyle = LineStyle.dot; 
				dr.drawRect(b); 
				dr.lineStyle = LineStyle.normal; 
				dr.alpha = 1; 
			}
			
			buildMessages.drawLayers(dr, mainView); 
			
			drawChangeIndicators(dr, globalChangeindicatorsAppender[]); globalChangeindicatorsAppender.clear; 
			
			buildMessages.drawMessageConnectionArrows(dr, mainView); 
			
			mixin(求each(q{ref p},q{inspectorParticles},q{p.updateAndDraw(dr)})); 
			
			textSelections.draw(dr, mainView); //Bug: this will not work for multiple workspace views!!!
			
			modules.drawModuleImportGraph(dr); 
			
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
			globalVisualizeSpacesAndTabs = !textSelections.empty; 
			
			globalChangeindicatorsAppender.clear; 
			mixin(求each(q{m},q{modules.modules},q{m.visibleConstantNodes.clear})); 
			
			structureMap.beginCollect; 
			super.draw(dr); 
			structureMap.endCollect(dr); 
			//customDraw(dr); 
		} 
	}
} 