module didebuilder; 

import didebase; 

import buildobjs : BuildSettings, globalPidList; 
import buildmessages : decodeDMDMessages; 
import buildsys : 	BuildResult, buildsys_spawnProcessMultiSettings, 
	buildSystemWorkerState, buildSystemWorker, MsgBuildCommand, MsgBuildRequest; 

import didemodulemanager : ModuleManager; 
import didebuildmessagemanager : BuildMessageManager; 

import dideexpr : NiceExpression; 
import didemodule : addInspectorParticle; 

import dideexternalcompiler: ExternalCompiler; 

class Builder : IBuildServices
{
	/+Note:  ⚠ Only a single builder is allowed because buildSystemWorkerState is global and singlular.+/
	
	mixin SmartChild!q{
		ModuleManager	modules,
		BuildMessageManager 	buildMessages
	}; 
	
	Path workPath = Path(`z:\temp2`); 
	
	Tid buildSystemWorkerTid; 
	BuildResult buildResult; //collects buildMessages and output
	
	Bitmap[File] debugImageBlobs; 
	
	ExternalCompiler externalCompiler; 
	
	@STORED
	{
		@property {
			//Todo: bad naming
			string _settings_launchRequirements() const => buildsys_spawnProcessMultiSettings.toJson; 
			void _settings_launchRequirements(string s) { buildsys_spawnProcessMultiSettings.fromJson(s); } 
		} 
	} 
	
	
	void _construct()
	{
		version(/+$DIDE_REGION Initialize external compiler services+/all)
		{
			const rootPath = Path(workPath, "DIDE_projfs_"~now.raw.only.hashOf.to!string(26)); 
			rootPath.wipe(false); 
			externalCompiler = new ExternalCompiler(rootPath, workPath); 
		}
		
		buildResult = new BuildResult; 
		buildSystemWorkerTid = spawn(&buildSystemWorker); 
	} 
	
	void _destruct()
	{
		buildSystemWorkerTid.send(MsgBuildCommand.shutDown); 
		
		if(building)
		{
			LOG("Waiting for buildsystem to shut down."); 
			while(building) { write('.'); sleep(100); }
		}
		
		externalCompiler.free; 
	} 
	
	@property stateText()
	=> ((building)?(
		format!"Building: %d,  %d/%d"(
			buildSystemWorkerState.inFlight, 
			buildSystemWorkerState.compiledModules, 
			buildSystemWorkerState.totalModules
		)
	):("")); 
	
	
	@property bool building()const
	=> buildSystemWorkerState.building; 	@property bool ready()const
	=> !buildSystemWorkerState.building; 		@property bool cancelling()const
	=> buildSystemWorkerState.cancelling; 	
	@property bool running()const
	=> !!dbgsrv.exe_pid;  @property bool running_console()const
	=> !!dbgsrv.console_hwnd; 
	
	
	protected void clearDebugImageBlobs()
	{ mixin(求each(q{f},q{debugImageBlobs.byKey},q{bitmaps.remove(f); textures.invalidate(f); })); } 
	
	protected void resetBuildState()
	{
		clearDebugImageBlobs; 
		buildMessages.firstErrorMessageArrived = false; 
		modules.modules.each!((m){ m.resetBuildMessages; }); 
		modules.modules.each!((m){ m.resetInspectors; }); 
		dbgsrv.resetBeforeRun; 
	} 
	
	
	void run()
	{
		if(!running) killRunningConsole; 
		resetBuildState; 
		launchBuildSystem!"run"; 
	}  void rebuild()
	{
		if(!running) killRunningConsole; 
		resetBuildState; 
		externalCompiler.reset; 
		launchBuildSystem!"rebuild"; 
	} 
	
	protected void dontFocusUpcomingErrorMessage()
	{ buildMessages.firstErrorMessageArrived = true; } 
	
	void cancelBuild()
	{
		if(building) {
			dontFocusUpcomingErrorMessage; 
			buildSystemWorkerTid.send(MsgBuildCommand.cancel); 
		}
	} 
	
	@property bool canKillCompilers()
	=> !globalPidList.empty;  void killCompilers()
	{
		dontFocusUpcomingErrorMessage; 
		globalPidList.killAll; 
	} 
	
	@property bool canKillRunningProcess()
	=> !!dbgsrv.exe_pid;  void killRunningProcess()
	{
		if(canKillRunningProcess)
		{ killAndWaitProcess(dbgsrv.exe_pid); }
	} 
	
	@property bool canKillRunningConsole()
	=> !!dbgsrv.console_hwnd;  void killRunningConsole()
	{
		if(canKillRunningConsole)
		{
			import core.sys.windows.windows; 
			PostMessage(cast(HANDLE) dbgsrv.console_hwnd, WM_CLOSE, 0, 0); 
		}
	} 
	
