module didebuildmessagemanager; 

import didebase; 
import didenode : CodeComment, specialCommentMarker; 
import didemodulemanager : ModuleManager; 

class BuildMessageManager
{
	mixin SmartChild!(
		q{ModuleManager modules},
		q{initLayers; }
	); 
	
	
	CodeRow[string] messageUICache; 
	string[string] messageSourceTextByLocation; 
	
	
	Module.Message[] incomingVisibleModuleMessageQueue; 
	bool firstErrorMessageArrived; 
	
	
	void process(DMDMessage[] messages)
	{ mixin(求each(q{m},q{messages},q{process(m)})); } 
	
	static CodeNode createNode(DMDMessage msg, bool hideLocation)
	{
		/+
			Todo: An option to not render all codeLocations.
			- When the next line's location is same as the precceding line's.
			- When the message is at it's designated location.
		+/
		
		auto src = msg.sourceText; 
		
		if(hideLocation)
		{
			/+
				Todo: Maybe not the best solution. 
				A minimized codelocation node would be better with a mouse over hint.
			+/
			enum locMarker = specialCommentMarker~"LOC",
			locPattern = "*/+"~locMarker~" *+/*"; 
			if(src.isWild(locPattern))
			src = i"$(wild[0])/+hidden:/+$(locMarker) $(wild[1])+/+/$(wild[2])".text; 
		}
		
		auto 	msgCol	= new CodeColumn(null, src, TextFormat.managed_block),
			msgRow	= msgCol.rows.frontOrNull.enforce("Can't get builMessageRow."),
			msgNode 	= (cast(CodeNode)(msgRow.subCells.frontOrNull)).enforce("Can't get buildMessageNode."); 
		msgNode.buildMessageHash = msg.hash; 
		msgNode.measure; /+
			It's required to initialize bkColor. 
			For example: Animation effect needs to know the color.
		+/
		return msgNode; 
	} 
	
	
	
