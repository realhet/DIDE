//@exe
///@debug
//@release

import het.utils;

enum StructureType : byte {
	unstructuredText, 
	cComment, dComment, slashComment, sheBang, setLine, 
	structuredText, structuredBlock, structuredIndex, structuredList, 
	tokenString, 
	cString, cChar, rString, dString, qString
}

/*enum structuralCharSets{ 
	EOF = "\0\x1A_"	,//_ => _ _EOF_ _
	EOL = "\r\n\xA8\xA9"	,// \xE2\x80\xA8 => \u2028, \xE2\x80\xA9 => \u2029
}*/

//struct CharDetectorRefine{ char ch; bool function

/+alias tokenDetect_structureStart	= tokenDetect!(["/*", "/+", "//", `#line `, `#!`, `(`, `)`, `[`, `]`, `{`, `}`, `-q{`, `'`, `"`, `-r"`, "`", `-q"`]	 ~ chd_EOF);
alias tokenDetect_EOL	= tokenDetect!(["\r", "\n", "\u2028", "\u2029"]	 ~ chd_EOF);
alias tokenDetect_cCommentEnd	= tokenDetect!(["*/"]	 ~ chd_EOF);
alias tokenDetect_dCommentEnd	= tokenDetect!(["+/", "/+"]	 ~ chd_EOF);
alias tokenDetect_cString	= tokenDetect!([`"`, `\"`]	 ~ chd_EOF);
alias tokenDetect_charString	= tokenDetect!([`'`, `\'`]	 ~ chd_EOF);
alias tokenDetect_wString	= tokenDetect!([`"`]	 ~ chd_EOF);
alias tokenDetect_dString	= tokenDetect!(["`"]	 ~ chd_EOF);+/+/

/+struct TokenCase{ string token; void function() fun; }
void tokenDetect(alias structuredFun, TokenCase[] cases)(ref string src){
	
}+/

//note: no need for bactwards detection! 16 slot is enough. 

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
	//pragma(msg, __FUNCTION__, "\n", gen);
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

uint uintHash(uint h0, string haFun)(string s){
	uint h = h0;
	foreach(a; s.byChar.map!"cast(uint)a") h = mixin(haFun);
	return h;
}

uint djb2Hash(bool opt)(string s){
	//http://www.cse.yorku.ca/~oz/hash.html
	return s.uintHash!(5381, opt ? "(h << 5) + h + a" : "h*33u + a");
}

uint sdbmHash(bool opt)(string s){
	//http://www.cse.yorku.ca/~oz/hash.html
	return s.uintHash!(0, opt ? "(h << 6) + (h << 16) - h + a" : "h* 65599u + a");
}

uint tokenHash()(string s){
	switch(s.length){
		case 0: return 0;
		case 1: return *(cast(ubyte*)s.ptr)+7123u;
		case 2: return *(cast(ushort*)s.ptr)+2541281u;
		default: return s.sdbmHash!1;
	}
}

enum Token : ubyte{
	//EOF markers			
	@("\0") NULL	,@("\x1A") SUB	,@("__"~"EOF"~"__") specialEOF	,
				
	//line separators			
	@("\r") CR	,@("\u2028") LineSep	,	
	@("\n") LF	,@("\u2029") ParaSep	,	
				
	//special tokens			
	@("#!") sheBang	,@("#line ") setLine	,	
				
	//white space			
	@(" ") space	,@("\t") tab	,	
	@("\x0B") verticalTab	,@("\x0C") formFeed	,	
				
	//comments			
	@("/*") cCommentOpen	,@("*/") cCommentClose	,@("//") slashComment	,
	@("/+") dCommentOpen	,@("+/") dCommentClose	,	
				
