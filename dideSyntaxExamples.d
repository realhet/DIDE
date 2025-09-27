module dideSyntaxExamples; 

version(none) : 
struct TestCodeStruct
{
	unittest { hello; } public mixin template TestMixinTemplate() { int a; int b; } 
	public template TestTemplate() { int a; int b; } 
	public alias aaa = TestClass2; 
	public enum TestEnum = 5, TestEnum2 = 6; 
	public enum TestBlock : int { a = 5, b = a} 
	public struct TestStruct { int a; int b; } 
	public union TestUnion { int a; int b; } 
	public class TestClass1 { int a; int b; } 
	public class TestClass2 :	TestClass1 {} 
	public interface TestInterface { int a(); int b(); } 
	public: 
	public {
		public int kkk; 
		public int iii=5, jjj=6; 
		const xxxx0 = 0x0.5p3; 
		public int function() funcptrdecl; 
		public int forward(); 
		public int hello() { label1: label2: return 1 ? 2 : 3; } 
	} 
	
	struct OpaqueStruct; union OpaqueUnion; class OpaqueClass; interface OpaqueInterface; 
	struct OpaqueStruct2(T); union OpaqueUnion2(T); 
	
	static if(1==1) : 
	
	struct SSSS1 {
		static if(0) private: public:  //must encapsulate only "private:" 
		
