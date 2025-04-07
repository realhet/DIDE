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
				list.keys.each!killAndWaitProcess; 
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
						/+
							/+Code: std.process.kill(pid);+/ <- Sometimes it gives "access denied".
							Must wait for the process to terminate, not just kill.
						+/
						killAndWaitProcess(pid); 
					}
					catch(Exception e)
					{ WARN(e.extendedMsg); }
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
	
	
}