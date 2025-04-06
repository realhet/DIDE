module buildsys; 

import het;  
import std.file: dirEntries, SpanMode; 
import std.process: executeShell, Config, spawnProcess; 
import het.parser: DPaths, CodeLocation; 
import buildobjs: 	SourceCache, SourceStats, DMDMessageDecoder,
	SpawnProcessMultiSettings, spawnProcessMulti,
	MSVCEnv, LDCVER, calcHash, mainHelpStr, macroHelpStr, 
	ModuleInfo, resolveModuleImportDependencies, calculateObjHashes; 
public import buildobjs: DMDMessage, decodeDMDMessages, BuildSettings, globalPidList; 

mixin((
	(表([
		[q{/+Note: ModuleBuildState+/},q{/+Note: Colors+/}],
		[q{notInProject},q{clBlack}],
		[q{queued},q{clWhite}],
		[q{compiling},q{clWhite}],
		[q{aborted},q{clGray}],
		[q{hasErrors},q{clRed}],
		[q{hasWarnings},q{(RGB(128, 255, 0))}],
		[q{hasDeprecations},q{(RGB(64, 255, 0))}],
		[q{flawless},q{clLime}],
	]))
) .GEN!q{GEN_enumTable}); 

bool buildStateIsCompleted(ModuleBuildState a)
{ with(ModuleBuildState) return !!a.among(hasWarnings, hasDeprecations, flawless); } 

//convinience function with default settings only, no search paths
File[] allProjectFilesFromModule(File file)
{
	if(!file.exists) return []; 
	//Todo: not just for //@exe of //@dll
	BuildSettings settings = {verbose : false}; 
	BuildSystem buildSystem; 
	return buildSystem.findDependencies(file, settings).map!(m => m.file).array; 
} 

struct CompilationResult
{
	File file; 
	int result = int.min; 
	string output, xJson; 
	DateTime t0, t1; @property duration() => t1-t0; 
	
	bool valid() const => file && result==0; 
	bool opCast(T : bool)() const => valid; 
} 

struct BuildSystem
{
	private: //current build
		//input data
		File mainFile; 
		Path workPath; //mainly for the .obj files. This is optional.
		BuildSettings settings; 
	
		//flags
		//bool verbose, compileOnly, generateMap, isWindowedApp, collectTodos, useLDC, singleStepCompilation;
	
		//derived data
		bool isExe, isDll, hasCoreModule, isWindowedApp; 
		File targetFile, mapFile, defFile, resFile; 
		File[string] resFiles; 
		string[] runLines, defLines; 
		ModuleInfo[] modules; 
		string[] todos; 
	
		//cached data
		SourceCache sourceCache; 
		ubyte[][string] objCache, exeCache, mapCache, resCache; 
		string[string] outputCache, jsonCache; 
	
		//flags for special operation (daemon mode)
		public bool disableKillProgram, isDaemon; 
	
		//events ///////////////////////////////////////////////////////////////////////////
	
		void delegate(
		File mainFile, in File[] filesToCompile, in File[] filesInCache, 
		in string[] todos, in SourceStats sourceStats
	) onBuildStarted; 
		void delegate(in CompilationResult) onCompileProgress; 
		void delegate (DMDMessage[] messages) onBuildMessages; 
		bool delegate(int inFlight, int justStartedIdx) onIdle; //returns true if IDE wants to cancel.
	
		//logging
		public string sLog; 
		void log(T...)(T args)
	{
		if(settings.verbose)
		{ write(args); console.flush; }
		foreach(const s; args)
		sLog ~= to!string(s); 
	} 
		void logln	(T...)(T args)
	{ log(args, '\n'); } 
		void logf	(T...)(string fmt, T args)
	{ log(format(fmt, args)); } 
		void logfln(T...)(string fmt, T args)
	{ log(format(fmt, args), '\n'); } 
	
		//Performance monitoring
		struct Times
	{
		float compile=0, res=0, link=0, all=0; 
		float other()
		{ return all-compile-res-link; } 
		string report()
		{
			float pc = 100/all; 
			return bold("PERFORMANCE:  ")~
				format(
				"All:%.3f  =  Compile:%.3f + RC:%.3f + Link:%.3f + other:%.3f    (%.1f %.1f %.1f %.1f)%%",
				all, compile   , res   , link   , other   ,
				compile*pc, res*pc, link*pc, other*pc
			); 
		} 
	} 
		Times times; 
	
		struct Perf
	{
		float *t; 
		DateTime T0; 
		this(ref float f)
		{ T0 = now; t = &f; } 
		~this()
		{ *t += (now-T0).value(second); } 
	} 
		static perf(string f)
	{ return "auto _perfMeasurerStruct = Perf(times."~f~");"; } 
	
		void prepareMapPdbResDef()
	{
		//mapFile
		File mf = targetFile.otherExt(".map"); 
		mf.remove; 
		if(settings.generateMap)
		{ mapFile = mf; }
		
		//pdb file
		targetFile.otherExt(".pdb").remove; //just remove it.
		
		//defFile
		File df = targetFile.otherExt(".def"); //Todo: redundant
		df.remove; 
		if(!defLines.empty)
		{
			defFile = df; 
			string defContent = defLines.join("\r\n"); 
			defFile.write(defContent); 
			foreach(idx, line; defLines)
			logln(idx ? " ".replicate(5):bold("DEF: "), line); 
		}
		
		//resFile
		if(resFiles.length>0)
		resFile = targetFile.otherExt(".res"); 
		else resFile = File(""); 
		
	} 
	
