//@exe
///@debug
//@release
//@compile

import het.utils;

// IndexOfToken ///////////////////////////////////////

ubyte[] extractTokenFirstUbytes(string[] tokens){
	return tokens	.map!(t => cast(ubyte)t[0])
		.array.sort.uniq.array;
}

enum ToUbyteArray(string s) = mixin('[' ~ s.byChar.map!(b => format!"ubyte(%d)"(cast(ubyte)b)).join(',') ~ ']');
enum ToUbyteArrayOfArray(string[] s) = mixin('[' ~ s.map!(a =>	'[' ~ a	.byChar.map!(b => format!"ubyte(%d)"(cast(ubyte)b)).join(',')~ ']').join(',') ~ ']');

///This version stops at the first needle, not returning the shortest needle (phobos version).
///The result is 0 based.  -1 means not found.
sizediff_t startsWithToken(string[] tokens)(string s){
	asm{ int 3; }
	print(__FUNCTION__);
	asm{ int 3; }
	const ba = cast(ubyte[])s;
	static foreach(idx, token; ToUbyteArrayOfArray!tokens){{ //opt: slow linear search. Should use a char map for the first char. Or generate a switch statement.
		if(ba.startsWith(token)) return idx;
	}}
	return -1;
}

/// Find the first location index and the token index in the string. 
/// Returns s.length if can't find anything.
/// If the token is marked with tmPreserve, then it will not skip it. (slashComment for example)
struct IndexOfTokenResult{
	//opt: int instead of size_t
	sizediff_t	tokenIdx=-1; //0based
	size_t	tokenLen, tokenStartIdx; 
	
	bool valid() const{ return tokenIdx>=0; }
	auto opCast(b : bool)() const{ return valid; }
	auto tokenEndIdx() const{ return tokenStartIdx+tokenLen; }
} //opt: int-tel kiprobalni size_t helyett.

auto indexOfToken(string[] tokens)(string s, size_t startIdx){
	assert(startIdx<=s.length);
	
	static if(!tokens.equal([""])){ //special case: [""] means: take everything, seek to the end.
		
		//use findAmong with the list of first ubytes
		static if(0){
			//this is exactly slow as if it were omitted. It really needs SSE strcmp!
			//static immutable firstUBytes = tokens.extractTokenFirstUbytes;
			//startIdx = s.length - (cast(ubyte[])s)[startIdx..$].findAmong(firstUBytes).length;
		}
		
		//opt: slow linear search
		//opt: statistical reordering of items
		foreach(i; startIdx..s.length){ 
			const tIdx = s[i..$].startsWithToken!tokens;
			if(tIdx>=0)
				return IndexOfTokenResult(tIdx, tokens[tIdx].length, i);
		}
	}
			
	//emulate physical eof with a \0.  If can't find -> -1.
	enum NullTokenIdx = tokens.countUntil("\0");
			
	return IndexOfTokenResult(NullTokenIdx, 0, s.length); //the very end of the string, and 0 idx
}

