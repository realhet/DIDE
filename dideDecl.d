module didedecl; 

import didebase, het.parser; 
import diderow : SourceTextBuilder; 
import didenode : NodeStyle, specialCommentMarker, CodeBlock, CodeComment, CodeString; 
import dideexpr : NiceExpression, processNiceTemplateMixinStatement, processNiceStatementRow, processNiceExpressionBlock; 

version(/+$DIDE_REGION+/all) {
	deprecated struct DDeclarationRecord {
		string type; 
		string header; 
	} 
	DDeclarationRecord[] dDeclarationRecords; 
	
	version(/+$DIDE_REGION keyword tables+/all)
	{
		static immutable namedSymbols =
		[
			 //["none", ""] is mandatory
			["none", ""],	["semicolon", ";"],	["colon", ":"],	["comma", ","],
			["equal", "="],	["question", "?"],	["block", "{"],	["params", "("],
		]; 
		
		static immutable sentenceDetectionRules =
		[
			["; = ? alias import", ";"],
			["{ unittest invariant", "{"],
			["enum struct union class module interface template", "; {"],
			[":", ":"], /+Todo: Ignore this rule when "::". To support  C++ std::namespace.+/
			/+Note: template CAN have the ending: ';' -> std.typecons.isTuple +/
		]; 
		
		static immutable prepositionPatterns =
		[
			"with (",
			"for (", 	"foreach (", 	"foreach_reverse (", 	"static foreach (", 	"static foreach_reverse (",
			"while (", 	"do",			
			"version (", 	"debug (",  	"debug", 	"scope (",
			"if (", 	"static if (", 	"else if (", 	"else static if (",
			"else", 	"else version (", 	"else debug (", 	"else debug", 
			"switch (", 	"final switch (",		
			"try", 	"catch (", 	"finally",	
			"debug =",	"else debug =", //special case: debug = is a statement, not a preposition!.
			"__region", //decoded from: version(/+$D*DE_REGION title+/all)
			
			/+
				Note: mixins: String mixins are processed later, at every "()" list blocks.  
					They are transformed into a CodeBlock
				Template String mixins are processed later, the keyword "mixin" is detected before every statement; 
				/+
					Todo: String mixin detection should be done BEFORE processing prepositions.
					After mixin statement can be inserted here.
					
					Must fix attributes for mixins statement, and then 'mixin' and 'import' 
					can be handled the same way.
					Currently string imports are NOT supported.
					
					More like this: __traits(), pragma() /+pragma is problematic, it has many forms+/
					
					update: 
				+/
			+/
		]
		.sort!"a>b".array; 
		//Note: descending order is important.  "debug (" must be checked before "debug"
		
		static immutable prepositionLinkingRules =
		[
			[["do"], ["while"]],
			[["if", "static if", "version", "debug", "else if", "else static if", "else version", "else debug"], ["else", "else if", "else static if", "else version", "else debug"	]],
			[["try", "catch"], ["catch", "finally"]]
		]; 
		
		static immutable attributeKeywords =
		[
			"extern", "align", "deprecated",
			"private", "package", "package", "protected", "public", "export",
			"pragma", "static", "abstract ", "final", "override", "synchronized", "auto", "scope", 
			"const", "immutable", "inout", "shared", "__gshared", "__rvalue",
			"nothrow", "pure", "ref", "return"
		]; 
	}
	
	version(/+$DIDE_REGION keyword helper fun+/all)
	{
		//keyword helper functions ///////////////////////////////////////////////
		
		alias nameOfSymbol = arraySwitch!(namedSymbols[].map!"a[1]", namedSymbols[].map!"a[0]"); 
		alias symbolOfName = arraySwitch!(namedSymbols[].map!"a[0]", namedSymbols[].map!"a[1]"); 
		
		bool isNamedSymbol(string symbol)
		{ return namedSymbols.map!"a[1]".canFind(symbol); } 
		bool isSymbolName(string name)
		{ return namedSymbols.map!"a[0]".canFind(name); } 
		
		string toSymbolEnum(string s)
		{ return isNamedSymbol(s) ? nameOfSymbol(s) : "_"~s; } 
		
		/// do conversion from simple string symbols/identifiers to enum members
		/// "; : alias if" -> "semicolon, colon, _alias, _if"
		string toSymbolEnumList(string s)
		{ return s.split.filter!"a.length".map!toSymbolEnum.join(", "); } 
		
		
		auto genExtractIdentifiers(string ending)()
		{
			return ending.format!q{
				sentenceDetectionRules	.filter!"a[1].canFind(`%s`)".map!"a[0].split"
					.join.filter!isDLangIdentifier.array
			}; 
		} 
		
		static immutable 	prepositionKeywords 	= prepositionPatterns.map!((a)=>(a.stripRight(" (="))).array.sort.uniq.array, 
		 	blockKeywords 	= mixin(genExtractIdentifiers!"{"),
			statementKeywords 	= mixin(genExtractIdentifiers!";"); 
		
		static foreach(name; "preposition attribute statement block".split)
		{ mixin(format!q{bool is%sKeyword(string s) { return %sKeywords.canFind(s); } }(name.capitalize, name)); }
		//Opt: Use hash tables for these is*Keyword functions!
		
		auto withoutStartingSpace(Cell[][] a)
		{
			if(a.length && a.front.length) if(auto g = cast(Glyph)a.front.front) if(g.ch==' ') a.front = a.front[1..$]; 
			return a; 
		} 
		
		auto withoutEndingSpace(Cell[][] a)
		{
			if(a.length && a.back.length) if(auto g = cast(Glyph)a.back.back) if(g.ch==' ') a.back = a.back[0..$-1]; 
			return a; 
		} 
		
	}
	class Declaration : CodeNode
	{
		CodeColumn attributes; 
		string keyword; 
		CodeColumn header, block; 
		char ending; 
		bool blockHasExtraSemicolonEnding; 
		
		int internalNewLineCount, internalTabCount; //Todo: this counter only needed to count up to 2.
		
		@property bool hasInternalNewLine() const { return internalNewLineCount>0; } 
		@property bool hasInternalTab() const { return internalTabCount>0; } 
		
		bool hasJoinedNewLine, hasJoinedTab; 
		
		bool explicitPrepositionBlock; 
		
		Declaration nextJoinedPreposition; 
		
		@property isBlock() const
		=> ending=='}'; @property isStatement() const
		=> ending==';'; 
		@property isSection() const
		=> ending==':'; @property isPreposition() const
		=> ending==')'; 
		
		@property string blockEnding()
		=> ((blockHasExtraSemicolonEnding)?("};"/+for C-like languages.+/):("}")); 
		
		bool isRegion; //detected automatically
		bool regionDisabled; 
		bool isShortenedFunction; 
		
		version(/+$DIDE_REGION BuildMessage handling+/all)
		{
			CodeColumn buildMessages; 
			
			override CodeColumn* accessBuildMessageColumn()
			{ return &buildMessages; } 
		}
		
		Declaration lastJoinedPreposition()
		{
			auto d = this; 
			while(d.nextJoinedPreposition)
			d = d.nextJoinedPreposition; 
			return d; 
		} 
		
		Declaration firstJoinedPreposition()
		{
			if(!isPreposition) return null; 
			
			Declaration a = this; 
			while(1)
			{
				assert(a.isPreposition); 
				if(auto b = cast(Declaration) a.parent)
				a = b; 
				else
				break; 
			}
			return a; 
		} 
		
		Declaration[] allJoinedPrepositionsFromThis()
		{
			Declaration[] res; 
			auto act = this; 
			while(act)
			{
				res ~= act; 
				act = act.nextJoinedPreposition; 
			}
			return res; 
		} 
		
		protected void setContentParent(Declaration p)
		{
			//used to set visual parents. The actual chain is stored in the linked list: nextJoinedPreposition.
			void a(CodeColumn col) { if(col) col.setParent(p); } 
			a(attributes); 
			a(header); 
			a(block); 
		} 
		
		void appendJoinedPreposition(Declaration decl)
		{
			assert(decl && decl.isPreposition); 
			auto last = lastJoinedPreposition; 
			last.nextJoinedPreposition = decl; 
			
			decl.setParent(last); //The declaration's parent is the previous declaration
			auto root = firstJoinedPreposition; 
			decl.setContentParent(root); 
		} 
		
		Declaration nestedPreposition()
		{
			if(isPreposition)
			if(
				!explicitPrepositionBlock
				//bugfix: if(1){if(2)a;}else b;  else is wrongly moved inside blocks
			)
			if(auto a = cast(Declaration) block.singleCellOrNull)
			if(a.isPreposition)
			return a; 
			return null; 
		} 
		
		Declaration[] allNestedPrepositions()
		{
			Declaration[] res; 
			auto act = this; 
			while(act && act.isPreposition) {
				res ~= act; 
				act = act.nestedPreposition; 
			}
			return res; 
		} 
		
		bool canHaveHeader() const
		{
			if(keyword.among("else", "unittest", "invariant", "try", "finally", "do")) return false; 
			return true; 
		} 
		
		bool onlyShowHeaderWhenNotEmpty() const
		{ return !!keyword.among("return", "break", "continue", "goto case", "goto"); } 
		
		@property canHaveAttributes()const 
		=> !(
			keyword.among(
				"mixin", "return", "break", "continue", "goto case", "goto",
				"assert", "static assert", "enforce"
			)
		); 
		
		@property headerHasBrackets() const
		=> !!keyword.among("enforce","assert","static assert"); 
		/+
			Todo: when the mixinTemplate is a declaration it can be 'const' for example.
			But because of mixin(), it can't go well along whit the preposition 'system'.
			So it is just ignored.
			Existing attributes will be preserved, then the Declaration becomes a plain statement.
		+/
		
		bool isSimpleBlock() const
		{ return isBlock && keyword=="" && header.empty && attributes.empty; } 
		
		bool isFunction()
		{ return isBlock && !isRegion && keyword=="" && identifier!=""; } 
		
		
		bool isAttributeBlock()
		{ return isBlock && !isRegion && keyword=="" && identifier=="" && !attributes.empty; } 
		
		void verify()
		{
			if(isBlock)	{
				enforce(block, "Invalid null block."); 
				enforce(
					keyword=="" || keyword.isBlockKeyword, 
					"Invalid declaration block keyword: "~keyword.quoted
				); 
			}
			else if(isStatement)
			enforce(
				keyword=="" || keyword.isStatementKeyword || keyword=="mixin", 
				"Invalid declaration statement keyword: "~keyword.quoted
			); 
			else if(isSection)
			enforce(
				keyword.among(""), 
				"Invalid declaration section keyword: "~keyword.quoted
			); 
			else if(isPreposition)
			enforce(
				keyword.isPrepositionKeyword, 
				"Invalid declaration preposition keyword: "~keyword.quoted
			); 
			else
			enforce(
				0, 
				"Invalid declaration ending: "~ending.text.quoted
			); 
			
		} 
		
		this(CodeBlock b)
		{
			//promote the block.
			assert(b); 
			assert(b.parent); 
			assert(b.content); 
			assert(b.type == CodeBlock.Type.block); 
			
			super(b.parent); 
			
			attributes = new CodeColumn(this, []); 
			header = new CodeColumn(this, []); 
			block = b.content; block.setParent(this); 
			ending = '}'; 
			
			verify; 
			
			refreshLineIdx; 
		} 
		
		this(Container parent, Cell[][] attrCells, string keyword, Cell[][] headerCells, CodeColumn block, char ending)
		{
			assert(parent); 
			super(parent); 
			
			void processShortenedFunction()
			{
				if(ending==';' && keyword=="" && !block && attrCells.empty && !headerCells.empty)
				{
					bool foundListBlock; 
					foreach(y, row; headerCells)
					foreach(x, node; row)
					{
						if(auto g = (cast(Glyph)(node)))
						{
							if(g.ch=='=')
							{
								if(!foundListBlock) return; // `()` must precede `=>`
								
								if(auto g2 = (cast(Glyph)(row.get(x+1))))
								if(g2.ch=='>')
								{
									isShortenedFunction = true; 
									
									auto blockCells = headerCells[y..$]; 
									headerCells = headerCells[0..y+1].dup; 
									headerCells[y] = headerCells[y][0..x]; 
									blockCells[0] = blockCells[0][x+2..$]; 
									
									block = new CodeColumn(this, blockCells.withoutStartingSpace); 
									
									return; 
								}
								return; 
							}
							if(
								g.ch.inRange('#', ')') || g.ch.inRange('+', '-') || g.ch.inRange(':', '?') || 
								g.ch.among('/', '^', '|', '~') /+These chars aren't allowed.+/
								/+* is allowed, for pointers+/
							) return; 
						}
						else if(auto b = (cast(CodeBlock)(node)))
						{ if(b.type==CodeBlock.Type.list) foundListBlock = true; }
					}
				}
				
				/+Bug: processShortenedFunction fails with multiline header: Fucked up, growing indtents on saving.+/
			} 
			
			processShortenedFunction; 
			
			
			auto detectInternalNewLine(Cell[][] a)
			{
				if(isBlock || isShortenedFunction)
				{
					if(a.length>1 && a.back.map!structuredCellToChar.all!"a==' '")
					{
						a.popBack; 
						internalNewLineCount++; 
						/+
							Bug: It can destroy comments because 
							comments are ' ' too.
						+/
					}
				}
				return a; 
			} 
			
			this.keyword = keyword; 
			this.ending = ending; 
			this.block = block; if(block) block.setParent(this); 
			this.attributes = new CodeColumn(this, attrCells.withoutStartingSpace.withoutEndingSpace); 
			this.header = new CodeColumn(this, detectInternalNewLine(headerCells.withoutStartingSpace.withoutEndingSpace)); 
			//Note: ⚠ detectInternalNewLine() is not a pure function. The order of the operations above is important!!!
			
			decodeSpecial; 
			
			verify; 
			
			bool promoteStatement()
			{
				/+Todo: Handle attributes preceding template mixins!+/
				enforce(!block && keyword=="" && ending==';'); 
				
				bool kw_space_expr(string kw, bool canHaveVisibilityAttr = false)
				{
					auto detectVisibility()
					=> only("public", "private", "package", "protected", "export").map!q{a~' '}
					.filter!((kw)=>(header.byCell.map!structuredCellToChar.startsWith(kw))).frontOr("")
					/+Opt: these searches must be optimized with parsing, not by bumbly checking every keyword...+/
					/+Todo: mixin can suck up more attributes. For example: /+Code: static immutable mixin a;+/+/; 
					
					auto visibility = ((canHaveVisibilityAttr)?(detectVisibility):(""))/+Contains extra space+/; 
					
					if(header.byCell.map!structuredCellToChar.drop(visibility.length/+skip the attribute+/).startsWith(kw~' '))
					{
						if(visibility.length)
						{
							enforce(attributes.empty, "There are existing attributes."); 
							const lenWithoutSpace = visibility.length-1; 
							attributes = new CodeColumn(this, [header.rows[0].subCells[0 .. lenWithoutSpace]]); 
						}
						with(header.rows[0]) {
							subCells = subCells[(visibility.length + kw.length + 1).min($) .. $]; 
							refreshTabIdx; needMeasure; 
						}
						this.keyword = kw; return true; 
					}
					else
					{ return false; }
					
					/+
						Todo: mixin template with name, and assignmend syntax: 
						/+Link: https://dlang.org/changelog/2.111.0.html#dmd.mixin-assign+/
					+/
				} 
				
				bool kw_only(string kw)
				{
					if(header.byCell.map!structuredCellToChar.equal(kw))
					{
						with(header.rows[0]) {
							subCells = subCells[kw.length .. $]; 
							refreshTabIdx; needMeasure; 
						}
						this.keyword = kw; return true; 
					}else return false; 
				} 
				
				bool kw_bracket_expr(string kw)
				{
					if(header.byCell.map!structuredCellToChar.equal(kw~'('))
					{
						auto blk = (cast(CodeBlock)(header.rows[0].subCells[$-1])).enforce; 
						//LOG("BRACKET EXPR", kw, blk.sourceText); 
						header = new CodeColumn(this, blk.content.rows.map!"a.subCells".array); 
						this.keyword = kw; return true; 
					}else return false; 
				} 
				
				//Opt: make a table of this, exit faster by checking the first char(s)
				//Todo: handle .enforce too.   //for .identifier!()() there should be a shortcut!
				//Todo: detect Row({}) and Column({})
				//Todo: detect const, auto, ... declaration blocks.
				//Todo: detect throw ; statement too
				
				
				return kw_space_expr("mixin", true) 	||
				kw_space_expr("return") 	|| kw_only("return")	||
				kw_space_expr("continue") 	|| kw_only("continue") 	||
				kw_space_expr("break") 	|| kw_only("break")	||	
				kw_space_expr("goto case") 	|| kw_only("goto case")	||
				kw_space_expr("goto") 	|| kw_only("goto")	||
				kw_bracket_expr("static assert")	|| kw_bracket_expr("assert")|| kw_bracket_expr("enforce"); 
			} 
			
			//RECURSIVE!!!
			if(isBlock)
			{
				if(keyword.among("enum", "alias"))	processHighLevelPatterns_expr(block); 
				else	{
					if(header) processHighLevelPatterns_expr(header); 
					processHighLevelPatterns_block(block); 
				}
			}
			else if(isStatement)
			{
				if(isShortenedFunction)	{
					processHighLevelPatterns_expr(header); 
					processHighLevelPatterns_expr(block); 
				}
				else if(keyword.among("enum", "alias", "mixin"))	{ processHighLevelPatterns_expr(header); }
				else if(keyword=="")	{
					/+
						This calls processHighLevelPatterns_expr 
						(including mixin() detection)
						and then calls niceExpression/specialStatements
					+/
					processHighLevelPatterns_statement(header); 
					
					/+
						Mixin statement promotion is 
						called AFTER the string mixin() detection.
					+/
					if(promoteStatement)
					{
						/+
							Try to process it further:
							If rhere is a niceEXPRESSION inside,
							it will gowngrade it to simple statement
							and put the NiceExpression in it.
						+/
						processNiceTemplateMixinStatement(this); 
					}
				}
			}
			else if(isPreposition)
			{
				foreach(p; allJoinedPrepositionsFromThis)
				{
					if(p.header) processHighLevelPatterns_expr(p.header); 
					processHighLevelPatterns_block(p.block); 
				}
			}
			//Todo: in labels it must detect case: and default:!
			//Todo: In case: labels it must process expressions!
			
			refreshLineIdx; 
		} 
		
		string type()
		{
			if(keyword.length) return keyword; 
			if(isBlock || isShortenedFunction) return "function"; 
			if(isStatement	) return "statement"; 
			if(isPreposition) return "preposition"; 
			if(isSection) return "section"; 
			return ""; 
		} 
		
		char opening() const
		{
			return ending.predSwitch(
				'}', '{', 
				')', '(', 
				' '
			); 
		} 
		
		bool isLabel() const
		{
			if(!isSection) return false; 
			auto src = header.rows.map!(row => row.subCells.map!structuredCellToChar).joiner(" "); 
			
			while(!src.empty && src.front==' ') src.popFront; 
			
			if(src.empty || !src.front.isDLangIdentifierStart) return false; 
			
			string id = src.front.text; 
			src.popFront; 
			while(!src.empty && src.front.isDLangIdentifierCont)
			{
				id ~= src.front.text; 
				src.popFront; 
			}
			
			if(isAttributeKeyword(id)) return false; 
			
			if(!src.all!"a==' '") return false; //something els at the end
			
			return true; ; 
		} 
		
		private bool _identifierValid; //Todo: use Nullable!string
		private string _identifier; 
		override @property string identifier()
		{
			
			string calcIdentifier()
			{
				if(isBlock || isShortenedFunction)
				{
					if(keyword=="")
					{
						auto s = header.extractThisLevelDString.text; 
						foreach(p; s.strip.split('(').retro.drop(1))
						{
							auto q = p.strip.split!isDLangWhitespace.filter!"a.length".array; 
							if(!q.empty && !q.back.isAttributeKeyword && !q.back.among("if", "in", "do")) return q.back; 
						}
					}
					else if(
						keyword.among(
							"class", "struct", "interface", "union", 
							"template", "mixin template", "enum", "module"
						)
					)
					{
						return header.shallowText.strip.wordAt(0); 
						//Todo: this is nasty!!! Should use proper DLang identifier detection.
					}
				}
				
				return ""; 
			} 
			
			if(_identifierValid.chkSet) { _identifier = calcIdentifier; }
			
			return _identifier; 
		} 
		
		override string caption()
		{
			//Todo: cache this too
			if(isRegion) return header.sourceText; 
			return identifier; 
		} 
		
		private void decodeSpecial()
		{
			//Note: only callable from within this(), as it does not reset flags.
			
			if(isPreposition && keyword=="version" && header.rowCount==1)
			if(auto cmt = header.firstCell!CodeComment)
			if(auto optionIdx = header.shallowText.withoutStarting(compoundObjectChar).among("all", "none"))
			if(cmt.isSpecialComment("REGION"))
			{
				//Todo: Similar to regions: if(0) and if(1) should be handled to. Including their else blocks as well. +static
				
				/+
					Todo: There should be a { } region too with it's own scope.  Using first "//Title: comment".
					The {//title: } region comment makes difficulties inside preposition blocks.
				+/
				
				isRegion = true; 
				regionDisabled = optionIdx==2; 
				keyword = "__region"; 
				
				header = cmt.content; 
				header.setParent(this); 
				
				//remove the marker
				with(header.rows[0])
				{
					subCells = subCells[specialCommentMarker.length + "REGION".length .. $]; 
					if(!subCells.empty && chars[0]==' ') subCells.popFront; 
					needMeasure; 
				}
				
				return; 
			}
		} 
		
		bool isSpecial()
		{ return isRegion; } 
		private final void emitDeclaration(R)(ref R outputRange)
		{
			with(outputRange)
			{
				
				void putIndent()
				{ static if(UI) put("    "); } void putNLIndent()
				{ putNL; putIndent; } void putUI(A)(A a)
				{ static if(UI) put(a); } 
				
				void emitPreposition(Declaration decl, bool closingSemicolon = false)
				{
					with(decl)
					{
						//Note: prepositions have no attributes. 'static' and 'final' is encoded in the keyword.
						
						//Todo: put a space before 'else;   ->    if(1) { a; }else b;  
						//Todo: put a space after 'else'  if it is followed by an alphaNumeric char. -> that's compilation error
						//Todo: if(a//comment){}  <- this comment fails.
						
						
						if(canHaveHeader)
						{
							putUI(' '); 
							put(keyword); 
							
							static bool isHeaderOmittableForKeyword(string keyword)
							{
								enum list = 	prepositionPatterns.filter!(a => a.endsWith(" ("))
									.map!(a => a[0..$-2])
									.filter!(a => prepositionPatterns.canFind(a))
									.array; 
								/+
									Normally in DLang, these are the keywords having
									optionally omittable ()blocks: "debug", "else debug"
								+/
								return list.canFind(keyword); 
							} 
							
							const omitHeader = header.empty && isHeaderOmittableForKeyword(keyword); 
							//debug has an optional () block
							
							enum alwaysShowBrackets = false /+Todo: into settings...+/; 
							
							if(alwaysShowBrackets)
							{ if(!omitHeader) put("(", header, ")", true); else putUI(' '); }
							else
							{ putUI(' '); if(!omitHeader) put("(", header, ")", !UI); }
						}
						else
						{
							putUI(' '); 
							put(keyword); 
						}
						
						//Todo: detect if there is more than one statements inside. If so, it must write a { } block!
						
						if(closingSemicolon)
						{ put(';'); if(autoSpaceAfterDeclarations) put(' '); }
						else
						{
							if(internalNewLineCount > hasJoinedNewLine) { putUI(' '); putNLIndent; }
							else put(internalTabCount > hasJoinedTab ? '\t' : ' '); 
							
							/+
								Todo: ^^ ez a space lehet tab is. Ekkor az else if chain blokkjai szepen egymas 
								ala vannak igazitva. Jelenleg az if expressionja es a blokkja kozotti 
								senkifoldjen csak a space, newline es a comment 
								van detektalna (a comment az lehet, hogy nincs is!).
								Viszont legyen a tab is detektalva! Az 3 allapot.
								A tab eseten egy fel sornyi szunetet is be lehetne iktatni. 
								A space eseten ez nem kell, mert a blokk eleje is mashol lesz. 
								A newline eseten eleve ott a vastag elvalaszto sor.
								Update: Ez elvileg mar megy, de kell hozza teszteket csinalni!
							+/
							
							//Todo: there should be a tab right after the if and before the (expression).
							//Todo: I must make the rules of things that could go onto the surface of CodeNodes.
							
							put("{", block, "}", explicitPrepositionBlock); 
						}
						
						if(nextJoinedPreposition)
						{
							/+
								Bug: This bug fucks up line indexing, it add 2 exra to it.
								Test code in a .d file:
								/+
									Code: if(1)
									if(1)
									a; 
									
									//This should be line 3, but it's line 5!
								+/
								After copying it becomes:
								/+
									Code: if(1)
									if(1)
									a; 
									
									//This should be line 3, but it's line 5!
								+/
							+/
							
							if(nextJoinedPreposition.hasJoinedNewLine) { putUI(' '); putNL; }
							else if(nextJoinedPreposition.hasJoinedTab) put('\t'); 
							
							//Note: It doesn't matter if the newline is bewore or	 after or on both sides
							//Note: ...around an "else". As it is either joined horizontally or vertically.
							
							//Propagate bkColor through else chain
							nextJoinedPreposition.block.bkColor = block.bkColor,
							nextJoinedPreposition.header.bkColor = block.bkColor; 
							
							const nextClosingSemicolon = keyword=="do" && nextJoinedPreposition.keyword=="while"; 
							emitPreposition(nextJoinedPreposition, nextClosingSemicolon); //RECURSIVE!!!
						}
						else
						putUI(' '); 	
					}
				} 
				
				void emitBlock()
				{
					if(isSimpleBlock)
					{
						/+
							Todo: the transition from simpleBlock to non-simple block is not clear.
							A boolean flag is needed to let the user write into the header.
						+/
						put("{", block, blockEnding); 
						
						
						static if(false && CODE)
						{
							/+
								Note: This space can't emited in () and [] blocks, only in {} blocks,
								because it will produce endless spaces.
								But it's difficult to detect, so I rather produce { {}} and later remove the first space.
							+/
							if(autoSpaceAfterDeclarations) put(' '); 
						}
						
						/+
							Bug: Autogenerate { } after prepositions.
							It can cause nasty bugs.
							/+$DIDE_IMG: c:\dl\bigbug.png+/
						+/
					}
					else
					{
						bool needSpace; 
						if(keyword!="")
						{
							put(attributes); 
							if(!attributes.empty) put(' '); 
							
							put(keyword); 
							needSpace |= true; 
						}
						
						if(canHaveHeader)
						{
							if(needSpace.chkClear) put(' '); 
							put("", header, ""); 
							needSpace |= true; 
						}
						
						if(hasInternalNewLine)
						putNLIndent; 
						else if(needSpace.chkClear) put(' '); 
						
						put("{", block, blockEnding); 
						if(autoSpaceAfterDeclarations) put(' '); else putUI(' '); 
					}
				} 
				
				void emitRegion()
				{
					static if(UI)
					{
						if(
							!header.empty//optional header title
						)
						{
							put(header); 
							if(hasInternalNewLine) putNL; else put(' '); 
						}
						put(block); 
						//region has a thin border and no braces.
					}
					else
					{
						//verify that header is valid for a /+comment+/
						const src = header.sourceText; 
						enforce(
							isValidDLang("/+"~src~"+/"), 
							"Invalid DIDE marker format. (Must be a valid /+comment+/):\n"~src
						); 
						
						put(
							"version(/+" ~ specialCommentMarker ~ "REGION" ~ (header.empty ? "" : " "),
							header,
							"+/"~(regionDisabled ? "none":"all")~")"
						); 
						if(hasInternalNewLine) putNL; else put(' '); 
						put("{", block, "}"); 
					}
				} 
				
				void emitShortenedFunction()
				{
					put(header); 
					static if(UI)	{
						if(hasInternalNewLine) putNL; put(" ⇒ "); 
						put(block); 
					}
					else	{
						if(hasInternalNewLine) putNL; else put(' '); put("=> "); 
						auto lastRow = block.rows.back; 
						foreach(row; block.rows) { put(row); if(row !is lastRow) putNL; }
					}
					put(';'); 
				} 
				
				void emitStatementOrSection()
				{
					if(keyword!="")
					{
						if(canHaveAttributes || !attributes.empty)
						{
							put(attributes); 
							if(!attributes.empty) put(' '); 
						}
						else
						{
							putUI(' '); 
							/+no atts, just a graphical space+/
						}
						
						static if(CODE)
						{
							/+putSeparatorSpace; +/
							/+
								Todo: This ain't work.
								When I copy a letter 'A' and 
								a mixin statement,
								it becomes: /+Code: Amixin T;+/
								instead of: /+Code: A mixin T;+/
							+/
						}
						
						put(keyword); 
					}
					if(canHaveHeader)
					{
						/+
							in statements, 
							the header is the body
						+/
						if(headerHasBrackets)
						{ put("(", header, ")"~ending.text); }
						else
						{
							if(!header.empty || !onlyShowHeaderWhenNotEmpty)
							{
								if(keyword!="" && !header.empty) put(' '); 
								put("", header, ending.text); 
							}
							else
							{ put(ending); }
						}
					}
					else
					put(ending); 
				} 
				
				if(isBlock)
				{ emitBlock; }
				else if(isPreposition)
				{
					if(isRegion)	emitRegion; 
					else	emitPreposition(this); 
				}
				else
				{
					//statement or section
					if(isShortenedFunction)	emitShortenedFunction; 
					else	emitStatementOrSection; 
					
					if(autoSpaceAfterDeclarations)
					put(' '); 
					else
					{
						putUI(' '); 
						/+this space makes the border thicker+/
					}
				}
			}
		} 
		
		override void rearrange()
		{
			//_identifierValid = false;
			
			const isSimpleStatement = isStatement && keyword=="" && !isShortenedFunction; 
			
			auto builder = nodeBuilder(
				skWhitespace, ((isSimpleStatement)?(NodeStyle.dim) :(NodeStyle.bright)), 
				structuredColor(type).nullable
			); 
			with(builder)
			{
				//set subColumn bkColors
				if(isBlock || isPreposition) block.bkColor = mix(darkColor, brightColor, 0.125f); 
				else if(isShortenedFunction) block.bkColor = darkColor; 
				
				const canBeEmpty = !isPreposition; 
				foreach(a; only(attributes, header))
				if(a)
				{ a.bkColor = ((canBeEmpty && a.empty) ?(mix(darkColor, brightColor, ((isSimpleStatement)?(0.25f):(0.75f)))) :(darkColor)); }
				
				if(isPreposition && isRegion)
				header.bkColor = syntaxBkColor(skComment); 
				
				emitDeclaration(builder); 
			}
			
			super.rearrange; 
			
			mixin(求each(q{a},q{allJoinedPrepositionsFromThis},q{a.rearrange_appendBuildMessages})); 
		} 
		
		override void buildSourceText(ref SourceTextBuilder builder)
		{ emitDeclaration(builder); } 
		
		override void draw(Drawing dr)
		{
			//draw ///////////////////////////////////
			super.draw(dr); 
			
			if(isRegion && regionDisabled)
			{
				dr.color = syntaxBkColor(skComment); dr.alpha = .66; dr.fillRect(outerBounds); 
				
				dr.lineWidth = 2; 
				dr.color = syntaxFontColor(skComment); dr.alpha = .5; dr.drawX(outerBounds); 
				
				dr.alpha = 1; 
			}
		} 
		
		override @property RGB avgColor()
		{
			RGBSum sum; 
			foreach(col; only(attributes, header, block))
			if(col) sum.add(col.avgColor, col.outerSize.area); 
			sum.add(bkColor, outerSize.area-sum.totalWeight); 
			return sum.avg(bkColor); 
		} 
		
		protected void refreshLineIdx()
		{
			/+
				Note: This function refreshes the line indices of this Node and all it's first level Rows.
				It requires that the inner Nodes having their lineIndices already refreshed.
				It is only used with CodeColumnBuilder, because SourceTextBuilder is normally regenerating all the lineIndices.
				
				To debug use VisualizeCodeLineIndices=1.
				Row and Node induces should will overlap nicely with the Glyph indices,  so the first lineIndex in each row 
				must show a proper, nonzero number and ovelrapped 'R' and 'N' letters.
				Non clickable text inside Nodes will have 0 lineIdx.
				
				/+Todo: embedded bitmap advanced comment+/
				/+
					Todo: verify the result of this by comparing the produced Node, Row, Glyph lineIndices 
					of CodeColumnBuilder and SourceTextBuilder(This is the reference because it is the simplest of the two)
				+/
			+/
			
			lineIdx = 0; 
			
			foreach_reverse(col; only(attributes, header, block))
			if(col)
			{
				col.refreshLineIdx; 
				
				if(auto a = col.rows.front.lineIdx) lineIdx = a; 
			}
			
			static if(0)
			{
				/+
					Todo: There are a lot of lineIdx fails, but mostly for quite empty declarations.
					Try to solve as many as can...
					Now it's not a priority
				+/
				if(!lineIdx) {
					print("lineidx fail-----------"); 
					print(this.sourceText); 
					print("-----------"); 
					static bool a; if(a.chkSet) ERR("Declaration.lineIdx fail. ...sigh..."); 
				}
			}
		} 
		
		/+
			Todo: /+
				Code: static if(a) { a; }
				else static if(b) { b; }
				else { c; }
			+/
			The statements can be aligned with the TAB.
			But the expressions can't.
		+/
		
	} 
	version(/+$DIDE_REGION parsing helper fun+/all)
	{
		//parsing helper fun ////////////////////////////////////////////////
		
		bool isBreakRow(Row r)
		{
			//if(auto cmt = cast(CodeComment) r.subCells.backOrNull) return cmt.isSpecialComment("BR");
			if(auto g = cast(Glyph) r.subCells.backOrNull) return g.ch == '\v' /+Vertical Tab+/; 
			return false; 
		} 
		
		dchar structuredCellToChar(Cell c)
		{
			return c.castSwitch!(
				(Glyph g)	=> isDLangWhitespace(g.ch) ? ' ' : g.ch	,
				(CodeComment _) 	=> ' '	,
				(CodeString _)	=> '"'	,
				(CodeBlock b)	=> b.prefix[0]	,
				(Declaration d)	=> compoundObjectChar	,
				(NiceExpression n)	=> compoundObjectChar	,
				()	=> ' '
			); 
		} 
		
		bool isWhitespaceOrComment(Cell c)
		{
			return c.castSwitch!(
				(Glyph	g) 	=> isDLangWhitespace(g.ch)	,
				(CodeComment 	_) 	=> true	,
				(Cell	c)	=> false
			); 
		} 
		
		bool isChar(Cell c, dchar ch)
		{ if(auto g = (cast(Glyph)(c))) return g.ch==ch; return false; } 
		
		bool cellIsSpace(Cell c)
		{
			return c.castSwitch!(
				(Glyph g) 	=> g.ch==' '	,
				(Cell c)	=> false
			); 
		} 
		
		bool isWhitespaceOrComment(CodeRow row)
		{ return !row || row.subCells.all!isWhitespaceOrComment; } 
		
		
		dstring extractThisLevelDString(R)(R rng)
		{ return rng.map!structuredCellToChar.dtext; } 
		
		dstring extractThisLevelDString(CodeRow row)
		{ return row.subCells.extractThisLevelDString; } 
		
		dstring extractThisLevelDString(CodeColumn col)
		{
			//every chacacter or node maps to exactly one character (including newline)
			return col.rows.map!extractThisLevelDString.join("\n"); 
		} 
		
		
		auto removeBack(alias filter="true", R)(ref R[] rows, sizediff_t cnt)
		{ return removeFront!(filter, false, R)(rows, cnt); } 
		
		auto removeFront(alias filter="true", bool fromFront=true, R)(ref R[] rows, sizediff_t cnt)
		{
			
			struct RemovedCells {
				CodeComment[] comments; 
				Cell lastCell; 
				int newLineCount, tabCount; 
				int removedCount; 
				bool overflow; 
			} 
			RemovedCells res; 
			
			static ref Cell[] accessCells(ref R r)
			{
				static if(is(R==Cell[])) return r; 
				else static if(is(R==CodeRow)) return r.subCells; 
				else static assert(0, "Unhandled type"); 
			} 
			
			while(cnt>0) {
				if(rows.empty) { res.overflow = true; break; }
				
				static if(fromFront)
				auto actRow = accessCells(rows.front); 
				else
				auto actRow = accessCells(rows.back); 
				
				if(!actRow.empty)
				{
					//Opt: this is unoptimal but simple
					static if(fromFront)
					auto actCell = actRow.front; 
					else
					auto actCell = actRow.back; 
					
					if(!actCell.unaryFun!filter) break; 
					
					res.lastCell = actCell; //LOG(structuredCellToChar(actCell));
					if(auto cmt = cast(CodeComment) actCell)
					{ res.comments ~= cmt; }
					else if(auto glyph = cast(Glyph) actCell)
					{ if(glyph.ch=='\t') res.tabCount++; }
					
					
					static if(fromFront)
					accessCells(rows.front).popFront; 
					else
					accessCells(rows.back).popBack; 
					
					res.removedCount ++; 
				}
				else
				{
					if(rows.length>1)
					{
						static if(fromFront)
						rows = rows[1..$]; 
						else
						rows = rows[0..$-1]; 
						
						res.newLineCount ++; 
						res.removedCount ++; 
					}
					else
					{ res.overflow = true; break; }
				}
				cnt--; 
			}
			return res; 
		} 
		
	}struct TokenProcessor(Token)
	{
		//TokenProcessor /////////////////////////////////
		
		private static
		{
			//Helpers functions
			
			auto strToToken(alias E)(string s)
			{
				static assert(is(E==enum)); 
				static assert(E.none == 0); 
				
				static string strFromToken(E)(E e) if(is(E==enum))
				{
					const a = e.text; 
					if(a.startsWith('_')) return a[1..$]; 
					return a.symbolOfName; 
				} 
						
				enum 	 members = [EnumMembers!E],
					 m = assocArray(members.map!(a => strFromToken(a)), members); 
				if(auto a = s in m) return *a; 
				return E.none; 
			} 
			
			struct TokenLocation(Token)
			{
				int pos, len; Token token; 
				@property int end() const { return pos+len; } 
			} 
			
			auto findTokenLocations(Token)(dstring str)
			{
				auto res = appender!(TokenLocation!Token[]); 
				
				void tryAppend(dstring s, size_t pos)
				{
					const token = strToToken!Token(s.text); 
					//Opt: this conversion from dstring to string is slow and only string identifiers 
					//and symbols are in the keywords and in the symbols.
					
					if(token != Token.none)
					res ~= TokenLocation!Token(cast(int)pos, cast(int) s.length, token); 
				} 
				
				static void categorizeDlangChar(dchar ch, ref char s/+state+/)
				{
					if(s=='a')
					{ if(!isDLangIdentifierCont(ch)) s = ' '; }
					else if(s=='0')
					{ if(!isDLangNumberCont(ch)) s = ' '; }
					else
					{
						if(isDLangIdentifierStart(ch)) s = 'a'; 
						else if(isDLangNumberStart(ch)) s = '0'; 
						else s = ' '; 
					}
					
					//return 'a' for identifiers, '0' for numbers, ' ' for newline. 
					//Otherwise terutn the actual char.
					//return s==' ' ? (ch=='\n' ? ' ' : ch) : s; 
				} 
				
				char actState = ' '; 
				dstring actWord; 
				foreach(idx, dchar ch; str)
				{
					//detect words and symbols
					auto lastState = actState; 
					bool wordFound = false; 
					categorizeDlangChar(ch, actState); 
					if(lastState!=actState)
					{
						if(actState=='a')
						{
							actWord = "";  
							//Note: this parser ignores numbers
						}
						else if(lastState=='a')
						wordFound = true; 
					}
					if(actState=='a') actWord ~= ch;  //Note: this parser ignores numbers
					if(wordFound) tryAppend(actWord, idx-actWord.length); //Note: no 'else' here!!!
					if(actState==' ') tryAppend(ch.dtext, idx); //symbol
				}
				if(actState=='a') tryAppend(actWord, str.length-actWord.length); //Note: ignores numbers
				
				return res[]; 
			} 
		} public
		{
			
			CodeColumn col; 
			const dstring srcDStr; 
			//this-level symbolic dchars.  a=identifier, 0=number, space=whitespace or comment, 
			//   \n is newLine. all other chars are preserved
			
			TokenLocation!Token[] tokens; 
			
			TokenLocation!Token[] sentence; //fetchTokenSentence's result
			
			CodeRow[] dst; 
			
			void appendNewLine()
			{ dst ~= new CodeRow(col); } 
			
			void appendCell(Cell c)
			{
				if(c) {
					dst.back.subCells ~= c; 
					c.setParent = dst.back; 
				}
			} 
			
			int 	srcIdx; 
			ivec2 srcPos; 
			
			Cell[][] resultCells; //the temporal result of operations
				
			this(CodeColumn col)
			{
				this.col = col; 
				srcDStr = extractThisLevelDString(col); 
				tokens = findTokenLocations!Token(srcDStr); 
				
				appendNewLine; 
			} 
			
			~this()
			{
				//finalize and refresh the column
				transferUntil(cast(int)srcDStr.length); 
				
				col.subCells = cast(Cell[])dst; 
				foreach(r; col.rows) {
					r.refreshTabIdx; 
					r.needMeasure; 
				}
			} 
			
			void fetchTokens(Token[] term)()
			{
				const idx = tokens.map!(t => term.canFind(t.token)).countUntil(true); 
				enforce(idx>=0, "ECFT:" ~ tokens.text); 
				sentence = tokens[0..idx+1]; 
				tokens = tokens[idx+1..$]; 
			} 
			
			void fetchSingleToken()
			{
				enforce(tokens.length); 
				sentence = tokens[0..1]; 
				tokens.popFront; 
			} 
				
			enum Operation
			{ skip, transfer, fetch} 
			
			void processSrc(Operation op, bool whitespaceAndCommentAndInterpolationBlockOnly = false)(int targetIdx)
			{
				assert(srcIdx <= targetIdx); 
				assert(srcPos.y.inRange(col.rows)); 
				assert(srcPos.x.inRange(0, col.rowCharCount(srcPos.y))); 
				
				static if(op==Operation.fetch) { resultCells = null; resultCells.length = 1; }
				
				while(srcIdx < targetIdx)
				{
					auto srcRow = col.rows[srcPos.y]; //Opt: only fetch row when needed
					if(srcPos.x<srcRow.subCells.length)
					{
						//Cell
						auto cell = srcRow.subCells[srcPos.x]; 
						
						static if(whitespaceAndCommentAndInterpolationBlockOnly)
						{
							bool isComment()
							{
								if(cast(CodeComment)cell) return true; 
								if(auto g = cast(Glyph)cell) if(g.ch.isDLangWhitespace) return true; 
								if(auto b = cast(CodeBlock)cell) if(b.type==CodeBlock.Type.interpolation) return true; 
								return false; 
							} 
							if(!isComment) break; 
						}
						
						static if(op==Operation.transfer) appendCell(cell); 
						static if(op==Operation.fetch) resultCells.back ~= cell; 
						
						srcPos.x ++; 
					}
					else
					{
						//NewLine
						static if(op==Operation.transfer) appendNewLine; 
						static if(op==Operation.fetch) resultCells.length ++; 
						
						srcPos = ivec2(0, srcPos.y+1); 
					}
					srcIdx++; 
				}
			} 
			
			alias transferUntil = processSrc!(Operation.transfer); 
			
			alias skipUntil = processSrc!(Operation.skip); 
			
			auto fetchUntil(int targetIdx)
			{ processSrc!(Operation.fetch)(targetIdx); return resultCells; } 
			
			bool transferWhitespaceAndCommentsAndInterpolationBlocks()
			{
				const lastIdx = srcIdx; 
				processSrc!(Operation.transfer, true)(srcDStr.length.to!int); 
				return lastIdx != srcIdx; 
			} 
			
			auto peek(T : Cell)()
			{
				if(auto row = col.rows.get(srcPos.y))
				return cast(T) row.subCells.get(srcPos.x); 
				return null; 
			} 
			
			dchar peekChar()
			{
				if(auto g = peek!Glyph)
				return g.ch; 
				return '\0'; 
			} 
			
			bool skipOptionalSpace()
			{
				if(peekChar==' ')
				{
					processSrc!(Operation.skip, true)(srcIdx+1); 
					return true; 
				}
				return false; 
			} 
			
			bool skipOptionalCharToken(dchar ch, Token tk)
			{
				if(peekChar==';' && tokens.length && tokens.front.token==tk)
				{
					processSrc!(Operation.skip, false)(srcIdx+1); 
					tokens.popFront; 
					return true; 
				}
				return false; 
			} 
			
			int remainingCellsOnLine()
			{
				if(auto row = col.rows.get(srcPos.y))
				return row.subCells.length.to!int - srcPos.x; 
				return 0; 
			} 
			
			void dropOutpacedTokens()
			{
				while(!tokens.empty && tokens.front.pos<srcIdx)
				tokens.popFront; 
			} 
			
			void transferWhitespaceAndCommentsAndInterpolationBlocksAndDirectives()
			{
				//Directives are specialized CodeComments.
				//They are detected and processed here.
				//Preprocessor support is limited The low level parser
				transferWhitespaceAndCommentsAndInterpolationBlocks; 
				
				again: 
				if(peekChar=='#' /+Todo: This must be the FIRST # on a line!!!+/)
				{
					const directiveLineIdx = peek!Glyph.lineIdx; 
					skipUntil(srcIdx + 1); //skip the '#'
					
					Cell[][] directiveCells; 
					
					version(/+$DIDE_REGION+/all)
					{
						/+
							Note: multiline directives are transformed into a single line,
							so this only reads one structured line.
						+/
						fetchUntil(srcIdx+remainingCellsOnLine); 
						if(!resultCells.empty) directiveCells ~= resultCells[0]; 
					}
					
					version(/+$DIDE_REGION+/none) {
						/+Note: 250218 This is deprecated because handleMultilineCMacros does this.+/
						version(/+$DIDE_REGION Collect all lines of the directive+/all)
						{
							while(1) {
								//Note: '\\' backslash is not supported by DLang
								
								fetchUntil(srcIdx+remainingCellsOnLine); 
								if(resultCells.empty) break; 
								
								bool isExtendedLine()
								{
									if(resultCells[0].length)
									if(auto g = cast(Glyph) resultCells[0].back)
									if(g.ch == '\\') return true; 
									return false; 
								} 
								
								if(isExtendedLine)
								{
									/+
										Todo: Deprecate this! This fails with structured code.
										This multiline thing is deprecated.
										The handleMultilineMacros will do this earlier.
									+/
									directiveCells ~= resultCells[0][0..$-1]; 
									
									if(srcIdx<srcDStr.length)
									{
										skipUntil(srcIdx+1); //skip newLine
										continue; 
									}
									else
									{
										break; //it's EOF
									}
								}
								else
								{
									directiveCells ~= resultCells[0]; 
									break; 
								}
							}
						}
					}
					
					Cell[] endingWhite; 
					version(/+$DIDE_REGION Remove last comment and whitespace+/all)
					{
						//It looks nicer as elastic tabs can't go across multiple directives (yet)
						ref lastRow() { return directiveCells.back; } 
						
						const cnt = lastRow.retro.until!(c => c.structuredCellToChar != ' ').walkLength; 
						const idx = lastRow.length - cnt; 
						
						endingWhite = lastRow[idx..$]; 
						
						lastRow = lastRow[0..idx]; 
					}
					
					auto directive = new CodeComment(null); 
					directive.type = CodeComment.Type.directive; 
					directive.lineIdx = directiveLineIdx; 
					directive.content = new CodeColumn(directive, directiveCells, directiveLineIdx); 
					directive.content.fillSyntax(skDirective); 
					
					directive.promoteCustomDirective; 
					
					appendCell(directive); 
					endingWhite.each!(c => appendCell(c)); 
					
					//ignore tokens inside the directive
					dropOutpacedTokens; 
					
					//clean up the remaining NewLine and retry
					if(transferWhitespaceAndCommentsAndInterpolationBlocks)
					goto again; 
				}
			} 
		} 
	} 
	auto findCellPattern(string[] patterns)(ref Cell[][] cellRows)
	{
		//findCellPattern ////////////////////////////////
		
		struct Result {
			string pattern; 
			size_t idx; 
			
			//CodeComment[] comments;
			//int newLineCount;
			
			bool opCast(T : bool)() const
			{ return pattern!=""; } 
		} 
		Result res; 
		
		/+
			Opt: this is a slow search, it tries all the patterns one by one through the whole string.
			Calling structuredCellToChar too many times.
		+/
		foreach(pattern; patterns)
		{
			auto src = cellRows.map
			!(
				row => row.map!(
					(cell){
						//if(auto cmt = cast(CodeComment) cell) res.comments ~= cmt; //collect comments
						return cell.structuredCellToChar; 
					}  
				)
			)
			.joiner([dchar('\n')]); 
			
			size_t idx; 
			bool match=true; 
			foreach(dchar pch; pattern)
			{
				void step()
				{ src.popFront; idx++; } 
				
				void stepWhite() {
					//if(pch=='\n') res.newLineCount++; //collect newlines
					step; 
				} 
				
				if(pch==' ')
				{ while(!src.empty && src.front.among(' ', '\n')) stepWhite; }
				else
				{
					if(!src.empty && pch==src.front) { step; }else {
						match = false; 
						break; 
					}
				}
			}
			if(match)
			if(
				!pattern.back.isDLangIdentifierCont || src.empty || !src.front.isDLangIdentifierCont
								//whole words only, if the pattern ends with a letter
			)
			{
				res.pattern = pattern; 
				res.idx = idx; 
				break; 
			}
		}
		
		return res; 
	} 
	Declaration[] extractPrepositions(CodeRow temporaryParent, ref Cell[][] cellRows)
	{
		//extractPrepositions ///////////////////////////////
		Declaration[] res; 
		
		int totalNewLineCount, totalTabCount; 
		CodeComment[] totalComments; 
		
		///remove from cellRows, return last removed cell
		Cell skip(size_t idx)
		{
			auto res = cellRows.removeFront(idx); 
			totalNewLineCount += res.newLineCount; 
			totalTabCount += res.tabCount; 
			totalComments ~= res.comments; 
			return res.lastCell; 
		} 
		
		void skipWhite()
		{
			auto res = cellRows.removeFront!(c => c.isWhitespaceOrComment)(int.max); 
			totalNewLineCount += res.newLineCount; 
			totalTabCount += res.tabCount; 
			totalComments ~= res.comments; 
		} 
		
		void skipOneOptionalSpace()
		{ cellRows.removeFront!(c => c.cellIsSpace)(1); } 
		
		void appendCommentsAndNewLines()
		{
			if(totalTabCount || totalNewLineCount || !totalComments.empty)
			{
				if(res.length)
				{
					res.back.internalNewLineCount += totalNewLineCount; 
					res.back.internalTabCount += totalTabCount; 
					
					//append internal comments to the end of the (block)
					foreach(cmt; totalComments)
					{
						auto r = res.back.header.rows.back; 
						cmt.setParent(r); 
						r.appendCell(cmt); 
						r.needMeasure; 
					}
				}
				else
				{
					if(totalComments.length)
					WARN("There were skipped internal comments:\n"~totalComments.map!"a.sourceText".join('\n')); 
					if(totalNewLineCount)
					WARN("There were skipped internal newLines:\n"~totalNewLineCount.text); 
				}
				
				totalNewLineCount 	= 0; 
				totalTabCount	= 0; 
				totalComments	= []; 
			}
		} 
		
		void append(string keyword, Cell[][] paramCells)
		{
			//write("	"~keyword~"  "); //todo
			auto decl = new Declaration(temporaryParent, null, keyword, paramCells, new CodeColumn(null, []), ')'); 
			res ~= decl; 
			skipWhite; 
			appendCommentsAndNewLines; 
		} 
		
		while(auto match = cellRows.findCellPattern!prepositionPatterns)
		with(match) {
			
			//totalNewLineCount 	+= match.newLineCount;
			//totalTabCount 	+= match.tabCount;
			//totalComments 	~= match.comments;
			
			if(pattern.endsWith('='))
			{
				 //special terminal patterns.
				if(pattern=="debug =")
				{
					//it's a statement, not a preposition
				}
				else if(pattern=="else debug =")
				{
					skip(4); //skipping else keyword
					append("else", []); 
				}
				else
				enforce(0, "Unhandled terminal preposition ="); 
				break; 
			}
			else if(pattern.endsWith('('))
			{
				auto param = (cast(CodeBlock) skip(idx)); 
				assert(param && param.prefix=="("); 
				append(pattern.withoutEnding(" ("), param.content.rows.map!(r => r.subCells).array); 
			}
			else
			{
				skip(idx); 
				append(pattern, []); 
			}
		}
		
		return res; 
	} 
	void processHighLevelPatterns_block(CodeColumn col_)
	{
		//debug line idx: print("PHLPB:", "lineIdx="~col_.rows[0].lineIdx.text); 
		
		
		processHighLevelPatterns_macroExpressions(col_); //it must be issued for the whole column BEFORE the block processor. It will eliminate string mixin()s, so the block processor can handle the remaining mixin statements.
		
		//generate Token enum from sentence detection rules.
		mixin(format!"enum DeclToken{ none, %s }"(sentenceDetectionRules.map!"a[0].split".join.map!toSymbolEnum.join(", "))); 
		
		auto proc = TokenProcessor!DeclToken(col_); 
		with(proc)
		with(DeclToken)
		{
			version(/+$DIDE_REGION+/all)
			{
				Declaration receiver; 
				
				void appendDeclaration(Declaration decl)
				{
					if(receiver)
					{
						
						if(
							!receiver.explicitPrepositionBlock && receiver.block.empty 
							&& decl.isSimpleBlock && receiver.isPreposition
						)
						{
							//unpack the declaration block
							receiver.explicitPrepositionBlock = true; 
							receiver.block = decl.block; 
							receiver.block.setParent(receiver); 
						}
						else
						{
							auto row = receiver.block.rows.back; 
							row.appendCell(decl); 
							decl.setParent(row); 
							
							/+
								Note: The receiver has an empty block, therefore that 
								rowIdx is 0.  Now that is has a nonEmpty block, 
								the row's line indices could be refreshed.
							+/
							receiver.refreshLineIdx; 
						}
						
						if(decl.isPreposition)
						receiver = decl; 
						else if(decl.isStatement || decl.isBlock)
						receiver = null; 
						else if(decl.isSection)
						{
							if(!decl.isLabel) receiver = null; 
							/+
								Note: A preposition can receive any number of labels, 
								but only one attribute section. 
							+/
						}
						else
						assert(0, "Unidentified declaration type"); 
					}
					else
					{
						proc.appendCell(decl); 
						
						if(decl.isPreposition) receiver = decl; 
					}
					
				} 
				
				void joinPrepositions()
				{
					//joinPrepositions //////////////////////////////////////////
					size_t backTrackCount = 0; 
					//CodeComment[] precedingComments;
					bool hasJoinedNewLine, hasJoinedTab; 
					
					Declaration findSrcPreposition(in string[] validKeywords)
					{
						Declaration recursiveSearch(Declaration decl)
						{
							Declaration res; 
							if(decl)
							foreach_reverse(d; decl.allNestedPrepositions)
							{
								d = d.lastJoinedPreposition; 
								if(validKeywords.canFind(d.keyword))
								{
									enum danglingIsValid = true; 
									static if(danglingIsValid)
									{
										return d; //return the nearest match
									}
									else
									{
										if(!res) res = d; 
										else return null; //multiple opportinities means: dangling
										/*
											Todo: to handle dangling warnings, else dstPrepositions 
											should be marked as dangling, and ensure that 
											no other propositions could join to them. 
										*/
									}
									
								}
							}
							
							return res; 
						} 
						
						backTrackCount = 1; //first is the dstPreposition, it's always dropped
						//precedingComments = [];
						hasJoinedNewLine = false; 
						hasJoinedTab = false; 
						auto a = dst	.retro.map!(r => r.subCells.retro)
							.joiner(only(null)/+newLine is null+/).drop(1); 
						while(!a.empty)
						{
							if(a.front is null)
							{
								//Note: this newline is in front of the else.
								/+
									Currently the trigger to put the else on a new line is the 
									newline after the else.
									In text there are 4 combinations. 
									In structured view there are only 2. (same line or new line)
								+/
								hasJoinedNewLine = true; 
							}
							else if(a.front.isWhitespaceOrComment)
							{
								//Todo: collect the comment and and at least make a WARN
								if(auto cmt = cast(CodeComment) a.front)
								{
									//WARN("Lost comment: "~cmt.sourceText);  
									//precedingComments ~= cmt;
									//Note: This comment is saved somewhere else.
									
									//Todo: process joined comments
								}
								else if(auto glyph = cast(Glyph)a.front)
								{
									if(glyph.ch=='\t')
									hasJoinedTab = true; 
								}
							}
							else
							break; 
							
							//advance
							a.popFront; 
							backTrackCount++; 
						}
						auto rootDecl = cast(Declaration) a.frontOrNull; 
						
						//dstPrepositionRootDecl = rootDecl; //return this on the side
						return recursiveSearch(rootDecl); 
					} 
					if(auto row = dst.backOrNull)
					if(auto dstPreposition = cast(Declaration) row.subCells.backOrNull)
					if(dstPreposition.isPreposition)
					foreach(rule; prepositionLinkingRules)
					if(rule[1].canFind(dstPreposition.keyword))
					{
						if(auto srcPreposition = findSrcPreposition(rule[0]))
						{
							//backTrack until the receiver
							assert(backTrackCount>0); 
							auto removed = dst.removeBack(backTrackCount); 
							
							//place the joined internal comments at beginning of the block
							foreach(cmt; removed.comments)
							{
								auto r = dstPreposition.block.rows.back; 
								cmt.setParent(row); 
								r.subCells = cmt ~ r.subCells; 
								r.refreshTabIdx; 
								r.needMeasure; 
							}
							
							dstPreposition.internalNewLineCount += removed.newLineCount; 
							dstPreposition.internalTabCount += removed.tabCount; 
							dstPreposition.hasJoinedNewLine = hasJoinedNewLine; 
							dstPreposition.hasJoinedTab = hasJoinedTab; 
							
							/+
								Todo: tab detection is bad here. 
								opengl.shaders.attrib is a good example.
							+/
							
							srcPreposition.appendJoinedPreposition(dstPreposition); 
						}
						break; //dstPreposition can present in only one rule
					}
				} 
			}version(/+$DIDE_REGION+/all)
			{
				while(tokens.length)
				{
					transferWhitespaceAndCommentsAndInterpolationBlocksAndDirectives; 
					//these comments are going into the body of the block
					
					const main = tokens.front; 
					auto mainIsKeyword()
					{ return main.token.functionSwitch!"a.text.startsWith('_')"; } 
					
					sw: 
					switch(main.token)
					{
						static foreach(a; sentenceDetectionRules)
						mixin(
							format!	q{case %s: fetchTokens!([%s]); break sw; }
								(a[0].toSymbolEnumList, a[1].toSymbolEnumList)
						); 
						default: 	fetchSingleToken; 
					}
					
					auto ending = sentence.back; 
					const endingChar = ending.token.predSwitch(
						semicolon, 	';', 
						colon,	':', 
						block,	'}', ' '
					); 
					const keyword = ((endingChar.among(';', '}')&& mainIsKeyword) ?(main.token.text[1..$]):("")); 
					
					version(/+$DIDE_REGION Handle DLang Function Contracts+/all)
					{
						if(sentence.length==1 && sentence.back.token == DeclToken.block)
						{
							static auto isSkippableContractBlock(dstring s)
							{
								/+
									Opt: would be faster	to check for invalid chars first. 
									"dinotu({ \n"	Or check the number of letters first.
								+/
								
								//{ whitespace in/out/do whitespace opt( whitespace {
								assert(s.length>=2); 
								assert(s.startsWith('{')); 
								assert(s.endsWith('{')); 
								s = s[1..$-1].strip; 
								
								//in/out/do whitespace opt(
								s = s.withoutEnding('(').stripRight; 
								
								//in/out/do
								return s.among("in"d, "out"d, "do"d); 
							} 
							
							int i = main.pos; 
							while(
								!tokens.empty && tokens.front.token == DeclToken.block 
								&& isSkippableContractBlock(srcDStr[i .. tokens.front.end])
							)
							{
								ending = tokens.front; 
								sentence ~= ending; 
								i = ending.pos; 
								tokens.popFront; 
							}
						}
					}
					
					if(endingChar.among(';', '}', ':'))
					{
						
						Cell[][] attrs; 
						if(keyword != "") {
							attrs = fetchUntil(main.pos); 
							skipUntil(main.end); 
						}
						
						auto header = fetchUntil(ending.pos); 
						
						CodeColumn block; 
						if(endingChar.among(';', ':', '('))
						{ skipUntil(ending.end); }
						else if(endingChar == '}')
						{
							auto container = fetchUntil(ending.end); 
							block = (cast(CodeBlock) container.front.front).content; 
							
							//Todo: Transform { x } => {x}   Warning: It can be bad for undo/redo
							//if(block.rowCount==1 && block.rows.front.length>=2 && block.rows.frontfirstChar==' '
						}
						else
						enforce(0, "Unhandled endingChar: "~endingChar.text.quoted); 
						
						auto temporaryParent = proc.dst.back /+
							Note: This is not the final parent, it's only there 
							to access the module from the parent chain.
						+/; 
						auto declarationChain = 	extractPrepositions(temporaryParent, attrs.length ? attrs : header) ~
							new Declaration(temporaryParent, attrs, keyword, header, block, endingChar); 
						
						foreach(decl; declarationChain) appendDeclaration(decl); 
						
						joinPrepositions; 
						
						if(autoSpaceAfterDeclarations) skipOptionalSpace; 
						
						if(joinSemicolonsAfterBlocks)
						if(
							declarationChain.length==1 && declarationChain.front.isBlock
							&& skipOptionalCharToken(';', DeclToken.semicolon)
						)
						{
							declarationChain.front.blockHasExtraSemicolonEnding = true; 
							if(autoSpaceAfterDeclarations) skipOptionalSpace; 
						}
					}
					else
					{
						ERR("Unhandled token"~ending.text); 
						transferUntil(ending.end); 
					}
				}
			}
		}
	} 
	enum CurlyBlockKind { empty, declarationsOrStatements, list} 
	
	auto detectCurlyBlock(CodeColumn col_)
	{
		/+
			Opt: This is terrbily slow. Must do this with a CodeColumn.bidirectional range.
			That also should detect identifiers/keywords.
		+/
		auto p = col_.extractThisLevelDString.text; 
		p = p.replace("\n", " "); 
		p = p.replace("  ", " "); 
		p = p.replace(" {", "{"); 
		//p = p.replace(" [", "["); 
		//p = p.replace(" (", "("); 
		p = p.strip; 
		
		//Todo: A a={a:{b:c}};  <- it thinks this is a function body
		/+
			Note: In a ',' separated list, if there is any identifier ':' starting, then it's an expression, not a code.
			Inside {} it is a structure initializer
			Inside () it is a parameter list
		+/
		version(none)
		{ A a={ a: { b: c}}; }version(none)
		{ A a={ a: c}; /+this one is ok+/}
		/+
			Todo: if there is a comment at the end of a one liner block, 
			then there will be an an extra space at the start of the block /sigh
		+/
		
		//first start with easy decisions at the end of the block
		if(p=="") return CurlyBlockKind.empty; 
		if(p.endsWith(';') || p.endsWith(':')) return CurlyBlockKind.declarationsOrStatements; 
		
		if(p.canFind("{,") || p.canFind(",{")) return CurlyBlockKind.list; 
		if(p.canFind(';')||p.canFind('{')) return CurlyBlockKind.declarationsOrStatements; 
		
		return CurlyBlockKind.list; 
		
		//Todo: Can't detect structure initializer here: VkClearValue clearColor = { color: { float32: [ 0.8f, 0.2f, 0.6f, 1.0f ]}}; 
	} 
	
	bool isHighLevelBlock(CodeColumn col)
	{
		bool found; 
		foreach(cell; col.rows.map!(r => r.subCells).joiner) {
			if(cast(Declaration) cell) { found = true; continue; }
			if(cast(CodeComment) cell) continue; 
			if(auto g = cast(Glyph) cell)
			if(g.ch.isDLangWhitespace) continue; 
			return false; 
		}
		return found; 
	} 
	
	void promoteMacroExpression(CodeRow row, ref int cellIdx, CodeBlock blk/+redundant but faster+/)
	{
		foreach(
			const kw; [
				"import", "mixin", "__traits", "__rvalue", "__ctfeWrite", "pragma", 
				"typeof", "typeid"
			]
			/+Todo: extract this array to macroExpressionKeywords+/
			/+Todo: implement 'isExpression' too!+/
			//Opt: speed this up
		)
		{
			const kwLen = (cast(int)(kw.length)); 
			auto kwIdx = cellIdx - kwLen; 
			/+handle optional internal space 'mixin ()'+/
			if(kwIdx>0 && row.chars[cellIdx-1]==' ') kwIdx--; 
			if(
				kwIdx>=0 && /+the keyword fits+/
				equal(row.chars[kwIdx..kwIdx+kwLen], kw) && /+the keyword matches+/
				(
					(kwIdx<=0) || !isDLangIdentifierCont(row.chars[kwIdx-1])
					/+there is no identifier char before the keyword+/
				)
			)
			{
				
				//suck up the extra space at the start
				const extraSpaceAtStart = false && (kwIdx-1>=0 && row.chars[kwIdx-1]==' '); 
				/+
					Todo: 'extraSpaceAtStart' is disabled because when writing, 
					it only puts a space if it is required.
					/+Code: a =mixin(x);+/ <- here, the extra space is NOT required for example.
				+/
				
				/+remove keyword+/
				const 	st = kwIdx-extraSpaceAtStart, 
					en = cellIdx; 
				row.subCells = row.subCells.remove(tuple(st, en)); 
				cellIdx -= en-st; //adjust the loop
				row.refreshTabIdx/+because subCells changed+/; 
				
				/+promote () to a special block+/
				blk.type = kw.predSwitch(
					"import"	, CodeBlock.Type.stringImport, 
					"mixin"	, CodeBlock.Type.stringMixin, 
					"__traits"	, CodeBlock.Type.traits,
					"__rvalue"	, CodeBlock.Type.rvalue,
					"__ctfeWrite"	, CodeBlock.Type.ctfeWrite,
					"pragma"	, CodeBlock.Type.pragmaExpr,
					"typeof"	, CodeBlock.Type.typeofExpr,
					"typeid"	, CodeBlock.Type.typeidExpr,
				); 
				blk.needMeasure; 
				
				return; 
			}
		}
	} 
	void processHighLevelPatterns_statement(CodeColumn col)
	{
		//Note: it's called from Declaration.this() for every highlevel statement
		
		if(!col) return; 
		
		
		//First it processes like an expression
		processHighLevelPatterns_expr(col); //Note: depth first recursion
		
		//And then processes single row Statement declarations further
		if(auto decl = (cast(Declaration)(col.parent)))
		if(decl.isStatement)
		if(col.rowCount==1) processNiceStatementRow(col.rows[0]); 
	} 
	
	alias processHighLevelPatterns_macroExpressions = processHighLevelPatterns_expr!(Yes.macroExpressionsOnly); 
	
	void processHighLevelPatterns_expr(Flag!"macroExpressionsOnly" macroExpressionsOnly = No.macroExpressionsOnly)(CodeColumn col)
	{
		foreach(int rowIdx, row; col.rows)
		{
			for(int cellIdx=0; cellIdx<row.cellCount; cellIdx++)
			{
				ref cell() => row.subCells[cellIdx]/+Note: this must be a reference, because niceExpression can replace its content.+/; 
				
				version(/+$DIDE_REGION Do the macro expression promotions first+/all)
				{
					if(auto blk = (cast(CodeBlock)(cell)))
					{ if(blk.type==CodeBlock.Type.list) promoteMacroExpression(row, cellIdx, blk); }
					else if(auto str = (cast(CodeString)(cell)))
					{ str.promoteToInterpolatedText(row, cellIdx); /+Note: i"str".text -> ti"str"+/}
				}
				
				static if(macroExpressionsOnly)
				if(auto blk = (cast(CodeBlock)(cell)))
				if(blk.type.among(CodeBlock.Type.block, CodeBlock.Type.list)) continue; 
				
				
				if(auto blk = (cast(CodeBlock)(cell)))
				{
					final switch(blk.type)
					{
						case 	CodeBlock.Type.block /+Note: {}+/: 	{
							blk.content.processHighLevelPatterns_optionalBlock; 
							if(blk.content.isHighLevelBlock)
							{
								/+Promote block to Declaration.block.+/
								cell = new Declaration(blk); 
							}
						}	break; 
						case CodeBlock.Type.index /+Note: []+/: 	{ blk.content.processHighLevelPatterns_expr; }	break; 
						case 	CodeBlock.Type.list 	/+Note: ()+/,
							CodeBlock.Type.interpolation	/+Note: $()+/,
							/+Note: macroExpressions from here:+/
							CodeBlock.Type.stringImport	/+Note: import()+/,
							CodeBlock.Type.stringMixin 	/+Note: mixin()+/,
							CodeBlock.Type.traits 	/+Note: __traits()+/,
							CodeBlock.Type.rvalue 	/+Note: __rvalue()+/,
							CodeBlock.Type.ctfeWrite 	/+Note: __ctfeWrite()+/,
							CodeBlock.Type.pragmaExpr 	/+Note: pragma()+/,
							CodeBlock.Type.typeofExpr 	/+Note: typeof()+/,
							CodeBlock.Type.typeidExpr 	/+Note: typeid()+/
						/+
							Todo: These were opened by 
							promoteMacroExpression, 
							maybe it's bad to list them all here
						+/: 	{
							blk.content.processHighLevelPatterns_expr; 
							processNiceExpressionBlock(cell); /+Note: depth first recursion+/
						}	break; 
					}
				}
				else if(auto str = cast(CodeString) cell)
				{
					switch(str.type)
					{
						case 	CodeString.Type.tokenString /+Note: q{}+/,
							CodeString.Type.interpolated_tokenString /+Note: iq{}+/,
							CodeString.Type.interpolated_tokenString_text /+Note: tiq{}+/: 	{ str.content.processHighLevelPatterns_optionalBlock; }	break; 
						case 	CodeString.Type.interpolated_cString /+Note: i""+/, 
							CodeString.Type.interpolated_dString /+Note: i``+/,
							CodeString.Type.interpolated_cString_text /+Note: ti""+/, 
							CodeString.Type.interpolated_dString_text /+Note: ti``+/: 	{
							str.content.processHighLevelPatterns_expr; 
							/+this will process the $() string interpolations+/
						}	break; 
						default: 
					}
				}
			}
		}
		
		if(auto str = (cast(CodeString)(col.singleCellOrNull))) str.promoteInterpolatedTokenStringTextMixin(col); 
	} 
	
	void processHighLevelPatterns_optionalBlock(CodeColumn col_)
	{
		//Note: This on either calls _block or _expr
		//if(p!="" && !p.endsWith(';'))
		//print("optional Block:", p);
		
		if(detectCurlyBlock(col_)==CurlyBlockKind.declarationsOrStatements)
		{
			/+
				auto p = col_.extractThisLevelDString.text.replace("\n", " ").strip;
				print("attempting: ", p);
			+/
			processHighLevelPatterns_block(col_); 
		}
		else
		{
			processHighLevelPatterns_expr(col_); //keep continue to discover recursively
		}
	} 
	
	
	void processHighLevelPatterns(CodeColumn col_, TextFormat textFormat)
	{
		switch(textFormat)
		{
			case TextFormat.managed_block: 	processHighLevelPatterns_block(col_); break; 
			case TextFormat.managed_statement: 	processHighLevelPatterns_statement(col_); break; 
			case TextFormat.managed_goInside: 	processHighLevelPatterns_expr(col_); break; 
			case 	TextFormat.managed_optionalBlock,
				TextFormat.managed: 	processHighLevelPatterns_optionalBlock(col_); break; 
			default: 
		}
	} 
	
	
	
	
	
	
}