	//string literals			
	@("'") cChar	,@("\"") cString	,@("`") dString	,
	@(`\'`) cCharEscape	,@(`\"`) cStringEscape	,
	@("r\"") rString	,
	@(`q"/`) qStringSlashOpen	,@(`/"`) qStringSlashClose	,@(`/"c`) qStringSlashCloseC	,@(`/"w`) qStringSlashCloseW	,@(`/"d`) qStringSlashCloseD	,
	@(`q"{`) qStringCurlyOpen	,@(`}"`) qStringCurlyClose	,@(`}"c`) qStringCurlyCloseC	,@(`}"w`) qStringCurlyCloseW	,@(`}"d`) qStringCurlyCloseD	,
	@(`q"(`) qStringRoundOpen	,@(`)"`) qStringRounyClose	,@(`)"c`) qStringRounyCloseC	,@(`)"w`) qStringRounyCloseW	,@(`)"d`) qStringRounyCloseD	,
	@(`q"[`) qStringSquareOpen	,@(`]"`) qStringSquaryClose	,@(`]"c`) qStringSquaryCloseC	,@(`]"w`) qStringSquaryCloseW	,@(`]"d`) qStringSquaryCloseD	,
	@(`q"<`) qStringAngleOpen	,@(`>"`) qStringAnglyClose	,@(`>"c`) qStringAnglyCloseC	,@(`>"w`) qStringAnglyCloseW	,@(`>"d`) qStringAnglyCloseD	,
	
	@(`"c`) cCharEndingC	,@(`'c`) cStringEndingC	,@("`c") dStringEndingC	,
	@(`"w`) cCharEndingW	,@(`'w`) cStringEndingW	,@("`w") dStringEndingW	,
	@(`"d`) cCharEndingD	,@(`'d`) cStringEndingD	,@("`d") dStringEndingD	,
	
	@(`<`) angleOpen	,@(`>`) angleClose	,
	@(`q"`) qStringIdentifier	,@("QSTRID") QSTRID	, //special marker to scan for an identifier for delimited strings.
	@("q{") tokenString	,
	
				
	//structure boundaries			
	@("(") roundBraceOpen	,@(")") roundBraceClose	,	
	@("[") squareBraceOpen	,@("]") squareBraceClose	,	
	@("{") curlyBraceOpen	,@("}") curlyBraceClose	,	
}

template token(string s){
	static foreach(idx, t; EnumMembers!Token){
		static if(getUDAs!(EnumMembers!Token[idx], string)[0]==s) enum token = t;
		//todo:          ^^^^^^^^^^^^^^^^^  if I uset here, getUDAs return empty array. WHY is this?!!
	}
}
static assert(token!("q{")==Token.tokenString);

template tokens(string s){
	enum parts = mixin(s.split.format!"AliasSeq!(%(%s,%))"); //todo: how to make aliassec from a splitted string nicely
	enum tokens = [staticMap!(token, parts)];
} 
static assert(tokens!("q{ `")==[Token.tokenString, Token.dString]);

immutable 	EOFTokens	= "\0 \x1A __EOF__"	,
	EOFTokensInStrings 	= "\0 \x1A"	, //note: __ EOF __  is NOT detected in strings. Only in structuredText and comments.
	NewLineTokens	= "\r \n \u2028 \u2029"	;

struct TokenTransition{
	Token[] tokens;
	TokenState dest;
	int flags; //1 = push
	@property bool isPop() const{ return dest == TokenState.pop; }
	@property bool isPush() const{ return flags==1; }
}

string extendCWD(string s){	return s.split(" ").map!(a => "*c *w *d *".replace("*", a)).join(" "); }

enum TT	(string s, alias dst, int flags = 0	) = TokenTransition(tokens!s, dst, flags);
enum Push	(string s, alias dst	) = TT!(s, dst, 1);
enum Pop	(string s	) = TT!(s, TokenState.pop);
enum Pop_str	(string s	) = Pop!(extendCWD(s));
enum Ignore	(string s	) = TT!(s, TokenState.ignore);
enum EOFHandler	(	) = TT!(EOFTokens, TokenState.eof); //normal eof handler
enum EOFHandler_str	(	) = TT!(EOFTokensInStrings, TokenState.eof); //Don't check for __ EOF __ in strings

enum TokenState{
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
	@EOFHandler
	structured,
	
	@Pop!NewLineTokens 	 @Pop!EOFTokens	 	 slashComment	,
		 @Pop!"*/"	 @EOFHandler	 cComment	,
	@Push!("/+", dComment)	 @Pop!"+/"	 @EOFHandler	 dComment 	,
					