// StructureScanner //////////////////////////////////////////////////
struct StructureScanner{
	static private{//-----------------------------------------------------------------------------------------------------
		
		struct Transition{
			string token;
			State dstState;
			int op; //1 = push
			@property bool isPop() const{ return dstState == State.pop; }
			@property bool isIgnore() const{ return dstState == State.ignore; }
			@property bool isPush() const{ return op==1; }
		}
		
		static auto collectStateTransitions(State st)(){
			static auto doit(A...)(A args){
				Transition[] res;
				foreach(a; args) static if(is(typeof(a)==Transition[])) res ~= a;
				return res;
			}
			return doit(mixin(st.stringof.format!"__traits(getAttributes, %s)")); //todo: why is this mixin needed here???
		}
		
		string extendCWD(string s){ 
			//return s.split(" ").map!(a => a~"c "~a~"w "~a~"d "~a).join(" ");
			//todo: ^^^^^^^^^^^ this fails in CTFE. It makes const char[][] instead of string[]
			
			string res;
			foreach(a; s.split) 
				res ~= (res.length ? " " : "") ~ a~"c "~a~"w "~a~"d "~a;
			return res;
		}
	
		auto Trans(string s, State dst, int op=0){ 
			return s=="" 	?	[Transition("", dst, op)]  //s=="" means take ALL chars from src
				:	s.split(' ').map!(t => Transition(t, dst, op)).array;
		}
		
		auto Push	(string s, State dst	){ return Trans(s, dst, 1); }
		auto Pop	(string s	){ return Trans(s, State.pop); }
		auto Ignore	(string s	){ return Trans(s, State.ignore); }
		auto PopCWD	(string s	){ return Pop(extendCWD(s)); }
		
		enum NewLineTokens	= "\r \n \u2028 \u2029";
		enum EOFTokens	= "\0 \x1A";
		enum EOF	= Trans(EOFTokens	, State.unstructured);
		enum StructuredEOF	= Trans(EOFTokens ~ " __EOF__"	, State.unstructured);
		
		version(none) enum State : ubyte { // State graph //////////////////////////////////////////////////////////////////
			/+special system tokens+/ ignore, pop, eof, @Trans("", eof) unstructured, 
			
			@Push("{ ( [ q{"	, structured	) @Pop("] ) }")
			@Push("//"	, slashComment	) @Push("/*"	, cComment	) @Push("/+"	, dComment	)
			@Push("'"	, cChar	) @Push(`"`	, cString	) @Push("`"	, dString	) @Push(`r"`	, rString	)
			@Push(`q"/`	, qStringSlash	) @Push(`q"{`	, qStringCurly	) @Push(`q"(`	, qStringRound	) 
			@Push(`q"[`	, qStringSquare	) @Push(`q"<`	, qStringAngle	) @Push(`q"`	, qStringBegin	)
			@StructuredEOF
			structured,
			
			@Pop(NewLineTokens)	 @Pop(EOFTokens)	 	slashComment	,
				 @Pop("*/")	 @EOF	cComment	,
			@Push("/+", dComment)	 @Pop("+/")	 @EOF	dComment 	,
							
			@Ignore(`\\ \'`)	 @PopCWD(`'`)	 @EOF	 cChar	,
			@Ignore(`\\ \"`)	 @PopCWD(`"`)	 @EOF	 cString	,
				 @PopCWD(`"`)	 @EOF	 rString	,
				 @PopCWD("`")	 @EOF	 dString	,
				 @PopCWD(`/"`)	 @EOF	 qStringSlash	,
			@Push("{", qStringCurlyInner)	 @PopCWD(`}"`)	 @EOF	 qStringCurly	,
			@Push("(", qStringRoundInner)	 @PopCWD(`)"`)	 @EOF	 qStringRound	,
			@Push("[", qStringSquareInner)	 @PopCWD(`]"`)	 @EOF	 qStringSquare	,
			@Push("<", qStringAngleInner)	 @PopCWD(`>"`)	 @EOF	 qStringAngle	,
							
			@Push("{", qStringCurlyInner)	 @Pop(`}`)	 @EOF	 qStringCurlyInner	,
			@Push("(", qStringRoundInner)	 @Pop(`)`)	 @EOF	 qStringRoundInner	,
			@Push("[", qStringSquareInner)	 @Pop(`]`)	 @EOF	 qStringSquareInner	,
			@Push("<", qStringAngleInner)	 @Pop(`>`)	 @EOF	 qStringAngleInner	,
							
			@Trans(NewLineTokens, qStringMain)	 	 @EOF	 qStringBegin	,
			/+ handled specially +/	 	 @EOF	 qStringMain	,
		}
		
		enum State : ubyte { // State graph //////////////////////////////////////////////////////////////////
			/+special system tokens+/ ignore, pop, eof, @Trans("", eof) unstructured, 
			
			@Push("(", structured) @Pop(")") @Push("/*", comment) @Push(`'`, name) @Trans(";", structured) @EOF structured,
			@Pop("*/") @EOF comment,
			@Ignore(`\\ \'`) @Pop("'") @EOF name
		}
	
	}//static private

	import std.concurrency : Generator, yield; //Ali Cehreli Fiber presentation: https://youtu.be/NWIU5wn1F1I?t=1624

	static struct ScanResult{
		string op, src;
	}

