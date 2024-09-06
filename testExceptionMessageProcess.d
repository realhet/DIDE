//@exe
//@debug

import het; 

string processExceptionMessage(string message)
{/+copy original version from dide.d!+/} 

const msg1 = 
`c:\d\testcleartypemultisampling.d(84,1): Error: object.Exception: FUCK
----------------
0x00007FF7419942D4 in bailOut!(Exception) at C:\D\ldc2\import\std\exception.d(522)
0x00007FF741A2E021 in enforce!int at C:\D\ldc2\import\std\exception.d(443)
0x00007FF741A91376 in raise at c:\d\libs\het\package.d(1230)
0x00007FF741991A38 in onPaint at c:\d\testcleartypemultisampling.d(84)
0x00007FF741BC53DE in internalPaint at c:\d\libs\het\win.d(997)
0x00007FF741BC51EB in internalRedraw at c:\d\libs\het\win.d(680)
0x00007FF741BC31BE in WndProc at c:\d\libs\het\win.d(732)
0x00007FF741BC241E in GlobalWndProc at c:\d\libs\het\win.d(326)
0x00007FFFFB0DEF5C in CallWindowProcW
0x00007FFFFB0DE9DE in CallWindowProcW
0x00007FFFDB7DF1F0 in glPushClientAttrib
0x00007FFFFB0DEF5C in CallWindowProcW
0x00007FFFFB0DE8CC in DispatchMessageW
0x00007FFFFB0F1633 in SendMessageTimeoutW
0x00007FFFFBB513E4 in KiUserCallbackDispatcher
0x00007FFFF9691704 in NtUserDispatchMessage
0x00007FFFFB0DE7B1 in DispatchMessageW
0x00007FF741BC254C in D main at c:\d\libs\het\win.d(253)
0x00007FF741C60695 in void rt.dmain2._d_run_main2(char[][], ulong, extern (C) int function(char[][])*).runAll()
0x00007FF741C6034B in d_run_main2
0x00007FF741C605F6 in d_wrun_main
0x00007FF741BC7234 in wmain at C:\D\ldc2\import\core\internal\entrypoint.d(32)
0x00007FF741CF6CC0 in __scrt_common_main_seh at d:\agent\_work\3\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl(288)
0x00007FFFFB687374 in BaseThreadInitThunk
0x00007FFFFBAFCC91 in RtlUserThreadStart
`,
msg2 =
`Error: OS Exception: ACCESS_VIOLATION at 7FF6E29C1A1E info: 0, 0
----------------
0x00007FF6E29C1A1E in onPaint at c:\d\testcleartypemultisampling.d(85)
0x00007FF6E2BF53BE in internalPaint at c:\d\libs\het\win.d(997)
0x00007FF6E2BF51CB in internalRedraw at c:\d\libs\het\win.d(680)
0x00007FF6E2BF319E in WndProc at c:\d\libs\het\win.d(732)
0x00007FF6E2BF23FE in GlobalWndProc at c:\d\libs\het\win.d(326)
0x00007FFFFB0DEF5C in CallWindowProcW
0x00007FFFFB0DE9DE in CallWindowProcW
0x00007FFFDB7DF1F0 in glPushClientAttrib
0x00007FFFFB0DEF5C in CallWindowProcW
0x00007FFFFB0DE8CC in DispatchMessageW
0x00007FFFFB0F1633 in SendMessageTimeoutW
0x00007FFFFBB513E4 in KiUserCallbackDispatcher
0x00007FFFF9691704 in NtUserDispatchMessage
0x00007FFFFB0DE7B1 in DispatchMessageW
0x00007FF6E2BF252C in D main at c:\d\libs\het\win.d(253)
0x00007FF6E2C90675 in void rt.dmain2._d_run_main2(char[][], ulong, extern (C) int function(char[][])*).runAll()
0x00007FF6E2C9032B in d_run_main2
0x00007FF6E2C905D6 in d_wrun_main
0x00007FF6E2BF7214 in wmain at C:\D\ldc2\import\core\internal\entrypoint.d(32)
0x00007FF6E2D26CA0 in __scrt_common_main_seh at d:\agent\_work\3\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl(288)
0x00007FFFFB687374 in BaseThreadInitThunk
0x00007FFFFBAFCC91 in RtlUserThreadStart`; 

/+
	?:\?*.?*(*): Error: *
	Error: *
	----------------
	0x???????????????? in * at ?:\?*.?*(*)
	0x???????????????? in *
+/
void main() {
	console(
		{
			foreach(m; [msg1, msg2])
			m.processExceptionMessage.print; 
		}
	); 
} 