//@exe
//@debug
//@compile -J c:\d\projects\dide\

//Note: This is a test application for the automated, DIDE integrated shader compiler thing

import het, het.projectedfslib, testShaderSys; 



auto compileGlslShader(string args /+Example: glslc -O0+/, string src, Path workPath, string baseFile="", int baseLine=1)
{
	string[] finalOutput; int finalStatus = 0; immutable(ubyte)[] finalBinary; 
	try {
		enum GlslSection
		{
			common,
			vert,	//Vertex Shader
			frag,	//Fragment Shader
			tesc,	//Tessellation Control (Hull) Shader
			tese,	//Tessellation Evaluation (Domain) Shader
			geom,	//Geometry Shader
			comp,	//Compute Shader
			mesh,	//Mesh Shader (Vulkan)
			task,	//Task Shader (Vulkan)
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
					auto resultData = dstFile.read(false); 
					srcFile.remove(false); dstFile.remove(false); 
				}
				
				version(/+$DIDE_REGION Store compiler status and binary+/all)
				{
					if(st.status==0 && resultData.length)
					{
						ArchiveMember am = new ArchiveMember; 
						am.name = "a."~sect.section.text~".spv"; 
						am.expandedData = resultData; 
						am.compressionMethod = CompressionMethod.deflate; 
						zip.addMember(am); 
					}
					
					if(st.status) finalStatus = st.status; 
				}
				
				version(/+$DIDE_REGION Process GLSL errors messages+/all)
				{
					const 	escapedFileName 	= srcFile.fullName.quoted[1..$-1],
						mask_noLine 	= escapedFileName~": ?*: *",
						mask	= escapedFileName[1..$-1]~":?*: ?*: *"; 
					auto lastRawLineIdx = long.min; 
					foreach(i, line; st.output.splitLines)
					if(line.strip!="")
					{
						if(line.endsWith(" error generated.")) continue; 
						
						void reformat(int lineIdx, string err, string msg)
						{
							lineIdx += baseLine-1; 
							err = err.capitalize; 
							msg = msg.replace('\'', '`'); 
							auto bf = baseFile=="" ? srcFile.fullName : baseFile; 
							line = i"$(bf)($(lineIdx),1): $(err): $(msg)".text; 
						} 
						
						enum defaultLineIdx = 1; 
						if(line.isWild(mask))
						reformat(wild.ints(0, 1), wild[1], wild[2]); 
						else if(line.isWild(mask_noLine))
						reformat(defaultLineIdx, wild[0], wild[1]); 
						else {
							if(lastRawLineIdx+1 != i)
							reformat(defaultLineIdx, "Error", line); 
							else line = "       "~line/+supplemental line+/; 
							lastRawLineIdx = i; 
						}
						
						finalOutput ~= line; 
					}
				}
				
				if(finalStatus) break; //stop early after the first failure
			}
		}
		
		enforce(zip.totalEntries, "No binaries generated."); 
		
		finalBinary = (cast (immutable(ubyte)[])(((finalStatus==0)?(zip.build):("ERROR:"~finalStatus.text)))); 
	}
	catch(Exception e)
	{
		finalStatus = 9999; finalBinary = []; 
		finalOutput ~= i"$(baseFile)($(baseLine),1) Error: compileGlslShader() exception: $(e.simpleMsg.splitLines.enumerate.map!((a)=>(((a.index)?("       "):(""))~a.value)).join('\n'))".text; 
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
} class ExternalCompiler
{
	const Path rootPath; 
	
	GUID instanceId; 
	PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT context; 
	
	struct CompilationInput
	{ string args, src, file; int line; } 
	
	struct CompilationResult
	{
		int status=int.min; 
		string output; 
		immutable(ubyte[]) binary; 
	} 
	
	CompilationInput[string] inputs; 
	CompilationResult[string] results; 
	
	void addInput(string args, string src, string file, int line)
	{
		const 	hash 	= src.hashOf(args.hashOf).to!string(26),
			input 	= CompilationInput(args, src, file, line); 
		synchronized(this) { inputs[hash] = input; } 
	} 
	
	CompilationResult onCompile(string hash)
	{
		CompilationInput input; 
		enum maxInputWaitTime = 2*second; 
		const tMax = now + maxInputWaitTime; 
		while(1) {
			synchronized(this) { input = inputs.get(hash, CompilationInput.init); } 
			if(input.args!="" || now>tMax) break; sleep(30); 
		}
		
		CompilationResult res; 
		if(input.args.wordAt(0)=="glslc")
		{
			auto r = compileGlslShader(
				input.args, input.src, Path(`z:\temp2`), 
				input.file, input.line
			); 
			res.status = r.status,  res.output = r.output,  res.binary = r.binary; 
		}
		else
		{
			res.status = 9999; const s = input.args.quoted('`'); 
			res.output = i"$(file)($(line),1): Error: Unable to call external compiler: `$(s)`".text; 
		}
		
		synchronized(this) { results[hash] = res; } 
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
				auto res = onCompile(name); 
				synchronized(this_) { results[name] = res; } 
				PRJ_PLACEHOLDER_INFO info; 
				info.FileBasicInfo = mixin(體!((PRJ_FILE_BASIC_INFO),q{FileSize : res.binary.length})); 
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
				
				const size = res.binary.length.to!uint; if(!size) return S_OK; 
				auto buff = PrjAllocateAlignedBuffer(ctx, size); 
				if(!buff) return HR_OUTOFMEMORY; 
				
				buff[0..size] = cast(ubyte[])res.binary; 
				auto hr = PrjWriteFileData(ctx, &callbackData.DataStreamId, buff, 0, size); 
				
				PrjFreeAlignedBuffer(buff); 
				
				return hr; 
			}
		} 
	} 
	
	this(Path rootPath_)
	{
		PrjInit(true); 
		
		version(/+$DIDE_REGION Create virtualization root+/all)
		{
			version(/+$DIDE_REGION 1. Create a directory to serve as the virtualization root.+/all)
			{
				rootPath = rootPath_; 
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
	
	~this()
	{
		version(/+$DIDE_REGION Shutting down virtualization instance+/all)
		{
			PrjStopVirtualizing(context); context = null; 
			rootPath.wipe(false); 
		}
	} 
} 

void main() {
	console(
		{
			auto res = compileGlslShader(
				"glslc", iq{
					#version 430
					
					@vert: 
					layout(binding = 0) uniform UniformBufferObject { mat4 mvp; } ubo; 
					
					layout(location = 0) in vec3 inPosition; 
					layout(location = 1) in vec3 inColor; 
					
					layout(location = 0) out vec3 fragColor; 
					
					void main()
					{
						gl_Position = ubo.mvp * vec4(inPosition, 1.0); 
						fragColor = inColor; 
					} 
					
					@frag: 
					layout(location = 0) in vec3 fragColor; 
					
					layout(location = 0) out vec4 outColor; 
					
					void main() { outColor = vec4(fragColor, 1.0); } 
				}.text, Path(`z:\temp2`), "shaderfile.glsl", 10000
			); 
			res.print; 
			File(`z:\temp2\out.zip`).write(res.binary); 
			
			const rootPath = Path(`z:\temp2\DIDE_projFS_`/+~now.raw.to!string(26)+/); 
			rootPath.wipe(false); 
			
			auto _間=init間; 
			auto pvd = new ExternalCompiler(rootPath); 
			foreach(i; 0..10000) sleep(1000); 
			pvd.free; 
			((0x2F757A242873).檢((update間(_間)))); 
			
			
			
		}
	); 
} 