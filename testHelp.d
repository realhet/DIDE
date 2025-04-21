//@exe
//@debug
///@release

import het.ui, het.ai; 

struct HelpManager
{
	string actHelpQuery, actSearchKeyword; 
	
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
		/+
			if(s.canFind("$DIDE_PRIMARY_SELECTION$"))
			{ s = s.replace("$DIDE_PRIMARY_SELECTION$", textSelections.primary.sourceText.replace("\n", " ")); }
		+/
	} 
	
	/+
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
	+/
	
	string[string] cache; 
	Path cachePath() => Path(appPath, "WebCache"); 
	
	string cachedQuery(string cacheId, string delegate() executeQuery)
	{
		const useCache = cacheId!=""; 
		File cacheFile; 
		
		if(useCache) {
			cacheFile = File(cachePath, cacheId.encodeFileName); 
			try return cacheFile.readStr(true); catch(Exception e) {}
		}
		string res = executeQuery(); 
		if(useCache) cacheFile.write(res); 
		return res; 
	} 
	
	string httpGet(string url, string cacheId="")
	=> cachedQuery(cacheId, ((){ import het.http; return het.http.curlGet(url); })); 
	
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
			`https://learn.microsoft.com/en-us/windows/win32/`
		]; 
		
		string[] preferred; 
		foreach(link; links) foreach(a; helpProviders) if(link.startsWith(a)) preferred.addIfCan(link); 
		
		return preferred; 
	} 
	
	
	string[] scrapeLinks_dpldocs(string query)
	{
		prepareHelpQuery(query); if(query=="") return []; 
		
		auto queryUrl = `https://search.dpldocs.info/?q=`~urlEncode(query); 
		auto bloatml = httpGet(queryUrl, query~".dpldocs"); 
		
		string[] links; 
		{
			auto s = bloatml; 
			while(s.isWild(`*<dt class="search-result" *<a href="//*"*</dt><dd>*</dd>*`))
			{
				const 	url 	= wild[2],
					undocumented 	= wild[4].canFind(`<span class="undocumented-note">`); 
				enum paths = [
					"phobos.dpldocs.info/", 
					"druntime.dpldocs.info/"
				]; 
				if(!undocumented && paths.any!((p)=>(url.startsWith(p))))
				links ~= "https://"~url; 
				
				s = wild[5]; 
			}
		}
		
		static if((常!(bool)(0)))	{ return links; }
		else	{ if(links.length<=1) return links.take(1).array; else return [queryUrl]; }
	} 
	
	string[] scrapeLinks_mslearn(string query)
	{
		prepareHelpQuery(query); if(query=="") return []; 
		
		auto queryUrl = `https://learn.microsoft.com/api/search?locale=en-us&scoringprofile=semantic-captions&%24top=1&search=`~urlEncode(query); 
		auto 	bloatml = httpGet(queryUrl, query~".mslearn"); 
		
		enum prefix = "https://learn.microsoft.com/en-us/windows/win32/"; 
		if(bloatml.isWild(`*"url":"`~prefix~`*"*`))
		{ return [prefix~wild[1]]; }
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
					"https://api.deepseek.com/v1/chat/completions", "deepseek-chat", 
					"The user will give a search string, you must reply with a documentation link. 
The search will fit into one of these categories: Win32, Vulkan, OpenGL, GLSL, DLang, Arduino Language.
Reply only the link, no talking! I need a working link!"
				); 
				model.apiKey = File(appPath, "a.a").readStr; 
			}
			return model; 
		} 
		
		string doit()
		{
			auto res = model.ask(query); 
			enforce(res.startsWith("https://"), "Unknown deepsearch response: "~res); 
			return res; 
		} 
		
		auto res = cachedQuery(query~".deepsearch", &doit); 
		
		return [res]; 
	} 
	
	string scrapeLinks_combined(string w)
	{
		string[] list = scrapeLinks_dpldocs(w); 
		if(list.length) return list[0]; 
		else {
			list = scrapeLinks_bing(w) ~ scrapeLinks_mslearn(w); 
			auto important = list.filter!((a)=>(a.canFind("khronos"))).array; 
			if(important.length)	return important[0]; 
			else if(list.length)	return list[0]; 
			else {
				list = scrapeLinks_deepseek(w); 
				if(list.length) return list[0]; 
				else { return ""; }
			}
		}
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
	
	bool deepsearch()
	=> startChrome!scrapeLinks_deepseek; 
	
	bool combinedSearch()
	{
		auto link = scrapeLinks_combined(actHelpQuery); 
		if(link=="") return false; 
		startChrome(link, actSearchKeyword); 
		return true; 
	} 
	
	
} 

class FrmHelp : GLWindow
{
	mixin autoCreate; 
	
	HelpManager hlp; 
	
	override void onCreate()
	{ clientSize = ivec2(640, 480); } 
	
	override void onUpdate()
	{
		with(im)
		Panel(
			PanelPosition.client, 
			{
				const testWords = [
					"max", "maxElement", "registerClass", "HBITMAP", "vec3", "glClearColor", 
					"VkPhysicalDev", "GL_FRONT_AND_BACK", "AUDCLNT_E_DEVICE_IN_USE",
					"texParameterf", "WM_USER", "gl_FragCoord", "vkGetPhysicalDeviceProperties"
				]; 
				Row(
					{
						foreach(w; testWords)
						if(Btn(w, ((w).genericArg!q{id}))) {
							/+
								print(w); 
								hlp.scrapeLinks_dpldocs(w).each!((a){ print("dpldocs:", a); }); 
								hlp.scrapeLinks_bing(w).each!((a){ print("bing:", a); }); 
								hlp.scrapeLinks_mslearn(w).each!((a){ print("mslearn:", a); }); 
								hlp.scrapeLinks_deepseek(w).each!((a){ print("deepsearch:", a); }); 
								print; 
							+/
							
							hlp.startChrome(hlp.scrapeLinks_combined(w), w); 
						}
					}
				); 
			}
		); 
		
		invalidate; 
	} 
	
} 