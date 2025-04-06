module diderow; 

import didebase, het.parser; 
import didenode : CodeContainer, CodeComment; 
import didedecl : Declaration; 
import didemodule : addGlobalChangeIndicator; 


version(/+$DIDE_REGION+/all) {
	struct SourceTextBuilder
	{
		enum CODE = true, UI = !CODE; 
		
		string result; 
		
		int lineCounter = 1; 
		int indentCount; 
		
		bool enableIndent = true; 
		bool needsNewLine, backslashNewLine; //to support //comments and #directives
		bool updateLineIdx; 
		
		bool actLineIsClear()
		{
			auto s = result; 
			while(s.endsWith('\t')) s = s[0..$-1]; 
			if(s=="" || s.endsWith(DefaultNewLine)) return true; 
			return false; 
		} 
		
		void putNL(int indentAdjust = 0)()
		{
			if(backslashNewLine)
			{
				//The loader replaces \ with spaces, so this will try to replace whitespace with \.
				if(result.length && result.back.among(' ', '\t'))	*(cast(char*)(&result[$-1])) = '\\'; 
				else	result ~= '\\'; 
			}
			
			result ~= DefaultNewLine; 
			
			if(enableIndent)
			result ~= "\t".replicate(max(0, indentCount + indentAdjust)); 
			
			lineCounter++; 
			needsNewLine = false; 
		} 
		
		void put(dchar ch)
		{
			
			assert(!ch.isDLangNewLine, "It's illegal to add newLine using put().  Use putNL() instead!"); 
			
			if(needsNewLine) putNL; 
			result ~= ch; 
		} 
		
		void put(string str)
		{
			if(str=="") return; 
			assert(str.byDchar.all!(not!isDLangNewLine), "It's illegal to add newLine using put().  Use putNL() instead!"); 
			
			if(needsNewLine) putNL; 
			result ~= str; 
		} 
		
		void put(CodeRow row)
		{
			if(updateLineIdx)
			{ row.lineIdx = lineCounter; }
			
			put(row.subCells); 
		} 
		
		void putStatementBody(CodeColumn col)
		{
			foreach(i, row; col.rows) {
				if(i) putNL; 
				put(row); 
			}
		} 
		
		void adjustCustomPrefix(ref string customPrefix, CodeColumn col)
		{
			//adjust the stylistic space after the customPrefix
			if(customPrefix != "")
			{
				if(col.empty)
				{ if(customPrefix.endsWith(' ')) customPrefix = customPrefix[0 .. $-1]; }
				else
				{ if(customPrefix.length && !customPrefix.endsWith(' ')) customPrefix ~= ' '; }
			}
		} 
		
		void putSeparatorSpace()
		{
			if(result.length && result.back.isDLangIdentifierCont)
			put(' '); 
		} 
		
		void put(CodeColumn col, string customPrefix="")
		{
			if(!col.rowCount) return; 
			//Todo: there should be no CodeColumns without at least a single CodeRow inside. -> invatiant{}
			
			//assert(col.rowCount>0, "Empty col: "~col.rowCount.text);
			
			const isMultiLine = col.rowCount>1; 
			/+Todo: ennek rekurzivnak kellene lennie. Ebben a peldaban belul van a multiline rekurziv modon. { a({ b;<NL>c; }); }+/
			
			/+
				Note: custom prefix example for "Prefix: ":
				
				(Prefix: single line)
				
				(
					Prefix: first line
					second line
				)
			+/
			
			adjustCustomPrefix(customPrefix, col); 
			
			void putMultiLine()
			{
				indentCount++; 
				scope(exit) indentCount--; 
				
				foreach(i, row; col.rows)
				{
					putNL; 
					if(i==0) put(customPrefix); 
					put(row); 
				}
				
				putNL!(-1); 
			} 
			
			if(enableIndent)
			{
				if(isMultiLine || needsNewLine)
				{ putMultiLine; }
				else
				{
					assert(col.rows.length == 1); 
					auto row = col.rows.front; 
					
					const stylisticSpaces = result.endsWith('{') && !result.endsWith("q{") && row.chars.length>0; 
					
					version(/+$DIDE_REGION Save the state of the output stream+/all)
					{
						const savedLineCounter = lineCounter; 
						const savedLength = result.length; 
					}
					
					const firstLineIsClear = actLineIsClear; 
					
					if(stylisticSpaces && (cast(Declaration) row.subCells.front)) put(' '); 
					put(customPrefix); 
					put(row); /+
						Opt: this should exit right at the first newline to do that putMultilineOperation.
						But only when the if condition before the state restore operation is true.
					+/
					if(!autoSpaceAfterDeclarations /+Note: Because this would be a double spase+/)
					if(stylisticSpaces && !row.isCodeSpaces.back) put(' '); 
					
					if(!firstLineIsClear && (needsNewLine || lineCounter > savedLineCounter))
					{
						//it's actually a multiline block. Rollback and repeat.
						
						//restore the output stream
						version(/+$DIDE_REGION Restore the state of the output stream+/all)
						{
							result.length = savedLength; 
							lineCounter = savedLineCounter; 
						}
						
						putMultiLine; 
					}
				}
			}
			else
			{
				put(customPrefix); 
				putStatementBody(col); 
			}
		} 
		
		void put(Cell cell)
		{
			if(auto glyph = cast(Glyph) cell)
			{
				if(updateLineIdx) glyph.lineIdx = lineCounter; 
				put(glyph.ch); 
			}
			else if(auto node = cast(CodeNode) cell)
			{
				if(updateLineIdx) node.lineIdx = lineCounter; 
				node.buildSourceText(this); 
			}
			else
			enforce(0, "Unsupported cell type: "~typeid(cell).name); 
		} 
		
		void put(R)(R cells)
		if(isInputRange!R && __traits(compiles, cast(Cell) cells.front))
		{ foreach(c; cells) put(c); } 
		
		
		void put(string prefix, string customPrefix, CodeColumn block, string postfix)
		{
			const 	enableIndent_prev 	= enableIndent,
				backslashNewLine_prev 	= backslashNewLine; 
			if(
				!prefix.empty && (
					prefix.back.among('\'', '"', '`', '#')
					|| prefix.get(1)=='"'
				)
			) enableIndent = false; 
			/+prefix="#" is for preprocessor directives, 	and customPrefix will contain the id.+/
			
			if(prefix=="#") backslashNewLine = true; 
			
			scope(exit)
			{
				enableIndent 	= enableIndent_prev, 
				backslashNewLine 	= backslashNewLine_prev; 
			}
			
			
			put(prefix); 
			
			if((prefix=="" && postfix.among(";", ":", "")))
			{
				adjustCustomPrefix(customPrefix, block); 
				put(customPrefix); 
				putStatementBody(block); 
			}
			else
			{ put(block, customPrefix); }
			
			const newLineRequired = !!prefix.startsWith("//", "#"); //Todo: multiline #directive
			if(newLineRequired)
			{
				assert(postfix==""); 
				needsNewLine = true; 
			}
			else
			{ put(postfix); }
		} 
		
		void put(string prefix, CodeColumn block, string postfix)
		{ put(prefix, "", block, postfix); } 
		
		void put(string prefix, CodeColumn block, string postfix, bool showFix)
		{
			if(!showFix)
			{ put(block); }
			else
			{ put(prefix, block, postfix); }
		} 
	} 
	class CodeRow: Row
	{
		CodeColumn parent; 
		
		int lineIdx; 
		bool halfSize; 
		
		protected AvgColor _avgColor; 
		
		static if(rearrangeFlash) DateTime rearrangeTime; 
		
		override inout(Container) getParent() inout
		{ return parent; } 
		override void setParent(Container p)
		{ parent = enforce(cast(CodeColumn)p); } 
		
		int index()
		{ return parent.subCellIndex(this); } 
		
		bool empty() const
		{ return subCells.empty; } 
		
		size_t length() const
		{ return subCells.length; } 
		
		auto singleCellOrNull()
		{ return subCells.length==1 ? subCells[0] : null; } 
		
		auto singleNodeOrNull()
		{ return (cast(CodeNode)(singleCellOrNull)); } 
		
		auto firstCellOrNull()
		{ return subCells.get(0); } 
		
		auto firstNodeOrNull()
		{ return (cast(CodeNode)(firstCellOrNull)); } 
		
		auto byCell()
		{ return subCells.map!"a"; } 
		
		auto byNode(T : CodeNode = CodeNode)()
		{ return byCell.map!(a=>cast(T)a).filter!"a".cache; } 
		
		auto lastCell(T : Cell = Cell)()
		{ return (cast(T)(subCells.backOrNull)); } 
		
		auto lastNode() => lastCell!CodeNode; 
		auto lastComment() => lastCell!CodeComment; 
		
		
		auto glyphs()
		{ return subCells.map!(c => cast(Glyph)c); } //can return nulls
		
		auto chars(dchar objectChar=compoundObjectChar)()
		{ return glyphs.map!(a => a ? a.ch : objectChar); } 
		
		string shallowText(dchar objectChar=compoundObjectChar)()
		{ return chars!objectChar.to!string; } 
		//Todo: combine this with extractThisLevelDString
		
		//Todo: mode isSpace inside elastic tab detection, it's way too specialized
		
		private static bool isIndentableSyntax(T)(T sk)
		{
			return !!sk.among(skWhitespace, skComment); 
			/+don't count string literals, their indent must be preserved!+/
		} 
		
		//Todo: refactor isCode* to isIndentable*
		private static bool isCodeSpace(Cell c)
		{
			if(auto g = cast(Glyph)c)
			return g.ch==' ' && isIndentableSyntax(g.syntax); 
			return false; 
		} 
		private static bool isCodeTab(Cell c)
		{
			if(auto g = cast(Glyph)c)
			return g.ch=='\t' && isIndentableSyntax(g.syntax); 
			return false; 
		} 
		private static bool isAnyWhitespace(Cell c)
		{
			if(auto g = cast(Glyph)c)
			return !!g.ch.among(' ', '\t'); 
			return false; 
		} 
		auto isCodeSpaces()
		{ return subCells.map!isCodeSpace; } 
		
		auto leadingCodeSpaces()
		{ return subCells.until!(not!isCodeSpace	); } 
		auto leadingCodeTabs()
		{ return subCells.until!(not!isCodeTab	); } 
		auto leadingAnyWhitespaces()
		{ return subCells.until!(not!isAnyWhitespace	); } 
		
		auto leadingCodeSpaceCount()
		{ return cast(int)leadingCodeSpaces.walkLength; } 
		auto leadingCodeTabCount()
		{ return cast(int)leadingCodeTabs.walkLength; } 
		auto leadingAnyWhitespaceCount()
		{ return cast(int)leadingAnyWhitespaces.walkLength; } 
		
		auto codeTabCount()
		{ return subCells.count!isCodeTab; } 
		
		bool isDLangIdentifier()
		{ return chars.isDLangIdentifier; } 
		
		
		this(CodeColumn parent_)
		{
			parent = enforce(parent_); 
			id.value = this.identityStr; 
			
			needMeasure; 
			//also sets measureOnlyOnce flag. This is an on-demand realigned Container.
			
			flags.wordWrap	= false; 
			flags.clipSubCells	= true; 
			flags.cullSubCells	= true; 
			flags.rowElasticTabs	= false; 
			flags.dontHideSpaces	= true; 
			flags.noBackground	= true; 
			
			//bkColor = parent.bkColor;
		} 
		
		this(CodeColumn parent_, string line, ubyte[] syntax)
		{
			assert(line.length==syntax.length); 
			this(parent_); 
			set(line, syntax); 
		} 
		
		void set(string line, ubyte[] syntax)
		{
			//set is called from CodeColumnBuilder.
			internal_setSubCells([]); 
			
			static TextStyle style; //it is needed by appendCode/applySyntax
			this.appendCode(
				line, syntax, (ubyte s){ applySyntax(style, s); }  ,
				style/+, must paste tabs!!! DefaultIndentSize+/
			); 
			
			//Note: tabIdx is already refreshed by appendCode
			//spreadElasticNeedMeasure;
		} 
		
		this(CodeColumn parent_, string line)
		{
			this(parent_); 
			insertText(0, line); 
		} 
		
		this(CodeColumn parent_, Cell[] cells)
		{
			this(parent_); 
			
			//take ownership of the cells.
			cells.each!(c => c.setParent(this)); 
			subCells = cells; 
			refreshTabIdx; 
			needMeasure; 
			/+
				Note: this is used from the high level parser.
				It will sort out elastic tabs, but elastic tabs should be updated automatically somehow...
			+/
		} 
		
		final string sourceText()
		{
			//Todo: refactor this as a template mixin
			SourceTextBuilder builder; 
			builder.put(this); 
			return builder.result; 
		} 
		
		CaretPos localCaretPos(int idx)
		{
			const len = cellCount; 
			if(len==0) return CaretPos(vec2(0, 0), innerHeight); 
			
			idx = idx.clamp(0, len); 
			//if(idx<0 || idx>len) return CaretPos.init;
			
			if(idx==len) with(subCells.back) return CaretPos(outerTopRight, outerHeight); 
			if(idx==0) with(subCells[0]) return CaretPos(outerPos, outerHeight); 
			
			const 	y0 = min(subCells[idx-1].outerTop   , subCells[idx].outerTop   ),
				y1 = max(subCells[idx-1].outerBottom, subCells[idx].outerBottom); 
			
			return CaretPos(vec2(subCells[idx].outerLeft, y0), y1-y0); 
		} 
		
		bounds2 newLineBounds()
		{
			const p = newLinePos; 
			return bounds2(p, p + DefaultFontNewLineSize); 
		} 
		
		vec2 newLinePos()
		{ return vec2(cellCount ? subCells.back.outerRight : 0, (innerHeight-DefaultFontHeight)*.5f); } 
		
		/// Returns inserted count
		int insertSomething(int at, void delegate() appendFun)
		{
			enforce(at>=0 && at<=subCells.length, "Out of bounds"); 
			
			auto after = subCells[at..$]; 
			subCells = subCells[0..at]; 
			
			const cnt0 = subCells.length; 
			
			appendFun(); 
			
			const insertedCnt = (subCells.length-cnt0).to!int; 
			if(insertedCnt) setChangedCreated; 
			
			subCells ~= after; 
			
			refreshTabIdx; 
			needMeasure; 
			spreadElasticNeedMeasure; 
			
			return insertedCnt; 
		} 
		
		/// Returns inserted count
		int insertText(int at, string str)
		{
			if(str.empty) return 0; 
			const res = insertSomething
			(
				at, {
					CodeColumn col = parent.enforce("CodeRow must have a CodeColumn parent."); 
					const syntax = col.getSyntax(str.empty ? ' ' : str.front); 
					this.appendCodeStr(str, syntax); 
				}  
			); 
			
			return res; 
		} 
		
		/// Splits row into 2 rows. Returns the newli created row which is NOT yet inserted to the column.
		CodeRow splitRow(int x)
		{
			assert(x>=0 && x<=cellCount); 
			
			auto nextRow = new CodeRow(parent); 
			nextRow.setChangedCreated; 
			
			nextRow.subCells = this.subCells[x..$]; 
			nextRow.adoptSubCells; 
			this.subCells = this.subCells[0..x]; 
			
			if(nextRow.subCells.length)
			this.setChangedRemoved; 
			
			only(this, nextRow).each!"a.refreshTabIdx"; 
			only(this, nextRow).each!"a.spreadElasticNeedMeasure"; 
			
			return nextRow; 
		} 
		
		///must be called after the code changed. It tracks elasticTabs, and realigns if needed
		void spreadElasticNeedMeasure()
		{
			//Todo: such beautyful name... NOT!
			if(needMeasure)
			{
				
				//extend up and down along elastic tabs
				auto i = index; //Opt: this index calculation is slow. Feed index from the inside
				assert(i>=0); 
				
				//simple but unefficient criteria: has any tabs or not
				foreach(a; mixin(指(q{parent.rows},q{0..i})).retro.until!"!a.tabIdxInternal.length") if(!a.needMeasure) break; 
				foreach(a; mixin(指(q{parent.rows},q{i+1..$})).until!"!a.tabIdxInternal.length") if(!a.needMeasure) break; 
			}
		} 
		
		override void rearrange()
		{
			assert(verifyTabIdx, "tabIdxInternal check fail"); 
			
			invalidateAvgColor; 
			adjustCharWidths; 
			innerSize = vec2(0); flags.autoWidth = true; flags.autoHeight = true; 
			super.rearrange; 
			
			{
				vec2 v = innerSize; 
				if(empty) v.maximize(DefaultFontEmptyEditorSize * ((halfSize) ?(SubScriptFontScale):(1))); 
				if(empty && parent.rowCount>1) v.y /= 2; 
				innerSize = v; 
			}
			
			static if(rearrangeLOG) LOG("rearranging", this); 
			static if(rearrangeFlash) rearrangeTime = now; 
			
			//Opt: Row.flexSum <- ezt opcionalisan ki kell kiiktatni, lassu.
		} 
		
		@property hasVerticalTab() => chars.endsWith('\x0b'); 
		
		void removeVerticalTab()
		{
			if(hasVerticalTab)
			{
				subCells = subCells[0 .. $-1]; 
				needMeasure; 
			}
		} 
		
		void addVerticalTab()
		{
			if(!hasVerticalTab)
			{
				static TextStyle tsVT; 
				static bool initialized; if(initialized.chkSet) tsVT.applySyntax(skIdentifier1); 
				
				appendChar('\x0b', tsVT); 
				needMeasure; 
			}
		} 
		
		
		void applyHalfSize()
		{
			halfSize = true; //no going back
			
			enum targetHeight 	= DefaultSubScriptFontHeight,
			triggerHeight 	= DefaultFontHeight-1; 
			
			foreach(glyph; glyphs.filter!"a")
			{
				//shrink the text
				if(glyph.outerHeight>=triggerHeight)
				glyph.outerSize *= ((targetHeight)/(glyph.outerHeight)); 
			}
			
			needMeasure; 
		} 
		
		void fillColor(RGB fc, RGB bkc)
		{
			bkColor = bkc; //Todo: Is bkColor used in draw() at all?
			foreach(g; glyphs.filter!"a") {
				g.fontColor = fc; 
				g.bkColor = bkc; 
			}
		} 
		
		void fillBkColor(RGB bkc)
		{
			bkColor = bkc; 
			foreach(g; glyphs.filter!"a") g.bkColor = bkc; 
		} 
		
		
		///Transfer cells and form an error comment from them. Append it into this row.
		void appendError(Cell[] cells)
		{
			//Generate sourceText from problematic cells
			SourceTextBuilder builder; 
			builder.put(cells); 
			auto str = builder.result; 
			
			//Create and append am Error Comment Node
			auto scanner = DLangScanner
				(
				format!"/+Error:%s+/"(
					str	.replace("/+", "/ +")
						.replace("+/", "+ /")
				)
				/+
					This comment is valid, so it can be reloaded later 
					as a valid cell that shows the exact same error.
				+/
			); 
			auto cmt = new CodeComment(this); 
			cmt.rebuild(scanner); 
			this.appendCell(cmt); 
		} 
		
		override float contentInnerWidth() const
		{
			if(subCells.empty) return DefaultFontEmptyEditorSize.x; 
			
			//This is compatible with the MixinTable cells.
			static if(0)
			{
				/+
					Todo: megcsinalni rendesen ezt a helykitolteses realign szopást.
					Olyan egyenletmegoldosnak kene lenni, mint a CAD-ban.  Nem utolag pofozgatasosnak.  
					Ezekkel a cache-olt poziciokkal mindig baj van, de qrvasok az adat cacheolni kell.
				+/
				if(auto cntrNode = (cast(CodeContainer)(subCells.backOrNull)))
				{
					if(auto col = cntrNode.content)
					{
						//this is the last column in the node.
						auto rows = col.cachedPageRowRanges.backOr (cast(Row[])(col.subCells)); 
						const extraSpaceOnTheRight = rows.map!(r=>r.innerWidth - r.contentInnerWidth/+recursion!+/).minElement; 
						return cntrNode.outerRight - extraSpaceOnTheRight
							/+ + (cntrNode.innerSize.x - col.outerRight) + cntrNode.bottomRightGapSize.x+/; 
						//Bug: Last pew pixels are lost on the /+Note:blabla+/ comments. The rightmost frame becomes hidden...
						/+
							Bug: A tablazat jobb szelere kell extra betuket beirni, aztan visszatorolni -> 
								-> A tablazat jobb szelen a kurzor ki fog repulni a visszatorles 
									utan oda, mintha a Row hosszu maradt volna.
						+/
					}
				}
			}
			
			//original behavior
			return subCells.back.outerRight; 
		} 
		
		
		
		version(/+$DIDE_REGION Stuff used by Column only+/all)
		{
			//Todo: These should go elsewhere!  These are private.
			
			int findRowLineIdx_min()
			{
				foreach(cell; subCells) {
					if(auto a = cast(Glyph)cell) { if(a.lineIdx) return a.lineIdx; }
					else if(auto a = cast(CodeNode)cell) { if(a.lineIdx) return a.lineIdx; }
				}
				return 0; 
			} 
			void adjustCharWidths()
			{
				bool isLeading = true; 
				foreach(g; glyphs)
				if(g)
				{
					//Todo: make this nicer
					void setWidth(float w)
					{ g.outerWidth = halfSize ? w*SubScriptFontScale : w; } 
					
					if(isCodeSpace(g))
					{
						setWidth(
							isLeading 	? LeadingSpaceWidth
								: NormalSpaceWidth
						); 
					}
					else
					{
						isLeading = false; 
						
						//non-leading char width modifications
						if(
							g.syntax==skNumber && g.ch!='.'	//number except '.'
							|| g.ch.among('+', '-', '_')	//symbols next to numbers
							/*|| g.syntax==6/+string+/*/
							/+Bug: Write a number in front of an identifier! It turns all the identifier to monospace.+/
						) setWidth(NormalSpaceWidth); 
					}
				}
				else
				{ isLeading = false; }
			} 
			
			void replaceSpacesWithTabs(int xStart, int xTab, size_t tabCount)
			{
				assert(xStart<=xTab	, "invalid xStart, xTab"); 
				assert(xStart>=0	, "xStart out of range"); 
				assert(xTab<subCells.length	, "xTab out of range"); 
				assert(glyphs[xStart..xTab+1].all!(g => isCodeSpace(g))	, "All must be spaces"); 
				assert(tabCount <= xTab-xStart+1	, "tabCount too much."); 
				
				auto normalizeLeadingSpaces(Cell[] sc)
				{
					sc	.until!(a => !(isCodeSpace(a) && a.outerWidth!=NormalSpaceWidth))
						.each!(a => a.outerWidth = NormalSpaceWidth); 
					return sc; 
				} 
				
				internal_setSubCells(
					subCells[0..xStart+tabCount] ~
					(xTab+1<subCells.length ? normalizeLeadingSpaces(subCells[xTab+1..$]) : [])
				); 
				foreach(i; xStart..xStart+tabCount) spaceToTab(i); //promote spaces to tabs
				
				refreshTabIdx; //Todo: should only be done once at the end...
			} 
			
			void convertLeadingSpacesToTabs(int spaceCnt)
			{
				//Todo: tab inside string literal. width is too big  File(`c:\D\libs\!shit\_unused.arsd\html.d`)
				//subCells.each!LOG;
				assert(spaceCnt>0); 
				const tabCnt = leadingCodeSpaceCount/spaceCnt; 
				//LOG(leadingCodeSpaceCount, spaceCnt);
				if(tabCnt>0) {
					const removeCnt = tabCnt*spaceCnt-tabCnt; 
					internal_setSubCells(subCells[removeCnt..$]); 
					foreach(i; 0..tabCnt) spaceToTab(i); 
					refreshTabIdx; //Todo: should only be done once at the end...
				}
			}   ref avgColor()
			{
				if(_avgColor.valid.chkSet)
				_avgColor.recalculate(this); 
				
				return _avgColor; 
			} 
		}
		protected
		{
			static immutable float 	NormalSpaceWidth	= (DefaultFontHeight/18.0f)*7.25f, //same as '0'..'9' and +-_
				LeadingSpaceWidth 	= NormalSpaceWidth; 
			
			
			
			private void spaceToTab(long i)
			{
				auto g = glyphs[i]; 
				assert(isCodeSpace(g)); 
				g.ch = '\t'; 
				g.isTab = true; 
				//Note: refreshTabIdx must be called later
			} 
			
			
			struct AvgColor
			{
				RGB color; 
				bool valid; 
				bounds1 xRange; 
				
				void recalculate(CodeRow row)
				{
					with(row)
					if(subCells.length)
					{
						const lwsCnt = leadingAnyWhitespaceCount; //Opt: this should be memoized
						if(lwsCnt<subCells.length)
						{
							auto cellRange = subCells[lwsCnt..$]; 
							xRange = bounds1(cellRange.front.outerLeft, cellRange.back.outerRight); 
							
							RGBSum sum; 
							
							foreach(cell; cellRange)
							{
								sum.add(
									cell.castSwitch!(
										(Glyph glyph) 	=> mix(glyph.bkColor, glyph.fontColor, .25f),
										(CodeNode node) 	=> node.avgColor,
										(Container cntr) 	=> cntr.bkColor
									), cell.outerSize.area
								); 
							}
							
							color = sum.avg; 
							
							return; //success
						}
					}
					
					xRange = bounds1.init; //nothing to fill
				} 
			} 
			
			void invalidateAvgColor()
			{ _avgColor.valid = false; } 
		} 
		
		
		
		version(/+$DIDE_REGION+/all)
		{
			override void draw(Drawing dr)
			{
				
				enum enableCodeLigatures = true; 
				
				void drawLowDetail()
				{
					with(avgColor)
					if(xRange)
					{
						dr.color = color; enum gap = .125f; 
						auto r = bounds2(xRange.low, innerHeight*gap, xRange.high, innerHeight*(1-gap))+innerPos; 
						dr.fillRect(r); 
					}
				} 
				
				void visualizeTabs()
				{
					foreach(ti; tabIdxInternal)
					{
						assert(ti.inRange(subCells)); 
						auto g = cast(Glyph)subCells.get(ti); 
						assert(g, "tabIdxInternal fail"); 
						if(g) {
							dr.vLine(g.outerRight-2, g.outerTop+2, g.outerBottom-2); 
							//Todo: it is NOT in the horizontal center! (g.outerRight-2)
							
							//const y = g.outerPos.y + g.outerHeight*.5f;
							//dr.vLine(g.outerRight, y-2, y+2);
							//dr.hLine(g.outerLeft+1, y, g.outerRight-1);
						}
					}
				} 
				
				void visualizeSpaces()
				{
					foreach(g; glyphs.filter!(a => a && a.ch==' '))
					{
						assert(g); 
						dr.point(g.outerBounds.center); 
						/+
							Todo: don't highlight single spaces only if there is a tab or character 
							or end of line next to them.
						+/
					}
				} 
				
				void drawLigatures()
				{
					//Todo: --- 3 dashes should be a straight line.   === too.   With | < > at the end too.  With + at the middle.
					if(parent.getSyntax('=')==skSymbol)
					{
						auto r = glyphs; 
						
						while(1)
						{
							static struct Ligature {
								string src; 
								dchar dst; 
								float hScale = 1; 
							} 
							static immutable Ligature[] ligatures = 
							[
								{ "==", '='},
								{ "!=", '≠'},
								{ "<=", '≤', .66},
								{ ">=", '≥', .66},
								{ "=>", '⇒', .66},
								{ ">>=", '\0'},
								{ "<<=", '\0'}
							]; 
							
							auto f = find!((a, b) => a && a.ch==b)(r, aliasSeqOf!(ligatures[].map!"a.src".array)); 
							auto ligatureIdx = (cast(int)f[1])-1; 
							if(ligatureIdx<0) break; 
							const ligature = &ligatures[ligatureIdx]; 
							auto rSrc = f[0][0 .. ligature.src.length]; 
							r = f[0][rSrc.length .. $]; //advance
							if(rSrc[0].syntax != skSymbol) continue; 
							if(!ligature.dst) continue; 
							auto bnd = bounds2(rSrc[0].outerPos, rSrc[$-1].outerBottomRight); 
							
							dr.color = rSrc[0].bkColor; dr.alpha = 1; dr.fillRect(bnd); 
							
							if(ligature.hScale<1)
							{
								const w = bnd.width * ((1-ligature.hScale)/(2)); 
								bnd.left += w; bnd.right -= w; 
							}
							
							static int[ligatures.length] stIdx; 
							if(stIdx[0]==0)
							{
								auto ts = tsNormal; 
								foreach(i, ch; ligatures.map!"a.dst".array)
								stIdx[i] = ch.fontTexture(ts); 
							}
							
							dr.color = rSrc[0].fontColor; 
							dr.drawFontGlyph(stIdx[ligatureIdx], bnd, rSrc[0].bkColor, rSrc[0].fontFlags); 
							
							/+
								Todo: Ez nem teljesen jo, mert a != es a == nem ugyanolyan szeles, ha 2 karakterbol van.
								A ligaturajuknak viszont ugyanolyan szelesnek kellene lennie. Ezt a ligatura feldolgozast az 
								Elastic Tab feldolgozasba is bele kene belerakni.
								A performace visszaeses itt nem nagy, mert csak a LOD szering lathato dolgokon megy vegig.
							+/
						}
					}
				} 
				
				if(
					lod.calcVisibleSize(outerHeight)<6 
					&& im.actTargetSurface==0 /+Note: LOD is only enabled on the world view, not on the UI+/
				)
				{ drawLowDetail; }
				else
				{
					super.draw(dr); 
					
					//Opt: these calculations operqations should be cached. Seems not that slow however
					/+
						Todo: only display this when there is an editor cursor active in the codeColumn
						(or in the module)
					+/
					dr.translate(innerPos); scope(exit) { dr.pop; dr.alpha = 1; }
					
					dr.color = clGray; dr.alpha = .4f; dr.lineWidth = .5f; dr.pointSize = 1; 
					
					if(globalVisualizeSpacesAndTabs)
					{
						visualizeTabs; 
						visualizeSpaces; 
					}
					
					if(enableCodeLigatures) drawLigatures; 
					
					if(VisualizeCodeLineIndices) {
						//Todo: csak akkor rajzolja ki, ha nagyon bele van zoomolva!!!
						dr.color = clWhite; 
						dr.fontHeight = 1.25; 
						dr.textOut(vec2(0), format!"%sR"(lineIdx)); 
					}
				}
				
				//visualize changed/created/modified
				addGlobalChangeIndicator(dr, this/*, vec2(padding.left, innerHeight)*.5f*/); 
				
				static if(rearrangeFlash)
				if(now-rearrangeTime < 1*second)
				{
					dr.color = clGold; 
					dr.alpha = (1-(now-rearrangeTime).value(second)).sqr*.5f; 
					dr.fillRect(outerBounds); 
					dr.alpha = 1; 
				}
			} 
		}
	} 
}