		void initData(File mainFile_)
	{
		 //clears the above
		mainFile = mainFile_.actualFile; 
		enforce(mainFile.exists, "Can't open main project file: "~mainFile.fullName); 
		
		DPaths.init; 
		DPaths.addImportPath(mainFile.path.fullPath); 
		DPaths.addImportPath(`c:\d\libs\`); 
		
		isExe = isDll = hasCoreModule = isWindowedApp = false; 
		targetFile = File(""); 
		workPath = Path(""); 
		runLines			 .clear; 
		defLines			 .clear; 
		resFiles			 .clear; 
		modules	   .clear; 
		todos	   .clear; 
	} 
	
		static bool removePath(ref File fn, Path path)
	{
		 //Todo: belerakni az utils-ba, megcsinalni path-osra a DPath-ot.
		bool res = fn.fullName.startsWith(path.fullPath); 
		if(res)
		fn.fullName = fn.fullName[path.fullPath.length..$]; 
		return res; 
	} 
		static bool removePath(ref File fn, string path)
	{ return removePath(fn, Path(path)); } 
	
		static string bold(string s)
	{ return "\33\17"~s~"\33\7"; } 
	
		string smallName(File fn)
	{
		 //strips down extension, removes filePath
		fn.ext = ""; 
		
		if(!removePath(fn, mainFile.path))
		foreach(p; DPaths.allPaths)
		if(removePath(fn, p))
		break; 
		
		return fn.fullName.replace(`\`, `.`); 
	} 
	
		void processBuildMacro(string buildMacro)
	{
		void addCompileArgs(in string[] args)
		{ settings.compileArgs.addIfCan(args); } void addLinkArgs(in string[] args)
		{ settings.linkArgs.addIfCan(args); } void addLdcLinkArgs(in string[] args)
		{ settings.ldcLinkArgs.addIfCan(args); } 
		
		version(none) scope(exit) { LOG("buildMacro processed:", buildMacro.quoted, "settings:", settings.toJson); }
		
		const 	args	= splitCommandLine(buildMacro),
			cmd	= lc(args[0]),
			param1 	= args.length>1 ? args[1] : ""; 
		
		const isMain = modules.length==1; 
		
		const isTarget = ["exe", "dll"].canFind(cmd); 
		if(!isExe && !isDll)
		{ enforce(isTarget, "Main project file must start with target declaration (//@EXE or //@DLL) with an optional projectName."); }else
		{ enforce(!isTarget, "Target declaration (//@EXE or //@DLL) is already specified."); }
		
		alias CMD = het.parser.BuildMacroCommand; 
		final switch(cmd.to!CMD.ifThrown((cmd~'_').to!CMD))
		{
			case 	CMD.exe,
				CMD.dll: 	{
				enforce(isMain, "Target declaration (//@EXE or //@DLL) is not in the main file."); 
				
				isExe = cmd=="exe"; 
				isDll = cmd=="dll"; 
				
				auto ext = "."~cmd; 
				targetFile = ((param1.empty)?(mainFile.otherExt(ext)) :(File(mainFile.path, param1~ext))); 
				
				if(isDll)
				{
					//add implicit macros for DLL
					settings.compileArgs ~= "-shared"; 
					defLines ~= "LIBRARY"; 
					defLines ~= "EXETYPE NT"; 
					defLines ~= "SUBSYSTEM WINDOWS"; 
					defLines ~= "CODE SHARED EXECUTE"; 
					defLines ~= "DATA WRITE"; 
				}
			}	break; 
			case CMD.res: 	{
				string id = args.length>2 ? args[2] : ""; 
				auto src = File(param1); 
				
				if(!src.isAbsolute)
				src.path = mainFile.path; /+
					all resources are relative to the project, 
					unless they as absolute.
				+/
				
				bool any; 
				if(src.exists)
				{
					 //one file
					if(id=="")
					id = src.name; 
					resFiles[id] = src; 
					any = true; 
				}
				else
				{
					string pattern = src.name; 
					if(pattern=="")
					pattern = "*.*"; 
					try
					{
						//Todo: filekeresest belerakni a filePath-ba.
						foreach(f; dirEntries(src.path.fullPath, pattern, SpanMode.shallow))
						{
							 //many files
							auto fn = File(f.name); 
							if(fn.exists)
							{
								resFiles[id ~ fn.name] = fn; 
								any = true; 
							}
						}
					}
					catch(Throwable)
					{}
				}
				enforce(any, format(`Can't find any resources at: "%s"`, src)); 
				//Todo: source file/line number visszajelzes
			}	break; 
			
					
			case CMD.def: 	{ defLines ~= buildMacro[3..$].strip; }	break; 
			case CMD.win: 	{ isWindowedApp = true; }	break; 
			case CMD.compile: 	{ addCompileArgs(args[1..$]); }	break; 
			case CMD.link: 	{ addLinkArgs(args[1..$]); }	break; 
			case CMD.ldclink: 	{ addLdcLinkArgs(args[1..$]); }	break; 
					
			case CMD.run: 	{ runLines ~= buildMacro[3..$].strip.replace("$", targetFile.fullName); }	break; 
					
			case CMD.import_: 	{ DPaths.addImportPathList(buildMacro[6..$]); }	break; 
					
			case CMD.release: 	{
				enum releaseArgs = ["-release", "-O", "-inline", "-boundscheck=off"]; 
				addCompileArgs(releaseArgs); /+Todo: 250220 this seems deprecated.  -inline parameter is wrong for LDC2.+/
			}	break; 
			case CMD.debug_: 	{
				enum debugArgs = ["-g", "--gline-tables-only"]; 
				//Todo: WRONG NAMING!!! //@debug only means //@debugINFO!!!!
				addCompileArgs(debugArgs); 
				addLdcLinkArgs(debugArgs); 
			}	break; 
				/+
				Todo: The release and debug macro should be system-wide configurable. 
				Now it seems better to hardwire the most common options
			+/	
					
			case CMD.single: 	{ settings.singleStepCompilation = true; }	break; 
			case CMD.ldc: 	{ logln("Deprecated build macro: //@LDC"); }	break; 
			/+default: enforce(false, "Unknown BuildMacro command: "~cmd);+/
			
			/+
				Optional build macros:
					this is what ///@debug does:
						///@command -g
						///@ldclink -g
					This is houw to emit only line info:
						///@compile --gline-tables-only
			+/
		}
	} 
	
		//process source files recursively
		void processSourceFile(File file)
	{
		if(modules.canFind!(a => a.file==file))
		return; 
		
		enforce(file.exists, format(`File not found: "%s"`, file)); 
		
		//add this module
		double dateTime; 
		auto act = sourceCache.access(file); 
		modules ~= new ModuleInfo(act); 
		auto mAct = &modules[$-1]; 
		
		//process buildMacros
		foreach(bm; act.parser.buildMacros)
		processBuildMacro(bm); 
		
		//collect Todo/Opt list
		todos ~= act.parser.todos; 
		
		//decide if it has to link with windows libs
		if(!hasCoreModule)
		{
			foreach(const imp; act.parser.importDecls)
			if(imp.isCoreModule)
			{
				addIfCan(settings.linkArgs, ["kernel32.lib", "user32.lib"]); //Todo: not needed to add these, they're implicit -> try it out!
				hasCoreModule = true; 
				break; 
			}
		}
		
		//collect imports NEW
		foreach(const imp; act.parser.importDecls)
		if(imp.isUserModule)
		{
			if(
				const f = File(
					imp.resolveFile(
						mainFile.path, file.fullName, false/*
							File not found is only a warning, 
							not exception.
							The compiler or linkel will find out later
							if there is a problem.
						*/
					)
				)
			)
			if(!mAct.importedFiles.canFind(f))
			{
				mAct.importedFiles ~= f; 
				mAct.importedModuleNames ~= imp.name.fullName; 
			}
		}
		
		
		//reqursive walk on imports
		foreach(imp; mAct.importedFiles)
		processSourceFile(imp); 
	} 
	
		static string processDMDErrors(string sErr, string path)
	{
		//processes each errorlog individually, making absolute filepaths
		string[] list; 
		
		auto rx = rtRegex!`(.+)\(.+\): `; 
		foreach(s; sErr.splitLines)
		{
			
			//Make absolute paths.
			auto m = matchFirst(s, rx); 
			if(!m.empty)
			{
				string fn = m[1]; 
				if(!fn.canFind(`:\`))
				s = path ~ s; 
			}
			
			list ~= s~"\r\n"; 
		}
		return list.join; 
	} 
	
		static string mergeDMDErrors(string sErr)
	{
		//processes the combined log
		string[] list; 
		foreach(s; sErr.splitLines)
		{
			s ~= "\r\n"; 
			if(!list.canFind(s))
			list ~= s; 
		}
		return list.join; 
	} 
	
		ModuleInfo* findModule(in File fn)
	{
		foreach(ref m; modules)
		if(m.file==fn)
		return &m; 
		return null; 
	} 
	
		auto moduleFullNameOf(in File fn)
	{
		auto mi = findModule(fn); 
		return mi ? mi.moduleFullName : ""; 
	} 
	
		auto objFileOf(string ext="obj")(File srcFile)
	{
		//this is the simplest strategy
		if(!workPath)
		{
			return srcFile.otherExt(ext); //right next to the source file
		}else
		{
			auto s = moduleFullNameOf(srcFile); //Opt: it's slow
			enforce(s != "", "moduleFullNameOf() fail: "~srcFile.text); 
			return File(workPath, s~'.'~ext); 
		}
	} 
		
		auto jsonFileOf(File srcFile)
	{ return objFileOf!"json"(srcFile); } 
		
	
		bool is64bit()
	{ return !settings.compileArgs.canFind("-m32"); } 
		bool isOptimized()
	{ return settings.compileArgs.canFind("-O"); } 
		bool isIncremental()
	{ return !settings.singleStepCompilation; } 
	
		/// converts the compiler args from ldmd2 to ldc2
		void makeLdc2CompatibleArgs(ref string[] args)
	{
		foreach(ref a; args)
		{
			if(a=="-inline")
			a = "-enable-inlining=true";  //Note: this is the default in -O2
		}
	} 
	
		string[] makeCommonCompileArgs()
	{
		//make commandline args
		auto args = [
			"ldc2", "--vcolumns", "--verrors-context", 
			
			"--verrors=0", "--verror-supplements=0" 
			/+
				240813: 	LDC bugfix: Supplemental messages are always displayed, 
					even when their main messages are filtered out.
			+/
			
			/+"-v"+//+, /+It's quitr bogus in LDC.+/+/
		]; 
		
		/+
			Note: 20240928: From now I stop using --allinst.
			
			/+Link: https://forum.dlang.org/post/nedjfzfyxyudrjeypcvg@forum.dlang.org+/
			User1234: "-allinst" disable an internal system of speculation that is: "this instance is already 
			emitted so dont do it again".
			
			Over the years it has appeared that the speculation does not always work as it should.
			The classic symptom of that is when people encounter linker errors related to missing symbols. 
			
			"-allinst" is the number one workaround. When activated, it's likely that things get emitted 
			more than once, but at least, speculation bugs are gone.
			
			You may ask "but then there should be other linker errors about double definition ?". 
			No, those syms has to be emitted as "weak" symbols, so the linker ignore duplicated definitions.
		+/
		
		if(isIncremental)
		args ~= ["-c"/+, "-allinst"+/]; /+
			no more "-op", because every output filename 
			is specified explicitly with "-of="
		+/
		
		//default bitness is 64
		if(!settings.compileArgs.canFind("-m32") && !settings.compileArgs.canFind("-m64"))
		args ~= "-m64"; 
		
		//defaul mcpu if not present
		if(!settings.compileArgs.map!(a => a.startsWith("-mcpu=")).any)
		args ~= ["-mcpu=athlon64-sse3", "-mattr=+ssse3"]; 
		
		args ~= format!`-I=%s`(DPaths.getImportPathList); 
		
		args ~= settings.compileArgs; 
		
		return args; 
	} 
	
		string[][] makeCompileCmdLines(File[] srcFiles, string[] commonCompilerArgs)
	{
		//Todo: refact multi
		//Note: filenames are normalCase, but LDC2 must get lowercase filenames.
		
		string[][] cmdLines; 
		if(isIncremental)
		{
			foreach(fn; srcFiles)
			{
				auto c = commonCompilerArgs ~ ["-of=" ~ objFileOf(fn).fullName.lc, fn.fullName.lc]; 
				
				if(settings.xJson)
				c ~= ["-X", "--Xf=" ~ jsonFileOf(fn).fullName.lc]; 
				
				cmdLines ~= c; 
			}
		}
		else
		{
			//single
			auto c = commonCompilerArgs; 
			c ~= `-of=`~targetFile.fullName; 
			foreach(fn; srcFiles)
			c ~= fn.fullName.lc; //lowercase because LDC2 drops all kinds of errors.
			if(defFile.fullName!="")
			c ~= defFile.fullName; 
			if(resFile.fullName!="")
			c ~= resFile.fullName; 
			
			string[] libFiles; 
			foreach(fn; settings.linkArgs)
			switch(lc(File(fn).ext))
			{
				 //Todo: ezt osszevonni a linkerrel
				case ".lib": libFiles ~= fn; break; 
				default: break; 
			}
			
			
			//Todo: Handle of xJson
			
			cmdLines ~= c; 
		}
		return cmdLines; 
	} 
	
		string[] compileCommands; 
		
		enum printCommands = false; 
		
		void compile(File[] srcFiles, File[] cachedFiles) //Compile ////////////////////////
	{
		
		
		
		if(srcFiles.empty)
		return; 
		
		mixin(perf("compile")); 
		
		auto args = makeCommonCompileArgs(); 
		auto cmdLines = makeCompileCmdLines(srcFiles, args); 
		
		foreach(ref line; cmdLines)
		makeLdc2CompatibleArgs(line); 
		
		logln; logln(bold("COMPILE COMMANDS:")); 
		foreach(line; cmdLines)
		{ logln(joinCommandLine(line)); }
		
		logln; 
		
		//Todo: it's a big mess.
		compileCommands = cmdLines.map!joinCommandLine.array; 
		//this is passed to the link() where the $build.bat file will be exported.
		
		if(printCommands)
		{
			print; 
			compileCommands.each!print; 
		}
		
		//////////////////////////////////////////////////////////////////////////////////////
		
		string[] outputs; 
		string combinedOutput; 
		string allOutput; 
		int combinedResult; 
		
		void accumulateOutput(string output, File f)
		{
			combinedOutput ~= processDMDErrors(output, f.path.fullPath); 
			allOutput ~= f.fullName~": COMPILER OUTPUT:\n"~output~"\n"; 
		} 
		
		log(bold("Compiling: ")); 
		
		DMDMessageDecoder msgDec; 
		msgDec.defaultPath = mainFile.path; 
		
		void fetchAndCall_onBuildMessages()
		{
			auto messages = msgDec.fetchUpdatedMessages.map!"a.dup".array; 
			/+Note: dup needed for thread safety, because msg.subMessages array can grow.+/
			if(messages.length && onBuildMessages)
			onBuildMessages(messages); 
		} 
		
		if(todos.length /+Note: Send all todos, bugs and opts before launching the compilers.+/)
		with(msgDec) {
			actSourceFile = mainFile; 
			processDMDOutput(todos); 
			fetchAndCall_onBuildMessages; 
		}
		
		foreach(srcFile; cachedFiles)
		{
			const 	objHash 	= findModule(srcFile).objHash,
				output	= outputCache[objHash]; 
			
			if(onCompileProgress)
			onCompileProgress(
				mixin(體!((CompilationResult),q{
					srcFile, 0/+success+/, output, jsonCache[objHash],
					DateTime.init, DateTime.init /+because cached+/
				}))
			); 
			
			accumulateOutput(output, srcFile); 
			
			{
				msgDec.actSourceFile = srcFile; 
				auto lines = output.splitLines; //Todo: Find a way to distinguish stdout and stderr.
				msgDec.processDMDOutput_partial(lines, true); 
				fetchAndCall_onBuildMessages; 
			}
		}
		
		bool cancelled; 
		combinedResult = spawnProcessMulti
		(
			srcFiles, cmdLines, null, 
			/*working dir=*/mainFile.path, /*log path=*/workPath, outputs, 
			((idx, result, output, t0, t1) {
				//logln(bold("COMPILED("~result.text~"): ")~joinCommandLine(cmdLines[idx]));
				log(
					" \33#*\33\7 "	.replace("#", result ? "\14" : "\12")
						.replace("*", srcFiles[idx].name)
				); 
				
				const xJson = ((
					settings.xJson
					/+
						Note: There can be a valid X Json when the compilation fails.
						I keep that too because it helps resolving the error.
					+/
				) ?(jsonFileOf(srcFiles[idx]).readText(false)):("")); 
				
				//storing obj into objCache
				if(isIncremental && result==0)
				{
					const 	srcFile	= srcFiles[idx],
						objFile	= objFileOf(srcFile),
						objHash 	= findModule(srcFile).objHash; 
					objCache[objHash] = objFile.forcedRead; 
					outputCache[objHash] = output; 
					jsonCache[objHash] = xJson; 
				}
				
				if(onCompileProgress)
				onCompileProgress(mixin(體!((CompilationResult),q{srcFiles[idx], result, output, xJson, t0, t1}))); 
				
				static if(0)
				{
					//hard stop: kill
					return result == 0; //break(kill) if any error
				}
				else
				{
					//soft stop: cancel and keep all results.
					if(result)
					cancelled = true; 
					return true; //continue
				}
			}),
			((int inFlight, int justStartedIdx) {
				cancelled |= onIdle ? onIdle(inFlight, justStartedIdx) : false; 
				return cancelled; 
			}),
			
			buildsys_spawnProcessMultiSettings,
			
			((string id, ref string[] stdOut, ref string[] stdErr, bool isFinal) {
				//foreach(a; stdErr) print("incoming>", a); 
				msgDec.actSourceFile = File(id); 
				
				/+Always take every output line from stdOut.+/
				msgDec.addConsoleMessage(stdOut.fetchAll); 
				
				/+Only complete messages are fetched form stdErr.+/
				msgDec.processDMDOutput_partial(stdErr, isFinal); 
				
				fetchAndCall_onBuildMessages; 
			})
		); 
		
		/+
			print("=========================================="); 
			msgDec.messages.each!print; 
		+/
		
		//Todo: cleanup here. The combined output aren't used anymore...
		
		logln; 
		logln; 
		
		//process combined error log
		foreach(i, o; outputs)
		accumulateOutput(o, srcFiles[i]); 
		combinedOutput = mergeDMDErrors(combinedOutput); 
		
		//add todos
		if(settings.collectTodos)
		combinedOutput ~= todos.map!(s => s~"\r\n").join; 
		
		if(!combinedOutput.empty)
		logln(combinedOutput); 
		
		if(1) { File(workPath, `$output.txt`).write(allOutput); }
		
		//check results
		enforce(!cancelled, "Compillation cancelled."); 
		enforce(combinedResult==0, combinedOutput); 
	} 
	
		void overwriteObjsFromCache(File[] filesInCache)
	{
		File[] objWritten; 
		foreach(fn; filesInCache)
		{
			 //provide files already in cache
			auto data = objCache[findModule(fn).objHash]; 
			auto objFn = objFileOf(fn); 
			if(objFn.writeIfNeeded(data))
			objWritten ~= fn; 
		}
		if(!objWritten.empty)
		logln(bold("WRITING CACHE -> OBJ: "), objWritten.map!(a=>smallName(a)).join(", ")); 
	} 
	
		void resCompile(File resFile, string resHash) //Todo: ez igy csunya, ahogy at van passzolva
	{
		mixin(perf("res")); 
		resFile.remove; 
		if(resFiles.length>0)
		{
			auto resInCache = (resHash in resCache) !is null; 
			if(resInCache)
			{
				 //found in cache
				auto data = resCache[resHash]; 
				if(!equal(resFile.read, data))
				{
					logln(bold("WRITING CACHE -> RES: "), resFile); 
					resFile.write(data); 
				}
			}else
			{
				 //recompiling
				auto rcFile = resFile.otherExt(".rc"); 
				
				string toCString(File s)
				{ return `"`~s.fullName.replace(`\`, `\\`).replace(`"`, `\"`)~`"`; } 
				
				//create rc content
				auto rcContent = resFiles.byKeyValue
					.map!(kv => format("Z%s 999 %s", kv.key.binToHex, toCString(kv.value))).join("\r\n"); 
				rcFile.write(rcContent); 
				
				//call RC.exe
				auto rcCmd = ["rc", rcFile.fullName]; 
				auto line = joinCommandLine(rcCmd); 
				logln(bold("CALLING RC: "), line); 
				auto rc = executeShell(line, MSVCEnv.getEnv(is64bit), Config.suppressConsole | Config.newEnv); 
				//Todo: resource compiler totally bugs on 64bit. Workaround: use resource hacker manually
				
				//cleanup
				rcFile.remove; 
				
				enforce(enforce(rc.status==0, rc.output)); 
				
				logln(bold("STORING RES -> CACHE: "), resFile); 
				resCache[resHash] = resFile.read; 
			}
		}else
		{
			resFile.remove; //no resfile needed
		}
	} 
	
		void link(string[] linkArgs, string[] ldcLinkArgs)
	{
		mixin(perf("link")); 
		if(modules.empty)
		return; 
		
		string[] 	objFiles = modules.map!(m => objFileOf(m.file).fullName).array,
			libFiles,           //user32, kernel32 nem kell, megtalalja magatol
			linkOpts; //Todo: kideriteni, hogy ez miert kell a windowsos cuccokhoz
		
		if(settings.generateMap)
		addIfCan(linkOpts, "/MAP"/+Generate map file+/)/+Todo: If there is proper pdb support, no need for the map file.+/; 
		
		foreach(fn; linkArgs)
		switch(lc(File(fn).ext))
		{
			 //sort out different link commandline parts
			case ".obj": 	objFiles ~= fn; 	break; 
			case ".lib": 	libFiles ~= fn; 	break; 
			case ".map": 	mapFile = File(fn); 	break; 
			default: 	linkOpts ~= fn; //treat as an option
		}
		
		
		//Todo: /ENTRY, /SUBSYSTEM=CONSOLE/WINDOWS  -> VisualD has help.
		
		string[] cmd; 
		static if(LDCVER>=128)
		{
			cmd = 	[
				"ldc2", `-of=` ~ targetFile.fullName,
				`--link-internally`, //default = ms link
				`--mscrtlib=libcmt`
			] ~ //default = libcmt
				ldcLinkArgs ~
				linkOpts.map!"`-L=`~a".array ~
				objFiles; 
		}else
		{
			cmd = 	[
				"link",	 `/LIBPATH:`~(is64bit?`c:\D\ldc2\lib64`:`c:\D\ldc2\lib32`), //Todo: the place for these is in DPath
					 `/OUT:`~targetFile.fullName,
					 `/MACHINE:`~(is64bit ? "X64" : "X86")
			] ~
				linkOpts ~
				libFiles ~
				`legacy_stdio_definitions.lib` ~
				objFiles ~
				["druntime-ldc.lib", "phobos2-ldc.lib", /*msvcrt.lib*/ "libcmt.lib"]; 
		}
		
		if(resFile)
		cmd ~= resFile.fullName; 
		
		//add libs for LDC
		/+
			Note: LDC 1.20.0: "msvcrt.lib": gives a warning in the linker.
						https://stackoverflow.com/questions/3007312/resolving-lnk4098-defaultlib-msvcrt-conflicts-with
							libcmt.lib: static CRT link library for a release build (/MT)
							msvcrt.lib: import library for the release DLL version of the CRT (/MD)
						LDC 1.28: no need to add manually. --mscrtlib=...
		+/
		
		
		auto line = joinCommandLine(cmd); 
		logln(bold("LINKING: "), line); 
		auto link = executeShell(line, null, Config.suppressConsole, size_t.max, mainFile.path.fullPath); 
		
		if(printCommands) print(line); 
		
		//Todo: Move this to the beginning of the build process, so I can run this manually if anything fails.
		File(targetFile.path, "$build.bat").write(chain(compileCommands, line.only).join("\r\n")); 
		
		//cleanup
		defFile.remove; 
		if(targetFile.extIs("exe"))
		{
			targetFile.otherExt("exp").remove; 
			targetFile.otherExt("lib").remove; 
		}
		
		enforce(link.status==0, "Link Error: "~link.status.text~" "~link.output); //stop the compiling process
	} 
	
	
	public: 
		void reset_cache()
	{
		sourceCache.reset; 
		objCache.clear; 
		outputCache.clear; 
		jsonCache.clear; 
		exeCache.clear; 
		mapCache.clear; 
		resCache.clear; 
	} 
		//Errors returned in exceptions
		void build(in File mainFile_, in BuildSettings originalSettings)
	{
		{
			//build /////////////////////////////////////////////////
			times = times.init; 
			mixin(perf("all")); 
			
			sLog = ""; 
			initData(mainFile_); 
			settings = originalSettings.dup; 
			
			//Rebuild all?
			if(settings.rebuild)
			reset_cache; 
			
			//workPath
			workPath = settings.getWorkPath(Path("")); //"" means obj files are placed next to their sources.
			
			//reqursively collect modules
			processSourceFile(mainFile); 
			
			//check if target exists
			enforce(isExe||isDll, "Must specify project target (//@EXE or //@DLL)."); 
			
			//calculate dependency hashed of obj files to lookup in the objCache
			modules.resolveModuleImportDependencies; 
			const compilerSalt = joinCommandLine(settings.compileArgs); 
			
			LOG(settings.compileArgs); 
			modules.calculateObjHashes(compilerSalt); //Note: Compiler specific hash generation.
			
			//ensure that no std or core files are going to be recompiled
			foreach(const m; modules)
			enforce(!DPaths.isStdFile(m.file), `It is forbidden to recompile an std/etc/core module. `~m.file.text); 
			
			//select files for compilation
			File[] filesToCompile, filesInCache; 
			foreach(ref m; modules)
			((m.objHash !in objCache) ? filesToCompile : filesInCache) ~= m.file; 
			
			//order by age
			filesToCompile = filesToCompile.sort!((a, b) => a.modified > b.modified).array; 
			
			SourceStats sourceStats = {
				totalModules 	: modules.length.to!int,
				totalLines	: modules.map!"a.sourceLines".sum,
				totalBytes	: modules.map!"a.sourceBytes".sum
			}; 
			
			
			//print out information
			{
				logln(bold("BUILDING PROJECT:    "), mainFile); 
				logln(bold("TARGET FILE:         "), targetFile); 
				logln(
					bold("OPTIONS:             "), 	"LDC", " ", 
						is64bit?64:32, "bit ", 
						isOptimized?"REL":"DBG", " ", 
						settings.singleStepCompilation?"SINGLE":"INCR"
				); 
				with(sourceStats)
				logln(
					bold("SOURCE STATS:        "), 
					format("Modules: %s   Lines: %s   Bytes: %s", totalModules, totalLines, totalBytes)
				); 
				
				
				if(0)
				{
					 //verbose display of the module graph
					foreach(i, const m; modules)
					{
						auto list = m.deps.filter!(fn => fn!=m.file).map!(a => smallName(a)).join(", "); 
						bool comp = filesToCompile.canFind(m.file); 
						logln((comp ? " \33\16*\33\7 " : "  "), bold(smallName(m.file))~" : "~list); 
					}
				}
				
				if(1)
				{
					if(filesToCompile.length)
					logln(bold("MODULES TO COMPILE:  "), (mixin(求map(q{f},q{filesToCompile},q{smallName(f)}))).join(", ")); 
					if(filesInCache  .length)
					logln(bold("MODULES FROM CACHE:  "), (mixin(求map(q{f},q{filesInCache},q{smallName(f)}))).join(", ")); 
				}
			}
			
			//notify the ide, that a compilation has started. So it can mark the modules visually.
			if(onBuildStarted)
			onBuildStarted(mainFile, filesToCompile, filesInCache, todos, sourceStats); 
			
			//deprecated functionality: DIDE kills the target.
			//delete target file and bat file.
			//It ensures that nothing uses it, and there will be no previous executable present after a failed compilation.
			/+
				targetFile.remove(false); 
				if(targetFile.exists)
				{
					if(settings.killExe && !disableKillProgram)
					{ enforce(killDeleteExe(targetFile), "Failed to close target process."); }else
					{ enforce(false, "Unable to delete target file."); }
				}
			+/
			
			targetFile.remove(true); 
			
			/////////////////////////////////////////////////////////////////////////////////////
			//calculate resource hash
			string resHash = calcHash(resFiles.byKeyValue.map!(kv => format!"(%s|%s|%s)"(kv.key, kv.value, kv.value.modified)).join); 
			
			
			/////////////////////////////////////////////////////////////////////////////////////
			//Cleanup: define what to do at cleanup. Do it even if an Exception occurs.
			scope(exit)
			{
				if(!settings.leaveObjs)
				{
					 //including res file
					resFile.remove; 
					foreach(fn; chain(filesToCompile, filesInCache))
					{
						objFileOf(fn).remove; 
						if(settings.xJson) jsonFileOf(fn).remove; 
					}
					
				}
				if(!settings.generateMap)
				mapFile.remove; //linker makes it for dlls even not wanted
			}
			
			/////////////////////////////////////////////////////////////////////////////////////
			//compile and link
			auto exeHash = calcHash(joinCommandLine(settings.linkArgs ~ targetFile.fullName ~ modules[0].objHash ~ resHash)); 
			//depends on main obj and on linker params.  //todo: include resource hash
			
			bool exeInCache = (exeHash in exeCache) !is null; 
			if(exeInCache)
			{
				//exe file is already found in cache
				auto data = exeCache[exeHash]; 
				logln(bold("WRITING CACHE -> EXE: "), targetFile); 
				targetFile.write(data); //overwrite if needed
				if(exeHash in mapCache)
				mapFile.write(mapCache[exeHash]); 
			}else
			{
				prepareMapPdbResDef; 
				resCompile(resFile, resHash); 
				
				compile(filesToCompile, filesInCache); 
				overwriteObjsFromCache(filesInCache); 
				link(settings.linkArgs, settings.ldcLinkArgs); 
				
				logln(bold("STORING EXE -> CACHE: "), targetFile); 
				exeCache[exeHash] = targetFile.read; 
				if(mapFile.exists)
				mapCache[exeHash] = mapFile.read; 
			}
			
		}//end of compile
		
		
		/////////////////////////////////////////////////////////////////////////////////////
		//performance monitoring
		logln(times.report); 
		
		/////////////////////////////////////////////////////////////////////////////////////
		//run
		if(!settings.compileOnly)
		{
			//This is closing the console in the new window, not good, needs a bat file anyways...
			/*
				if(runLines.empty && isExe){
					runLines ~= targetFile.fullName;
					if(!isWindowedApp) runLines ~= "@pause";
				}
				if(!runLines.empty){
					auto cmd = ["cmd", "/c", runLines.join("&")];
					logln(bold("RUNNING: ") ~ cmd.text);
					spawnProcess(cmd);
				}
			*/
			
			//old version
			const batFile = File(targetFile.path, "$run.bat"); 
			batFile.remove; 
			//Bug: When DIDE is compiled and running, the program it runs will overwrite this same bat file. Solution -> $run_exename.bat
			
			auto runCmd = runLines.join("\r\n"); 
			
			//make the default runCmd for exe
			if(runCmd.empty && isExe)
			{
				runCmd = targetFile.fullName; 
				//if(!isWindowedApp) runCmd ~= "\r\n@pause";
			}
			
			if(!runCmd.empty)
			{
				batFile.write(runCmd); 
				foreach(idx, line; runCmd.split('\n'))
				logln(idx ? " ".replicate(9):bold("RUNNING: "), line); 
				const env = settings.dideDbgEnv!="" ? ["DideDbgEnv" : settings.dideDbgEnv] : null; 
				
				//Todo: spawnShell could be simpler...
				spawnProcess(["cmd", "/c", "start", batFile.fullName], env, Config.detached, targetFile.path.fullPath); 
			}
		}
	} 
	
	
		auto findDependencies(File mainFile_, BuildSettings originalSettings)
	{
		sLog = ""; 
		initData(mainFile_); 
		settings = originalSettings; 
		
		//Rebuild all?
		if(settings.rebuild)
		reset_cache; 
		
		//workPath
		workPath = settings.getWorkPath(
			Path("")
			/+"" means obj files are placed next to their sources.+/
		); 
		
		//reqursively collect modules
		processSourceFile(mainFile); 
		
		return modules; 
	} 
	
	
		//This can be used by commandline or by a dll export.
		//Input: args (args[0] is ignored)
		//Outputs: statnard ans error outputs.
		//result: 0 = no error
		int commandInterface(string[] args, ref string sOutput, ref string sError)
	{
		try
		{
			sLog = sError = sOutput = ""; 
			
			settings = BuildSettings.init; 
			auto opts = parseOptions(args, settings, No.handleHelp); 
			
			//args.each!print; import het.stream;print(settings.toJson);
			
			if(opts.helpWanted || args.length<=1)
			{
				settings.verbose = true; 
				logln(mainHelpStr.replace(`$$$OPTS$$$`, opts.helpText)); 
			}
			else if(settings.macroHelp)
			{
				settings.verbose = true; 
				logln(macroHelpStr); 
			}
			else
			{
				auto mainFile = File(args[1]); 
				enforce(mainFile.exists, "Error: File not found: "~mainFile.fullName); 
				build(mainFile, settings); //this overwrites the settings.
			}
			
			sOutput = sLog; 
			return 0; 
		}
		catch(Exception e)
		{
			//sError = format("Exception in %s(%s): %s", e.file, e.line, e.msg);
			sError = e.simpleMsg; 
			sOutput = sLog; 
			return -1; 
		}
	} 
	
		void	cacheInfo()
	{
		/*
				logln(bold("CACHE STATS:"));
			foreach(m; modules){
				logln(m.moduleFullName.leftJustify(20));
			}
		*/
	}  
	
} version(/+$DIDE_REGION BuildSystemWorker+/all)
{
	import core.thread, std.concurrency; 
	
	
	//messages sent to buildSystemWorker
	
	enum MsgBuildCommand
	{ cancel, shutDown} 
	
	struct MsgBuildRequest
	{
		File mainFile; 
		BuildSettings settings; 
	} 
	
	
	//messages received from buildSystemWorker
	
	struct MsgBuildStarted
	{
		File mainFile; 
		immutable File[] filesToCompile, filesInCache; 
		immutable string[] todos; 
		SourceStats sourceStats; 
	} 
	
	struct MsgCompileStarted
	{
		int fileIdx=-1;    //indexes MsgBuildStarted.filesToCompile
	} 
	
	struct MsgCompileProgress
	{ CompilationResult compilationResult; } 
	
	struct MsgBuildFinished
	{
		File mainFile; 
		string error; 
		string output; 
	} 
	
	struct MsgBuildMessages
	{ shared DMDMessage[] messages; } 
	
	
	
	struct BuildSystemWorkerState
	{
		//BuildSystemWorkerState /////////////////////////////////
		//worker state that don't need synching.
		bool building, cancelling; 
		int totalModules, compiledModules, inFlight; 
	} 
	
	__gshared const BuildSystemWorkerState buildSystemWorkerState; 
	
	__gshared SpawnProcessMultiSettings buildsys_spawnProcessMultiSettings; //controls multithreaded compilation behavior
	
	void buildSystemWorker()
	{
		BuildSystem buildSystem; 
		auto state = &cast()buildSystemWorkerState; 
		bool isDone = false; 
		
		//register events
		
		void onBuildStarted(
			File mainFile, in File[] filesToCompile, in File[] filesInCache, 
			in string[] todos, in SourceStats sourceStats
		)
		{
			//Todo: rename to buildStart
			with(state)
			{
				totalModules = (filesToCompile.length + filesInCache.length).to!int; 
				compiledModules = inFlight = 0; 
			}
			
			//LOG(mainFile, filesToCompile, filesInCache);
			ownerTid.send(MsgBuildStarted(mainFile, filesToCompile.idup, filesInCache.idup, todos.idup, sourceStats)); 
		} 
		buildSystem.onBuildStarted = &onBuildStarted; 
		
		void onCompileProgress(in CompilationResult cr)
		{
			state.compiledModules++; 
			//LOG("######################", file, result, output);
			ownerTid.send(MsgCompileProgress(cr)); 
		} 
		buildSystem.onCompileProgress = &onCompileProgress; 
		
		bool onIdle(int inFlight, int justStartedIdx)
		{
			state.inFlight = inFlight; 
			
			if(justStartedIdx>=0)
			ownerTid.send(MsgCompileStarted(justStartedIdx)); 
			
			//receive commands from mainThread
			bool cancelRequest = false; 
			receiveTimeout
			(
				0.msecs,
				((MsgBuildCommand cmd) {
					if(cmd==MsgBuildCommand.shutDown)
					{ cancelRequest = true; isDone = true; 	state.cancelling = true; }
					else if(cmd==MsgBuildCommand.cancel) { cancelRequest = true; 	state.cancelling = true; }
				}),
				
				((immutable MsgBuildRequest req) { WARN("Build request ignored: already building..."); })
			); 
			
			return cancelRequest; 
		} 
		buildSystem.onIdle = &onIdle; 
		
		void onBuildMessages(DMDMessage[] messages)
		{ ownerTid.send(MsgBuildMessages(cast(shared)messages)); } 
		buildSystem.onBuildMessages = &onBuildMessages; 
		
		//main worker loop
		while(!isDone)
		{
			receive
			(
				((MsgBuildCommand cmd) {
					if(cmd==MsgBuildCommand.shutDown)
					isDone = true; 
				}),
				
				((immutable MsgBuildRequest req) {
					string error; 
					try
					{
						state.building = true; 
						//Todo: onIdle
						buildSystem.build(req.mainFile, req.settings); 
					}
					catch(Exception e)
					{ error = e.simpleMsg; }
					ownerTid.send(MsgBuildFinished(req.mainFile, error, buildSystem.sLog)); 
				})
			); 
			
			state.clear; //must be the last thing in loop to clear this.
		}
		
	} 
}


class BuildResult
{
	File mainFile; 
	File[] filesToCompile, filesInCache; 
	File[] allFiles; 
	bool[File] filesInProject, filesInFlight; 
	
	int[File] results; //command line console exit codes
	
	DMDMessage[] incomingMessages; //incoming from the MessageDecoder. Must be polled and fetched.
	CompilationResult[] incomingCompilationResults; //incoming X Json files.  Other side must pull!
	
	SourceStats sourceStats; 
	
	DateTime lastUpdateTime, buildStarted, buildFinished; 
	
	mixin ClassMixin_clear; 
	
	auto getBuildStateOfFile(File f) const
	{
		with(ModuleBuildState)
		{
			if(f !in filesInProject)
			return notInProject; 
			if(auto r = f in results)
			{
				if(*r)
				return hasErrors; 
				return hasWarnings; //Todo: detect hasDeprecations, flawless
			}
			return f in filesInFlight ? compiling : queued; 
		}
	} 
	
	
	void receiveBuildMessages()
	{
		while(
			receiveTimeout
			(
				0.msecs,
				((in MsgBuildStarted msg) {
					clear; 
					
					buildStarted = now; 
					sourceStats = msg.sourceStats; 
					
					mainFile = msg.mainFile; 
					
					filesToCompile = msg.filesToCompile.dup; 
					filesInCache = msg.filesInCache.dup; 
					
					allFiles = filesToCompile ~ filesInCache; 
					allFiles.each!((f){
						filesInProject[f] = true; 
						//Todo: initialize fileNameFixer with these correct names
					}); 
					
					foreach(f; filesInCache)	{
						//generate valid outputs of cached files.
						results[f] = 0;  //0 = success
					}
				}),
				
				((in MsgCompileStarted msg) {
					auto f = filesToCompile.get(msg.fileIdx); 
					assert(f); 
					filesInFlight[f] = true; 
				}),
				
				((in MsgCompileProgress msg) {
					const f = msg.compilationResult.file; 
					filesInFlight.remove(f); 
					results[f] = msg.compilationResult.result; 
					incomingCompilationResults ~= msg.compilationResult; 
				}),
				
				((in MsgBuildMessages msg) {
					auto messages = (cast(DMDMessage[])(msg.messages)); 
					/+Note: Safe to cast, it's not used anywhere else.+/
					
					incomingMessages ~= messages; //DIDE will poll this.
				}),
				
				((in MsgBuildFinished msg) {
					buildFinished = now; 
					
					filesInFlight.clear; 
					
					if(msg.error!="")
					{
						incomingMessages ~= new DMDMessage(
							CodeLocation(mainFile.fullName), 
							DMDMessage.type.error, "BuildSys: "~msg.error
						); 
					}
					
					{
						const buildStatText = format!
							"BuildStats:  %.3f seconds,  %d modules,  %d source lines,  %d source bytes"
							(
							(buildFinished-buildStarted).value(second), 
							sourceStats.totalModules,
							sourceStats.totalLines,
							sourceStats.totalBytes
						); 
						incomingMessages ~= new DMDMessage(
							CodeLocation(mainFile.fullName), 
							DMDMessage.type.console, buildStatText
						); 
					}
				})
				
			)
		)
		{ lastUpdateTime = now; }
	} 
	
} 
version(/+$DIDE_REGION+/all) {
	
	
	
	
}