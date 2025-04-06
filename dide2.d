//@exe
//@compile --d-version=stringId

//@debug
//@release

import core.thread, std.concurrency; 

import didebase, buildsys, syntaxExamples; 
import didenode : CodeComment, CodeContainer, CodeString, CodeBlock; 
import didemodule : addInspectorParticle; 
import didedecl : Declaration; 
import dideexpr : NiceExpression, ToolPalette; 
import dideworkspace : Workspace; 


version(/+$DIDE_REGION+/all)
{
	//Todo: Ability to change comment type // /+ /*	and also todo: note: bug:
	//Todo: Ability to change the whitespace after a	preposition: space, tab, newline
	//Todo: toggle space/tab/newline after prepositions.
	//Todo: Easily Reduce Build Times by Profiling	the D Compiler   profiling the LDC2 compiler.  ldc2 -ftime-trace,  timetrace2txt, -> web perfetto.ui
	//Todo: automatic spaces around operators and ligatures.
	
	//Todo: dide builder to ignore unknown modules, like: derelict.util.loader    Because sometimes (version()) they will not be compiled at all.
	
	//Todo: wholeWords search (eleje/vege kulon)
	//Todo: filter search results per file and per syntax (comment, string, code, etc)
	
	//Todo: het.math.cmp integration with std
	
	//Todo: accept repeared keystrokes even when the FPS is low. (Ctrl+X Shift+Del Del Backspace are really slow now.)
	
	/+
		Todo: cs Kod szerkesztonek feltetlen csinald meg, hogy kijelolt szovegreszt kulon ablakban tudj editalni tobb ilyen 
		lehessen esetleg ha egy fuggveny felso soran vagy akkor automatikusan rakja ki a fuggveny torzset
	+/
	//Todo: cs lehessen splittelni: pl egyik tab full kod full scren, a masik tabon meg splittelve ket fuggveny
	
	//Todo: save/restore buildsystem cache on start/exit
	
	//Todo: Find: display a list of distinct words around the searched text. AKA Autocomplete for search.
	//Todo: kinetic scroll
	
	//Todo: module hierarchy detector should run ARFTER save when pressing F9 (Not before when the contents is different in the file and in the editor)
	
	//Todo: frame time independent lerp for view.zoomAroundMouse() https://youtu.be/YJB1QnEmlTs?t=482
	
	//Todo: Search: x=12  match -> x =12,	x =  12 too. Automatic whitespaces.
	//Todo: Structure error visibility: In	Highighted view, mark the onclosed brackets too. Not just the wrong brackets. c:\dl\broken_structure.d
	
	//Todo: markdown a commentekben.
	
	//Todo: handle newline before and after else.
	//Todo: switch(c){ static foreach(a; b) case a[0]: return a[1]; default: return 0; }    <- It case label must suck statement into it. Not just sop at the :
	//Todo: tab removal from the left side of multiline comments
	
	//Todo: inline struct.  Use it to model persistent and calculated fields of a struct/class  -> DConf Online '22 - Model all the Things!
	
	/+
		Todo: Properly handle Noman's land between preposition and the statement next to. It could be space, tab, newline with optional comments.
		Verify it still works in between adjacent preposition.
	+/
	
	//Todo: Implement q"a ... a" identifier-qstring handling in new DIDE DLang Scanner.
	/+
		Todo: CharSetBits is an example to a divergent export import operation. Every save it prepends more tabs in front of it. Delimited string bug.
			const str = q"/ NEWLINE TAB blabla NEWLINE TAB/"; 
	+/
	
	//Todo: Szerenyebb legyen az atomvillanas effekt! (module highlight, bele a settingsbe!)
	
	//Todo: Vízszintes elválasztó vonal (0x000C szabad): FormFeed. (Függôleges elválasztó vonal már van: Vertical Tab, azaz a hasábra tördelés)
	/+
		Todo: Specialis karakter: Innentôl jobbra igazítás. Kellene ilyen tipusu Elastic Tab is a számokhoz. 
		Elastic tabs, ami a balra levo szamot jobbra huzza. Ezt ki kell találni, nem kerek.
	+/
	
	//Todo: Location Slots: These should actively updated when selected.  Not just saved/loaded.  Should be always saved.
	
	//Todo: UndoRedo: mindig jelolje ki a szovegreszeket, ahol a valtozasok voltak! MultiSelectionnal az osszeset!
	//Todo: UndoRedo: hash ellenorzes a teljes dokumentumra.
	//Bug: multiselect.copy -> items are in RANDOM order
	
	//Todo: Doodling layer. (rajzolgatas, bekarikazas, nyilazas, satirozas)
	
	//Todo: find: There must be a button to repeat find operation. The [Find] caption itself...
	/+Todo: Nem megy az Alt+. emoji beszuras, mert elveszti a fokiszt es akkor eltunteti a selections.+/
	/+
		Todo: ha kijelolok tobb szoveget, akkor a masolas utan beillesztve random sorrendben fogja azokat beszurni. 
		Kibaszottul idegesítô! 
	+/
	/+Todo: Implement predSwitch as a 2 column grid!+/
	/+
		Todo: single clicking on a module which is not has a cursor, should only deselect the existing cursors and select the whole module. 
		After this on a successful doubleclict, it could place a new cursor there, (only when modifiers = none)
	+/
	
	enum visualizeMarginsAndPaddingUnderMouse = (常!(bool)(0)); //Todo: make this a debug option in a menu
	
	auto frmMain()
	{ return (cast(FrmMain)mainWindow); } 
	
	auto global_getBuildResult()
	{ return frmMain.buildResult; } 
	
	size_t allocatedSize(in Cell c)
	{
		if(!c) return 0; 
		import core.memory; 
		size_t res = GC.sizeOf(cast(void*)c); 
		if(auto co = cast(const Container)c)
		{ res += co.subCells.map!(allocatedSize).sum; }
		return res; 
	} 
	
	//MainOverlay //////////////////////////////////////////////////////////
	class MainOverlayContainer : het.ui.Container {
		this()
		{ flags.targetSurface = 0; } 
		override void onDraw(Drawing dr)
		{ frmMain.drawOverlay(dr); } 
	} 
	
	
	//CellInfo ////////////////////////////////////////////
	
	struct CellInfoStruct
	{
		Cell cell; 
		
		string toString()
		{
			
			auto adjustStr(string s)
			{ return (s.empty || s.canFind('\n')) ? s.quoted : s; } 
			auto containerStr(CodeContainer c, string name)
			{ return name ~ adjustStr(c.prefix ~ c.postfix); } 
			
			return cell.castSwitch!(
				(Module a) 	=> "module", //m.file.name,
				(Declaration a) 	=> adjustStr(a.type ~ (a.opening.text~a.ending).strip),
				(CodeComment a) 	=> containerStr(a, "comment"),
				(CodeString a) 	=> containerStr(a, "string"),
				(CodeBlock a) 	=> containerStr(a, "block"),
				(CodeColumn a) 	=> "\u25a4",
				(CodeRow a) 	=> "\u25a5",
				(Glyph  a) 	=> a.ch<128 ? a.ch.text.quoted: '"'~a.ch.text~'"',
				(Cell a) 	=> typeid(a).name,
				() 	=> "null"
			); 
		} 
	} 
	
	auto cellInfo(Cell cl)
	{ return cl.CellInfoStruct; } 
	auto cellInfo(CellLocation cl)
	{ return cl.cell.CellInfoStruct; } 
	
	auto cellInfoText(T)(T a)
	{ return a.cellInfo.text; } 
	
	
	class FrmMain : GLWindow, IBuildServices
	{
		mixin autoCreate; 
		
		
		@STORED {
			bool mainMenuOpened; 
			
			enum MenuPage { Tools, Palette, Settings, ResMon } 
			MenuPage menuPage; 
			string toolPalettePage; 
			
			@property {
				//Todo: bad naming
				string _settings_launchRequirements() const { return buildsys_spawnProcessMultiSettings.toJson; } 
				void _settings_launchRequirements(string s) { buildsys_spawnProcessMultiSettings.fromJson(s); } 
			} 
			
			bool showModuleButtons, showTextSelectionDebugInfo, showHitTest, showUndoStack, showResyntaxQueue; 
			
			bool rightMenuOpened; 
		} 
		
		Path workPath = Path(`z:\temp2`); 
		
		Workspace workspace; 
		File workspaceFile; 
		bool initialized; //workspace has been loaded.
		
		MainOverlayContainer overlay; 
		
		Tid buildSystemWorkerTid; 
		
		BuildResult buildResult; //collects buildMessages and output
		
		string baseCaption; 
		bool isSpecialVersion; //This is a copy of the .exe that is used to cimpile dide2.exe
		
		MSQueue!string dbgRerouteQueue; 
		
		Bitmap[File] debugImageBlobs; void clearDebugImageBlobs() { mixin(求each(q{f},q{debugImageBlobs.byKey},q{bitmaps.remove(f); textures.invalidate(f); })); } 
		
		ToolPalette _toolPalette; @property toolPalette()
		{ if(!_toolPalette) _toolPalette = new ToolPalette; return _toolPalette; } 
		
		override void onCreate()
		{
			//onCreate //////////////////////////////////
			baseCaption = appFile.nameWithoutExt.uc; 
			isSpecialVersion = baseCaption != "DIDE2"; 
			
			{ auto a = this; a.fromJson(ini.read("settings", "")); }//Todo: this.fromJson
			
			initBuildSystem; 
			workspace = new Workspace(view, (cast(IBuildServices)(this))); 
			
			workspaceFile = appFile.otherExt(Workspace.defaultExt); 
			overlay = new MainOverlayContainer; 
			
			dbgRerouteQueue = new MSQueue!string; 
			globalDbgRerouteQueue = dbgRerouteQueue; 
		} 
		
		override void onDestroy()
		{
			ini.write("settings", this.toJson); 
			if(initialized) workspace.saveWorkspace(workspaceFile); 
			workspace.destroy; 
			destroyBuildSystem; 
		} 
		
		@VERB("Alt+F4") void closeApp()
		{ import core.sys.windows.windows; PostMessage(hwnd, WM_CLOSE, 0, 0); } 
		
		@property bool building()const
		{ return buildSystemWorkerState.building; } 
		@property bool ready()const
		{ return !buildSystemWorkerState.building; } 
		@property bool cancelling()const
		{ return buildSystemWorkerState.cancelling; } 
		@property bool running()const
		{ return !!dbgsrv.exe_pid; } 
		@property bool running_console()const
		{ return !!dbgsrv.console_hwnd; } 
		
		void initBuildSystem()
		{
			buildResult = new BuildResult; 
			buildSystemWorkerTid = spawn(&buildSystemWorker); 
		} 
		
		void updateBuildSystem()
		{
			{
				buildResult.receiveBuildMessages; 
				auto msgs = buildResult.incomingMessages.fetchAll; 
				workspace.buildMessages.process(msgs); 
			}
			
			{
				auto compilationResults = buildResult.incomingCompilationResults.fetchAll; 
				
				foreach(cr; compilationResults)
				{
					workspace.insight.processIncomingProjectJson(cr.xJson); 
					/+Opt: Cache these jsons, only generate if changed.+/
					
					if((常!(bool)(0))) print("Incoming CR:", cr.file, cr.xJson.length, cr.t0, cr.t1, cr.t1-cr.t0); 
					
					if(auto Δt = cr.t1 - cr.t0)
					if(auto m = workspace.modules.findModule(cr.file))
					m.compilationTime = Δt.value(second); 
				}
			}
			
			//Note: These operations are fast: only 0.015 ms
			
			if(dbgsrv.exe_pid)
			{
				const running = PIDModuleFileIsRunning(dbgsrv.exe_pid, workspace.modules.mainModuleFile.otherExt("exe")); 
				
				if(!running) {
					dbgsrv.exe_pid = 0; /+It's been terminated.+/
					WARN("PID terminated"); 
				}
			}
			
			if(dbgsrv.console_hwnd)
			{
				import core.sys.windows.windows; 
				if(!IsWindow(cast(HANDLE) dbgsrv.console_hwnd))
				dbgsrv.console_hwnd = 0; 
			}
			
			if(dbgsrv.exe_hwnd)
			{
				import core.sys.windows.windows; 
				if(!IsWindow(cast(HANDLE) dbgsrv.exe_hwnd))
				dbgsrv.exe_hwnd = 0; 
			}
			
			with(buildSystemWorkerState)
			{
				enum scale = 16; /+Note: It shows a tiny bit of progress at the start+/
				const total = totalModules*scale; 
				const act = (compiledModules*scale).max(1).min(total); 
				setTaskbarProgress(building, act, total); 
				
				//Todo: show error on the taskbarList
			}
		} 
		
		void destroyBuildSystem()
		{
			buildSystemWorkerTid.send(MsgBuildCommand.shutDown); 
			
			if(building)
			{
				LOG("Waiting for buildsystem to shut down."); 
				while(building) { write('.'); sleep(100); }
			}
		} 
		
		void launchBuildSystem(string command)()
		{
			static assert(command.among("rebuild", "run"), "Invalid command `"~command~"`"); 
			if(building)
			{ beep; return; }
			
			if(!workPath.exists) workPath.make; 
			
			BuildSettings bs = {
				killExe	: false/+It's deprecated. DIDE Kills it.+/,
				rebuild	: command=="rebuild",
				verbose	: false,
				compileOnly	: command=="rebuild",
				workPath	: this.workPath.fullPath,
				collectTodos	: false,
				generateMap 	: true,
				compileArgs	: ["-wi"], /+"-v" <- not good: it also lists all imports+/
				dideDbgEnv	: dbgsrv.getDataFileName,
				xJson	: true
			}; 
			
			void addOpt(string o)
			{ if(o.length) bs.compileArgs.addIfCan(o); } 
			
			buildSystemWorkerTid.send(cast(immutable)MsgBuildRequest(workspace.modules.mainModuleFile, bs)); 
			//Todo: immutable is needed because of the dynamic arrays in BuildSettings... sigh...
		} 
		
		
		void resetBuildState()
		{
			clearDebugImageBlobs; 
			workspace.buildMessages.firstErrorMessageArrived = false; 
			workspace.modules.modules.each!((m){ m.resetBuildMessages; }); 
			workspace.modules.modules.each!((m){ m.resetInspectors; }); 
			dbgsrv.resetBeforeRun; 
		} 
		
		void run()
		{
			if(!running) killRunningConsole; 
			resetBuildState; 
			launchBuildSystem!"run"; 
		} 
		
		void rebuild()
		{
			if(!running) killRunningConsole; 
			resetBuildState; 
			launchBuildSystem!"rebuild"; 
		} 
		
		void cancelBuild()
		{
			if(building) {
				workspace.buildMessages.firstErrorMessageArrived = true; //Don't focus on the upcoming cancellation error message!
				buildSystemWorkerTid.send(MsgBuildCommand.cancel); 
			}
		} 
		
		@property bool canKillCompilers()
		{ return !globalPidList.empty; } 
		
		void killCompilers()
		{
			workspace.buildMessages.firstErrorMessageArrived = true; //Don't focus on the upcoming cancellation error message!
			globalPidList.killAll; 
		} 
		
		
		@property bool canKillRunningProcess()
		{ return !!dbgsrv.exe_pid; } 
		
		void killRunningProcess()
		{
			if(canKillRunningProcess)
			{
				killAndWaitProcess(dbgsrv.exe_pid); 
				/+
					import core.sys.windows.windows; 
					if(auto hProcess = OpenProcess(PROCESS_TERMINATE, FALSE, dbgsrv.exe_pid))
					{
					/+
						Bug: ACCESS DENIED:
						After a process has terminated, call to TerminateProcess with open handles to the process fails with ERROR_ACCESS_DENIED (5) error code.
						https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-terminateprocess
						If you need to be sure the process has terminated, call the WaitForSingleObject function with a handle to the process.
						The handle must have the SYNCHRONIZE access right. For more information, see Standard Access Rights.
					+/
						TerminateProcess(hProcess, 0); 
						CloseHandle(hProcess); 
					}
				+/
			}
		} 
		
		@property bool canKillRunningConsole()
		{ return !!dbgsrv.console_hwnd; } 
		
		void killRunningConsole()
		{
			if(canKillRunningConsole)
			{
				import core.sys.windows.windows; 
				PostMessage(cast(HANDLE) dbgsrv.console_hwnd, WM_CLOSE, 0, 0); 
			}
		} 
		
		@property bool canCloseRunningWindow()
		{ return !!dbgsrv.exe_hwnd; } 
		
		void closeRunningWindow()
		{
			if(canCloseRunningWindow)
			{ dbgsrv.forceExit; }
		} 
		
		@property bool canTryCloseProcess()
		{
			//this is condition is used by the Ctrl+F2 button. Only tries once.
			return canCloseRunningWindow && !dbgsrv.isForcingExit; /+Note: windowed app.+/
		} 
		
		void closeOrKillProcess()
		{
			if(canTryCloseProcess)
			{ dbgsrv.forceExit; }
			else
			{ killRunningProcess; killRunningConsole; }
		} 
		
		void onDebugLog(string s)
		{
			//Todo: This communication should be full binary
			if(s.startsWith("INSP_"))
			{
				s = s[5..$]; 
				try
				{
					if(s.isWild("TXT:*:*"))
					{
						const 	id 	= wild[0].to!ulong(16),
							value 	= wild[1],
							moduleHash 	= (cast(uint)(id)),
							location 	= (cast(uint)(id>>32)); 
						if(auto m = moduleHash in workspace.modules.moduleByHash)
						{
							if(auto node = m.getInspectorNode(location))
							{
								if(auto ne = cast(NiceExpression)node)
								{
									ne.updateDebugValue(value); 
									addInspectorParticle(ne, clWhite, bounds2.init, ne.debugValueDiminisingIntensity); 
									return; 
								}
							}
						}
						WARN("Inspection unknown location: "~id.to!string(16)~":"~value); 
					}
					else if(s.isWild("TXT_BLB:*:*"))
					{
						const 	id 	= wild[0].to!ulong(16),
							blobAddress 	= wild[1].to!ulong(16),
							moduleHash 	= (cast(uint)(id)),
							location 	= (cast(uint)(id>>32)),
							value 	= (cast(string)(dbgsrv.getBlob(blobAddress))); 
						
						if(auto m = moduleHash in workspace.modules.moduleByHash)
						{
							if(auto node = m.getInspectorNode(location))
							{
								if(auto ne = cast(NiceExpression)node)
								{
									ne.updateDebugValue(value); 
									addInspectorParticle(ne, clWhite, bounds2.init, ne.debugValueDiminisingIntensity); 
									return; 
								}
							}
						}
					}
					else if(s.isWild("IMG_BLB:*:*:*:*:*"))
					{
						const 	id 	= wild[0].to!ulong(16),
							blobAddress 	= wild[1].to!ulong(16),
							moduleHash 	= (cast(uint)(id)),
							location 	= (cast(uint)(id>>32)),
							value 	= dbgsrv.getBlob(blobAddress),
							elementType	= wild[2],
							width	= wild[3].to!int(16),
							height	= wild[4].to!int(16); 
						
						Bitmap bmp; string error; 
						try
						{
							enforce(width>0 && height>0, i"Invalid image dimensions ($(width)x$(height))".text); 
							enforce(blobAddress, "Image Blob is null."); 
							auto buf = dbgsrv.getBlob(blobAddress); 
							enforce(buf.length, "Image Blob is empty."); 
							
							sw: 
							switch(elementType)
							{
								static foreach(C; AliasSeq!(ubyte, float))
								static foreach(N; [1, 2, 3, 4])
								{
									{
										static if(N==1) alias E = C; else alias E = Vector!(C, N); 
										case E.stringof: 
										bmp = new Bitmap(
											image2D(width, height, (cast(E[])(buf)))
											/+
												Note: NOT a copy!
												It points to Windows SharedMemory.
												
												This means, it is noisy, but good enough for debugging.
											+/
										); 
										break sw; 
									}
								}
								default: raise("Unknown ImageBlob element type: "~elementType); 
							}
							
							enforce(bmp && bmp.valid, "Can't load ImageBlob."); 
							bmp.modified = now; //Todo: This should come from the EXE, not from DIDE.
							bmp.file = File(i`temp:\\IMG_BLB_$(wild[0]).img`.text); 
							bitmaps.set(bmp); 
							/+
								Opt: ain't work: textures.refreshFile(bmp.file, bmp); 
								ain't work: textures.invalidate(bmp.file);
								Only Img.autoRefresh works and that's slow...
								This is a big mess...
							+/
							
							debugImageBlobs[bmp.file] = bmp; 
						}
						catch(Exception e)
						{ error = e.simpleMsg; }
						if(auto m = moduleHash in workspace.modules.moduleByHash)
						{
							if(auto node = m.getInspectorNode(location))
							{
								if(auto ne = cast(NiceExpression)node)
								{
									string imgParams; 
									if(auto col = ne.operands[1])
									if(auto cmt = col.lastRow.lastComment)
									{ imgParams = cmt.content.sourceText; }
									
									ne.updateDebugValue
										(
										((error=="")?(
											"$DIDE_CODE " ~ //prefix handled by Inspector Node.
											i"/+$DIDE_IMG $(bmp.file.cmdArg) autoRefresh=1 $(imgParams)+/".text
										) :("ImageBlob Error: " ~ error))
									); 
									//Opt: Img.autoRefresh is slow. It should update Img.stIdx
									
									addInspectorParticle(ne, clWhite, bounds2.init, ne.debugValueDiminisingIntensity); 
									return; 
								}
							}
						}
					}
					else
					raise("Invalid inspection message: "~s.quoted); 
				}
				catch(Exception e)
				{ ERR("Inspection exception: "~e.simpleMsg); }
			}
			else
			LOG("DBGLOG:", s); 
		} 
		
		void onDebugException(string message)
		{
			/+
				LOG("DBGEXC:\n"~message); 
				
				/+
					Bug: Exception messages are fucked up now.
					Take out the .map file interpreter from the .exe and move it to here.
					Because in exception handling it must not use GC!
					Only process .map file if there is no .pdb file.
					The exe should onpy produce an error report file.  If the map/pdb file is next to it, it can be interpreted.
				+/
				
				const defaultPrefix = workspace.mainModule ? workspace.mainModule.file.fullName~": " : "$unknown$.d: Error: "; 
				string lastPrefix; 
				string[] processedLines; 
				foreach(s; message.splitLines)
				{
					if(s.isWild(`?:\?*.d*(?*): *`)) {
						lastPrefix = wild[0]~`:\`~wild[1]~`.d`~wild[2]~`(`~wild[3]~`): `; 
						processedLines ~= s; 
					}
					else
					{
						s = s.strip; 
						if(s!="")
						processedLines ~= (lastPrefix.length ? lastPrefix : defaultPrefix) ~ s; 
					}
				}
				auto processedText = processedLines.join('\n'); 
				
				LOG("PROCESSED:\n"~processedText); 
				
				//Todo: process these errors more. d:\testExceptions.d   Also make an exception style and dont erase only the exceptions from the list.
			+/
			
			string processExceptionMessage(string message)
			{
				static bool ignoreFunction(string f)
				{
					static immutable list = 
					[
						`__scrt_common_main_seh`, `BaseThreadInitThunk`, `RtlUserThreadStart`, 
						`CallWindowProcW`, `CallWindowProcW`, `glPushClientAttrib`, `CallWindowProcW`, 
						`DispatchMessageW`, `SendMessageTimeoutW`, `KiUserCallbackDispatcher`, 
						`NtUserDispatchMessage`, `DispatchMessageW`, 
						`void rt.dmain2._d_run_main2(char[][], ulong, extern (C) int function(char[][])*).runAll()`, 
						`d_run_main2`, `d_wrun_main`
					]; 
					return list.canFind(f); 
				} 
				
				static bool ignoreLocation(string loc)
				{
					static immutable list = 
					[`\ldc2\import\core\internal\entrypoint.d(`, `\ldc2\import\std\exception.d(`]; 
					return list.any!((a)=>(loc.canFind(a))); 
				} 
				
				static string dquoted(string s) => '`' ~ s.replace("`", "<DQuote>") ~ '`'; 
				static addCol(string s) => s ~ ((s.canFind(','))?(""):(",1")); 
				
				auto lines = message.splitLines; 
				
				if(lines.get(1)=="----------------")
				{
					
					string doit(bool hasLocation)
					{
						string[] res, unprocessed; 
						
						string firstLocation; 
						foreach(s; lines.drop(2))
						{
							if(s.isWild(`0x???????????????? in * at ?:\?*.?*(*)`))
							{
								if(ignoreFunction(wild[1])) continue; 
								auto loc = i`$(wild[2]):\$(wild[3]).$(wild[4])($(addCol(wild[5]))): `.text; 
								if(ignoreLocation(loc)) continue; 
								if(firstLocation=="") firstLocation = loc; 
								res ~= i`$(loc)       called from $(dquoted(wild[1]))`.text; 
							}
							else if(s.isWild(`0x???????????????? in *`))
							{
								if(ignoreFunction(wild[1])) continue; 
								if(res.length)	res.back ~= i`, $(wild[1])`.text; 
								else	unprocessed ~= s; 
							}
							else if(s.strip!="")
							unprocessed ~= s; 
						}
						
						return chain(only(((hasLocation)?(""):(firstLocation))~lines[0]), res).join('\n'); 
					} 
					
					if(lines[0].isWild("?:\?*.?*(*): Exception: *")) return doit(true); 
					else if(lines[0].isWild("Exception: *")) return doit(false); 
				}
				
				return message; 
			} 
			
			message = processExceptionMessage(message); 
			auto dmdMessages = decodeDMDMessages(message, workspace.modules.mainModuleFile); 
			if(dmdMessages.length)
			{
				workspace.buildMessages.process(dmdMessages); 
				im.flashException(dmdMessages[0].oneLineText); 
			}
			else
			ERR("Failed to decode exception message: "~message); 
		} 
		
		////////////////////////////////////////////////////////////////////////////////////////////////////
		
		
		
		override void onPaint()
		{
			//onPaint ///////////////////////////////////////
			gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT); 
			
			toolPalette.visibleConstantNodes.clear; 
		} 
		
		void drawOverlay(Drawing dr)
		{
			if(0) dr.mmGrid(view); 
			
			workspace.customDraw(dr); 
			
			
			scope(exit) dr.alpha = 1; 
			dr.alpha = .5f; 
			dr.lineWidth = -1; 
			if(visualizeMarginsAndPaddingUnderMouse)
			foreach(cl; workspace.locate(view.mousePos.vec2))
			{
				auto rOuter 	= cl.globalOuterBounds; 
				auto rMargin 	= rOuter; 	cl.cell.margin.apply(rMargin); 
				auto rInner 	= rMargin; 	cl.cell.padding.apply(rInner); 
				
				/*
					dr.color = clRed	; dr.drawRect(rOuter);
					dr.color = clGreen	; dr.drawRect(rMargin);
					dr.color = clBlue	; dr.drawRect(rInner);
				*/
				
				void drawDiff(bounds2 o, bounds2 i)
				{
					if(o.top 	!= i.top	) dr.fillRect(o.left, o.top, o.right, i.top); 
					if(o.bottom 	!= i.bottom	) dr.fillRect(o.left, i.bottom, o.right, o.bottom); 
					if(o.left 	!= i.left	) dr.fillRect(o.left, i.top, i.left, i.bottom); 
					if(o.right 	!= i.right	) dr.fillRect(i.right, i.top, o.right, i.bottom); 
				} 
				
				dr.color = clWhite; dr.drawRect(rOuter); 
				dr.color = clWhite; dr.drawRect(rMargin); 
				dr.color = clWhite; dr.drawRect(rInner); 
				dr.color = clYellow; drawDiff(rOuter, rMargin); 
				dr.color = clAqua; drawDiff(rMargin, rInner); 
				
			}
			
			/*
				if(workspace.changed) foreach(m; workspace.modules) if(m.changed){
									LOG(m.file);
								} 
			*/
		} 
		
		override void afterPaint()
		{ bloodScreenEffect.glDraw; } 
		
		override void onUpdate()
		{
			workspace.mainIsForeground 	= this.isForeground; 
			//showFPS = true;
			//im.focus
			
			version(/+$DIDE_REGION update a virtual file from clipboard+/all) {
				static uint id; 
				if(id.chkSet(clipboard.sequenceNumber))
				File(`virtual:\clipboard.txt`).write(clipboard.text); 
				//Todo: sinchronize the clipboard both ways.
				//Todo: don't load too big files. And most importantly don't crash.
			}
			
			dbgsrv.onDebugLog = &onDebugLog; 
			dbgsrv.onDebugException = &onDebugException; 
			
			dbgsrv.update; 
			
			if(frmMain.isForeground && view.isMouseInside && (inputs.LMB.pressed || inputs.RMB.pressed))
			{ im.focusNothing; }
			
			updateBlink; 
			bloodScreenEffect.update; 
			
			updateBuildSystem; 
			
			if(application.tick>5 && initialized.chkSet)
			{
				CodeColumn.selfTest; 
				if(workspaceFile.exists) { workspace.loadWorkspace(workspaceFile); }
			}
			
			if(dbgRerouteQueue)
			dbgRerouteQueue.fetchAll.each!((msg){
				print("Local debug mgs:", msg); 
				//Todo: convert these into flashmessages
			}); 
			
			invalidate; //Todo: low power usage
			
			version(D_Optimized)	enum D_Optimized = true; 
			else	enum D_Optimized = false; //Todo: exeBuildInfo struct into het.utils
			
			caption = format!"%s%s - [%s] %s %s"(
				baseCaption,
				D_Optimized ? " (opt)" : "",
				workspace.modules.mainModuleFile.fullName,
				workspace.modules.modules.any!"a.changed" ? "Edited" : "",
				buildSystemWorkerState.building ? format!"Building: %d,  %d/%d"(buildSystemWorkerState.inFlight, buildSystemWorkerState.compiledModules, buildSystemWorkerState.totalModules) : "" 
				/+
					dbgsrv.pingLedStateText,
					dbgsrv.exe_pid ? dbgsrv.exe_pid.format!"PID:%s" : "",
					dbgsrv.console_hwnd ? dbgsrv.console_hwnd.format!"CON:%s" : ""
				+/
			); 
			
			/+
				view.navigate(false/+disable keyboard navigation+/ && !im.wantKeys && !inputs.Ctrl.down 
				&& !inputs.Alt.down && isForeground, false/+worksheet.update handles it+/!im.wantMouse && isForeground);
			+/
			view.updateSmartScroll; 
			view.animSpeed = mix(view.animSpeed, 0.3f, .01f); //slowly goes to it.
			setLod(view.scale_anim); 
			
			if(canProcessUserInput) callVerbs(this); 
			
			//Menu //////////////////////////////////////////////
			if(1)
			with(im)
			{
				Panel(
					PanelPosition.topLeft, 
					{
						if(!mainMenuOpened) {
							margin = "0"; padding = "0"; /+border = "1 normal gray";+/
							if(Btn(symbol("GlobalNavigationButton"), { innerWidth = fh; })) mainMenuOpened = true; 
						}
						else {
							margin = "0"; padding = "0"; 
							Row(
								{
									if(Btn(bold(symbol("ChevronLeft")), { innerWidth = fh; })) mainMenuOpened = false; 
									BtnRow(menuPage); 
								}
							); 
							Column(
								{
									padding = "2"; 
									with(workspace)
									{
										final switch(menuPage)
										{
											case MenuPage.Tools: 	{
												UI_refactor; 
												
												Grp!Column
												(
													"Show Debug Info",
													{
														ChkBox(showModuleButtons, "Module buttons"); 
														ChkBox(showHitTest, "HitTest"); 
														ChkBox(showUndoStack, "Undo stack"); 
														ChkBox(showResyntaxQueue, "Resyntax Queue"); 
														ChkBox(showFPS	, "Show FPS Graph"); 
													}
												); 
											}	break; 
													
											case MenuPage.Palette: 	with(toolPalette) {
												UI(toolPalettePage); 
												if(templateSource!="" && KeyCombo("LMB").pressed && isForeground)
												workspace.editor.insertNode(templateSource, subColumnIdx); 
											}	break; 
													
											case MenuPage.Settings: 	Grp!Column("BuildSystem: Launch Requirements", { buildsys_spawnProcessMultiSettings.stdUI; }); 	break; 
													
											case MenuPage.ResMon: 	resourceMonitor.UI(400); 	break; 
										}
									}
								}
							); 
						}
					}
				); 
				if(!mainMenuOpened)
				{
					const vec2 shiftOut = (magnitude(max((viewGUI.mousePos - lastContainer.outerBounds.bottomLeft) * vec2(1, 1), 0) * .02f))^^2 * vec2(-1, -1); 
					lastContainer.outerPos += shiftOut; 
				}
			}
			
			with(workspace)
			if(!modules.selectedStickers.empty)
			with(im)
			Panel(
				PanelPosition.topCenter, 
				{
					Row(
						{
							foreach(
								colorName; [
									"Yellow", "White", "LightOrange", "Olive", 
									"Green", "PastelBlue", "Aqua", "Blue", 
									"Orange", "Pink", "Red", "Purple"
								].map!"`Sticky` ~ a"
							)
							if(
								Btn(
									{
										Row(
											{
												flags.clickable = false; 
												style.bkColor = (colorName).toRGB; 
												border = "1 normal black"; 
												Text("    "); 
											}
										); 
									}, genericId(colorName)
								)
							)
							{
								foreach(s; modules.selectedStickers)
								if(s.props.color.chkSet(colorName))
								s.needMeasure; 
							}
						}
					); 
				}
			); 
			
			if(showModuleButtons)
			with(im)
			Panel(
				PanelPosition.topClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					Row(
						{
							 //Todo: Panel should be a Row, not a Column...
							Row({ workspace.modules.UI_ModuleBtns; flex = 1; }); 
						}
					); 
				}
			); 
			
			if(showTextSelectionDebugInfo)
			with(im)
			with(workspace)
			{
				if(textSelections[].length)
				{
					NL; 
					if(textSelections[].length>1)
					{ Text(format!"  Multiple Text Selections: %d  "(textSelections.length)); }
					else if(textSelections[].length==1)
					{ Text(format!"  Text Selection: %s  "(textSelections[0].toReference.text)); }
				}
			}
			
			if(showHitTest)
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					Row(
						{
							Text(hitTestManager.lastHitStack.map!(a => "["~a.id.text~"]").join(` `)); 
							NL; 
							if(hitTestManager.lastHitStack.length) Text(hitTestManager.lastHitStack.back.text); 
							
							Text("\n", workspace.locate_snapToRow(view.mousePos.vec2).text); 
						}
					); 
				}
			); 
			
			if(showUndoStack)
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					if(auto m = workspace.modules.primaryModule)
					{
						Container(
							{
								flags.hScrollState = ScrollState.auto_; 
								actContainer.appendCell(m.undoManager.createUI); 
							}
						); 
					}
				}
			); 
			
			
			if(showResyntaxQueue)
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					Column({ workspace.editor.UI_ResyntaxQueue; }); 
				}
			); 
			
			
			void VLine()
			{ with(im) Container({ innerWidth = 1; innerHeight = fh; bkColor = clGray; }); } 
			
			//StatusBar
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; 
					Row(
						{
							/*theme = "tool";*/ style.fontHeight = 18; 
							
							//Todo: faszomat ebbe a szarba:
							flags.vAlign = VAlign.center;  //ha ez van, akkot a text kozepre megy, de a VLine nem latszik.
							//flags.yAlign = YAlign.stretch; //ha ez, akkor meg a VLine ki van huzva.
							
							Row(
								{
									margin = "0 3"; flags.yAlign = YAlign.center; 
									//style.fontHeight = 18+6;
									//buildSystemWorkerState.UI; 
									
									if(dbgsrv.isActive)
									{
										if(Btn("■", enable(dbgsrv.isExeWaiting)).pressed) dbgsrv.setAck(1); 
										if(Btn("▶", enable(dbgsrv.isExeWaiting)).repeated) dbgsrv.setAck(-1); 
									}
									
									static bool buildOpt_release, buildOpt_debug; 
									//return Btn({ Column({ Row(); Row(); }); });
									
									static CaptIconBtn	(string srcModule=__MODULE__, size_t srcLine=__LINE__)
										(string capt, string icon, bool en = true)
									{
										return Btn!(srcModule, srcLine)
										(
											{
												Column(
													{
														flags.clickable = false; 
														Row(HAlign.center, { fh = ceil(fh*.66f); Text(capt); flags.clickable = false; }); 
														Row(HAlign.center, { Text(icon); flags.clickable = false; }); 
													}
												); 
											},
											enable(en)
										); 
									} 
									static CaptIconBtn2	(string srcModule=__MODULE__, size_t srcLine=__LINE__)
										(string capt, string icon, float w, bool en, void delegate() fun)
									{
										return Btn!(srcModule, srcLine)
										(
											{
												Row(
													{
														innerWidth = fh*w; 
														innerHeight = ceil(fh*1.66f); 
														flags.clickable = false; 
														Text(" ", icon!="" ? icon~" " : ""); 
														Text(capt~"\n"); 
														fh = ceil(fh*.66f); 
														fun(); 
													}
												); 
											},
											enable(en)
										); 
									} 
									
									
									BtnRow(
										{
											if(CaptIconBtn("REL", ((buildOpt_release)?("🚀"):("🐌")), !building)) buildOpt_release.toggle; 
											if(CaptIconBtn("DBG", ((buildOpt_debug)?("🐞"):("➖")), !building)) buildOpt_debug.toggle; 
										}
									)
									/+Todo: ezt a 2 buttont bekotni, hogy modositsa a project forrast.+/; 
									
									enum greenRightTriangle = tag("style fontColor=green")~" ▶ "~tag("style fontColor=black"); 
									
									static struct A { string capt, icon; void delegate() task; bool en = true; } 
									
									const modifier_rebuild = inputs.Shift.down; 
									
									{
										auto a = 	cancelling 	? A("Cancelling", "", {}, false) : 
											building 	? A("Building", "", {}, false) : 
											running 	? A("Running", "", {}, false) 
												: (
											modifier_rebuild 	? A("Rebuild", "⚙", { rebuild; })
												: A("Run", greenRightTriangle, { run; })
										); 
										if(
											CaptIconBtn2(
												a.capt, a.icon, 4, a.en, 
												{
													fh = ceil(fh*.66f); 
													with(buildSystemWorkerState)
													{
														const w = innerWidth; 
														Row(
															{
																flags.clickable = false; 
																innerSize = vec2(w, fh); 
																
																static drawProgress(
																	vec2 size, int compiled, int inFlight, int total,
																	RGB clBackground, RGB clQueued, RGB clCompiled
																)
																{
																	auto dr = new Drawing; 
																	
																	auto r = bounds2(vec2(0), size); 
																	if(!r.empty)
																	{
																		dr.color = clBackground; 
																		dr.fillRect(r); 
																		r = r.inflated(-.5f, -1);  //Opt: ellenorizni, ha ez double, akkor is floattal szamol-e.
																	}
																	
																	if(total.inRange(1, 1000) && !r.empty)
																	{
																		//Must do errorchecks, because it updated asynchronously as nasty globals.
																		compiled = compiled.clamp(0, total); 
																		inFlight = inFlight.clamp(0, total-compiled); 
																		
																		const sc = r.width / total; //Opt: ellenorizni, hogy ha ezt belerakom a box()-ba, akkor 1x szamolja-e.
																		
																		void box(int i) { dr.fillRect(bounds2(i*sc+.5f, r.top, i*sc+sc-.5f, r.bottom)); } 
																		
																		dr.color = clCompiled; 	foreach(i; 0 .. compiled) box(i); 
																		dr.color = mix(clQueued, clCompiled, blink^^2); 	foreach(i; compiled .. compiled+inFlight) box(i); 
																		dr.color = clQueued; 	foreach(i; compiled+inFlight .. total) box(i); 
																	}
																	
																	//Todo: a szinezes lehetne error/warning alapjan is.  A rectangle belseje lehetne olyan szinu.
																	//Todo: a legutolso forditas eredmenye maradjon kint. Ha projectet valt, akkor tunjon el.
																	
																	return dr; 
																} 
																bkColor = mix(bkColor, clGray, .175f); 
																addOverlayDrawing(
																	drawProgress(
																		innerSize, compiledModules, inFlight, totalModules, 
																		bkColor, mix(bkColor, clGray, .25f), clAccent
																	)
																); 
															}
														); 
													}
												}
											)
										) a.task(); 
									}
									{
										auto a = 	cancelling 	? A("Kill", "🔪", { killCompilers; }) :
											building 	? A("Cancel", "❌", { cancelBuild; }) :
											running	? (
											canTryCloseProcess 	? A("Close", "✖", { closeOrKillProcess; }) 
												: A("Kill", "🔪", { closeOrKillProcess; })
										) :
											canKillRunningConsole	? A("Close", "🖥", { killRunningConsole; })
												: A("Stop", "   ", {}, false); 
										if(
											CaptIconBtn2(
												a.capt, a.icon, 4, a.en, 
												{
													theme = "tool"; 
													auto B(string capt, bool vis, void delegate() fun)
													{ if(vis && Btn(capt, ((capt).genericArg!q{id}), enable(true), { margin = Margin(0, .5, 0, .5); })) fun(); } 
													
													B("LDC", canKillCompilers, &killCompilers); 
													B("PID", canKillRunningProcess, &killRunningProcess); 
													B("WND", canCloseRunningWindow, &closeRunningWindow); 
													B("CON", canKillRunningConsole, &killRunningConsole); 
													
													//Todo: Ha a window es a console open, de a nagy button disabled, akkor ezek sem hasznalhatoak.
													//Todo: ha csak a console window marad, azt is be lehessen zarni.🖥🗔
												}
											)
										) a.task(); 
									}
									
									
									/+🐌🚀✨🐞🔪🛠▶🛑🟥■+/
								}
							); 
							
							VLine; //---------------------------
							
							Row(
								{
									 flex = 1; margin = "0 3"; flags.yAlign = YAlign.center; flags.clipSubCells = true; 
									//style.fontHeight = 18+6;
									
									if(lod.moduleLevel) workspace.modules.UI_selectedModulesHint; 
									if(!lod.moduleLevel) workspace.help.UI_mouseLocationHint(workspace, view); 
									
									
									enum showMousePosCellInfoHint = false; 
									if(showMousePosCellInfoHint) Text("\n", workspace.locate(view.mousePos.vec2).map!cellInfoText.join(' ')); 
								}
							); 
							
							VLine; //---------------------------
							
							BtnRow(
								{
									margin = "0 3"; 
									workspace.buildMessages.UI_LayerBtns(view); 
								}
							); 
							VLine; //---------------------------
							
							Row(
								{
									margin = "0 3"; flags.vAlign = VAlign.center; 
									version(/+$DIDE_REGION+/none) {
										if(Btn("ErrorList")) workspace.showErrorList.toggle; 
										if(Btn("Calc size")) print(workspace.allocatedSize); 
									}
									Text(now.text); NL; 
									Text(
										i"FPS=$(FPS
	.format!"%.0f")  Z=$(log2(lod.pixelSize)
	.format!"%.2f")  A=$(view.animSpeed
	.format!"%.2f")".text
									); 
								}
							); 
							
							if(1)
							{
								VLine; 
								workspace.textSelections.UI_structureLevel; 
							}
							
							//this applies YAlign.stretch
							with(actContainer) {
								measure; 
								foreach(c; cast(.Container[])subCells) c.measure; 
							}
							
							
							
						}
					); 
				}
			); 
			
			with(im)
			{
				bool anyVisible; 
				Panel(
					workspace.outline.visible || workspace.insight.visible ? PanelPosition.rightClient : PanelPosition.topRight,
					{
						margin = "0"; padding = "0"; 
						bool[] vis = [
							workspace.search.UI(workspace.modules, workspace.textSelections, workspace.buildMessages, (cast(INavigator)(workspace)), view),
							workspace.insight.UI(workspace.modules, workspace.textSelections, workspace.editor, (cast(INavigator)(workspace)), view),
							workspace.outline.UI(workspace.modules, workspace.textSelections, view)
						]; /+Todo: refactor this terrible menu+/
						anyVisible = vis.any; 
						
						if(!anyVisible)
						{
							if(rightMenuOpened)
							{
								Row(
									{
										BtnRow(
											{
												if(Btn("📁", hint("Outline"))) { workspace.outlineActivate; }
												if(Btn("💡", hint("Insight"))) { workspace.insightActivate; }
												if(Btn("🔍", hint("Search"))) workspace.searchBoxActivate; 
											}
										); 
										if(Btn(bold(symbol("ChevronRight")), { innerWidth = fh; })) rightMenuOpened = false; 
									}
								); 
							}
							else
							{ if(Btn(symbol("GlobalNavigationButton"), { innerWidth = fh; })) rightMenuOpened = true; }
						}
					}
				); 
				if(!rightMenuOpened && !anyVisible)
				{
					const vec2 shiftOut = (magnitude(max((viewGUI.mousePos - lastContainer.outerBounds.bottomLeft) * vec2(-1, 1), 0) * .02f))^^2 * vec2(1, -1); 
					lastContainer.outerPos += shiftOut; 
				}
			}
			
			im.UI_FlashMessages; 
			
			workspace.update(view, buildResult); 
			im.root ~= workspace; 
			
			
			version(/+$DIDE_REGION Interactive controls on modules+/all)
			{
				with(im)
				{
					Container
					(
						{
							version(/+$DIDE_REGION Temporarily switch to 'view' surface. Slider needs the correct mousePos.+/all)
							{ selectTargetSurface(0); scope(exit) selectTargetSurface(1); }
							
							//	flags.targetSurface = 0; 
							
							auto enabledModule = workspace.modules.primaryModule; 
							const oldStyle = style; scope(exit) style = oldStyle; 
							
							mixin(求each(q{m},q{workspace.modules.modules},q{
								const moduleIsEnabled = m is enabledModule && !m.isReadOnly; 
								m.UI_constantNodes(moduleIsEnabled, 0); 
							})); 
						}
					); 
					
					root ~= removeLastContainer.subCells; //no need for the container, just the controls
				}
				
				if(dbgsrv.isActive /+Remove 'hold' on modified values. (Only hold them for a short period)+/)
				{
					const t0 = application.tick; 
					foreach(ref t; dbgsrv.data.interactiveValues.ticks) if(t<t0) t = 0; 
				}
			}
			
			im.root ~= overlay; 
			
			view.subScreenArea = im.clientArea / clientSize; 
			
			workspace.modules.UI_PopupScrumMenu(view.mousePos.vec2); 
			
			//bottomRight hint
			with(im)
			Panel
				(
				PanelPosition.bottomRight,
				{
					margin = "0 24 24 0"; 
					border = Border.init; 
					padding = "0"; 
					flags.noBackground = true; 
					workspace.help.UI_mouseOverHint(workspace.buildMessages, workspace.outerWidth); 
				}
			); 
			
			
			//update mouse cursor//////////////////////////
			MouseCursor chooseMouseCursor()
			{
				with(MouseCursor)
				{
					if(cancelling) return NO; 
					if(building) return APPSTARTING; 
					if(im.mouseOverUI || im.wantMouse) return ARROW; //Todo: im.chooseMouseCursor
					with(workspace.modules.moduleSelectionManager)
					{
						if(mouseOp == MouseOp.move) return SIZEALL; 
						if(mouseOp == MouseOp.rectSelect) return CROSS; 
					}
					if(workspace.textSelections[].any)
					{
						return IBEAM; 
						/+
							Bug: ez az IBeam a form jobb oldalan eltunik pont annyi pixelnyire 
														az ablak jobb szeletol, mint ahany pixelre az ablak bal szele van 
														a desktop bal szeletol merve.
						+/
					}
					return ARROW; 
				}
			} 
			
			mouseCursor = chooseMouseCursor; 
			
			//print(lod.zoomFactor*DefaultFontHeight);
		} 
	} 
	
}