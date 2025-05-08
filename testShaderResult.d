import hello; 
enum N = 5,
status = 	import  ("hello") +
	import("hello") +
	mixin(iq{$(N)}.text) + 
	mixin( iq{$(N)}.text ) + 
	mixin( iq{$(N)} .text )
	/+Code: mixin( iq{$(N)} .text )+/
	,
data = x"414243 444546
616263 31 32 33 34 35 36 37"; 