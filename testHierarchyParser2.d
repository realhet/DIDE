//@exe
///@debug
//@release

import het.utils;

// IndexOfToken ///////////////////////////////////////

ubyte[] extractTokenChars(string[] tokens){
	return tokens	.map!(t => cast(ubyte)t[0])
		.array.sort.uniq.array;
}

/// It supports a static array of strings as parameters
size_t startsWithToken(string[] tokens)(string s){
	const ba = cast(ubyte[])s;
	enum gen = 	"ba.startsWith( "
		~ tokens	.map!(a =>	'[' 
				~ a	.byChar.map!(b => format!"ubyte(%d)"(cast(ubyte)b))
					.join(',') 
				~ ']')
			.join(',') 
		~ " )";
	pragma(msg, __FUNCTION__, "\n", gen);
	return mixin(gen);
}

/// Find the first location index and the token index in the string. 
/// Returns s.length if can't find anything.
/// If the token is marked with tmPreserve, then it will not skip it. (slashComment for example)
struct IndexOfToken{
	//opt: int instead of size_t
	size_t		tokenIdx, //1based
		tokenStartIdx, tokenLen; 
	@property auto tokenEndIdx() const{ return tokenStartIdx+tokenLen; }
	
	void skip(ref string src) const{ src = src[tokenEndIdx..$]; }
	
	string fetchSS(ref string src) const{ auto tmp = src[0..tokenStartIdx	]; src = src[tokenStartIdx	..$]; return tmp; }
	string fetchSE(ref string src) const{ auto tmp = src[0..tokenStartIdx	]; src = src[tokenEndIdx	..$]; return tmp; }
	string fetchEE(ref string src) const{ auto tmp = src[0..tokenEndIdx	]; src = src[tokenEndIdx	..$]; return tmp; }
} //opt:int

auto indexOfToken(string[] tokens)(string s){
	enum len  = 0 ~ tokens.map!(t => t.length).array;
	//opt:array of struct instead of struct of arrays
	
	foreach(i; 0..s.length)
		if(auto t = s[i..$].startsWithToken!tokens) 
			return IndexOfToken(t, i, len[t]);
			
	return IndexOfToken(0, s.length, 0);
}

