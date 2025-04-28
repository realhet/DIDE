module projectedfslib; 
import het; 


private alias PCWSTR = const wchar*, LPCWSTR = const wchar*, 
INT32 = int, UINT32 = uint, UINT8 = ubyte, BOOLEAN = bool, 
INT64 = long, LARGE_INTEGER = long; 


private
{
	class Loader
	{
		HANDLE lib; 
		bool success; 
		this()
		{
			lib = loadLibrary("projectedfslib.dll", false); 
			if(lib)
			{
				static foreach(name; __traits(allMembers, mixin(__MODULE__)))
				{
					{
						alias member = __traits(getMember, mixin(__MODULE__), name); 
						static if(__traits(compiles, typeof(member)))
						static if(typeof(member).stringof.startsWith("extern"))
						lib.getProcAddress(name, member, true); 
					}
				}
				success = true; 
			}
		} 
	} 
	
	alias loader = Singleton!Loader; 
} 

bool PrjInit(bool required=false)
{
	auto res = loader.success; 
	if(required) res.enforce("Unable to load projectedfslib.dll."); 
	return res; 
} 

version(/+$DIDE_REGION Common structures+/all)
{
	enum PRJ_NOTIFY_TYPES
	{
		PRJ_NOTIFY_NONE	= 0x00000000,
		PRJ_NOTIFY_SUPPRESS_NOTIFICATIONS	= 0x00000001,
		PRJ_NOTIFY_FILE_OPENED	= 0x00000002,
		PRJ_NOTIFY_NEW_FILE_CREATED	= 0x00000004,
		PRJ_NOTIFY_FILE_OVERWRITTEN	= 0x00000008,
		PRJ_NOTIFY_PRE_DELETE	= 0x00000010,
		PRJ_NOTIFY_PRE_RENAME	= 0x00000020,
		PRJ_NOTIFY_PRE_SET_HARDLINK	= 0x00000040,
		PRJ_NOTIFY_FILE_RENAMED	= 0x00000080,
		PRJ_NOTIFY_HARDLINK_CREATED	= 0x00000100,
		PRJ_NOTIFY_FILE_HANDLE_CLOSED_NO_MODIFICATION 	= 0x00000200,
		PRJ_NOTIFY_FILE_HANDLE_CLOSED_FILE_MODIFIED	= 0x00000400,
		PRJ_NOTIFY_FILE_HANDLE_CLOSED_FILE_DELETED	= 0x00000800,
		PRJ_NOTIFY_FILE_PRE_CONVERT_TO_FULL	= 0x00001000,
		PRJ_NOTIFY_USE_EXISTING_MASK	= 0xFFFFFFFF
	} 
	
	//DEFINE_ENUM_FLAG_OPERATORS(PRJ_NOTIFY_TYPES); 
	
	// This enum shares the same value space as PRJ_NOTIFY_TYPES, but
	// these values are not bit flags.
	enum PRJ_NOTIFICATION
	{
		PRJ_NOTIFICATION_FILE_OPENED	= 0x00000002,
		PRJ_NOTIFICATION_NEW_FILE_CREATED	= 0x00000004,
		PRJ_NOTIFICATION_FILE_OVERWRITTEN	= 0x00000008,
		PRJ_NOTIFICATION_PRE_DELETE	= 0x00000010,
		PRJ_NOTIFICATION_PRE_RENAME	= 0x00000020,
		PRJ_NOTIFICATION_PRE_SET_HARDLINK	= 0x00000040,
		PRJ_NOTIFICATION_FILE_RENAMED	= 0x00000080,
		PRJ_NOTIFICATION_HARDLINK_CREATED	= 0x00000100,
		PRJ_NOTIFICATION_FILE_HANDLE_CLOSED_NO_MODIFICATION 	= 0x00000200,
		PRJ_NOTIFICATION_FILE_HANDLE_CLOSED_FILE_MODIFIED	= 0x00000400,
		PRJ_NOTIFICATION_FILE_HANDLE_CLOSED_FILE_DELETED	= 0x00000800,
		PRJ_NOTIFICATION_FILE_PRE_CONVERT_TO_FULL	= 0x00001000,
	} 
	
	alias PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT = HANDLE; 
	alias PRJ_DIR_ENTRY_BUFFER_HANDLE = HANDLE; 
}

