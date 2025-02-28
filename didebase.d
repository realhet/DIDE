module didebase; 
import het.ui; 

import didecolumn: CodeColumn; 
import diderow: CodeRow; 
import didenode : CodeNode; 
import didemodule: Module, AnimatedCursors, DefaultNewLine; 

version(/+$DIDE_REGION+/all) {
	struct TextCursor
	{
		/+
			Todo: to be able to edit and preserve the textcursor indices, 
			textcursor should target objects, not indices. [codeRow, cell] 
			would be the minimum. codeRow.subCellIdx(cell) and codeRow.index 
			should be cached.
		+/
		
		CodeColumn codeColumn; 
		
		ivec2 pos; 
		float desiredX=0; //used for up down movement, after left right movements.
		
		static if(AnimatedCursors)
		{
			vec2 	targetPos	= vec2(float.nan),
				animatedPos 	= vec2(float.nan); 
			float 	targetHeight,
				animatedHeight; 
			//Todo: should use CaretPos structs and interpolate them.
		}
		
		@property bool valid() const
		{ return (codeColumn !is null) && pos.x>=0 && pos.y>=0; } 
		bool opCast(B:bool)() const => valid; 
		
		@property int rowCharCount() const
		{
			//Todo: constness
			return codeColumn ? codeColumn.rowCharCount(pos.y) : 0; 
		} 
		
		@property bool isAtLineStart() const
		{ return pos.x<=0; } 
		@property bool isAtLineEnd() const
		{ return pos.x>=rowCharCount; } 
		
		int opCmp(in TextCursor b) const
		{
			//simple case: they are on the same column or any of them are invalid
			if(codeColumn is b.codeColumn || !valid || !b.valid)
			return cmpChain(cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x)); 
			
			/+
				Opt: multiColumn selection sorting is extremely slow. 
				Maybe the hierarchical column order should be cached in an integer value.
			+/
			
			/+
				Opt: this index searching is fucking slow. But this is the correct way to sort. 
				Maybe it should be cached somehow...
			+/
			auto order(in TextCursor c)
			=> c.codeColumn	.thisAndAllParents!Container
				.array.retro
				.slide!(No.withPartial)(2)
				.map!((a)=>(a[0].subCellIndex(a[1]))); 
			return cmpChain(
				cmp(order(this), order(b)), 
				
				/+only for safety:+/
				cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x)
			); 
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
		enum home	= int.min,
		end	= int.max,
		wordLeft	= home+1,
		wordRight 	= end-1; 
		
		void calcDesiredX_unsafe()
		{ desiredX = pos.x<=0 ? 0 : codeColumn.rows[pos.y].subCells[pos.x-1].outerBounds.right; } 
			
		void calcDesiredX_safe()
		{
			desiredX = 0; 
			if(pos.x>0 && codeColumn)
			if(auto row = codeColumn.getRow(pos.y))
			if(auto cell = row.subCells.get(pos.x-1))
			desiredX = cell.outerRight; 
			
			
			/+
				if(!codeColumn || pos.x<=0)
				{ desiredX = 0; }
				else
				{
					if(auto row = codeColumn.getRow(pos.y))
					{
						if(row.cellCount==0)
						{ desiredX = 0; }
						else
						{ desiredX = row.subCells[pos.x-1/+Todo: it's still not safe+/].outerBounds.right; }
					}
					else
					{ desiredX = 0; }
				}
			+/
		} 
		
		void moveToLineStart()
		{
			moveRight(home); 
			if(pos.x) moveRight(home); //it steps over leading tabs too
		} 
		
		void moveToLineEnd()
		{ moveRight(end); } 
		
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
				//Opt: cache idx2pos and pos2idx. The line searcher is slow in those
				pos = codeColumn.idx2pos(codeColumn.pos2idx(pos)+delta); //Note: this must be a clamped move
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
				moveDown(delta.y); 
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
		
		auto toReference()
		{
			TextCursorReference res; 
			if(valid)
			if(auto row = (codeColumn).getRow(pos.y))
			{
				//Todo: fix constness!!
				res.path = CellPath(row); 
				res.left	= row.subCells.get(pos.x-1); 
				res.right	= row.subCells.get(pos.x); 
			}
			
			return res; 
		} 
	} 
	CodeRow rowAt(CodeColumn cc, int y)
	{
		if(!cc) return null; 
		return cast(CodeRow)(cc.subCells.get(y)); 
	} 
	
	CodeRow rowAt(TextCursor tc)
	{ return rowAt(tc.codeColumn, tc.pos.y); } 
	
	
	Cell cellAt(CodeRow cr, int x)
	{
		if(!cr) return null; 
		return cr.subCells.get(x); 
	} 
	
	Cell cellAt(CodeColumn cc, ivec2 p)
	{ return cellAt(rowAt(cc, p.y), p.x); } 
	
	Cell cellAt(TextCursor tc)
	{ return cellAt(tc.codeColumn, tc.pos); } 
	
	
	dchar charAt(const CodeRow cr, int i, bool newLineAtEnd=true)
	{
		if(!cr || i<0 || i>cr.subCells.length) return '\x00'; 
		if(i==cr.subCells.length) return newLineAtEnd ? '\n' : '\x00'; 
		const cell = cr.subCells[i]; 
		if(const g = cast(const Glyph)cell) return g.ch; else return '\x01'; 
	} 
	
	dchar charAt(const CodeColumn cc, ivec2 p)
	{
		if(!cc || p.y<0 || p.x<0 || p.y>=cc.rowCount) return '\x00'; 
		return charAt(cast(const CodeRow)cc.subCells[p.y], p.x, p.y<cc.rowCount-1); 
	} 
	
	dchar charAt(const TextCursor tc)
	{ return charAt(tc.codeColumn, tc.pos); } 
	
	enum WordCategory { space, symbol, word} 
	
	WordCategory wordCategory(dchar ch)
	{
		import std.uni; 
		if(ch.isDLangIdentifierCont) return WordCategory.word; 
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
			if(forward)	return cursor.pos.y>cursor.codeColumn.lastRowIdx; 
			else	return cursor.pos.y<0; 
		} 
		void popFront()
		{
			if(forward)	cursor.moveRight_unsafe; 
			else	cursor.moveLeft_unsafe; 
		} 
		auto save() { return this; } 
	} 
	
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
	
	bounds2 worldOuterBounds(Cell cell)
	{
		auto bnd = worldInnerBounds(cell); 
		if(bnd) {
			bnd.low 	-= cell.topLeftGapSize,
			bnd.high 	+= cell.bottomRightGapSize; 
		}
		return bnd; 
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
		//Todo: this works for single line only!
		return ts.valid 	? worldBounds(ts.cursors[0]) | worldBounds(ts.cursors[1])
			: bounds2.init; 
	} 
	
	bounds2 worldBounds(TextSelection[] ts)
	{
		//Todo: constness
		return ts.map!worldBounds.fold!"a|b"(bounds2.init); 
	} 
	
	struct CaretPos
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
	
	struct TextSelection
	{
		//TextSelection ///////////////////////////////
		TextCursor[2] cursors; 
		bool primary; 
		
		this(TextCursor c0, TextCursor c1 ,bool primary)
		{ cursors[0] = c0; cursors[1] = c1; this.primary = primary; } 
		this(TextCursor c, bool primary)
		{ cursors[0] = c; cursors[1] = c; this.primary = primary; } 
		
		auto dup() { return TextSelection(cursors[0], cursors[1], primary); } 
		
		ref caret()
		{ return cursors[1]; } 
		ref const caret()
		{ return cursors[1]; } 
		
		auto codeColumn()
		{ return cursors[0].codeColumn; } 
		
		@property bool valid() const
		{ return cursors[].map!"a.valid".all && cursors[0].codeColumn is cursors[1].codeColumn; } 
		bool opCast(B:bool)() const => valid; 
		
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
		{ return valid ? abs(codeColumn.pos2idx(cursors[0].pos) - codeColumn.pos2idx(cursors[1].pos)) : 0; } //Todo: constness
		
		int opCmp(const TextSelection b) const
		{
			//Todo: *** structured codeColumns: it assumes cursors[0].codeColumn is the same as cursors[1].codeColumn
			return cmpChain(
				/+
					250219: This was evil!!! Sorting by raw pointer.... OMG....
					cmp(
						(cast(size_t)(cast(void*)cursors[0].codeColumn)),
						(cast(size_t)(cast(void*)b.cursors[0].codeColumn))/+***+/
					),
				+/
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
					en=codeColumn.pos2idx(end.pos); //Note: st and en is validated
				
				auto crsr = TextCursor(codeColumn, codeColumn.idx2pos(st)); 
				if(en>st) {
					res.reserve(en-st); 
					//don't care about newlines and Unicode overhead... It's only fast for ASCII
					
					foreach(i; st..en) {
						scope(exit) crsr.moveRight_unsafe; //Todo: refactor all textselection these loops
						
						auto row = codeColumn.rows[crsr.pos.y]; 
						
						if(crsr.pos.x<row.cellCount)
						{
							auto cell = row.subCells[crsr.pos.x]; 
							//Note: this code is redundant, but fast -> .sourceText(cells)
							if(auto g = cast(Glyph)cell)
							{ res ~= g.ch; }
							else if(auto n = cast(CodeNode)cell)
							{
								res ~= n.sourceText; 
								//this can throw exceptions if the node has an invalid content
							}
							else
							{ raise("Fatal error: Source cells must be either Glyph or CodeNode 1"); }
						}
						else
						{
							res ~= DefaultNewLine; //Todo: newLine const
						}
					}
				}
			}
			return res; 
		} 
		
		T[] cells(T:Cell = Cell)()
		{
			//Todo: refactor this to byCells: a bidirectional range
			
			//Note: it returns all nonnull T objects on the root level.
			T[] res; 
			if(valid && cursors[0] != cursors[1])
			{
				const 	st=codeColumn.pos2idx(start.pos),
					en=codeColumn.pos2idx(end.pos); //Note: st and en is validated
				
				auto crsr = TextCursor(codeColumn, codeColumn.idx2pos(st)); 
				if(en>st) {
					res.reserve(en-st); 
					//don't care about newlines and Unicode overhead... It's only fast for ASCII
					
					foreach(i; st..en) {
						scope(exit) crsr.moveRight_unsafe; //Todo: refactor all textselection these loops
						//Todo: refactor this in a functional way. sourceText() and cells() are has the same loop
						auto row = codeColumn.rows[crsr.pos.y]; //Opt: slow lookup of row on every step.
						
						if(crsr.pos.x<row.cellCount)
						{
							//highlighted chars
							if(auto cell = cast(T) row.subCells[crsr.pos.x])
							res ~= cell; 
							
						}
					}
				}
			}
			return res; 
		} 
		
		alias nodes = cells!CodeNode; 
		
		//Todo: byCell
		version(/+$DIDE_REGION+/none) {
			void visitCells()
			{
				if(sel.valid && !sel.isZeroLength)
				{
					const 	st 	= sel.codeColumn.pos2idx(sel.start.pos),
						en 	= sel.codeColumn.pos2idx(sel.end.pos); //Note: st and en is validated
					auto crsr = TextCursor(sel.codeColumn, sel.codeColumn.idx2pos(st)); 
					foreach(i; st..en) {
						auto row = sel.codeColumn.rows[crsr.pos.y]; 
						if(crsr.pos.x<row.cellCount)
						{
							//highlighted chars
							if(auto n = (cast(CodeNode)(row.subCells[crsr.pos.x])))
							cleanupBuildMessagesAndSearchResults(n); 
						}
						crsr.moveRight_unsafe; 
					}
					//Todo: refactor this as sel.byNode
				}
			} 
		}
		
		bool hitTest(vec2 p)
		{
			return false; 
			//Todo: hitTest
		} 
		
		private auto reduce(string what)()
		{
			if(!valid) return typeof(this).init; 
			auto res = this; 
			res.cursors[] = mixin("res."~what); 
			return res; 
		} 
		
		auto reduceToStart()
		=> reduce!"start"; 	 auto reduceToEnd()
		=> reduce!"end"; 	 auto reduceToCaret()
		=> reduce!"caret"; 	 auto reduceToCursor0()
		=> reduce!"cursors[0]"; 	 auto reduceToCursor1()
		=> reduce!"cursors[1]"; 	 
		
		auto toReference()
		=> TextSelectionReference(cursors[0].toReference, cursors[1].toReference, primary);  
		
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
	=> sel.zeroLengthSelectionsToOne(Yes.toLeft); 
	auto zeroLengthSelectionsToOneRight(TextSelection[] sel)
	=> sel.zeroLengthSelectionsToOne(No .toLeft); 
	
	TextSelection useValidCursor(TextSelection ts)
	{
		if(ts.valid) return ts; 
		const i = ts.cursors[0].valid ? 0 : 1; 
		return TextSelection(ts.cursors[i], ts.cursors[i], ts.primary); 
	} 
	
	int distance(TextSelection ts, TextCursor tc)
	{
		//Todo: constness
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
		//Todo: there should be an intersects too: 2 selections can touch but if one is zeroLength is disappears.
		//Todo: constness
		bool chk()
		{
			auto a0 = a.start, a1 = a.end; 
			auto b0 = b.start, b1 = b.end; 
			return 	(a0<=b0 && b0<=a1) ||
				(a0<=b1 && b1<=a1) ||
				(b0<=a0 && a0<=b1) ||
				(b0<=a1 && a1<=b1); 
			//Opt: not so optimal.
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
		auto sorted = input.array.sort;  //Opt: on demand sorting
		
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
			with(sel.cursors[0]) { pos.x = 0; desiredX = 0; }//Note: TextCursor.home is not good: It stops at leadingWhiteSpace
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
	
	struct TextCursorReference
	{
		//TextCursorReference ////////////////////////////////////
		
		//Used to store a TextCursor temporarily. After editing operations these cursors can be converted back to normal cursora.
		//Also used to get a textual absolute path of the cursor location.
		
		CellPath path;       //must end with a codeRow. Starts with a root container.  Normally: root module column row
		Cell left, right;  //(null, null) is valid. -> That is an empty row.
		
		bool valid()
		{
			 //Todo: constness
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
					res.pos.y = row.index; //Opt: slof linear search
					res.pos.x = 0; 
					
					const rightIdx = right ? row.subCellIndex(right) : -1; 
					if(rightIdx>=0)
					{ res.pos.x = rightIdx; }
					else
					{
						const leftIdx = left ? row.subCellIndex(left) : -1; 
						if(leftIdx>=0)
						{
							res.pos.x = leftIdx + 1; //Note: +1 because cursor is to the right
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
	} 
	struct TextSelectionReference
	{
		TextCursorReference[2] cursors; 
		bool primary; 
		
		this(TextCursorReference c0, TextCursorReference c1, bool primary)
		{ cursors[0] = c0; cursors[1] = c1; this.primary = primary; } 
		this(TextSelection ts)
		{ this = ts.toReference; } 
		
		TextSelection fromReference()
		=> TextSelection(
			cursors[0].fromReference, 
			cursors[1].fromReference, primary
		).useValidCursor; 
		
		
		bool valid()
		{
			if(!cursors[0].valid) return false; 
			if(!cursors[1].valid) return false; 
			/+
				Opt: This is the bottleneck. It searches rows linearly insidt columns. 
				Also searches chars inside rows linearly.
			+/
			
			if(cursors[0].path.length	!=	cursors[1].path.length)
			{ return false; /+not in the same depth+/}
			
			if(cursors[0].path[$-2]	!is	cursors[1].path[$-2])
			{ return false; /+not in the same Column+/}
			
			assert(
				equal(cursors[0].path[0..$-1], cursors[1].path[0..$-1]),
				"Cursors should be on the same path."
			); 
			
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
		
		this(string s, Module delegate(File) onFindModule)
		{ this = TextSelection(s, onFindModule).toReference; } 
		
	} 
	
	/// a.b|1|4|5|=>|2|3* -> a.b|1|2|3*
	string reduceTextSelectionReferenceStringToStart(string src)
	{
		/+
			Todo: This nasty text fiddling workaround function could be avoided.
			If the start cursor was stored in the delete/insert operation's 
			undo record, not the whole textSelection. The end cursor of 
			the text selection could be invalid, thus rendering the whole 
			textSelection invalid. But the start cursor is always valid.
		+/
		
		__gshared unittested = false; //Todo: unittest nicely
		if(chkSet(unittested))
		{
			alias f = reduceTextSelectionReferenceStringToStart; 
			enforce(f("a|b|c5*"	)=="a|b|c5*"	); 
			enforce(f("a|b1|c1|=>|b1|e2*"	)=="a|b1|c1*"	); 
			enforce(f("a|b|a0000|=>|a001"	)=="a|b|a0000"	); 
			enforce(f("a|b|a0001|=>|0"	)=="a|b|0"	); 
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
	struct CellPath
	{
		//CellPath ///////////////////////////////
		Cell[] path; //Todo: constness
		alias path this; 
		
		this(Cell act)
		{ path = act.thisAndAllParents.array.retro.array; } 
		
		static private string pathElementToString (Container parent, Cell child)
		{
			if(!parent) return "?NullParent?"; 
			if(!child) return "?NullChild?"; 
			
			if(auto col = (cast(CodeColumn)(child)))
			{
				if(!cast(CodeNode)parent) return "?WrongColumnParent?"; 
				const indexAmongCodeColumns = (mixin(求map(q{a},q{parent.subCells},q{(cast(CodeColumn)(a))}))).filter!"a".countUntil(child); 
				if(indexAmongCodeColumns<0) return "?CantFindColumn?"; 
				return format!"C%d|"(indexAmongCodeColumns); 
			}
			
			if(auto row = (cast(CodeRow)(child)))
			{
				if(!cast(CodeColumn)parent) return "?WrongRowParent?"; 
				const idx = parent.subCellIndex(child); 
				if(idx<0) return "?CantFindRow?"; 
				return idx.format!"R%d|"; 
			}
			
			if(auto mod = (cast(Module)(child)))
			{
				if(!typeid(parent).name.endsWith(".Workspace")) return "?WrongModuleParent?"; 
				return mod.file.fullName ~ "|"; 
			}
			
			if(auto node = (cast(CodeNode)(child)))
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
			//Todo: constness
			if(path.empty) return ""; 
			return byPathElements.map!(a => pathElementToString(a[])).join; 
		} 
		
		static private bool isPathElementValid(Container parent, Cell child)
		{
			return !pathElementToString(parent, child).startsWith('?'); 
			//Opt: not so effective because of strings
		} 
		
		bool valid()
		{
			//Todo: constness
			return 	byPathElements.map!(a => isPathElementValid(a[])).all
				&& cast(CodeRow)path.backOrNull; 
		} 
		
		static private int pathElementToIntex(Container parent, Cell child)
		{ return parent.subCellIndex(child); } 
	} 
}