	@Ignore!`\'`	 @Pop_str!`'`	 @EOFHandler_str	 cChar	,
	@Ignore!`\"`	 @Pop_str!`"`	 @EOFHandler_str	 cString	,
		 @Pop_str!`"`	 @EOFHandler_str	 rString	,
		 @Pop_str!"`"	 @EOFHandler_str	 dString	,
		 @Pop_str!`/"`	 @EOFHandler_str	 qStringSlash	,
	@Push!("{", qStringCurlyInner)	 @Pop_str!`}"`	 @EOFHandler_str	 qStringCurly	,
	@Push!("(", qStringRoundInner)	 @Pop_str!`)"`	 @EOFHandler_str	 qStringRound	,
	@Push!("[", qStringSquareInner)	 @Pop_str!`]"`	 @EOFHandler_str	 qStringSquare	,
	@Push!("<", qStringAngleInner)	 @Pop_str!`>"`	 @EOFHandler_str	 qStringAngle	,
					
	@Push!("{", qStringCurlyInner)	 @Pop!`}`	 @EOFHandler_str	 qStringCurlyInner	,
	@Push!("(", qStringRoundInner)	 @Pop!`)`	 @EOFHandler_str	 qStringRoundInner	,
	@Push!("[", qStringSquareInner)	 @Pop!`]`	 @EOFHandler_str	 qStringSquareInner	,
	@Push!("<", qStringAngleInner)	 @Pop!`>`	 @EOFHandler_str	 qStringAngleInner	,
			
	@TT!(NewLineTokens, qStringMain)	 	 @EOFHandler_str	 qStringBegin,
	@Pop!"QSTRID"	 	 @EOFHandler_str	 qStringMain,
}

enum transitions(alias ts) = getUDAs!(ts, TokenTransition);

TokenState tokenStateSeek(TokenState ts)(ref string){
	
}

auto process(TokenState actState, ref string src, ref TokenState[] stack){
	swLabel: final switch(actState){
		static foreach(tsIdx, ts; EnumMembers!TokenState){
			case ts:{
				immutable transitions = getUDAs!(ts, ts);
				pragma(msg, "generating case code for:"~ts.stringof);
				print(ts);
				break swLabel;
			}
		}
	}
	
	return TokenState.eof;
}

void testTokenStateProcessor(){
	string src = " /+ D0/+ D1+/ D2+/";
	TokenState[] stack;
	print(process(TokenState.structured, src, stack));
}

static foreach(idx, ts; EnumMembers!TokenState){
	pragma(msg, ts);
	static foreach(u; transitions!(EnumMembers!TokenState[idx])){
		pragma(msg, u);
	}
}
/+enum TokenState{
	//terminal states
	eof, unexpectedEof,
	
	@TT([], eof) //it takes all the text
	unstructured, 
	
	@TT(EOFTokens, eof) //todo: if the stack is empty, this is an unexpected eof
	
	@TTPush([Token.slashComment], slashComment)
	@TTPush([Token.cCommentOpen], cComment)
	@TTPush([Token.dCommentOpen], dComment)
	
	@TTPush([Token.cChar], cChar)
	@TTPush([Token.cString], cString)
	
	@TTPush([Token.curlyBraceOpen], structuredBlock)
	@TTPush([Token.roundBraceOpen], structuredArgs)
	@TTPush([Token.squareBraceOpen], structuredIndex)
	@TTPop([Token.curlyBraceClose, Token.roundBraceClose, Token.squareBraceOpen])
	
	structured,
	
	@TTPop(EOFTokens~NewLineTokens)
	slashComment,
	
	@TT(EOFTokens, eof)
	@TTPop([Token.cCommentEnd])
	cComment,
	
	@TT(EOFTokens, eof)
	@TTPush([Token.dCommentOpen], dComment)
	@TTPop([Token.dCommentEnd])
	dComment,
	
	@TT(EOFTokensInStrings, eof)
	@TTIgnore([Token.cCharEscape])
	@TTPop([Token.cCharC, Token.cCharW, Token.cCharD, Token.cChar])
	cChar,
	
	@TT(EOFTokensInStrings, eof)
	@TTIgnore([Token.cStringEscape])
	@TTPop([Token.cStringC, Token.cStringW, Token.cStringD, Token.cString])
	cString,
	
	@TT(EOFTokensInStrings, eof)
	@TTPop([Token.cStringC, Token.cStringW, Token.cStringD, Token.cString])
	rString,
	
	@TT(EOFTokensInStrings, eof)
	@TTPop([Token.dStringC, Token.dStringW, Token.dStringD, Token.dString])
	qString,
}+/




