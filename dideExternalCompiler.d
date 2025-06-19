module dideexternalcompiler; 

import het, het.projectedfslib; 

void log(A...)(A a) { print("\34\1"~a.text~"\34\0"); } 

class ExternalCompiler
{
	/+
		Note: /+H3: Usage:+/
		
		1. Create a path to use as the virtualization root.
			/+
			Code: const rootPath = Path(`x:\temp`); rootPath.wipe(false); 
			auto ec = new ExternalCompiler(rootPath); 
		+/
		
		2. Add an input compilation task.
			/+
			Code: const hash = ExternalCompiler.calcHash(args, src); 
			ec.addInput(
				"glslc -S", 	//Note: specify the commandline
				q{
					@comp: 
					#version 430
					void main() {} 
				}, 	//Note: source code
				hash, 	/+Note: This will be used as fileName and AA.key+/
				"testShader.comp", 1 	//Note: source file and line for error reports
			); 
		+/
		
		3. Open and read the result file. This operation will trigger the compilation.
			/+Code: immutable(ubyte)[] data = File(`x:\temp\`~hash).read; +/
			The input task (step 2) can be added later. It will wait up to 2 seconds when accessing the file.
		
		4. Check if there was an error.
			/+
			Structured: if(
				data.startsWith((cast(ubyte[])("ERROR:")))
				&& (cast(string)(data)).isWild("ERROR:*\n*")
			)
			{
				print("Error code: ", wild[0]); 
				print("Error message: ", wild[1]); 
			}
		+/
		
		5. The input and result caches and the virtualized path can be cleared calling /+Code: ec.reset;+/
		
		
		/+H3: Error codes:+/
		
			/+
			Structured: (表([
				[q{/+Note: Code+/},q{/+Note: Meaning+/}],
				[q{9999},q{"Exception while invoking the external compiler."}],
				[q{9998},q{"Unknown external compiler, based on the first identifier of 'args'."}],
				[q{9997},q{"Timed out waiting for 'input' to arrive. (2 seconds max)"}],
			]))
		+/
		
		/+H3: Supported external compilers:+/
		
			/+Code: glslc+/: 	Outputs compiled SPIR-V binaries packaged in a .zip archive.
				The resulting .zip archive contains individual shader files: /+Code: a.vert, a.frag, ...+/
		
		/+Link: https://forum.dlang.org/post/vxmpvpilwvgybppmkcgv@forum.dlang.org+/
	+/
	
	static void test()
	{
		console
		(
			{
				const rootPath = Path(`z:\temp2\ExtComp_test`); 	auto _間=init間; 
				rootPath.wipe(false); 	((0x8CB35AA4136).檢((update間(_間)))); 
				auto ec = new ExternalCompiler(rootPath, Path(`z:\temp2`)); 	((0x93835AA4136).檢((update間(_間)))); 
				const 	args 	= "glslc -S", 
					src 	= q{
					@comp: 
					#version 430
					void main() {} 
				},
					hash	= ExternalCompiler.calcHash(args, src); 	
				ec.addInput(args, src, hash, "testShader.comp", 1); 	((0xA4235AA4136).檢((update間(_間)))); 
				File(rootPath, hash).read.hexDump; 	((0xA9635AA4136).檢((update間(_間)))); 
				File(rootPath, hash).read.hexDump/+cached+/; 	((0xAF435AA4136).檢((update間(_間)))); 
				ec.reset; 	
				File(rootPath, hash).read.hexDump/+can't access+/; 	((0xB6935AA4136).檢((update間(_間)))); 
				ec.free; 	((0xBA335AA4136).檢((update間(_間)))); 
			}
		); 
	} 
	const Path rootPath, workPath; 
	
	static calcHash(string args, string src)
	=> src.hashOf(args.hashOf).to!string(26); 
	
	protected
	{
		GUID instanceId; 
		PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT context; 
		
		struct CompilationInput
		{
			string args, src, hash, file; int line; immutable(int)[] lineIdxMap; 
			
			bool opEquals(in CompilationInput b)const 
			=> args==b.args && src==b.src && equal(lineIdxMap, b.lineIdxMap); 
		} 
		
		struct CompilationResult
		{
			int status=int.min; string output; 
			immutable(ubyte)[] binary; 
			
			bool valid() const
			=> status==0; 	bool opCast(B : bool)() const
			=> valid; 
			immutable(ubyte[]) effectiveBinary() const /+It contains error message too+/
			=> ((status)?((cast(immutable(ubyte[]))("ERROR:"~status.text~"\n"~output))):(binary)); 
		} 
		
		CompilationInput[string] inputs; 
		CompilationResult[string] results; 
		//Todo: monitor the memory usage of these caches. Maybe too many versuons are stored of the same shaders...
		
		CompilationResult doCompile(string hash)
		{
			synchronized(this) { if(auto a = hash in results) return *a; } 
			
			CompilationInput input; 
			enum maxInputWaitTime = 30*second; 
			const tMax = now + maxInputWaitTime; auto timeout = false; 
			while(1) {
				synchronized(this) { input = inputs.get(hash, CompilationInput.init); } 
				if(input.args!="") break; 
				if(now>tMax) { timeout = true; break; }
				sleep(30); 
			}
			
			CompilationResult res; 
			void setErr(int status, string msg)
			{
				res.status = status; 
				res.output = i"$(input.file)($(input.line),1): $(msg)".text; 
			} 
			
			if(timeout)
			{ setErr(9997, "Error: External compiler input timeout: "~hash.quoted('`')); }
			else {
				const args = input.args.replace("\r\n", " ").strip; 
				args.wordAt(0).predSwitch
				(
					"glslc", 
					{
						auto r = compileGlslShader(
							args, input.src, input.hash, Path(`z:\temp2`), 
							input.file, input.line, input.lineIdxMap
						); 
						with(res) { status = r.status, output = r.output,  binary = r.binary; }
					},
					
					{ setErr(9998, "Error: Unknown external compiler: "~input.args.quoted('`')); }
				)(); 
			}
			synchronized(this) { results[hash] = res; } 
			
			return res; 
		} 
	} 
	protected static extern(Windows)
	{
		HRESULT MyStartEnumCallback	(
			const PRJ_CALLBACK_DATA* callbackData,
			const GUID* enumerationId
		) 
		{ return S_OK; } 
		
		HRESULT MyGetEnumCallback	(
			const PRJ_CALLBACK_DATA* callbackData,
			const GUID* enumerationId,
			const wchar* searchExpression,
			const PRJ_DIR_ENTRY_BUFFER_HANDLE dirEntryBufferHandle
		) 
		{ return S_OK; } 
		
		HRESULT MyEndEnumCallback	(
			const PRJ_CALLBACK_DATA* callbackData,
			const GUID* enumerationId
		) 
		{ return S_OK; } 
		
		HRESULT MyGetPlaceholderInfoCallback	(const PRJ_CALLBACK_DATA* callbackData) 
		{
			auto 	ctx 	= callbackData.NamespaceVirtualizationContext,
				this_ 	= (cast(ExternalCompiler)(callbackData.InstanceContext)),
				name 	= callbackData.FilePathName.text; 
			with(this_)
			{
				auto res = doCompile(name); 
				PRJ_PLACEHOLDER_INFO info; 
				info.FileBasicInfo = mixin(體!((PRJ_FILE_BASIC_INFO),q{FileSize : res.effectiveBinary.length})); 
				return PrjWritePlaceholderInfo(ctx, callbackData.FilePathName, &info, info.sizeof); 
			}
		} 
		
		HRESULT MyGetFileDataCallback	(
			const PRJ_CALLBACK_DATA* callbackData,
			const UINT64 byteOffset, const UINT32 length
		) 
		{
			auto 	ctx 	= callbackData.NamespaceVirtualizationContext,
				this_ 	= (cast(ExternalCompiler)(callbackData.InstanceContext)),
				name 	= callbackData.FilePathName.text; 
			with(this_)
			{
				CompilationResult* res; 
				synchronized(this_) { res = name in results; } 
				if(!res) return HR_ACCESS_DENIED; 
				
				const size = res.effectiveBinary.length.to!uint; if(!size) return S_OK; 
				auto buff = PrjAllocateAlignedBuffer(ctx, size); 
				if(!buff) return HR_OUTOFMEMORY; 
				
				buff[0..size] = (cast(ubyte[])(res.effectiveBinary)); 
				auto hr = PrjWriteFileData(ctx, &callbackData.DataStreamId, buff, 0, size); 
				
				log(i"Projected file written.  Hash: $(name)  Length: $(size) bytes."); 
				
				PrjFreeAlignedBuffer(buff); 
				return hr; 
			}
		} 
	} 
	
	this(Path rootPath_/+used by projfs+/, Path workPath_/+used by compilers+/)
	{
		rootPath 	= rootPath_,
		workPath 	= workPath_; 
		PrjInit(true); 
		
		version(/+$DIDE_REGION Create virtualization root+/all)
		{
			version(/+$DIDE_REGION 1. Create a directory to serve as the virtualization root.+/all)
			{
				enforce(rootPath, "Root path can't be null."); 
				enforce(!rootPath.exists, "Root path can't be an existing path.  It will be wiped after exit."); 
				rootPath.make(true); 
			}
			
			version(/+$DIDE_REGION 2. Create a virtualization instance ID.+/all)
			{ hrChk!CoCreateGuid(&instanceId); }
			
			version(/+$DIDE_REGION 3. Mark the new directory as the virtualization root+/all)
			{
				hrChk!PrjMarkDirectoryAsPlaceholder(
					rootPath.fullPath.toUTF16z, 
					null, null, &instanceId
				); 
			}
		}
		
		version(/+$DIDE_REGION Start virtualization instance+/all)
		{
			version(/+$DIDE_REGION 1. Set up the callback table.+/all)
			{
				auto callbackTable = 
				mixin(體!((PRJ_CALLBACKS),q{
					// Supply required callbacks.
					StartDirectoryEnumerationCallback 	: &MyStartEnumCallback,
					GetDirectoryEnumerationCallback	: &MyGetEnumCallback,
					EndDirectoryEnumerationCallback	: &MyEndEnumCallback,
					GetPlaceholderInfoCallback	: &MyGetPlaceholderInfoCallback,
					GetFileDataCallback	: &MyGetFileDataCallback,
					
					// The rest of the callbacks are optional.
					QueryFileNameCallback	: null,
					NotificationCallback	: null,
					CancelCommandCallback 	: null,
				})); 
			}
			
			version(/+$DIDE_REGION 2. Start the instance.+/all)
			{
				PrjStartVirtualizing(
					rootPath.fullPath.toUTF16z,
					&callbackTable, (cast(void*)(this)), null, context
				); 
			}
		}
	} 
	
	//Link: file:///C:/dl/windows-win32-projfs.pdf
	
	void addInput(
		string args, string src, string hash, 
		string file, int line, immutable(int)[] lineIdxMap = []
	)
	{
		const input = CompilationInput(args, src, hash, file, line, lineIdxMap); 
		auto inCache = false; 
		synchronized(this)
		{
			inputs.update
			(
				hash, (() =>(input)), 
				((ref CompilationInput existing) {
					enforce(
						existing.args==input.args && existing.src==input.src, 
						/+compiler args and sources must be identical at least!!!+/
						i"Hash collision (possible mismatched external code): 
	existing:$(existing.toJson)
	!= input:$(input.toJson)".text
					); 
					existing = input; //overwrite it.  Maybe just the source line was changed.
					inCache = true; 
				})
			); 
		} 
		log(
			i"External code input added. Hash: $(hash) 
  Length: $(src.length) bytes.  Found in cache: $(inCache)."
		); 
	} 
	
	protected void _reset_noSynch()
	{
		foreach(key; chain(inputs.keys, results.keys))
		PrjDeleteFile(context, key.toUTF16z); 
		results.clear; inputs.clear; 
	} 
	
	void reset()
	{ synchronized(this) _reset_noSynch; } 
	
	import didebase : ShutdownLog; 
	
	void shutDown()
	{
		ShutdownLog(11); 
		if(context)
		{
			scope(exit) context = null; 
			ShutdownLog(12); 
			version(all/++/)
			{
				reset; 
				/+
					Bug: the random crash is here:
					didebase.d(18,1): ShutdownLog 1
					didebase.d(18,1): ShutdownLog 2
					didebase.d(18,1): ShutdownLog 3
					didebase.d(18,1): ShutdownLog 11
					didebase.d(18,1): ShutdownLog 12
					An exception was thrown while finalizing an instance of didebuilder.Builder
					Press Enter to continue...
				+/
			}
			ShutdownLog(13); 
			PrjStopVirtualizing(context); 
			ShutdownLog(14); 
			rootPath.wipe(false); 
			ShutdownLog(15); 
		}
	} 
	
	~this()
	{
		ShutdownLog(16); 
		shutDown; 
		ShutdownLog(17); 
	} 
} 
private auto myExecuteShell(string commandLine, string workDir = "")
	@trusted //Todo: @safe
{
	import std.process; 
	auto p = pipeShell(
		commandLine, mixin(幟!((Redirect),q{stdout | stderrToStdout})), 
		null, mixin(幟!((Config),q{suppressConsole})), workDir
	); 
	
	version(/+$DIDE_REGION Start listening to stdOut and stdErr+/all)
	{
		auto lines = new SSQueue!string; 
		auto outThread = new Thread(
			{
				foreach(
					a; 	p.stdout.byLineCopy
						.map!((a)=>(a.withoutEnding('\r')))
				)
				{ lines.put(a); }
			}
		); 
		outThread.start; scope(exit) outThread.join; 
	}
	
	auto status = wait(p.pid); 
	
	return Tuple!(int, "status", string[], "outputLines")(status, lines.fetchAll); 
} 

