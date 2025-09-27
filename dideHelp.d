module didehelp;  

import het.ai; 
import didebase; 
import didedecl : Declaration; 
import didemodule : Breadcrumb, toBreadcrumbs; 
import didetextselectionmanager : TextSelectionManager; 
import didebuildmessagemanager : BuildMessageManager; 

enum HelpProvider {bing, msdn, dpldocs, dpldocs_searchPage, deepseek, combined, combined_noContext} 

struct HelpManager
{
	TextSelectionManager textSelections; 
	
	string actHelpQuery, actSearchKeyword; 
	bounds2 actSearchKeywordBounds; 
	TextSelection actSearchKeywordSelection; 
	
	bool enableDebug; 
	
	static string extractHelpQuery(Breadcrumb[] breadcrumbs, string word)
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
									(("Breadcrumb:"~i.text).名!q{id})
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
						auto msgNode = buildMessages.createNode(mm.message, hideLocation: false); 
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
	
	__gshared MSQueue!string infoQueue, errorQueue; 
	void initialize()
	{
		if(!infoQueue) infoQueue = new typeof(infoQueue); 
		if(!errorQueue) errorQueue = new typeof(errorQueue); 
	} 
	
	void update()
	{
		foreach(s; infoQueue.fetchAll) im.flashInfo("Help: ", s); 
		foreach(s; errorQueue.fetchAll) im.flashError("Help Error: "~s); 
	} 
	