version(/+$DIDE_REGION Virtualization instance APIs+/all)
{
	struct PRJ_NOTIFICATION_MAPPING
	{
		PRJ_NOTIFY_TYPES NotificationBitMask; 
		PCWSTR NotificationRoot; 
	} 
	
	enum PRJ_STARTVIRTUALIZING_FLAGS
	{
		PRJ_FLAG_NONE	= 0x00000000,
		PRJ_FLAG_USE_NEGATIVE_PATH_CACHE 	= 0x00000001
	} 
	
	struct PRJ_STARTVIRTUALIZING_OPTIONS
	{
		PRJ_STARTVIRTUALIZING_FLAGS Flags; 
		UINT32 PoolThreadCount; 
		UINT32 ConcurrentThreadCount; 
		PRJ_NOTIFICATION_MAPPING* NotificationMappings; 
		UINT32 NotificationMappingsCount; 
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PCWSTR virtualizationRootPath,
		const PRJ_CALLBACKS* callbacks,
		const void* instanceContext,
		const PRJ_STARTVIRTUALIZING_OPTIONS* options,
		out PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT  namespaceVirtualizationContext
	) PrjStartVirtualizing; 
	
	__gshared extern(Windows) void function
		(const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext) PrjStopVirtualizing; 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		out UINT32 totalEntryNumber
	) PrjClearNegativePathCache; 
	
	struct PRJ_VIRTUALIZATION_INSTANCE_INFO
	{
		GUID InstanceID; 
		UINT32 WriteAlignment; 
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		out PRJ_VIRTUALIZATION_INSTANCE_INFO virtualizationInstanceInfo
	) PrjGetVirtualizationInstanceInfo; 
}

version(/+$DIDE_REGION Placeholder and File APIs+/all)
{
	enum PRJ_PLACEHOLDER_ID_LENGTH = 128; 
	
	struct PRJ_PLACEHOLDER_VERSION_INFO
	{
		UINT8[PRJ_PLACEHOLDER_ID_LENGTH] ProviderID; 
		UINT8[PRJ_PLACEHOLDER_ID_LENGTH] ContentID; 
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PCWSTR rootPathName,
		const PCWSTR targetPathName,
		const PRJ_PLACEHOLDER_VERSION_INFO* versionInfo,
		const GUID* virtualizationInstanceID
	) PrjMarkDirectoryAsPlaceholder; 
	
	struct PRJ_FILE_BASIC_INFO
	{
		BOOLEAN IsDirectory; 
		INT64 FileSize; 
		LARGE_INTEGER CreationTime; 
		LARGE_INTEGER LastAccessTime; 
		LARGE_INTEGER LastWriteTime; 
		LARGE_INTEGER ChangeTime; 
		UINT32 FileAttributes; 
	} 
	
	struct PRJ_PLACEHOLDER_INFO
	{
		PRJ_FILE_BASIC_INFO FileBasicInfo; 
		
		struct TEaInformation
		{
			UINT32 EaBufferSize; 
			UINT32 OffsetToFirstEa; 
		} TEaInformation EaInformation; 
		
		struct TSecurityInformation
		{
			UINT32 SecurityBufferSize; 
			UINT32 OffsetToSecurityDescriptor; 
		} TSecurityInformation SecurityInformation; 
		
		struct TStreamsInformation
		{
			UINT32 StreamsInfoBufferSize; 
			UINT32 OffsetToFirstStreamInfo; 
		} TStreamsInformation StreamsInformation; 
		
		PRJ_PLACEHOLDER_VERSION_INFO VersionInfo; 
		UINT8[1] VariableData; 
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		const PCWSTR destinationFileName,
		const PRJ_PLACEHOLDER_INFO* placeholderInfo,
		const UINT32 placeholderInfoSize
	) PrjWritePlaceholderInfo; 
	
	enum PRJ_UPDATE_TYPES
	{
		PRJ_UPDATE_NONE	= 0x00000000,
		PRJ_UPDATE_ALLOW_DIRTY_METADATA	= 0x00000001,
		PRJ_UPDATE_ALLOW_DIRTY_DATA	= 0x00000002,
		PRJ_UPDATE_ALLOW_TOMBSTONE	= 0x00000004,
		PRJ_UPDATE_RESERVED1	= 0x00000008,
		PRJ_UPDATE_RESERVED2	= 0x00000010,
		PRJ_UPDATE_ALLOW_READ_ONLY	= 0x00000020,
		PRJ_UPDATE_MAX_VAL = (PRJ_UPDATE_ALLOW_READ_ONLY << 1)
	} 
	
	enum PRJ_UPDATE_FAILURE_CAUSES
	{
		PRJ_UPDATE_FAILURE_CAUSE_NONE	= 0x00000000,
		PRJ_UPDATE_FAILURE_CAUSE_DIRTY_METADATA	= 0x00000001,
		PRJ_UPDATE_FAILURE_CAUSE_DIRTY_DATA	= 0x00000002,
		PRJ_UPDATE_FAILURE_CAUSE_TOMBSTONE	= 0x00000004,
		PRJ_UPDATE_FAILURE_CAUSE_READ_ONLY	= 0x00000008,
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		const PCWSTR destinationFileName,
		const PRJ_PLACEHOLDER_INFO* placeholderInfo,
		const UINT32 placeholderInfoSize,
		const PRJ_UPDATE_TYPES updateFlags,
		out PRJ_UPDATE_FAILURE_CAUSES failureReason
	) PrjUpdateFileIfNeeded; 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		const PCWSTR destinationFileName,
		const PRJ_UPDATE_TYPES updateFlags,
		out PRJ_UPDATE_FAILURE_CAUSES failureReason
	) PrjDeleteFile; 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		const GUID* dataStreamId,
		const void* buffer,
		const UINT64 byteOffset,
		const UINT32 length
	) PrjWriteFileData; 
	
	enum PRJ_FILE_STATE
	{
		PRJ_FILE_STATE_PLACEHOLDER	= 0x00000001,
		PRJ_FILE_STATE_HYDRATED_PLACEHOLDER	= 0x00000002,
		PRJ_FILE_STATE_DIRTY_PLACEHOLDER	= 0x00000004,
		PRJ_FILE_STATE_FULL	= 0x00000008,
		PRJ_FILE_STATE_TOMBSTONE	= 0x00000010,
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PCWSTR destinationFileName,
		out PRJ_FILE_STATE fileState
	) PrjGetOnDiskFileState; 
	
	__gshared extern(Windows) void* function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		const size_t size
	) PrjAllocateAlignedBuffer; 
	
	__gshared extern(Windows) void function
		(const void* buffer) PrjFreeAlignedBuffer; 
}