	void process(DMDMessage msg)
	{
		if(!modules.mainModule) return; 
		
		static bool disable = false; 
		
		try
		{
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
				void addMessageToModule(CodeNode msgNode, bool isNew)
				{
					auto mm = containerModule.addModuleMessage(isNew, msg, msgNode, searchResults); 
					auto layer = &layers[msg.type]; 
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
							version(/+$DIDE_REGION single line comments+/all)
							{
								if(auto col = row.parent)
								if(auto cmt = (cast(CodeComment)(col.parent)))
								if(isMatchingComment(cmt))
								{ return cmt; }
							}version(/+$DIDE_REGION multiline comments+/all)
							{
								if(sr.cells.length==1)
								if(auto cmt = (cast(CodeComment)(sr.cells[0])))
								if(isMatchingComment(cmt))
								{ return cmt; }
							}
							
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
					
					CodeNode msgNode; 
					if(auto cmt = locateActualComment)
					{
						//only a single searchResult remains, and with the actual persistent message
						msgNode = cmt; 
						searchResults = [nodeToSearchResult(cmt, null)]; 
					}
					else
					{ msgNode = createNode(msg, hideLocation: false); }
					
					addMessageToModule(msgNode, true); 
				}
				else
				{
					//This buildMessage is injected at the bottom of a node.
					auto msgNode = createNode(msg, hideLocation: true); 
					const isNewMessage = containerNode.addBuildMessage(msgNode); 
					searchResults = searchResults ~ nodeToSearchResult(msgNode, null); 
					addMessageToModule(msgNode, isNewMessage); 
				}
			}
			else
			raise(i"Failed to find module  $(msg.location.file), also no MainModule.".text); 
			
		}
		catch(Exception e) { ERR(e.text~"\n"~msg.text); }
	} 
	
	version(/+$DIDE_REGION+/all) {
		alias SearchResult = Container.SearchResult; 
		SearchResult nearestSearchResult;  //Todo: MMB jumps to nearestSearchResult
		float nearestSearchResult_dist; 
		RGB nearestSearchResult_color; 
		
		protected
		{
			RGB _nearestSearchResult_ActColor; 
			
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
				Drawing dr, R searchResults, vec2 mousePos,
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
								updateNearestSearchResult(distanceB(mousePos, b), sr); 
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
									updateNearestSearchResult(distance(mousePos, p[1]), sr); 
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
		} 
	}
	version(/+$DIDE_REGION+/all) {
		static struct Layer
		{
			ModuleManager modules; 
			DMDMessage.Type type; 
			//Todo: these fields should be readonly.  Not const, but readonly.  With a field mixin or somerhing....
			
			bool visible = true; //Each layer can be hidden
			bounds2 btnWorldBounds; //Screen bounds of the button, for particle effect.
			
			auto searchResults()
			=> modules.modules.map!((m)=>(
				choose(
					type==DMDMessage.Type.find, 
					m.findSearchResults,
					m.messagesByType[type].map!((msg)=>(msg.searchResults)).joiner
				)
			)).joiner; 
			
			auto searchResultCount()
			=> mixin(求sum(q{m},q{modules.modules},q{((type==DMDMessage.Type.find)?(m.findSearchResults.length) :(m.messagesByType[type].length))})); 
			
			void clear()
			{
				enforce(type==DMDMessage.Type.find, "Fatal: clear() only supportted for findResults, not messageMarkers."); 
				mixin(求each(q{m},q{modules.modules},q{m.findSearchResults.clear})); 
			} 
			
			void zoomAt(View2D view)
			{
				auto sr = searchResults; if(sr.empty) return; 
				const maxScale = max(view.scale, 1); 
				view.zoom(sr.map!(r => r.bounds).fold!"a|b", 12); 
				view.scale = min(view.scale, maxScale); 
			} 
			
			void UI_Btn(View2D view/+for zooming+//+Todo: get it from an interface+/)
			{
				with(im) {
					if(
						Btn(
							{
								auto fade(RGB c) => c.mix(clSilver, ((visible)?(0):(.75f))); 
								
								const syntax = DMDMessage.typeSyntax[type]; 
								style.bkColor = bkColor = fade(syntax.syntaxBkColor); 
								const highContrastFontColor = syntax.syntaxFontColor; 
								style.fontColor = fade(highContrastFontColor); 
								
								Row(
									{
										flags.hAlign = HAlign.center; 
										//innerWidth = ceil(fh*2); 
										innerHeight = ceil(fh*1.66f); 
										flags.clickable = false; 
										Text(DMDMessage.typeShortCaption[type]); NL; 
										fh = ceil(fh*.66f); 
										theme = "tool"; 
										
										if(const cnt = searchResultCount)
										{
											if(Btn(cnt.text))
											{
												visible = true; 
												zoomAt(view); 
											}
										}
									}
								); 
								
								btnWorldBounds = view.invTrans(actContainerBounds); 
							},
							((type).genericArg!q{id})
						)
					)
					visible.toggle; 
				}
			} 
		} 
		
		protected Layer[DMDMessage.Type.max+1] layers_internal; 
		
		protected void initLayers()
		{
			foreach(i, ref lay; layers_internal) {
				lay.type = i.to!(DMDMessage.Type); 
				lay.modules = modules; 
			}
		} 
		
		inout layers()
		=> layers_internal[];  ref findResultLayer()
		=> layers[DMDMessage.Type.find]; 
		
		@STORED @property
		{
			size_t layerVisibilityMask() const
			=> layers.map!((lay)=>(((lay.visible)?(1<<lay.type):(0)))).sum; 
			
			void layerVisibilityMask(size_t v)
			{ layers.each!((ref lay){ lay.visible = v.getBit(lay.type); }); } 
		} 
		
		void UI_LayerBtns(View2D view/+for zooming+/)
		{ with(im) { foreach(ref layer; layers[1..$]) { layer.UI_Btn(view); }}} 
		
		void drawLayers(Drawing dr, View2D mainView)
		{
			layers[DMDMessage.Type.unknown].visible = false; 
			resetNearestSearchResult; 
			const mp = mainView.mousePos.vec2; 
			
			foreach_reverse(ref layer; layers)
			if(layer.visible)
			drawSearchResults(dr, layer.searchResults, mp, DMDMessage.typeSyntax[layer.type].syntaxBkColor); 
			
			if(nearestSearchResult_dist > mainView.invScale*24)
			nearestSearchResult = SearchResult.init; 
			
			if(nearestSearchResult.bounds)
			{ drawSearchResults(dr, only(nearestSearchResult), mp, nearestSearchResult_color.mix(clWhite, .5f)); }
		} 
		
		
	}
	version(/+$DIDE_REGION+/all) {
		static struct MessageConnectionArrow
		{
			vec2 p1, p2; 
			DMDMessage.Type type; 
			bool isException; //a side-information for type
		} 
		bool[MessageConnectionArrow] messageConnectionArrows; 
		
		uint _messageConnectionArrows_hash; 
		
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
					auto layer = &layers[type]; 
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
	
	
} 