void testHashes(){
	auto data = [`(`, `{`, `[`, "/*", "/+", "//", `'`, `"`, "`", "r\"", "q\"", "q{", `#line `, `#!`, `)`, `}`, `]`, "\0", "\x1A", "__EOF__"].replicate(10);
	
	data.take(20).each!(s => print(s.djb2Hash!0, s.djb2Hash!1, s.sdbmHash!0, s.sdbmHash!1, s.xxh32, s.hashOf));
	
	
	uint h;
	void f0(){ h += data.map!(djb2Hash!0).sum; }
	void f1(){ h += data.map!(djb2Hash!1).sum; }
	void f2(){ h += data.map!(sdbmHash!0).sum; }
	void f3(){ h += data.map!(sdbmHash!1).sum; }
	void f4(){ h += data.map!(xxh32).sum; }
	void f5(){ h += data.map!(hashOf).sum; }
	void f6(){ h += data.map!(tokenHash).sum; }

	import std.datetime.stopwatch;
	benchmark!(f0, f1, f2, f3, f4, f5, f6)(1000).each!print;
}

template tokenHash(string s){
	enum tokenHash = djb2Hash(s);
}

auto indexOfToken(string[] tokens)(string s){
	enum len  = 0 ~ tokens.map!(t => t.length).array;
	//opt:array of struct instead of struct of arrays
	
	foreach(i; 0..s.length)
		if(auto t = s[i..$].startsWithToken!tokens) 
			return IndexOfToken(t, i, len[t]);
			
	return IndexOfToken(0, s.length, 0);
}

/*immutable EofTokens = ["\0", "\x1A", "__EOF__"].tmPreserve;
//note: __EOF __ can be only detecrted in structured parts, comments and tokenStrings. But not is string literals.
pragma(msg, "   __EOF__".indexOfToken!([`(`, `{`, `[`, "/*", "/+", "//".tmPreserve, `'`.tmPreserve, `"`, "`", "r\"", "q\"", "q{", `#line `, `#!`, `)`, `}`, `]`,]	 ~ EofTokens));
pragma(msg, extractTokenChars([`(`, `{`, `[`, "/*", "/+", "//".tmPreserve, `'`.tmPreserve, `"`, "`", "r\"", "q\"", "q{", `#line `, `#!`, `)`, `}`, `]`,]	 ~ EofTokens).length);*/

struct StructureNode{
	StructureNode[] subNodes;
	string data;	//type specific data
	StructureType	type; 
	ubyte depth; //1 based, not updated by the parser.
	ushort wParam;
	uint line, column; //1 based, not updated by the parser.
	uint lParam;
	
	string subNodesSourceText(){
		return subNodes.map!(n => n.sourceText).join;
	}
	
	string sourceText(bool pretty=false)(){
		with(EgaColor!pretty)
	
		//black blue green cyan red magenta brown white gray ltBlue ltGreen ltCyan ltRed ltMagenta yellow ltWhite
		
		with(StructureType) switch(type){
			case(unstructuredText)	: return gray(data);
			case(structuredText)	: return white(data) ~ subNodesSourceText;
			case(cComment)	: return magenta("/*" ~ data ~ "*/");
			case(slashComment)	: return magenta("//" ~ data ~ "\n"); //todo: get default newline from somewhere
			case(dComment)	: return magenta("/+" ~ data ~ subNodesSourceText ~ "+/");
			default	: return "!!!!!!!!!!!!NOTIMPL!!!!!!!!!!!!!!";
		}
	}
	
	string prettyText(){ return sourceText!true; }
}
static assert(StructureNode.sizeof == 48);