version(/+$DIDE_REGION Callback support+/all)
{
	enum PRJ_CALLBACK_DATA_FLAGS
	{
		PRJ_CB_DATA_FLAG_ENUM_RESTART_SCAN	= 0x00000001,
		PRJ_CB_DATA_FLAG_ENUM_RETURN_SINGLE_ENTRY 	= 0x00000002
	} 
	
	struct PRJ_CALLBACK_DATA
	{
		UINT32 Size; 
		PRJ_CALLBACK_DATA_FLAGS Flags; 
		PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT NamespaceVirtualizationContext; 
		INT32 CommandId; 
		GUID FileId; 
		GUID DataStreamId; 
		PCWSTR FilePathName; 
		PRJ_PLACEHOLDER_VERSION_INFO* VersionInfo; 
		UINT32 TriggeringProcessId; 
		PCWSTR TriggeringProcessImageFileName; 
		void* InstanceContext; 
	} 
	
	alias PRJ_START_DIRECTORY_ENUMERATION_CB = extern(Windows) HRESULT function
		(
		const PRJ_CALLBACK_DATA* callbackData,
		const GUID* enumerationId
	); 
	
	alias PRJ_GET_DIRECTORY_ENUMERATION_CB = extern(Windows) HRESULT function
		(
		const PRJ_CALLBACK_DATA* callbackData,
		const GUID* enumerationId,
		const PCWSTR searchExpression,
		const PRJ_DIR_ENTRY_BUFFER_HANDLE dirEntryBufferHandle
	); 
	
	alias PRJ_END_DIRECTORY_ENUMERATION_CB = extern(Windows) HRESULT function
		(
		const PRJ_CALLBACK_DATA* callbackData,
		const GUID* enumerationId
	); 
	
	alias PRJ_GET_PLACEHOLDER_INFO_CB = extern(Windows) HRESULT function
		(const PRJ_CALLBACK_DATA* callbackData); 
	
	alias PRJ_GET_FILE_DATA_CB = extern(Windows) HRESULT function
		(
		const PRJ_CALLBACK_DATA* callbackData,
		const UINT64 byteOffset,
		const UINT32 length
	); 
	
	alias PRJ_QUERY_FILE_NAME_CB = extern(Windows) HRESULT function
		(const PRJ_CALLBACK_DATA* callbackData); 
	
	union PRJ_NOTIFICATION_PARAMETERS
	{
		struct TPostCreate { PRJ_NOTIFY_TYPES NotificationMask; } 
		TPostCreate PostCreate; 
		
		struct TFileRenamed { PRJ_NOTIFY_TYPES NotificationMask; } 
		TFileRenamed FileRenamed; 
		
		struct TFileDeletedOnHandleClose { BOOLEAN IsFileModified; } 
		TFileDeletedOnHandleClose FileDeletedOnHandleClose; 
	} 
	
	alias PRJ_NOTIFICATION_CB = extern(Windows) HRESULT function
		(
		const PRJ_CALLBACK_DATA* callbackData,
		const BOOLEAN isDirectory,
		const PRJ_NOTIFICATION notification,
		const PCWSTR destinationFileName,
		PRJ_NOTIFICATION_PARAMETERS* operationParameters
	); 
	
	alias PRJ_CANCEL_COMMAND_CB = extern(Windows) void function
	(const PRJ_CALLBACK_DATA* callbackData); 
	
	struct PRJ_CALLBACKS 
	{
		PRJ_START_DIRECTORY_ENUMERATION_CB* StartDirectoryEnumerationCallback; 
		PRJ_END_DIRECTORY_ENUMERATION_CB* EndDirectoryEnumerationCallback; 
		PRJ_GET_DIRECTORY_ENUMERATION_CB* GetDirectoryEnumerationCallback; 
		PRJ_GET_PLACEHOLDER_INFO_CB* GetPlaceholderInfoCallback; 
		PRJ_GET_FILE_DATA_CB* GetFileDataCallback; 
		
		PRJ_QUERY_FILE_NAME_CB* QueryFileNameCallback; 
		PRJ_NOTIFICATION_CB* NotificationCallback; 
		PRJ_CANCEL_COMMAND_CB* CancelCommandCallback; 
	} 
	
	enum PRJ_COMPLETE_COMMAND_TYPE
	{
		PRJ_COMPLETE_COMMAND_TYPE_NOTIFICATION = 1,
		PRJ_COMPLETE_COMMAND_TYPE_ENUMERATION = 2
	} 
	
	struct PRJ_COMPLETE_COMMAND_EXTENDED_PARAMETERS
	{
		PRJ_COMPLETE_COMMAND_TYPE CommandType; 
		
		union  {
			struct TNotification { PRJ_NOTIFY_TYPES NotificationMask; } 
			TNotification Notification; 
			
			struct TEnumeration { PRJ_DIR_ENTRY_BUFFER_HANDLE DirEntryBufferHandle; } 
			TEnumeration Enumeration; 
		} 
	} 
	
	__gshared extern(Windows) HRESULT function
		(
		const PRJ_NAMESPACE_VIRTUALIZATION_CONTEXT namespaceVirtualizationContext,
		const INT32 commandId,
		const HRESULT completionResult,
		const PRJ_COMPLETE_COMMAND_EXTENDED_PARAMETERS* extendedParameters
	) PrjCompleteCommand; 
}

version(/+$DIDE_REGION Enumeration APIs+/all)
{
	__gshared extern(Windows) HRESULT function
		(
		const PCWSTR fileName,
		const PRJ_FILE_BASIC_INFO* fileBasicInfo,
		const PRJ_DIR_ENTRY_BUFFER_HANDLE dirEntryBufferHandle
	)PrjFillDirEntryBuffer; 
	
	__gshared extern(Windows) BOOLEAN function
		(
		const PCWSTR fileNameToCheck,
		const PCWSTR pattern
	)PrjFileNameMatch; 
	
	__gshared extern(Windows) int function
		(
		const PCWSTR fileName1,
		const PCWSTR fileName2
	)PrjFileNameCompare; 
	
	__gshared extern(Windows) BOOLEAN function
		(const LPCWSTR fileName)PrjDoesNameContainWildCards; 
}