	private static auto scan(string src){
		enum log = 0;

		State[] stack = [State.structured];
		ref State state()	{ return stack.back; }
		int stackLen()	{ return cast(int)stack.length; }
		
		while(src.length){
			
			swState: final switch(state){
				static foreach(caseState; EnumMembers!State){
					case caseState:{
						static immutable	transitions	 = collectStateTransitions!caseState,
							tokens	 = transitions.map!"a.token".array;
						//pragma(msg, caseState, "\n", transitions.map!(a => a.format!"  %s").join("\n"));
						if(log){
							print("------------------------------------");
							print("SRC:", EgaColor.yellow(src.quoted));
							print("State:", state, "Stack:", stack.retro);
							print("Looking for:", transitions.map!"a.token");
						}
						
						//terminal node
						
						static if(transitions.length){
							auto match = indexOfToken!tokens(src, 0);
							
							//skip ignored tokens
							enum ignoreTokenIdx = transitions.countUntil!(t => t.isIgnore);
							static if(ignoreTokenIdx>=0){
								while(match && transitions[match.tokenIdx].isIgnore)
									match = indexOfToken!tokens(src, match.tokenEndIdx);
							}
							
							if(log) print(match);
							if(match){ //found something
								auto	contents 	= src[0..match.tokenStartIdx],
									tokenStr 	= src[match.tokenStartIdx..match.tokenEndIdx]; //the actual token from the string. The last "" is detected as "\0"
								src = src[match.tokenEndIdx..$]; //advance
								with(transitions[match.tokenIdx]){
									assert(!isIgnore, "Ignored tokens must be already skipped before this point.");
									
									if(contents.length)
										yield(ScanResult("content", contents)); 
									
									//update stack
									if(isPush){ 
										stack ~= dstState;
										yield(ScanResult("push", tokenStr)); 
									}else{ //pop or trans. Both needs a non-empty stack.
										if(stack.length){ 
											if(isPop){
												stack.popBack;
												yield(ScanResult("pop", tokenStr)); 
											}else{ //transition
												state = dstState;
												yield(ScanResult("trans", tokenStr)); 
											}
										}else{
											yield(ScanResult("stack.empty", tokenStr ~ src));
											return;
										}
									}
								}
							}else{
								yield(ScanResult("scanner.stopped1", src));
								return;
								//assert(0, format!"Scanner error: Find nothing in state %s, and \0 is not even handled."(caseState));
							}
							break swState; //break from case
						}else{
							yield(ScanResult("scanner.stopped2", src));
							return;
							//static assert(caseState.among(State.pop, State.ignore, State.eof), format!"Scanner State graph error: %s should reach State.eof."(caseState));
						}
					}
				}
			}
		}//end while
		
	}//end func
	
	static auto scanner(string src){
		return new Generator!ScanResult({ scan(src); });
	}
}
	
void main(){ console({ //main() //////////////////////////////////////////////////////////////
	//StructureScanner("hello //comment\nnext line/*ccomment\nanother line*//+/+Nested+/comment+/__EOF__text beyond eof", [StructureScanner.State.structured]).each!print;
	
	/*auto src = File(`c:\d\libs\het\utils.d`).readText;
	auto sc = StructureScanner.scanner(src);
	
	T0;
	print(sc.walkLength);
	print(DT);
	
	import het.tokenizer;
	T0;
	auto sourceCode = new SourceCode(src);
	print(sourceCode.tokens.length);
	print(DT);
	
	
	
	readln;
	
	void dump(){
		auto src = File(`c:\d\projects\DIDE\testHierarchyParser2.d`).readText;
		auto sc = StructureScanner.scanner(src);
		sc.each!((a){
			write(a.op.predSwitch(	"content"	, EgaColor.ltWhite	(a.src),
				"push"	, EgaColor.ltBlue	(a.src),
				"pop"	, EgaColor.ltGreen	(a.src),
				"trans"	, EgaColor.ltCyan	(a.src)
					, EgaColor.gray	(a.src)));
		});
	}
	
	dump;*/
	
	T0;
	auto src = File(`c:\dl\sac.step`).readText;           	DT.print;
	auto scanner = StructureScanner.scanner(src);	DT.print;
	scanner.walkLength.print;	DT.print;
	
	scanner = StructureScanner.scanner(src);
	
	scanner	.take(200)
		.filter!(a => !a.src.isWild(`*:\*`)) //a file neveket nem mutatom
		.each!((a){
			with(EgaColor) write(a.op.predSwitch(	"content"	, ltWhite	(a.src),
				"push"	, ltBlue	(a.src),
				"pop"	, ltGreen	(a.src),
				"trans"	, ltCyan	(a.src)
					, gray	(a.src) ));
	});
	
	print("\n--------------------------DONE------------------------------");
}); }