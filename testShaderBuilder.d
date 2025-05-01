//@exe
//@debug
//@compile -J c:\d\projects\dide\

//Note: This is a test application for the automated, DIDE integrated shader compiler thing

import het, het.projectedfslib, testShaderSys; 

class ProjectedExternalCompiler
{
	const Path rootPath; 
	
	GUID instanceId; 
	PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT context; 
	
	struct CompilationResult
	{
		File file; 
		int status = int.min; 
		string output; 
		immutable(ubyte)[] binary; 
	} 
	
	CompilationResult[string] results; 
	
	CompilationResult onCompile(string name)
	{
		CompilationResult res; 
		res.file = File(rootPath, name); 
		//if(file.isExt("glsl"))
		print("Compiling", res.file); 
		sleep(1000); 
		print("Done"); 
		res.status = 0; 
		res.output = ""; 
		res.binary = (cast(immutable ubyte[])(
			`enum status = 0,
data = x"414243 444546
616263 31 32 33 34 35 36 37"; `.idup
		)); 
		return res; 
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
				this_ 	= (cast(ProjectedExternalCompiler)(callbackData.InstanceContext)),
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
				this_ 	= (cast(ProjectedExternalCompiler)(callbackData.InstanceContext)),
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
			const rootPath = Path(`z:\temp2\DIDE_projFS_`/+~now.raw.to!string(26)+/); 
			rootPath.wipe(false); 
			
			auto _間=init間; 
			auto pvd = new ProjectedExternalCompiler(rootPath); 
			foreach(i; 0..10000) sleep(1000); 
			pvd.free; 
			((0x141D7A242873).檢((update間(_間)))); 
			
			
			
			
			
			
		}
	); 
} 