	@property bool canCloseRunningWindow()
	=> !!dbgsrv.exe_hwnd;  void closeRunningWindow()
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
	protected void launchBuildSystem(string command)()
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
			compileArgs	: [
				"-wi", 
				"-J", externalCompiler.rootPath.fullPath,
				/+"-v" <- not good: it also lists all imports+/
			],
			dideDbgEnv	: dbgsrv.getDataFileName,
			xJson	: true
		}; 
		
		void addOpt(string o)
		{ if(o.length) bs.compileArgs.addIfCan(o); } 
		
		buildSystemWorkerTid.send(cast(immutable)MsgBuildRequest(modules.mainModuleFile, bs)); 
		//Todo: immutable is needed because of the dynamic arrays in BuildSettings... sigh...
	} 
	
	void updateBuildSystem(void delegate(string) onProcessIncomingProjectJson)
	{
		{
			dbgsrv.onDebugLog = &onDebugLog; 
			dbgsrv.onDebugException = &onDebugException; 
			
			dbgsrv.update; 
		}
		
		{
			buildResult.receiveBuildMessages; 
			foreach(msg; buildResult.incomingMessages.fetchAll)
			{
				if(
					msg.type==DMDMessage.Type.unknown
					&& msg.content.isWild("$DIDE_EXTERNAL_COMPILATION_REQUEST: *")
				)
				{
					try
					{
						//Try to decode the 3 string parameters
						string[] params; params.fromJson("["~wild[0]~"]"); 
						
						if(params.length==3 /+old version+/)
						{
							const 	args 	= params[0], 
								incomingHash 	= params[1], 
								src 	= params[2]; 
							
							const calculatedHash = src.hashOf(args.hashOf).to!string(26); 
							enforce(
								incomingHash==calculatedHash, 
								i"Wrong hash $(incomingHash)!=$(calculatedHash)".text
							); 
							
							externalCompiler.addInput(
								args, src, calculatedHash, 
								msg.location.file.fullName, msg.location.lineIdx
							); 
							continue; 
						}
						
						if(params.length==2 /+new version+/)
						{
							const 	incomingHash 	= params[0], 
								srcParts 	= deserializeIES(params[1], incomingHash); 
							
							writeln(" -= ExternalCodeIES =- "); 
							auto 	ec = ExternalCodeIES(params[1], incomingHash),
								lineIdxMap = ec.getLineIdxMap(msg.location.lineIdx, partIdx: 1); 
							lineIdxMap.enumerate.drop(1)
								.each!((a){ print(format!"%3d -> %3d"(a.index, a.value)); }); 
							
							enforce(srcParts.length==2, i"Invalid srcParts count: $(srcParts.length)".text); 
							const 	args 	= srcParts[0], 
								src 	= srcParts[1]; 
							externalCompiler.addInput(
								args, src, incomingHash,
								msg.location.file.fullName, msg.location.lineIdx, 
								lineIdxMap
							); 
							continue; 
						}
						
						enforce(0, i"Uknown paramCount: $(params.length)".text); 
					}
					catch(Exception e) {
						ERR(
							"Invalid External Code pragma message exception: "
							~e.simpleMsg~"\n"
							~msg.content
						); 
					}
				}
				else if(
					msg.type==DMDMessage.Type.error
					&& msg.content.isWild(`static assert:  "$DIDE_EXTERNAL_COMPILATION_ERROR:*"`)
				)
				{ continue; }
				
				buildMessages.process(msg); 
			}
		}
		
		{
			auto compilationResults = buildResult.incomingCompilationResults.fetchAll; 
			
			foreach(cr; compilationResults)
			{
				onProcessIncomingProjectJson(cr.xJson); 
				/+Opt: Cache these jsons, only generate if changed.+/
				
				if((常!(bool)(0))) print("Incoming CR:", cr.file, cr.xJson.length, cr.t0, cr.t1, cr.t1-cr.t0); 
				
				if(auto Δt = cr.t1 - cr.t0)
				if(auto m = modules.findModule(cr.file))
				m.compilationTime = Δt.value(second); 
			}
		}
		
		//Note: These operations are fast: only 0.015 ms
		
		if(dbgsrv.exe_pid)
		{
			const running = PIDModuleFileIsRunning(dbgsrv.exe_pid, modules.mainModuleFile.otherExt("exe")); 
			
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
			mainWindow.setTaskbarProgress(building, act, total); 
			
			//Todo: show error on the taskbarList
		}
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
					if(auto m = moduleHash in modules.moduleByHash)
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
					
					if(auto m = moduleHash in modules.moduleByHash)
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
					if(auto m = moduleHash in modules.moduleByHash)
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
		import buildmessages : decodeDMDMessages; 
		auto dmdMessages = decodeDMDMessages(message, modules.mainModuleFile); 
		if(dmdMessages.length)
		{
			buildMessages.process(dmdMessages); 
			im.flashException(dmdMessages[0].oneLineText); 
		}
		else
		ERR("Failed to decode exception message: "~message); 
	} 
	
	void UI_Settings()
	{
		buildsys_spawnProcessMultiSettings.stdUI; 
		with(im) {
			Grp(
				"External compiler service",
				{
					Row("ProjFS root: \t", { Static(externalCompiler.rootPath.fullPath, { width = fh*12; }); }); 
					Row("Work path: \t", { Static(externalCompiler.workPath.fullPath, { width = fh*12; }); }); 
				}
			); 
		}
	} 
	
	void UI()
	{
		with(im)
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
	} 
	
	
	
	
	
} 