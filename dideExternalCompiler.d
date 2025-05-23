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
			Code: ec.addInput(
				"glslc -S", 	//Note: specify the commandline
				q{
					@comp: 
					#version 430
					void main() {} 
				}, 	//Note: source code
				"testShader.comp", 1 	//Note: source file and line for error reports
			); 
		+/
		
		3. Open and read the result file. This operation will trigger the compilation.
			/+
			Code: const hash = ExternalCompiler.calcHash(args, src); 
			immutable(ubyte)[] data = File(`x:\temp\`~hash).read; 
		+/
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
				rootPath.wipe(false); 	((0x89535AA4136).檢((update間(_間)))); 
				auto ec = new ExternalCompiler(rootPath, Path(`z:\temp2`)); 	((0x90235AA4136).檢((update間(_間)))); 
				const 	args 	= "glslc -S", 
					src 	= q{
					@comp: 
					#version 430
					void main() {} 
				},
					hash	= src.hashOf(args.hashOf).to!string(26); 	
				ec.addInput(args, src, "testShader.comp", 1); 	((0xA0735AA4136).檢((update間(_間)))); 
				File(rootPath, hash).read.hexDump; 	((0xA5B35AA4136).檢((update間(_間)))); 
				File(rootPath, hash).read.hexDump/+cached+/; 	((0xAB935AA4136).檢((update間(_間)))); 
				ec.reset; 	
				File(rootPath, hash).read.hexDump/+can't access+/; 	((0xB2E35AA4136).檢((update間(_間)))); 
				ec.free; 	((0xB6835AA4136).檢((update間(_間)))); 
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
		{ string args, src, file; int line; } 
		
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
		
		CompilationResult doCompile(string hash)
		{
			synchronized(this) { if(auto a = hash in results) return *a; } 
			
			CompilationInput input; 
			enum maxInputWaitTime = 2*second; 
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
				input.args.wordAt(0).predSwitch
				(
					"glslc", 
					{
						auto r = compileGlslShader(
							input.args, input.src, Path(`z:\temp2`), 
							input.file, input.line
						); 
						res.status = r.status,  res.output = r.output,  res.binary = r.binary; 
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
				
				log(i"Projected file written. Length: $(size) bytes."); 
				
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
	
	void addInput(string args, string src, string file, int line)
	{
		const 	hash 	= calcHash(args, src),
			input 	= CompilationInput(args, src, file, line); 
		synchronized(this) { inputs[hash] = input; } 
		
		log(i"External code input added. Length: $(src.length) bytes."); 
	} 
	
	void reset()
	{
		synchronized(this) {
			foreach(key; results.byKey) PrjDeleteFile(context, key.toUTF16z); 
			results.clear; inputs.clear; 
		} 
	} 
	
	~this()
	{
		version(/+$DIDE_REGION Shutting down virtualization instance+/all)
		{
			reset; 
			PrjStopVirtualizing(context); context = null; 
			rootPath.wipe(false); 
		}
	} 
} 
auto compileGlslShader(string args /+Example: glslc -O0+/, string src, Path workPath, string baseFile="", int baseLine=1)
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
			
			const baseName = "shdr_"~src.hashOf(args.hashOf).to!string(26); 
			auto fn(string ext) => File(workPath, baseName~"."~ext); 
			foreach(sect; sections)
			{
				version(/+$DIDE_REGION Call GLSL compiler+/all)
				{
					const 	sectionrSrc 	= sect.lines.join('\n'),
						srcFile 	= fn(sect.section.text),
						dstFile 	= fn(sect.section.text~".out"); 
					srcFile.write(sectionrSrc); 
					import std.process: Config; 
					auto st = executeShell(
						args~" "~srcFile.quoted~" -o "~dstFile.quoted, null, 
						Config.suppressConsole, size_t.max, workPath.fullPath
					); 
					log(i"External compiler finished. Status =  $(st.status)."); 
					auto resultData = dstFile.read(false); 
					srcFile.remove(false); dstFile.remove(false); 
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
					const 	escapedFileName 	= srcFile.fullName.quoted[1..$-1],
						mask_noLine 	= escapedFileName~": *: *",
						mask	= escapedFileName~":*: *: *"; 
					foreach(i, line; st.output.splitLines)
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
							lineIdx += baseLine-1; 
							err = err.capitalize; 
							msg = msg.replace('\'', '`'); 
							auto bf = baseFile=="" ? srcFile.fullName : baseFile; 
							line = i"$(bf)($(lineIdx),1): $(err): $(msg)".text; 
						} 
						
						bool validMsgType(string s)
						=> !!s.among(
							"error", "warning", "note"
							/+Todo: 'note' can be the supplemental msg+/
						); 
						
						enum defaultLineIdx = 1; 
						
						if(line.isWild(mask) && validMsgType(wild[1]))
						reformat(wild.ints(0), wild[1], wild[2]); 
						else if(line.isWild(mask_noLine) && validMsgType(wild[0]))
						reformat(defaultLineIdx, wild[0], wild[1]); 
						else if(line.isWild("glslc: error: *"))
						reformat(defaultLineIdx, "error", "GLSLC: "~wild[0]); 
						else {
							reformat(defaultLineIdx, "Console", line); 
							/+
								Todo: do this but with supplemental messages:
								file(5,1): Console: blablabla
								file(5,1):         line2
							+/
						}
						
						finalOutput ~= line; 
					}
				}
				
				if(finalStatus) break; //stop early after the first failure
			}
		}
		
		//enforce(finalStatus==0, "Compilation failed"); 
		if(finalStatus==0) enforce(zip.totalEntries, "No binaries generated."); 
		
		finalBinary = (cast (immutable(ubyte)[])(((finalStatus==0)?(zip.build):("ERROR:"~finalStatus.text)))); 
		
		log(i"External code generated: $(finalBinary.length) bytes."); 
	}
	catch(Exception e)
	{
		finalStatus = 9999; finalBinary = []; 
		finalOutput ~= i"$(baseFile)($(baseLine),1): Error: GLSLC: $(e.simpleMsg.splitLines.enumerate.map!((a)=>(((a.index)?("       "):(""))~a.value)).join('\n'))".text; 
	}
	static struct CompilationResult {
		int status = int.min; 
		string output; 
		immutable(ubyte)[] binary; 
	} return CompilationResult(
		finalStatus, 
		finalOutput.join('\n'), 
		finalBinary
	); 
} 