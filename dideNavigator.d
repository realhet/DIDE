module didenavigator; 

import didebase; 
import didenode : CodeComment; 
import didemodulemanager : ModuleManager; 
import didebuildmessagemanager : BuildMessageManager; 

class Navigator : INavigator
{
	mixin SmartChild!q{
		Container	workspaceContainer,
		ModuleManager	modules,
		BuildMessageManager 	buildMessages,
		View2D	view
	}; 
	
	enum CodeLocationPrefix 	= "CodeLocation:",
	MatchPrefix	= "Match:"; 
	
	Nullable!vec2 jumpRequest; 
	Nullable!bounds2 scrollInBoundsRequest; 
	
	protected bool MMBReleasedWithoutScrolling()
	{
		return inputs.MMB.released && mainWindow.mouse.hoverMax.screen.manhattanLength<=2; 
		//Todo: Ctrl+left click should be better. I think it will not conflict with the textSelection, only with module selection.
	} 
	
	void jumpTo(vec2 pos)
	{
		with(view) if(scale<0.3f) scale = 1; 
		jumpRequest = nullable(vec2(pos)); 
	} 
	
	void jumpTo(bounds2 bnd)
	{
		//if(bnd) jumpTo(bnd.center); 
		if(bnd)
		{
			if(view.scale<1) view.scale = 1; 
			view.smartScrollTo(bnd); 
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
	
	version(/+$DIDE_REGION Stored Locations+/all)
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
				origin	= view.origin.vec2,
				zoomFactor 	= view.scale; 
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
				view.origin	= origin.dvec2,
				view.scale 	= zoomFactor; 
			}
		} 
		
	}
	
	CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0))
	{
		ofs += workspaceContainer.innerPos; 
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
	
	static CellLocation[] findLastCodeRow(CellLocation[] st)
	{
		foreach_reverse(i; 0..st.length) {
			//Todo: functinal
			auto row = cast(CodeRow)st[i].cell; 
			if(row) return st[i..$]; 
		}
		return []; 
	} 
	
	TextCursor cellLocationToTextCursor(CellLocation[] st, Container workspaceContainer)
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
		
		return validate(res, workspaceContainer); 
	} 
	
	TextCursor createCursorAt(vec2 p)
	=> cellLocationToTextCursor(locate_snapToRow(p), workspaceContainer); 
	version(/+$DIDE_REGION Scrolling+/all)
	{
		void scrollV(float dy)
		{ view.scrollV(dy); } 
		void scrollH(float dx)
		{ view.scrollH(dx); } 
		void zoom(float log)
		{ view.zoom(log); } //Todo: Only zoom when window is foreground
		
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
	
	void updateJumps()
	{
		if(MMBReleasedWithoutScrolling)
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
							{
								im.flashWarning(i"File not found $(loc.file.fullName.quoted).".text); 
								return; 
							}
							modules.loadModule(loc.file); 
							//Todo: move all buildMessages from mainFile to the newly opened file.
						}
						jumpTo(loc); return; 
					}
				}
			}
			
			//check the nearest searchresult
			if(view.isMouseInside)
			jumpTo(buildMessages.nearestSearchResult.reference); 
		}
	} 
	
	void updateScrollRequests()
	{
		if(!jumpRequest.isNull)
		{
			view.origin = jumpRequest.get - (view.subScreenOrigin-view.origin); 
			jumpRequest.nullify; 
		}
		if(!scrollInBoundsRequest.isNull)
		{
			view.scrollZoom(scrollInBoundsRequest.get); 
			scrollInBoundsRequest.nullify; 
		}
	} 
	
	
} 