// Lexer //////////////////////////////////////////////////
struct StructureScanner{
	static{//----------------------------------------------------------------------------
		
		immutable 	EOFTokens	= "\0 \x1A __EOF__"	,
			EOFTokens_str 	= "\0 \x1A"	, //note: __ EOF __  is NOT detected in strings. Only in structuredText and comments.
			NewLineTokens	= "\r \n \u2028 \u2029"	;
		
		struct Transition{
			string[] tokens;
			State dst;
			int op; //1 = push
			@property bool isPop() const{ return dst == State.pop; }
			@property bool isPush() const{ return op==1; }
		}
		
		struct TR{ string token; State dst; int op; }
		TR[] expand(in Transition transition){ return transition.tokens.map!(t => TR(t, transition.dst, transition.op)).array; }
		TR[] expand(in Transition[] transitions){ return transitions.map!(t => expand(t)).join; }
		
		string extendCWD(string s){	return s.split(' ').map!(a => "*c *w *d *".replace("*", a)).join(" "); }
		
		enum Trans	(string s, alias dst, int op = 0	) = Transition(s.split(' '), dst, op);
		enum Push	(string s, alias dst	) = Trans!(s, dst, 1);
		enum Pop	(string s	) = Trans!(s, State.pop);
		enum Pop_str	(string s	) = Pop!(extendCWD(s));
		enum Ignore	(string s	) = Trans!(s, State.ignore);
		enum EOF	(	) = Trans!(EOFTokens, State.eof); //normal eof handler
		enum EOF_str	(	) = Trans!(EOFTokens_str, State.eof); //Don't check for __ EOF __ in strings
		
		enum State : ubyte {
			//terminal states
			eof, unexpectedEof,
			
			//special states
			pop, ignore,
			 
			@Push!("", eof) //"" means it takes all the text
			unstructured,
			
			@Push!("{ ( [ q{"	, structured	) @Pop!"] ) }"
			@Push!("//"	, slashComment	) @Push!("/*"	, cComment	) @Push!("/+"	, dComment	)
			@Push!("'"	, cChar	) @Push!(`"`	, cString	) @Push!("`"	, dString	) @Push!(`r"`	, rString	)
			@Push!(`q"/`	, qStringSlash	) @Push!(`q"{`	, qStringCurly	) @Push!(`q"(`	, qStringRound	) 
			@Push!(`q"[`	, qStringSquare	) @Push!(`q"<`	, qStringAngle	) @Push!(`q"`	, qStringBegin	)
			@EOF!()
			structured,
			
			@Pop!NewLineTokens 	 @Pop!EOFTokens	 	 slashComment	,
				 @Pop!"*/"	 @EOF!()	 cComment	,
			@Push!("/+", dComment)	 @Pop!"+/"	 @EOF!()	 dComment 	,
							
			@Ignore!`\'`	 @Pop_str!`'`	 @EOF_str!()	 cChar	,
			@Ignore!`\"`	 @Pop_str!`"`	 @EOF_str!()	 cString	,
				 @Pop_str!`"`	 @EOF_str!()	 rString	,
				 @Pop_str!"`"	 @EOF_str!()	 dString	,
				 @Pop_str!`/"`	 @EOF_str!()	 qStringSlash	,
			@Push!("{", qStringCurlyInner)	 @Pop_str!`}"`	 @EOF_str!()	 qStringCurly	,
			@Push!("(", qStringRoundInner)	 @Pop_str!`)"`	 @EOF_str!()	 qStringRound	,
			@Push!("[", qStringSquareInner)	 @Pop_str!`]"`	 @EOF_str!()	 qStringSquare	,
			@Push!("<", qStringAngleInner)	 @Pop_str!`>"`	 @EOF_str!()	 qStringAngle	,
							
			@Push!("{", qStringCurlyInner)	 @Pop!`}`	 @EOF_str!()	 qStringCurlyInner	,
			@Push!("(", qStringRoundInner)	 @Pop!`)`	 @EOF_str!()	 qStringRoundInner	,
			@Push!("[", qStringSquareInner)	 @Pop!`]`	 @EOF_str!()	 qStringSquareInner	,
			@Push!("<", qStringAngleInner)	 @Pop!`>`	 @EOF_str!()	 qStringAngleInner	,
					
			@Trans!(NewLineTokens, qStringMain)	 	 @EOF_str!()	 qStringBegin,
			/+ handled specially +/	 	 @EOF_str!()	 qStringMain,
		}
	}//static
	public{ //----------------------------------------------------------------------
		
		static struct Result{
			string src, token;
			State state;
		}
		
		private{
			string src, nextSrc;  
			State state = State.structured;
			State[] stack;
			
			bool isResultValid;
			Result result;
			
			void process(){
				assert(!isResultValid);
				nextSrc = src;
				
				swState: final switch(state){
					static foreach(stIdx, st; EnumMembers!State){
						case st:{
							//enum Transition[] transitions = ;
							enum trs = expand([getUDAs!(EnumMembers!State[stIdx], Transition)]);
							enum tokens = trs.map!(t => t.token).array;
							print("aaaaa", st);
							foreach(tr; trs) print("   ", tr);
							foreach(t; tokens) print("   ", t);
							//print(src.indexOfToken!tokens);
						}break swState;
					}
				}
				
				result.state = state;
				result.src = nextSrc.front.text;
				nextSrc.popFront;
				
			}
		}
		
		auto save(){ return this; }
		
		@property bool empty() const{ return src.empty; }
		
		@property auto front(){
			if(isResultValid.chkSet) process;
			return result;
		}
		
		void popFront(){
			if(isResultValid.chkSet) process;
			src = nextSrc;
			isResultValid = false;
		}
	}
}
	
void main(){ console({
	auto sc = StructureScanner("hello");
	foreach(r; sc) print(r);
}); }