StructureNode[] parse(StructureType T)(ref string src)
{
	StructureNode[] res;
	
	static if(T==StructureType.unstructuredText){{
		if(src.length){
			res ~= StructureNode([], src, T);
			src = "";
		}
	}}else static if(T==StructureType.slashComment){{
		auto f = src.indexOfToken!(["\r", "\n", "\u2028", "\u2029", "\0", "\x1A", "__EOF__"]);
		res ~= StructureNode([], f.fetchSS(src), T);
	}}else static if(T==StructureType.cComment){{
		auto f = src.indexOfToken!(	["*/", "\0", "\x1A", "__EOF__"]);
			//1    2    3        4
		if(f.tokenIdx==1){
			res ~= StructureNode([], f.fetchSE(src), T);
		}else{
			//Unexpected EOF
			res ~= StructureNode([], f.fetchSS(src), T);
		}
	}}else static if(T==StructureType.dComment){{
		auto f = src.indexOfToken!(	["+/", "/+", "\0", "\x1A", "__EOF__"]);
			//1    2    3    4        5
		if(f.tokenIdx==1){ //close
			res ~= StructureNode([], f.fetchSE(src), T);
		}else if(f.tokenIdx==2){ //open new
			res ~= StructureNode([], f.fetchSE(src), T);
			res ~= StructureNode(src.parse!T, "", T);  //recursion!!!!
		}else{
			//Unexpected EOF
			res ~= StructureNode([], f.fetchSS(src), T);
		}
	}}else static if(T==StructureType.structuredText){{
		while(src.length){
			auto f =	src.indexOfToken!(	[`(`, `{`, `[`, "/*", "/+", "//", `'`, `"`, "`", "r\"", "q\"", "q{", `#line `, `#!`, `)`, `}`, `]`, "\0", "\x1A", "__EOF__"]);
				//1  2	3  4    5   6  7  8  9 10	11	12   13	14 15 16 17  18   19    20 
			
			//read it until the token, store it as structuredText, then seek to the token
			if(f.tokenStartIdx>0){
				auto tmp = src[0..f.tokenStartIdx];
				src = src[f.tokenStartIdx..$];
				f.tokenStartIdx = 0;
				
				res ~= StructureNode([], tmp, StructureType.structuredText);
			}
			
			switch(f.tokenIdx){
				case 4: f.skip(src);	 res ~= src.parse!(StructureType.cComment	); break;
				case 5: f.skip(src);	 res ~= src.parse!(StructureType.dComment	); break;
				case 6: f.skip(src);	 res ~= src.parse!(StructureType.slashComment	); break;
				default: res ~= StructureNode([], src, StructureType.unstructuredText); src = "";
			}
		}
	}}else{{ 
		static assert(0, "Unhandled: "~T.stringof);
	}}
	
	return res;
}

void testParse(StructureType T)(string src){
	print("parsing:", src.quoted);
	auto res = src.parse!T;
	res.prettyText.print;
	res.each!print;
	print("remaining:", src.quoted);
	print;
}




/+StructureNode[] parse(StructureType T : StructureType.structuredText)(ref string src){
	StructureNode[] res;
	
	void emit(StructureNode n){ res ~= n; }
	void emit(StructureNode[] n){ res ~= n; }
	
	void appendStructured(){
		if(idx>0){ 
			emit(StructureNode([], src[0..idx], StructureType.structuredText));
			src = src[idx..$];
		}
	}

	while(src.length){
		//Detect the start of any structural thing
		auto idx = CharDetector_structured.countUntilChar(src);
		
		void detectAfterIdx(){
			if(idx+1<src.len){
				idx2 = CharDetector_structured.countUntilChar(src[idx+1..$]);
				idx = idx2>=0 ? idx+1+idx2 : -1;
			}else{
				idx = -1;
			}
		}
		
		again:
		
		if(idx<0){ //there is no structured elements at all. Emit the whole string as structured.
			idx = src.length;
			appendStructured;
			break;
		}
		
		char ch(int ofs=0)(){ src.get(idx+ofs); }
		switch(ch){
			case `/`:
				switch(ch!1){
					case `/`: appendStructured; emit( parse!StructureType.slashComment(src)	); break;
					case `*`: appendStructured; emit( parse!StructureType.cComment(src)	); break;
					case `+`: appendStructured; emit( parse!StructureType.dComment(src)	); break;
					default: detectAfterIdx; goto again;
				}
			break;
			default: detectAfterIdx; goto again;
		}
	}
	
	return res;
}+/

string sourceText	(R)(R r){ return r.map!"a.sourceText".join; }
string prettyText	(R)(R r){ return r.map!"a.prettyText".join; }


void main(){ console({
	testHashes;
	
	testTokenStateProcessor;
	/+
	"slashComment1".testParse!(StructureType.slashComment);
	"slashComment2\n".testParse!(StructureType.slashComment);
	"slashComment2__EOF__".testParse!(StructureType.slashComment);

	"cComment1\n*/".testParse!(StructureType.cComment);
	"bad cComment2\n__EOF__".testParse!(StructureType.cComment);
	
	immutable testSource = q{
		/* cComment */ blabla //slashComment
		/+ /+ nested dComment +/ /+ dComment2 +/+/
		
	};

	testSource.testParse!(StructureType.structuredText);
	
	//T0; DT.print;+/
});}