module dideworkspace; 

import het.ui, dideui, didebase; 

import het.parser : CodeLocation, SyntaxKind, syntaxFontColor, syntaxBkColor; 
import buildsys : DMDMessage, decodeDMDMessages, BuildSettings, BuildSystem, BuildResult, ModuleBuildState, moduleBuildStateColors; 

import diderow : CodeRow; 
import didecolumn : CodeColumn; 
import didenode : CodeNode, CodeComment, StructureMap, visitNestedCodeColumns, visitNestedCodeNodes; 
import didedecl : Declaration, 	/+these are for statistics only ->+/dDeclarationRecords, processHighLevelPatterns_block; 
import didemodule : Module, moduleOf, WorkspaceInterface, StructureLevel, TextFormat, TextModification, addInspectorParticle, TextModificationRecord, Breadcrumb, toBreadcrumbs, nearestDeclarationBlock, DefaultNewLine, compoundObjectChar, AnimatedCursors, MaxAnimatedCursors, rearrangeLOG, drawChangeIndicators, globalChangeindicatorsAppender, globalVisualizeSpacesAndTabs, inspectorParticles, ScrumTable, ScrumSticker; 
import didemodulemanager : ModuleManager; 
import didetextselectionmanager : TextSelectionManager; 
import dideinsight : ModuleDeclarations, DDB, Insight; 
import dideai : AiManager; 
alias blink = dideui.blink; 


class BuildMessageManager
{
	mixin SmartChild!q{ModuleManager modules}; 
	
	
	struct MarkerLayerSettings
	{
		const DMDMessage.Type type; //this is the identity
		bool visible = true; //this is the settings
		bounds2 btnWorldBounds; //Screen bounds of the button, for particle effect.
	} 
	
	auto markerLayerSettings = [EnumMembers!(DMDMessage.Type)].map!MarkerLayerSettings.array; 
	
	
	CodeRow[string] messageUICache; 
	string[string] messageSourceTextByLocation; 
	
	static struct MessageConnectionArrow
	{
		vec2 p1, p2; 
		DMDMessage.Type type; 
		bool isException; //a side-information for type
	} 
	bool[MessageConnectionArrow] messageConnectionArrows; 
	
	uint _messageConnectionArrows_hash; 
	
	Module.Message[] incomingVisibleModuleMessageQueue; 
	bool firstErrorMessageArrived; 
	
	
	auto getMarkerLayerCount(DMDMessage.Type type)
	{ return (mixin(求sum(q{mod},q{modules.modules},q{((type==DMDMessage.Type.find)?(mod.findSearchResults.length) :(mod.messagesByType[type].length))}))); } 
	
	auto getMarkerLayer_find()
	{ return modules.modules.map!((m)=>(m.findSearchResults)).joiner; } 
	
	auto getMarkerLayer(DMDMessage.Type type)
	{
		enforce(type!=DMDMessage.Type.find); 
		return modules.modules.map!((m)=>(m.messagesByType[type].map!((msg)=>(msg.searchResults)).joiner)).joiner; 
	} 
	
	auto clearMarkerLayer_find()
	{ foreach(m; modules.modules) m.findSearchResults = []; } 
	
	
	void process(DMDMessage[] messages)
	{ mixin(求each(q{m},q{messages},q{process(m)})); } 
	
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
	
	void appendMessageConnectionArrows(DMDMessage rootMessage)
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
					auto sr = codeLocationToSearchResults(msg.location, &modules.findModule); 
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
	
	void updateMessageConnectionArrows()
	{
		if(_messageConnectionArrows_hash.chkSet(mixin(求sum(q{m},q{modules.modules},q{m._updateSearchResults_state}))))
		{
			messageConnectionArrows.clear; 
			foreach(t; [EnumMembers!(DMDMessage.Type)])
			if(!t.among(DMDMessage.Type.find, DMDMessage.Type.console))
			{
				foreach(mod; modules.modules)
				foreach(mm; mod.messagesByType[t])
				appendMessageConnectionArrows(mm.message); 
			}
			//5.6ms, not bad
		}
	} 
	
