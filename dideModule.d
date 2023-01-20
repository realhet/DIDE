module didemodule;/+DIDE+/
version(/+$DIDE_REGION+/all)
{
	
	/+
		23.01.05: StructuredEditor note: Make the structured editing possible
				[ ] insert a space
					-> didemodule.d(2502): @CodeColumn.resyntax:  Resyntax: Glyph expected ivec2(0, 0)
					(CodeColumn.resyntax() - resyntaxer.appendHighlighted(sourceText))
				[ ] insert a newline
				[ ] delete a whitespace
				[ ] delete a letter
				[ ] delete a CodeNode
				[ ] all the above works for root level
				[ ] all the above works for a nested Comment
				[ ] all the above works for a nested String
				[ ] all the above works for a nested CodeNode
	+/
	
	//todo: Multiline #define is NOT allowed in D tokenStrings
	
	import het, het.ui, het.tokenizer, het.structurescanner ,buildsys;
	
	//version identifiers: AnimatedCursors
	enum MaxAnimatedCursors = 100;
	
	enum rearrangeLOG = false;
	enum rearrangeFlash = false;
	
	enum LogModuleLoadPerformance = false;
	
	enum visualizeStructureLevels = false;
	
	__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.
	__gshared DefaultNewLine = "\r\n"; //this is used for saving source code
	
	const clModuleBorder = clGray;
	const clModuleText = clBlack;
	
	enum specialCommentMarker = "$DIDE_"; //used in /++/ comments to mark DIDE special comments
	enum compoundObjectChar = '\uFFFC';
	
	version(/+$DIDE_REGION ChangeIndicator+/all)
	{
		//ChangeIndicator /////////////////////////////////////
		
		struct ChangeIndicator
		{
			//todo: this is quite similar to CaretPos
			vec2	pos;
			float	height;
			ubyte	thickness;
			ubyte 	mask;
					
			vec2	top	() const
			{ return pos; }
			vec2	center	() const
			{ return pos + vec2(0, height/2); }
			vec2	bottom	() const
			{ return pos + vec2(0, height); }
			bounds2	bounds	() const
			{ return bounds2(top, bottom); }
		}
		
		Appender!(ChangeIndicator[]) globalChangeindicatorsAppender;
		
		void addGlobalChangeIndicator(in vec2 pos, in float height, in int thickness, in int mask)
		{ globalChangeindicatorsAppender ~= ChangeIndicator(pos, height, cast(ubyte)thickness, cast(ubyte)mask); }
		
		void addGlobalChangeIndicator(Drawing dr, Container cntr)
		{
			with(cntr) {
				if(const mask = changedMask)
				{
					enum ofs = vec2(-4, 0);
					if(cast(CodeRow)cntr)
					addGlobalChangeIndicator(dr.inputTransform(outerPos+ofs), outerHeight, 4, mask);
					else if(cast(CodeColumn)cntr)
					addGlobalChangeIndicator(dr.inputTransform(innerPos+ofs), innerHeight, 1, mask);
				}
			}
		}
		
		void draw(Drawing dr, in ChangeIndicator[] arr)
		{
			enum palette = [clBlack, clLime, clRed, clYellow];
			
			//const clamper = RectClamper(im.getView, 5);
			
			void drawPass(int pass)(in ChangeIndicator ci)
			{
				static if(pass==1) {
					dr.lineWidth = -float(ci.thickness)-1.5f;
					//opted out: dr.color = clBlack;
				}
				static if(pass==2) {
					dr.lineWidth = -float(ci.thickness);
					dr.color = palette[ci.mask];
				}
						
				//if(clamper.overlaps(ci.bounds)){
					dr.vLine(ci.pos, ci.pos.y + ci.height);
				//}else{
				//dr.vLine(clamper.clamp(ci.center), lod.pixelSize);  //opt: result of claming should be cached...
				//}
			}
					
			/+pass 1+/  dr.color = clBlack;	foreach_reverse(const a; arr) drawPass!1(a);
			/+pass 2+/	foreach_reverse(const a; arr) drawPass!2(a);
		}
		
	}
	
}version(/+$DIDE_REGION Utility+/all)
{
	//Utility //////////////////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		
		version(/+$DIDE_REGION LOD   +/all)
		{
			//LOD //////////////////////////////////////////
			
			struct LodStruct
			{
				float zoomFactor=1, pixelSize=1;
				int level;
							
				bool codeLevel	   =	true; //level 0
				bool moduleLevel		= false; //level 1/*code text visible*/, 2/*code text invisible*/
			}
			
			__gshared const LodStruct lod;
			
			void setLod(float zoomFactor_)
			{
				with(cast(LodStruct*)(&lod))
				{
					zoomFactor = zoomFactor_;
					pixelSize = 1/zoomFactor;
					level = pixelSize>6 ? 2 :
									pixelSize>2 ? 1 : 0;
								
					codeLevel = level==0;
					moduleLevel = level>0;
				}
			}
			
		}
		
		
		
		
		
		dchar charAt(const CodeRow cr, int i, bool newLineAtEnd=true)
		{
			if(!cr || i<0 || i>cr.subCells.length) return '\x00';
			if(i==cr.subCells.length) return newLineAtEnd ? '\n' : '\x00';
			const cell = cr.subCells[i];
			if(const g = cast(const Glyph)cell) return g.ch;else return '\x01';
		}
		
		dchar charAt(const CodeColumn cc, ivec2 p)
		{
			if(!cc || p.y<0 || p.x<0 || p.y>=cc.rowCount) return '\x00';
			return charAt(cast(const CodeRow)cc.subCells[p.y], p.x, p.y<cc.rowCount-1);
		}
		
		dchar charAt(const TextCursor tc)
		{ return charAt(tc.codeColumn, tc.pos); }
		
		enum WordCategory { space, symbol, word }
		
		WordCategory wordCategory(dchar ch)
		{
			import std.uni;
			if(ch.isAlphaNum || ch=='_') return WordCategory.word;
			if(ch.among(' ', '\t', '\n', '\r')) return WordCategory.space;
			return WordCategory.symbol;
		}
		
		bool isWordBoundary(R)(R a)
		{
			//input: 2 element historical sliding window of the characters
			//output is true when the wordCategory is decreasing.
			//The 3 possible transitions are: word->symbol, word->space, symbol->space
			return a.front.wordCategory > a.drop(1).front.wordCategory;
		}
		
		struct CharFetcher
		{
			TextCursor cursor;
			bool forward=true;
			
			@property dchar front() const
			{ return charAt(cursor); }
			@property bool empty() const
			{
				if(forward)
				return cursor.pos.y>cursor.codeColumn.lastRowIdx;
				else
				return cursor.pos.y<0;
			}
			
			void popFront()
			{
				if(forward)
				cursor.moveRight_unsafe;
				else
				cursor.moveLeft_unsafe;
			}
					
			auto save() { return this; }
		}
	}version(/+$DIDE_REGION+/all)
	{
		vec2 worldOuterPos(Cell cell)
		{
			if(!cell) return vec2(0);
			if(auto parent = cell.getParent) return worldInnerPos(parent)+cell.outerPos;
			return cell.outerPos;
		}
		
		vec2 worldInnerPos(Cell cell)
		{
			if(!cell) return vec2(0);
			return worldOuterPos(cell) + cell.topLeftGapSize;
		}
		
		bounds2 worldInnerBounds(Cell cell)
		{
			if(!cell) return bounds2.init;
			auto p = worldInnerPos(cell);
			return bounds2(p, p+cell.innerSize);
		}
		
		bounds2 worldBounds(TextCursor tc)
		{
			if(tc.valid)
			if(auto row = tc.codeColumn.getRow(tc.pos.y))
			with(row.localCaretPos(tc.pos.x))
			{ return bounds2(pos, pos+vec2(0, height)) + row.worldInnerPos; }
					
			return bounds2.init;
		}
		
		bounds2 worldBounds(TextSelection ts)
		{
			return ts.valid 	? worldBounds(ts.cursors[0]) | worldBounds(ts.cursors[1])
				: bounds2.init;
		}
		
		bounds2 worldBounds(TextSelection[] ts)
		{
			  //todo: constness
			return ts.map!worldBounds.fold!"a|b"(bounds2.init);
		}
		
		auto moduleOf(inout Cell c)
		{ return cast(inout)(c ? c.allParents!Module.frontOrNull : null); }
		
		auto moduleOf(TextCursor c)
		{ return c.codeColumn.moduleOf; }
		auto moduleOf(TextSelection s)
		{ return s.caret.codeColumn.moduleOf; }
		
		bool isReadOnly(in Cell c)
		{ return c.thisAndAllParents!Module.map!"a.isReadOnly".any; }
		bool isReadOnly(in TextCursor c)
		{ return c.codeColumn.isReadOnly; }
		bool isReadOnly(in TextSelection s)
		{ return s.caret.codeColumn.isReadOnly; }
			
		static struct CaretPos
		{
			//CaretPos ///////////////////////////////////
			
			/// CaretPos is A caret's graphical position in world coords
			
			vec2 pos;
			float height=0;
			bool valid()const
			{ return height>0; }
			bool opCast(B:bool)() const
			{ return valid; }
			
			void draw(Drawing dr)
			{
				if(valid)
				{
					if(dr.alpha<1)
					{
						//shrink a bit by alpha
						const shrink = (1-dr.alpha)*height*.33f;
						dr.vLine(pos.x, pos.y+shrink, pos.y+height-shrink);
					}
					else
					{ dr.vLine(pos, pos.y+height); }
				}
			}
					
			vec2	top   () const
			{ return pos; }
			vec2	center() const
			{ return pos + vec2(0, height/2); }
			vec2	bottom() const
			{ return pos + vec2(0, height); }
			bounds2	bounds() const
			{ return bounds2(top, bottom); }
		}
	}	
}version(/+$DIDE_REGION UI functions+/all)
{
	version(/+$DIDE_REGION+/all)
	{
		
		__gshared float blink;
		
		void updateBlink()
		{ blink = float(sqr(sin(blinkf(134.0f/60)*PIf))); }
		
		void setRoundBorder(Container cntr, float borderWidth)
		{
			with(cntr) {
				border.width = borderWidth;
				border.color = bkColor;
				border.inset = true;
				border.borderFirst = true;
			}
		}
		
		void RoundBorder(float borderWidth)
		{
			with(im) {
				border.width = borderWidth;
				border.color = bkColor;
				border.inset = true;
				border.borderFirst = true;
			}
		}
		
		//! UI ///////////////////////////////
		
		static void UI_OuterBlockFrame(T = .Row)(RGB color, void delegate() contents)
		{
			with(im)
			Container!T(
				{
					margin = "0.5";
					padding = "1.5";
					style.bkColor = bkColor = color;
					style.fontColor = blackOrWhiteFor(color);
					flags.yAlign = YAlign.top;
					RoundBorder(8);
					if(contents) contents();
				}
			);
		}
		
		static void UI_InnerBlockFrame(T = .Row)(RGB color, RGB fontColor, void delegate() contents)
		{
			with(im)
			Container!T(
				{
					margin = "0";
					padding = "0 4";
					style.bkColor = bkColor = color;
					style.fontColor = fontColor;
					flags.yAlign = YAlign.top;
					RoundBorder(8);
					if(contents) contents();
				}
			);
		}
		
		static void UI_BuildMessageContents(CodeLocation location, string title, void delegate() contents)
		{
			with(im) {
				location.UI;   //opt: this is FUCKING slow
				if(title!="") Text(bold(" "~title~" "));
				if(contents) contents();
			}
		}
		
		static void UI_ConsoleTextBlock(string contents)
		{
			with(im) {
				UI_InnerBlockFrame(
					clBlack, clWhite, {
						style.font = "Lucida Console";
						Text(contents);
						//todo: Use codeRow here for optimized LOD. Refer to -> UI_BuildMessageTextBlock()
					}
				);
			}
		}
		
		static void UI_CompilerOutput(File file, string text)
		{ UI_OuterBlockFrame(RGB(0xD0D0D0), { UI_BuildMessageContents(CodeLocation(file), "Output:", { UI_ConsoleTextBlock(text); }); }); }
		
		void UI(in CodeLocation cl)
		{
			 with(cl)
			with(im)
			UI_InnerBlockFrame(
				clSilver, clBlack, {
					auto s = cl.text;
							
					actContainer.id = "CodeLocation:"~s;
							
					FileIcon_small(file.ext);
							
					Text(s);
				}
			);
			
		}
		
		
		void UI(in BuildSystemWorkerState bsws)
		{
			with(bsws)
			with(im) {
				Row(
					{
						width = 6*fh;
						Row(
							{
								if(building) style.fontColor = mix(style.fontColor, style.bkColor, blink);
								Text(cancelling ? "Cancelling" : building ? "Building" : "BuildSys Ready");
							}
						);
						Row(
							{
								 flex=1; flags.hAlign = HAlign.right;
								if(building && !cancelling && totalModules)
								Text(format!"%d(%d)/%d"(compiledModules, inFlight, totalModules));
								else if(building && cancelling) { Text(format!"\u2026%d"(inFlight)); }
							}
						);
					}
				);
			}
			
		}
	}version(/+$DIDE_REGION+/all)
	{
		void UI_BuildMessageTextBlock(string message, RGB clFont)
		{
			//Apply syntax highlight on the texts between `` quotes.
			auto isCode = new bool[message.length];
			{
				bool inCode = false;
				size_t i;
				foreach(ch; message.byChar)
				{
					if(!inCode)
					{ if(ch=='`') inCode=true; }
					else
					{ if(ch=='`') inCode=false;else isCode[i]=true; }
					i++;
				}
			}
					
			auto codeOnly = message.dup;
			foreach(i, b; isCode) if(!b) codeOnly.ptr[i] = ' ';
					
			auto sc = scoped!SourceCode(cast(string)codeOnly);
					
			void appendLine(int idx) {
				with(im) {
					auto cr = cast(CodeRow)actContainer;
					auto r = sc.getLineRange(idx);
					cr.set(message[r[0]..r[1]], sc.syntax[r[0]..r[1]]);
					auto g = cr.glyphs;
					foreach(i, b; isCode[r[0]..r[1]])
					if(!b) g[i].fontColor = clFont;
				}
			}
					
			const lineCount = sc.lineCount;
			if(lineCount>=1)
			{
				with(im)
				UI_InnerBlockFrame!CodeColumn(
					clCodeBackground,
					clFont,
					{
						foreach(i; 0..lineCount)
						Container!CodeRow({ appendLine(i); });
					}
				);
			}
		}
		
		
		void UI(in BuildMessage msg, BuildResult br)
		{ UI(msg, br.subMessagesOf(msg.location)); }
		
		void UI(in BuildMessage msg, in BuildMessage[] subMessages)
		{
			with(msg)
			with(im)
			UI_OuterBlockFrame(
				type.color,
				{
					UI_BuildMessageContents(
						location,
						parentLocation ? "\u2026" : type.to!string.capitalize~":",
						{
							const clFont = avg(type.color, clWhite);
							
							UI_BuildMessageTextBlock(message, clFont);
							
							foreach(sm; subMessages)
							{ Text("\n    "); sm.UI([]); }
						}
					);
				}
			);
		}
		
		//! Draw //////////////////////////////////////////////////////
		
		void drawHighlight(Drawing dr, bounds2 bnd, RGB color, float alpha)
		{
			if(!bnd) return;
			dr.color = color;
			dr.alpha = alpha;
			dr.fillRect(bnd);
			dr.lineWidth = -1;
			dr.drawRect(bnd);
			dr.alpha = 1;
		}
		
		void drawHighlight(Drawing dr, Cell c, RGB color, float alpha)
		{
			if(!c) return;
			drawHighlight(dr, c.outerBounds, color, alpha);
		}
		
	}
}struct CellPath
{
	//CellPath ///////////////////////////////
	Cell[] path; //todo: constness
	alias path this;
	
	this(Cell act)
	{ path = act.thisAndAllParents.array.retro.array; }
	
	static private string pathElementToString (Container parent, Cell child)
	{
		if(!parent) return "?NullParent?";
		if(!child) return "?NullChild?";
		
		if(auto col = cast(CodeColumn)child)
		{
			if(!cast(CodeNode)parent) return "?WrongColumnParent?";
			assert(cast(CodeNode)parent);  //todo: put these assertions elsewhere
			const indexAmongCodeColumns = parent.subCells.map!(a => cast(CodeColumn)a).filter!"a".countUntil(child);
			if(indexAmongCodeColumns<0) return "?CantFindColumn?";
			return format!"C%d|"(indexAmongCodeColumns);
		}
		
		if(auto row = cast(CodeRow)child)
		{
			if(!cast(CodeColumn)parent) return "?WrongRowParent?";
			const idx = parent.subCellIndex(child);
			if(idx<0) return "?CantFindRow?";
			return idx.format!"R%d|";
		}
		
		if(auto mod = cast(Module)child)
		{
			if(!typeid(parent).name.endsWith(".Workspace")) return "?WrongModuleParent?";
			return mod.file.fullName ~ "|";
		}
		
		if(auto node = cast(CodeNode)child)
		{
			if(!cast(CodeRow)parent) return "?WrongNodeParent?";
			const idx = parent.subCellIndex(child);
			if(idx<0) return "?CantFindNode?";
			return format!"N%d|"(idx);
		}
		
		return "?UnknownChild?";
	}
	
	auto byPathElements()
	{
		return path	.slide!(No.withPartial)(2)
			.map!(sl => tuple!("parent", "child")(cast(Container)sl[0], sl[1]) );
	}
	
	string toString()
	{
		//todo: constness
		if(path.empty) return "";
		return byPathElements.map!(a => pathElementToString(a[])).join;
	}
	
	static private bool isPathElementValid(Container parent, Cell child)
	{
		return !pathElementToString(parent, child).startsWith('?');
		//opt: not so effective because of strings
	}
	
	bool valid()
	{
		//todo: constness
		return 	byPathElements.map!(a => isPathElementValid(a[])).all
			&& cast(CodeRow)path.backOrNull;
	}
	
	static private int pathElementToIntex(Container parent, Cell child)
	{ return parent.subCellIndex(child); }
}struct TextCursor
{
	//TextCursor /////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		/+
			todo: to be able to edit and preserve the textcursor indices, 
					textcursor should target objects, not indices. [codeRow, cell] 
					would be the minimum. codeRow.subCellIdx(cell) and codeRow.index 
					should be cached.
		+/
		
		CodeColumn codeColumn;
		
		ivec2 pos;
		float desiredX=0; //used for up down movement, after left right movements.
		
		version(AnimatedCursors)
		{
			vec2 	targetPos	= vec2(float.nan),
				animatedPos 	= vec2(float.nan);
		}
		
		@property bool valid() const
		{ return (codeColumn !is null) && pos.x>=0 && pos.y>=0; }
		
		@property int rowCharCount() const
		{
			//todo: constness
			return codeColumn ? codeColumn.rowCharCount(pos.y) : 0;
		}
		
		@property bool isAtLineStart() const
		{ return pos.x<=0; }
		@property bool isAtLineEnd() const
		{ return pos.x>=rowCharCount; }
			
		int opCmp(in TextCursor b) const
		{
			//simple case: they are on the same column or both invalid
			if(codeColumn is b.codeColumn || !valid || !b.valid)
			return cmpChain(cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x));
			
			/+
				opt: multiColumn selection sorting is extremely slow. 
							Maybe the hierarchical column order should be cached in an integer value.
			+/
			
			/+
				/opt: this index searching is fucking slow. But this is the correct way to sort. 
							Maybe it should be cached somehow...
			+/
			auto order(in TextCursor c)
			{
				return c.codeColumn	.thisAndAllParents!Container
					.array.retro
					.slide!(No.withPartial)(2)
					.map!(a => a[0].subCellIndex(a[1]));
			}
			
			return cmpChain(cmp(order(this), order(b)), cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x));
		}
		
		bool opEquals(in TextCursor b) const
		{ return codeColumn is b.codeColumn && pos == b.pos; }
		
		void moveRight_unsafe()
		{
			pos.x++;
			if(pos.x>codeColumn.rowCharCount(pos.y))
			{
				pos.x=0;
				pos.y++;
			}
		}
			
		void moveLeft_unsafe()
		{
			pos.x--;
			if(pos.x<0)
			{
				pos.y--;
				pos.x=codeColumn.rowCharCount(pos.y);
			}
		}
			
		void moveLeft(long delta)
		{ moveRight(-delta); }
		void moveRight(long delta)
		{ moveRight(delta.to!int); }
			
		//special delta units
		enum 	home	= int.min,
			end	= int.max,
			wordLeft	= home+1,
			wordRight 	= end-1;
			
		void calcDesiredX_unsafe()
		{ desiredX = pos.x<=0 ? 0 : codeColumn.rows[pos.y].subCells[pos.x-1].outerBounds.right; }
			
		void calcDesiredX_safe()
		{
			if(!codeColumn || pos.x<=0)
			{ desiredX = 0; }
			else
			{
				if(auto row = codeColumn.getRow(pos.y))
				{
					if(row.cellCount==0)
					{ desiredX = 0; }
					else
					{ desiredX = row.subCells[pos.x-1].outerBounds.right; }
				}
				else
				{ desiredX = 0; }
			}
		}
	}version(/+$DIDE_REGION+/all)
	{
		void moveRight(int delta)
		{
			if(!delta) return;
			if(delta==home)
			{
				const ltc = codeColumn.rows[pos.y].leadingCodeTabCount; //unsafe
				pos.x = pos.x>ltc ? ltc : 0; //first stop is right after leading tabs, then goes to 0
			}
			else if(delta==end)
			{
				pos.x = codeColumn.rows[pos.y].cellCount; //unsafe
			}
			else if(delta==wordRight)
			{
				const skip = 	CharFetcher(this, true)
					.chain("\n\n"d) //extra stopping condition when no word boundary found
					.slide(2)
					.countUntil!(a => a.isWordBoundary || a.equal("\n\n"d)) /+only stop at empty lines (that's 2 newline)+/;
				moveRight(skip+1);
			}
			else if(delta==wordLeft)
			{
				const skip = 	CharFetcher(this, false)
					.drop(1) //ignore the char at right hand side of the cursor
					.chain("\n\n"d) //extra stopping condition when no word boundary found
					.slide(2)
					.countUntil!(a => a.isWordBoundary || a.drop(1).front=='\n') /+stop at every newline+/;
				moveLeft(skip+1);
			}
			else
			{
				//opt: cache idx2pos and pos2idx. The line searcher is slow in those
				pos = codeColumn.idx2pos(codeColumn.pos2idx(pos)+delta); //note: this must be a clamped move
			}
			calcDesiredX_unsafe;
		}
		
		void moveDown(int delta)
		{
			if(!delta) return;
			if(delta==home)
			pos.y = 0;
			else if(
				delta==end//home
			)
			pos.y = codeColumn.rowCount-1;
			else
			pos.y = (pos.y+delta).clamp(0, codeColumn.rowCount-1);
			
			//jump to desired x in actual row
			auto r = codeColumn.rows[pos.y];
			pos.x = iota(r.cellCount+1).map!(i => abs((i<=0 ? 0 : r.subCells[i-1].outerBounds.right)-desiredX)).minIndex.to!int;
		}
		
		void move(ivec2 delta)
		{
			if(!delta) return;
			
			if(!delta.x) {
				 //handle clipping in the y direction.  Generate home/end
				if(delta.y<0 && pos.y<=0) delta = ivec2(home);
				if(delta.y>0 && pos.y>=codeColumn.rowCount-1) delta = ivec2(end);
			}
				
			if(delta==ivec2(home))
			{
				pos = ivec2(0); desiredX = 0;
				//this needed to skip the possible stop right after the leading tabs in the first line
			}
			else
			{
				moveDown (delta.y);
				moveRight(delta.x);
			}
		}
		
		CaretPos localPos(bool world = false)()
		{
			//local to the codeColumn
			CaretPos res;
			if(valid)
			if(auto row = codeColumn.getRow(pos.y))
			{
				res = row.localCaretPos(pos.x);
				if(res.valid)
				{
					static if(world)
					res.pos += worldInnerPos(row);
					else
					res.pos += row.innerPos;
				}
			}
			
			return res;
		}
		
		auto worldPos()
		{ return localPos!true; }
		
		auto toReference() const
		{
			TextCursorReference res;
			if(valid)
			if(auto row = (cast()codeColumn).getRow(pos.y))
			{
				//todo: fix constness!!
				res.path = CellPath(row);
				res.left	= row.subCells.get(pos.x-1);
				res.right	= row.subCells.get(pos.x);
			}
			
			return res;
		}
	}
}struct TextCursorReference
{
	//TextCursorReference ////////////////////////////////////
	
	//Used to store a TextCursor temporarily. After editing operations these cursors can be converted back to normal cursora.
	//Also used to get a textual absolute path of the cursor location.
	
	CellPath path;       //must end with a codeRow. Starts with a root container.  Normally: root module column row
	Cell left, right;  //(null, null) is valid. -> That is an empty row.
	
	bool valid()
	{
		 //todo: constness
		if(!path.valid) return false;
		
		auto parent = cast(CodeRow)path.back;
		if(!parent) return false;
		
		return 	parent.subCells.empty || //this means that the row was empty and the caret is at the beginning of the row.
			left	&& parent.subCellIndex(left )>=0 ||
			right 	&& parent.subCellIndex(right)>=0;
	}
	
	string toString()
	{
		if(!valid) return "";
		auto res = path.toString;
		
		//this special processing is for the caret. Decide the idx from the left and right cells.
		if(!left && !right)
		res ~= "X0";
		else
		{
			auto parent = cast(CodeRow)path.back;
			if(!parent) return "";
			
			const leftIdx	= left	? parent.subCellIndex(left ) : -1;
			const rightIdx	= right	? parent.subCellIndex(right) : -1;
			
			auto idx = -1;
			if(rightIdx>=0)
			idx = rightIdx;
			else if(
				leftIdx >=0//select one valid
			)
			idx = leftIdx+1; //add 1, because it's on the left side of the caret!
			
			if(idx>=0)
			res ~= format!"X%d"(idx);
			else
			return ""; //it's lost
		}
		
		return res;
	}
	
	TextCursor fromReference()
	{
		TextCursor res;
		
		if(valid)
		if(auto col = cast(CodeColumn)path[$-2])
		if(auto row = cast(CodeRow)path[$-1])
		{
			if(row.parent is col)
			{
				res.codeColumn = col;
				res.pos.y = row.index; //opt: slof linear search
				res.pos.x = 0;
				
				const rightIdx = right ? row.subCellIndex(right) : -1;
				if(rightIdx>=0)
				{ res.pos.x = rightIdx; }
				else
				{
					const leftIdx = left ? row.subCellIndex(left) : -1;
					if(leftIdx>=0)
					{
						res.pos.x = leftIdx + 1; //note: +1 because cursor is to the right
					}
				}
				
				res.desiredX = row.localCaretPos(res.pos.x).pos.x;
			}
			else
			assert(0, "row.parent !is col");
		}
		
		
		return res.valid ? res : TextCursor.init;
	}
	
	/// Used when a delete operation joins 2 tows and the second row is deleted.
	void replaceLatestRow(CodeRow old, CodeRow new_)
	{
		if(path.length && path.back is old)
		path.back = new_;
	}
}struct TextSelection
{
	//TextSelection ///////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		TextCursor[2] cursors;
		bool primary;
		
		this(TextCursor c0, TextCursor c1 ,bool primary)
		{ cursors[0] = c0; cursors[1] = c1; this.primary = primary; }
		this(TextCursor c, bool primary)
		{ cursors[0] = c; cursors[1] = c; this.primary = primary; }
		
		ref caret()
		{ return cursors[1]; }
		ref const caret()
		{ return cursors[1]; }
		
		auto codeColumn()
		{ return cursors[0].codeColumn; }
		
		@property bool valid() const
		{ return cursors[].map!"a.valid".all && cursors[0].codeColumn is cursors[1].codeColumn; }
		bool opCast(B:bool)() const
		{ return valid; }
		
		@property auto start() const
		{ return min(cursors[0], cursors[1]); }
		@property auto end() const
		{ return max(cursors[0], cursors[1]); }
		
		@property bool isZeroLength() const
		{ return cursors[0]==cursors[1]; }
		@property bool isSingleLine() const
		{ return cursors[0].pos.y==cursors[1].pos.y; }
		@property bool isMultiLine() const
		{ return !isSingleLine; }
		
		@property bool isAtLineStart() const
		{ return start.isAtLineStart; }
		@property bool isAtLineEnd() const
		{ return end  .isAtLineEnd; }
		
		@property int calcLength()
		{ return valid ? abs(codeColumn.pos2idx(cursors[0].pos) - codeColumn.pos2idx(cursors[1].pos)) : 0; } //todo: constness
		
		int opCmp(const TextSelection b) const
		{
			//todo: *** structured codeColumns: it assumes cursors[0].codeColumn is the same as cursors[1].codeColumn
			return cmpChain(
				cmp(
					cast(size_t)(cast(void*)cursors[0].codeColumn),
										cast(size_t)(cast(void*)b.cursors[0].codeColumn)/+***+/
				),
				cmp(start, b.start),
				cmp(end, b.end),
				cmp(caret, b.caret)
			);
		}
		
		bool opEquals(const TextSelection b) const
		{
			return 	cursors[0].codeColumn is b.cursors[0].codeColumn
				&& start==b.start
				&& end==b.end
				&& caret==b.caret;
		}
	}version(/+$DIDE_REGION+/all)
	{
		void move(ivec2 delta, bool isShift)
		{
			if(!delta) return;
			
			if(!isShift && cursors[0]!=cursors[1])
			{
				caret = delta.y.cmpChain(delta.x)<0 ? start : end; //collapse selection if it is a non-shift move
				
				static void restrict(ref int x, int y)
				{
					if(!y && x)
					{
						if(x.among(TextCursor.wordLeft, TextCursor.wordRight, TextCursor.home, TextCursor.end))
						{
							x = 0; //wordLeft/wordRight/home/end stops at the end of the selection
						}
						else
						{ x -= sign(x); }
					}
				}
				
				with(delta) {
					restrict(x, y);
					restrict(y, x);
				}
			}
			caret.move(delta);
			if(!isShift) cursors[0] = caret;
		}
		
		string sourceText()
		{
			string res;
			if(valid && cursors[0] != cursors[1])
			{
				const 	st=codeColumn.pos2idx(start.pos),
					en=codeColumn.pos2idx(end.pos); //note: st and en is validated
				
				auto crsr = TextCursor(codeColumn, codeColumn.idx2pos(st));
				if(en>st) {
					res.reserve(en-st);
					//don't care about newlines and Unicode overhead... It's only fast for ASCII
					
					foreach(i; st..en) {
						scope(exit) crsr.moveRight_unsafe; //todo: refactor all textselection these loops
						
						auto row = codeColumn.rows[crsr.pos.y];
							
						if(crsr.pos.x<row.cellCount)
						{
							//highlighted chars
							auto cell = row.subCells[crsr.pos.x];
							if(auto g = cast(Glyph)cell)
							{ res ~= g.ch; }
							else if(auto n = cast(CodeNode)cell)
							{
								res ~= n.sourceText; //this can throw exceptions if the node has an invalid content
							}
							else
							{
								raise("NOT IMPL"); //todo: structured editor
							}
						}
						else
						{
							res ~= DefaultNewLine; //todo: newLine const
						}
					}
				}
			}
			return res;
		}
		
		bool hitTest(vec2 p)
		{
			return false;
			//todo: hitTest
		}
		
		private auto reduce(string what)()
		{
			if(!valid) return typeof(this).init;
			auto res = this;
			res.cursors[] = mixin("res."~what);
			return res;
		}
		
		auto reduceToStart()
		{ return reduce!"start"; }
		auto reduceToEnd()
		{ return reduce!"end"; }
		auto reduceToCaret()
		{ return reduce!"caret"; }
		auto reduceToCursor0()
		{ return reduce!"cursors[0]"; }
		auto reduceToCursor1()
		{ return reduce!"cursors[1]"; }
		
		auto toReference()
		{ return TextSelectionReference(cursors[0].toReference, cursors[1].toReference, primary); }
	}version(/+$DIDE_REGION+/all)
	{
		this(string s, Module delegate(File) onFindModule)
		{
			try
			{
				s = s.strip;
				if(s!="")
				{
					
					if(s.endsWith(TextSelectionReference.primaryMark))
					{
						primary = true;
						s = s.withoutEnding(TextSelectionReference.primaryMark);
					}
					
					Container parent;
					CodeColumn codeColumn;
					
					void step(Cell c)
					{
						c.enforce;
						parent = c.to!Container;
					}
					
					int cidx = 0;
					ivec2[2] pos;
					foreach(partIdx, part; s.split('|'))
					{
						if(!partIdx)
						{ step(onFindModule(File(part))); }
						else if(part.startsWith('C'))
						{
							const idx = part[1..$].to!uint;
							step(parent.subCells.map!(a => cast(CodeColumn)a).filter!"a".drop(idx).frontOrNull);
							//Parent is CodeNode. Only search amongst its child CodeColumns.
						}
						else if(part.startsWith('R'))
						{
							const idx = part[1..$].to!uint;
							codeColumn = enforce(cast(CodeColumn)parent);
							step(parent.subCells.drop(idx).frontOrNull);
							pos[cidx].y = idx;
						}
						else if(part.startsWith('N'))
						{
							const idx = part[1..$].to!uint;
							step(parent.subCells.drop(idx).frontOrNull);
							pos[cidx].x = idx;
						}
						else if(part.startsWith('X'))
						{
							const idx = part[1..$].to!uint;
							enforce(cast(CodeRow)parent && idx>=0 && idx<=parent.cellCount);
							//special caret range checking
							
							pos[cidx].x = idx;
							parent = null; //the end of the cursor. It can restart after "=>".
						}
						else if(part=="=>")
						{
							enforce(cidx==0 && !parent);
							cidx++;
							parent = codeColumn;
						}
						else enforce(0);
					}
					
					enforce(cidx.among(0, 1) && codeColumn);
					if(cidx==0) pos[1] = pos[0];
					foreach(i; 0..2) {
						cursors[i] = TextCursor(codeColumn, pos[i]);
						cursors[i].calcDesiredX_unsafe;
					}
					
					enforce(valid); //just a light test
				}
			}
			catch(Exception e)
			{ this = typeof(this).init; }
		}
	}
}version(/+$DIDE_REGION+/all)
{
	int distance(TextSelection ts, TextCursor tc)
	{
		//todo: constness
		if(ts.valid && tc.valid && ts.codeColumn is tc.codeColumn)
		{
			auto cc = tc.codeColumn, st = ts.start, en = ts.end;
			if(tc<st) return cc.pos2idx(st.pos) - cc.pos2idx(tc.pos);
			if(tc>en) return cc.pos2idx(tc.pos) - cc.pos2idx(en.pos);
			return 0; //it's inside
		}
		else
		{ return int.max; }
	}
	
	bool touches(TextSelection a, TextSelection b)
	{
		//todo: there should be an intersects too: 2 selections can touch but if one is zeroLength is disappears.
		//todo: constness
		bool chk()
		{
			auto a0 = a.start, a1 = a.end;
			auto b0 = b.start, b1 = b.end;
			return 	(a0<=b0 && b0<=a1) ||
				(a0<=b1 && b1<=a1) ||
				(b0<=a0 && a0<=b1) ||
				(b0<=a1 && a1<=b1);
			//opt: not so optimal.
		}
			
		return a.valid && b.valid && a.codeColumn is b.codeColumn && chk;
	}
	
	TextSelection merge(TextSelection a, TextSelection b)
	{
		const backward = a.cursors[0]>a.cursors[1] || b.cursors[0]>b.cursors[1];
		auto res = TextSelection(min(a.start, b.start), max(a.end, b.end), a.primary || b.primary);
		if(backward) swap(res.cursors[0], res.cursors[1]);
		return res;
	}
	
	TextSelection[] merge(R)(R input)
	if(isInputRange!R && is(ElementType!R==TextSelection))
	{
		auto sorted = input.array.sort;  //opt: on demand sorting
		
		TextSelection[] res;
		foreach(a; sorted)
		{
			if(res.length && touches(a, res.back))
			{ res.back = merge(a, res.back); }
			else
			{ res ~= a; }
		}
		
		return res;
	}
	
	auto extendToFullRow(TextSelection sel)
	{
		if(sel.valid)
		{
			with(sel.cursors[0]) { pos.x = 0; desiredX = 0; } //note: TextCursor.home is not good: It stops at leadingWhiteSpace
			with(sel.cursors[1]) {
				moveRight(TextCursor.end);
				moveRight(1); //goes to start of next line
			}
		}
		return sel;
	}
	
	auto extendToWordsOrSpaces(TextSelection sel)
	{
		if(sel.valid)
		{
			void adjust(ref TextCursor c, int dir)
			{
				const dchar[] neighbors = 	CharFetcher(c, false).drop(1).take(1).array ~
					CharFetcher(c, true).take(1).array;
				if(neighbors.length<2) return; //it's at the end
				
				static bool isSpace(dchar ch)
				{ return ch.among(' ', '\t')>0; } //Only space and tab counts here.
				static bool isWord (dchar ch)
				{ return wordCategory(ch)==WordCategory.word; }
				
				auto lookingForWords = neighbors.any!isWord;
				auto lookingForSpaces = neighbors.all!isSpace; //2 spaces -> lookingForSpace
				
				if(lookingForWords || lookingForSpaces)
				{
					const cnt = 	CharFetcher(c, dir>0)
						.drop(dir<0 ? 1 : 0)
						.chain("+"d) //extend with a dummy symbol to stop at
						.countUntil!(
						ch => lookingForWords ? !isWord(ch)
													: lookingForSpaces	? !isSpace(ch)
													: true
					);
					if(cnt>0)
					c.moveRight(dir*cnt);
				}
			}
			
			const stIdx = sel.cursors[0]<=sel.cursors[1] ? 0 : 1;
			adjust(sel.cursors[stIdx], -1);
			adjust(sel.cursors[1-stIdx],  1);
		}
		return sel;
	}
}version(/+$DIDE_REGION+/all)
{
	auto zeroLengthSelectionsToFullRows(TextSelection[] sel)
	{
		auto fullRows = sel	.filter!"a.valid && a.isZeroLength"
			.map!extendToFullRow.array;
		
		return merge(sel ~ fullRows);
	}
	
	auto zeroLengthSelectionsToOne(TextSelection[] sel, Flag!"toLeft" toLeft)
	{
		const dir = toLeft ? -1 : 1;
		
		auto a = sel.dup;
		a.each!(
			(ref s){
				if(s.valid && s.isZeroLength)
				s.move(ivec2(dir, 0), true);
			}
		);
		
		return merge(a);
	}
	
	auto zeroLengthSelectionsToOneLeft (TextSelection[] sel)
	{ return sel.zeroLengthSelectionsToOne(Yes.toLeft); }
	auto zeroLengthSelectionsToOneRight(TextSelection[] sel)
	{ return sel.zeroLengthSelectionsToOne(No .toLeft); }
	
	
	/// input newLine must be standardized. Only that type of newLine is recognized.
	/// it only adds newLine when the last item doesn't have one at its end
	/// replaces all '\n' to specidied newLine
	string sourceTextJoin(R)(R r, string newLine)
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
	
	
	string sourceText(TextSelection[] ts)
	{
		return ts	.filter!"a.valid && !a.isZeroLength"
			.map!"a.sourceText"
			.sourceTextJoin(DefaultNewLine);
	}
	
	bool hitTest(TextSelection[] ts, vec2 p)
	{
		return ts.map!(a => a.hitTest(p)).any;
		//todo: this should be in the draw routine with automatic mouse hittest
	}
	
	TextSelection useValidCursor(TextSelection ts)
	{
		if(ts.valid) return ts;
		const i = ts.cursors[0].valid ? 0 : 1;
		return TextSelection(ts.cursors[i], ts.cursors[i], ts.primary);
	}
	
	/+
		void animate(ref TextSelection sel, )
			{
				version(AnimatedCursors){
			
				}
			}
	+/
	
	struct SourceTextBuilder
	{
		//SourceTextBuilder /////////////////////////
		enum CODE = true, UI = !CODE;
		
		string result;
		
		bool enableIndent = true;
		
		int newLineCount, indentCount;
		bool needsNewLine; //to support //comments and #directives
		
		bool updateLineNumbers;
		
		bool actLineIsClear()
		{
			auto s = result;
			while(s.endsWith('\t')) s = s[0..$-1];
			if(s=="" || s.endsWith(DefaultNewLine)) return true;
			return false;
		}
		
		void putNL(int indentAdjust = 0)()
		{
			result ~= DefaultNewLine;
			
			if(enableIndent)
			result ~= "\t".replicate(max(0, indentCount + indentAdjust));
			
			newLineCount++;
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
		{ put(row.subCells); }
		
		void putStatementBody(CodeColumn col)
		{
			foreach(i, row; col.rows)
			{
				if(i) putNL;
				put(row);
			}
		}
		
		void put(CodeColumn col)
		{
			if(!col.rowCount) return; //todo: there should be no CodeColumns without at least a single CodeRow inside. -> invatiant{}
			//assert(col.rowCount>0, "Empty col: "~col.rowCount.text);
			
			const isMultiLine = col.rowCount>1;
			/+todo: ennek rekurzivnak kellene lennie. Ebben a peldaban belul van a multiline rekurziv modon. { a({ b;<NL>c; }); }+/
			
			void putMultiLine()
			{
				indentCount++;
				scope(exit) indentCount--;
				
				foreach(i, row; col.rows)
				{
					putNL;
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
					auto row = col.rows.front;
					
					//todo: Transform {x} => { x }   to look nice
					const stylisticSpaces = result.endsWith('{') && !result.endsWith("q{") && row.chars.length>0;
					
					//if(stylisticSpaces) put(' ');
					const prevNewLineCount = newLineCount;
					const startPos = result.length;
					const firstLineIsClear = actLineIsClear;
					
					if(stylisticSpaces && !row.isCodeSpaces.front) put(' ');
					put(row);
					if(stylisticSpaces && !row.isCodeSpaces.back) put(' ');
					
					if(!firstLineIsClear && (needsNewLine || newLineCount>prevNewLineCount))
					{
						//it's actually a multiline block. go back and repeat.
						result.length = startPos;
						
						putMultiLine;
					}
				}
			}
			else
			putStatementBody(col);
		}
		
		void put(Cell cell)
		{
			void doUpdateLineNumber(T)(T a)
			{
				if(updateLineNumbers)
				a.line = newLineCount+1;
			}
			
			if(auto glyph = cast(Glyph) cell)
			{
				put(glyph.ch);
				doUpdateLineNumber(glyph);
			}
			else if(auto node = cast(CodeNode) cell)
			{
				node.buildSourceText(this);
				doUpdateLineNumber(node);
			}
			else
			enforce(0, "Unsupported cell type: "~typeid(cell).name);
		}
		
		void put(R)(R cells)
		if(isInputRange!R && __traits(compiles, cast(Cell) cells.front))
		{ foreach(c; cells) put(c); }
		
		void put(string prefix, CodeColumn block, string postfix, bool showFix=true)
		{
			if(!showFix)
			{ put(block); }
			else
			{
				const enableIndent_prev = enableIndent;
				if(!prefix.empty && prefix.back.among('\'', '"', '`', '#')) enableIndent = false;
				scope(exit) enableIndent = enableIndent_prev;
				
				put(prefix);
				
				if((prefix=="" && postfix.among(";", ":", "")))
				{
					//LOG("SB", block.sourceText);
					putStatementBody(block);
				}
				else
				{ put(block); }
				
				const newLineRequired = !!prefix.among("//", "#"); //todo: multiline #
				if(newLineRequired)
				{
					assert(postfix=="");
					needsNewLine = true;
				}
				else
				{ put(postfix); }
			}
		}
	}
	struct CodeNodeBuilder
	{
		//CodeNodeBuilder ///////////////////////////////
		enum UI = true, CODE = !UI;
		
		CodeNode node;
		TextStyle style;
		int inverse; //0, 1, 2
		RGB darkColor, brightColor, halfColor;
		
		void putNL()
		{ put('\n'); }
		
		void put(T)(T a)
		{
			static if(isSomeString!T)
			node.appendStr(a, style);
			else static if(isSomeChar!T)
			node.appendChar(a, style);
			else static if(is(T:Cell))
			node.appendCell(a);
			else
			static assert(0, "unhandled type");
		}
		
		void put(string prefix, CodeColumn block, string postfix, bool showFix=true)
		{
			if(showFix) put(prefix);
			put(block);
			if(showFix) put(postfix);
		}
	}
	
}version(/+$DIDE_REGION+/all)
{
	struct TextSelectionReference
	{
		//TextSelectionReference //////////////////////////////
		TextCursorReference[2] cursors;
		bool primary;
		
		this(TextCursorReference c0, TextCursorReference c1, bool primary)
		{ cursors[0] = c0; cursors[1] = c1; this.primary = primary; }
		this(TextSelection ts)
		{ this = ts.toReference; }
		
		TextSelection fromReference()
		{ return TextSelection(cursors[0].fromReference, cursors[1].fromReference, primary).useValidCursor; }
		
		bool valid()
		{
			if(!cursors[0].valid) return false;
			if(!cursors[1].valid) return false;
			//opt: this is the bottleneck. It searches rows linearly insidt columns. Also searches chars inside rows linearly.
			
			if(cursors[0].path.length	!=	cursors[1].path.length) return false; //not in the same depth
			if(cursors[0].path[$-2]	!is	cursors[1].path[$-2]) return false; //not in the same Column
			
			assert(equal(cursors[0].path[0..$-1], cursors[1].path[0..$-1])); //check the whole path
			
			return true;
		}
		
		void replaceLatestRow(CodeRow old, CodeRow new_)
		{
			foreach(ref c; cursors)
			c.replaceLatestRow(old, new_);
		}
		
		private enum primaryMark = "*";
			
		string toString()
		{
			if(!valid) return "";
			
			auto s0 = cursors[0].toString, s1 = cursors[1].toString;
			
			auto primaryStr = primary ? primaryMark : "";
			
			if(s0==s1)
			return s0 ~ primaryStr;
			else
			return s0~"|=>|"~s1.split('|')[$-2..$].join('|') ~ primaryStr;
		}
			
		this(string s, Module delegate(File) onFindModule) { this = TextSelection(s, onFindModule).toReference; }
			
	}
	
	/// a.b|1|4|5|=>|2|3* -> a.b|1|2|3*
	string reduceTextSelectionReferenceStringToStart(string src)
	{
		/+
			todo: This nasty text fiddling workaround function could be avoided
					if the start cursor was stored in the delete/insert operation's undo record, 
					not the whole textSelection. The end cursor of the text selection could be 
					invalid, thus rendering the whole textSelection invalid. But the start cursor is always valid.
		+/
		
		__gshared unittested = false; //todo: unittest nicely
		if(chkSet(unittested))
		{
			alias f = reduceTextSelectionReferenceStringToStart;
			enforce(f("a|b|c5*"	)=="a|b|c5*"	 );
			enforce(f("a|b1|c1|=>|b1|e2*"	)=="a|b1|c1*"	 );
			enforce(f("a|b|a0000|=>|a001"	)=="a|b|a0000"	 );
			enforce(f("a|b|a0001|=>|0"	)=="a|b|0"	 );
		}
		
		int toNum(string s)
		{
			if(s.empty) return -1;
			return (s.front.isDigit ? s : s[1..$]).to!int.ifThrown(-1);
		}
		
		const isPrimary = src.endsWith('*');
		if(isPrimary) src = src[0..$-1];
		
		auto parts = src.split('|');
		
		if(auto fs = parts.findSplit(only("=>")))
		{
			const trailLen = fs[2].length;
			if(fs[0].length>=trailLen)
			{
				if(cmp(fs[0][$-trailLen..$].map!toNum, fs[2].map!toNum)<0)
				parts = fs[0];
				else
				parts = fs[0][0..$-trailLen] ~ fs[2];
			}
		}
		
		auto res = parts.join('|');
		
		if(isPrimary) res ~= "*";
		return res;
	}
}
class CodeRow: Row
{
	/// CodeRow ////////////////////////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		CodeColumn parent;
		
		static if(rearrangeFlash) DateTime rearrangeTime;
		
		override inout(Container) getParent() inout
		{ return parent; }
		override void setParent(Container p)
		{ parent = enforce(cast(CodeColumn)p); }
		
		int index()
		{ return parent.subCellIndex(this); }
		
		bool empty() const
		{ return subCells.empty; }
		
		Cell singleCellOrNull()
		{ return subCells.length==1 ? subCells[0] : null; }
		
		auto glyphs()
		{ return subCells.map!(c => cast(Glyph)c); } //can return nulls
		
		auto chars()
		{ return glyphs.map!(a => a ? a.ch : compoundObjectChar); }
		
		string shallowText()
		{ return chars.to!string; } 
		//todo: combine this with extractThisLevelDString
		
		//todo: mode isSpace inside elastic tab detection, it's way too specialized
		
		private static bool isCodeSpace(Cell c)
		{
			if(auto g = cast(Glyph)c)
			return g.ch==' ' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; 
			return false; 
		}
		private static bool isCodeTab(Cell c)
		{
			if(auto g = cast(Glyph)c)
			return g.ch=='\t' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/;
			return false;
		}
		private static bool isAnyWhitespace(Cell c)
		{
			if(auto g = cast(Glyph)c)
			return !!g.ch.among(' ', '\t');
			return false;
		}
		private auto isCodeSpaces()
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
		
	}version(/+$DIDE_REGION+/all)
	{
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
				line, syntax, (ubyte s){ applySyntax(style, s); },
								style/+, must paste tabs!!! DefaultIndentSize+/
			);
			
			//note: tabIdx is already refreshed by appendCode
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
			//note: this is used from the high level parser. It will sort out elastic tabs, but elastic tabs should be updated automatically somehow...
		}
		
		final string sourceText()
		{
			//todo: refactor this as a template mixin
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
		{
			assert(innerHeight>=DefaultFontHeight);
			return vec2(cellCount ? subCells.back.outerRight : 0, (innerHeight-DefaultFontHeight)*.5f);
		}
	}version(/+$DIDE_REGION+/all)
	{
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
			const res = insertSomething(
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
			//todo: such beautyful name... NOT!
			if(needMeasure)
			{
				
				//extend up and down along elastic tabs
				auto i = index; //opt: this index calculation is slow. Feed index from the inside
				assert(i>=0);
				
				//simple but unefficient criteria: has any tabs or not
				foreach(a; parent.rows[0..i].retro.until!"!a.tabIdxInternal.length") if(!a.needMeasure) break;
				foreach(a; parent.rows[i+1..$]  .until!"!a.tabIdxInternal.length") if(!a.needMeasure) break;
			}
		}
		
		override void rearrange()
		{
			
			assert(verifyTabIdx, "tabIdxInternal check fail");
			
			adjustCharWidths;
			
			innerSize = vec2(0); flags.autoWidth = true; flags.autoHeight = true;
			
			super.rearrange;
			
			innerSize = max(innerSize, DefaultFontEmptyEditorSize);
			
			static if(rearrangeLOG) LOG("rearranging", this);
			
			static if(rearrangeFlash) rearrangeTime = now;
			
			//opt: Row.flexSum <- ezt opcionalisan ki kell kiiktatni, lassu.
		}
	}version(/+$DIDE_REGION+/all)
	{
		protected
		{
			static immutable float 	NormalSpaceWidth	= 7.25f, //same as '0'..'9' and +-_
				LeadingSpaceWidth 	= NormalSpaceWidth;
			
			void adjustCharWidths()
			{
				
				bool isLeading = true;
				foreach(g; glyphs)
				if(g)
				{
					//todo: make this nicer
					if(isCodeSpace(g))
					{
						g.outerWidth = isLeading 	? LeadingSpaceWidth
							: NormalSpaceWidth;
					}
					else
					{
						isLeading = false;
						
						//non-leading char width modifications
						if(
							g.syntax==5 && g.ch!='.'	//number except '.'
													|| g.ch.among('+', '-', '_')	//symbols next to numbers
													/*|| g.syntax==6/+string+/*/
						) g.outerWidth = NormalSpaceWidth;
					}
				}
				else
				{ isLeading = false; }
				
				//foreach(g; glyphs) g.outerWidth = NormalSpaceWidth; //monospace everything
			}
			
			private void spaceToTab(long i)
			{
				auto g = glyphs[i];
				assert(isCodeSpace(g));
				g.ch = '\t';
				g.isTab = true;
				//note: refreshTabIdx must be called later
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
				
				refreshTabIdx; //todo: should only be done once at the end...
			}
			
			void convertLeadingSpacesToTabs(int spaceCnt)
			{
				//todo: tab inside string literal. width is too big  File(`c:\D\libs\!shit\_unused.arsd\html.d`)
				//subCells.each!LOG;
				assert(spaceCnt>0);
				const tabCnt = leadingCodeSpaceCount/spaceCnt;
				//LOG(leadingCodeSpaceCount, spaceCnt);
				if(tabCnt>0) {
					const removeCnt = tabCnt*spaceCnt-tabCnt;
					internal_setSubCells(subCells[removeCnt..$]);
					foreach(i; 0..tabCnt) spaceToTab(i);
					refreshTabIdx; //todo: should only be done once at the end...
				}
			}
		}
		
	}version(/+$DIDE_REGION+/all)
	{
		override void draw(Drawing dr)
		{
			//draw ////////////////////////////////
			if(/*lod.level>1*/ lod.zoomFactor*outerHeight<3 && im.actTargetSurface==0)
			{
				 //note: LOD is only enabled on the world view, not on the UI
				
				if(subCells.length)
				{
					const lwsCnt = leadingAnyWhitespaceCount; //opt: this should be memoized
					if(lwsCnt<subCells.length)
					{
						auto cell = subCells[lwsCnt];
						const r = bounds2(cell.outerPos, subCells.back.outerBottomRight) + innerPos;
						
						//decide row's average color. For simplicity choose the first char's color
						if(auto glyph = cast(Glyph)cell)
						{ dr.color = avg(glyph.bkColor, glyph.fontColor); }
						else if(auto cntr = cast(Container)cell)
						{ dr.color = cntr.bkColor; }
						else
						{ assert(0, "Invalid class in CodeRow"); }
						
						dr.fillRect(r.inflated(vec2(0, -r.height/4)));
					}
					
					//todo: Draw bigger subNodes.
				}
				
			}
			else
			{
				super.draw(dr);
				
				//visualize tabs ---------------------------------------
				
				//opt: these calculations operqations should be cached. Seems not that slow however
				/+
					todo: only display this when there is an editor cursor active in the codeColumn
									(or in the module)
				+/
				dr.translate(innerPos); dr.alpha = .4f;
				scope(exit) { dr.pop; dr.alpha = 1; }
				dr.color = clGray;
				
				if(tabIdxInternal.length)
				{
					dr.lineWidth = .5f;
					foreach(ti; tabIdxInternal)
					{
						assert(ti.inRange(subCells));
						auto g = cast(Glyph)subCells.get(ti);
						assert(g, "tabIdxInternal fail");
						if(g) {
							dr.vLine(g.outerRight-2, g.outerTop+2, g.outerBottom-2);
							//const y = g.outerPos.y + g.outerHeight*.5f;
							//dr.vLine(g.outerRight, y-2, y+2);
							//dr.hLine(g.outerLeft+1, y, g.outerRight-1);
						}
					}
				}
				
				//visualize spaces ------------------------------
				dr.pointSize = 1;
				foreach(g; glyphs.filter!(a => a && a.ch==' '))
				{
					assert(g);
					dr.point(g.outerBounds.center);
					/+
						todo: don't highlight single spaces only if there is a tab or character 
											or end of line next to them.
					+/
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
}static struct CodeColumnBuilder(bool rebuild)
{
	//CodeColumnBuilder /////////////////////////////////////////
	
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
			static int staticLineCounter;
			
			void NL()
			{ col.appendCell(actRow = new CodeRow(col, "", null)); }
			
			void initialize()
			{
				col.clearSubCells;
				NL; //there must be 1 row always. Empty column is a single empty row.
			}
			
			void appendChar(dchar ch)
			{
				switch(ch)
				{
					case '\n', '\r', '\u2028', '\u2029':
						if(skipNextN.chkClear && ch=='\n') break;
						skipNextN = ch=='\r';
						NL;
						staticLineCounter++;
					break;
					default: 
						//update cached textStyle
						if(_currentSk.chkSet(syntax))
					applySyntax(ts, syntax);
						
						actRow.appendSyntaxCharWithLineIdx(ch, ts, syntax, staticLineCounter); 
				}
			}
			
			void appendNode(CodeNode node)
			{
				assert(node);
				assert(node.parent is actRow);
				actRow.appendCell(node);
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
				actRow = col.rowCount ? col.rows[0] : null; //todo: there must be a first row.
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
						//opt: cache this array per each row
						
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
							if(auto delta = g.adjustBoldWidth(prevFontFlags)/+todo: must handle monospace too. skNumber should have a monospaced string.+/)
							{
								//row size changed. Later must call the spreadElasticTabs thing
								actRow.needMeasure; 
								//opt: cache this and call only once per each row
								//todo: Ensure elastic tabs recursive spread.
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
				//opt: cache this array per each row
				enforce(n, "Resyntax: CodeNode expected "~actPos.text);
				
				//no need to check anything
				//opt: no need to rebuild the node, only skip it.
				
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
			
			static char categorize(dchar ch)
			{
				if(isAlphaNum(ch) || ch.among('_', '#', '@')) return 'a';
				if(ch.among(' ', '\t', '\x0b', '\x0c')) return ' ';
				return '+';
			}
			
			foreach(s; src.splitWhen!((a, b) => categorize(a) != categorize(b)).map!text)
			{
				switch(s[0])
				{
					case ' ', '\t', '\x0b', '\x0c': 	syntax = skWhitespace; 	break;
					case '0': ..case '9':	syntax = skNumber; 	break;
					case '#':	syntax = skDirective; 	break;
					//todo: Support "#line n" directive for line numbering. Or ignore it... Just make karcshader.glsl work.
					case '@':	syntax = skLabel; 	break;
					
					default:	if(s[0].isAlpha || s[0]=='_')
					{
						if(auto kw = kwLookup(s))
						{
							with(KeywordCat)
							switch(kwCatOf(kw))
							{
								case Attribute:	syntax = skAttribute;	break;
								case Value:	syntax = skBasicType; 	break;
								case BasicType:	syntax = skBasicType;	break;
								case UserDefiniedType:	syntax = skKeyword;	break;
								case SpecialFunct:	syntax = skAttribute;	break;
								case SpecialKeyword:	syntax = skKeyword;	break;
								default:	syntax = skKeyword;	break;
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
			auto syntaxStack = [syntax];
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
					syntaxStack ~= syntax;
					switch(sr.src)
					{
						case "//", "/*", "/+":	syntax = skComment; 	appendStr(sr.src); 		break;
						case "{", "(", "[":	syntax = skSymbol;	appendStr(sr.src);	syntax = skWhitespace; 	break;
						case `q{`:	syntax = skString;	appendStr(sr.src);	syntax = skWhitespace;	break;
						case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`: 	syntax = skString;	appendStr(sr.src);		break;
						default:	syntax = skError;	appendStr(sr.src);		break;
						//todo: identifier quoted string `q"id`
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
								static if(rebuild) c.line = staticLineCounter;
								c.rebuild(scanner);
								appendNode(c);
							}
							switch(sr.src)
							{
								//todo: //comment must ensure that after it, there will be a NewLine
								case "//":	N!CodeComment; appendChar('\n'); 	continue; 
								case "/*", "/+",:	N!CodeComment;	continue; 
								case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`, `q{`: 	N!CodeString;	continue;
								case "{", "(", "[":	N!CodeBlock;	continue;
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
						appendStr(sr.src);
						
						syntax = syntaxStack.back;
						syntaxStack.length--;
						//todo: error checking for compatible closing tags. Maybe it can be implemented in the scanner too.
					}
					break;
					//case ScanOp.trans: setSyntax(skError); break;
					case ScanOp.content: 
						if(syntax.among(skComment, skString))
					{
						appendStr(sr.src); 
						//todo: highlight string escapes
						//todo: advanced comment formatting
					}
					else
					{ appendHighlighted_internal(sr.src); }
					break;
					default:
						syntax = skError; 
						appendStr(sr.src); //todo: it should optionally raise an exception. Example: when a structural scan fails, it should revert to highlighted.
				}
				
				scanner.popFront;
			}
			
			static if(rebuild)
			col.convertSpacesToTabs(Yes.outdent);
			
			static if(resyntax)
			foreach(r; col.rows)
			if(
				!r.flags._measured
										/+these are the rows affected by a width-changing fontFlag resuntax.+/
			)
			{
				r.adjustCharWidths; //todo: this should be replaced by monospace fontFlag.
				//230109
				//note: this is needed by the resized rows
				r.spreadElasticNeedMeasure;
			}
			
			col.needMeasure;
		}
	}
}class CodeColumn: Column
{
	//CodeColumn ////////////////////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		//note: this is basically the CodeBlock
		Container parent;
		//CodeContext context;
		
		enum defaultSpacesPerTab = 4; //default in std library
		int spacesPerTab = defaultSpacesPerTab; //autodetected on load
		
		DateTime lastResyntaxTime; //needed for the multithreaded syntax highligh processing. It can detect if the delayed syntax highlight is up-to-date or not.
		
		/// Minimal constructor creating an empty codeColumn with 0 rows.
		this(Container parent)
		{
			this.parent = parent;
			//this.context = context;
			//id.value = this.identityStr;  //id is not used anymore for this
			
			needMeasure;  //also sets measureOnlyOnce flag. This is an on-demand realigned Container.
			flags.wordWrap	= false;
			flags.clipSubCells	= true;
			flags.cullSubCells	= true;
			flags.columnElasticTabs = true;
			bkColor = mix(clCodeBackground, clGray, .25f);
		}
		
		this(Container parent_, Cell[][] cells)
		{
			this(parent_);
			subCells = cast(Cell[])(cells.map!(r => new CodeRow(this, r)).array);
			
			//one row must always present.
			if(subCells.empty) subCells ~= new CodeRow(this);
		}
		
		bool empty() const
		{ return !rows.length || rows.length==1 && rows[0].empty; }
		
		auto byCell()
		{ return rows.map!(r => r.subCells).joiner(only(null)); }
		
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
					//todo: make more rules like this
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
			
			//from here: module will tell
			if(auto m = moduleOf(this))
			{ return m.structureLevel; }
			return StructureLevel.plain;
		}
		
		SyntaxKind getSyntax(dchar ch)
		{
			if(getStructureLevel==StructureLevel.plain) {
				if(auto cmt = cast(CodeComment) parent)
				{
					return cmt.isDirective ? skDirective : skComment; //todo: Not working. #define ispurple, just like skComment...
				}
				else if(auto str = cast(CodeString) parent)
				{
					if(str.type != CodeString.Type.tokenString)
					return skString;
				}
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
			
			//todo: advanced version that checks the surroundings at the insert position.
		}
		
		int getLineOfFirstGlyphOrNode()
		{
			auto c = rows.map!(r => r.subCells).joiner.frontOrNull;
			if(auto g = cast(Glyph) c) return g.line;
			if(auto n = cast(CodeNode) c) return n.line;
			return 0;
		}
		
		auto calcWhitespaceStats()
		{
			import het.tokenizer : WhitespaceStats;
			WhitespaceStats whitespaceStats;
			foreach(r; rows)
			{
				//todo: optimize it somehow... Statistically...
				if(!r.leadingCodeTabs.empty)
				{ whitespaceStats.tabCnt++; }
				else
				{
					auto spaceCnt = r.leadingCodeSpaceCount;
					whitespaceStats.addSpaceCnt(spaceCnt);
				}
			}
			//note: this is just lame statistics to detect the size of a tab only for converting spaces to tabs.
			return whitespaceStats;
		}
		
		void convertSpacesToTabs(Flag!"outdent" outdent)
		{
			//remove the 2 stylistic spaces at the front and back, in a single row block. { a; }
			if(outdent)
			if(rows.length==1)
			with(rows.front)
			if(isCodeSpaces.length >= 3)
			if(isCodeSpaces[0] && !isCodeSpaces[1] && isCodeSpaces[$-1] && !isCodeSpaces[$-2]) {
				subCells = subCells[1..$-1];
				refreshTabIdx;
			}
				
			
			
			//todo: this can only be called after the rows were created. Because it doesn't call needMeasure_elastic()
			createElasticTabs;
			
			spacesPerTab = calcWhitespaceStats.detectIndentSize(DefaultIndentSize);
			//opt: this can be slow. Maybe put it on a keyboard shortcut.
			
			rows.each!(row => row.convertLeadingSpacesToTabs(spacesPerTab));
			
			//outdent
			if(outdent)
			{
				
				//todo: refactor it into CodeRow
				static bool isWhitespaceRow(CodeRow r)
				{
					return r.subCells.empty || r.subCells.all!(
						(c){
							if(auto g = cast(Glyph)c)
							if(g.ch.isDLangWhitespace && g.syntax.among(0/+whitespace+/, 9/+comment+/)) return true;
							return false;
						}
					);
					//return r.leadingCodeTabCount<r.cellCount; 
				}
				
				//remove first and last whitespace row
				const firstRowRemoved = subCells.length>1 && isWhitespaceRow(rows.front);	if(firstRowRemoved) subCells.popFront;
				const lastRowRemoved = subCells.length>1 && isWhitespaceRow(rows.back);	if(lastRowRemoved) subCells.popBack;
				
				//only rows that not only tabs are relevant
				bool relevant(CodeRow r)
				{
					return r.subCells.any!(
						(c){
							//non-stringLiteral whitespace is irrelevant
							if(auto g = cast(Glyph)c) {
								if(g.ch.among(' ', '\t') && g.syntax.among(0/+whitespace+/, 9/+comment+/)) return false;
								return true;
							}
							
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
						note: this fixes	the following bug:
											const 	a=1,   ->		const a=1,
												b=2;	b=2; 
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
				const canIgnoreFirstRow = !firstRowRemoved && (canBeStatement(rows.front) || rows.front.isWhitespaceOrComment || hasNonLeadingTab(rows.front)) && rows.drop(1).any!relevant;
				auto relevantRows = rows.drop(int(canIgnoreFirstRow)).filter!relevant;
				if(!relevantRows.empty)
				{
					const numTabs = relevantRows.map!"a.leadingCodeTabCount".minElement;
					
					/+
						todo: If there is an unsure situation, the an earlier numTabs value should be used to cut off tabs depending on the outer successful block.
															<- these tabse are a good example. The numTabs values must be stored in an stack outside.
					+/
					
					if(numTabs)
					foreach(r; rows)
					if(r.leadingCodeTabCount>=numTabs) {
						r.subCells = r.subCells[numTabs..$];
						r.refreshTabIdx;
						/+
							note: no need to call needRefresh_elastic because all rows will be refreshed.
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
			
			needMeasure;
		}
	}version(/+$DIDE_REGION+/all)
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
				
				int y0 = y;	 if(canGoUp) while(y0 > 0	&& detectTab(x, y0-1)) y0--;
				int y1 = y;	 if(canGoDown) while(y1 < rowCount-1	&& detectTab(x, y1+1)) y1++;
				
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
							//todo: the tabs below this one should inherit the indent of this first line
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
			
			//todo: bug with labels: c:\D\ldc2\import\std\internal\math\biguintcore.d search-> div3by2correction
			
		}
	}version(/+$DIDE_REGION+/all)
	{
		void resyntax()
		{
			//note: IT IS ILLEGAL TO MODIFY the contents in this. Only change to font color and flags are valid.
			//todo: older todo: resyntax: Problem with the Column Width detection when the longest line is syntax highlighted using bold fonts.
			//todo: older todo: resyntax: Space and hex digit sizes are not adjusted after resyntax.
			if(getStructureLevel>=StructureLevel.highlighted)
			{
				try { resyntaxer.appendHighlighted(shallowText); }catch(Exception e) {
					WARN(e.simpleMsg);
					//todo: mark the error.
				}
				//todo: additionally highlight language specific keywords.
			}
			else
			{ assert(0, "Unable to resyntax plain text."); }
		}
		
		void fillSyntax(SyntaxKind sk)
		{
			static TextStyle ts; ts.applySyntax(sk);
			rows.map!(r => r.glyphs).joiner.filter!"a".each!(
				(g){
					g.bkColor = ts.bkColor;
					g.fontColor = ts.fontColor;
					g.fontFlags = ts.fontFlags;  //todo: refactor this 3 assignments.
				}
			);
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
			
		int rowCharCount(int rowIdx) const
		{
			//todo: it's ugly because of the constness. Make it nicer.
			if(rowIdx.inRange(subCells))
			return cast(int)((cast(CodeRow)subCells[rowIdx]).subCells.length);
			return 0;
		}
		
		final string sourceText()
		{
			SourceTextBuilder builder;
			builder.put(this);
			return builder.result;
		}
		
		auto byShallowChar(dchar lineSep = '\n')()
		{ return rows.map!(r => r.chars).joiner(only(lineSep)); }
		
		dchar firstChar()
		{ return byShallowChar.frontOr('\0'); }
		
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
	}version(/+$DIDE_REGION+/all)
	{
		string shallowText()
		{
			return rows.map!(r => r.shallowText).join('\n');
			//note: it was joined bwith DefaultNewLine (\n\r), but can't remember why
		}
		
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
		
		void setupBorder()
		{
			this.setRoundBorder(8);
			margin.set(.5);
			padding.set(.5, 4);
		}
		
		override void rearrange()
		{
			setupBorder;
			
			//ote: Can't cast to CodeRow because "compiler.err" has Rows. Also CodeNode is a Row.
			auto rows = cast(Row[])subCells;
			assert(rows.map!(a => cast(Row)a).all);
			
			if(rows.empty)
			{ innerSize = DefaultFontEmptyEditorSize; }
			else
			{
				//measure and spread rows vertically rows
				float y=0, maxW=0;
				const totalGap = rows.front.totalGapSize; //note: assume all rows have the same margin, padding, border settings
				foreach(r; rows) {
					r.measure;
					r.outerPos = vec2(0, y);
					y += r.innerHeight+totalGap.y;
				}
				
				processElasticTabs(cast(Cell[])rows); //opt: apply this to a subset that has been remeasured
				
				const maxInnerWidth = rows.map!"a.contentInnerWidth".maxElement;
				innerSize = vec2(maxInnerWidth + totalGap.x, y);
				/+
					todo: this is not possible with the immediate UI because the autoWidth/autoHeigh 
									information is lost. And there is no functions to return the required content size.
									The container should have a current size, a minimal required size and separate autoWidth flags.
				+/
					
				if(!flags.dontStretchSubCells)
				foreach(r; rows) r.innerWidth = maxInnerWidth;
			}
				
			static if(rearrangeLOG) LOG("rearranging", this);
		}
		
		override void draw(Drawing dr)
		{
			//draw ///////////////////////////////////
			super.draw(dr);
			
			//visualize changed/created/modified
			addGlobalChangeIndicator(dr, this/*, topLeftGapSize*.5f*/);
			
			//visualize structuredLevel
			if(visualizeStructureLevels)
			{
				dr.color = syntaxFontColor(getSyntax('a'));//clWow[2+getStructureLevel];
				dr.lineWidth = -2;
				dr.drawRect(outerBounds);
			}
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
			test_RowCount("\n ", 2, "\n "); /+
				todo: a tabokat visszaalakitani space-ra. Csak a leading comment/whitespace-re menjen,
								 az elastic tabokat meg egymas ala kell igazitani space-ekkel.
								De ezt majd kesobb. Most minden tab lesz.
			+/
			test_RowCount("\r\n", 2, "\n");
			test_RowCount(" \n \n \r\n", 4, " \n \n \n"); //todo: a tabokat visszaalakitani space-ra
			test_RowCount(" \n \n \r\n ", 4, " \n \n \n "); //todo: a tabokat visszaalakitani space-ra
		}
	}
}
version(/+$DIDE_REGION+/all)
{
	
	/// Label //////////////////////////////////////////
	
	enum LabelType { folder, module_, mainRegion, subRegion }
	
	class Label : Row
	{
		Cell reference;
		bool alignRight;
		
		this(LabelType labelType, vec2 pos, string str, Cell reference=null)
		{
			this.reference = reference;
			
			auto ts = tsNormal;
			ts.fontColor = clWhite;
			ts.bkColor = clBlack;
			ts.transparent = true;
			
			with(LabelType) {
				const isRegion = labelType.among(mainRegion, subRegion)!=0;
				ts.fontHeight = isRegion ? 180 : 255;
				ts.bold = false && labelType != subRegion;
				alignRight = isRegion;
			}
			
			with(flags) {
				noHitTest = true;
				dontSearch = true;
				dontLocate = true;
				noBackground = true;
			}
			
			outerPos = pos;
			
			//icon
			Img icon;
			if(labelType==LabelType.module_)
			icon = new Img(File(`icon:\`~File(str).ext.lc));
			else if(labelType==LabelType.folder)
			icon = new Img(File(`icon:\folder\`));
			
			if(icon) {
				icon.innerSize = vec2(ts.fontHeight);
				icon.transparent = true;
				appendCell(icon);
			}
			
			//text
			appendStr(str, ts);
			measure;
		}
		
		void reposition()
		{
			if(reference) {
				outerX = alignRight ? reference.outerWidth-this.outerWidth : 0;
				outerY = reference.outerY;
			}
		}
	}
	
	//FolderLabel //////////////////////////////////
	
	auto cachedFolderLabel(string folderPath)
	{ return ImStorage!Label.access(srcId(genericId(folderPath)), new Label(LabelType.folder, vec2(0), Path(folderPath).name)); }
	
	void dumpDDoc(string src)
	{
		print("----Original DDoc---------------------------------------------------");
		LOG(src);
		print("----Processed DDoc-------------------------------------------------");
		string stack="*";
		auto scanner = src.DDocScanner;
		if(1)
		f:foreach(sr; scanner)
		{
			with(EgaColor)
			switch(sr.op)
			{
				case ScanOp.content:	{
					if(stack[$-1]=='`') write(ltGreen(sr.src));
					else if(stack[$-1]=='*') write(ltWhite(sr.src));
					else write(ltBlue(sr.src));
				} break;
				case ScanOp.push:	{
					write(yellow(sr.src));
					stack ~= sr.src[0];
				} break;
				case ScanOp.pop:	{
					write(yellow(sr.src));
					stack.popBack;
					if(stack.empty) { write(ltRed("Out of stack")); break f; }
				} break;
				case ScanOp.trans:	{ write(ltCyan(sr.src)); } break;
				default:	{ write(EgaColor.ltRed(sr.op.text~":"~sr.src)); } break;
			}
		}
		 
		print("---End of Processed DDoc----------------------------------------------");
	}
	
	
	//! Undo/History System ////////////////////////////////////
	/+
			
			 ----------------------> o.item[0] --------------------------->
																.item[n] --------------------------->
					doModifications ->
				<- unDoModifivations
																o.when
			
		 ---X---> loaded -----> modified --Y--> saved --X---> loaded --------->
		 X = unable to nndo, must go bact to the latest 'loaded' event
		 Y = nothing to undo
	+/
	
	string encodePrevAndNextSourceText(string prev, string act)
	{
		//todo: ezt kiprobalni jsonnal is, hogy van-e egyaltalan ennek a manualis cuccnak valami ertelme
		return prev.length.to!string~"\\"~prev~act;
	}
	
	string[2] decodePrevAndNextSourceText(string s)
	{
		auto a = s.splitter("\\");
		if(!a.empty)
		try
		{
			auto snum = a.front;
			const prevLen = snum.to!size_t;
			s = s[snum.length+1..$];
			if(prevLen<=s.length) return [s[0..prevLen], s[prevLen..$]];
		}
		catch(Exception)
		{}
		
		return typeof(return).init;
	}
	
	struct TextModificationRecord
	{ string where, what; }
	
	struct TextModification
	{
		bool isInsert;
		TextModificationRecord[] modifications; //Must preserve order!!!!
	}
	
}struct UndoManager
{
	version(/+$DIDE_REGION+/all)
	{
			
		//bug: UndoManager is sticking to a module. If the module is renamed, I don't know what happens...
		//opt: Loaded event is wasting a lot of memory. It should use differential text coding. And zip.
		//todo: also store the textSelections in the undoevents
		
		private uint lastUndoGroupId;
		
		enum EventType
		{ loaded, saved, modified }
		
		class Event
		{
			DateTime id; //unique ID
			EventType type;
			TextModification[] modifications;
			Event[] items;
			
			Event parent;
			
			this(Event parent, DateTime id, EventType type, bool isInsert, string where, string what)
			{
				this.parent = parent;
				this.id = id;
				this.type = type;
				modifications ~= TextModification(isInsert, [TextModificationRecord(where, what)]);
			}
			
			override int opCmp(in Object b) const
			{
				auto bb = cast(Event)b;
				return cmp(id, bb ? bb.id : DateTime.init);
			}
			
			string summaryText(string insMark = "(+)", string delMark = "(-)", string moreMark="...", bool isQuoted=true)(int maxStrLen = 20) const
			{
				final switch(type)
				{
					case EventType.loaded: return "Loaded";
					case EventType.saved: return "Saved";
					case EventType.modified:{
						string res;
						int actStrLen, actMode; //1:ins, -1:del
						foreach(const m; modifications)
						{
							const nextMode = m.isInsert ? 1 : -1;
							if(actMode.chkSet(nextMode))
							{
								const s = actMode>0 ? insMark : delMark;
								res ~= s;
								//no, because it could be a markup symbol: actStrLen += cast(int)s.walkLength;
							}
								
							//todo: detect backspace (text selections are going backwards, and reverse order)
							foreach(mr; m.modifications)
							foreach(ch; mr.what)
							{
								if(ch<32)
								{
									static if(isQuoted)
									{
										const s = ch.text.quoted[1..$-1];
										res ~= s;
										actStrLen += s.length.to!int;
											
										//compact \r\n into \n
										if(res.endsWith(`\r\n`)) {
											res = res[0..$-4]~`\n`;
											actStrLen -= 2;
										}
									}
									else
									{
										res ~= ('\u2400'+ch); //visual control chars
										actStrLen += 1;
									}
								}
								else
								{ res ~= ch; actStrLen++; }
								
								if(actStrLen>=maxStrLen)
								return res ~ moreMark;
							}
						}
						return res;
					}
				}
			}
			
			override string toString() const
			{ return format!"UndoEvent(%s, %s, items:%d)"(id, summaryText, items.length); }
			
			Container createUI(Event actEvent)
			{
				static bool tsInitialized;
				static TextStyle tsEvent;
				if(tsInitialized.chkSet) {
					tsEvent = tsNormal; //opt: save this
				}
				
				auto outer = new Row;
				
				Row inner;
				with(inner = new Row)
				{
					padding = "2";
					margin = "4";
					border = "1 normal black";
					
					auto ts = tsEvent;
					inner.appendMarkupLine(
						this.id.text~"\n"~summaryText!(
							tag("style fontColor=green"),
													tag("style fontColor=red"),
													tag("style fontColor=black")~"\u2026", false
						), ts
					);
				}
				
				Row innerWithArrow;
				with(innerWithArrow = new Row)
				{
					appendCell(inner);
					innerWithArrow.appendStr(this is actEvent ?  "\U0001F846" : "\u2b95", tsEvent); //arrow
				}
				inner = innerWithArrow;
				
				outer.appendCell(inner);
				
				if(items.length==1)
				{
					outer.appendCell(items[0].createUI(actEvent)); //recursive
				}
				else if(items.length>1)
				{
					auto col = new Column;
					outer.appendCell(col);
					
					foreach(item; items)
					col.appendCell(item.createUI(actEvent)); //recursive
				}
				
				return outer;
			}
			
		}
	}version(/+$DIDE_REGION+/all)
	{
		Event[DateTime] allEvents;
		
		private DateTime latestId; //used for unique id generation
		
		Event actEvent, rootEvent;
		
		protected bool executing; //when executing, disable the recording of events.
		
		Event oldestEvent()
		{ return allEvents.byValue.minElement(null); }
		Event newestEvent()
		{ return allEvents.byValue.maxElement(null); }
			
		bool hasAnyModifications() const { return allEvents.byValue.any!(e => e.type == EventType.modified); }
			
		void justLoaded(File file, string contents)
		{ addEvent(0, EventType.loaded, file.fullName, contents, false); }  //todo: fileName, fileContents for history
		void justSaved(File file, string contents)
		{ addEvent(0, EventType.saved, file.fullName, ""      , false); }
		void justInserted(uint undoGroupId, string where, string what)
		{ addEvent(undoGroupId, EventType.modified , where, what, true ); }
		void justRemoved(uint undoGroupId, string where, string what)
		{ addEvent(undoGroupId, EventType.modified , where, what, false); }
		
		void addEvent(uint undoGroupId, EventType type, string where, string what, bool isInsert)
		{
			if(executing) return;
			
			//append latest event in the same group
			const	    extendLastGroup = type==EventType.modified
				&& actEvent && actEvent.type==EventType.modified
				&& actEvent.modifications.length
				&& lastUndoGroupId==undoGroupId;
			if(extendLastGroup)
			{
				assert(actEvent.modifications.back.isInsert==isInsert);
				actEvent.modifications.back.modifications ~= TextModificationRecord(where, what);
			}
			else
			{
				lastUndoGroupId = undoGroupId;
				
				latestId.actualize;
				//a new unique Id. This garantees that all child is newer than the parent.
				//Takes 150ns to get the precise system time.
				
				//fusion of modification.
				const fusion = 		type == EventType.modified
					&& 	actEvent
					&&	actEvent.type == EventType.modified
					&&	latestId-actEvent.id < .75*second;
				if(fusion)
				{
					actEvent.id = latestId;
					actEvent.modifications ~= TextModification(isInsert, [TextModificationRecord(where, what)]);
				}
				else
				{
					if(!actEvent) assert(allEvents.empty);
					auto e = new Event(actEvent, latestId, type, isInsert, where, what);
					allEvents[e.id] = e;
					if(actEvent) actEvent.items ~= e;
					actEvent = e; //this is the new act
					if(!rootEvent) rootEvent = e;
				}
			}
		}
		
		bool canUndo()
		{
			return actEvent && actEvent !is rootEvent; //rootEvent must be a Load event. That can't be cancelled.
		}
		
		void undo(void delegate(in TextModification) execute, void delegate(string where, string what) reload)
		{
			assert(!executing);
			
			if(!canUndo) return;
			
			executing = true; scope(exit) executing = false;
			
			bool again;
			do {
				again = false;
				final switch(actEvent.type)
				{
					case EventType.modified: 	actEvent.modifications.retro.each!execute; break;
					case EventType.saved:	again = true; break; //nothing happened, "save event" is it's just a marking for the user
					case EventType.loaded:	reload(
						actEvent.modifications[0].modifications[0].where,
												actEvent.modifications[0].modifications[0].what.decodePrevAndNextSourceText[0]
					); break;
						//todo: ^^^^^^ ugly and needs range checking
				}
				actEvent = actEvent.parent;
			}
			while(again && canUndo);
		}
		
		bool canRedo()
		{ return actEvent && actEvent.items.length; }
		
		void redo(void delegate(in TextModification) execute, void delegate(string where, string what) reload)
		{
			//todo: refactor undo/redo. Too much copy paste.
			if(!canRedo) return;
			
			executing = true; scope(exit) executing = false;
			
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
						//todo: ^^^^ ugly and needs range check
				}
			}
			while(again && canRedo);
				
		}
			
		Container createUI()
		{ return rootEvent ? rootEvent.createUI(actEvent) : null; }
	}
}class StructureMap
{
	//StructureMap //////////////////////////////////////////
	
	private static StructureMap collector;
	private static bool collecting()
	{ return collector !is null; }
	
	bool debugTrigger;
	
	struct Rec
	{ CodeNode node; bounds2 bnd; }
	Rec[] visibleNamedNodes;
	
	void beginCollect()
	{
		assert(!collecting);
		collector = this;
		
		visibleNamedNodes.clear;
	}
	
	void onCollect(Drawing dr, CodeNode node)
	{
		assert(collector is this);
		
		if(node.caption != "")
		visibleNamedNodes ~= Rec(node, dr.inputTransform(node.outerBounds));
	}
	
	void endCollect(Drawing dr)
	{
		assert(collector is this);
		collector = null;
		
		if(debugTrigger.chkClear)
		{
			foreach(n; visibleNamedNodes)
			{ n.node.fullIdentifier.print; }
		}
		
		if(1) {
			
			/*
				dr.color = clFuchsia;
				dr.lineWidth = -1;
				dr.fontHeight = -18;
				foreach(n; visibleNamedNodes){
					//n.node.fullIdentifier.print;
					dr.drawRect(n.bnd);
					dr.textOut(n.bnd.topLeft, n.node.identifier);
					
				}
			*/
			
			
			if(lod.zoomFactor<0.5)
			{
				dr.lineWidth = -1;
				foreach_reverse(n; visibleNamedNodes)
				{
					dr.fontHeight = min(8512, n.bnd.height);
					
					const caption = n.node.caption;
					
					const width = dr.textWidth(caption);
					if(width > n.bnd.width) dr.fontHeight *= n.bnd.width/width;
					
					auto visibleHeight = dr.fontHeight * lod.zoomFactor;
					if(!visibleHeight.inRange(4, 64)) continue; 
					
					dr.alpha = 0.5;
					dr.color = mix(n.node.bkColor, clBlack, 0.75);
					dr.fillRect(n.bnd);
					
					dr.alpha = 1;
					dr.color = n.node.bkColor;
					dr.drawRect(n.bnd);
					
					dr.alpha = 1;
					dr.color = mix(n.node.bkColor, clWhite, 0.75);
					dr.textOut(n.bnd.topLeft, caption);
					
				}
			}
		}
	}
}class CodeNode : Row
{
	//CodeNode //////////////////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		Container parent;
		
		int line; //the starting source line
		
		auto subColumns()
		{ return subCells.map!(a => cast(CodeColumn)a).filter!"a"; }
		
		this(Container parent)
		{
			this.parent = parent;
			id = this.identityStr;
			
			needMeasure; //enables on-demand measure
			flags.wordWrap	= false;
			flags.clipSubCells	= true;
			flags.cullSubCells	= true;
			flags.rowElasticTabs	= true;
			flags.dontHideSpaces	= true;
			
			this.setRoundBorder(8);
			margin = "0.5";
			padding = "1 1.5";
		}
		
		~this()
		{ parent = null; }
		
		override inout(Container) getParent() inout
		{ return parent; }
		override void setParent(Container p)
		{ parent = p; }
		
		abstract void buildSourceText(ref SourceTextBuilder builder);
		
		final string sourceText()
		{
			SourceTextBuilder builder;
			if(cast(Module) this) builder.updateLineNumbers = true;
			buildSourceText(builder);
			return builder.result;
		}
		
		@property string identifier()
		{ return ""; }
		@property string caption()
		{ return ""; }
		
		CodeNode parentNode()
		{
			if(auto r = cast(CodeRow) parent)
			if(auto c = cast(CodeColumn) r.parent)
			if(auto n = cast(CodeNode) c.parent)
			return n;
			return null;
		}
		
		CodeNode namedParentNode()
		{
			for(auto p = parentNode; p; p = p.parentNode)
			{
				auto id = p.identifier;
				if(id!="") return p;
			}
			return null;
		}
		
		string fullIdentifier()
		{
			/*
				if(identifier=="") return "";
				auto identifierPath = allParents!CodeNode.map!(a => a.identifier).filter!"a.length".array.retro;
				return chain(identifierPath, only(identifier)).join('.');
			*/
			
			auto i = identifier; if(i=="") return "";
			
			for(auto n = namedParentNode; n; n = n.namedParentNode)
			i = n.identifier ~ '.' ~ i;
			
			return i;
		}
	}version(/+$DIDE_REGION+/all)
	{
		auto nodeBuilder(SyntaxKind syntax, int inverse_, Nullable!RGB customColor = Nullable!RGB.init)
		{
			
			CodeNodeBuilder res;
			with(res) {
				node 	= this;
				style 	= tsSyntax(syntax);  if(!customColor.isNull) style.fontColor = customColor.get;
				inverse 	= inverse_;
				darkColor	= style.bkColor,
				brightColor 	= style.fontColor,
				halfColor	= mix(darkColor, brightColor, inverse.predSwitch(0, .15f, 1, .5f, 1));
				
				style.bkColor = border.color = bkColor	= halfColor; 
				style.fontColor	= inverse ? darkColor : brightColor;
				style.bold 	= true;
			}
			
			//initialize node
			subCells = []; //This rebuilds and realigns the whole Row subCells.
			flags.yAlign = YAlign.center;
			
			return res;
		}
		
		override void rearrange()
		{
			innerSize = vec2(0);
			flags.autoWidth = true;
			flags.autoHeight = true;
			
			super.rearrange;
			static if(rearrangeLOG) LOG("rearranging", this);
		}
		
		override void draw(Drawing dr)
		{
			//collect structuremap data (It's preceding draw, to add the parent first)
			if(StructureMap.collector)
			StructureMap.collector.onCollect(dr, this);
			
			super.draw(dr);
			
			//visualize changed/created/modified
			addGlobalChangeIndicator(dr, this/*, topLeftGapSize*.5f*/);
			
			if(VisualizeCodeLineNumbers) {
				dr.color = clWhite;
				dr.fontHeight = 1.25;
				dr.textOut(outerPos, format!"%s"(line));
			}
		}
		
		void fillSyntax(SyntaxKind sk)
		{
			static TextStyle ts; ts.applySyntax(sk);
			subCells.map!(a => cast(Glyph) a).filter!"a".each!(
				(g){
					g.bkColor = ts.bkColor;
					g.fontColor = ts.fontColor;
					g.fontFlags = ts.fontFlags;  //todo: refactor this 3 assignments.
					g.syntax = cast(ubyte) sk;
				}
			);
			bkColor = ts.bkColor;
		}
		
	}
}class CodeContainer : CodeNode
{
	//CodeContainer /////////////////////////////
	CodeColumn content;
	
	abstract SyntaxKind syntax() const;
	abstract string prefix() const;
	abstract string postfix() const;
	
	this(Container parent)
	{
		super(parent);
		content = new CodeColumn(this);
	}
	
	override void buildSourceText(ref SourceTextBuilder builder)
	{ builder.put(prefix, content, postfix); }
	
	protected T parseBlockPrefix(T, string[] tokens, R)(R scanner) if(isScannerRange!R)
	{
		enforce(!scanner.empty);
		const sr = scanner.front;
		enforce(sr.op == ScanOp.push);
		auto res = tokens.countUntil(sr.src).to!T;
		scanner.popFront;
		return res;
	}
	
	final void rearrange_node() { super.rearrange; }
	
	override void rearrange()
	{
		with(nodeBuilder(syntax, prefix.among("[", "(", "{") ? 0 : 1))
		{
			content.bkColor = darkColor;
					
			put(prefix); 	const i0 = subCells.length;
			put(content);	const i2 = subCells.length;
			put(postfix); //todo: //slashComment must ensure that after it there is a newLine
					
			rearrange_node;
			
			//yAlign prefix to top and postfix to bottom
			//todo: 4 modes to align: center, top/bottom, stretch, stretch-repeat
			if(0)
			if(content.rowCount>1)
			{
				foreach(c; subCells[0..i0]) c.outerPos.y = 0;
				foreach(c; subCells[i2..$]) c.outerPos.y = innerHeight-c.outerHeight;
			}
			
		}
	}
}class CodeComment : CodeContainer
{
	 //CodeComment //////////////////////////////////////////
	enum Type
	{ slashComment, cComment, dComment, directive }
	enum TypePrefix 	= ["//"	, "/*", "/+", "#"];
	enum TypePostfix 	= [""	, "*/", "+/", "" ];
	//node: directive is detected by the high level parser, not the structured scanner.
	
	Type type;
	bool isDDoc;
	
	@property bool isDirective() const
	{ return type == Type.directive; }
	
	override SyntaxKind syntax() const
	{ return isDirective ? skDirective : skComment; }
	override string prefix() const
	{ return TypePrefix[type]; }
	override string postfix() const
	{ return type==Type.directive ? (content.rowCount>1 ? "\\" : "") : TypePostfix[type]; }
	
	this(CodeRow parent)
	{ super(parent); }
	
	void rebuild(R)(R scanner) if(isScannerRange!R)
	{
		type = parseBlockPrefix!(Type, TypePrefix)(scanner);
		isDDoc = !scanner.empty && scanner.front.op==ScanOp.content && scanner.front.src.startsWith(prefix.back);
		
		//get content
		auto rebuilder = CodeColumnBuilder!true(content);
		while(!scanner.empty)
		{
			if(scanner.front.op==ScanOp.push)
			{
				//opening a new something
				if(scanner.front.src=="/+")
				{
					auto n = new CodeComment(rebuilder.actRow);  //RECURSION!!!!!
					n.rebuild(scanner);
					rebuilder.appendNode(n);
					continue;
				}
				else
				{ enforce(0, "Invalid push: "~scanner.front.src); }
			}else if(scanner.front.op==ScanOp.pop)
			{
				//closing token
				scanner.popFront;
				break;
			}
			else
			{
				rebuilder.syntax = scanner.front.op==ScanOp.content ? skComment : skError;
				rebuilder.appendStr(scanner.front.src);
				
				//if(isDDoc) dumpDDoc(scanner.front.src); //todo: DDoc parser
			}
			scanner.popFront;
		}
		
		content.convertSpacesToTabs(Yes.outdent);
		needMeasure;
	}
	
	bool isSpecialComment()
	{
		return content.byShallowChar.startsWith(specialCommentMarker);
		//opt: startsWith should get a real range, not a copy of the full string.
	}
	
	string extractSpecialComment()
	{ return isSpecialComment ? content.sourceText.withoutStarting(specialCommentMarker) : ""; }
	
	bool isSpecialComment(string keyword)
	{ return extractSpecialComment.wordAt(0)==keyword; }
	
	bool verify(bool markErrors = false)()
	{
		bool anyErrors;
		void mark(Glyph g)
		{
			if(markErrors)
			if(g) {
				//todo: There should be a fontFlag: Error, and the GPU should calculate the actual color from a themed palette
				g.bkColor = clRed;
				g.fontColor = clYellow;
			}
			
			anyErrors = true;
		}
		
		auto byGlyph()
		{ return content.rows.map!(r => r.glyphs).joiner(only(null)); }
		
		void checkInvalid(dchar ch)
		{
			content.fillSyntax(skComment);
			
			byGlyph.each!((g){ if(anyErrors || g && g.ch==ch) mark(g); }); 
		}
		
		void checkInvalid2(dchar ch0, dchar ch1)
		{
			content.fillSyntax(skComment);
			
			bool lastCh0;
			foreach(g; byGlyph)
			{
				const actCh0 = g && g.ch==ch0;
				if(anyErrors || lastCh0 && g && g.ch==ch1) mark(g); 
				lastCh0 = actCh0;
			}
		}
		
		//todo: redundant code
		void checkNesting(dchar chOpen, dchar chClose)
		{
			if(chOpen==chClose)
			{ checkInvalid(chOpen); }
			else
			{
				content.fillSyntax(skComment);
				
				int cnt;
				byGlyph.each!(
					(g){
						if(g)
						{
							if(g.ch==chOpen) cnt++;
							else if(g.ch==chClose) cnt--;
							
							if(anyErrors || cnt<0) mark(g);
						}
					}
				);
				
				if(
					cnt>0//unclosed nesting!
				)
				{
					anyErrors = true;
					//todo: mark unclosed nesting
				}
			}
		}
		
		void markButFirstRow()
		{
			auto a = content.rows.drop(1).map!(r => r.glyphs).joiner(only(null));
			a.each!(g => mark(g));
		}
		
		with(Type)
		final switch(type)
		{
			case slashComment: 	if(content.rowCount>1) { anyErrors = true; markButFirstRow; }	break;
			case cComment: 	checkInvalid2('*', '/');	break;
			case dComment: 	checkInvalid2('+', '/'); checkInvalid2('/', '+'); 	break;
			case directive: 	checkNesting('(', ')'); 	break;
		}
		
		
		if(anyErrors && markErrors)
		{ fillSyntax(skError); }
		
		return !anyErrors;
	}
	
	override void rearrange()
	{
		if(isSpecialComment) {
			auto scmt = extractSpecialComment;
			if(scmt.wordAt(0)=="IMG")
			{
				with(nodeBuilder(syntax, 0))
				{
					auto cmd = scmt.commandLineToMap;
					auto f = File(cmd.get("1"));
					
					style.italic = false;
					put('\U0001F5BC');
					
					//load it immediatelly
					//todo: autorefresh code images
					bitmaps(f, No.delayed);
					
					auto img = new Img(f, darkColor);
					put(img);
					
					rearrange_node;
				}
				return;
			}
		}
		
		super.rearrange;
		
		verify!true;
	}
	
	override void buildSourceText(ref SourceTextBuilder builder)
	{
		enforce(verify, "Invalid comment format");
		super.buildSourceText(builder);
	}
}class CodeString : CodeContainer
{
	//CodeString //////////////////////////////////////////
	//todo: qString_id
	enum Type
	{ dString	, cChar	, cString	, rString	, qString_round	, qString_square	, qString_curly	, qString_angle	, qString_slash	, tokenString	 }
	enum TypePrefix 	= 	["`"	, "'"	, `"`	, `r"`	, `q"(`	, `q"[`	, `q"{`	, `q"<`	, `q"/`	, `q{`	];
	enum TypePostfix 	= 	["`"	, "'"	, `"`	, `"`	, `)"`	, `]"`	, `}"`	, `>"`	, `/"`	, `}`	];
	
	enum CharSize
	{ default_, c, w, d }
	
	Type type;
	CharSize charSize;
	
	override SyntaxKind syntax() const
	{ return skString; }
	override string prefix() const
	{ return TypePrefix[type]; }
	override string postfix() const
	{ return TypePostfix[type]~sizePostfix; }
	string sizePostfix() const
	{ return charSize!=CharSize.default_ ? charSize.text : ""; }
	
	this(CodeRow parent) { super(parent); }
	
	void rebuild(R)(R scanner) if(isScannerRange!R)
	{
		type = parseBlockPrefix!(Type, TypePrefix)(scanner);
		charSize = CharSize.default_;
		
		//get content
		auto rebuilder = CodeColumnBuilder!true(content);
		
		if(type==Type.tokenString)
		{
			content.bkColor = mix(syntaxBkColor(skString), clCodeBackground, .75f);
			//todo: clCodeBackground should be inherited to all the inner backgrounds.
			//todo: language dependent keyword coloring
			
			rebuilder.appendStructured(scanner); //this will stop at the closing "}"
			
			if(!scanner.empty && scanner.front.op==ScanOp.pop && scanner.front.src.startsWith("}"))
			{
				//closing token: Decode char/word/dword string element size specifier.
				if(auto cwdIdx = scanner.front.src.back.among('c', 'w', 'd'))
				charSize = cast(CharSize)cwdIdx;
				
				scanner.popFront;
			}
			else
			enforce(0, "Invalid tokenstring");
		}
		else
		{
			while(!scanner.empty)
			{
				if(scanner.front.op==ScanOp.push)
				{ enforce(0, "Invalid push: "~scanner.front.src); }
				else if(scanner.front.op==ScanOp.pop)
				{
					//closing token: Decode char/word/dword string element size specifier.
					if(auto cwdIdx = scanner.front.src.back.among('c', 'w', 'd'))
					charSize = cast(CharSize)cwdIdx;
					
					scanner.popFront;
					break;
				}
				else
				{
					rebuilder.syntax = scanner.front.op==ScanOp.content ? skString : skError;
					rebuilder.appendStr(scanner.front.src);
				}
				scanner.popFront;
			}
		}
		
		needMeasure;
	}
	
	bool verify(bool markErrors = false)()
	{
		bool anyErrors;
		void mark(Glyph g)
		{
			if(markErrors)
			if(g) {
				//todo: There should be a fontFlag: Error, and the GPU should calculate the actual color from a themed palette
				g.bkColor = clRed;
				g.fontColor = clYellow;
			}
			
			anyErrors = true;
		}
		
		auto byGlyph()
		{ return content.rows.map!(r => r.glyphs).joiner(only(null)); }
		
		void checkInvalid(dchar ch)
		{
			content.fillSyntax(skString);
			
			byGlyph.each!((g){ if(anyErrors || g && g.ch==ch) mark(g); }); 
		}
		
		void checkInvalid_escape(dchar ch, dchar escape)
		{
			content.fillSyntax(skString);
			
			bool lastEscape;
			foreach(g; byGlyph)
			{
				const actEscape = g && g.ch==escape;
				if(anyErrors || !lastEscape && g && g.ch==ch) mark(g); 
				lastEscape = actEscape;
			}
		}
		
		void checkNesting(dchar chOpen, dchar chClose)
		{
			if(chOpen==chClose)
			{ checkInvalid(chOpen); }
			else
			{
				content.fillSyntax(skString);
				
				int cnt;
				byGlyph.each!(
					(g){
						if(g)
						{
							if(g.ch==chOpen) cnt++;
							else if(g.ch==chClose) cnt--;
							
							if(anyErrors || cnt<0) mark(g);
						}
					}
				);
				
				if(
					cnt>0//unclosed nesting!
				)
				{
					anyErrors = true;
					//todo: mark unclosed nesting
				}
			}
		}
		
		with(Type)
		final switch(type)
		{
			case cString, cChar: 	checkInvalid_escape(TypePrefix[type].back, '\\');	break;
			case dString, rString: 	checkInvalid(TypePrefix[type].back); 	break;
			case qString_round, qString_square, qString_curly, qString_angle, qString_slash: 	checkNesting(TypePrefix[type].back, TypePostfix[type].front); 	break;
			case tokenString: 		break;
			/+todo: Any symbol can be used, not just slash '/'. The symbol in the qString must be a parameter.+/
			//todo: Identifier delimited qString.
		}
		
		
		if(anyErrors && markErrors)
		{ fillSyntax(skError); }
		
		return !anyErrors;
	}
	
	override void rearrange()
	{
		super.rearrange;
		verify!true;
	}
	
	override void buildSourceText(ref SourceTextBuilder builder)
	{
		enforce(verify, "Invalid string literal format");
		super.buildSourceText(builder);
	}
}class CodeBlock : CodeContainer
{
	//CodeBlock //////////////////////////////////////////
	enum Type 		 { block	, list	, index	 }
	enum TypePrefix 	= 	["{"	, "("	, `[`	];
	enum TypePostfix 	= 	["}"	, ")"	, `]`	];
	
	Type type;
	
	override SyntaxKind syntax	() const
	{ return skSymbol; }
	override string prefix() const
	{ return TypePrefix[type]; }
	override string postfix() const
	{ return TypePostfix[type]; }
	
	this(Container parent)
	{ super(parent); }
	
	void rebuild(R)(R scanner) if(isScannerRange!R)
	{
		type = parseBlockPrefix!(Type, TypePrefix)(scanner);
		auto rebuilder = CodeColumnBuilder!true(content);
		rebuilder.appendStructured(scanner); //this will stop at the closing token
		if(!scanner.empty && scanner.front.op==ScanOp.pop && scanner.front.src==postfix)
		{
			//analize patterns
			//note: -> processHighLevel
			/*
				if(scanner.front.src=="}"){
								auto crsr = content.endCursor;
								print(crsr);
								while(!isnull(crsr.pos)){
									crsr.moveRight(-1);
									print(2, crsr);
									auto c = content.rows[crsr.pos.y].subCells[crsr.pos.x];
									print(3, crsr);
									if(auto g = cast(Glyph)c){
										print(4, crsr);
										if(g.syntax==skWhitespace){
											write(" ");
										}else if(g.syntax==skKeyword){
											write(EgaColor.ltGreen(g.ch.text));
										}else{
											write(g.ch);
										}
									}else if(auto s = cast(CodeString)c){
										write(`"`);
									}else if(auto s = cast(CodeComment)c){
										write("/");
									}else if(auto b = cast(CodeBlock)c){
										write(b.prefix[0]);
									}else write("?");
								}
							}
			*/
			
			//closing token
			scanner.popFront;
		}
		else
		enforce(0, "Invalid block closing token");
		
		/+
			if(type!=Type.block){
						content.setRoundBorder(2);
						content.margin = "0.25";
						content.padding = "0.25 4";
						
						this.setRoundBorder(2);
						this.margin = "0.25";
						this.padding = ".6 .75";
					}
		+/
		
		needMeasure;
	}
}version(/+$DIDE_REGION+/all)
{
	/// Module ///////////////////////////////////////////////
	interface WorkspaceInterface
	{
		@property bool isReadOnly();
		@property StructureLevel getDesiredStructureLevel();
	}
	
	enum StructureLevel : ubyte
	{ plain, highlighted, structured, managed }
	
	class Module : CodeBlock
	{
		//this is any file in the project
		version(/+$DIDE_REGION+/all)
		{
			File file;
			
			DateTime fileLoaded, fileModified, fileSaved; //opt: detect these times from the outside
			size_t sizeBytes;  //todo: update this form the outside
			
			StructureLevel structureLevel;
			static foreach(e; EnumMembers!StructureLevel)
			mixin(
				format!q{
					@property is%s() const
					{ return structureLevel == StructureLevel.%s; }
				}(e.text.capitalize, e.text)
			);
			
			ModuleBuildState buildState;
			bool isCompiling;
					
			bool isMainExe, isMainDll, isMainLib, isMain, isStdModule, isFileReadOnly;
			
			UndoManager undoManager;
			
			override SyntaxKind syntax() const
			{ return skWhitespace; }
			override string prefix() const
			{ return ""; }
			override string postfix() const
			{ return ""; }
			
			this(Container parent, File file_)
			{
				super(parent);
				bkColor = clModuleBorder;
				fileLoaded = now;
				file = file_.actualFile;
				reload((cast(WorkspaceInterface) parent) ? (cast(WorkspaceInterface) parent).getDesiredStructureLevel : StructureLevel.plain);
			}
			
			override @property string identifier()
			{
				//todo: process the module statement.
				return file.nameWithoutExt;
			}
			
			override @property string caption()
			{ return file.name; }
			
			///It must return the actual logic. Files can be temporarily readonly while being compiled for example.
			bool isReadOnly()
			{
				//return inputs["ScrollLockState"].active;
				return isCompiling || isFileReadOnly || isStdModule || (cast(WorkspaceInterface)parent).isReadOnly;
			}
					
			void resetModuleTypeFlags()
			{ isMain = isMainExe = isMainDll = isMainLib = isStdModule = isFileReadOnly = false; }
					
			void detectModuleTypeFlags()
			{
				
				bool isMainSomething(string ext)()
				{
					if(content)
					if(auto r = content.getRow(0))
					{
						/+
							todo: this detector is not so nice...
													Need to develop more advanced source code parsing methods.
						+/
						
						//structured
						if(auto c = cast(CodeComment)(r.subCells.get(0)))
						if(sameText(c.content.shallowText.stripRight, "@"~ext)) return true;
						//highlighted/plain
						if(sameText(r.shallowText.stripRight, "//@"~ext)) return true;
					}
					
					return false;
				}
				isMainExe = isMainSomething!"exe";
				isMainDll = isMainSomething!"dll";
				isMainLib = isMainSomething!"lib";
				isMain = isMainExe || isMainDll || isMainLib;
				
				isStdModule = file.fullName.isWild(`c:\d\ldc2\import\*`);
				//todo: detect compiler import path correctly
				
				isFileReadOnly = isStdModule || file.isReadOnly || file.name.sameText("compile.err");
				//todo: periodically chenck if file is exists and other attributes in the IDE
			}
		}version(/+$DIDE_REGION+/all)
		{
			void reload(StructureLevel desiredStructureLevel, Flag!"useExternalContents" useExternalContents = No.useExternalContents, string externalContents="")
			{
				fileModified = file.modified;
				sizeBytes = file.size;
				resetModuleTypeFlags;
				structureLevel = StructureLevel.plain; //reset to the most basic level
						
				auto prevSourceText = sourceText;
				string sourceText = useExternalContents	? externalContents
					: this.file.readText;
				undoManager.justLoaded(this.file, encodePrevAndNextSourceText(prevSourceText, sourceText));
				
				CodeColumnBuilder!true.staticLineCounter = 1;
				
				void doPlain()
				{
					try
					{
						content.rebuilder.appendPlain(sourceText);
						structureLevel = StructureLevel.plain;
					}
					catch(Exception e)
					{ raise("Fatal error. Unable to load module even in plain mode. "~file.text~"\n"~e.simpleMsg); }
				}
				
				void doHighlighted()
				{
					try
					{
						content.rebuilder.appendHighlighted(sourceText);
						/+
							todo: this is NOT raising an exception, only draws the error with 
													red and and display a WARN. It should revert to plain...
						+/
						structureLevel = StructureLevel.highlighted;
					}
					catch(Exception e)
					{
						WARN("Unable to load module in highlighted mode. "~file.text~"\n"~e.simpleMsg);
						doPlain;
					}
				}
				
				void doStructured()
				{
					try
					{
						content.rebuilder.appendStructured(sourceText); 
						structureLevel = StructureLevel.structured;
					}
					catch(Exception e)
					{
						WARN("Unable to load module in structured mode. "~file.text~"\n"~e.simpleMsg);
						doHighlighted;
					}
				}
				
				void doManaged()
				{
					doStructured; 
					if(isStructured)
					{
						try
						{
							processHighLevelPatterns_block(content);
							structureLevel = StructureLevel.managed;
						}
						catch(Exception e)
						{
							WARN("Unable to load module in managed mode. "~file.text~"\n"~e.simpleMsg);
							doStructured;
						}
					}
				}
				
				[&doPlain, &doHighlighted, &doStructured, &doManaged][desiredStructureLevel]();
				
				needMeasure;
			}
			
			size_t linesOfCode()
			{
				return content.rowCount;
				//todo: update this. only good for unstructured code.
			}
			
			override void rearrange()
			{
				detectModuleTypeFlags;
				super.rearrange;
			}
			
			void save()
			{
				if(isReadOnly) return;
				sourceText.saveTo(file, Yes.onlyIfChanged); //sourceText can throw
				clearChanged;
				fileModified = file.modified; //opt: slow
				fileSaved = now;
			}
		}
	}
}version(/+$DIDE_REGION ErrorList+/all)
{
	//ErrorList ////////////////////////////////////////////
	
	auto createErrorListCodeColumn(Container parent)
	{
		auto code = new CodeColumn(parent);
		code.padding = "1";
		code.flags.dontStretchSubCells = true;
			
		import dide2; //todo: should not import main module.
		auto buildResult = global_getBuildResult;
		auto markerLayerHideMask = global_getMarkerLayerHideMask;
			
		foreach(file; buildResult.remainings.keys.sort)
		{
			auto pragmas = buildResult.remainings[file];
			if(pragmas.length) code.append({ UI_CompilerOutput(file, pragmas.join('\n')); });
		}
			
		with(im)
		code.append(
			{
				foreach(loc; buildResult.messages.keys.sort)
				{
					auto msg = buildResult.messages[loc];
					if(msg.parentLocation) continue;
					if((1<<msg.type) & markerLayerHideMask) continue;
					msg.UI(buildResult.subMessagesOf(msg.location));
				}
			}
		);
		
			
		return code;
	}
	
	
	//bug: ErrorListModule is fucked up
	deprecated class ErrorListModule : Module
	{
		//ErrorListModule ////////////////////////////////////////////////////////
		this(Container parent, File file_)
		{
			super(parent, file_);
			
			reload(StructureLevel.plain);
		}
		
		override bool isReadOnly()
		{ return true; }
		
		override void reload(StructureLevel desiredLevel, Flag!"useExternalContents" useExternalContents = No.useExternalContents, string contents="")
		{
			clearSubCells;
			fileModified = now;
			sizeBytes = 0; //todo: note this has no file.
			resetModuleTypeFlags;
			structureLevel = StructureLevel.plain; //reset to the most basic level
			content = createErrorListCodeColumn(this); //todo: remake this with a parser
			appendCell(enforce(content));
			needMeasure;
		}
	}
}
version(/+$DIDE_REGION+/all)
{
	version(/+$DIDE_REGION+/all)
	{
		version(/+$DIDE_REGION color tables+/all)
		{
			
			//High level stuff ///////////////////////////////////
			
			RGB brighter(RGB a, float f)
			{ return (a.rgbToFloat*(1+f)).floatToRgb; }
			
			enum clPiko : RGB8
			{
				G940 	= RGB(139, 59, 43).brighter(.25f),
				G239 	= RGB(245, 156, 0),
				G231 	= RGB(238, 114, 3),
				G119 	= RGB(221, 11, 47).brighter(.35f),
				G115 	= RGB(222, 0, 126),
				G107 	= RGB(158, 25, 129),
				G62 	= RGB(92, 36, 131).brighter(.25f),
				R1 	= RGB(22, 186, 231),
				R2 	= RGB(0, 134, 192),
				R3 	= RGB(0, 105, 180),
				R4 	= RGB(0, 79, 159),
				R9 	= RGB(0, 48, 93),
				W 	= RGB(134, 188, 37),
				BW 	= RGB(101, 179, 46),
				W3 	= RGB(0, 120, 88),
				WY 	= RGB(0, 169, 132),
				K15 	= RGB(255, 227, 126),
				K30 	= RGB(255, 237, 0),
				DKW 	= RGB(255, 204, 0),
				GE31 	= RGB(157, 157, 156),
			} RGB structuredColor(string name, RGB def = clGray)
			{
				switch(name)
				{
					case "template":	return clPiko.G940;
					case "enum":	return clPiko.G239;
					case "alias":	return clPiko.G231;
					case "if", "switch", "final switch", "else":	return clPiko.G119;
					case "for", "do", "while", "foreach", "foreach_reverse": 	return mix(clOrange, RGB(221, 11, 47), .66);
					case "version", "debug", "static if", "static foreach", "static foreach_reverse":	return mix(clPiko.G115, clPiko.G119, .5);
					case "module", "import":	return clPiko.G107;
					case "unittest":	return clPiko.G62;
						
					case "section":	return clPiko.R1;
					case "with":	return clPiko.R2;
					case "__unused1":	return clPiko.R4;
						
					case "class":	return clPiko.W;
					case "interface":	return clPiko.BW;
					case "struct":	return clPiko.W3;
					case "union":	return clPiko.WY;
					case "mixin template":	return clPiko.K15;
					case "mixin":	return clPiko.DKW;
					case "statement":	return clGray;
					case "function", "invariant":	return clSilver;
					case "__region":	return clGray;
					default:	return def;
				}
			}
			
			//bug mix(clOrange, clPiko.G119, .5).floatToRgb   FUCKING FAILS to compile!!!!
			
		}
		version(/+$DIDE_REGION keyword tables+/all)
		{
					
			//keyword tables /////////////////////////////////////
			
			static immutable namedSymbols =
			[
				 //["none", ""] is mandatory
				["none"	, ""	],		 	["semicolon"	, ";"	],		 	["colon"	, ":"	],		 	["comma"	, ","	],
				["equal"	, "="	],		 	["question"	, "?"	],		 	["block"	, "{"	],		 	["params"	, "("	],
			];
			
			static immutable sentenceDetectionRules =
			[
				["; = ? module import alias"	, ";"	],
				["{ template unittest invariant"	, "{"	],
				["enum struct union class interface"	, "; {"	],
				[":"	, ":"	],
			];
			
			static immutable prepositionPatterns =
			[
				"with (",
				"for (", 	"foreach (", 	"foreach_reverse (", 	"static foreach (", 	"static foreach_reverse (",
				"while (", 	"do",		
				"version (", 	"debug (",  	"debug", 	
				"if (", 	"static if (", 	"else if (", 	"else static if (",
				"else", 	"else version (", 	"else debug (", 	"else debug", 
				"switch (", 	"final switch (",		
				"try", 	"catch (", 	"finally",	
				"debug =",	"else debug =", //special case: debug = is a statement, not a preposition!.
				"__region", //decoded from: version(/+$D*DE_REGION title+/all)
				//"scope (", "synchronized (", "synchronized" //todo: These are for statements only! 
			].sort!"a>b".array;
			//note: descending order is important.  "debug (" must be checked before "debug"
			
			//used in detectCurlyBlock()
			static immutable statementDetecionEndings = [
				"with(",	"for(", 	"foreach(", 	"foreach_reverse(",
				"while(", 	"do", 	"if(", 	"else", 
				"version(", 	"debug(",		
				"switch(",	"try", 	"catch(", 	"finally"
				//todo: 
			].sort.array; //sorting is important: it is binary-searched
			
			static immutable prepositionLinkingRules =
			[
				[["do"	], ["while"	]],
				[["if", "static if", "version", "debug", "else if", "else static if", "else version", "else debug"	], ["else", "else if", "else static if", "else version", "else debug"	]],
				[["try", "catch"	], ["catch", "finally"	]]
			];
			
			static immutable attributeKeywords =
			[
				"extern", "align", "deprecated",
				"private", "package", "package", "protected", "public", "export",
				"pragma", "static", "abstract ", "final", "override", "synchronized", "auto", "scope", 
				"const", "immutable", "inout", "shared", "__gshared", 
				"nothrow", "pure", "ref", "return"
			];
		}
	}version(/+$DIDE_REGION keyword helper fun+/all)
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
		
		
		//todo: move to utils
		bool isDLangIdentifier(alias fStart=isDLangIdentifierStart, alias fCont=isDLangIdentifierCont, S)(in S s)
		{
			auto a = s.byDchar;
			if(a.empty) return false;
			if(!a.front.unaryFun!fStart) return false;
			a.popFront;
			return a.all!(unaryFun!fCont);
		}
		
		alias isDLangNumber(S) = isDLangIdentifier!(isDLangNumberStart, isDLangNumberCont, S);
		
		auto genExtractIdentifiers(string ending)()
		{
			return ending.format!q{
				sentenceDetectionRules.filter!"a[1].canFind(`%s`)".map!"a[0].split".join.filter!(a => a.length && a[0].isDLangIdentifierStart).array //todo: isDLangIdentifier
			};
		}
		
		static immutable 	prepositionKeywords 	= prepositionPatterns.map!(a => a.stripRight(" (=")).array.sort.uniq.array, 
		 	blockKeywords 	= mixin(genExtractIdentifiers!"{"),
			statementKeywords 	= mixin(genExtractIdentifiers!";");
		
		static foreach(name; "preposition attribute statement block".split)
		{ mixin(format!q{bool is%sKeyword	(string s) { return %sKeywords	.canFind(s); } }(name.capitalize, name)); }
		
		
		//getLeadingAttributesAndComments /////////////////////////////////////////
		
		/+
			auto getLeadingAttributesAndComments(Token[] tokens){
						auto orig = tokens;
					
						ref Token t(){ assert(tokens.length); return tokens[0]; }
						void advance(){ assert(tokens.length); tokens = tokens[1..$]; }
						void skipComments(){ while(t.isComment) advance; }
						void skipBlock(){ auto level = t.level; while(!t.among!")"(level)) advance; advance; }
					
						while(tokens.length){
							if(t.isComment){              //comments
								advance;
							}else if(t.among!"@"){
								advance; skipComments;
								if(t.isIdentifier){         //@UDA
									advance; skipComments;
									if(t.among!"(") skipBlock;//@UDA(params)
								}else if(t.among!"("){         //@(params)
									skipBlock;
								}else{
									WARN("Garbage after @");  //todo: it is some garbage, what to do with the error
									break;
								}
							}else if(t.isAttribute){      //attr
								advance; skipComments;
								if(t.among!"(") skipBlock;  //attr(params)
							}else{
								break; //reached the end normally
							}
						}
					
						return orig[0..$-tokens.length];
					}
		+/
		
		
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
}class Declaration : CodeNode
{
	//Declaration /////////////////////////////
	version(/+$DIDE_REGION+/all)
	{
		CodeColumn attributes;
		string keyword;
		CodeColumn header, block;
		char ending;
		
		int internalNewLineCount, internalTabCount; //todo: this counter only needed to count up to 2.
		
		@property bool hasInternalNewLine() const { return internalNewLineCount>0; }
		@property bool hasInternalTab() const { return internalTabCount>0; }
		
		bool hasJoinedNewLine, hasJoinedTab;
		
		bool explicitPrepositionBlock;
		
		Declaration nextJoinedPreposition;
		
		bool isBlock() const
		{ return ending=='}'; }
		bool isStatement() const
		{ return ending==';'; }
		bool isSection() const
		{ return ending==':'; }
		bool isPreposition() const
		{ return ending==')'; }
		
		bool isRegion; //detected automatically
		bool regionDisabled;
		
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
			static bugcnt = 0;
			if(!bugcnt++) { beep; ERR("//todo: set the parents and bkcolors of the joinedPrepositions. A 2. else if feltetel hattere is rossz."); }
			
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
				!explicitPrepositionBlock//bugfix: if(1){if(2)a;}else b;  else is wrongly moved inside blocks
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
			
			while(act && act.isPreposition)
			{
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
		
		bool isSimpleBlock() const
		{ return isBlock && keyword=="" && header.empty && attributes.empty; }
		
		void verify() {
			if(isBlock)
			{
				enforce(block, "Invalid null block.");
				enforce(keyword=="" || keyword.isBlockKeyword, "Invalid declaration block keyword: "~keyword.quoted);
			}
			else if(isStatement)
			{ enforce(keyword=="" || keyword.isStatementKeyword, "Invalid declaration statement keyword: "~keyword.quoted); }
			else if(isSection)
			{ enforce(keyword.among(""), "Invalid declaration section keyword: "~keyword.quoted); }
			else if(isPreposition)
			{ enforce(keyword.isPrepositionKeyword, "Invalid declaration preposition keyword: "~keyword.quoted); }
			else
			enforce(0, "Invalid declaration ending: "~ending.text.quoted);
		}
		
		this(Container parent, Cell[][] attrCells, string keyword, Cell[][] headerCells, CodeColumn block, char ending)
		{
			super(parent);
			
			auto detectInternalNewLine(Cell[][] a) //blabla
			{
				if(!isBlock) return a;
				if(a.length>1 && a.back.map!structuredCellToChar.all!"a==' '") {
					a.popBack; 
					internalNewLineCount++;
				}
				return a;
			}
			
			this.keyword = keyword;
			this.ending = ending;
			this.block	= block; if(block) block.setParent(this);
			this.attributes 	= new CodeColumn(this, attrCells.withoutStartingSpace.withoutEndingSpace);
			this.header 	= new CodeColumn(this, detectInternalNewLine(headerCells.withoutStartingSpace.withoutEndingSpace));
			
			decodeSpecial;
			
			verify;
			
			
			
			//RECURSIVE!!!
			
			if(isBlock)
			{
				if(keyword=="enum")
				processHighLevelPatterns_enum(block);
				else {
					if(header) processHighLevelPatterns_goInside(header);
					processHighLevelPatterns_block(block);
				}
			}
			else if(isStatement)
			{ if(keyword=="") { processHighLevelPatterns_statement(header); } }else if(isPreposition)
			{
				foreach(p; allJoinedPrepositionsFromThis)
				{
					if(p.header) processHighLevelPatterns_goInside(p.header);
					processHighLevelPatterns_block(p.block);
				}
			}
			
			calcLine;
		}
		
		this(CodeBlock blk)
		{
			//promote the block.
			assert(blk);
			assert(blk.parent);
			assert(blk.type == CodeBlock.Type.block);
			
			super(blk.parent);
			
			blk.content.setParent(this);
			this.ending	= '}';
			this.block	= blk.content; if(block) block.setParent(this);
			this.attributes 	= new CodeColumn(this, []);
			this.header 	= new CodeColumn(this, []);
			
			verify;
			
			calcLine;
		}
		
		protected void calcLine()
		{
			void doIt(CodeColumn col)
			{
				if(!col) return;
				line = col.getLineOfFirstGlyphOrNode;
			}
			
			line = 0;
			doIt(attributes); if(line) return;
			doIt(header); if(line) return;
			doIt(block); if(line) return;
		}
		
	}version(/+$DIDE_REGION+/all)
	{
		string type()
		{
			if(keyword.length) return keyword;
			if(isStatement	) return "statement";
			if(isPreposition	) return "preposition";
			if(isSection	) return "section";
			if(isBlock	) return "function";
			return "";
		}
		
		char opening() const
		{ return ending.predSwitch('}', '{', ')', '(', ' '); }
		
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
			
			return true;;
		}
		
		private bool _identifierValid; //todo: use Nullable!string
		private string _identifier;
		override @property string identifier()
		{
			
			string calcIdentifier()
			{
				if(isBlock)
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
					if(keyword.among("class", "struct", "interface", "union", "template", "mixin template", "enum"))
					{
						return header.shallowText.strip.wordAt(0);
						//todo: this is nasty!!! Should use proper DLang identifier detection.
					}
				}
				return "";
			}
			
			if(_identifierValid.chkSet) { _identifier = calcIdentifier; }
			
			return _identifier;
		}
		
		override string caption()
		{
			//todo: cache this too
			if(isRegion) return header.sourceText;
			return identifier;
		}
		
		private void decodeSpecial()
		{
			//note: only callable from within this(), as it does not reset flags.
			
			if(isPreposition && keyword=="version" && header.rowCount==1)
			if(auto cmt = header.firstCell!CodeComment)
			if(auto optionIdx = header.shallowText.withoutStarting(compoundObjectChar).among("all", "none"))
			if(cmt.isSpecialComment("REGION"))
			{
				//todo: extract "all" or "none" from version(). Handle enabled/disabled region.
				
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
				
				/*
					 apply new colors.... Rather use comment colors.
									
									const bkc = RGB(0x606060), fc = clWhite;
									
									header.bkColor = bkc;
									
									foreach(r; header.rows){
										foreach(c; r.subCells)
											if(auto g = cast(Glyph)c){
												g.bkColor = clRegionBk;
												g.fontColor = clRegionFont;
											}
									}
				*/
				
				return;
			}
		}
		
		bool isSpecial()
		{ return isRegion; }
		
	}version(/+$DIDE_REGION+/all)
	{
		
		private final void emitDeclaration(R)(ref R outputRange)
		{
			with(outputRange) {
				
				void putIndent()
				{ static if(UI) put("    "); } void putNLIndent()
				{ putNL; putIndent; } void putUi(A)(A a)
				{ static if(UI) put(a); }
				
				if(isBlock)
				{
					if(isSimpleBlock)
					{
						/+
							todo: the transition from simpleBlock to non-simple block is not clear.
												A boolean flag is needed to let the user write into the header.
						+/
						put("{", block, "}");
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
						
						put("{", block, "}");
						putUi(' ');
					}
				}
				else if(isPreposition)
				{
					if(isRegion)
					{
						static if(UI)
						{
							if(
								!header.empty//optional header title
							)
							{
								put(header); 
								if(hasInternalNewLine) putNL;else put(' ');
							}
							put(block);
							//region has a thin border and no braces.
						}
						else
						{
							//verify that header is valid for a /+comment+/
							const src = header.sourceText;
							enforce(isValidDLang("/+"~src~"+/"), "Invalid DIDE marker format. (Must be a valid /+comment+/):\n"~src);
							
							put(
								"version(/+" ~ specialCommentMarker ~ "REGION" ~ (header.empty ? "" : " "),
								header,
								"+/"~(regionDisabled ? "none":"all")~")"
							);
							if(hasInternalNewLine) putNL;else put(' ');
							put("{", block, "}");
						}
					}
					else
					{
						void emitPreposition(Declaration decl, bool closingSemicolon = false)
						{
							with(decl) {
								//note: prepositions have no attributes. 'static' and 'final' is encoded in the keyword.
								
								//todo: put a space before 'else;   ->    if(1) { a; }else b;
								
								if(canHaveHeader) {
									put(keyword);
									
									static bool isHeaderOmittableForKeyword(string keyword) {
										enum list = prepositionPatterns	.filter!(a => a.endsWith(" ("))
											.map!(a => a[0..$-2])
											.filter!(a => prepositionPatterns.canFind(a))
											.array;
										//Normally in DLang, these are the keywords havingoptionally omittable ()blocks: "debug", "else debug"
										return list.canFind(keyword);
									}
									const omitHeader = header.empty && isHeaderOmittableForKeyword(keyword); //debug has an optional () block
									
									putUi(' ');
									if(!omitHeader) put("(", header, ")", !UI); 
								}else { put(keyword); }
								
								if(closingSemicolon)
								{ put(';'); }else {
									
									if(internalNewLineCount > hasJoinedNewLine) putNLIndent;
									else put(internalTabCount > hasJoinedTab ? '\t' : ' ');
									
									/+todo: ^^ ez a space lehet tab is. Ekkor az else if chain blokkjai szepen egymas ala vannak igazitva. 
									Jelenleg az if expressionja es a blokkja kozotti senkifoldjen csak a space, newline es a comment van detektalna (a comment az lehet, hogy nincs is!).
									Viszont legyen a tab is detektalva! Az 3 allapot.
									A tab eseten egy fel sornyi szunetet is be lehetne iktatni. A space eseten ez nem kell, mert a blokk eleje is mashol lesz. 
									A newline eseten eleve ott a vastag elvalaszto sor.
									Update: Ez elvileg mar megy, de kell hozza teszteket csinalni!
									+/
									
									//todo: there should be a tab right after the if and before the (expression). I must make the rules of things that could go onto the surface of CodeNodes.
									
									put("{", block, "}", explicitPrepositionBlock);
								}
								putUi(' ');
								
								if(nextJoinedPreposition)
								{
									//todo: I think this is dead code. It does nothing.
									if(nextJoinedPreposition.hasJoinedNewLine) putNL;
									else if(nextJoinedPreposition.hasJoinedTab) put('\t');
									//note: It doesn't matter if the newline is bewore or	 after or on both sides
									//note: ...around an "else". As it is either joined horizontally or vertically.
									
									const nextClosingSemicolon = keyword=="do" && nextJoinedPreposition.keyword=="while";
									
									//todo: A preposition novelje az indent-et!  Ezen az if else-n lehet is ellenorizni.
									/+static if(CODE)
									{	//this puts too much tabs
										const canIndent = !nextClosingSemicolon && (nextJoinedPreposition.internalNewLineCount > nextJoinedPrepositionhasJoinedNewLine);
										if(canIndent) indentCount++;
										scope(exit) if(canIndent) indentCount--;
									}+/
									
									emitPreposition(nextJoinedPreposition, nextClosingSemicolon); //RECURSIVE!!!
								}	
							}
						}
						
						emitPreposition(this);
					}
				}
				else
				{
					//statement or section
					if(keyword!="")
					{
						put(attributes);
						if(!attributes.empty) put(' '); 
						put(keyword);
					}
					if(canHaveHeader)
					{
						if(keyword!="") put(' '); 
						put("", header, ending.text);
					}
					else
					put(ending); 
						
					putUi(' '); //this space makes the border thicker
				}
			}
		}
		
		override void rearrange()
		{
			//_identifierValid = false;
			
			auto builder = nodeBuilder(skWhitespace, isStatement && keyword=="" ? 0 : 2, structuredColor(type).nullable); 
			with(builder)
			{
				//set subColumn bkColors
				if(isBlock || isPreposition) block.bkColor = mix(darkColor, brightColor, 0.125f);
				
				foreach(a; only(attributes, header))
				if(a)
				{ a.bkColor = a.empty ? mix(darkColor, brightColor, 0.75f) : darkColor; }
				
				if(isPreposition && isRegion)
				header.bkColor = syntaxBkColor(skComment);
				
				emitDeclaration(builder);
			}
			
			super.rearrange;
		}
		
		override void buildSourceText(ref SourceTextBuilder builder)
		{ emitDeclaration(builder); }
		
		override void draw(Drawing dr)
		{
			//draw ///////////////////////////////////
			super.draw(dr);
			
			if(isRegion && regionDisabled)
			{
				dr.color = syntaxBkColor(skComment); 
				dr.alpha = .66; 
				dr.fillRect(outerBounds);
				
				dr.lineWidth = 2;
				dr.color = syntaxFontColor(skComment); 
				dr.alpha = .5;
				dr.drawX(outerBounds);
				dr.alpha = 1;
			}
			/*
				if(lod.pixelSize>2){ //experimental node identifier display
								auto id = identifier;
								dr.fontHeight = lod.pixelSize*12;
								if(outerHeight>=dr.fontHeight && id!=""){
									
									auto p = outerPos + vec2(max(0, outerWidth-dr.textWidth(id)), 0);
									
									dr.color = clBlack	; dr.fontBold = true	; dr.textOut(p, id);
									dr.color = clWhite	; dr.fontBold = false	; dr.textOut(p, id);
								}
							}
			*/
		}
	}
}version(/+$DIDE_REGION parsing helper fun+/all)
{
	//parsing helper fun ////////////////////////////////////////////////
	
	dchar structuredCellToChar(Cell c)
	{
		return c.castSwitch!(
			(Glyph	g) 	=> isDLangWhitespace(g.ch) ? ' ' : g.ch	,
			(CodeComment 	_) 	=> ' '	,
			(CodeString	_) 	=> '"'	,
			(CodeBlock	b) 	=> b.prefix[0]	,
			(Declaration	d)	=> compoundObjectChar
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
	
	bool isWhitespaceOrComment(CodeRow row)
	{ return !row || row.subCells.all!isWhitespaceOrComment; }
	
	dstring extractThisLevelDString(CodeRow row)
	{ return row.subCells.map!structuredCellToChar.dtext; }
	
	
	dstring extractThisLevelDString(CodeColumn col)
	{
		
		//every chacacter or node maps to exactly one character (including newline)
		const str = col.rows.map!extractThisLevelDString.join("\n");
		return str;
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
				//opt: this is unoptimal but simple
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
				//opt: this conversion from dstring to string is slow and only string identifiers 
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
						//note: this parser ignores numbers
					}
					else if(lastState=='a')
					wordFound = true;
				}
				if(actState=='a') actWord ~= ch;  //note: this parser ignores numbers
				if(wordFound) tryAppend(actWord, idx-actWord.length); //note: no 'else' here!!!
				if(actState==' ') tryAppend(ch.dtext, idx); //symbol
			}
			if(actState=='a') tryAppend(actWord, str.length-actWord.length); //note: ignores numbers
			
			return res[];
		}
	}public
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
		{ skip, transfer, fetch }
		
		void processSrc(Operation op, bool whitespaceAndCommentOnly = false)(int targetIdx)
		{
			assert(srcIdx <= targetIdx);
			assert(srcPos.y.inRange(col.rows));
			assert(srcPos.x.inRange(0, col.rowCharCount(srcPos.y)));
			
			static if(op==Operation.fetch) { resultCells = null; resultCells.length = 1; }
			
			while(srcIdx < targetIdx)
			{
				auto srcRow = col.rows[srcPos.y]; //opt: only fetch row when needed
				if(srcPos.x<srcRow.subCells.length)
				{
					//Cell
					auto cell = srcRow.subCells[srcPos.x];
					
					static if(whitespaceAndCommentOnly)
					{
						bool isComment()
						{
							if(cast(CodeComment)cell) return true;
							if(auto g = cast(Glyph)cell) if(g.ch.isDLangWhitespace) return true;
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
		
		bool transferWhitespaceAndComments()
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
		
		void transferWhitespaceAndCommentsAndDirectives()
		{
			//Directives are specialized CodeComments.
			//They are detected and processed here.
			//Preprocessor support is limited The low level parser
			transferWhitespaceAndComments;
			
			again:
			if(peekChar=='#')
			{
				skipUntil(srcIdx + 1); //skip the '#'
				
				Cell[][] directiveCells;
				version(/+DIDE_REGION Collect all lines of the directive+/all)
				{
					while(1) {
						fetchUntil(srcIdx+remainingCellsOnLine);
						assert(resultCells.length==1);
						
						bool isExtendedLine() {
							if(auto g = cast(Glyph) resultCells[0].back)
							if(g.ch == '\\') return true;
							return false;
						}
						
						if(isExtendedLine)
						{
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
				directive.content = new CodeColumn(directive, directiveCells);
				directive.content.fillSyntax(skDirective); //todo: directive syntax highlight not working.
				directive.line = directive.content.getLineOfFirstGlyphOrNode;
				
				appendCell(directive);
				endingWhite.each!(c => appendCell(c));
				
				//ignore tokens inside the directive
				dropOutpacedTokens;
					
				//clean up the remaining NewLine and retry
				if(transferWhitespaceAndComments)
				goto again;
			}
		}
	}
}version(/+$DIDE_REGION+/all)
{
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
			opt: this is a slow search, it tries all the patterns one by one through the whole string.
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
	}Declaration[] extractPrepositions(ref Cell[][] cellRows)
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
			
		auto skipWhite()
		{
			auto res = cellRows.removeFront!(c => c.isWhitespaceOrComment)(int.max);
			totalNewLineCount += res.newLineCount;
			totalTabCount += res.tabCount;
			totalComments ~= res.comments;
		}
		
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
			auto decl = new	Declaration(null, null, keyword, paramCells, new CodeColumn(null, []), ')');
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
	
	
	struct DDeclarationRecord {
		string type;
		string header;
	}
	DDeclarationRecord[] dDeclarationRecords;
	
	
}version(/+$DIDE_REGION+/all)
{
	void processHighLevelPatterns_block(CodeColumn col_)
	{
		//processHighLevelPatterns ////////////////////////////////
		
		//from here, process statements and declarations
		
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
						
						if(!receiver.explicitPrepositionBlock && receiver.block.empty && decl.isSimpleBlock && receiver.isPreposition)
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
						}
						
						if(decl.isPreposition)
						receiver = decl;
						else if(decl.isStatement || decl.isBlock)
						receiver = null;
						else if(decl.isSection)
						{
							if(!decl.isLabel) receiver = null;
							/+note: A preposition can receive any number of labels, but only one attribute section. +/
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
											todo: to handle dangling warnings, else dstPrepositions should be marked as dangling, 
																						and ensure that no other propositions could join to them. 
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
						auto a = dst.retro.map!(r => r.subCells.retro).joiner(only(null)/+newLine is null+/).drop(1);
						while(!a.empty)
						{
							if(a.front is null)
							{
								//note: this newline is in front of the else.
								//Currently the trigger to put the else on a new line is the newline after the else.
								//In text there are 4 combinations. In structured view there are only 2. (same line or new line)
								hasJoinedNewLine = true;
							}
							else if(a.front.isWhitespaceOrComment)
							{
								//todo: collect the comment and and at least make a WARN
								if(auto cmt = cast(CodeComment) a.front)
								{
									//WARN("Lost comment: "~cmt.sourceText);  
									//precedingComments ~= cmt;
									//Note: This comment is saved somewhere else.
									
									//todo: process joined comments
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
							//{ static cnt = 0; print(cnt++, srcPreposition.keyword, "-", dstPreposition.keyword); }
							
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
							
							srcPreposition.appendJoinedPreposition(dstPreposition);
						}
						break; //dstPreposition can present in only one rule
					}
				}
			}version(/+$DIDE_REGION+/all)
			{
				while(tokens.length)
				{
					transferWhitespaceAndCommentsAndDirectives; //these comments are going into the body of the block
					
					const main = tokens.front;
					auto mainIsKeyword()
					{ return main.token.functionSwitch!"a.text.startsWith('_')"; }
					
					sw: switch(main.token)
					{
						static foreach(a; sentenceDetectionRules)
						mixin(format!q{case %s: fetchTokens!([%s]); break sw;}(a[0].toSymbolEnumList, a[1].toSymbolEnumList));
						default:	fetchSingleToken;
					}
					
					auto ending = sentence.back;
					const endingChar = ending.token.predSwitch(semicolon, ';', colon, ':', block, '}', ' ');
					const keyword = endingChar.among(';', '}') && mainIsKeyword ? main.token.text[1..$] : "";
					
					version(/+$DIDE_REGION Handle DLang Function Contracts+/all)
					{
						if(sentence.length==1 && sentence.back.token == DeclToken.block) {
							/+
								//step back on whitespace and zero or one () param block
								int stepBackOnParamsAndWhitespace(int i0)
								{
									bool paramsFound;
									int j=-1;
									foreach_reverse(i; 0..i0)
									{
										const ch = srcDStr[i];
										if(ch.isDLangWhitespace) continue;
										else if(ch=='(' && !paramsFound) paramsFound = true;
										else { j = i; break; }
									}
									return j;
								}
								
								int checkContractKeyword(int endPos)
								{//checks if there is an 'in' or an 'out' keyword is written backwards from endPos
									if(endPos>=0)
									{
										auto A(int i){ return srcDStr.get(endPos-i); }
										bool isEnd(dchar ch){ return !isDLangIdentifierCont(ch); }
										
										if(A(0).among('n', 't', 'o') && A(1).among('i', 'u', 'd'))
											print(A(3), A(2), A(1), A(0));
										
										//todo: it's so ugly, but it works
										if(A(0)=='n' && A(1)=='i' && isEnd(A(2))) return 1;
										if(A(0)=='t' && A(1)=='u' && A(2)=='o' && isEnd(A(3))) return 2;
										if(A(0)=='o' && A(1)=='d' && isEnd(A(2))) return -1;
									}
									return 0;
								}
								
								while(tokens.length){
									const t = checkContractKeyword(stepBackOnParamsAndWhitespace(first-1));
									if(t==0) break;
									LOG(t);
									first = tokens.front;
									fetchTokens!([DeclToken.block]);
									if(t<0) break;
								}
							+/
							
							static auto isSkippableContractBlock(dstring s)
							{
								//opt: would be faster to check for invalid chars first. "dinotu({ \n"   Or check the number of letters first.
								
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
							while(!tokens.empty && tokens.front.token == DeclToken.block && isSkippableContractBlock(srcDStr[i .. tokens.front.end]))
							{
								ending = tokens.front;
								sentence ~= ending;
								i = ending.pos;
								tokens.popFront;
							}
						}
					}
					
					
					
					/*
						if(isContract){
												print("Contract Sentence debug-------------");
												sentence.each!print;
												print;
												print("main:", main);
												print("kw:", keyword);
											}
					*/
					
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
							
							//todo: Transform { x } => {x}   Warning: It can be bad for undo/redo
							//if(block.rowCount==1 && block.rows.front.length>=2 && block.rows.frontfirstChar==' '
						}
						else
						enforce(0, "Unhandled endingChar: "~endingChar.text.quoted);
						
						auto declarationChain = 	extractPrepositions(attrs.length ? attrs : header) ~
							new Declaration(null, attrs, keyword, header, block, endingChar);
						
						foreach(decl; declarationChain) appendDeclaration(decl);
						
						//collect statistics
						/+
							if(1) dDeclarationRecords ~= DDeclarationRecord(
														only(keyword, decl.isStatement ? ";" : decl.isSection ? ":" : decl.isBlock ? "}" : "").join,
														(decl.attributes.empty ? decl.header : decl.attributes).extractThisLevelDString.text
													);
						+/
						
						joinPrepositions;
						
						//print(dDeclarationRecords.back);
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
	
	void processHighLevelPatterns_enum(CodeColumn col_) {
		if(!col_) return;
		NOTIMPL;
		//print("enum block: "~col_.extractThisLevelDString.text);
	}
	
	void processHighLevelPatterns_statement(CodeColumn col_) {
		if(!col_) return;
		
		//print("statement: "~col_.extractThisLevelDString.text);
		processHighLevelPatterns_goInside(col_);
	}
	
	bool isHighLevelBlock(CodeColumn col) {
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
	
	void processHighLevelPatterns_goInside(CodeColumn col_)
	{
		//recursively look inside {} () [] q{} blocks
		foreach(ref cell; col_.rows.map!(r => r.subCells).joiner)
		{
			if(auto blk = cast(CodeBlock) cell)
			{
				final switch(blk.type)
				{
					case CodeBlock.Type.block:
						blk.content.processHighLevelPatterns_optionalBlock;
						if(blk.content.isHighLevelBlock) { cell = new Declaration(blk); }
						break; 
					case CodeBlock.Type.index: blk.content.processHighLevelPatterns_goInside; break;
					case CodeBlock.Type.list: blk.content.processHighLevelPatterns_goInside; break; //todo: function params augmentations: named params
				}
			}
			else if(auto str = cast(CodeString) cell)
			{
				if(str.type == CodeString.Type.tokenString)
				str.content.processHighLevelPatterns_optionalBlock;
			}
		}
	}
	
	
	enum CurlyBlockKind { empty, declarationsOrStatements, list }
	
	auto detectCurlyBlock(CodeColumn col_) {
		/+
			opt: This is terrbily slow. Must do this with a CodeColumn.bidirectional range.
					That also should detect identifiers/keywords.
		+/
		auto p = col_.extractThisLevelDString.text;
		p = p.replace("\n", " ");
		p = p.replace("  ", " ");
		p = p.replace(" {", "{");
		p = p.replace(" [", "]");
		p = p.replace(" (", ")");
		p = p.strip;
		
		//first start with easy decisions at the end of the block
		if(p=="") return CurlyBlockKind.empty;
		if(p.endsWith(';') || p.endsWith(':')) return CurlyBlockKind.declarationsOrStatements;
		
		if(p.canFind("{,") || p.canFind(",{")) return CurlyBlockKind.list;
		if(p.canFind(';')||p.canFind('{')) return CurlyBlockKind.declarationsOrStatements;
		
		//note: no need to discover keywords. A {} alone is enough.
		/+
			if(p.endsWith('{') && p.length>0){ //{ while(f()){} }
						
						/*string word;
						version(/+$DIDE_REGION take the last word and an optional '(' before '{' +/all)
						{
							sizediff_t i = p.length-2;
							void acc(){ word = p[i--] ~ word; }
							if(i>=0 && p[i]=='(') acc;
							while(i>=0 && p[i].isAlpha) acc;
						}
						
						if(word.endsWith('(') || statementDetecionEndings.assumeSorted.contains(word))
							return CurlyBlockKind.declarationsOrStatements; //actually this is a statement for sure
							
						print("!!!", word, "$$$", p);*/
						return CurlyBlockKind.declarationsOrStatements;
					}
		+/
		
		//do more complicated searches invlonving the entire block
		
		//give it up: it's not a declaration, neither a statement block
		return CurlyBlockKind.list;
	}
	
	
	void processHighLevelPatterns_optionalBlock(CodeColumn col_)
	{
		//if(p!="" && !p.endsWith(';'))
		//print("optional Block:", p);
		
		if(detectCurlyBlock(col_)==CurlyBlockKind.declarationsOrStatements) {
			/+
				auto p = col_.extractThisLevelDString.text.replace("\n", " ").strip;
				print("attempting: ", p);
			+/
			processHighLevelPatterns_block(col_);
		}else {
			processHighLevelPatterns_goInside(col_); //keep continue to discover recursively
		}
	}
}
//Test codes ////////////////////////////////////////
struct TestCodeStruct
{
	unittest { hello; }public mixin template TestMixinTemplate() { int a; int b; }
	public template TestTemplate() { int a; int b; }
	public alias aaa = TestClass2;
	public enum TestEnum = 5, TestEnum2 = 6;
	public enum TestBlock : int { a = 5, b = a }
	public struct TestStruct { int a; int b; }
	public union TestUnion { int a; int b; }
	public class TestClass1 { int a; int b; }
	public class TestClass2 : TestClass1 {}
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
}version(abcd)
{
	//nothing
}
else debug
{
	
	int testStatements()
	{
		ivec2 v2 = { [1, 2] };
		with(TestClass2) static int i=5;
		with(TestClass1)
		{
			if(1==2) {}else {}
			if(1==2) sleep(1);else {}
			if(1==2) {}else sleep(1);
			if(1==2) {}else if(2==3) {}else sleep(1);
			
			for(int i; i++; i<10) writeln(i);
			label1: foreach(i; 0..10) { writeln(i); break label1; }
			static foreach_reverse(i; 0..10) { { writeln(i); continue; } }
			while(0) {}
			do sleep(1);while(0);
			do { sleep(1); }while(0);
			
			switch(5) {
				case 6: break;
				case 7:..case 9: break;
				case 10, 11, 12: break;
				default: 
			}
			
			return typeof(return).max;
			
		}with(TestClass1)
		{
			/+
				todo: the next comment is handled badly (lost):
								Ctrl+C puts it after the else
								After reload it disappears
			+/
			static if(0) label1:label2:writeln;
			else
			label3:label4:{ label5: }
			  
			
			if(0) a;else b;
			if(0) a;else if(0) b;else c;
			if(0) if(0) a;else b; //else is dangling
			if(0) if(0) { a; }else b; //else is dangling
			if(0) { if(0) a; }else b;
			if(0) { if(0) a;else b; }
			if(0) { if(0) a;else b; }else c;
			
			
			//horizontal
			
			if(0) { /*comment05*/ block; }
			
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
			
			if(0) bla;else bla;
			
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
			{ /*comment23*/ }
			
			if(0) {}else if(0) {}else {}
		}with("if else newLine combinations")
		{
			if(0) {}else {} //OK 00 00
			
			if(0)
			{}else {} //OK 10 00
			
			if(0) {}
			else {} //FIXED 00 11  (extra NL after "else")
			
			if(0)
			{}
			else {} //FIXED 10 11  (extra NL after "else")
			
			if(0) {}else
			{} //OK 00 10
			
			if(0)
			{}else
			{}//OK 10 10
			
			if(0) {}
			else
			{} //OK 00 11
			
			if(0)
			{}
			else
			{} //OK 10 11
		}with(TestClass1)
		{
					
			//fixed bug: extra new line at the end of this if. The unwanted extra newline is before the else.
			if(0) {
				if(0) {}
				else {}
			}
			//this way it's ok
			if(0) { if(0) {}else {} }
			
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
			
			/+$DIDE_IMG c:\dl\smiley_face.bmp+/
			/+$DIDE_IMG c:\dl\smiley_face2.bmp+/
		}with(TestClass1)
		{
			//todo: parse this correctly:
			if(1) labe3:label2:1 ? f, f : f, f, i=5;  
			
			
			//todo: Extra empty statement at the end.  Must distinguish "while();" and "do ; while();}
			do {}while(0);
			
			
			//todo: do-uble bad parsing
			double f() { return 0; } 
			
			
			//todo: this if else looks bad
			if(1) a;
			else b;
			
			//todo: make this look good
			if(1) delta = 0;
			else
			beep;
			
			
			//todo: make this look good
			if(isDLangIdentifierStart(ch)) s = 'a';
			else if(isDLangNumberStart(ch)) s = '0';
			else s = ' ';
			
			//fixed: joinPreposition is WRONG!!!!!
			if(1) { if(2) a; }else b; //bad: else goes inside the explicit {} block
			if(1) if(2) a;else b; //good + Warning
			if(1) { if(2) a;else b; }//good
		}
	}
	
	debug(blabla) :
}
else
{
	
	auto testfun = (){
		//todo: process lambda's  =>{ or (){ , but not ={
		do sleep(1);while(0);
	};
}version(none) {
	//static initializer vs labmda
	
	auto l1 = { lambda1; };
	auto l2 = [{ lambda2; }];
	auto l3 = ({ lambda3; });
	auto l4 = b({ lambda4; });
	auto l5 = { lambda5; }();
	auto l5 = (){ lambda6; }();
	auto l6 = ()=>{ lambda7; }();
	auto l7 = a=>{ lambda7; }.b;
	
	struct S { int i; }/+Extra semicolon+/;
	S s1 = {};
	S s2 = { 5 };
	S[] s1 = [4, { 5 }];
	S[] s1 = [{ 5 }];
	S[] s1 = [{ 5 }, { 6 }];
	S[] s2 = b({ lambda4; });
	struct T { S s; }
	T[] t1 = [{ { 5 } }]; /+
		todo: this is clear that the innermost block is not 
				a statement/declaration block. 
				It should use normal CodeBlock instead of Declaration. 
	+/
	T[] t1 = [{ { 5,6 } }];
	
	struct S { int a, b, c, d = 7; }
	S s = { a:1, b:2 };
	S u = { 1, 2 };
	S v = { 1, d:3 };
	S w = { b:1, 3 };
	S w = { b:1, {} };
	S w = { { /+nothing+/ } };
	void a() { static if(5) { { /+nothing+/ } } }
	
}version(none) {
	//test do/while
	void xx()
	{
		do a;while(1);
		
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
	out{ y; }in{ x; }//c1
	/+c7+/out(aaa)/+c2+/{ y; }//c3
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
		{ /+c+/ }
		
	}
}


debug debug = hehehe;else version = hahaha;

static if(
	0/*skipped comment*///after a newline too
)
static foreach(ch; ['a', 'b']) : //this must be the last test
		mixin(format!"enum testEnum", ch, "='", ch, "';");
		pragma(msg, mixin("testEnum", ch));
		
//c
//d

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
}

struct StylisticBugs
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
	} struct divergentTabsBug()
	{
		//CellPath ///////////////////////////////
		
		auto byPathElements()
		{
			return path	.a
				.b;
		}
		
	} void userTabs()
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
	} void manyTabs()
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
					//todo: ^^^^ ugly and needs range check
			}
		}
		while(again && canRedo);
	}
}