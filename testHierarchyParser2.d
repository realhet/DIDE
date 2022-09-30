//@exe
///@debug
//@release

import het.utils, het.assembly;

// IndexOfToken ///////////////////////////////////////

ubyte[] extractTokenFirstUbytesSorted(string[] tokens){
	return tokens	.map!(t => cast(ubyte)t[0])
		.array.sort.uniq.array;
}

enum ToUbyteArray(string s) = mixin('[' ~ s.byChar.map!(b => format!"ubyte(%d)"(cast(ubyte)b)).join(',') ~ ']');
enum ToUbyteArrayOfArray(string[] s) = mixin('[' ~ s.map!(a =>	'[' ~ a	.byChar.map!(b => format!"ubyte(%d)"(cast(ubyte)b)).join(',')~ ']').join(',') ~ ']');

///This version stops at the first needle, not returning the shortest needle (phobos version).
///The result is 0 based.  -1 means not found.
sizediff_t startsWithToken(string[] tokens)(string s){
	static assert(tokens.all!"a.length");
	
	//simple tokens are 1 byte long and no other tokens are starting with them.
	static bool isSimple(string tk){ return tk.length==1 && tokens.filter!(t => t.startsWith(tk)).walkLength==1; }
	static immutable 	simpleTokens	= tokens.filter!isSimple.array,
		charSet	= tokens.map!"ubyte(a[0])".array.sort.uniq.array,
		charSet_simpleIdx 	= charSet.map!(b => simpleTokens.canFind((cast(char)b).text) ? tokens.countUntil((cast(char)b).text): -1).array,
		charSet_complexTokens	= charSet.map!(b => simpleTokens.canFind((cast(char)b).text) ? [] : tokens.filter!(t => t.startsWith((cast(char)b).text)).map!(t => tuple(t[1..$], tokens.countUntil(t))).array).array; //todo: ezt a 2 szintu tombot transzponalni kell.
	static if(1){
		pragma(msg, format!"tokens                  (%2d): %s"(tokens.length, tokens));
		pragma(msg, format!"  simpleTokens          (%2d): %s"(simpleTokens.length, simpleTokens));
		pragma(msg, format!"  charSet               (%2d): %s"(charSet.length, charSet));
		pragma(msg, format!"  charSet_simpleIdx     (%2d): %s"(charSet_simpleIdx.length, charSet_simpleIdx));
		pragma(msg, format!"  charSet_complexTokens(%2d): %s"(charSet_complexTokens.length, charSet_complexTokens));
		pragma(msg, "");
	}
	
	static if(0){
		static foreach(idx, token; tokens){{ //opt: slow linear search. Should use a char map for the first char. Or generate a switch statement.
			if((cast(ubyte[])s).startsWith(cast(ubyte[])token)) return idx;
		}}
	}else{
		if(s.length){
			auto cIdx = charSet.countUntil(cast(ubyte)s[0]); //opt: <- pcmpestri
			if(cIdx>=0){ //todo: slow
				auto stIdx = charSet_simpleIdx[cIdx];
				if(stIdx>=0) return stIdx;
				
				s = s[1..$]; //todo: should be recursive from here.
				foreach(ct; charSet_complexTokens[cIdx]){{ //opt: slow linear search. Should use a char map for the first char. Or generate a switch statement.
					if((cast(ubyte[])s).startsWith(cast(ubyte[])(ct[0]))) return ct[1];
				}}
			}
		}
	}
	return -1;
}

