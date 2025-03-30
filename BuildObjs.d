module buildobjs; 

version(/+$DIDE_REGION+/all) {
	/+
		Todo: 240624
		Integrating other external compilers into LDC2
		/+Link: https://forum.dlang.org/post/aeerdahnkiujvrdwyxvt@forum.dlang.org+/
		
		LDC2 -> DIDE: pragma(msg, x)  Special message catched realtime using pipeProcess()
		DIDE -> LDC2: import(fileName)  -J Virtual files in a directory using ProjFS
	+/
	
	
	//Todo: syntaxHighlight() returns errors! Build system it must handle those!
	//Todo: RUN: set working directory to the main.d
	//Todo: editor: goto line
	//Todo: a todokat, meg optkat meg warningokat, ne jelolje mar pirossal az editorban a filenevek tabjainal.
	//Todo: editor find in project files.
	//Todo: editor clear errorline when compiling
	//Todo: invalid //@ direktivaknal error
	//Todo: a dll kilepeskor takaritsa el az obj fileokat
	//Todo: use shebang hashbang #! at the beginning of the file to mark that is is a main file.
	/+
		Todo: Revisit the obj file hash calculation. It should only include the options that are make the obj different. 
		Must exclude RUN commands for example.
	+/
	//Todo: editor: ha typo-t ejtek, es egy nekifutasra irtam be a szot, akkor magatol korrigaljon!
	//Todo: Ha vmelyik modulnal error van, az osszes olyan modul forditasat allitsa le, amelyik fugg attol!
	//Todo: In the future it could handle special pragmas: pragma(msg, __FILE__~"("~__LINE__.text~",1): Message: ...");
	/+
		Todo: Interctive Incremental build: While COMPILING a project and any modules of it being SAVED,
		then it should RECOMPILE that particular module again. 
		So, istead of BLOCKING the file save operation, SOLVE the situation intelligently!
	+/
	
	/*
		[ ] irja ki, hogy mi van a cache-ban.
		[x] run program utan eltunik a console
		[ ] a visszaadott output text nem tartalmazhat szineket, vagy tartalmazhat, 
		   de akkor meg a delphiben kell azokat a kodokat kiszedni. (1B)
		[ ] kill build lehetosege.
		
		// ezek nem mennek kulonallo buildsystembol, csak az ide-bol!!!
		[-] kill program accessviolazik
		[-] kill program szinten meghiva a DIDE debug service-t, azt majd tiltani kell. 
		   Ugyanis kesobb allandoan mukodni fog ez az exe es emiatt nem csatlakozhat ra a dide-re! Ezen agyalni kell!
	*/
	
	/+
		240317 DConf
		/+Todo: kiprobalni a DUB-ot (nem multithreaded)+/
		/+Todo: kiprobalni a reggae-t (multithreaded)+/
		/+Todo: kiprobalni a compiler time trace-t /+Code: LDC --ftime-trace+/+/
	+/
	
	import het, het.parser; 
	import std.process: executeShell, Config; 
	import std.regex; 
	//std.file, std.path, std.process
	
	
	enum LDCVER = 139
	/+The targeted LDC version by this builder.  Valid versions: 139+/; 
	
	class GlobalPidList
	{
		import std.process; 
		
		private bool[Pid] list; 
		
		void add(Pid pid)
		{ synchronized(this) list[pid] = true; } 
		
		void remove(Pid pid)
		{ synchronized(this) if(pid in list) list.remove(pid); } 
		
		void killAll()
		{
			synchronized(this)
			{
				list.keys.each!kill; 
				list.clear; 
			} 
		} 
		
		auto opSlice()
		{
			Pid[] res; 
			synchronized(this) res = list.keys; 
			return res; 
		} 
		
		auto opCall()
		{
			Pid[] res; 
			synchronized(this) res = list.keys.sort.array; 
			return res; 
		} 
		
		bool empty() const
		{
			bool res; 
			synchronized(this) res = list.empty; 
			return res; 
		} 
	} 
	
	alias globalPidList = Singleton!GlobalPidList; 
	//Todo: globalPidList... Not the best naming...
	
	
	struct SpawnProcessMultiSettings
	{
		mixin((
			(表([
				[q{/+Note: Type+/},q{/+Note: Name+/},q{/+Note: Default+/},q{/+Note: @RANGE+/},q{/+Note: @CAPTION+/},q{/+Note: @HINT+/}],
				[q{uint},q{minLatency_ms},q{100},q{0, 10_000},q{"Min latency (ms)"},q{"Amout of time it will wait 
between consequtive compiler launches."}],
				[q{uint},q{maxThreads},q{8},q{1, 32},q{"Max running threads"},q{"Maximum number of 
concurrent compilers running."}],
				[q{uint},q{maxCpuUsage_percent},q{90},q{10, 100},q{"Max CPU usage %"},q{"Maximum CPU usage % allowed 
when launching a new compiler instance."}],
				[q{uint},q{minAvalilableRam_GB},q{2},q{0, 100},q{"Min free RAM (GB)"},q{"RAM requirement to launch 
a new compiler instance."}],
				[q{uint},q{stdLineGroupungInterval_ms},q{500},q{0, 10_000},q{"Grouping Interval (ms)"},q{"Group consequtive incoming text lines from stdOut and stdErr.  
	0	:  Disable.
	max 	: Process all  lines when the exe finishes."}],
			]))
		).調!(GEN_fields)); /+
			ram: 	12GB 	5/8 cores	128.2s
				24GB 	8/8 cores	107.6s  19% speedup
				8GB	12/12 cores 	partial fail!
				8GB	4/12 cores	works.
		+/
	} 
	
	int spawnProcessMulti(
		File[] ids, in string[][] cmdLines, 
		in string[string] env, Path workPath, Path logPath, out string[] sOutput, 
		bool delegate(int idx, int result, string output, DateTime t0, DateTime t1) onProgress/*returns enable flag*/, 
		bool delegate(int inFlight, int justStartedIdx) onIdle/*return cancel flag*/,
		in ref SpawnProcessMultiSettings settings,
		void delegate(string id, ref string[] stdOut, ref string[] stdErr, bool isFinal) onStdLineReceived
	)
	{
		class Executor
		{
			/+Todo: Measure start and end times for module compilation stats+/
			
			import std.process, std.file : chdir; 
			
			string id; //to identify this executor
			
			//input data
			string[] cmd; 
			string[string] env; 
			Path workPath; 
			
			//temporal data
			ProcessPipes pipes; 
			@property pid() => pipes.pid; 
			GroupByTime!string 	stdOutGrouper, 
				stdErrGrouper; string[] 	pendingOutLines, 
				pendingErrLines; 
			
			//output data
			int result; 
			bool ended; 
			string output; 
			
			//timing
			DateTime t0, t1; @property duration() => t1-t0; 
			
			enum State
			{ idle, running, finished} 
			@property state() => ((pid !is null)?(State.running) : (((!ended)?(State.idle) :(State.finished)))); 
			@property isIdle() => state==State.idle; 
			@property isRunning() => state==State.running; 
			@property isFinished() => state==State.finished; 
			
			
			Thread outThread, errThread; 
			
			this()
			{} 
			
			protected void appendOutput(string s)
			{
				if(s.length) {
					if(output.length) output ~= '\n'; 
					output ~= s; 
				}
			} 
			
			void setup(string id, in string[] cmd, in string[string] env = null, Path workPath = Path.init)
			{
				if(isRunning) ERR("already running"); 
				
				version(/+$DIDE_REGION Reset everything+/all)
				{
					kill; 
					this.clearFields_init; 
				}this.id 	= id,
				this.cmd 	= cmd.dup,
				this.env 	= cast(string[string])env,
				this.workPath 	= workPath; 
			} 
			
			void start(string id, in string[] cmd, in string[string] env = null, Path workPath = Path.init)
			{
				setup(id, cmd, env, workPath); 
				start; 
			} 
			
			this(bool startNow, string id, in string[] cmd, in string[string] env = null, Path workPath = Path.init)
			{
				this(); 
				((startNow)?(&start):(&setup))(id, cmd, env, workPath); 
			} 
			
			
			protected void setEndResult(int val)
			{
				result = val; 
				pipes = ProcessPipes.init; 
				t1 = now; 
				ended = true; 
			} 
			
			protected void killPipeReader(alias thr)()
			{ thr.free; } 
			
			protected void waitPipeReader(alias thr)()
			{
				ignoreExceptions({ if(thr) thr.join; }); 
				thr.free; 
			} 
			
			protected void fetchPipes(Time minT, bool isFinal=false)
			{
				if(stdOutGrouper.canGet(minT) || stdErrGrouper.canGet(minT) || isFinal /+Fast exit without synching.+/)
				synchronized(this /+Note: synches GroupeByTime structs.+/)
				{
					if(isFinal) minT = 0*second; 
					auto 	o 	= stdOutGrouper.get(minT),
						e	= stdErrGrouper.get(minT); 
					pendingOutLines 	~= o,
					pendingErrLines 	~= e; 
					if(o.length || e.length || isFinal)
					{
						onStdLineReceived(id, pendingOutLines, pendingErrLines, isFinal); 
						appendOutput(chain(o, e).join('\n')); 
					}
				} 
			} 
			
			protected void fetchPipes_final()
			{ fetchPipes(0*second, true); } 
			
			
			void start()
			{
				if(isRunning) { ERR("already running"); return; }
				
				t0 = now; 
				pipes = pipeProcess(
					cmd, Redirect.stdout | Redirect.stderr, env, 
					Config.suppressConsole, workPath.fullPath
				); 
				
				version(/+$DIDE_REGION Start listening to stdOut and stdErr+/all)
				{
					output = ""; 
					
					outThread = new Thread
					(
						{
							foreach(a; pipes.stdout.byLineCopy.map!((a)=>(a.withoutEnding('\r'))))
							{ synchronized(this) stdOutGrouper.put(a); }
						}
					); 
					errThread = new Thread
					(
						{
							foreach(a; pipes.stderr.byLineCopy.map!((a)=>(a.withoutEnding('\r'))))
							{ synchronized(this) stdErrGrouper.put(a); }
						}
					); 
					
					outThread.start; 
					errThread.start; 
				}
				
				if(pid) globalPidList.add(pid); 
			} 
			
			void update()
			{
				//checks if the running process ended.
				if(pid !is null)
				{
					fetchPipes(settings.stdLineGroupungInterval_ms * milli(second)); 
					
					auto w = tryWait(pid); 
					if(w.terminated)
					{
						globalPidList.remove(pid); 
						
						/+
							Note: These readers should automatically ended after the process is terminated,
							so it's OK to just wait for them.
						+/
						waitPipeReader!outThread; 
						waitPipeReader!errThread; 
						
						fetchPipes_final; 
						
						//output is already collected in 'output' field.
						
						setEndResult(w.status); 
					}
				}
			} 
			
			void kill()
			{
				if(pid) globalPidList.remove(pid); //make sure to remove.
				
				killPipeReader!outThread; 
				killPipeReader!errThread; 
				
				if(!isFinished)
				{
					if(pid)
					try
					{
						std.process.kill(pid); 
						/+
							Bug: ACCESS DENIED bug when stopping compilers:
							After a process has terminated, call to TerminateProcess with open handles to the process fails with ERROR_ACCESS_DENIED (5) error code.
							https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-terminateprocess
							If you need to be sure the process has terminated, call the WaitForSingleObject function with a handle to the process.
							The handle must have the SYNCHRONIZE access right. For more information, see Standard Access Rights.
						+/
					}
					catch(Exception e)
					{
						WARN(e.extendedMsg); 
						/+
							Sometimes it gives "Access is denied.", 
							maybe because it's already dead, so just ignore.
						+/
					}
					setEndResult(-1); 
				}
			} 
			
		} 
		/// returns true if it must work more
		static bool update(
			Executor[] executors, 
			bool delegate(
				int idx, int result, string output, 
				DateTime t0, DateTime t1
			) onProgress = null
		)
		{
			bool doBreak; 
			foreach(i, e; executors)
			{
				if(!e.isFinished)
				{
					e.update; 
					if(e.isFinished && (onProgress !is null))
					{
						const doContinue = onProgress(i.to!int, e.result, e.output, e.t0, e.t1); 
						if(!doContinue) doBreak = true; 
					}
				}
				if(doBreak) break; 
			}
			
			if(doBreak) { executors.each!(e => e.kill); }
			
			return !executors.all!(e => e.isFinished); 
		} 
		
		
		//it was developed for running multiple compiler instances.
		
		Executor[] executors = (mixin(求map(q{a},q{cmdLines.enumerate},q{new Executor(false, a.value.filter!"a.endsWith(`.d`)".join(';'), a.value, env, workPath)}))).array; 
		
		DateTime lastLaunchTime; 
		bool cancelled; 
		
		while(update(executors, onProgress))
		{
			const runningCnt = executors.count!(e => e.isRunning).to!int; 
			
			bool canLaunchNow()
			{
				with(settings)
				return runningCnt==0 /+the very first compiler will launc immediately+/|| 
					(
					(now-lastLaunchTime).value(milli(second)) >= minLatency_ms
					&& runningCnt < maxThreads.clamp(0, GetNumberOfCores)
					&& GetCPULoadPercent <= maxCpuUsage_percent 
					&& GetMemAvailMB >= minAvalilableRam_GB*1024
				); 
			} 
			
			sizediff_t justStartedIdx = -1; 
			if(!cancelled && canLaunchNow)
			foreach(i, e; executors)
			if(e.isIdle)
			{
				e.start; 
				lastLaunchTime = now; 
				justStartedIdx = i; 
				break; 
			}
			
			if(onIdle)
			cancelled |= onIdle(runningCnt, justStartedIdx.to!int); 
			if(cancelled && runningCnt==0)
			break; 
			
			sleep(10); //Todo: config
		}
		
		sOutput = []; 
		auto res = 0; 
		foreach(e; executors)
		{
			if(e.result)
			res = e.result; //aggregate error codes
			//combine output and error lof
			sOutput ~= e.output; 
		}
		
		
		return res; 
		
	} 
	
	
	//////////////////////////////////////////////////////////////////////////////
	//Builder help text                                                       //
	//////////////////////////////////////////////////////////////////////////////
	
	immutable
		versionStr = "1.06",
		mainHelpStr =  //Todo: ehhez edditort csinalni az ide-ben
		"\33\16HLDC\33\7 "~versionStr~" - An automatic build tool for the \33\17LDC "~
		{ auto s = LDCVER.text; return s[0]~"."~s[1..$]; }()~
		"\33\7  compiler.
by \33\0\34\x0Cre\34\x0Fal\34\x0Ahet\34\0\33\7 2016-2022  Build: "~__TIMESTAMP__~
		"

\33\17Usage:\33\7  hldc.exe <mainSourceFile.d> [options]

\33\17Daemon mode:\33\7  hldc.exe daemon [default options]

\33\17Requirements:\33\7
 * Visual Studio 2017 Community Edition (for the VC runtime, not anymore for the ms linker)
 * Visual D (this installs LDC2 and sets up the environment for VS)
 * LDC location must be: c:\\d\\ldc2\\bin\\ldc2.exe (to access precompiled libs from there)
 * Implicit path of static libraries: c:\\d\\ldc2\\lib64\\ (put any .lib files here)
 * Implicit path of library includes: c:\\d\\libs\\ (you can put here your package folders)
 * Only supports Windows 64bit target, incremental build
 * Main module must start with this build-macro: //@EXE

\33\17Known bugs:\33\7
 * Fixed in LDC 1.28: Don't use Tuples in format(). They're conflicting with the -allinst parameter which is
   required for incremental builds.
 * Resource building is broken.
 * Dll/Lib output is also broken.

\33\17Options:\33\7
$$$OPTS$$$
",
		macroHelpStr =
		"\33\17Build-macros:\33\7
  These special comments are embedded in the source files to control various
  options in HLDC. No other external/redundant files needed, every information
  needed for a build is stored inside your precious sources files.
  Double quotes are supported for parameters containing spaces.

\33\17//@MACRO_COMMAND [param1 [param2 [paramN...]]]\33\7
  Every build macro starts with the //@ symbols and must placed at the
  beginning of a line. You can easily disable a macro by putting a / or a
  space in front of it.

\33\17//@EXE [name]\33\7
  Specifies that this module must be compiled to an exe file.
  The name is optional and must not containing the file extension.

\33\17//@DLL [name]\33\7
  Same as the above but for DLL and LIB output. A .def file is automatically
  generated, but you can also add custom DEF lines to it..

\33\17//@DEF <line>\33\7
  Creates a .def file and puts the line into it. The linker will use it later.

\33\17//@RES <fileName> [resourceName]\33\7
  Inserts a file into the project's .res file. If the resourceName is omitted,
  then it will use the fileName without the path. In the program these files
  can be accessed by this way -> res:\\resource1.dat.

\33\17//@RES <searchPath> [prefix]\33\7
  Inserts the resource files it finds using searchPath. It's recursive.
  Puts the optional prefix before the induvidual fileNames.

\33\17//@WIN\33\7
  Specifies that this is a Windows application. A DEF file for Windows will be created.
  The default run.bat will not include the 'pause' command at the end.

\33\17//@COMPILE [param1 [param2 [paramN...]]]\33\7
\33\17//@LINK [param1 [param2 [paramN...]]]\33\7
  Passes parameters to the LDC compiler and to the MSLINK linker.

\33\17//@RUN <command>\33\7
  After successful compile/link it puts these commands into a .bat file
  and runs it. Example:
    //@RUN $ 1234
    //@RUN @pause
  It will run the current executable using 1234 as a parameter and leave the
  console window on screen by using pause.
  Special characters:
    \"$\" is a wildcard for the target executable fileName without the extension.

Experimental:
\33\17//@RELEASE\33\7
  Adds -release -O -inline -boundscheck=off params to the COMPILE options

\33\17//@SINGLE\33\7
  Single pass compilation without caching. At the moment it's quite broken.
"
		/+Todo: Make this with Table based programming+/; 
	
	//////////////////////////////////////////////////////////////////////////////
	//Common structs                                                          //
	//////////////////////////////////////////////////////////////////////////////
	
	//Todo: editor: amikor higlightolja a szot, amin allok, akkor .-al egyutt is meg . nelkul is kene csinalni.
	//Todo: info/error logging kozpontositasa.
	
	struct EditorFile
	{
		align(1): 	 //Editor sends it's modified files using this struct
			char* fileName, source; 	 //align1 for Delphi compatibility
			int length; 
			DateTime dateTime; 
		//Note: 240827 Currently it isn't used: All edited files are saved in the editor before the build process.
	} 
	
	struct BuildSettings
	{
		mixin((
			(表([
				[q{/+Note: type+/},q{/+Note: decl+/},q{/+Note: char+/},q{/+Note: name+/},q{/+Note: description+/}],
				[q{bool},q{verbose},q{"v"},q{"verbose"},q{"Verbose output. Otherwise it will only display the errors."}],
				[q{bool},q{generateMap},q{"m"},q{"map"},q{"Generate map file."}],
				[q{bool},q{compileOnly},q{"c"},q{"compileOnly"},q{"Compile and link only, do not run."}],
				[q{bool},q{leaveObjs},q{"e"},q{"leaveObj"},q{"Leave behind .obj and .res files after compilation."}],
				[q{bool},q{rebuild},q{"r"},q{"rebuild"},q{"Rebuilds everything. Clears all caches."}],
				[q{string[]},q{importPaths},q{"I"},q{"include"},q{"Add include path to search for .d files."}],
				[q{string[]},q{compileArgs},q{"o"},q{"compileOpt"},q{"Pass extra compiler option."}],
				[q{string[]},q{linkArgs},q{"L"},q{"linkOpt"},q{"Pass extra linker option."}],
				[q{string[]},q{ldcLinkArgs},q{"y"},q{"ldcLinkOpt"},q{"Pass extra LDC linker option."}],
				[q{bool},q{killExe},q{"k"},q{"kill"},q{"Kill currently running executable before compile."}],
				[q{bool},q{collectTodos},q{"t"},q{"todo"},q{"Collect //Todo: and //Opt: comments."}],
				[q{bool},q{singleStepCompilation},q{"n"},q{"single"},q{"Single step compilation."}],
				[q{string},q{workPath},q{"w"},q{"workPath"},q{"Specify path for temp files. Default = Project's path."}],
				[q{bool},q{macroHelp},q{"a"},q{"macroHelp"},q{"Show info about the build-macros."}],
				[q{string},q{dideDbgEnv},q{"d"},q{"dideDbgEnv"},q{"DIDE can specify it's debug environment."}],
				[q{bool},q{xJson},q{"x"},q{"xJson"},q{"Generate X JSON files."}],
			]))
		) .GEN!q{
			(
				mixin(求map(q{a},q{rows},q{
					format!q{@("%s|%-14s= %s") %s %s; }
					(a[2][1..$-1], a[3][1..$-1], a[4][1..$-1], a[0], a[1])
				}))
			).join
		}); 
		
		//Todo: mi a faszert irja ki allandoan az 1 betus roviditest mindenhez???
		
		
		/// This is needed because the main source header can override the string arrays
		auto dup() const
		{
			BuildSettings res; 
			static foreach(fn; AllFieldNames!BuildSettings)
			{
				static if(is(typeof(mixin(fn))==const(string[])))
				{
					mixin("res.*=*.dup;".replace("*", fn)); //deep copy
				}else
				{ mixin("res.*=*;".replace("*", fn)); }
			}
			return res; 
		} 
		
		Path getWorkPath(lazy Path defaultPath)
		{
			auto p = Path(workPath); 
			if(!p)
			p = defaultPath; 
			enforce(!p || p.exists, "WorkPath doesn't exist " ~ p.text); 
			return p; 
		} 
	} 
	
	Path getWorkPath(string[] args, lazy Path defaultPath)
	{
		BuildSettings s; parseOptions(args, s, No.handleHelp); 
		return s.getWorkPath(defaultPath); 
	} 
	
	
	struct MSVCEnv
	{
		static
		{
			private
			{
				string[string] amd64, x86; 
				string current; 
				void get(ref string[string] e, string cmd)
				{
					auto r = executeShell(cmd, null, Config.suppressConsole).output; 
					if(r.empty)
					throw new Exception("Unable to run msvcEnv.bat. Please put LDC2/bin into the PATH."); 
					
					void add(string s)
					{
						auto i = s.indexOf("="); 
						if(i<0)
						return; 
						auto name = s[0..i], value = s[i+1..$]; 
						e[name] = value; 
					} 
					r.lineSplitter.each!add; 
				} 
				
				string[string] acquire(ref string[string] e, string arch)
				{
					if(e.empty)
					{
						static if(LDCVER>=128)
						{
							get(e, `set`); //msvcenv.bat is deprecated.
						}else
						{ get(e, `msvcenv `~arch~` && set`); }
					}
					return e; 
				} 
			} 
			
			string[string] getEnv(bool amd64_)
			{
				if(amd64_)
				return acquire(amd64, "amd64"); 
				else return acquire(x86  , "x86"  ); 
			} 
		} 
	} 
	
	//////////////////////////////////////////////////////////////////////////////
	//Hash calculation                                                        //
	//////////////////////////////////////////////////////////////////////////////
	
	string calcHash(string data, string data2 = "")
	{ return [(data~data2).xxh3_64].binToHex; } 
	
	//////////////////////////////////////////////////////////////////////////////
	//BuildSys Source File Cache                                              //
	//////////////////////////////////////////////////////////////////////////////
	
	struct SourceCache
	{
		private: 
			//first look inside this
			EditorFile[File] editorFiles; 
		
			//then look into the filesystem
			struct Content
		{
			File file; 
			string source_original; 
			DateTime dateTime; 
			string hash; 
			
			//processed things
			Parser parser; 
			bool processed; 
			
			void unProcess()
			{
				processed = false; 
				parser = new Parser(); 
			} 
			
			void process()
			{
				parser.tokenize(file.fullName, source_original); //it is needed to extract imported modules and such
				if(parser.wasError)
				WARN(parser.errorStr); 
			} 
		} 
			Content[File] cache; 
		
		public: 
			void reset()
		{ cache.clear; } 
		
			void dump()
		{
			foreach(ref ch; cache)
			writeln(ch.file); 
		} 
		
			void setEditorFiles(int count, EditorFile* data)
		{
			editorFiles.clear; 
			foreach(i; 0..count)
			{
				auto fn = File(to!string(data[i].fileName)); 
				editorFiles[fn] = data[i]; 
			}
			editorFiles.rehash; 
		} 
		
			Content* access(File	file)
		{
			//id	 cache	editor	what_to_do_with_cache
			//0	 0	0	load from file
			//1	 0	1	load from editor
			//2	 1	0	load from file if fileDate>cacheDate
			//3	 1	1	load from editor if editorDate>cacheDate
			
			auto ef = file in editorFiles; 
			auto ch = file in cache; 
			
			void refresh()
			{
				ch.unProcess; 
				if(ef)
				{
					//refresh from editor
					ch.dateTime = ef.dateTime; 
					ch.source_original = to!string(ef.source[0..ef.length]); 
				}
				else
				{
					//refresh from file
					ch.dateTime = file.modified; 
					ch.source_original = file.readStr(false); 
					//not mustexists because some files are nonexistent due to conditional imports
				}
				ch.hash = calcHash(ch.source_original); 
			} 
			
			if(!ch)
			{
				//not in cache
				cache[file] = Content(file); 
				ch = file in cache; //Opt: unoptimal
				refresh; 
			}
			else
			{
				//already in cache
				const dt = ((ef)?(ef.dateTime) :(file.modified)); 
				if(ch.dateTime<dt)
				refresh; 
			}
			
			//access now temporarily has automatic processing
			if(chkSet(ch.processed))
			ch.process; 
			
			return ch; 
		} 
		
	} 
	
	//Todo: editor: ha ilyen bazinagy commentbe irok, akkor a keretet ne csusztassa el a jobbszelen.
	//Todo: editor: ha ratehenkedek a //-re, es FOLYAMATOSAN nyomom, akkor egeszitse ki 80 char-ig! Ugyanez --ra meg =-re
	//Todo: editor: ha hosszan nyomom az r-t, akkor egeszitse ki return-ra!
	//Todo: editor: while, if utan rakjon()-t is leptesse a kurzort!
	
	//////////////////////////////////////////////////////////////////////////////
	//ModuleInfo class used by Builder                                        //
	//////////////////////////////////////////////////////////////////////////////
	
	class ModuleInfo
	{
		File file; //Todo: rename it to just 'file'
		string fileHash; 
		string moduleFullName; 
		File[] importedFiles; 
		string[] importedModuleNames; //Todo: it's fucking lame
		File[] deps; //dependencies
		string objHash; //calculated by hashing the dependencies and the compiler flags
		
		int sourceLines, sourceBytes; //stats
		
		this(SourceCache.Content* content)
		{
			file = content.file; 
			fileHash = content.hash; 
			sourceLines = content.parser.sourceLines; 
			sourceBytes = content.source_original.length.to!int; 
			
			moduleFullName = content.parser.getModuleFullName; 
			if(moduleFullName.empty)
			moduleFullName = file.nameWithoutExt; 
		} 
	} 
	
	//Todo: editor ha egy wordon allok, akkor a tobbi wordot case sensitiven keresse! Ez mar nem pascal!
	
	//Todo: editor: ha kijelolok egy szovegreszt es replacezni akarok akkor az autocomplete legordulobe csak az ott elofordulo szavakat rakja ki!
	//Todo: editorban ha typo error van es mar nincs rajta a cursor, akkor villogjon az az error, meg legyen egy gomb, ami javitja is az
	
	//////////////////////////////////////////////////////////////////////////////
	//Module Import Dependency Solver                                         //
	//////////////////////////////////////////////////////////////////////////////
	
	void resolveModuleImportDependencies(ref ModuleInfo[] modules)
	{
		/+
			Todo: Az addIfCan linearis kereses miatt ez igy szornyen lassu: 
			209 file-t 1.8sec alatt csinalt meg: 
			Kesobb majd meg kell csinalni binaris keresesre 
			vagy ami megjobb: NxN-es boolean matrixosra.
		+/
		
		//extend module imports to dependency lists
		foreach(ref m; modules)
		{
			m.deps = m.importedFiles.dup; 	//it's depending on it's imports...
			m.deps.addIfCan(m.file); 	//...and itself. (In D a module can import itself too)
		}
		
		bool any; 
		do
		{
			any = false; 
			foreach(ref m1; modules)
			foreach(ref m2; modules)
			{
				if(m1.deps.canFind(m2.file))
				{
					//when m1 deps m2
					foreach(fn; m2.deps)
					{
						any |= m1.deps.addIfCan(fn); 
						//add m2's deps to m1's import list if can. Don't add self
					}
				}
			}
		}
		while(any); 
		
		//sort it to make it consequent
		modules.each!q{a.deps.sort}; 
	} 
	
	void calculateObjHashes(ref ModuleInfo[] modules, string salt)
	{
		foreach(ref m; modules)
		{
			string s = salt~"|"~m.file.fullName; 
			foreach(dep; m.deps)
			{
				s ~= modules.filter!((m)=>(m.file==dep)).map!"a.file.fullName~a.fileHash".reduce!"a~b"; 
				//Opt: ez 2x olyan gyors lehetne filter nelkul
			}
			m.objHash = calcHash(s); 
			//contains hash of all the required filenames and fileContents plus a salt (compiler options)
		}
	} 
	
	struct SourceStats
	{
		int 	totalModules,
			totalLines,
			totalBytes; 
	} 
	
	
	class DMDMessage
	{
		mixin((
			(表([
				[q{/+Note: Type : ubyte+/},q{/+Note: Prefixes+/},q{/+Note: ShortCaption+/},q{/+Note: ColorCode+/},q{/+Note: Color+/},q{/+Note: Syntax+/}],
				[q{unknown},q{""},q{""},q{""},q{clBlack},q{skWhitespace}],
				[],
				[q{find},q{"Find: "},q{"Find"},q{""},q{clSilver},q{skFoundAct}],
				[],
				[q{error},q{"Error: "},q{"Err"},q{"\33\14"},q{clRed},q{skError}],
				[q{warning},q{"Warning: "},q{"Warn"},q{"\33\16"},q{clYellow},q{skWarning}],
				[q{deprecation},q{"Deprecation: "},q{"Depr"},q{"\33\13"},q{clAqua},q{skDeprecation}],
				[q{console},q{"Console: "},q{"Con"},q{""},q{clWhite},q{skConsole}],
				[],
				[q{todo},q{"Todo: "},q{"Todo"},q{"\33\11"},q{clBlue},q{skTodo}],
				[q{opt},q{"Opt: "},q{"Opt"},q{"\33\15"},q{clFuchsia},q{skOpt}],
				[q{bug},q{"Bug: "},q{"Bug"},q{"\33\6"},q{clOrange},q{skBug}],
				[],
				[q{//Order is important: it defines paint order
				}],
			]))
		) .GEN!q{GEN_enumTable}); 
		private enum exceptionPrefix = "Exception: "; //handled specuially
		
		CodeLocation location; 
		Type type; 
		string content, lineSource;  //Todo: lineSource is not needed, also sometimes it's bogus in LDC
		
		int count = 1; //occurences of this message in the multi-module build
		
		DMDMessage[] subMessages; //it's a tree
		
		protected uint hash_; @property hash() => hash_; 
		
		bool isException; //It's a special error message. It looks red/yellow in DIDE.
		
		this(
			CodeLocation location_, 
			string content_, 
			Type type_=Type.unknown
		) {
			location = location_; 
			content = content_; 
			type = type_; 
			detectType; 
			recalculateHash; 
		} 
		
		this(CodeLocation location_, Type type_, string content_)
		{ this(location_, content_, type_); } 
		
		this(DMDMessage m)
		{
			location = m.location; 
			content = m.content; 
			type = m.type; 
			lineSource = m.lineSource; 
			count = m.count; 
			hash_ = m.hash; 
			subMessages = (mixin(求map(q{s},q{m.subMessages},q{s.dup}))).array; 
		} 
		
		auto dup()
		{ return new DMDMessage(this); } 
		
		void recalculateHash()
		{
			ulong h = location.hashOf	(type.hashOf(content.hashOf)); 
			
			//make every console message different
			if(type==Type.console) h += (cast(ulong)((cast(void*)(this)))); 
			
			hash_ = (cast(uint)(h)) + (cast(uint)(h>>32)); 
		} 
		
		@property col() const
		{ return location.columnIdx; } @property line() const
		{ return location.lineIdx; } @property mixinLine() const
		{ return location.mixinLineIdx; } 
		
		@property typePrefix() const {
			return ((
				type==Type.error 
				&& isException
			)?("Exception: ") :(typePrefixes[type])); 
		} 
		
		bool opEquals(in DMDMessage b)const
		{
			return 	location 	== b.location 	&&
				type	== b.type 	&&
				content	== b.content; 
		}  int opCmp(const DMDMessage b) const
		{
			return 	cmp(location, b.location)
				.cmpChain(cmp(type, b.type))
				.cmpChain(cmp(content, b.content)); 
		} 
		bool isSupplemental() const
		{ return type==Type.unknown && content.startsWith(' '); } 
		
		bool isInstantiatedFrom() const
		{
			return 	isSupplemental && 	(
				content.stripLeft.startsWith("instantiated from here: ") 	||
				content.endsWith(" instantiations, -v to show) ...") 	||
				content.canFind(" recursive instantiations from here: ")
			); 
		} 
		
		///A persistend message is written in the code, it's not generated by a compiler.
		bool isPersistent() const
		{ with(Type) return !!type.among(todo, bug, opt); } 
		
		protected void detectType()
		{
			if(type!=Type.unknown) return; 
			
			bool doit(string prefix)
			{
				if(content.startsWith(prefix))
				{
					content = content[prefix.length .. $]; 
					return true; 
				}
				return false; 
			} 
			
			
			foreach(i, prefix; typePrefixes)
			if(i && doit(prefix))
			{ type = (cast(Type)(i));  return; }
			
			if(doit(exceptionPrefix))
			{
				/+Note: It's counted as an error, but looks different in DIDE+/
				type = Type.error; isException = true; return; 
			}
		} 
		string toString_internal(int level, bool enableColor, string indentStr) const
		{
			auto res = 	indentStr.replicate(level) ~
				withEndingColon(location.text) ~
				((enableColor)?(typeColorCode[type]):("")) ~ typePrefix ~
				((enableColor)?("\33\7"):("")) ~ content; 
			
			foreach(const ref sm; subMessages)
			res ~= "\n" ~ sm.toString_internal(level + sm.isInstantiatedFrom, enableColor, indentStr); 
			
			return res; 
		} 
		
		override string toString() const
		{ return toString_internal(0, true, "  "); } 
		
		private static
		{
			static withEndingColon(string s)
			{ return ((s=="")?(""):(s~": ")); }  static withStartingSpace(string s)
			{ return ((s=="")?(""):(" "~s)); } 
			
			int[] findQuotePairIndices(string s)
			{
				int[] indices; 
				foreach(i, char ch; s) if(ch=='`') indices ~= i.to!int; 
				
				if(indices.length & 1)
				{
					indices = indices.remove(max(indices.length.to!int - 2, 0)); 
					//it removes the second rightmost element. The leftmost and the rightmost are always valid.
				}
				return indices; 
			} 
			
			static string encapsulateCodeBlocks(string msg)
			{
				//locate all the code snippets inside `` and surround them with / +Code: ... + /
				const indices = findQuotePairIndices(msg); 
				auto opening = false; 
				foreach_reverse(i; indices)
				{
					const 	left = msg[0 .. i],
						right = msg[i+1 .. $]; 
					
					auto separ = opening ? "/+Code: " :"+/"; 
					if(left.endsWith(separ[1])) separ = ' ' ~ separ; //Not to produce "/+/" or "+/+"
					
					msg = left ~ separ ~ right; 
					opening = !opening; 
				}
				
				return msg; 
			} 
		} 
		
		
		private string[] allRecursiveContentLines() const
		{ return content ~ subMessages.map!((sm)=>(sm.allRecursiveContentLines)).join; } 
		
		private string sourceText_internal(int level=0) const
		{
			if(isPersistent/+Note: Todo/Bug/Opt messages are handled in a special fashion+/)
			{
				auto lines = allRecursiveContentLines; 
				
				lines[0] = typePrefix ~ lines[0]; 
				if(lines.length>1)
				{
					//Outdent all lines but the first.
					auto prefix = lines[1..$].map!(s=>s[0..$-s.stripLeft.length]).fold!commonPrefix; 
					foreach(ref s; lines[1..$]) s = s.withoutStarting(prefix); 
				}
				
				auto res = safeDCommentBody(lines.join('\n')) ~ " /+$DIDE_LOC "~location.text~"+/"; 
				
				return res; 
			}
			
			auto res = 	"\t".replicate(level) ~
				typePrefix ~
				encapsulateCodeBlocks(safeDCommentBody(content.stripLeft)) ~
				((location)?(" /+$DIDE_LOC "~location.text~"+/"):("")); 
			
			foreach(const ref sm; subMessages)
			res ~= "\n"~sm.sourceText_internal(level + sm.isInstantiatedFrom); 
			
			return res; 
		} 
		
		string sourceText() const
		{ return "/+\n" ~ sourceText_internal ~ "\n+/"; } 
		
		CodeLocation[] allLocations() const
		{
			CodeLocation[] res; 
			if(location) res ~= location; 
			foreach(const m; subMessages)
			res ~= m.allLocations; 
			return res; 
		} 
		
		string oneLineText() const
		{ return typePrefix~content.firstLine; } 
	} 
	
	
	struct DMDMessageDecoder
	{
		DMDMessage[] messages;  //globally accumulated messages for all modules
		
		//accumulators only for the last batch of std lines
		DMDMessage[] updatedMessages; 
		string[] pragmas; 
		
		
		//message filtering
		
		__gshared string[] messageFilters = [
			//"Warning: C preprocessor directive ", 
			"Deprecation: token string requires valid D tokens, not"
		]; 
		/+
			Todo: Put these filters in the main DIDE/settings!
			Counters would be usefull for every hits in the recent build.
		+/
		
		//internal state
		private
		{
			DMDMessage[uint] messageMap; 
			FileNameFixer fileNameFixer; 
			
			//Manage states for many sourcefiles.  While the message array is common.
			File _actSourceFile; 
			DMDMessage parentMessage, topLevelParentMessage; 
			
			DMDMessage[2][File] _actSourceFileState; 
		} 
		
		@property actSourceFile()
		{ return _actSourceFile; } 
		
		@property void actSourceFile(File f)
		{
			if(f==actSourceFile) return; 
			_actSourceFileState[_actSourceFile] = [parentMessage, topLevelParentMessage]; 
			
			_actSourceFile = f; //print("selecting source file: ", f); 
			
			if(auto a = _actSourceFile in _actSourceFileState)
			{ parentMessage = (*a)[0], topLevelParentMessage = (*a)[1]; }
			else
			{ parentMessage = null, topLevelParentMessage = null; }
		} 
		
		
		void createFileNameFixerIfNeeded()
		{ if(!fileNameFixer) fileNameFixer = new FileNameFixer; } 
		
		@property void defaultPath(Path path)
		{
			createFileNameFixerIfNeeded; 
			fileNameFixer.defaultPath = path; 
		} 
		
		string sourceText() const
		{ return messages.map!"a.sourceText".join("\n"); } 
		
		private static bool keepMessage(in DMDMessage m)
		{
			foreach(f; messageFilters)
			if(joiner(only(m.typePrefix, m.content)).startsWith(f))
			return false; 
			
			return true; 
		} 
		
		void addConsoleMessage(string[] lines)
		{
			if(lines.empty) return; 
			const s = lines.join('\n'); 
			if(s.strip=="") return; 
			messages ~= new DMDMessage(
				CodeLocation(actSourceFile.fullName), 
				DMDMessage.Type.console, 
				s
			); 
			updatedMessages ~= messages.back; 
		} 
		
		
		private enum rxDMDMessage = ctRegex!	`^((\w:\\)?[\w\\ \-.,]+.d)(-mixin-([0-9]+))?[^(]*\(([0-9]+),([0-9]+)\): (.*)`
			/+1:fn 2:drive       3       4            5      6       7+/
			/+drive:\ is optional.+/
			/+Todo: detect multiple mixin line indices!+/; 
		
		static int decodeColumnMarker(string s)
		{
			return ((
				s.endsWith('^') &&
				(
					s.length==1 || 
					s[0..$-1].all!"a.among(' ', '\t')"
				)
			)?((cast(int)(s.length))):(0)); 
		} 
		static bool isColumnMarker(string s)
		{ return decodeColumnMarker(s)>0; }; 
		
		
		static bool isDMDMessage(string s)
		{
			auto m = matchFirst(s, rxDMDMessage); 
			return !m.empty; 
		} 
		
		static bool isDMDMainMessage(string s)
		{
			auto m = matchFirst(s, rxDMDMessage); 
			if(!m.empty)
			{
				DMDMessage msg; 
				with(msg)
				{
					content = m[7]; detectType; 
					return type!=Type.unknown; 
				}
			}
			return false; 
		} 
		
		void processDMDOutput_partial(ref string[] lines, bool isFinal)
		{
			if(lines.empty) return; 
			
			if(isFinal)
			{
				processDMDOutput(lines); 
				lines = []; 
			}
			else
			{
				auto prevLines = lines; 
				
				while(lines.length)
				{
					const s = lines.back; 
					
					//from here, break if it's a valid ending
					if(isColumnMarker(s)) { break; }
					else if(isDMDMessage(s))
					{
						const dqCnt = s.count('`'); 
						if(
							!dqCnt
							/+has no quotation inside+/
						) break; 
						if(
							(dqCnt%2==0) && 
							(s.count('"')==0) && 
							(s.count('\'')==0)
							/+
								has even quotation, 
								but no other strings
							+/
						) break; 
					}
					lines.popBack; 
				}
				
				processDMDOutput(lines); 
				lines = prevLines[lines.length..$]; 
			}
		} 
		
		DMDMessage[] fetchUpdatedMessages()
		{
			//add remaining pragmas first to messages
			addConsoleMessage(pragmas.fetchAll); 
			
			//then fetch all new or modified messages
			return updatedMessages.fetchAll; 
		} 
		
		void processDMDOutput(string[] lines)
		{
			if(lines.empty) return; 
			
			createFileNameFixerIfNeeded; 
			
			static File decodeFileMarker(string line, FileNameFixer fileNameFixer)
			{
				enum rx = ctRegex!`^(\w:\\[\w\\ \-.,]+.d): COMPILER OUTPUT:$`; 
				auto m = matchFirst(line, rx); 
				return m.empty ? File.init : fileNameFixer(m[1]); 
				/+
					Todo: This file marker is kinda deprecated. 
					No need to collect all the messages from all modules into a single text.
				+/
			} 
			
			static DMDMessage fetchDMDMessage(ref string[] lines, FileNameFixer fileNameFixer)
			{
				DMDMessage decodeDMDMessage(string s)
				{
					auto m = matchFirst(s, rxDMDMessage); 
					if(!m.empty)
					{
						return new DMDMessage
							(
							CodeLocation(
								fileNameFixer(m[1]).fullName, 
								m[5].to!int.ifThrown(0), 
								m[6].to!int.ifThrown(0), 
								m[4].to!int.ifThrown(0)
							), 
							m[7]
						); 
					}
					
					return null; 
				} 
				
				auto msg = decodeDMDMessage(lines.front); 
				if(msg)
				{
					int endIdx; 
					foreach(i; 1 .. lines.length.to!int)
					{
						if(decodeColumnMarker(lines[i])==msg.col)
						{ endIdx = i; break; }
						if(decodeDMDMessage(lines[i])) break; 
						if(decodeFileMarker(lines[i], fileNameFixer)) break; 
					}
					
					if(endIdx>=2 /+Note: endIdx==1 is invalid, that's  the cited line.+/)
					{
						lines.fetchFront; //first line of a multiline message
						foreach(i; 1..endIdx-1)
						if(lines.length)
						msg.content ~= "\n"~lines.fetchFront; 
						msg.lineSource = lines.fetchFront; 
						lines.fetchFront; //skip the marker line
					}
					else
					{
						lines.fetchFront; //slingle line message
					}
				}
				return msg; 
			} 
			
			while(lines.length)
			{
				if(auto msg = fetchDMDMessage(lines, fileNameFixer))
				{
					auto chg = false; 
					if(msg.isSupplemental && parentMessage)
					{
						auto idx = parentMessage.subMessages.map!"a.hash".countUntil(msg.hash); 
						if(idx>=0)
						{
							parentMessage = parentMessage.subMessages[idx]; 
							parentMessage.count++; 
						}
						else
						{
							parentMessage.subMessages ~= msg; chg = true; /+new subMessage added+/
							parentMessage = msg; 
						}
					}
					else
					{
						if(msg.isSupplemental)
						WARN("No parent message for supplemental message:", msg); 
						
						if(keepMessage(msg))
						{
							const hash = msg.hash; 
							if(auto m = hash in messageMap)
							{
								(*m).count++; /+already exists+/
								parentMessage = *m; 
							}
							else
							{
								messages ~= msg; chg = true; /+new top level message added+/
								messageMap[hash] = msg; 
								parentMessage = msg; 
							}
							topLevelParentMessage = parentMessage; 
						}
					}
					if(chg && topLevelParentMessage && !updatedMessages.endsWith(topLevelParentMessage))
					{ updatedMessages ~= topLevelParentMessage; }
				}
				else
				{ pragmas ~= lines.fetchFront; }
			}
			
		} 
	} 
	
	DMDMessage[] decodeDMDMessages(string err, File file = File.init)
	{
		DMDMessageDecoder dec; 
		dec.actSourceFile = file; 
		dec.processDMDOutput(err.splitLines); 
		return dec.fetchUpdatedMessages; 
	} 
	
}
