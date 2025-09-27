module didesearch; 

import didebase; 
import didemodulemanager : ModuleManager; 
import didetextselectionmanager : TextSelectionManager; 
import didebuildmessagemanager : BuildMessageManager; 

static struct SearchBox
{
	bool searchBoxActivate_request; 
	@STORED
	{
		bool 	searchBoxVisible, 
			advancedSearchOptionsVisible, 
			lookInAllModules; 
		string searchText; 
		SearchOptions searchOptions; 
	} 
	
	void activate(string s, bool global=false)
	{
		searchBoxActivate_request = true; searchText = s; 
		lookInAllModules = global; 
	} 
	
	void deactivate(BuildMessageManager buildMessages)
	{ if(searchBoxVisible.chkClear) { searchText = ""; buildMessages.findResultLayer.clear; }} 
	
	import core.thread.fiber; 
	static class SearchFiber : Fiber
	{
		mixin SmartChild!
		(
			q{
				Module[] modules, 
				string searchText,
				SearchOptions searchOptions,
				SearchBox.SearchStats* stats
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
	void UI_searchBox(ModuleManager modules, TextSelectionManager textSelections, BuildMessageManager buildMessages, INavigator navigator, View2D view, bool justActivated)
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
								Edit(searchText, ((justActivated).名!q{focusEnter}), { flex = 1; editContainer = actContainer; })
								|| justActivated || searchHashChanged
							)
							{
								//refresh search results
								buildMessages.findResultLayer.clear; 
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
									
									textSelections.clear; 
									if(auto mod = modules.expectOneSelectedModule)
									if(auto line = searchText[1..$].to!int.ifThrown(0))
									{
										navigator.jumpTo(CodeLocation(mod.file.fullName, line)); 
										//Todo: show a highlight on that row...
									}
									
								}
								else
								{
									auto mods = lookInAllModules ? modules.modules : modules.selectedModules; 
									if(mods.empty && lookInAllModules.chkSet) { mods = modules.modules; }
									searchFiber = new SearchFiber(mods, searchText, searchOptions, &searchStats); 
									/+Note: the old searchFiber stops because it loses all references and will not be called again.+/
								}
							}
							//display the number of matches. Also save the location of that number on the screen.
							const matchCnt = buildMessages.findResultLayer.searchResultCount; 
							Row({ if(matchCnt) Text(" ", clGray, matchCnt.text, " "); }); 
							
							BtnRow(
								{
									if(
										Btn(
											"🔍", isFocused(editContainer) ? kcFindZoom : KeyCombo(""),
											enable(matchCnt>0), hint("Zoom screen on search results.")
										)
									)
									{ buildMessages.findResultLayer.zoomAt(view); }
									if(
										Btn(
											"Sel", isFocused(editContainer) ? kcFindToSelection : KeyCombo(""),
											enable(matchCnt>0), hint("Select search results.")
										)
									)
									{ textSelections.select(buildMessages.findResultLayer.searchResults); }
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
							{ deactivate(buildMessages); }
						}
					); 
					
					if(advancedSearchOptionsVisible)
					{
						Column(
							{
								sw; 
								Grp!Row("Boundary conditions", { sw; Text("start: "); BtnRow(searchOptions.boundaryTypeStart, (("st").名!q{id})); Text(" end: "); BtnRow(searchOptions.boundaryTypeEnd, (("en").名!q{id})); }); 
								Grp!Row(
									"Syntaxes: ", {
										sw; foreach(const a; searchStats.syntaxes.byKeyValue.array.sort!"a.value>b.value")
										{
											Btn(
												i"$(a.value)× ".text, {
													style.fontColor = syntaxFontColor(a.key); 
													style.bkColor = syntaxBkColor(a.key); 
													Text(a.key.text); 
												}, ((a.key).名!q{id})
											); 
										}
									}
								); 
								Grp!Row(
									"Words: ", {
										sw; foreach(const a; searchStats.wholeWords.byKeyValue.array.sort!"a.value>b.value".take(30))
										{ Btn(i"$(a.value)× $(a.key)".text, ((a.key).名!q{id})); }
									}
								); 
							}
						); 
					}
				}
			); 
		}
		
	} 
	
	bool UI(ModuleManager modules, TextSelectionManager textSelections, BuildMessageManager buildMessages, INavigator navigator, View2D view)
	{
		with(im)
		{
			{
				bool justActivated; 
				if(searchBoxActivate_request.chkClear)
				{ searchBoxVisible = justActivated = true; }
				
				if(searchBoxVisible)
				{ UI_searchBox(modules, textSelections, buildMessages, navigator, view, justActivated); }
				
				return searchBoxVisible; 
			}
		}
	} 
} 