size_t skipTokens(string[] tokens)(string s){
	static assert(tokens.all!"a.length");
	static immutable charSet = tokens.map!"ubyte(a[0])".array.sort.uniq.array;
	
	static if(0){
		const res = s.length - (cast(ubyte[])s).findAmong(charSet).length;
		//print("QQ", res); static int cnt; if(cnt++==20) readln;
		return res;
	}else{
		enum sseLengthLimit = 16; //SSE vector size limit
		
		//generate charSetVector: It contains all the chars the tokens can start with.
		static assert(charSet.length <= sseLengthLimit);
		static immutable ubyte16 charSetVector = mixin(charSet.padRight(0, sseLengthLimit).text);
		
		auto remaining = s.length, p0 = s.ptr, p = p0;
		while(remaining>=16){ //note: this padding solves the unaligned read from a 4k page boundary at the end of the string. No masked reads needed.
			/*const tmp = __asm!size_t(
				q{
					movdqu $3, %XMM4
					pcmpestri $5, %XMM4, $1
				}
				//    0   1  2   3  4  5
				, q{={RCX},x,{RAX},*p,{RDX},i,~{XMM4},~{flags}}, 
				charSetVector, charSet.length, p, remaining, 0
			); */
			const tmp = __asm!size_t( //no 16byte align needed.
				q{
					pcmpestri $5, $3, $1
				}
				//    0   1  2   3  4  5
				, q{={RCX},x,{RAX},*p,{RDX},i,~{flags}}, 
				charSetVector, charSet.length, p, remaining, 0
			);
			
			p += tmp;
			if(tmp<16) break;  //opt: Carry Flag signals if nothing found
			remaining -= tmp;
		}
		const res = p-p0;
		//print("QQ", res); static int cnt; if(cnt++==20) readln;
		return res;
	}
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
		static assert(tokens.all!"a.length");
		
		do{
			//FastSkip
			static if(1)
				startIdx += skipTokens!tokens(s[startIdx..$])/+.HIST!(20)+/;
			
			//check the tokens at startIdx
			const tIdx = s[startIdx..$].startsWithToken!tokens;
			if(tIdx>=0)
				return IndexOfTokenResult(tIdx, tokens[tIdx].length, startIdx);
			
		}while(startIdx++ < s.length);
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
		
		enum State : ubyte { // State graph //////////////////////////////////////////////////////////////////
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
		
		/+todo: Step Parser enum State : ubyte { // State graph //////////////////////////////////////////////////////////////////
			/+special system tokens+/ ignore, pop, eof, @Trans("", eof) unstructured, 
			
			@Push("(", structured) @Pop(")") @Push("/*", comment) @Push(`'`, name) @Trans(";", structured) @EOF structured,
			@Pop("*/") @EOF comment,
			@Ignore(`\\ \'`) @Pop("'") @EOF name
		}+/
	
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


void benchmark(){
	auto files	= Path(`c:\d\ldc2\import\std`	).files("*.d", true)
		~ Path(`c:\d\libs\het`	).files("*.d");
	
	Time[2] totalTime = 0*second;  size_t[2] totalBytes;
	foreach(file; files){
		const src = file.readText;
		static foreach(i; 0..2){{
			size_t actBytes;
			T0; 
			static if(i==0){{ import het.tokenizer; auto sc = new SourceCode(src); actBytes = sc.tokens.map!"a.source.length".sum; }}
			static if(i==1){{ actBytes = StructureScanner.scanner(src).map!"a.src.length".sum; }}
			totalTime[i] += DT;
			totalBytes[i] += src.length;
			static if(i==1) if(actBytes!=src.length) ERR("StructureScanner is FUCKED UP:", i, file, actBytes, src.length);
		}}
	}
	string measurement(int i){ 
		const bps = totalBytes[i]/totalTime[i].value(second);
		return (bps/1024^^2).format!"%.1fMiB/s";
	}
	print("Benchmark: ", 
		" old:", measurement(0), 
		" new:", measurement(1), 
		" gain:", EgaColor.yellow((totalTime[0].value(second)/totalTime[1].value(second)).format!"%.2fx"), 
		" Data: ", totalBytes[0].shortSizeText!1024.format!"%siB", 
		" Time(new):", siFormat("%.3fs", totalTime[1])
	);
}
	
			
void main(){ console({ //main() //////////////////////////////////////////////////////////////
	foreach(f; Path(`c:\d\libs\het\`).files(`*.d`)){
		auto src = f.readText;
		auto scanner = StructureScanner.scanner(src);	
		print(f);
		print(src.length, scanner.map!(a => a.src.length).sum);
	}
	
	benchmark;
	
	
	T0;
	auto src = File(`c:\d\libs\het\`~`com`~`.d`).readText;           	DT.print;
	auto scanner = StructureScanner.scanner(src);	DT.print;
	scanner.walkLength;	DT.print;
	{ import het.tokenizer; cast(void)(new SourceCode(src)); }	DT.print;
	print(src.length);
	
	
	scanner = StructureScanner.scanner(src);
	
	if(1) scanner	.take(100)
		//.filter!(a => !a.src.isWild(`*:\*`)) //a file neveket nem mutatom
		.each!((a){
			with(EgaColor) write(a.op.predSwitch(	"content"	, ltWhite	(a.src),
				"push"	, ltBlue	(a.src),
				"pop"	, ltGreen	(a.src),
				"trans"	, ltCyan	(a.src)
					, gray	(a.src) ));
	});
	
	print("\n--------------------------DONE------------------------------");
}); }