	void launch(HelpProvider provider)
	{
		static void doLaunch(HelpProvider provider, string actHelpQuery, string actSearchKeyword, bool enableDebug)
		{
			/+
				Todo: Fix these shitty help providers:
				
				win32	: https://learn.microsoft.com/api/search?locale=en-us&scoringprofile=semantic-captions&%24top=3&search=RegisterClass
				vulkan	: https://registry.khronos.org/vulkan/specs/latest/man/html/   (no search...)
				D	: A forrasban benne van a dokumentacio. Fel kell dolgoznom (nem most).
				GLSL	: Manualisan hasznalom a web browsert...
				bing	: fuck that. -> deepseek
				google	: fuck that too. -> deepseek
			+/
			
			static void removeSearchContext(ref string s)
			{
				const i = s.lastIndexOf(" +"); 
				if(i>=0)
				{
					const left = s[0 .. i], right = s[i+2 .. $]; 
					if(
						left.isDLangIdentifier/+the context identifier+/ &&
						right!="" && !right.front.isDLangWhitespace && !right.front.isDLangNewLine
					)
					{ s = right; }
				}
			} 
			
			void prepareHelpQuery(ref string s, Flag!"keywordOnly" keywordOnly = No.keywordOnly)
			{ if(keywordOnly) removeSearchContext(s); } 
			
			static Path cachePath() => Path(appPath, "WebCache"); 
			
			static string cachedQuery(string cacheId, string delegate() executeQuery)
			{
				const useCache = cacheId!=""; 
				File cacheFile; 
				
				if(useCache) {
					cacheFile = File(cachePath, cacheId.encodeFileName); 
					try return cacheFile.readStr(true); catch(Exception e) {}
				}
				string res = executeQuery(); 
				if(useCache && res.strip!="") cacheFile.write(res); 
				return res; 
			} 
			
			static string httpGet(string url, string cacheId="")
			=> cachedQuery(
				cacheId, ((){
					HelpManager.infoQueue.put("accessing: "~url.withoutStarting("https://").splitter('/').take(1).join); 
					string res; 
					try { import het.http; res = het.http.curlGet(url); }
					catch(Exception e) { HelpManager.errorQueue.put(e.simpleMsg); }
					return res; 
				})
			); 
			
			string[] scrapeLinks_bing(string query)
			{
				prepareHelpQuery(query); if(query=="") return []; 
				
				auto 	bloatml 	= httpGet(`https://bing.com/search?q=`~urlEncode(query), query~".bing"),
					links 	= bloatml	.splitter(`href="`).drop(1)
							.map!(s=>s.splitter(`"`).frontOr("")).filter!"a!=``".array; 
				links = links.filter!((a)=>(a.startsWith("https://") && !a.canFind(".bing.com"))).array; 
				
				immutable helpProviders = [
					`https://registry.khronos.org/vulkan/specs/`,
					`https://registry.khronos.org/OpenGL-Refpages/`,
					`https://www.khronos.org/opengl/wiki/`,
					`https://learn.microsoft.com/en-us/windows/win32/`,
					`https://en.ids-imaging.com/manuals/ids-software-suite/ueye-manual/`
				]; 
				
				string[] preferred; 
				foreach(link; links) {
					foreach(a; helpProviders)
					if(link.startsWith(a)) preferred.addIfCan(link); 
				}
				
				if(enableDebug) {
					print("bing links:"); 
					links.each!((a){ print("  \33"~((preferred.canFind(a))?('\12'):('\7'))~a~"\33\7"); }); 
					print; 
				}
				
				return preferred; 
			} 
			
			
			string[] scrapeLinks_dpldocs(string query, Flag!"searchPage" searchPage = Yes.searchPage)
			{
				prepareHelpQuery(query, Yes.keywordOnly); if(query=="") return []; 
				
				auto queryUrl = `https://search.dpldocs.info/?q=`~urlEncode(query); 
				auto bloatml = httpGet(queryUrl, query~".dpldocs"); 
				
				string[] links; 
				{
					auto s = bloatml; 
					while(s.isWild(`*<dt class="search-result" *<a href="//*"*</dt><dd>*</dd>*`))
					{
						const 	url 	= wild[2],
							undocumented 	= wild[4].map!toLower.canFind(`undocumented`); 
						enum paths = [
							"phobos.dpldocs.info/", 
							"druntime.dpldocs.info/"
						]; 
						const valid = !undocumented && paths.any!((p)=>(url.startsWith(p))); 
						
						if(valid) links ~= "https://"~url; 
						
						if(enableDebug) {
							print("dpldocs links:"); 
							links.each!((a){ print("  \33"~((valid)?('\12'):('\7'))~"https://"~a~"\33\7"); }); 
							print; 
						}
						
						s = wild[5]; 
					}
				}
				
				if(searchPage && links.length>1) links = [queryUrl]; 
				
				return links; 
			} 
			
			string[] scrapeLinks_mslearn(string query)
			{
				prepareHelpQuery(query, Yes.keywordOnly); if(query=="") return []; 
				
				auto queryUrl = 
					`https://learn.microsoft.com/api/search?locale=en-us&scoringprofile=semantic-captions&%24top=1&search=`
					~urlEncode(query); 
				auto 	bloatml = httpGet(queryUrl, query~".mslearn"); 
				
				enum prefix = "https://learn.microsoft.com/en-us/windows/win32/"; 
				if(bloatml.isWild(`*"url":"`~prefix~`*"*`))
				{
					const link = prefix~wild[1]; 
					if(enableDebug) {
						print("mslearn links:"); /+Todo: this is not a proper link collection operation.+/
						link.only.each!((a){ print("  \33"~((true)?('\12'):('\7'))~a~"\33\7"); }); 
						print; 
					}
					return [link]; 
				}
				else
				return []; 
			} 
			
			string[] scrapeLinks_deepseek(string query)
			{
				prepareHelpQuery(query); if(query=="") return []; 
				
				AiModel model()
				{
					__gshared AiModel model; 
					if(!model)
					{
						model = new AiModel
						(
							//"https://api.deepseek.com/v1/chat/completions"
							"https://api.deepseek.com/chat/completions"
							, "deepseek-chat", 
							"The user will give a search string, you must reply with a documentation link. 
The search will fit into one of these categories: Win32, Vulkan, OpenGL, GLSL, DLang, Arduino Language.
Reply only the link, no talking! I need a working link! If you can't find a link, just reply `null`."
						); 
						model.temperature = 0.25; 
						model.apiKey = File(appPath, "a.a").readStr; 
					}
					return model; 
				} 
				
				string doit()
				{
					HelpManager.infoQueue.put("accessing: deepseek.com"); 
					string actRes; 
					void onToken(AiChat.Event e, string s)
					{
						if(e==AiChat.Event.text)
						{ actRes ~= s; HelpManager.infoQueue.put("accessing: deepseek.com:\n"~actRes); }
					} 
					
					auto res = model.ask(query, debugPrint : enableDebug, userEvent : enableDebug ? null : &onToken); 
					
					enforce(res==`null` || res.startsWith("https://"), "Unknown deepsearch response: "~res); 
					return res; 
				} 
				
				auto res = cachedQuery(query~".deepsearch", &doit); 
				return res==`null` ? [] : [res]; 
			} 
			
			string[] scrapeLinks_combined(string w, Flag!"context" context = Yes.context)
			{
				if(!context) removeSearchContext(w); 
				
				//Opt: Make these web accesses in parallel and do it in the background.
				string[] list = scrapeLinks_dpldocs(w, No.searchPage); 
				if(list.length) return list; 
				else {
					list = scrapeLinks_bing(w) ~ scrapeLinks_mslearn(w); 
					auto important = list.filter!((a)=>(a.canFind("khronos"))).array; 
					if(important.length)	return important; 
					else if(list.length)	return list; 
					else {
						list = scrapeLinks_deepseek(w); 
						if(list.length) return list; 
						else { return []; }
					}
				}
			} 
			
			mixin((
				(表([
					[q{/+Note: Browser+/},q{/+Note: Name+/},q{/+Note: cmd+/},q{/+Note: wndClass+/},q{/+Note: wndTitleMask+/},q{/+Note: wndLoadingTitle+/}],
					[q{chrome},q{"Chrome"},q{"chrome"},q{"Chrome_WidgetWin_1"},q{"* - Google Chrome"},q{"Untitled - Google Chrome"}],
					[q{edge},q{"Edge"},q{"msedge"},q{"Chrome_WidgetWin_1"},q{"* - Microsoft\u200B Edge"},q{"Untitled * - Microsoft\u200B Edge"}],
					[],
					[q{/+
						wndTitleMask	: Used to locate chrome windows, to detect if it is loaded.
						wndLoadingTitle 	: Used to detect the page loading state.
					+/}],
				]))
			) .GEN!q{GEN_enumTable}); 
			
			const browser = Browser.edge; 
			
			void startBrowserUrl(string url, string keyword="")
			{
				if(url==``) return; 
				try {
					HelpManager.infoQueue.put("launching"~browserName[browser]); 
					
					prepareHelpQuery(keyword); 
					
					mainWindow.setForegroundWindow; //just to make sure
					executeShell(joinCommandLine(["start", browserCmd[browser], url])); 
					auto wi = waitWindow(browserWndClass[browser], browserWndTitleMask[browser], 2*second); 
					
					if(keyword!="")
					{
						const 	clipboardHadText = clipboard.hasText,
							savedClipboardText = clipboardHadText ? clipboard.text : ""; 
						scope(exit) if(clipboardHadText) clipboard.text = savedClipboardText; 
						
						clipboard.text = keyword; 	
						
						int extraWait = 3; 
						foreach(i; 0..100) {
							const title = getWindowInfo(wi.handle).title; 
							const isLoading = title.isWild(browserWndLoadingTitle[browser]); 
							if(!isLoading) if(--extraWait<=0) break; 
							sleep(100); 
						}
						
						inputs.pressCombo("Ctrl+F"); 	sleep(50); 
						inputs.pressCombo("Ctrl+V"); 	sleep(50); 
						
						const needEnter = [`https://registry.khronos.org/vulkan/specs/`].any!((a)=>(url.startsWith(a))); 
						if(needEnter /+Note: This skips to the second match.+/)
						{ inputs.pressCombo("Enter"); 	sleep(50); }
					}
				}
				catch(Exception e) { LOG(e.simpleMsg); }
			} 
			
			bool startBrowser(alias linkScraper, A...)(A args)
			{
				auto links = linkScraper(actHelpQuery, args); if(links.empty) return false; 
				startBrowserUrl(links[0], actSearchKeyword); return true; 
			} 
			
			
			
			
			try
			{
				/+
					Todo: stringMixin niceexpressions should be processed inside case labels. 
					/+Code: case mixin(舉!((HelpProvider),q{combined})): +/
				+/
				final switch(provider)
				{
					case HelpProvider.bing: 	startBrowser!scrapeLinks_bing; 	break; 
					case HelpProvider.msdn: 	startBrowser!scrapeLinks_mslearn; 	break; 
					case HelpProvider.dpldocs: 	startBrowser!scrapeLinks_dpldocs(No.searchPage); 	break; 
					case HelpProvider.dpldocs_searchPage: 	startBrowser!scrapeLinks_dpldocs(Yes.searchPage); 	break; 
					case HelpProvider.deepseek: 	startBrowser!scrapeLinks_deepseek; 	break; 
					case HelpProvider.combined: 	startBrowser!scrapeLinks_combined(Yes.context); 	break; 
					case HelpProvider.combined_noContext: 	startBrowser!scrapeLinks_combined(No.context); 	break; 
				}
			}
			catch(Exception e)
			{ HelpManager.errorQueue.put(e.simpleMsg); }
		} 
		string primarySelectionText; 
		bool primarySelectionText_accessed; 
		string prepare(string s)
		{
			if(s.canFind("$DIDE_PRIMARY_SELECTION$"))
			{
				if(primarySelectionText_accessed.chkSet)
				primarySelectionText = textSelections.primary.sourceText.replace("\n", " "); 
				s = s.replace("$DIDE_PRIMARY_SELECTION$", primarySelectionText); 
			}
			return s; 
		} 
		
		spawn(&doLaunch, provider, prepare(actHelpQuery), prepare(actSearchKeyword), enableDebug); 
	} 
	
	
} 