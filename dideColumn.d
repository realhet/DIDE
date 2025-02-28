module didecolumn; 

import het.ui, het.parser, dideui, didebase; 
import diderow : CodeRow, SourceTextBuilder; 
import didenode : CodeNode, CodeContainer, CodeBlock, CodeComment, CodeString; 
import didedecl : Declaration, processHighLevelPatterns, isWhitespaceOrComment, isBreakRow; 
import didemodule : TextFormat, StructureLevel, compoundObjectChar, rearrangeLOG, addGlobalChangeIndicator, handleMultilineCMacros, preprocessMultilineMacros, moduleOf, DefaultIndentSize, MultiPageGapWidth, visualizeStructureLevels; 
import dideexpr : NiceExpression, mixinTableSplitFun, isMixinTableCell, MixinTableContainerClass; 

version(/+$DIDE_REGION+/all) {
	static struct CodeColumnBuilder(bool rebuild)
	{
		
		
		version(/+$DIDE_REGION+/all)
		{
			enum resyntax = !rebuild; 
			
			CodeColumn col; 
			
			TextStyle tsWhitespace, ts; 
			SyntaxKind _currentSk=skWhitespace, syntax=skWhitespace; 
			
			CodeRow actRow; 
			bool skipNextN; //after \r, skip the next \n
			
			static if(rebuild)
			{
				static int staticLineCounter;  //Bug: this one is global. So it only works in a single thread.
				
				void NL_internal()
				{
					col.appendCell(actRow = new CodeRow(col, "", null)); 
					actRow.lineIdx = staticLineCounter; 
				} 
				
				void initialize()
				{
					col.clearSubCells; 
					NL_internal; //there must be 1 row always. Empty column is a single empty row.
				} 
				
				void appendChar(dchar ch)
				{
					switch(ch)
					{
						case '\n', '\r', '\u2028', '\u2029': 
							if(skipNextN.chkClear && ch=='\n') break; 
							skipNextN = ch=='\r'; 
							staticLineCounter++; 
							NL_internal; 
						break; 
						default: 
							//update cached textStyle
							if(_currentSk.chkSet(syntax))
						applySyntax(ts, syntax); 
							
							actRow.appendSyntaxCharWithLineIdx(ch, ts, syntax, staticLineCounter); 
					}
				} 
				
				void appendCell(Cell cell)
				{
					assert(cell); 
					actRow.appendCell(cell); 
				} 
				
				void appendNode(CodeNode node)
				{
					assert(node); 
					assert(node.parent is actRow); 
					appendCell(node); 
				} 
			}
				
		}version(/+$DIDE_REGION+/all)
		{
			static if(resyntax)
			{
				
				ivec2 actPos; 
				
				void initialize()
				{
					//seek to the first character
					actPos = ivec2(0); 
					actRow = col.rowCount ? col.rows[0] : null; //Todo: there must be a first row.
					enforce(actRow, "Resyntax: Invalid CodeColumn: No rows at all."); 
				} 
				
				void moveToNextRow()
				{
					enforce(actRow.cellCount==actPos.x, "Resyntax: Longer row than expected. "~actPos.text); 
					actPos.y++; 
					actPos.x = 0; 
					actRow = actPos.y<col.rowCount ? col.rows[actPos.y] : null; 
					enforce("Resyntax: More rows expected. "~actPos.text); 
				} 
				
				void moveToNextChar()
				{
					actPos.x++; 
					//this position is allowed to be out of range, because here comes the newline
				} 
				
				void appendChar(dchar ch)
				{
					switch(ch)
					{
						case '\n', '\r', '\u2028', '\u2029': 
							if(skipNextN.chkClear && ch=='\n') break; 
							skipNextN = ch=='\r'; 
							moveToNextRow; 
						break; 
						default: 
							/+
							debug 
								//const prevSyntax = syntax; 
								if(ch=='a') syntax = skKeyword; 
								scope(exit) if(ch=='a') syntax = prevSyntax;
						+/
							
							//update cached textStyle
							if(_currentSk.chkSet(syntax))
						applySyntax(ts, syntax); 
							
							auto g = cast(Glyph)(actRow.subCells.get(actPos.x)); 
							//Opt: cache this array per each row
							
							if(!g) {
							//StructuredEditor note: syntax highlighter ignores all classes except Glyph
							//enforce(g, "Resyntax: Glyph expected "~actPos.text);
						}
						else
						{
							enforce(g.ch == ch, "Resyntax: Glyph char changed "~actPos.text); 
							if(g.syntax.chkSet(syntax))
							{
								//syntaxChanged = true;
								g.bkColor	= ts.bkColor; 
								g.fontColor	= ts.fontColor; 
								
								const prevFontFlags = g.fontFlags; 
								g.fontFlags = ts.fontFlags; 
								if(auto delta = g.adjustBoldWidth(prevFontFlags)/+Todo: must handle monospace too. skNumber should have a monospaced string.+/)
								{
									//row size changed. Later must call the spreadElasticTabs thing
									actRow.needMeasure; 
									//Opt: cache this and call only once per each row
									//Todo: Ensure elastic tabs recursive spread.
									//230109
								}
							}
						}
							
							moveToNextChar; 
					}
				} 
				
				void appendNode(CodeNode node)
				{
					//StructuredEditor note: no need to check anything here
					auto n = cast(CodeNode)(actRow.subCells.get(actPos.x)); 
					//Opt: cache this array per each row
					enforce(n, "Resyntax: CodeNode expected "~actPos.text); 
					
					//no need to check anything
					//Opt: no need to rebuild the node, only skip it.
					
					moveToNextChar; 
				} 
			}
		}version(/+$DIDE_REGION+/all)
		{
			
			this(CodeColumn col)
			{
				this. col = col; 
				
				tsWhitespace 	= tsNormal	; applySyntax(tsWhitespace	, skWhitespace	); 
				ts 	= tsWhitespace	; applySyntax(ts	, _currentSk	); 
				
				initialize; 
			} 
			
			void appendStr(string str)
			{ foreach(dchar ch; str) appendChar(ch); } 
			
			void appendPlain(string str)
			{
				syntax = skIdentifier1; //no skWhiteSpace handling either.
				appendStr(str); 
			} 
			
			private void appendHighlighted_internal(string src)
			{
				
				/+250218: # is not a part of identifier syntax highlighting. It is processed by handleMultilineCMacros.+/
				/+
					Todo: apply skDirective to valid CodeComment.customDirectivePrefixes
					It is a # followed by 'define', etc.
					It needs a more complicated parser.
				+/
				
				static char categorize(dchar ch)
				{
					if(isDLangIdentifierCont(ch) || ch.among('_', '@'/+, '#'+/)) return 'a'; 
					if(ch.among(' ', '\t', '\x0b', '\x0c', '\r', '\n')) return ' '; 
					return '+'; 
				} 
				
				foreach(s; src.splitWhen!((a, b) => categorize(a) != categorize(b)).map!text)
				{
					switch(s[0])
					{
						case ' ', '\t', '\x0b', '\x0c', '\r', '\n': 	syntax = skWhitespace; 	break; 
						case '0': ..case '9': 	syntax = skNumber; 	break; 
						/+case '#': 	syntax = skDirective; 	break; +/
						//Todo: Support "#line n" directive for line numbering. Or ignore it... Just make karcshader.glsl work.
						case '@': 	syntax = skLabel; 	break; 
						
						default: 	if(s[0].isAlpha || s[0]=='_')
						{
							if(auto kw = kwLookup(s))
							{
								with(KeywordCat)
								switch(kwCatOf(kw))
								{
									case Attribute: 	syntax = skAttribute; 	break; 
									case Value: 	syntax = skBasicType; 	break; 
									case BasicType: 	syntax = skBasicType; 	break; 
									case UserDefiniedType: 	syntax = skKeyword; 	break; 
									case SpecialFunct: 	syntax = skAttribute; 	break; 
									case SpecialKeyword: 	syntax = skKeyword; 	break; 
									default: 	syntax = skKeyword; 	break; 
								}
							}
							else syntax = skIdentifier1; 
						}
						else if(s[0].isSymbol || s[0].isPunctuation)
						syntax = skSymbol; 
						else
						syntax = skIdentifier1; 
					}
					
					appendStr(s); 
				}
				
				syntax = skIdentifier1; 
			} 
			
			void appendHighlighted(string src)
			{ appendHighlighted	(src.DLangScanner); } 
			void appendStructured(string src)
			{ appendStructured	(src.DLangScanner); } 
			
			void appendHighlighted(R)(R scanner) if(isScannerRange!R)
			{ appendHighlightedOrStructured!false(scanner); } 
			void appendStructured(R)(R scanner) if(isScannerRange!R)
			{ appendHighlightedOrStructured!true(scanner); } 
		}version(/+$DIDE_REGION+/all)
		{
			void appendHighlightedOrStructured(bool structured=false, R)(R scanner)
			if(isScannerRange!R)
			{
				
				struct SRec {
					SyntaxKind syntax; 
					bool isTokenString; 
				} 
				auto syntaxStack = [SRec(syntax)]; 
				
				while(!scanner.empty)
				{
					auto sr = scanner.front; 
					
					//structural exit handling
					static if(structured)
					{
						if(syntaxStack.length==1 && sr.op==ScanOp.pop)
						{
							//only read until the end of the current level
							break; 
						}
					}
					
					void handleHighlightedPush()
					{
						syntaxStack ~= SRec(syntax); 
						void doit(SyntaxKind s) { syntax = s; appendStr(sr.src); } 
						switch(sr.src)
						{
							case "//", "/*", "/+": 	doit(skComment); 		break; 
							case "{", "(", "[", `$(`: 	doit(skSymbol); 	syntax = skWhitespace; 	break; 
							case `q{`: 	doit(skString); 	syntax = skWhitespace; syntaxStack.back.isTokenString = true; 	break; 
							case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`, `x"`, `i"`, "i`", `iq{`: 	doit(skString); 		break; 
							default: 	doit(skError); 		break; 
							//Todo: identifier quoted string `q"id`
						}
					} 
					
					switch(sr.op)
					{
						case ScanOp.push: 
							{
							static if(structured)
							{
								auto N(T)()
								{
									
									auto c = new T(actRow); 
									static if(rebuild) c.lineIdx = staticLineCounter; //Todo: staticLineCounter is 1 based, but newLineIdx is 0 based. This and the naming is crap.
									c.rebuild(scanner); 
									appendNode(c); 
								} 
								switch(sr.src)
								{
									//Todo: //comment must ensure that after it, there will be a NewLine
									case "//": 	N!CodeComment; appendChar('\n'); 	continue; 
									case "/*", "/+",: 	N!CodeComment; 	continue; 
									case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`, `q{`, `x"`, `i"`, "i`", `iq{`: 	N!CodeString; 	continue; 
									case "(", "{", "[", "$(": 	N!CodeBlock; 	continue; 
									default: handleHighlightedPush; 
								}
							}
							else
							{ handleHighlightedPush; }
						}
						break; 
						case ScanOp.pop: 
							if(syntaxStack.empty)
						{
							syntax = skError; 
							appendStr(sr.src); 
						}
						else
						{
							if(!syntax.among(skComment, skString)) syntax = skSymbol; 
							if(syntaxStack.back.isTokenString) syntax = skString; 
							appendStr(sr.src); 
							
							syntax = syntaxStack.back.syntax; 
							syntaxStack.length--; 
							//Todo: error checking for compatible closing tags. Maybe it can be implemented in the scanner too.
						}
						break; 
						//case ScanOp.trans: setSyntax(skError); break;
						case ScanOp.content: 
							if(syntax.among(skComment, skString))
						{
							appendStr(sr.src); 
							//Todo: highlight string escapes
							//Todo: advanced comment formatting
						}
						else
						{ appendHighlighted_internal(sr.src); }
						break; 
						default: 
							syntax = skError; //Todo: don't insert error text as code
							appendStr(sr.src); //Todo: it should optionally raise an exception. Example: when a structural scan fails, it should revert to highlighted.
					}
					
					scanner.popFront; 
				}
				
				static if(rebuild)
				col.convertSpacesToTabs(Yes.outdent); 
				
				static if(resyntax)
				foreach(r; col.rows)
				if(
					!r.flags._measured
					/+these are the rows affected by a width-changing fontFlag resintax.+/
				)
				{
					r.adjustCharWidths; //Todo: this should be replaced by monospace fontFlag.
					//230109
					//Note: this is needed by the resized rows
					r.spreadElasticNeedMeasure; 
				}
				
				col.needMeasure; 
			} 
		}
	} 
	class CodeColumn: Column
	{
		Container parent; 
		//CodeContext context;
		
		enum defaultSpacesPerTab = 4; //default in std library
		int spacesPerTab = defaultSpacesPerTab; //autodetected on load
		
		DateTime lastResyntaxTime; //needed for the multithreaded syntax highligh processing. It can detect if the delayed syntax highlight is up-to-date or not.
		
		bool edited; //this column is marked, so it can be syntax checked before saving.
		
		bool halfSize; 
		
		bool containsBuildMessages; 
		
		/// Minimal constructor creating an empty codeColumn with 0 rows.
		this(Container parent)
		{
			this.parent = parent; 
			id.value = this.identityStr; //it is used in ToolPalette to detect hitstack.
			/+
				Todo: This pointer coded in a string thing is so bad. 
				It should be a void ptr. Which has a payload: to decide if it is a ptr or an immediate id.
			+/
			
			initializeBorder; 
			
			needMeasure; //also sets measureOnlyOnce flag. This is an on-demand realigned Container.
			flags.wordWrap = false; 
			flags.clipSubCells = true; 
			flags.cullSubCells = true; 
			flags.columnElasticTabs = true; 
			bkColor = mix(clCodeBackground, clGray, .25f); 
		} 
		
		this(Container parent_, Cell[][] cells, int baseLineIdx=0)
		{
			this(parent_); 
			subCells = cast(Cell[])(cells.map!(r => new CodeRow(this, r)).array); 
			
			//one row must always present.
			if(subCells.empty) subCells ~= new CodeRow(this); 
			
			/+
				baseLineIdx is optional.
					If doesn't check the correctness of the lineIdx of the cells.
					But it is required because cell lines can be empty too.
					Other callers are using refreshLineIdx instead of this.
			+/
			if(baseLineIdx)
			{ foreach(i, r; rows) r.lineIdx = baseLineIdx + (cast(int)(i)); }
		} 
		
		this(CodeNode parent_, string source, TextFormat textFormat, int lineIdx_=0)
		{
			this(parent_); 
			
			switch(textFormat)
			{
				case TextFormat.managed_first: ..case TextFormat.managed_last: 
				{
					static if(handleMultilineCMacros)
					source = preprocessMultilineMacros(StructureLevel.structured, source); 
					
					with(rebuilder)
					{
						if(parent_) staticLineCounter = parent_.lineIdx; 
						if(lineIdx_) staticLineCounter = lineIdx_; 
						appendStructured(source); //This can throw all kinds of syntax errors.
					}
					processHighLevelPatterns(this, textFormat); 
				}
				break; 
				
				default: raise(textFormat.format!"Unhandled textFormat: %s"); 
			}
		} 
		
		version(/+$DIDE_REGION Associative Array support+/none)
		{
			override size_t toHash() { return (cast(size_t)(&this)); } 
			override bool opEquals(Object o) { return o is this; } 
		}
		
		bool empty() const
		{ return !rows.length || rows.length==1 && rows[0].empty; } 
		
		auto byCell()
		{ return rows.map!(r => r.subCells).joiner(only(null)); } 
		
		auto byNode(T : CodeNode = CodeNode)()
		{ return byCell.map!(a=>cast(T)a).filter!"a"; } 
		
		T lastCell(T : Cell = Cell)()
		{ if(auto row = lastRow) return row.lastCell!T; else return null; } 
		
		auto lastNode() => lastCell!CodeNode; 
		auto lastComment() => lastCell!CodeComment; 
		
		
		Cell singleCellOrNull()
		{ return rows.length==1 ? rows[0].singleCellOrNull : null; } 
		
		auto rebuilder()
		{ return CodeColumnBuilder!true	(this); } 
		auto resyntaxer()
		{ return CodeColumnBuilder!false	(this); } 
		
		StructureLevel getStructureLevel()
		{
			enforce(parent, "CodeColumn must have a parent"); 
			
			if(auto d = cast(Declaration) parent)
			{
				if(d.isStatement) {
					if(d.keyword=="import") return StructureLevel.highlighted; 
					//Todo: make more rules like this
				}
				return StructureLevel.managed; 
			}
			else if(auto cmt = cast(CodeComment) parent)
			{ return StructureLevel.plain; }
			else if(auto str = cast(CodeString) parent)
			{
				if(str.type != CodeString.Type.tokenString)
				return StructureLevel.plain; 
			}
			else if(auto niceExpr = cast(NiceExpression) parent)
			{
				if(this is niceExpr.operands[1] && niceExpr.isProbe)
				return StructureLevel.plain; 
			}
			
			//from here: module will tell
			if(auto m = moduleOf(this))
			{ return m.structureLevel; }
			return StructureLevel.plain; 
		} 
		
		bool isStructuredCode() //Todo: constness
		{ return getStructureLevel >= StructureLevel.structured; } 
		
		bool isDLangIdentifier()
		{ return rowCount==1 && rows[0].isDLangIdentifier; } 
		
		
		SyntaxKind getSyntax(dchar ch)
		{
			if(getStructureLevel==StructureLevel.plain) {
				if(auto ccntr = cast(CodeContainer) parent)
				return ccntr.syntax; 
				if(auto niceExpr = cast(NiceExpression) parent)
				if(this is niceExpr.operands[1] && niceExpr.isProbe)
				return skConsole; 
				
				return skIdentifier1; 
			}
			
			//from here: threat as highlighted
			
			if(ch=='@') return skAttribute; 
			if(ch.among('\'', '"', '`')) return skString; 
			if(ch.isDLangWhitespace) return skWhitespace; 
			if(ch.isDLangIdentifierStart) return skIdentifier1; 
			if(ch.isDLangNumberStart) return skNumber; 
			if(ch.isDLangSymbol) return skSymbol; 
			return skWhitespace; 
			
			//Todo: advanced version that checks the surroundings at the insert position.
		} 
		
		@property isPartOfBuildMessages()
		{
			foreach(a; this.thisAndAllParents)
			if(auto c = (cast(CodeColumn)(a)))
			if(c.containsBuildMessages) return true; 
			return false; 
		} 
		
		@property isPartOfSourceCode() => !isPartOfBuildMessages; 
		
		void refreshLineIdx()
		{
			int predictedIdx = 0; 
			foreach_reverse(row; rows)
			{
				const actIdx = row.findRowLineIdx_min; 
				if(actIdx>0)
				{
					row.lineIdx = actIdx; 
					predictedIdx = actIdx; 
				}
				else
				{
					predictedIdx --; 
					if(predictedIdx>0)
					row.lineIdx = predictedIdx; 
					else
					predictedIdx = 0; 
				}
				//Note: The line indices of the last empty rows will be 0
				//Note: This algo is not working with empty columns
				/+
					Todo: the current workaround is to regenerate all 
					the lineindices in the module.load.
				+/
			}
		} 
		
		auto calcWhitespaceStats()
		{
			WhitespaceStats whitespaceStats; 
			foreach(r; rows)
			{
				//Todo: optimize it somehow... Statistically...
				if(!r.leadingCodeTabs.empty)
				{ whitespaceStats.tabCnt++; }
				else
				{
					auto spaceCnt = r.leadingCodeSpaceCount; 
					whitespaceStats.addSpaceCnt(spaceCnt); 
				}
			}
			//Note: this is just lame statistics to detect the size of a tab only for converting spaces to tabs.
			return whitespaceStats; 
		} 
		
		CodeNode extractSingleNode()
		{
			CodeNode res; 
			
			foreach(c; byCell)
			{
				if(auto n = cast(CodeNode) c)
				{
					enforce(res is null, "extractSingleNode: Only one CodeNode allowed."); 
					res = n; 
				}
				else if(auto g = cast(Glyph) c)
				{
					if(g.ch.isDLangWhitespace) continue; 
					raise("extractSingleNode: Only whitespace characters allowed."); 
				}
			}
			
			enforce(res, "extractSingleNode: Unable to extract CodeNode."); 
			return res; 
		} 
		
		
		
		void convertSpacesToTabs(Flag!"outdent" outdent)
		{
			void createElasticTabs()
			{
				//const t0=QPS; scope(exit) print(QPS-t0);
				
				bool detectTab(int x, int y)
				{
					if(cast(uint)y >= rowCount) return false; 
					with(rows[y])
					{
						if(cast(uint)x >= cellCount) return false; 
						return isCodeSpaces[x] && (x+1 >= cellCount || !isCodeSpaces[x+1]); 
					}
				} 
				
				bool[long] visited; 
				
				static struct TabInfo { int y, xStart, xTab; } 
				TabInfo[] newTabs; 
				
				void flood(int x, int y, bool canGoUp, bool canGoDown, lazy size_t leadingSpaceCount)
				{
					if(!canGoDown && !canGoUp) return; 
					
					//assume: x, y is a valid tab position
					if(visited.get(x+(long(y)<<32))) return; 
					
					int y0 = y; 	 if(canGoUp) while(y0 > 0	&& detectTab(x, y0-1)) y0--; 
					int y1 = y; 	 if(canGoDown) while(y1 < rowCount-1	&& detectTab(x, y1+1)) y1++; 
					
					int maxLen = 0, minLen = int.max; 
					if(y0<y1)
					foreach(yy; y0..y1+1)
					with(rows[yy]) {
						visited[x+(long(yy)<<32)] = true; 
						
						int x0 = x; while(x0 > 0 && isCodeSpaces[x0-1]) x0--; 
						int x1 = x; 
						
						int len = x1-x0+1; 
						maxLen.maximize(len); 
						minLen.minimize(len); 
					}
					
					if(maxLen>1)
					{
						
						int xStartMin = 0; 
						if(!canGoUp) xStartMin = leadingSpaceCount.to!int; 
						//ez egy behuzas. Nem mehet balrabb a tab, mint a legfelso sor indent-je.
						
						//if(xStartMin>0) "------------------".print;
						
						foreach(yy; y0..y1+1)
						with(rows[yy]) {
							int xStart	= x; while(xStart > xStartMin && isCodeSpaces[xStart-1]) xStart--; 
							int xTab	= x+1-minLen; 
							
							newTabs ~= TabInfo(yy, xStart, xTab); 
							
							//if(xStartMin>0) print(lines[yy].text, "         ", newTabs.back);
						}
					}
				} 
				
				//scan through all the rows and initiate floodFills
				foreach(y, row; rows)
				with(row) {
					int st = 0; 
					foreach(isSpace, len; isCodeSpaces.group)
					{
						const en = st + cast(int)len; 
						
						if(isSpace && st>0)
						{
							bool canGoUp, canGoDown; 
							
							if(len==1 && st>0 && chars[st-1].among('[', '('))
							{
								canGoDown = true; 
								//Todo: the tabs below this one should inherit the indent of this first line
							}
							else
							{ canGoUp = canGoDown = canGoDown = len>=2; }
							
							/+
								const leftChar = st>0 ? chars[st-1] : '\0';
								const rightChar = en+1<len ? chars[en+1] : '\0';
								if(!(leftChar.isSymbol || rightChar.isSymbol)) canGoUp = canGoDown = false;
							+/
							
							flood(en-1, cast(int)y, canGoUp, canGoDown, leadingCodeSpaceCount); 
						}
						
						st = en; 
					}
				}
				
				//replace spaces with tabs
				auto sortedTabs = newTabs.sort!((a, b) => cmpChain(cmp(a.y, b.y), cmp(b.xTab, a.xTab))<0); //x is descending!!
				
				int idx; 
				foreach(const tabInfo; sortedTabs)
				with(rows[tabInfo.y]) {
					
					//tabs on the previous line will split this tab if it is long enough
					auto tabsOnPrevLine = sortedTabs[0..idx]	.retro
						.until!(t => t.y< tabInfo.y-1)
						.filter!(t => t.y==tabInfo.y-1); 
					auto splitThisTabAt = tabsOnPrevLine.map!"a.xTab".filter!(a => a.inRange(tabInfo.xStart, tabInfo.xTab-1)); 
					const tabCount = 1 + splitThisTabAt.walkLength; 
					//print("act", tabInfo, "splitAt", splitAt, "extra tabs", splitAt.walkLength);
					replaceSpacesWithTabs(tabInfo.xStart, tabInfo.xTab, tabCount); 
					
					idx++; 
				}
				
				//Todo: bug with labels: c:\D\ldc2\import\std\internal\math\biguintcore.d search-> div3by2correction
				
			} 
			
			//remove the 2 stylistic spaces at the front and back, in a single row block. { a; }
			if(outdent && rows.length==1)
			with(rows.front)
			{
				if(
					isCodeSpaces.length>=2 && isCodeSpaces[0] && !isCodeSpaces[1] &&
					((cast(CodeComment)(subCells.back)) || (cast(CodeBlock)(subCells.back)))
				)
				{
					//remove only the front space
					subCells = subCells[1..$]; refreshTabIdx; 
				}
				else if(
					isCodeSpaces.length>=3 && isCodeSpaces[0] && !isCodeSpaces[1]
					&& isCodeSpaces[$-1] && !isCodeSpaces[$-2]
					&& chars[$-2].among(
						';', ':', 
						compoundObjectChar
					)
				)
				{
					//remove both spaces at front and back
					subCells = subCells[1..$-1]; refreshTabIdx; 
				}
			}
			
			//Todo: this can only be called after the rows were created. Because it doesn't call needMeasure_elastic()
			createElasticTabs; 
			
			if(rows.length>1)
			{
				
				spacesPerTab = calcWhitespaceStats.detectIndentSize(DefaultIndentSize); 
				//Opt: this can be slow. Maybe put it on a keyboard shortcut.
				
				rows.each!(row => row.convertLeadingSpacesToTabs(spacesPerTab)); 
				
				//outdent
				if(outdent)
				{
					
					/+
						Todo: This is a mess.
						
						Try a simpler logic: 
						"the whitespace before the closing ident is stripped from each line in the string itself"
						/+Link: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/tokens/raw-string+/
						/+Link: https://dpldocs.info/this-week-in-arsd/Blog.Posted_2025_02_20.html+/
					+/
					
					static isCodeWhitespaceGlyph(Glyph g)
					{
						return g.ch.isDLangWhitespace && g.syntax.among(
							0/+whitespace+/,
							9/+comment+/
						); 
					} 
					
					static isCodeWhitespaceCell(Cell c)
					{
						if(auto g = cast(Glyph)c)
						if(isCodeWhitespaceGlyph(g)) return true; 
						return false; 
					} 
					
					//Todo: refactor it into CodeRow
					static bool isCodeWhitespaceRow(CodeRow r)
					{
						return r.subCells.empty || r.subCells.all!isCodeWhitespaceCell; 
						//return r.leadingCodeTabCount<r.cellCount; 
					} 
					
					//remove first and last whitespace row
					const firstRowRemoved = 	subCells.length>1 && 
						isCodeWhitespaceRow(rows.front); 	if(firstRowRemoved)
					subCells.popFront; 
					const lastRowRemoved = 	subCells.length>1 && 
						isCodeWhitespaceRow(rows.back); 	if(lastRowRemoved)
					subCells.popBack; 
					
					//only rows that not only tabs are relevant
					static bool isRelevantRow(CodeRow r)
					{
						return r.subCells.any!
						(
							(c){
								//non-stringLiteral whitespace is irrelevant
								if(auto g = cast(Glyph)c) { return !isCodeWhitespaceGlyph(g); }
								
								enum commentsAreRelevant = true; 
								if(!commentsAreRelevant && cast(CodeComment)c) return false; 
								
								//everything else is relevant
								return true; 
							}  
						); 
					} 
					
					static bool canBeStatement(CodeRow row)
					{
						/+
							Note: this fixes the following bug:
							const  a=1, -> const a=1,
							b=2; b=2;
						+/
						
						foreach_reverse(dchar ch; row.chars)
						{
							if(ch==';') return true; 
							if(ch.isDLangWhitespace) continue; 
							break; 
						}
						return false; 
					} 
					
					static bool hasNonLeadingTab(CodeRow row)
					{ return row.leadingCodeTabCount > row.codeTabCount; } 
					
					//find minimum amount of tabs
					const canIgnoreFirstRow = 	!firstRowRemoved
						&& (
						canBeStatement(rows.front) || 
						rows.front.isWhitespaceOrComment || 
						hasNonLeadingTab(rows.front)
					)
						&& rows.drop(1).any!isRelevantRow; 
					
					auto relevantRows = rows.drop(int(canIgnoreFirstRow)).filter!isRelevantRow; 
					if(!relevantRows.empty)
					{
						const numTabs = relevantRows.map!"a.leadingCodeTabCount".minElement; 
						
						/+
							Todo: If there is an unsure situation, the an earlier numTabs value should be 
							used to cut off tabs depending on the outer successful block.
							<- these tabse are a good example. The numTabs values must be 
							stored in an stack outside.
						+/
						
						if(numTabs)
						foreach(r; rows)
						if(r.leadingCodeTabCount>=numTabs)
						{
							r.subCells = r.subCells[numTabs..$]; 
							r.refreshTabIdx; 
							/+
								Note: no need to call needRefresh_elastic because all rows will be refreshed.
								It's in convertSpacesToTabs which only kicks right after row creation.
							+/
						}
						
					}
					else
					{
						//there are no relevant rows at all. : cleanup all the tabs
						foreach(r; rows)
						if(auto cnt = r.leadingCodeTabCount)
						{
							r.subCells = r.subCells[cnt..$]; 
							r.refreshTabIdx; 
						}
					}
					
				}
			}
			
			needMeasure; 
		} 
		
		void resyntax()
		{
			/+
				Note: IT IS ILLEGAL TO MODIFY the contents in this. 
				Only change to font color and flags are valid.
			+/
			/+
				Todo: older todo: resyntax: Problem with the Column Width detection when 
				the longest line is syntax highlighted using bold fonts.
			+/
			//Todo: older todo: resyntax: Space and hex digit sizes are not adjusted after resyntax.
			if(true /+getStructureLevel>=StructureLevel.highlighted+/)
			{
				try {
					resyntaxer.appendHighlighted(shallowText!' '); 
					//Note: using space instead of compositeObjectChar
				}
				catch(Exception e) {
					WARN(e.simpleMsg); 
					//Todo: mark the error.
				}
				//Todo: additionally highlight language specific keywords.
			}
			else
			{ assert(0, "Unable to resyntax plain text."); }
		} 
		
		void fillSyntax(SyntaxKind sk)
		{
			static TextStyle ts; ts.applySyntax(sk); 
			rows	.map!(r => r.glyphs).joiner.filter!"a"
				.each!(
				(g){
					g.bkColor = ts.bkColor; 
					g.fontColor = ts.fontColor; 
					g.fontFlags = ts.fontFlags; 
					//Todo: refactor this 3 assignments.
				}  
			); 
			//Todo: fill row.bkColor
		} 
		
		void fillBkColor(RGB bkc)
		{
			bkColor = bkc; 
			foreach(r; rows) r.fillBkColor(bkc); 
		} 
		
		void fillColor(RGB fc, RGB bkc)
		{
			bkColor = bkc; 
			foreach(r; rows) r.fillColor(fc, bkc); 
		} 
		
		override inout(Container) getParent() inout
		{ return parent; } 
		override void setParent(Container p)
		{ parent = p; } 
		
		override void appendCell(Cell cell)
		{
			assert(cast(CodeRow)cell); 
			super.appendCell(cell); 
		} 
		
		auto const rows()
		{ return cast(CodeRow[])subCells; } 
		int rowCount() const
		{ return cast(int)subCells.length; } 
		int lastRowIdx() const
		{ return rowCount-1; } 
		int lastRowLength() const
		{ return rows.back.cellCount; } 
		
		auto getRow(int rowIdx)
		{ return rowIdx.inRange(subCells) ? rows[rowIdx] : null; } 
		
		auto firstRow()
		{ return rows.frontOrNull; } 
		auto lastRow()
		{ return rows.backOrNull; } 
		
		T firstCell(T=Cell)()
		{ return firstRow ? cast(T) firstRow.subCells.frontOrNull : null; } 
		
		int rowCharCount(int rowIdx) const
		{
			//Todo: it's ugly because of the constness. Make it nicer.
			if(rowIdx.inRange(subCells))
			return cast(int)((cast(CodeRow)subCells[rowIdx]).subCells.length); 
			return 0; 
		} 
		
		alias rowCellCount = rowCharCount; 
		
		final string sourceText()
		{
			SourceTextBuilder builder; 
			builder.put(this); 
			return builder.result; 
		} 
		
		auto byShallowChar(dchar lineSep = '\n')()
		{ return rows.map!(r => r.chars).joiner(only(lineSep)); } 
		
		dchar firstChar()
		{ return byShallowChar.frontOr('\U00000000'); } 
		
		T firstCell(T:Cell = Cell)()
		{
			//newline is not a valid first cell -> it does access viola
			if(auto r = getRow(0))
			return cast(T) r.subCells.get(0); 
			return null; 
		} 
		
		TextCursor homeCursor()
		{ return TextCursor(this, ivec2(0)); } 
		TextCursor endCursor()
		{ return TextCursor(this, ivec2(lastRowLength, rowCount-1)); } 
		TextSelection allSelection(bool primary)
		{ return TextSelection(homeCursor, endCursor, primary); } 
		
		TextSelection homeSelection(bool primary)
		{ return TextSelection(homeCursor, homeCursor, primary); } 
		
		TextSelection endSelection(bool primary)
		{ return TextSelection(endCursor, endCursor, primary); } 
		
		TextSelection lineSelection(bool selectWholeLine)(int line, bool primary)
		{
			auto y = line-1; 
			if(y.inRange(rows))
			{
				auto ts = TextSelection(TextCursor(this, ivec2(0, y)), primary); 
				if(selectWholeLine) ts.cursors[1].move(ivec2(TextCursor.end, 0)); 
				return ts; 
			}
			return TextSelection.init; 
		} 
		
		TextSelection lineSelection_home(int line, bool primary)
		{ return lineSelection!false(line, primary); } 
		
		TextSelection cellSelection(int line, int column, bool primary)
		{
			auto ts = lineSelection_home(line, primary); 
			if(ts) {
				auto dx = (column-1).clamp(0, rowCharCount(ts.cursors[0].pos.y)); 
				if(dx) ts.move(ivec2(dx, 0), false); 
			}
			return ts; 
		} 
		
		TextCursor cursorOf(Cell cell)
		{
			/+Opt: It's slow.+/
			if(cell)
			foreach(y; 0..rowCount)
			{
				const x = rows[y].subCellIndex(cell); 
				if(x>=0) return TextCursor(this, ivec2(x, y)); 
			}
			return TextCursor.init; 
		} 
		
		TextSelection selectionOf(Cell cell1, Cell cell2, bool primary)
		{
			if(auto c1 = cursorOf(cell1))
			if(auto c2 = cursorOf(cell2))
			{
				sort(c1, c2); c2.pos.x++; 
				return TextSelection(c1, c2, primary); 
			}
			return TextSelection.init; 
		} 
		
		
		string shallowText(dchar objectChar=compoundObjectChar)()
		{ return rows.map!(r => r.shallowText!objectChar).join('\n'); } 
		
		//index, location calculations
		int maxIdx() const
		{
			//inclusive end position
			assert(rowCount>0); 
			return rows.map!(r => r.cellCount + 1/+newLine+/).sum - 1/+except last newLine+/; 
		} 
			
		ivec2 idx2pos(int idx) const
		{
			if(idx<0) return ivec2(0); //clamp to min
			
			const rowCount = this.rowCount; 
			assert(rowCount>0, "One row must present even when the CodeColumn is empty."); 
			int y; 
			while(1) {
				const actRowLen = rows[y].cellCount+1; 
				if(idx<actRowLen)
				{ return ivec2(idx, y); }
				else
				{
					y++; 
					if(y<rowCount)
					{ idx -= actRowLen; }
					else
					{
						return ivec2(rows[rowCount-1].cellCount, rowCount-1); //clamp to max
					}
				}
			}
		} 
		
		int pos2idx(ivec2 p) const
		{
			if(p.y<0) return 0; //clamp to min
			if(p.y>=rowCount) return maxIdx; //lamp to max
			return rows[0..p.y].map!(r => r.cellCount+1).sum + clamp(p.x, 0, rows[p.y].cellCount); 
		} 
		
		void initializeBorder()
		{
			this.setRoundBorder(8); 
			margin = Margin(.5, .5, .5, .5); //Todo: need more clever constructors for Margion
			padding = Padding(.5, 4, .5, 4); 
		} 
		
		void applyHalfSize()
		{
			halfSize = true; //no going back...
			
			margin.set(0); 
			border = Border.init; 
			padding.set(0, 2); 
			
			foreach(r; rows) r.applyHalfSize; 
			needMeasure; 
		} 
		
		void applyNoBorder()
		{
			border = Border.init; 
			padding.right = 2; 
			padding.left = 2; 
			//margin is ok
			needMeasure; 
		} 
		
		void adjustWidth(float Δw)
		{
			if(Δw)
			{
				outerSize.x += Δw; 
				auto lastPage = ((cachedPageRowRanges.length) ?((cast(CodeRow[])(cachedPageRowRanges.back))):(rows)); 
				foreach(row; lastPage) { row.outerSize.x += Δw; }
			}
		} 
		
		Row[][] cachedPageRowRanges; 
		override Row[][] getPageRowRanges()
		{ return cachedPageRowRanges; } 
		
		override void rearrange()
		{
			cachedPageRowRanges = []; 
			
			//Note: Can't cast to CodeRow because "compiler.err" has Rows. Also CodeNode is a Row.
			auto rows = cast(Row[])subCells; 
			assert(rows.map!(a => cast(Row)a).all); 
			
			if(rows.empty)
			{ innerSize = DefaultFontEmptyEditorSize; }
			else
			{
				//measure and spread rows vertically rows
				float y=0, maxW=0; 
				const totalGap = rows.front.totalGapSize; //Note: assume all rows have the same margin, padding, border settings
				foreach(r; rows) {
					r.measure; 
					r.outerPos = vec2(0, y); 
					y += r.innerHeight+totalGap.y; 
				}
				
				if(flags.columnElasticTabs)
				{
					processElasticTabs (cast(Cell[])(rows)); 
					/+Opt: apply this to a subset that has been remeasured+/
				}
				if(flags.columnIsTable)
				{ processTableRows (cast(CodeRow[])(subCells)); }
				
				const maxInnerWidth = rows.map!"a.contentInnerWidth".maxElement; 
				innerSize = vec2(maxInnerWidth + totalGap.x, y); 
				/+
					Todo: this is not possible with the immediate UI because the autoWidth/autoHeigh 
					information is lost. And there is no functions to return the required content size.
					The container should have a current size, a minimal required size and separate autoWidth flags.
					
					row.contentInnerWidth() is NOT compatible with adjustCodeContainerWidth()!!!
					adjustCodeContainerWidth extends
				+/
				
				if(!flags.dontStretchSubCells)
				foreach(r; rows) r.innerWidth = maxInnerWidth; 
				
				enum enableColumnBreaks = true; 
				static if(enableColumnBreaks)
				{
					if(getStructureLevel >= StructureLevel.structured)
					{ cachedPageRowRanges = rearrangePages_byLastRows!isBreakRow(MultiPageGapWidth); }
					/+
						Todo: Must revisit MultiPage support in Columns!!!
						This should'nt be a post process thing! 
						This mess is only used here anyways.
					+/
				}
			}
			
			static if(rearrangeLOG) LOG("rearranging", this); 
		} 
		
		override void draw(Drawing dr)
		{
			enum enableNestedNodeSmoothing = true; 
			static if(enableNestedNodeSmoothing)
			{
				const savedBkColor = bkColor; 
				
				/+
					Note: This effect softens the contours of nested codeNodes. 
					It uses a dimmer average color.
				+/
				/+Opt: Calculate this effect only once.+/
				
				if(auto singleNode = (cast(CodeNode)(singleCellOrNull)))
				if(auto parentNode = (cast(CodeNode)(parent)))
				{
					if(!parentNode.isTableCell)
					bkColor = mix(parentNode.bkColor, singleNode.bkColor, .5f).mix(bkColor, .18f); 
				}
				
				super.draw(dr); 
				
				bkColor = savedBkColor; 
			}
			else
			{ super.draw(dr); }
			
			void drawMultiPageGaps(Drawing dr)
			{
				auto pages = cachedPageRowRanges; 
				
				if(pages.length<2) return; 
				
				dr.translate(innerPos); scope(exit) dr.pop; 
				
				const ofs = -1; //min(DefaultFontHeight/2, innerHeight*.25f);
				auto 	y0 = ofs,
					y1 = innerHeight - ofs; 
				
				dr.lineWidth = .5f; 
				if(auto n = cast(CodeNode) getParent)	dr.color = n.bkColor; 
				else	dr.color = clGray; 
				
				foreach(x; pages.drop(1).map!(a => a.front.outerLeft - MultiPageGapWidth/2))
				dr.vLine(x, y0, y1); 
			} 
			drawMultiPageGaps(dr); 
			
			//visualize changed/created/modified
			addGlobalChangeIndicator(dr, this/*, topLeftGapSize*.5f*/); 
			
			if(0) if(edited) { dr.lineWidth = -2; dr.color = clFuchsia; dr.drawRect(outerBounds); }
			
			//visualize structuredLevel
			if(visualizeStructureLevels)
			{
				dr.color = syntaxFontColor(getSyntax('a')); //clWow[2+getStructureLevel];
				dr.lineWidth = -2; 
				dr.drawRect(outerBounds); 
			}
		} 
		
		
		@property RGB avgColor()
		{
			RGBSum sum; 
			
			foreach(row; rows)
			with(row.avgColor)
			if(xRange)
			sum.add(color, xRange.size); 
			//Note: This is cached in CodeRow. I dont thint it should be cached here too.
			
			return sum.avg(bkColor); 
		} 
		
		
		
		void removeVerticalTabs()
		{
			foreach(row; rows) row.removeVerticalTab; 
			//Todo: These are raw operations, trashing the undo buffer.
			//Todo: must refactor to sequence of editing commands.
		} 
		
		bool addVerticalTabs(float targetHeight)
		{
			bool anyChg; 
			float y0 = 0; 
			
			auto pageHeight = targetHeight; 
			const totalHeight = rows.map!((r)=>(r.outerHeight)).sum; 
			const numPages = (iceil(totalHeight / pageHeight)).max(1); 
			if(numPages<=1) return anyChg; 
			
			pageHeight = totalHeight / numPages; 
			
			int actPages; 
			foreach(row; rows)
			if(row.outerBottom - y0 >= pageHeight)
			{
				y0 = row.outerBottom; 
				row.addVerticalTab; 
				
				actPages++; 
				if(actPages > numPages-1) break; 
			}
			return anyChg; 
			
			//Todo: These are raw operations, trashing the undo buffer.
		} 
		
		static void selfTest()
		{
			void test_RowCount(string src, int rowCount, string dst="*")
			{
				if(dst=="*") dst = src; 
				auto cc = scoped!CodeColumn(null); 
				cc.rebuilder.appendPlain(src); 
				void expect(T, U)(T a, U b)
				{ if(a!=b) ERR("Test fail: "~[src, rowCount.text, dst].text~" : "~a.text~" != "~b.text); } 
				expect(cc.rows.length, rowCount); 
				expect(cast(ubyte[])dst, cast(ubyte[])(cc.shallowText)); 
			} 
			
			test_RowCount("", 1); 
			test_RowCount(" ", 1); 
			test_RowCount("\n", 2); 
			test_RowCount("\n ", 2, "\n "); 
			/+
				Todo: a tabokat visszaalakitani space-ra. Csak a leading comment/whitespace-re menjen,
				 az elastic tabokat meg egymas ala kell igazitani space-ekkel.
				De ezt majd kesobb. Most minden tab lesz.
			+/
			
			test_RowCount("\r\n", 2, "\n"); 
			test_RowCount(" \n \n \r\n", 4, " \n \n \n"); //Todo: a tabokat visszaalakitani space-ra
			test_RowCount(" \n \n \r\n ", 4, " \n \n \n "); //Todo: a tabokat visszaalakitani space-ra
		} 
		
		static processTableRows(CodeRow[] rows)
		{
			static void adjustCodeContainerWidth(CodeContainer cntr, float w)
			{
				enum epsylon = .01f; 
				if(const Δw = w - cntr.outerSize.x)
				if((magnitude(Δw))>=epsylon)
				{
					cntr.outerSize.x = w; 
					cntr.content.adjustWidth(Δw); //adjust the actual CodeColumn
					//Adjust the postfix inside the CodeContainer too
					cntr.subCells.map!(a=>(cast(Glyph)(a))).retro.until!(g=>g is null).each!((g){ g.outerPos.x += Δw; }); 
				}
			} 
			
			static auto asFullRowComment(CodeRow row)
			{ return (cast(CodeComment)(row.singleCellOrNull)); } 
			
			/+
				Todo: Make this fully compatibe with multiple pages (Vertical Tabs).
				Must revisit MultiPage support in Columns!!!
			+/
			//Todo: adjustWidth should be universal amongst all classes...
			//Todo: cells are only expanding, not shrinking when edited...
			//Todo: mouse click on a table cell on the surface below the empty row -> Put the cursor in the row!!!
			
			static struct ColWidths
			{
				float[] colWidths; 
				float fullWidth = 0; 
				alias colWidths this; 
				@property opCast(B : bool)() const
				{ return !colWidths.empty; } 
				
				this(CodeRow[] rows)
				{
					foreach(row; rows)
					{
						if(auto cmt = asFullRowComment(row))
						{
							//Note: Handle full-length comment rows
							fullWidth.maximize(cmt.outerWidth); 
						}
						else
						{
							int idx=0; 
							foreach(rng; row.subCells.splitWhen!mixinTableSplitFun)
							{
								float calcCellWidth()
								{
									if(isMixinTableCell(rng.front))
									{ return rng.front.outerWidth; }
									else
									{ return rng.map!"a.outerWidth".sum; }
								} 
								
								if(colWidths.length<=idx)
								{
									colWidths ~= 0; 
									//only igrows by one, no while() needed
								}
								
								colWidths[idx++/+advance loop+/].maximize(calcCellWidth); 
							}
						}
					}
				} 
				
				void alignCommentRowsWithLastColumns()
				{
					//synch the right edge of the last cell with the commentRowWidth
					const cwSum =  colWidths.sum; 
					if(fullWidth>cwSum)
					{
						//extend rightmost column (if there is one)
						if(colWidths.length) colWidths.back += fullWidth - cwSum; 
					}
					else
					{
						//extend fullWidth up to the columns
						fullWidth = cwSum; 
					}
				} 
				
				void applyTo(CodeRow[] rows)
				{
					//spread colWidths
					foreach(row; rows)
					{
						if(auto cmt = asFullRowComment(row))
						{
							cmt.outerPos.x = 0; 
							adjustCodeContainerWidth(cmt, fullWidth); 
						}
						else
						{
							int idx=0; float actX=0; 
							foreach(rng; row.subCells.splitWhen!mixinTableSplitFun)
							{
								if(isMixinTableCell(rng.front))
								{
									const w = colWidths[idx]; 
									auto cntr = (cast(CodeContainer)(rng.front)); 
									
									cntr.outerPos.x = actX; 
									adjustCodeContainerWidth(cntr, w); 
									
									actX += w; 
								}
								else
								{
									const nextX = actX + colWidths[idx]; 
									foreach(cell; rng)
									{
										cell.outerPos.x = actX; 
										actX += cell.outerSize.x; 
									}
									
									/+
										Todo: Handle extra gap after the text 
										when clicking with mouse
									+/
									actX = nextX; 
								}
								idx++/+advance loop+/; 
							}
							
							//spread container heights
							const maxHeight = row	.subCells.map!"a.outerHeight"
								.maxElement(0); 
							foreach(cntr; row.byNode!MixinTableContainerClass)
							{
								cntr.outerSize.y = maxHeight; 
								/+
									Todo: Implement column.adjustHeight() too!!!!  
									Danger: There will be deadzone there!!!
								+/
							}
						}
						
						row.outerWidth = fullWidth; /+
							Must extend the rows to 
							the width of their contents!
						+/
					}
				} 
			} 
			
			void alignNestedTables(CodeRow[] rows, in ColWidths colWidths)
			{
				auto tableColumn(size_t idx)
				{ return rows.map!(r=>r.subCells.get(idx)); } 
				
				static NiceExpression extractNestedTable(Cell cell)
				{
					if(auto tstr = (cast(CodeString)(cell)))
					if(tstr.type==CodeString.Type.tokenString)
					if(auto ne = (cast(NiceExpression)(tstr.content.singleCellOrNull)))
					if(ne.operator.among(`表`)) return ne; 
					return null; 
				} 
				
				bool anyTablesRealigned = false; 
				foreach(cIdx; 0..colWidths.length)
				{
					NiceExpression[] tables; 
					if(
						tableColumn(cIdx).all!((c){
							if(auto nt = extractNestedTable(c))
							{ tables~=nt; return true; }
							
							//these cells are just valid in a column with nested tables
							if(
								!c /+nonExistent table cell+/
								|| (cast(CodeComment)(c))
								|| (cast(CodeString)(c))
							) return true; 
							
							//the rest is invalid
							return false; 
						})
						&& tables.length>=2
					)
					{
						//check if all the table headers are compatible
						//Todo: null check!!
						static getHdr(NiceExpression ne)
						{
							if(auto col = ne.operands[0])
							if(auto row = col.rows.frontOrNull)
							if(row.subCells.all!(c=>(cast(CodeComment)(c))))
							return row.sourceText; 
							return ""; 
						} 
						
						float maxTableContainerOuterWidth = 0; 
						
						foreach(tableGroup; tables.chunkBy!((a,b)=>getHdr(a)==getHdr(b)).map!array)
						if(
							tableGroup.length>=2 
							&& getHdr(tableGroup.front)!="" /+NestedTables must have headers+/
						)
						{
							auto nestedRows = tableGroup.map!(grp=>grp.operands[0].rows).join; 
							
							//realign all nested rows
							if(auto nestedColWidths = ColWidths(nestedRows))
							{
								nestedColWidths.alignCommentRowsWithLastColumns; 
								nestedColWidths.applyTo(nestedRows); 
								
								//Enlarge the nested tables.
								foreach(tbl; tableGroup)
								{
									auto col = tbl.operands[0]; 
									//At this point: all the outerWidth of the rows are extended to the full table
									if(const Δw = nestedColWidths.fullWidth - col.innerWidth)
									{
										anyTablesRealigned = true; 
										col.outerWidth += Δw; 
										tbl.outerWidth += Δw; 
										tbl.subCells	.retro.until!(a=>!(cast(CodeNode)(a)))
											.each!((c){ c.outerPos.x += Δw; }); 
										//Todo: refactor this:  This enlarges the operands[0] of a NiceExpression.
										//Adjust the 'cell' that contains the table too.
										if(auto rowOfTbl = (cast(CodeRow)(tbl.parent)))
										{
											if(const Δr = tbl.outerWidth - rowOfTbl.outerWidth)
											{
												rowOfTbl.outerWidth += Δr; 
												if(auto colOfTbl = rowOfTbl.parent)
												{
													colOfTbl.outerWidth += Δr; 
													if(auto cntrOfTbl = (cast(CodeContainer)(colOfTbl.parent)))
													{
														cntrOfTbl.outerWidth += Δr; 
														maxTableContainerOuterWidth.maximize(cntrOfTbl.outerWidth); 
													}
												}
											}
										}
									}
								}
							}
						}
						
						/+extend the width comments, which are in the column of the nested tables as well.+/
						if(maxTableContainerOuterWidth)
						{
							foreach(cntr; tableColumn(cIdx).map!(a=>(cast(CodeContainer)(a))).filter!"a")
							{ adjustCodeContainerWidth(cntr, maxTableContainerOuterWidth); }
						}
					}
				}
				
				if(anyTablesRealigned)
				{
					//spread the tableCells in the TableRows properly.
					foreach(r; rows)
					{
						r.subCells.spreadH; 
						r.outerWidth = r.subCells.map!(c=>c.outerRight).backOr(0.0f); 
					}
					
					//extent the full line comments too
					const totalTableWidth = rows.map!(r=>r.outerWidth).maxElement; 
					foreach(cmt; rows.map!(r=>(cast(CodeComment)(r.singleCellOrNull))).filter!"a")
					{ adjustCodeContainerWidth(cmt, totalTableWidth); }
				}
			} 
			
			//Main processing -----------------------------------------------------------------------------
			if(auto colWidths = ColWidths(rows))
			{
				colWidths.alignCommentRowsWithLastColumns; 
				colWidths.applyTo(rows); 
				
				alignNestedTables(rows, colWidths); 
			}
		} 
	} 
}