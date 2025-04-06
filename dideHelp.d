module didehelp;  

import didebase; 
import didedecl : Declaration; 
import didemodule : Breadcrumb, toBreadcrumbs; 
import didetextselectionmanager : TextSelectionManager; 
import didebuildmessagemanager : BuildMessageManager; 

struct HelpManager
{
	TextSelectionManager textSelections; 
	
	string actHelpQuery, actSearchKeyword; 
	bounds2 actSearchKeywordBounds; 
	TextSelection actSearchKeywordSelection; 
	
	void UI_mouseLocationHint(INavigator navig, View2D view)
	{
		with(im) {
			//Todo: This UI thing updated internal state. Not good...
			actSearchKeyword = ""; 
			actSearchKeywordBounds = bounds2.init; 
			actHelpQuery = ""; 
			
			bool isCaret, isAtLineEnd, wordIsSelectedText; 
			CellLocation[] st; 
			
			auto primary = textSelections.primary; 
			
			if(primary.caret)
			{
				isCaret = true; 
				
				if(textSelections.length==1)
				{
					if(primary.isZeroLength)
					{
						isAtLineEnd = primary.caret.isAtLineEnd; 
						st = cursorToCellLocations(primary.caret); 
					}
					else if(primary.isSingleLine)
					{
						st = cursorToCellLocations(primary.start); 
						wordIsSelectedText = true; 
					}
				}
			}
			else
			{ if(view.isMouseInside) st = navig.locate_snapToRow(view.mousePos.vec2); }
			
			if(st.length)
			{
				auto 	loc 	= cellLocationToCodeLocation(st),
					breadcrumbs 	= st.toBreadcrumbs; 
				if(wordIsSelectedText)
				{
					actSearchKeyword = "$DIDE_PRIMARY_SELECTION$"; 
					actSearchKeywordBounds = textSelections.primary.worldBounds; 
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
							{ navig.jumpTo(b.node); }
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
	void UI_mouseOverHint(BuildMessageManager buildMessages, float workspaceOuterWidth)
	{
		with(im) {
			if(lastNearestSearchResultReference.chkSet((cast(size_t)((cast(void*)(buildMessages.nearestSearchResult.reference)))).text))
			{
				mouseOverHintCntr = null; 
				
				if(buildMessages.nearestSearchResult.reference)
				{
					if(!mouseOverHintCntr)
					if(auto mm = (cast(Module.Message)(buildMessages.nearestSearchResult.reference)))
					{
						auto msgNode = buildMessages.createNode(mm.message); 
						with(msgNode) {
							outerWidth 	= min(outerWidth, max(workspaceOuterWidth-50, 50)),
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
	
	/+
		Todo: Fix these shitty help providers:
		
		win32	: https://learn.microsoft.com/api/search?locale=en-us&scoringprofile=semantic-captions&%24top=3&search=RegisterClass
		vulkan	: https://registry.khronos.org/vulkan/specs/latest/man/html/   (no search...)
		D	: A forrasban benne van a dokumentacio. Fel kell dolgoznom (nem most).
		GLSL	: Manualisan hasznalom a web browsert...
		bing	: fuck that. -> deepseek
		google	: fuck that too. -> deepseek
	+/
	
	protected void prepareHelpQuery(ref string s)
	{
		//Todo: this is kinda lame: It avoids getting the actual textSelection until the last moment.
		if(s.canFind("$DIDE_PRIMARY_SELECTION$"))
		{ s = s.replace("$DIDE_PRIMARY_SELECTION$", textSelections.primary.sourceText.replace("\n", " ")); }
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
	
	
	
	bool startChrome(alias linkScraper)()
	{
		auto links = linkScraper(actHelpQuery); 
		if(links.empty) return false; 
		startChrome(links[0], actSearchKeyword); 
		return true; 
	} 
	
	bool bing()
	=> startChrome!scrapeLinks_bing; 
	
	bool dpldocs()
	=> startChrome!scrapeLinks_dpldocs; 
	
} 