auto compileGlslShader(string args /+Example: glslc -O0+/, string src, string hash, Path workPath, string baseFile="", int baseLine=1, in int[] lineIdxMap=[])
{
	string[] finalOutput; int finalStatus = 0; immutable(ubyte)[] finalBinary; 
	try {
		enum GlslSection
		{
			common,	//reserved for hetlib / unified shader code
			
			comp,	//Compute Shader
			
			vert,	//Vertex Shader
			tesc,	//Tessellation Control (Hull) Shader
			tese,	//Tessellation Evaluation (Domain) Shader
			geom,	//Geometry Shader
			frag,	//Fragment Shader
			
			task,	//Task Shader (Vulkan)
			mesh,	//Mesh Shader (Vulkan)
			
			rgen,	//Ray Generation Shader (Ray Tracing)
			rint,	//Ray Intersection Shader (Ray Tracing)
			rahit,	//Ray Any-Hit Shader (Ray Tracing)
			rchit,	//Ray Closest-Hit Shader (Ray Tracing)
			rmiss,	//Ray Miss Shader (Ray Tracing)
			rcall	//Ray Callable Shader (Ray Tracing)
		} 
		static immutable glslSectionMap = assocArray(
			[__traits(allMembers, GlslSection)], 
			true.repeat
		); 
		static isGlslSection(string s) 
		=> s.startsWith('@') && s.endsWith(":") && (s[1..$-1] in glslSectionMap); 
		
		struct Section { GlslSection section; string[] lines; } 
		
		version(/+$DIDE_REGION Preprocess source and split to lines+/all)
		{
			auto lines = src.replace('\v', ' ').splitLines; 
			outdentLines(lines); 
		}
		
		version(/+$DIDE_REGION Discover sections+/all)
		{
			Section[] sections; 
			foreach(line; lines)
			{
				const stripped = line.strip; 
				if(isGlslSection(stripped))
				{
					const s = stripped[1..$-1].to!GlslSection; 
					if(s && !sections.map!"a.section".canFind(s)) sections ~= Section(s); 
				}
			}
		}
		
		version(/+$DIDE_REGION Collect lines of all sections+/all)
		{
			{
				auto actSection = GlslSection.common; 
				foreach(line; lines)
				{
					const stripped = line.strip; 
					if(isGlslSection(stripped))
					{
						actSection = stripped[1..$-1].to!GlslSection; 
						line = "/*"~stripped~"*/"; //hide section declaration inside a comment
					}
					foreach(ref dst; sections)
					dst.lines ~= ((
						actSection==GlslSection.common || 
						actSection==dst.section
					)?(line):("")); 
				}
				
				static if((常!(bool)(0)))
				{
					foreach(s; sections)
					{
						print("-------------", s.section, "----------------"); 
						foreach(i, line; s.lines) print(format!"%5d:%s"(i, line)); print; 
					}
				}
			}
		}
		version(/+$DIDE_REGION Compile all sections+/all)
		{
			import std.zip; 
			ZipArchive zip = new ZipArchive; 
			
			log(i"Started compiling external code. Source length: $(src.length) bytes."); 
			
			const baseName = "shdr_"~hash; 
			auto fn(string ext) => File(workPath, baseName~"."~ext); 
			foreach(sect; sections)
			{
				version(/+$DIDE_REGION Call GLSL compiler+/all)
				{
					const 	sectionrSrc 	= sect.lines.join('\n'),
						srcFile 	= fn(sect.section.text),
						dstFile 	= fn(sect.section.text~".out"); 
					srcFile.write(sectionrSrc); 
					
					const cmdLine = i`$(args) $(srcFile.cmdArg) -o $(dstFile.cmdArg)`.text; 
					log("executeShell() starting: "~cmdLine); 
					scope exit() { dstFile.remove(false); srcFile.remove(false); } 
					auto st = myExecuteShell(cmdLine, workDir: workPath.fullPath); 
					log(i"executeShell() finished. Status =  $(st.status)."); 
					
					auto resultData = dstFile.read(false); 
				}
				
				version(/+$DIDE_REGION Store compiler status and binary+/all)
				{
					if(st.status==0 && resultData.length)
					{
						ArchiveMember am = new ArchiveMember; 
						am.name = sect.section.text~".spv"; 
						am.expandedData = resultData; 
						am.compressionMethod = CompressionMethod.deflate; 
						zip.addMember(am); 
					}
					
					if(st.status) finalStatus = st.status; 
				}
				
				//Todo: vertical tab support in q{} iq{ } /++/ /**/
				
				
				version(/+$DIDE_REGION Process GLSL errors messages+/all)
				{
					const 	mask_noLine 	= srcFile.fullName~": *: *",
						mask	= srcFile.fullName~":*: *: *"; 
					size_t lastConsoleIdx; 
					foreach(i, line; st.outputLines)
					if(line.strip!="")
					{
						if(
							line.endsWith(
								" error generated.", 
								" errors generated."
							)
						) continue; 
						
						void reformat(int lineIdx, string err, string msg)
						{
							lineIdx = max(lineIdx-1, 1); /+remove first extra newLine+/
							if(lineIdx.inRange(lineIdxMap))	lineIdx = lineIdxMap[lineIdx]; 
							else	lineIdx += baseLine/+fallback+/; 
							err = err.capitalize; 
							msg = msg.replace('\'', '`'); 
							auto bf = baseFile=="" ? srcFile.fullName : baseFile; 
							line = i"$(bf)($(lineIdx),1): $(err) $(msg)".text; 
						} 
						
						bool validMsgType(string s)
						=> !!s.among(
							"error", "warning", "note"
							/+Todo: 'note' can be the supplemental msg+/
						); 
						
						enum defaultLineIdx = 1; 
						
						if(line.isWild(mask) && validMsgType(wild[1]))
						reformat(wild.ints(0), wild[1]~':', wild[2]); 
						else if(line.isWild(mask_noLine) && validMsgType(wild[0]))
						reformat(defaultLineIdx, wild[0]~':', wild[1]); 
						else if(line.isWild("glslc: error: *"))
						reformat(defaultLineIdx, "Error:", "GLSLC: "~wild[0]); 
						else {
							reformat(defaultLineIdx, ((lastConsoleIdx+1==i) ?("       "):("Console:")), line); 
							lastConsoleIdx = i; 
						}
						
						finalOutput ~= line; 
					}
				}
				
				if(finalStatus) break; //stop early after the first failure
			}
		}
		
		//enforce(finalStatus==0, "Compilation failed"); 
		if(finalStatus==0) enforce(zip.totalEntries, "No binaries generated."); 
		
		finalBinary = (cast(immutable(ubyte)[])(((finalStatus==0)?(zip.build) :("ERROR:"~finalStatus.text)))); 
		
		log(i"External code generated: Source length: $(src.length), binary length: $(finalBinary.length) bytes."); 
	}
	catch(Exception e)
	{
		log(i"External code exception: Source length: $(src.length), \34\4 exc: $(e.simpleMsg.quoted)\34\0"); 
		finalStatus = 9999; finalBinary = (cast(immutable(ubyte)[])("ERROR:"~finalStatus.text)); 
		foreach(i, s; e.simpleMsg.splitLines)
		{ finalOutput ~= i"$(baseFile)($(baseLine),1): $(((i==0)?("Error: GLSLC: "):("       ")))$(s)".text; }
	}
	
	static struct CompilationResult {
		int status = int.min; 
		string output; 
		immutable(ubyte)[] binary; 
	} return CompilationResult(
		finalStatus, 
		finalOutput.map!q{a~'\n'}.join, 
		finalBinary
	); 
} 