	void process(DMDMessage msg)
	{
		if(!modules.mainModule) return; 
		
		static bool disable = false; 
		
		try
		{
			auto 	msgNode 	= renderBuildMessage(msg),
				layer 	= &markerLayerSettings[msg.type]; 
			
			
			Container.SearchResult[] searchResults; 
			
			CodeNode getContainerNode(lazy CodeNode fallbackNode=null)
			{
				searchResults = codeLocationToSearchResults(msg.location, &modules.findModule); 
				
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
			
			auto containerModule = modules.findModule(msg.location.file).ifNull(modules.mainModule); 
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
	
	void zoomAt(R)(View2D view, R searchResults)
	if(isInputRange!(R, .Container.SearchResult))
	{
		if(searchResults.empty) return; 
		const maxScale = max(view.scale, 1); 
		view.zoom(searchResults.map!(r => r.bounds).fold!"a|b", 12); 
		view.scale = min(view.scale, maxScale); 
	} 
	
	void UI_BuildMessageType(DMDMessage.Type bmt, View2D view, )
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
	
	void drawMessageConnectionArrows(Drawing dr, View2D view)
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
		
		const pixelSize = view.invScale_anim; 
		
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
} 


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
		
		@STORED ModuleManager modules; 
		TextSelectionManager textSelections; 
		BuildMessageManager buildMessages; 
		
		
		
		//Restrict convertBuildResultToSearchResults calls.
		size_t lastBuildStateHash; 
		bool buildStateChanged; 
		
		Nullable!bounds2 scrollInBoundsRequest; 
		
		struct ResyntaxEntry {
			CodeColumn what; 
			DateTime when; 
		} 
		ResyntaxEntry[] resyntaxQueue; 
		
		SyntaxHighlightWorker syntaxHighlightWorker; 
		
		StructureMap structureMap; 
		
		void smartScrollTo(bounds2 b)
		{ mainView.smartScrollTo(b); } 
		
		ref desiredStructureLevel()
		=> modules.desiredStructureLevel; 
		
		void setTextSelectionReference(string s)
		{ textSelections.items = [TextSelectionReference(s, &modules.findModule).fromReference]; } 
		
		Container workspaceContainer()
		=> this/+safe access to functions needeng a workspace. 'this' would be unsafe.+/; 
		
		this()
		{
			modules = new ModuleManager; 
			modules.workspaceContainer = this; 
			modules.afterModulesChanged = &updateSubCells; 
			modules.onSmartScrollTo = &smartScrollTo; 
			modules.onGetPrimaryModule = &primaryModule; 
			modules.onSetTextSelectionReference = &setTextSelectionReference; 
			
			buildMessages = new BuildMessageManager(modules); 
			
			textSelections = new TextSelectionManager(this, modules); 
			
			aiManager.textSelections = textSelections; 
			aiManager.pasteText = &pasteText; 
			aiManager.insertNode = &insertNode; 
			aiManager.insertNewLine = &insertNewLine; 
			aiManager.cursorLeftSelect = &cursorLeftSelect; 
			aiManager.deleteToLeft = &deleteToLeft; 
			
			
			flags.targetSurface = 0; 
			flags.noBackground = true; 
			syntaxHighlightWorker = new SyntaxHighlightWorker; 
			structureMap = new StructureMap; 
			needMeasure; 
		} 
		
		~this()
		{
			syntaxHighlightWorker.free; 
			modules.free; 
		} 
		
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
				foreach(idx, const layer; buildMessages.markerLayerSettings) if(!layer.visible) res |= 1 << idx; 
				return res; 
			} 
			void markerLayerHideMask(size_t v)
			{ foreach(idx, ref layer; buildMessages.markerLayerSettings) layer.visible = ((1<<idx)&v)==0; } 
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
			=> textSelections[].map!(s => s.moduleOf).nonNulls.uniq; 
			
			
			/+
				+Selects all the CodeColumns under the cursors. 
				If there is none, selects all the modules' content CodeColumns.
			+/
			CodeColumn[] selectedOuterColumns()
			{
				CodeColumn[] cols; 
				
				foreach(c; textSelections[].map!"a.codeColumn")
				if(!cols.canFind(c)) cols ~= c; 
				if(cols.empty)
				foreach(c; modules.selectedModules.map!"a.content")
				cols ~= c; 
				
				return cols; 
			} 
			
			
			
			
			
		}
	}version(/+$DIDE_REGION+/all)
	{
		
		
		override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0))
		{
			ofs += innerPos; 
			foreach_reverse(m; modules.modules) {
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
		
	}version(/+$DIDE_REGION Cursor/Selection stuff+/all)
	{
		TextCursor createCursorAt(vec2 p)
		{ return cellLocationToTextCursor(locate_snapToRow(p), workspaceContainer); } 
		
		//textSelection, cursor movements /////////////////////////////
		
		int lineSize()
		{ return DefaultFontHeight; } 
		int pageSize()
		{ return (mainView.subScreenBounds_anim.height/lineSize*.9f).iround.clamp(2, 100); } 
		
		
		void cursorOp(ivec2 dir, bool select, bool stepInOut=false)
		{ auto ts = textSelections[]; applyCursorOp(ts, dir, select, stepInOut); textSelections.items = ts; } 
		
		void insertCursor(int dir)
		{
			auto 	prev = textSelections[],
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
			
			textSelections.items = merge(prev ~ next); 
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
			
			void scrollInModules(Module[] m)
			{ if(m.length) scrollInBoundsRequest = m.map!"a.outerBounds".fold!"a|b"; } 
			
			void scrollInAllModules()
			{ scrollInModules(modules.modules); } 
			
			void scrollInModule(Module m)
			{ if(m) scrollInModules([m]); } 
		}
		
		void cancelSelection_impl()
		{
			auto pm = modules.primaryModule; 
			
			void selectPrimaryModule()
			{ textSelections.clear; modules.select(pm); scrollInModule(pm); } 
			
			//multiTextSelect -> primaryTextSelect
			if(auto pts = primaryTextSelection)
			{ textSelections.items = pts; return; }
			
			void deselectAllModules()
			{ modules.modules.each!((m)=>(m.flags.selected = false)); } 
			
			if(!textSelections.empty)
			{ textSelections.clear; deselectAllModules; return; }
			
			//as a final act, zoom all
			deselectAllModules; scrollInAllModules; 
		} 
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
		void undoRedo_impl(string what)()
		{
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
			
			void executeUndoRedoRecord(in bool isUndo, in bool isInsert, in TextModificationRecord rec)
			{
				TextSelection ts; 
				bool decodeTs(bool reduceToStart)
				{
					string where = rec.where; 
					if(reduceToStart) where = where.reduceTextSelectionReferenceStringToStart; 
					ts = TextSelection(where, &modules.findModule); 
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
					textSelections.items = ts; 
				}
			} 
			
			void executeUndoRedo(bool isUndo)(in TextModification tm)
			{
				static if(isUndo) auto r = tm.modifications.retro; else auto r = tm.modifications; 
				r.each!(m => executeUndoRedoRecord(isUndo, tm.isInsert, m)); 
			} 
			
			void execute_undo(in TextModification tm)
			{ executeUndoRedo!true (tm); } void execute_redo(in TextModification tm)
			{ executeUndoRedo!false(tm); } 
			
			void execute_reload(string where, string what)
			{
				if(auto m=modules.findModule(File(where)))
				{
					m.reload(desiredStructureLevel, nullable(what)); 
					//selectAll
					textSelections.items = [m.content.allSelection(true)]; 
					//Todo: refactor codeColumn.allTextSelection(bool primary or not)
				}
				else
				assert(0, "execute_reload: module lost: "~where.quoted); 
				//Todo: somehow signal bact to the undo manager, if an undo operation is failed
			} 
			
			//Todo: select the latest undo/redo operation if there are more than 
			//one modules selected. If no modules selected: select from all of them.
			if(auto m = modules.primaryModule)
			{
				//Todo: undo should not remove textSelections on other modules.
				mixin(q{m.undoManager.$(&execute_$, &execute_reload); }.replace("$", what)); 
				textSelections.invalidateTextSelections; //because executeUndo don't call measure() so desiredX's are invalid.
			}
		} 
	}version(/+$DIDE_REGION Resyntax+/all)
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
	}version(/+$DIDE_REGION Cut   +/all)
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
		{ if(s!="") textSelections.items = paste_impl(textSelections[], s); }  void insertNode(string source, int subColumnIdx=-1)
		{
			textSelections.items = paste_impl(
				textSelections[], source, No.duplicateTabs, 
				Yes.isObject, subColumnIdx, TextFormat.managed_optionalBlock
			); 
		} 
		
	}version(/+$DIDE_REGION Update+/all)
	{
		
		
		//Todo: Ctrl+D word select and find
		
		//Mouse ---------------------------------------------------
		
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
			
			if(auto mod = modules.findModule(loc.file))
			{
				/+
					Todo: load the module automatically, 
					focus on module if no line number.  -> Insight
				+/
				
				
				auto searchResults = codeLocationToSearchResults(loc, &modules.findModule); 
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
								if(!modules.findModule(loc.file) && inputs["Shift"].down)
								{
									if(!loc.file.exists)
									{ im.flashWarning(i"File not found $(loc.file.fullName.quoted).".text); return; }
									modules.loadModule(loc.file); 
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
				updateResyntaxQueue; 
				
				measure; //measures all containers if needed, updates ElasticTabstops
				//textSelections = validTextSelections;  //this validation is required for the upcoming mouse handling
				//and scene drawing routines.
				
				//From here every positions and sizes are correct -----------------------------------------
				
				
				//particle effects for incoming messages
				foreach(mm; buildMessages.incomingVisibleModuleMessageQueue.fetchAll)
				{
					auto layer = &buildMessages.markerLayerSettings[mm.type]; 
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
						jumpTo(mm); 
						im.flashError(mm.message.oneLineText); 
						bloodScreenEffect.activate; 
					}
				}
				
				handleJumps(view); //jumping to locations with MMB 
				
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
				const textSelectionChanged = textSelections.update(view, &createCursorAt, mainIsForeground, wheelSpeed); 
				
				//Only if there are any cursors, module selection is forced to modules with textSelections
				if(textSelectionChanged && textSelections.length)
				{
					foreach(m; modules.modules) m.flags.selected = false; 
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
				else if(!textSelections.scrollInRequest.isNull)
				{
					const p = textSelections.scrollInRequest.get; 
					mainView.scrollZoom(bounds2(p, p)); 
				}
				else if(textSelectionChanged)
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
					return modules.modules	.map!"tuple(a.file, a.outerPos)"
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
		AiManager aiManager; 
		
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
			{ if(searchBoxVisible.chkClear) { searchText = ""; workspace.buildMessages.clearMarkerLayer_find; }} 
			
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
										workspace.buildMessages.clearMarkerLayer_find; 
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
											
											workspace.textSelections.clear; 
											if(auto mod = workspace.modules.expectOneSelectedModule)
											if(auto line = searchText[1..$].to!int.ifThrown(0))
											{
												workspace.jumpTo(format!"%s%s(%d,1)"(CodeLocationPrefix, mod.file.fullName, line)); 
												//Todo: show a highlight on that row...
											}
											
										}
										else
										{
											auto mods = lookInAllModules ? workspace.modules.modules : workspace.modules.selectedModules; 
											if(mods.empty && lookInAllModules.chkSet) { mods = workspace.modules.modules; }
											searchFiber = new SearchFiber(mods, searchText, searchOptions, &searchStats); 
											/+Note: the old searchFiber stops because it loses all references and will not be called again.+/
										}
									}
									//display the number of matches. Also save the location of that number on the screen.
									const matchCnt = workspace.buildMessages.getMarkerLayerCount(DMDMessage.Type.find); 
									Row({ if(matchCnt) Text(" ", clGray, matchCnt.text, " "); }); 
									
									BtnRow(
										{
											if(
												Btn(
													"🔍", isFocused(editContainer) ? kcFindZoom : KeyCombo(""),
													enable(matchCnt>0), hint("Zoom screen on search results.")
												)
											)
											{ workspace.buildMessages.zoomAt(view, workspace.buildMessages.getMarkerLayer_find); }
											if(
												Btn(
													"Sel", isFocused(editContainer) ? kcFindToSelection : KeyCombo(""),
													enable(matchCnt>0), hint("Select search results.")
												)
											)
											{ workspace.textSelections.select(workspace.buildMessages.getMarkerLayer_find); }
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
									mod = ws.modules.findModule(fullName.File/+Opt: this is a slow query+/); 
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
												return ws.modules.modules.filter!((m)=>(m.file.fullName.map!toLower.startsWith(p))).cache; 
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
													ws.modules.loadModule(f); 
													if(inputs.Alt.down)
													ws.modules.queueModuleRecursive(f); 
												}else { jumpTo(fullName, isDoubleClick); }
												
												if(canSelectModules)
												{
													foreach(m; ws.modules.modules) m.flags.selected = false; 
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
								auto m = ws.modules.findModule(f); 
								if(!m) { ws.modules.loadModule(f); m = ws.modules.findModule(f); }
								if(m) {
									if(!line) ws.jumpTo(m); 
									else { ws.jumpTo(CodeLocation(f.fullName, line.max(1), col.max(1))); }
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
			auto s = textSelections[].sourceText; 
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
			textSelections.items = paste_impl(textSelections[], storedMemSlots[n]); 
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
				buildMessages.process(messages); 
				
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
			buildMessages.firstErrorMessageArrived = true; 
			
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
			textSelections.preserve(
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
			if(!actSearchKeywordSelection.isZeroLength)
			{
				textSelections.items = actSearchKeywordSelection; 
				addInspectorParticle(actSearchKeywordSelection.worldBounds, clWhite, bounds2.init); 
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
						[q{"Ctrl+Shift+A"},q{selectAllModules},q{textSelections.clear; modules.modules.each!(m => m.flags.selected = true); scrollInAllModules; }],
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
							copy_impl(textSelections[].zeroLengthSelectionsToFullRows); 
							/+
								Bug: selection.isZeroLength Ctrl+C then Ctrl+V	It breaks the line. 
								Ez megjegyzi, hogy volt-e selection extension es	ha igen, akkor sorokon dolgozik. 
								A sorokon dolgozas feltetele az, hogy a target is zeroLength legyen. 
							+/
						}],
						[q{"Ctrl+X Shift+Del"},q{cut},q{
							TextSelection[] s1 = textSelections[].zeroLengthSelectionsToFullRows, s2; 
							copy_impl(s1); cut_impl2(s1, s2); textSelections.items = s2; 
						}],
						[q{"Backspace"},q{deleteToLeft},q{
							TextSelection[] s1 = textSelections[].zeroLengthSelectionsToOneLeft , s2; 
							cut_impl2(s1, s2); textSelections.items = s2; 
							//Todo: delete all leading tabs when the cursor is right after them
							/+Todo: Ctrl+Backspace = deletes words+/
						}],
						[q{"Del"},q{deleteFromRight},q{
							TextSelection[] s1 = textSelections[].zeroLengthSelectionsToOneRight, s2; 
							cut_impl2(s1, s2); textSelections.items = s2; 
							/+
								Bug: ha readonly, akkor NE tunjon el a kurzor! Sot, 
								ha van non-readonly selecton is, akkor azt meg el is bassza. 
							+/
							//Bug: delete should remove the leading tabs.
							/+Todo: Ctrl+Del = deletes words+/
						}],
						[q{"Ctrl+V Shift+Ins"},q{paste},q{textSelections.items = paste_impl(textSelections[], clipboard.text); }],
						[q{"Tab"},q{insertTab},q{textSelections.items = paste_impl(textSelections[], "\t"); }],
						[q{"Enter"},q{insertNewLine},q{
							textSelections.items = paste_impl(textSelections[], "\n", Yes.duplicateTabs); 
							//Todo: Must fix the tabCount on the current line first, and after that it can duplicate.
						}],
						[q{"Shift+Enter"},q{insertNewPage},q{
							/+
								Todo: it should automatically insert at the end of the selected rows.
								But what if the selection spans across multiple rows...
							+/
							textSelections.items = paste_impl(textSelections[], "\v"); 
							//Vertical Tab -> MultiColumn
						}],
						[],
						[q{"Ctrl+]"},q{indent},q{
							insertCursorAtStartOfEachLineSelected; 
							paste_impl(textSelections[], "\t"); 
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
							//copy_impl(s1); cut_impl2(s1, s2); textSelections.items = s2;
							//Todo: moveLineUp
						}],
						[q{"Alt+Down"},q{moveLineDown},q{/+Todo: moveLineDown+/}],
						[q{"Ctrl+Z"},q{undo},q{if(modules.expectOneSelectedModule) undoRedo_impl!"undo"; }],
						[q{"Ctrl+Y"},q{redo},q{if(modules.expectOneSelectedModule) undoRedo_impl!"redo"; }],
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
						[q{"Alt+S"},q{saveSelectedModules},q{feedAndSaveModules(modules.selectedModules); }],
						[q{"Ctrl+S"},q{saveSelectedModulesIfChanged},q{feedAndSaveModules(modules.selectedModules.filter!"a.changed"); }],
						[q{"Ctrl+Alt+S"},q{saveSelectedModulesIfChanged_noSyntaxCheck},q{feedAndSaveModules(modules.selectedModules.filter!"a.changed", No.syntaxCheck); }],
						[q{"Ctrl+Shift+S"},q{saveAllModulesIfChanged},q{feedAndSaveModules(modules.modules.filter!"a.changed"); }],
						[],
						[q{"Ctrl+W"},q{closeSelectedModules},q{
							modules.closeSelectedModules; 
							//Todo: this hsould work for selections and modules based on textSelections.empty
						}],
						[q{"Ctrl+Shift+W"},q{closeAllModules},q{modules.closeAllModules; }],
						[],
						[q{"Ctrl+F"},q{searchBoxActivate(bool global=false)},q{
							insight.deactivate; outline.deactivate; /+Todo: motherfucking lame+/
							search.activate(((actSearchKeyword=="$DIDE_PRIMARY_SELECTION$") ?(primaryTextSelection.sourceText) :(actSearchKeyword)), global); 
							/+Todo: Does nothing, then the search Edit is in focus.+/
						}],
						[q{"Ctrl+Shift+F"},q{searchBoxActivateGlobal},q{searchBoxActivate(true); }],
						[q{"Ctrl+D"},q{selectNextWord},q{selectAdjacentWord_impl!false; }],
						[q{"Ctrl+Shift+D"},q{selectPrevWord},q{selectAdjacentWord_impl!true; }],
						[q{"Ctrl+Shift+L"},q{selectSearchResults},q{textSelections.select(buildMessages.getMarkerLayer(DMDMessage.Type.find)); }],
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
							textSelections.preserve({ feedChangedModule(primaryCaret.moduleOf); }); 
						}],
						[],
						[q{"F9"},q{run},q{
							with(buildServices)
							if(ready && !running)
							{
								feedAndSaveModules(modules.changedProjectModules); 
								run; 
							}
						}],
						[q{"Shift+F9"},q{rebuild},q{
							with(buildServices)
							if(ready && !running)
							{
								feedAndSaveModules(modules.changedProjectModules); 
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
						[q{"F1"},q{help_bing},q{startChrome(scrapeLinks_bing(actHelpQuery).get(0), actSearchKeyword); }],
						[q{"Ctrl+F1"},q{help_dlang},q{startChrome(scrapeLinks_dpldocs(actSearchKeyword).get(0), actSearchKeyword); }],
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
							textSelections.preserve
							(
								{
									visitSelectedNestedCodeColumns((col){ col.removeVerticalTabs; }); 
									visitSelectedNestedCodeColumns((col){ col.addVerticalTabs(1400); }); 
								}
							); 
						}],
						[q{""},q{removeVerticalTabs},q{
							//Todo: This fucks up Undo/Redo and ignored edit permissions.
							textSelections.preserve
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
		void UI_structureLevel()
		{
			with(im) {
				BtnRow(
					{
						Module[] modules = modules.selectedModules; 
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
									textSelections.preserve
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
							auto msgNode = buildMessages.renderBuildMessage(mm.message); 
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
				foreach(sel; textSelections[])
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
						foreach(s; textSelections[])
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
					
					auto carets = textSelections[].map!getCaretWorldPos.array; 
					
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
			
			if(auto b = actSearchKeywordBounds) {
				dr.color = clWhite; dr.alpha = .6*blink; dr.lineWidth = 2; dr.lineStyle = LineStyle.dot; 
				dr.drawRect(b); 
				dr.lineStyle = LineStyle.normal; 
				dr.alpha = 1; 
			}
			
			resetNearestSearchResult; 
			
			buildMessages.markerLayerSettings[DMDMessage.Type.unknown].visible = false; 
			//markerLayerSettings[DMDMessage.Type.console].visible = true; 
			
			foreach_reverse(t; [EnumMembers!(DMDMessage.Type)])
			if(buildMessages.markerLayerSettings[t].visible)
			{
				void doit(R)(R sr) { drawSearchResults(dr, sr, DMDMessage.typeSyntax[t].syntaxBkColor); } 
				if(t==DMDMessage.Type.find)	doit(buildMessages.getMarkerLayer_find); 
				else	doit(buildMessages.getMarkerLayer(t)); 
			}
			
			if(nearestSearchResult_dist > mainView.invScale*24)
			nearestSearchResult = SearchResult.init; 
			
			if(nearestSearchResult.bounds)
			{ drawSearchResults(dr, [nearestSearchResult], nearestSearchResult_color.mix(clWhite, .5f)); }
			
			drawChangeIndicators(dr, globalChangeindicatorsAppender[]); globalChangeindicatorsAppender.clear; 
			
			buildMessages.drawMessageConnectionArrows(dr, mainView); 
			
			mixin(求each(q{ref p},q{inspectorParticles},q{p.updateAndDraw(dr)})); 
			
			drawTextSelections(dr, mainView); //Bug: this will not work for multiple workspace views!!!
			
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