		invariant { test; } 
	} 
} version(abcd)
{
	//nothing
}
else debug
{
	
	int testStatements()
	{
		ivec2 v2 = {[1, 2]}; 
		with(TestClass2) static int i=5; 
		with(TestClass1)
		{
			if(1==2) {}else {}
			if(1==2) sleep(1); else {}
			if(1==2) {}else sleep(1); 
			if(1==2) {}else if(2==3) {}else sleep(1); 
			
			for(int i; i++; i<10) writeln(i); 
			label1: foreach(i; 0..10) { writeln(i); break label1; }
			static foreach_reverse(i; 0..10) { { writeln(i); continue; }}
			while(0) {}
			do sleep(1); while(0);     
			do { sleep(1); }while(0);     
			
			switch(5) {
				case 6: break; 
				case 7: ..case 9: break; 
				case 10, 11, 12: break; 
				default: 
			}
			
			return typeof(return).max; 
			
		}with(TestClass1)
		{
			/+
				Todo: the next comment is handled badly (lost):
				Ctrl+C puts it after the else
				After reload it disappears
			+/
			static if(0) label1: label2: writeln; 
			else
			label3: label4: { label5: }
			  
			
			if(0) a; else b; 
			if(0) a; else if(0) b; else c; 
			//if(0) if(0) a; else b; //else is dangling
			//if(0) if(0) { a; }else b; //else is dangling
			if(0) { if(0) a; }else b; 
			if(0) { if(0) a; else b; }
			if(0) { if(0) a; else b; }else c; 
			
			
			//horizontal
			
			if(0) {/*comment05*/ block; }
			
			if(0/*comment06*/) { block; }
			
			if(0/*comment07*/) statement; 
			
			if(0/*comment08*/) statement; 
			
		}with(TestClass1)
		{
			//vertical
			
			if(
				0//comment01
			)
			{ block; }
			
			if(0) {
				 //comment02
				block; 
			}
			
			if(0) {
				 //comment03
				block; 
			}
			
			if(0/+comment04+/) { block; }
			
			if(0/*comment09*/)
			statement; 
			
			if(0/*comment10*/)
			statement; 
			
			if(0/*comment11*//*comment12*/)
			statement; 
			
			if(0) {
				 stm; 
				stm2; 
			}
			
		}with(TestClass1)
		{
			//if else variations
			
			if(0) bla; else bla; 
			
			if(0) {}else {}
			
			if(0/*comment20*/) {}else {}
			
			if(
				0//comment21
			)
			{}
			else
			{}
			
			if(0) {}else
			{}
			
			if(0) {}else
			{/*comment23*/}
			
			if(0) {}else if(0) {}else {}
		}with("if else newLine combinations")
		{
			if(0) {}else {}//OK 00 00
			
			if(0)
			{}else {}//OK 10 00
			
			if(0) {}
			else {}//FIXED 00 11  (extra NL after "else")
			
			if(0)
			{}
			else {}//FIXED 10 11  (extra NL after "else")
			
			if(0) {}else
			{}//OK 00 10
			
			if(0)
			{}else
			{}//OK 10 10
			
			if(0) {}
			else
			{}//OK 00 11
			
			if(0)
			{}
			else
			{}//OK 10 11
		}with(TestClass1)
		{
			{ {}}
			{ {}}
			{ {}}
			{ {}}
			
			
			//fixed bug: extra new line at the end of this if. The unwanted extra newline is before the else.
			if(0) {
				if(0) {}
				else {}
			}
			//this way it's ok
			if(0) { if(0) {}else {}}
			
			version(/+$DIDE_REGION+/all) {
				c = a + 5; //enabled region
			}
			
			version(/+$DIDE_REGION+/none) {
				c = a + 5; //disabled region
			}
			
			version(/+$DIDE_REGION This is the title+/all) {
				c = a + 5; //enabled region with title
			}
			
			version(/+$DIDE_REGION This is the title+/none)
			{
				c = a + 5; 
				//disabled region with title
			}
			
			/+$DIDE_IMG icon:\.txt+/
		}with(TestClass1)
		{
			//Todo: parse this correctly:
			if(1) labe3: label2: 1 ? f, f : f, f, i=5;  
			
			
			//Todo: Extra empty statement at the end.  Must distinguish "while();" and "do ; while();}
			do {}while(0);     
			
			
			//Todo: do-uble bad parsing
			double f() { return 0; } 
			
			
			//Todo: this if else looks bad
			if(1) a; 
			else b; 
			
			//Todo: make this look good
			if(1) delta = 0; 
			else
			beep; 
			
			
			//Todo: make this look good
			if(isDLangIdentifierStart(ch)) s = 'a'; 
			else if(isDLangNumberStart(ch)) s = '0'; 
			else s = ' '; 
			
			//fixed: joinPreposition is WRONG!!!!!
			if(1) { if(2) a; }else b; //bad: else goes inside the explicit {} block
			//if(1) if(2) a; else b; //good + Warning  dangling else
			if(1) { if(2) a; else b; }//good
		}
	} 
	
	debug(blabla) : 
}
else
{
	
	auto testfun = (){
		//Todo: process lambda's  =>{ or (){ , but not ={
		do sleep(1); while(0);     
	}; 
}version(none) {
	//static initializer vs labmda
	
	auto l1 = { lambda1; }; 
	auto l2 = [{ lambda2; }  ]; 
	auto l3 = ({ lambda3; }  ); 
	auto l4 = b({ lambda4; }  ); 
	auto l5 = { lambda5; }  (); 
	auto l5 = (){ lambda6; }  (); 
	auto l6 = ()=>{ lambda7; }	 (); 
	auto l7 = a=>{ lambda7; }	 .b; 
	
	auto f() => x; 
	auto f()
	=> x; 
	
	auto f() => x+
	y; 
	auto f()
	=> x+
	y; 
	
	struct S { int i; } /+Extra semicolon+/; 
	S s1 = {}; 
	S s2 = { 5}; 
	S[] s1 = [4, { 5}]; 
	S[] s1 = [{ 5}]; 
	S[] s1 = [{ 5}, { 6}]; 
	S[] s2 = b({ lambda4; }  ); 
	struct T { S s; } 
	T[] t1 = [{ { 5}}  ]; /+
		Todo: this is clear that the innermost block is not 
		a statement/declaration block. 
		It should use normal CodeBlock instead of Declaration.
	+/
	T[] t1 = [{ { 5,6}}  ]; 
	
	struct S { int a, b, c, d = 7; } 
	S s = { a:1, b:2}; 
	S u = { 1, 2}; 
	S v = { 1, d:3}; 
	S w = { b:1, 3}; 
	S w = {b:1, {}}; 
	S w = { {/+nothing+/}}; 
	void a() { static if(5) { {/+nothing+/}}} 
	
}version(none) {
	//test do/while
	void xx()
	{
		do a; while(1); 
		
		do {}while(1); 
		
		do
		{ xyz; }while(1); 
		
		do {}
		while(1); 
		
		do
		{}
		while(1); 
		
		do
		{}
		while(1); 
		{}
	} 
	
	//constraint if
	void f1(int N)()
	if(N & 1)
	{} 
	
	void fun()()
	if(true)
	in(true)
	out(; true)
	out(a; true)
	in{ x; }  
	out{ y; }  in{ x; }  //c1
	/+c7+/out(aaa)/+c2+/{ y; }  //c3
	do/+c4+/
	{ z; } 
	
	void fun2() {
		//done is not do bug. Keyword detection must detect whole words.
		done(5); 
		
		if(
			1
						//fixed: this comment has too much tabs in front of itself
		) {}
		if(
			1
			//this way it's ok
		) {}
		
		if(
			1//a
			//b
		)
		{/+c+/}
		
	} 
}version(none) {
	void multilineStringText()
	{
		//comment to makeit harder
		return r"
" ~ q{
			tokenString; 
			
			isStillIndented; 
		} ~ "
l1
l2
"; 
	} 	 struct StylisticBugs
	{
		string infiniteTabsBug()
		{
			string[] a = r.array; 
			
			foreach(i; 0..a.length.to!int-1)
			{
				const 	n0 = a[i  ].endsWith(newLine),
					n1 = a[i+1].startsWith(newLine); 
				if(n0 && n1)
				{
					a[i] = a[i][0..$-newLine.length]; //remove a newLine when there are 2
				}
				else if(!n0 && !n1)
				{
					  //add a newLine when there are 0
					a[i] ~= newLine; 
				}
			}
			
			return a.join; 
		} 
		struct divergentTabsBug()
		{
			//CellPath ///////////////////////////////
			
			auto byPathElements()
			{
				return path	.a
					.b; 
			} 
			
		} 
		void userTabs()
		{
			if(lookingForWords || lookingForSpaces)
			{
				const cnt = 	CharFetcher(c, dir>0)
					.drop(dir<0 ? 1 : 0)
					.chain("+"d) //extend with a dummy symbol to stop at
					.countUntil!(
					ch => 	lookingForWords	? !isWord(ch)
						: lookingForSpaces 	? !isSpace(ch)
						: true
				); 
				if(cnt>0)
				c.moveRight(dir*cnt); 
			}
		} 
		void manyTabs()
		{
			bool again; 
			do {
				actEvent = actEvent.items.back; //choose different path optionally
				
				again = false; 
				final switch(actEvent.type)
				{
					case EventType.modified: 	actEvent.modifications.each!execute; break; //it's in reverse text selection order.
					case EventType.saved: 	again = true; break; //nothing happened, "save event" is it's just a marking for the user
					case EventType.loaded: 	reload(
						actEvent.modifications[0].modifications[0].where,
						actEvent.modifications[0].modifications[0].what.decodePrevAndNextSourceText[1]
					); break; 
						//Todo: ^^^^ ugly and needs range check
				}
			}
			while(again && canRedo);     
		} 
	} 	 version(/+$DIDE_REGION Comments+/all)
	{
		//Slah comment
		/*C comment*/
		/+D comment+/
		/+
			Another D comment 
			/+Nested D comment+/
			//Slash commments doesn't nest
			/*Neither C comments*/
		+/
		
		//Todo: todo comment
		//Opt: opt comment
		/+Bug: bug comment+/
		/+Note: note comment+/
		//Link: link comment http://google.com
		/*Error: error comment*/
		//Exception: exception comment
		/*Warning: warning comment*/
		//Deprecation: deprecation comment
		/+Code: if(1 + 1 == 2) print("xyz");+/
		//Console: console comment
		
		/+
			Code: this is code /+
				nested comment,
				and code:/+Code: 1+1+/
			+/ ~ "45"
			void main()
			{ writeln("Hello World"); } 
		+/
		
		auto _testDirectives()
		{
			q{
				#directive
				#! shebang
				#line 5
				#define variable (1 + 2) * 3
				#ifdef cond
				#else
				#
				
				; 
			}; 
			
			/+
				surrounding stuff is necessary in order
				to turn on tokenString's statement parser.
			+/
		} 
		
		//Special DIDE comments
		
			//Region comment is only meaningful inside version() expression.
			//no spaces allowed around "all" or "none" keywords.
				version(/+$DIDE_REGION region+/all/+Extra coment/whitespace is illegal here.+/) {}
				version(/+$DIDE_REGION region+/all) {}
			
			//Image comment   $DIDE_IMG filename
				//Image	 $DIDE_IMG "font:\Times New Roman\48?Abc"
				//Image	 $DIDE_IMG "font:\Arial\48?Abc✏"
				/+$DIDE_IMG "font:\Times New Roman\48?Abc"+//+$DIDE_IMG "font:\Arial\48?Abc✏"+/
			
			//Code Location comment:  $DIDE_LOC filename(line,col)
				//$DIDE_LOC filename(line,col)  Code location comment
				//$DIDE_LOC filename.d(123,456)
				/*$DIDE_LOC c:\path\filename.d(123)*/
				/+$DIDE_LOC c:\path\filename.d()+/
				/+$DIDE_LOC c:\path\filename.d+/
				/+$DIDE_LOC filename.d-mixin-96(123,456)+/
			
			//Compiler messages   $DIDE_MSG
				//$DIDE_MSG text  Compiler message comment
				//$DIDE_MSG text  Compiler message comment
				/+
			$DIDE_MSG /+$DIDE_LOC c:\d\work.d(15,3)+/ Error blalba
			bla
		+/
		
		
		//DDoc comments
		
			/// This is a one line documentation comment.
			
			/** So is this. */
			
			/++ And this. +/
			
			/*
			*
				   This is a brief documentation comment.
		*/
			
			/*
			*
				 * The leading * on this line is not part of the documentation comment.
		*/
			
			/*
			********************************
						 The extra *'s immediately following the /** are not
						 part of the documentation comment.
		*/
			
			/+
			+
				   This is a brief documentation comment.
		+/
			
			/+
			+
				 + The leading + on this line is not part of the documentation comment.
		+/
			
			/+
			++++++++++++++++++++++++++++++++
						 The extra +'s immediately following the / ++ are not
						 part of the documentation comment.
		+/
			
			/**************** Closing *'s are not part *****************/
	}void anonymClassesMain()
	{
		import std.stdio: write, writeln, writef, writefln; 
		#line 1
		interface I
		{ void foo(); } 
		
		auto obj = new class I
			{
			void foo()
			{ writeln("foo"); } 
		}; 
		obj.foo(); 
		
		//Todo: it won't detect the 'class' because the '=' symbol.
	} version(none)
	{
		void NiceExpression_showcase()
		{
			//Note: this is deprecated. There is a new Table based showcase.
			
			(magnitude(a)) (normalize(a)) ((a).dot(b)) ((a).cross(b)) ((v).名!q{n}) (RGBr, g, b)
			((a)*(b)) ((a)/(b)) ((a)^^(n)) ((a).root(n)) (sqrt(a))  (RGBAr, g, b, a)
			((c)?(t):(f)) ((c) ?(t):(f)) ((c)?(t) :(f)) ((c) ?(t) :(f)); 
			
			//Note: scalar operations
			((2)*(x)); 	/+multiplication: ((a)*(b))+/ //Todo: more than 2 factors: ((a)*(b)*(c)*...)
			((divident)/(divisor)); 	//divide: ((divident)/(divisor))
			((base)^^(exponent)); 	//power: ((base)^^(exponent))
			((radicand).root(index)); 	//root: ((radicand).root(index))
			(sqrt(base)); 	//sqrt: (sqrt(base))
			((-b - (sqrt(((b)^^(2)) - 4*((a)*(c)))))/(((2)*(a)))) + ((1)/(((x)^^(2)))) + ((125).root(5)); 
			//((-b - (sqrt(((b)^^(2)) - 4*((a)*(c)))))/(((2)*(a)))) + ((1)/(((x)^^(2)))) + ((125).root(5))
			
			//Todo: relational operations
			((a).inRange(b, c)); 	//((a).inRange(b, c))
			((a)<(b)&&(b)<(c)); 	//((a)<(b)&&(b)<(c))
			
			//Note: vector algebra
			(magnitude(a)); 	//magnitude: (magnitude(a)) a: scalar or vector
			(normalize(vector)); 	//normalize: (normalize(vector))
			((a).dot(b)); 	//dot: ((a).dot(b))
			((a).cross(b)); 	//cross: ((a).cross(b))
			
			//Note: color constants
			(RGB(68, 255,		 0)), (RGB(.5, 1, 0)), (RGBA(0xFF00FF80)),
			(RGB(68, 255,		 0)), (RGB(.5, 1, 0)), (RGBA(0xFF00FF80)); 
			//Todo: Should go inside enum; !!!
			
			
			//Note: named parameters
			Text(((clRed).名!q{fontColor}), (((RGB0xFF0040)).名!q{bkColor}), "text"); //Todo: multiline style
			//Text(((clRed).名!q{fontColor}), (((RGB(0xFF0040))).名!q{bkColor}), "text"); 
			
			//Note: tenary operator
			((condition)?(exprIfFalse):(exprIfTrue)); 	//tenary: ((condition)?(exprIfTrue):(exprIfFalse))
			((condition) ?(exprIfFalse):(exprIfTrue)); 	//tenary: ((condition) ?(exprIfTrue):(exprIfFalse))
			((condition)?(exprIfFalse) :(exprIfTrue)); 	//tenary: ((condition)?(exprIfTrue) :(exprIfFalse))
			((condition) ?(exprIfFalse) :(exprIfTrue)); 	//tenary: ((condition) ?(exprIfTrue) :(exprIfFalse))
			
			//Todo: this should be marked with different desing: bright colors and black text.
			//Todo: Also the namedParameter's title should be plack.
			
				
			((x).PR!(/++/)); 	//probe: ((x).PR!(`result text`))
			
			auto a = (mixin(體!(RGB,q{red: 29, green: 255, blue: 50}))); 	/+/+Code: auto a = (mixin(體!((Type),q{StructInitializer})));+/+/
			auto a = (mixin(舉!(GPUVendor,q{AMD}))); 	/+/+Code: auto a = (mixin(舉!((Type),q{EnumProperty})));+/+/
			auto a = (mixin(幟!(CardSuit,q{hearts | caro}))); 	/+/+Code: auto a = (mixin(幟!((Type),q{Flags})));+/+/
			
			auto a = 	(cast(shared int)(1.5f+rnd(3))) +
				(cast (shared int)(1.5f+rnd(3)+blablabla)); /+
				/+Code: (cast(type)(expr))+/
				/+Code: (cast (type)(expr))+/
			+/
			
			//Todo: (mixin(...)) -> File(`...`)
			
			auto DFT(T)(in T[] x, float k)
			{
				const N = (cast(int)(x.length)); 
				return (mixin(和!(q{n=0},q{N-1},q{x[n] * ((ℯ)^^(-i*2*π*((k)/(N))*n))}))); 
			} 
		} 
	}version(none)
	{
		void main()
		{
			string[5] x; auto a(bool b) => ((b)?('✅'):('❌')); 
			mixin(求each(q{i=0},q{4},q{
				((0x3CE55951ECFD).檢(mixin(指(q{x},q{0})) ~= a(mixin(界0(q{1},q{i},q{4 }))))),
				((0x3D3C5951ECFD).檢(mixin(指(q{x},q{1})) ~= a(mixin(界1(q{1},q{i},q{4 }))))),
				((0x3D935951ECFD).檢(mixin(指(q{x},q{2})) ~= a(mixin(界2(q{1},q{i},q{4 }))))),
				((0x3DEA5951ECFD).檢(mixin(指(q{x},q{3})) ~= a(mixin(界3(q{1},q{i},q{4 }))))),
				((0x3E415951ECFD).檢(mixin(指(q{x},q{4})) ~= a(mixin(等(q{2},q{i},q{4-i})))))
			})); 
		} 
	}version(none)
	{
		
		/+
			Note: MixinDeclaration:	mixin ( ArgumentList ) ;
			MixinType:    	mixin ( ArgumentList )
			MixinExpression:    	mixin ( ArgumentList )
			MixinStatement:    	mixin ( ArgumentList ) ;
			
			Detection:
				Detect "mixin" keyword before ()
				That CAN substituted into a niceExpression block.
				Must be processed inside Statements and Expressions. (goInside = Expression)
		+/
		
		/+0:+/mixin("string mixin as declaration");  //wrongly detected mixin statement.  Extra space in it. But it's OK
		const mixin("string mixin as type") name; 
		const a = mixin("string mixin expression"); 
		const a = mixin("string mixin type")(mixin("string mixin expression1")+mixin("string mixin expression1")); 
		mixin 
		/+comment+/
		(); void f(mixin("arg"))
		{
			mixin("123").xyz; 
			(mixin("123").xyz); 
		} 
		
		
		/+
			Note: TemplateMixinDeclaration:  /+Link: -> DIDE.Declaration+/
			    mixin template Identifier TemplateParameters Constraintopt { DeclDefsopt }
			
			TemplateMixin: 
						 mixin MixinTemplateName TemplateArgumentsopt Identifieropt ;
						 mixin Identifier = MixinTemplateName TemplateArgumentsopt ;
			
			MixinTemplateName:  /+It NEVER starts with ()+/
						 . MixinQualifiedIdentifier
						 MixinQualifiedIdentifier
						 Typeof . MixinQualifiedIdentifier
			
			MixinQualifiedIdentifier:
						 Identifier
						 Identifier . MixinQualifiedIdentifier
						 TemplateInstance . MixinQualifiedIdentifier
		+/
		
		public alias aliasStatement = aa; 
		static enum enumStatement; 
		mixin(blabla) name/+this is a string mixin, not a mixin template+/; 
		mixin mixinStatement/+this is a mixin template+/; 
		static immutable mixin SimpleTemplate /+this one is NOT detected+/; 
		public mixin TemplateMixin_with_visibility; 
		mixin .modul.TemplateName!(arg1, mixin("arg2")); 
		mixin .modul.TemplateName!(arg1) instanceName2; 
		/+
			1.40 doesn't support this -> 
			/+Code: mixin instanceName3 = .modul.TemplateName!(arg1); +/
		+/
		
		
		static if(0)
		{
			pragma(msg, 123); 
			static	int i=5 ~ __traits(
				compiles, {
					int i = 123+256; 
					if(i>2) { beep; }
				}
			); 
		}
		string a = q{
			mixin(); 
			return; 	return a; 
			continue; 	continue a; 
			break; 	break a; 
			goto case; 	goto case a; 
			goto; 	goto a; 
			enforce(a, msg); 
			assert(a, msg); 
			static assert(a, msg); 
		}; 
	}version(none)
	{
		auto tables = 
		q{
			mixin 
			(
				/+saved:9132  loaded:9132+/
				(表([
					[q{/+Note: Type+/},q{/+Note: Bits+/},q{/+Note: Name+/},q{/+Note: Def+/}],
					[q{ubyte},q{2},q{"red"},q{3}],
					[q{ubyte},q{3},q{"green"},q{}],
					[q{ubyte},q{2},q{`blue`},q{3}],
					[q{bool},q{1},q{"alpha"},q{1}],
				]))
				/+saved:9140  loaded:9142+/
				.GEN_bitfields 
				/+Bug: Table adds extra lineIndices after right load.+/
			); 
		}~
		q{
			/+saved:9163  loaded:9165+/
			((){with(表([
				[q{/+Note: Cell Type+/},q{/+Note: Entry+/},q{/+Note: Storage+/},q{/+Note: Display+/}],
				[q{Expression / Code},q{"(1+2)*3"},q{"q{(1+2)*3}"},q{(1+2)*3}],
				[q{String literal},q{"`string`"},q{"q{`string`}"},q{`string`}],
				[q{Comment},q{"/+comment+/"},q{"q{/+comment+/}"},q{/+comment+/}],
				[q{Image},q{`/+$DIDE_IMG icon:\.txt+/`},q{`q{/+$DIDE_IMG icon:\.txt+/}`},q{/+$DIDE_IMG icon:\.txt+/}],
				[q{Nested Table},q{"It's complicated..."},q{"..."},q{
					(表([
						[q{/+Note: Type+/},q{/+Note: Bits+/},q{/+Note: Name+/},q{/+Note: Def+/}],
						[q{ubyte},q{2},q{"red"},q{3}],
						[q{ubyte},q{3},q{"green"},q{}],
						[q{ubyte},q{2},q{`blue`},q{3}],
					]))
				}],
				[q{
					Second Nested Table
					aligned to the first one
				},q{"more complicated..."},q{"..."},q{
					(表([
						[q{/+Note: Type+/},q{/+Note: Bits+/},q{/+Note: Name+/},q{/+Note: Def+/}],
						[q{bool},q{1},q{"al"~"pha"},q{1}],
						[q{/+Default color: Fuchsia+/}],
					]))
				}],
				[q{bad syntax},q{"1+(2"},q{"q{/+Error: ...+/}"},q{/+Error: 1+(2+/}],
				[],
				[q{/+^^ Empty line     Also this is a single line comment.+/}],
				[q{/+
					Warning: Use /+Code: Tab+/ to enter more than one entries.
					Multiline entries are not supported yet: /+Code: NewLine+/s are treated as table row boundaries only.
				+/}],
			])){
				/+Here comes the program that generates a string from the table.+/
				return rows.map!(
					r=>format!"%s %s%s;"(
						r.get(0), r.get(1), 
						((r.length>2) ?("="~r[2].inner):(""))
					)
				).join; 
			}}())
			/+saved:9204  loaded:9220+/
		}; 
	}
}
debug debug = hehehe; else version = hahaha; 

static if(
	0/*skipped comment*///after a newline too
)
static foreach(ch; ['a', 'b']) : //this must be the last test
		mixin(format!"enum testEnum", ch, "='", ch, "';"); 
		pragma(msg, mixin("testEnum", ch)); 
//c
//d