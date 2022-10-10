module didemodule;

import het, het.ui, het.tokenizer, het.structurescanner ,dideui, buildsys;

//version identifiers: AnimatedCursors
enum MaxAnimatedCursors = 100;

enum rearrangeLOG = false;
enum rearrangeFlash = false;

enum LogModuleLoadPerformance = false;

__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.
__gshared DefaultNewLine = "\r\n"; //this is used for saving source code

const clModuleBorder = clGray;
const clModuleText = clBlack;

// ChangeIndicator ////////////////////////////////////////////

struct ChangeIndicator{ //todo: this is quite similar to CaretPos
	vec2 pos;
	float height;
	ubyte thickness;
	ubyte mask;

	vec2	top   () const{ return pos; }
	vec2	center() const{ return pos + vec2(0, height/2); }
	vec2	bottom() const{ return pos + vec2(0, height); }
	bounds2	bounds() const{ return bounds2(top, bottom); }
}

Appender!(ChangeIndicator[]) globalChangeindicatorsAppender;

void addGlobalChangeIndicator(in vec2 pos, in float height, in int thickness, in int mask){
	globalChangeindicatorsAppender ~= ChangeIndicator(pos, height, cast(ubyte)thickness, cast(ubyte)mask);
}

void addGlobalChangeIndicator(Drawing dr, Container cntr){ with(cntr){
	if(const mask = changedMask){
		enum ofs = vec2(-4, 0);
		if	(cast(CodeRow	)cntr) addGlobalChangeIndicator(dr.inputTransform(outerPos+ofs), outerHeight, 4, mask);
		else if	(cast(CodeColumn	)cntr) addGlobalChangeIndicator(dr.inputTransform(innerPos+ofs), innerHeight, 1, mask);
	}
}}

void draw(Drawing dr, in ChangeIndicator[] arr){
	enum palette = [clBlack, clLime, clRed, clYellow];

	//const clamper = RectClamper(im.getView, 5);

	void drawPass(int pass)(in ChangeIndicator ci){
		static if(pass==1){
			dr.lineWidth = -float(ci.thickness)-1.5f;
			//opted out: dr.color = clBlack;
		}
		static if(pass==2){
			dr.lineWidth = -float(ci.thickness);
			dr.color = palette[ci.mask];
		}

		//if(clamper.overlaps(ci.bounds)){
			dr.vLine(ci.pos, ci.pos.y + ci.height);
		//}else{
		//  dr.vLine(clamper.clamp(ci.center), lod.pixelSize);  //opt: result of claming should be cached...
		//}
	}

	/+ pass 1 +/  dr.color = clBlack;	foreach_reverse(const a; arr) drawPass!1(a);
	/+ pass 2 +/	foreach_reverse(const a; arr) drawPass!2(a);
}


// LOD //////////////////////////////////////////

struct LodStruct {
	float zoomFactor=1, pixelSize=1;
	int level;

	bool codeLevel	   =	true; //level 0
	bool moduleLevel		= false; //level 1/*code text visible*/, 2/*code text invisible*/
}

__gshared const LodStruct lod;

void setLod(float zoomFactor_){
	with(cast(LodStruct*)(&lod)){
		zoomFactor = zoomFactor_;
		pixelSize = 1/zoomFactor;
		level = pixelSize>6 ? 2 :
						pixelSize>2 ? 1 : 0;

		codeLevel = level==0;
		moduleLevel = level>0;
	}
}


// CodeColumn navigation utils ////////////////////////////////////

dchar charAt(const CodeRow cr, int i, bool newLineAtEnd=true){
	if(!cr || i<0 || i>cr.subCells.length) return '\x00';
	if(i==cr.subCells.length) return newLineAtEnd ? '\n' : '\x00';
	const cell = cr.subCells[i];
	if(const g = cast(const Glyph)cell) return g.ch; else return '\x01';
}

dchar charAt(const CodeColumn cc, ivec2 p){
	if(!cc || p.y<0 || p.x<0 || p.y>=cc.rowCount) return '\x00';
	return charAt(cast(const CodeRow)cc.subCells[p.y], p.x, p.y<cc.rowCount-1);
}

dchar charAt(const TextCursor tc){
	return charAt(tc.codeColumn, tc.pos);
}

enum WordCategory{ space, symbol, word }

WordCategory wordCategory(dchar ch){
	import std.uni;
	if(ch.isAlphaNum || ch=='_') return WordCategory.word;
	if(ch.among(' ', '\t', '\n', '\r')) return WordCategory.space;
	return WordCategory.symbol;
}

bool isWordBoundary(R)(R a){
	//input: 2 element historical sliding window of the characters
	//output is true when the wordCategory is decreasing.
	//The 3 possible transitions are: word->symbol, word->space, symbol->space
	return a.front.wordCategory > a.drop(1).front.wordCategory;
}

struct CharFetcher{
	TextCursor cursor;
	bool forward=true;

	@property dchar front() const{ return charAt(cursor); }
	@property bool empty() const{
		if(forward)	return cursor.pos.y>=cursor.codeColumn.lastRowIdx;
		else	return cursor.pos.y<0;
	}

	void popFront(){
		if(forward) cursor.moveRight_unsafe;
					 else cursor.moveLeft_unsafe;
	}

	auto save(){ return this; }
}


// parent stuff: worldPos, parentChain ////////////////////////////

vec2 worldOuterPos(Cell cell){
	if(!cell) return vec2(0);
	if(auto parent = cell.getParent) return worldInnerPos(parent)+cell.outerPos;
	return cell.outerPos;
}

vec2 worldInnerPos(Cell cell){
	if(!cell) return vec2(0);
	return worldOuterPos(cell) + cell.topLeftGapSize;
}

bounds2 worldInnerBounds(Cell cell){
	if(!cell) return bounds2.init;
	auto p = worldInnerPos(cell);
	return bounds2(p, p+cell.innerSize);
}

auto moduleOf(inout Cell c) { return cast(inout)(c ? c.allParents!Module.frontOrNull : null); }

auto moduleOf(TextCursor c){ return c.codeColumn.moduleOf; }
auto moduleOf(TextSelection s){ return s.caret.codeColumn.moduleOf; }

bool isReadOnly(in Cell c){ return c.thisAndAllParents!Module.map!"a.isReadOnly".any; }
bool isReadOnly(in TextCursor c){ return c.codeColumn.isReadOnly; }
bool isReadOnly(in TextSelection s){ return s.caret.codeColumn.isReadOnly; }

struct CellPath{//CellPath ///////////////////////////////
	Cell[] path;     //todo: constness
	alias path this;

	this(Cell act){
		path = act.thisAndAllParents.array.retro.array;
	}

	static private string pathElementToString (Container parent, Cell child) {
		if(!parent) return "?NullParent?";
		if(!child) return "?NullChild?";

		if(auto col = cast(CodeColumn)child){
			if(!cast(CodeNode)parent) return "?WrongColumnParent?";
			assert(cast(CodeNode)parent);  //todo: put these assertions elsewhere
			const indexAmongCodeColumns = parent.subCells.map!(a => cast(CodeColumn)a).filter!"a".countUntil(child);
			if(indexAmongCodeColumns<0) return "?CantFindColumn?";
			return format!"C%d|"(indexAmongCodeColumns);
		}
		if(auto row = cast(CodeRow)child){
			if(!cast(CodeColumn)parent) return "?WrongRowParent?";
			const idx = parent.subCellIndex(child);
			if(idx<0) return "?CantFindRow?";
			return idx.format!"R%d|";
		}
		if(auto mod = cast(Module)child){
			if(!typeid(parent).name.endsWith(".Workspace")) return "?WrongModuleParent?";
			return mod.file.fullName ~ "|";
		}
		if(auto cmt = cast(CodeNode)child){
			if(!cast(CodeRow)parent) return "?WrongNodeParent?";
			const idx = parent.subCellIndex(child);
			if(idx<0) return "?CantFindNode?";
			return format!"N%d|"(idx);
		}

		return "?UnknownChild?";
	}

	auto byPathElements(){
		return path .slide!(No.withPartial)(2)
								.map!(sl => tuple!("parent", "child")(cast(Container)sl[0], sl[1]) );
	}

	string toString(){ //todo: constness
		if(path.empty) return "";
		return byPathElements.map!(a => pathElementToString(a[])).join;
	}

	static private bool isPathElementValid(Container parent, Cell child){
		return !pathElementToString(parent, child).startsWith('?'); //opt: not so effective because of strings
	}

	bool valid(){ //todo: constness
		return byPathElements.map!(a => isPathElementValid(a[])).all
				&& cast(CodeRow)path.backOrNull;
	}

	static private int pathElementToIntex(Container parent, Cell child){
		return parent.subCellIndex(child);
	}
}


bounds2 worldBounds(TextCursor tc){
	if(tc.valid) if(auto row = tc.codeColumn.getRow(tc.pos.y)) with(row.localCaretPos(tc.pos.x)){
		return bounds2(pos, pos+vec2(0, height)) + row.worldInnerPos;
	}

	return bounds2.init;
}

bounds2 worldBounds(TextSelection ts){
	return ts.valid ? worldBounds(ts.cursors[0]) | worldBounds(ts.cursors[1])
									: bounds2.init;
}

bounds2 worldBounds(TextSelection[] ts){  //todo: constness
	return ts.map!worldBounds.fold!"a|b"(bounds2.init);
}

/// A caret's graphical position in world coords
static struct CaretPos{ // CaretPos ///////////////////////////////////
	vec2 pos;
	float height=0;
	bool valid()const{ return height>0; }
	bool opCast(B:bool)() const{ return valid; }

	void draw(Drawing dr){
		if(valid){
			if(dr.alpha<1){ //shrink a bit by alpha
				const shrink = (1-dr.alpha)*height*.33f;
				dr.vLine(pos.x, pos.y+shrink, pos.y+height-shrink);
			}else{
				dr.vLine(pos, pos.y+height);
			}
		}
	}

	vec2	top   () const{ return pos; }
	vec2	center() const{ return pos + vec2(0, height/2); }
	vec2	bottom() const{ return pos + vec2(0, height); }
	bounds2	bounds() const{ return bounds2(top, bottom); }
}


struct TextCursor{  //TextCursor /////////////////////////////
//todo: to be able to edit and preserve the textcursor indices, textcursor should target objects, not indices. [codeRow, cell] would be the minimum. codeRow.subCellIdx(cell) and codeRow.index should be cached.
	CodeColumn codeColumn;

	ivec2 pos;
	float desiredX=0; //used for up down movement, after left right movements.

	version(AnimatedCursors){
		vec2 targetPos	= vec2(float.nan),
				 animatedPos	= vec2(float.nan);
	}

	@property bool valid() const{ return (codeColumn !is null) && pos.x>=0 && pos.y>=0; }

	@property int rowCharCount() const{ //todo: constness
		return codeColumn ? codeColumn.rowCharCount(pos.y) : 0;
	}

	@property bool isAtLineStart() const{ return pos.x<=0; }
	@property bool isAtLineEnd  () const{ return pos.x>=rowCharCount; }

	int opCmp    (in TextCursor b) const{
		//simple case: they are on the same column or both invalid
		if(codeColumn is b.codeColumn || !valid || !b.valid) return cmpChain(cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x));

		//opt: multiColumn selection sorting is extremely slow. Maybe the hierarchical column order should be cached in an integer value.

		//opt: this index searching is fucking slow. But this is the correct way to sort. Maybe it should be cached somehow...
		auto order(in TextCursor c){
			return c.codeColumn .thisAndAllParents!Container
													.array.retro
													.slide!(No.withPartial)(2)
													.map!(a => a[0].subCellIndex(a[1]));
		}

		return cmpChain(cmp(order(this), order(b)), cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x));
	}

	bool opEquals(in TextCursor b) const{ return codeColumn is b.codeColumn && pos == b.pos; }

	void moveRight_unsafe(){
		pos.x++;
		if(pos.x>codeColumn.rowCharCount(pos.y)){
			pos.x=0;
			pos.y++;
		}
	}

	void moveLeft_unsafe(){
		pos.x--;
		if(pos.x<0){
			pos.y--;
			pos.x=codeColumn.rowCharCount(pos.y);
		}
	}

	void moveLeft(long delta){ moveRight(-delta); }
	void moveRight(long delta){ moveRight(delta.to!int); }

	//special delta units
	enum home	= int.min,	 end	= int.max,
			 wordLeft	= home+1 ,	 wordRight	= end-1  ;

	void calcDesiredX_unsafe(){
		desiredX = pos.x<=0 ? 0 : codeColumn.rows[pos.y].subCells[pos.x-1].outerBounds.right;
	}

	void calcDesiredX_safe(){
		if(!codeColumn || pos.x<=0){
			desiredX = 0;
		}else{
			if(auto row = codeColumn.getRow(pos.y)){
				if(row.cellCount==0){
					desiredX = 0;
				}else{
					desiredX = row.subCells[pos.x-1].outerBounds.right;
				}
			}else{
				desiredX = 0;
			}
		}
	}

	void moveRight(int delta){
		if(!delta) return;
		if(delta==home){
			const ltc = codeColumn.rows[pos.y].leadingTabCount; //unsafe
			pos.x = pos.x>ltc ? ltc : 0; //first stop is right after leading tabs, then goes to 0
		}else if(delta==end){
			pos.x = codeColumn.rows[pos.y].cellCount; //unsafe
		}else if(delta==wordRight){
			const skip = CharFetcher(this, true)
									.chain("\n\n"d) //extra stopping condition when no word boundary found
									.slide(2)
									.countUntil!(a => a.isWordBoundary || a.equal("\n\n"d)); //only stop at empty lines (that's 2 newline)
			moveRight(skip+1);
		}else if(delta==wordLeft){
			const skip = CharFetcher(this, false)
									.drop(1) //ignore the char at right hand side of the cursor
									.chain("\n\n"d) //extra stopping condition when no word boundary found
									.slide(2)
									.countUntil!(a => a.isWordBoundary || a.drop(1).front=='\n'); //stop at every newline
			moveLeft(skip+1);
		}else{
			//opt: cache idx2pos and pos2idx. The line searcher is slow in those
			pos = codeColumn.idx2pos(codeColumn.pos2idx(pos)+delta); //note: this must be a clamped move
		}
		calcDesiredX_unsafe;
	}

	void moveDown(int delta){
		if(!delta) return;
		if(delta==home) pos.y = 0; //home
		else if(delta==end) pos.y = codeColumn.rowCount-1; //end
		else pos.y = (pos.y+delta).clamp(0, codeColumn.rowCount-1);

		//jump to desired x in actual row
		auto r = codeColumn.rows[pos.y];
		pos.x = iota(r.cellCount+1).map!(i => abs((i<=0 ? 0 : r.subCells[i-1].outerBounds.right)-desiredX)).minIndex.to!int;
	}

	void move(ivec2 delta){
		if(!delta) return;

		if(!delta.x){ //handle clipping in the y direction.  Generate home/end
			if(delta.y<0 && pos.y<=0) delta = ivec2(home);
			if(delta.y>0 && pos.y>=codeColumn.rowCount-1) delta = ivec2(end);
		}

		if(delta==ivec2(home)){
			pos = ivec2(0); desiredX = 0; //this needed to skip the possible stop right after the leading tabs in the first line
		}else{
			moveDown (delta.y);
			moveRight(delta.x);
		}
	}

	CaretPos localPos(bool world = false)(){ //local to the codeColumn
		CaretPos res;
		if(valid) if(auto row = codeColumn.getRow(pos.y)){
			res = row.localCaretPos(pos.x);
			if(res.valid){
				static if(world) res.pos += worldInnerPos(row);
										else res.pos += row.innerPos;
			}
		}
		return res;
	}

	auto worldPos(){
		return localPos!true;
	}

	auto toReference() const{
		TextCursorReference res;
		if(valid) if(auto row = (cast()codeColumn).getRow(pos.y)){  //todo: fix constness!!
			res.path = CellPath(row);
			res.left	= row.subCells.get(pos.x-1);
			res.right	= row.subCells.get(pos.x);
		}
		return res;
	}

}


/// Used to store a TextCursor temporarily. After editing operations these cursors can be converted back to normal cursora.
/// Also used to get a textual absolute path of the cursor location.
struct TextCursorReference{ // TextCursorReference ////////////////////////////////////
	CellPath path;       //must end with a codeRow. Starts with a root container.  Normally: root module column row
	Cell left, right;  //(null, null) is valid. -> That is an empty row.

	bool valid(){ //todo: constness
		if(!path.valid) return false;

		auto parent = cast(CodeRow)path.back;
		if(!parent) return false;

		return parent.subCells.empty || //this means that the row was empty and the caret is at the beginning of the row.
					 left	&& parent.subCellIndex(left )>=0 ||
					 right	&& parent.subCellIndex(right)>=0;
	}

	string toString(){
		if(!valid) return "";
		auto res = path.toString;

		//this special processing is for the caret. Decide the idx from the left and right cells.
		if(!left && !right) res ~= "X0";
		else{
			auto parent = cast(CodeRow)path.back;
			if(!parent) return "";

			const leftIdx	= left	? parent.subCellIndex(left ) : -1;
			const rightIdx	= right	? parent.subCellIndex(right) : -1;

			auto idx = -1;
			if     (rightIdx>=0) idx = rightIdx; //select one valid
			else if(leftIdx >=0) idx = leftIdx+1; //add 1, because it's on the left side of the caret!

			if(idx>=0)	res ~= format!"X%d"(idx);
			else	return ""; //it's lost
		}

		return res;
	}

	TextCursor fromReference(){
		TextCursor res;

		if(valid) if(auto col = cast(CodeColumn)path[$-2]) if(auto row = cast(CodeRow)path[$-1]){
			if(row.parent is col){
				res.codeColumn = col;
				res.pos.y = row.index; //opt: slof linear search
				res.pos.x = 0;
	
				const rightIdx = right ? row.subCellIndex(right) : -1;
				if(rightIdx>=0){
					res.pos.x = rightIdx;
				}else{
					const leftIdx = left ? row.subCellIndex(left) : -1;
					if(leftIdx>=0){
						res.pos.x = leftIdx + 1; //note: +1 because cursor is to the right
					}
				}

				res.desiredX = row.localCaretPos(res.pos.x).pos.x;
			}else assert(0, "row.parent !is col");
		}

		return res.valid ? res : TextCursor.init;
	}

	/// Used when a delete operation joins 2 tows and the second row is deleted.
	void replaceLatestRow(CodeRow old, CodeRow new_){
		if(path.length && path.back is old)
			path.back = new_;
	}

}

struct TextSelection{ //TextSelection ///////////////////////////////
	TextCursor[2] cursors;
	bool primary;

	this(TextCursor c0	, TextCursor c1 ,	bool primary){ cursors[0] = c0	; cursors[1] = c1	; this.primary = primary; }
	this(TextCursor c	,	bool primary){ cursors[0] = c	; cursors[1] = c	; this.primary = primary; }

	ref caret(){ return cursors[1]; }
	ref const caret(){ return cursors[1]; }

	auto codeColumn(){ return cursors[0].codeColumn; }

	@property bool valid() const{ return cursors[].map!"a.valid".all && cursors[0].codeColumn is cursors[1].codeColumn; }
	bool opCast(B:bool)() const{ return valid; }

	@property auto start() const{ return min(cursors[0], cursors[1]); }
	@property auto end  () const{ return max(cursors[0], cursors[1]); }

	@property bool isZeroLength() const{ return cursors[0]==cursors[1]; }
	@property bool isSingleLine() const{ return cursors[0].pos.y==cursors[1].pos.y; }
	@property bool isMultiLine() const{ return !isSingleLine; }

	@property bool isAtLineStart() const{ return start.isAtLineStart; }
	@property bool isAtLineEnd  () const{ return end  .isAtLineEnd  ; }

	@property int calcLength() { return valid ? abs(codeColumn.pos2idx(cursors[0].pos) - codeColumn.pos2idx(cursors[1].pos)) : 0; } //todo: constness

	int opCmp(const TextSelection b) const{
		return cmpChain(cmp(cast(size_t)(cast(void*)cursors[0].codeColumn), cast(size_t)(cast(void*)b.cursors[0].codeColumn)), //todo: structured codeColumns: it assumes cursors[0].codeColumn is the same as cursors[1].codeColumn
										cmp(start, b.start),
										cmp(end, b.end),
										cmp(caret, b.caret));
	}

	bool opEquals(const TextSelection b) const{
		return cursors[0].codeColumn is b.cursors[0].codeColumn
				&& start==b.start
				&& end==b.end
				&& caret==b.caret;
	}

	void move(ivec2 delta, bool isShift){
		if(!delta) return;

		if(!isShift && cursors[0]!=cursors[1]){
			caret = delta.y.cmpChain(delta.x)<0 ? start : end; //collapse selection if it is a non-shift move

			static void restrict(ref int x, int y){
				if(!y && x){
					if(x.among(TextCursor.wordLeft, TextCursor.wordRight, TextCursor.home, TextCursor.end)) x = 0; //wordLeft/wordRight/home/end stops at the end of the selection
					else x -= sign(x);
				}
			}

			with(delta){
				restrict(x, y);
				restrict(y, x);
			}
		}
		caret.move(delta);
		if(!isShift) cursors[0] = caret;
	}

	string sourceText(){
		string res;
		if(valid && cursors[0] != cursors[1]){
			const st=codeColumn.pos2idx(start.pos),
						en=codeColumn.pos2idx(end  .pos); //note: st and en is validated

			auto crsr = TextCursor(codeColumn, codeColumn.idx2pos(st));
			if(en>st){
				res.reserve(en-st); //don't care about newlines and unicode overhead...
				foreach(i; st..en){ scope(exit) crsr.moveRight_unsafe; //todo: refactor all textselection these loops
					auto row = codeColumn.rows[crsr.pos.y];

					if(crsr.pos.x<row.cellCount){//highlighted chars
						auto cell = row.subCells[crsr.pos.x];
						if(auto g = cast(Glyph)cell){
							res ~= g.ch;
						}else if(auto n = cast(CodeNode)cell){
							res ~= n.sourceText;
						}else{
							raise("NOT IMPL"); //todo: structured editor
						}
					}else{
						res ~= DefaultNewLine; // todo: newLine const
					}
				}
			}
		}
		return res;
	}

	bool hitTest(vec2 p){
		return false;
		//todo: hitTest
	}

	private auto reduce(string what)(){
		if(!valid) return typeof(this).init;
		auto res = this;
		res.cursors[] = mixin("res."~what);
		return res;
	}

	auto reduceToStart	 (){ return reduce!"start"; }
	auto reduceToEnd	 (){ return reduce!"end"; }
	auto reduceToCaret	 (){ return reduce!"caret"; }
	auto reduceToCursor0(){ return reduce!"cursors[0]"; }
	auto reduceToCursor1(){ return reduce!"cursors[1]"; }

	auto toReference(){
		return TextSelectionReference(cursors[0].toReference, cursors[1].toReference, primary);
	}

	this(string s, Module delegate(File) onFindModule){
		try{
			s = s.strip;
			if(s!=""){

				if(s.endsWith(TextSelectionReference.primaryMark)){
					primary = true;
					s = s.withoutEnding(TextSelectionReference.primaryMark);
				}

				Container parent;
				CodeColumn codeColumn;

				void step(Cell c){
					c.enforce;
					parent = c.to!Container;
				}

				int cidx = 0;
				ivec2[2] pos;
				foreach(partIdx, part; s.split('|')){
					if(!partIdx){
						step(onFindModule(File(part)));
					}else if(part.startsWith('C')){
						const idx = part[1..$].to!uint;
						step(parent.subCells.map!(a => cast(CodeColumn)a).filter!"a".drop(idx).frontOrNull); //Parent is CodeNode. Only search amongst its child CodeColumns.
					}else if(part.startsWith('R')){
						const idx = part[1..$].to!uint;
						codeColumn = enforce(cast(CodeColumn)parent);
						step(parent.subCells.drop(idx).frontOrNull);
						pos[cidx].y = idx;
					}else if(part.startsWith('N')){
						const idx = part[1..$].to!uint;
						step(parent.subCells.drop(idx).frontOrNull);
						pos[cidx].x = idx;
					}else if(part.startsWith('X')){
						const idx = part[1..$].to!uint;
						enforce(cast(CodeRow)parent && idx>=0 && idx<=parent.cellCount); //special caret range checking
						pos[cidx].x = idx;
						parent = null; //the end of the cursor. It can restart after "=>".
					}else if(part=="=>"){
						enforce(cidx==0 && !parent);
						cidx++;
						parent = codeColumn;
					}else enforce(0);
				}

				enforce(cidx.among(0, 1) && codeColumn);
				if(cidx==0) pos[1] = pos[0];
				foreach(i; 0..2){
					cursors[i] = TextCursor(codeColumn, pos[i]);
					cursors[i].calcDesiredX_unsafe;
				}

				enforce(valid); //just a light test
			}
		}catch(Exception e){
			this = typeof(this).init;
		}
	}

}

int distance(TextSelection ts, TextCursor tc){ //todo: constness
	if(ts.valid && tc.valid && ts.codeColumn is tc.codeColumn){
		auto cc = tc.codeColumn, st = ts.start, en = ts.end;
		if(tc<st) return cc.pos2idx(st.pos) - cc.pos2idx(tc.pos);
		if(tc>en) return cc.pos2idx(tc.pos) - cc.pos2idx(en.pos);
		return 0; //it's inside
	}else{
		return int.max;
	}
}

bool touches(TextSelection a, TextSelection b){	  //todo: there should be an intersects too: 2 selections can touch but if one is zeroLength is disappears.
	  //todo: constness
	bool chk(){
		auto a0 = a.start, a1 = a.end;
		auto b0 = b.start, b1 = b.end;
		return (a0<=b0 && b0<=a1)
				|| (a0<=b1 && b1<=a1)
				|| (b0<=a0 && a0<=b1)
				|| (b0<=a1 && a1<=b1); //opt: not so optimal.
	}

	return a.valid && b.valid && a.codeColumn is b.codeColumn && chk;
}

TextSelection merge(TextSelection a, TextSelection b){
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
	foreach(a; sorted){
		if(res.length && touches(a, res.back)){
			res.back = merge(a, res.back);
		}else{
			res ~= a;
		}
	}

	return res;
}

auto extendToFullRow(TextSelection sel){
	if(sel.valid){
		with(sel.cursors[0]){ pos.x = 0; desiredX = 0; } //note: TextCursor.home is not good: It stops at leadingWhiteSpace
		with(sel.cursors[1]){
			moveRight(TextCursor.end);
			moveRight(1); //goes to start of next line
		}
	}
	return sel;
}

auto extendToWordsOrSpaces(TextSelection sel){
	if(sel.valid){

		void adjust(ref TextCursor c, int dir){
			const dchar[] neighbors = CharFetcher(c, false).drop(1).take(1).array ~ CharFetcher(c, true).take(1).array;
			if(neighbors.length<2) return; //it's at the end

			static bool isSpace(dchar ch){ return ch.among(' ', '\t')>0; } //Only space and tab counts here.
			static bool isWord (dchar ch){ return wordCategory(ch)==WordCategory.word; }

			auto lookingForWords = neighbors.any!isWord;
			auto lookingForSpaces = neighbors.all!isSpace; //2 spaces -> lookingForSpace

			if(lookingForWords || lookingForSpaces){
				const cnt = CharFetcher(c, dir>0)
										.drop(dir<0 ? 1 : 0)
										.countUntil!(ch => lookingForWords	? !isWord(ch)
																		 : lookingForSpaces	? !isSpace(ch)
																		 : true);
				if(cnt>0)
					c.moveRight(dir*cnt);
			}
		}

		const stIdx = sel.cursors[0]<=sel.cursors[1] ? 0 : 1;
		adjust(sel.cursors[  stIdx], -1);
		adjust(sel.cursors[1-stIdx],  1);
	}
	return sel;
}

auto zeroLengthSelectionsToFullRows(TextSelection[] sel){
	auto fullRows = sel .filter!"a.valid && a.isZeroLength"
											.map!extendToFullRow.array;

	return merge(sel ~ fullRows);
}

auto zeroLengthSelectionsToOne(TextSelection[] sel, Flag!"toLeft" toLeft){
	const dir = toLeft ? -1 : 1;

	auto a = sel.dup;
	a.each!((ref s){
		if(s.valid && s.isZeroLength)
			s.move(ivec2(dir, 0), true);
	});

	return merge(a);
}

auto zeroLengthSelectionsToOneLeft (TextSelection[] sel){ return sel.zeroLengthSelectionsToOne(Yes.toLeft); }
auto zeroLengthSelectionsToOneRight(TextSelection[] sel){ return sel.zeroLengthSelectionsToOne(No .toLeft); }


/// input newLine is '\n'
/// it only adds newLine when the last item doesn't have one at its end
/// replaces all '\n' to specidied newLine
string sourceTextJoin(R)(R r, string newLine)
{
	string[] a = r.array;

	foreach(i; 0..a.length.to!int-1){
		const n0 = a[i  ].endsWith  (newLine),
					n1 = a[i+1].startsWith(newLine);
		if(n0 && n1){
			a[i] = a[i][0..$-newLine.length]; //remove a newLine when there are 2
		}else if(!n0 && !n1){  //add a newLine when there are 0
			a[i] ~= newLine;
		}
	}

	return a.join;
}


string sourceText(TextSelection[] ts){
	return ts
		.filter!"a.valid && !a.isZeroLength"
		.map!"a.sourceText"
		.sourceTextJoin(DefaultNewLine);
}

bool hitTest(TextSelection[] ts, vec2 p){
	return ts.map!(a => a.hitTest(p)).any; //todo: this should be in the draw routine with automatic mouse hittest
}

TextSelection useValidCursor(TextSelection ts){
	if(ts.valid) return ts;
	const i = ts.cursors[0].valid ? 0 : 1;
	return TextSelection(ts.cursors[i], ts.cursors[i], ts.primary);
}

void animate(ref TextSelection sel, ){
	version(AnimatedCursors){

	}
}


struct TextSelectionReference{ // TextSelectionReference //////////////////////////////
	TextCursorReference[2] cursors;
	bool primary;

	this(TextCursorReference c0, TextCursorReference c1, bool primary){ cursors[0] = c0; cursors[1] = c1; this.primary = primary; }
	this(TextSelection ts){ this = ts.toReference; }

	TextSelection fromReference(){
		return TextSelection(cursors[0].fromReference, cursors[1].fromReference, primary).useValidCursor;
	}

	bool valid(){
		if(!cursors[0].valid) return false;  //opt: this is the bottleneck. It searches rows linearly insidt columns. Also searches chars inside rows linearly.
		if(!cursors[1].valid) return false;

		if(cursors[0].path.length	!=	cursors[1].path.length) return false; //not in the same depth
		if(cursors[0].path[$-2]	!is	cursors[1].path[$-2]  ) return false; //not in the same Column

		assert(equal(cursors[0].path[0..$-1], cursors[1].path[0..$-1])); //check the whole path

		return true;
	}

	void replaceLatestRow(CodeRow old, CodeRow new_){
		foreach(ref c; cursors) c.replaceLatestRow(old, new_);
	}

	private enum primaryMark = "*";

	string toString(){
		if(!valid) return "";

		auto s0 = cursors[0].toString, s1 = cursors[1].toString;

		auto primaryStr = primary ? primaryMark : "";

		if(s0==s1) return s0 ~ primaryStr;
					else return s0~"|=>|"~s1.split('|')[$-2..$].join('|') ~ primaryStr;
	}

	this(string s, Module delegate(File) onFindModule){
		this = TextSelection(s, onFindModule).toReference;
	}

}

/// a.b|1|4|5|=>|2|3* -> a.b|1|2|3*
string reduceTextSelectionReferenceStringToStart(string src){
	//todo: This nasty text fiddling workaround function could be avoided if the start cursor was stored in the delete/insert operation's undo record, not the whole textSelection. The end cursor of the text selection could be invalid, thus rendering the whole textSelection invalid. But the start cursor is always valid.

	__gshared unittested = false; //todo: unittest nicely
	if(chkSet(unittested)){
		alias f = reduceTextSelectionReferenceStringToStart;
		enforce(f("a|b|c5*"	)=="a|b|c5*"	 );
		enforce(f("a|b1|c1|=>|b1|e2*"	)=="a|b1|c1*"	 );
		enforce(f("a|b|a0000|=>|a001"	)=="a|b|a0000"	 );
		enforce(f("a|b|a0001|=>|0"	)=="a|b|0"	 );
	}

	int toNum(string s){
		if(s.empty) return -1;
		return (s.front.isDigit ? s : s[1..$]).to!int.ifThrown(-1);
	}

	const isPrimary = src.endsWith('*');
	if(isPrimary) src = src[0..$-1];

	auto parts = src.split('|');

	if(auto fs = parts.findSplit(only("=>"))){
		const trailLen = fs[2].length;
		if(fs[0].length>=trailLen){
			if(cmp(fs[0][$-trailLen..$].map!toNum, fs[2].map!toNum)<0) parts = fs[0];
																														else parts = fs[0][0..$-trailLen] ~ fs[2];
		}
	}

	auto res = parts.join('|');

	if(isPrimary) res ~= "*";
	return res;
}

/// CodeRow ////////////////////////////////////////////////

class CodeRow: Row{
	CodeColumn parent;

	static if(rearrangeFlash) DateTime rearrangeTime;

	override inout(Container) getParent() inout { return parent; }
	override void setParent(Container p){ parent = enforce(cast(CodeColumn)p); }

	int index(){ return parent.subCellIndex(this); }

	auto glyphs()	{ return subCells.map!(c => cast(Glyph)c); } //can return nulls
	auto chars()	{ return glyphs.map!"a ? a.ch : '\u26A0'"; }
	string sourceText() { return chars.to!string; }

	//todo: mode isSpace inside elastic tab detection, it's way too specialized

	private static bool isSpace(Glyph g){ return g && g.ch==' ' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; } //this is for leadingTab detection
	private static bool isTab  (Glyph g){ return g && g.ch=='\t' /+any syntax counts for tabs +/; }
	private auto isSpaces() { return glyphs.map!(g => isSpace(g)); }
	private auto leadingSpaces(){ return glyphs.until!(g => !isSpace(g)); }
	private auto leadingTabs  (){ return glyphs.until!(g => !isTab(g)  ); }

	//these are needed for calcWhitespaceStats
	private static bool isCodeSpace	(Glyph g){ return g && g.ch==' ' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; }
	private static bool isCodeTab	(Glyph g){ return g && g.ch=='\t' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; }
	private auto leadingCodeSpaces	(){ return glyphs.until!(g => !isCodeSpace(g)); }
	private auto leadingCodeTabs	(){ return glyphs.until!(g => !isCodeTab(g)  ); }

	//this is for visualization
	private auto leadingWhitespaces(){ return glyphs.until!(g => !(g && g.ch.among(' ', '\t'))); }
	int leadingWhitespaceCount() { return cast(int)leadingWhitespaces.walkLength; }

	int leadingTabCount() { return cast(int)leadingTabs.walkLength; }

	this(CodeColumn parent_){
		parent = enforce(parent_);
		id.value = this.identityStr;

		needMeasure;  //also	sets measureOnlyOnce flag. This is an on-demand realigned Container.
		flags.wordWrap	= false;
		flags.clipSubCells	= true;
		flags.cullSubCells	= true;
		flags.rowElasticTabs	= false;
		flags.dontHideSpaces	= true;
		bkColor = clCodeBackground;
	}

	this(CodeColumn parent_, string line, ubyte[] syntax){
		assert(line.length==syntax.length);
		this(parent_);
		set(line, syntax);
	}

	this(CodeColumn parent_, string line){
		this(parent_);
		set(line, [ubyte(0)].replicate(line.length));
	}

	void set(string line, ubyte[] syntax){
		internal_setSubCells([]);

		static TextStyle style; //it is needed by appendCode/applySyntax
		this.appendCode(line, syntax, (ubyte s){ applySyntax(style, s); }, style/+, must paste tabs!!! DefaultIndentSize+/);

		//tabIdx if refreshed by appendCode
		refresh;
	}

	/// Returns inserted count
	int insertSomething(int at, void delegate() appendFun){
		enforce(at>=0 && at<=subCells.length, "Out of bounds");

		auto after = subCells[at..$];
		subCells = subCells[0..at];

		const cnt0 = subCells.length;

		appendFun();

		const insertedCnt = (subCells.length-cnt0).to!int;
		if(insertedCnt) setChangedCreated;

		subCells ~= after;

		refreshTabIdx;
		refresh;

		return insertedCnt;
	}

	/// Returns inserted count
	int insertText(int at, string str){
		if(str.empty) return 0;
		return insertSomething(at, {
			static TextStyle style; //it is needed by appendCode/applySyntax
			auto syntax = [ubyte(0)].replicate(str.length);
			this.appendCode(str, syntax, (ubyte s){ applySyntax(style, s); }, style/+, must paste tabs!!! DefaultIndentSize+/);
		});
	}

	/// Splits row into 2 rows. Returns the newli created row which is NOT yet inserted to the column.
	CodeRow splitRow(int x){
		assert(x>=0 && x<=cellCount);

		auto nextRow = new CodeRow(parent);
		nextRow.setChangedCreated;

		nextRow.subCells = this.subCells[x..$];
		nextRow.adoptSubCells;
		this.subCells = this.subCells[0..x];

		if(nextRow.subCells.length)
			this.setChangedRemoved;

		only(this, nextRow).each!"a.refreshTabIdx";
		only(this, nextRow).each!"a.refresh";

		return nextRow;
	}

	///must be called after the code changed. It tracks elasticTabs, and realigns if needed
	void refresh(){
		if(needMeasure){

			//extend up and down along elastic tabs
			auto i = index; //opt: this index calculation is slow. Feed index from the inside
			assert(i>=0);

			//simple but unefficient criteria: has any tabs or not
			foreach(a; parent.rows[0..i].retro.until!"!a.tabIdxInternal.length") if(!a.needMeasure) break;
			foreach(a; parent.rows[i+1..$]    .until!"!a.tabIdxInternal.length") if(!a.needMeasure) break;
		}
	}

	override void rearrange(){

		assert(verifyTabIdx, "tabIdxInternal check fail");

		adjustCharWidths;

		innerSize = vec2(0); flags.autoWidth = true; flags.autoHeight = true;

		super.rearrange;

		innerSize = max(innerSize, DefaultFontEmptyEditorSize);

		static if(rearrangeLOG) LOG("rearranging", this);

		static if(rearrangeFlash) rearrangeTime = now;

		//opt: Row.flexSum <- ezt opcionalisan ki kell kiiktatni, lassu.
	}

	protected{
		static immutable float NormalSpaceWidth	= 7.25f, //same as '0'..'9' and +-_
													 LeadingSpaceWidth	= NormalSpaceWidth;

		void adjustCharWidths(){

			bool isLeading = true;
			foreach(g; glyphs) if(g){
				if(isSpace(g)){
					g.outerWidth = isLeading ? LeadingSpaceWidth
																	 : NormalSpaceWidth;
				}else{
					isLeading = false;

					//non-leading char width modifications
					if(g.syntax==5 && g.ch!='.'	//number except '.'
					|| g.ch.among('+', '-', '_')	//symbols next to numbers
					/* || g.syntax==6/+string+/*/) g.outerWidth = NormalSpaceWidth;
				}
			}else{
				isLeading = false;
			}

			//foreach(g; glyphs) g.outerWidth = NormalSpaceWidth; //monospace everything
		}

		private void spaceToTab(long i){
			auto g = glyphs[i];
			assert(isSpace(glyphs[i]));
			g.ch = '\t';
			g.isTab = true;
			//note: refreshTabIdx must be called later
		}

		void replaceSpacesWithTabs(int xStart, int xTab, size_t tabCount){
			assert(xStart<=xTab	, "invalid xStart, xTab");
			assert(xStart>=0	, "xStart out of range");
			assert(xTab<subCells.length	, "xTab out of range");
			assert(glyphs[xStart..xTab+1].all!(g => isSpace(g))	, "All must be spaces");
			assert(tabCount <= xTab-xStart+1	, "tabCount too much.");

			auto normalizeLeadingSpaces(Cell[] sc){
				(cast(Glyph[])sc) .until!(a => !(isSpace(a) && a.outerWidth!=NormalSpaceWidth))
					.each!(a => a.outerWidth = NormalSpaceWidth);
				return sc;
			}

			internal_setSubCells(subCells[0..xStart+tabCount] ~ (xTab+1<subCells.length ? normalizeLeadingSpaces(subCells[xTab+1..$]) : []));
			foreach(i; xStart..xStart+tabCount) spaceToTab(i); //promote spaces to tabs

			refreshTabIdx; //todo: should only be done once at the end...
		}

		void convertLeadingSpacesToTabs(int spaceCnt){
			//todo: tab inside string literal. width is too big  File(`c:\D\libs\!shit\_unused.arsd\html.d`)

			assert(spaceCnt>0);
			const tabCnt = (cast(int)leadingSpaces.walkLength)/spaceCnt;
			if(tabCnt>0){
				const removeCnt = tabCnt*spaceCnt-tabCnt;
				internal_setSubCells(subCells[removeCnt..$]);
				foreach(i; 0..tabCnt) spaceToTab(i);
				refreshTabIdx; //todo: should only be done once at the end...
			}
		}

	}//protected

	CaretPos localCaretPos(int idx){
		const len = cellCount;
		if(len==0) return CaretPos(vec2(0, 0), innerHeight);

		idx = idx.clamp(0, len);
		//if(idx<0 || idx>len) return CaretPos.init;

		if(idx==len) with(subCells.back) return CaretPos(outerTopRight, outerHeight);
		if(idx==0) with(subCells[0]) return CaretPos(outerPos, outerHeight);

		const y0 = min(subCells[idx-1].outerTop   , subCells[idx].outerTop   ),
					y1 = max(subCells[idx-1].outerBottom, subCells[idx].outerBottom);

		return CaretPos(vec2(subCells[idx].outerLeft, y0), y1-y0);
	}

	override void draw(Drawing dr){ //draw ////////////////////////////////
		if(lod.level>1 && im.actTargetSurface==0){ //note: LOD is only enabled on the world view, not on the UI

			if(subCells.length){
				const lwsCnt = leadingWhitespaceCount; //opt: this should be memoized
				if(lwsCnt<subCells.length){
					auto cell = subCells[lwsCnt];
					const r = bounds2(cell.outerPos, subCells.back.outerBottomRight) + innerPos;

					//decide row's average color. For simplicity choose the first char's color
					if(auto glyph = cast(Glyph)cell){
						dr.color = avg(glyph.bkColor, glyph.fontColor);
					}else if(auto node = cast(CodeNode)cell){
						dr.color = clGray; //todo: get colod of codeNode
					}else{
						assert(0, "Invalid class in CodeRow");
					}

					dr.fillRect(r.inflated(vec2(0, -r.height/4)));
				}

				//todo: Draw bigger subNodes.
			}

		}else{
			super.draw(dr);

			//visualize tabs ---------------------------------------

			//opt: these calculations operqations should be cached. Seems not that slow however
			//todo: only display this when there is an editor cursor active in the codeColumn (or in the module)
			dr.translate(innerPos); dr.alpha = .4f;
			scope(exit){ dr.pop; dr.alpha = 1; }
			dr.color = clGray;

			if(tabIdxInternal.length){
				dr.lineWidth = .5f;
				foreach(ti; tabIdxInternal){	             assert(ti.inRange(subCells));
					auto g = cast(Glyph)subCells.get(ti);	             assert(g, "tabIdxInternal fail");
					if(g){
						dr.vLine(g.outerRight-2, g.outerTop+2, g.outerBottom-2);
						//const y = g.outerPos.y + g.outerHeight*.5f;
						//dr.vLine(g.outerRight, y-2, y+2);
						//dr.hLine(g.outerLeft+1, y, g.outerRight-1);
					}
				}
			}

			//visualize spaces ------------------------------
			dr.pointSize = 1;
			foreach(g; glyphs.filter!(a => a && a.ch==' ')){       assert(g);
				dr.point(g.outerBounds.center); //todo: don't highlight single spaces only if there is a tab or character or end of line next to them.
			}
		}

		//visualize changed/created/modified
		addGlobalChangeIndicator(dr, this/*, vec2(padding.left, innerHeight)*.5f*/);

		static if(rearrangeFlash) if(now-rearrangeTime < 1*second){
			dr.color = clGold;
			dr.alpha = (1-(now-rearrangeTime).value(second)).sqr*.5f;
			dr.fillRect(outerBounds);
			dr.alpha = 1;
		}
	}

	bounds2 newLineBounds(){
		const p = newLinePos;
		return bounds2(p, p + DefaultFontNewLineSize);
	}

	vec2 newLinePos(){
		assert(innerHeight>=DefaultFontHeight);
		return vec2(cellCount ? subCells.back.outerRight : 0, (innerHeight-DefaultFontHeight)*.5f);
	}

}


enum TextFormat{
	plainText,		// unstructured text
	plainD,	    //	unstructured D source
	declarations,	    // {	D declarations	         ; }	       // before ':' there can be attributes or staticif: version: debug:
	statements,	    // { D	statements	         ; }	       // before	':' there can be labels or case: default: conditions
	structInitializer,		// { field initializers	         , }		// before ':' there can be field identifiers
	stringLiteral,	    //	''w  ""w  ``w  r""w  q""w  q{}
	comment,		// //\n	/**/  /+/++/+/
	list,	    //	( , )
	forList,		// ( , ; )
	index	    //	[ , ]
}

// ErrorList ////////////////////////////////////////////

auto createErrorListCodeColumn(Container parent){
	auto code = new CodeColumn(parent);
	code.padding = "1";
	code.flags.dontStretchSubCells = true;

	import dide2; //todo: should not import main module.
	auto buildResult = global_getBuildResult;
	auto markerLayerHideMask = global_getMarkerLayerHideMask;

	foreach(file; buildResult.remainings.keys.sort){
		auto pragmas = buildResult.remainings[file];
		if(pragmas.length) code.append({ UI_CompilerOutput(file, pragmas.join('\n')); });
	}

	with(im) code.append({
		foreach(loc; buildResult.messages.keys.sort){
			auto msg = buildResult.messages[loc];
			if(msg.parentLocation) continue;
			if((1<<msg.type) & markerLayerHideMask) continue;
			msg.UI(buildResult.subMessagesOf(msg.location));
		}
	});

	return code;
}

//auto createErrorListModule(Container parent){
//  auto Module = new Module()
//}


struct CodeContext{

	enum CharSize: ubyte { default_, c, w, d }
	
	enum Type: ubyte	{
		plain		, // Simple text without any structure of highlight
		highlighted	, // syntax highlighted text without structure
		structured	, // structured and syntax highlighted code
		slashComment	, // simple comment text, no newLine allowed
		cComment	, // no `*/` allowed
		dComment	, // `/+` starts a new block, `+/` not	allowed
		cChar	, // ' C character literal with escapes	// all strings has extra parameter: charChoding: default(==char, but not written), char, word, dword
		cString	, // " C string literal with escapes
		dString	, // ` D string wysiwyg string
		rString	, // r" D string wysiwyg string
		qString_brace	, // q"( D delimited string
		qString_square	, // q"[ D delimited string
		qString_curly	, // q"{	D delimited string
		qString_angle	, // q"<	D delimited string
		qString_slash	, // q"/	D delimited string
		qString_id	, // q"id	// needs external parameter for the id
		tString	, // q{   tokenString    same as highlightedText // needs external parameter for language.
	}

	Type type;
	CharSize charSize;
	string delimitedStringId;
	
	@property bool isComment	() const{ with(CodeContext.Type) return type.inRange(slashComment	, dComment	); }
	@property bool isString	() const{ with(CodeContext.Type) return type.inRange(cChar	, tString	); }
	
	string prefix() const{
		with(Type) return type.predSwitch(
			cChar	, `'`,
			cString	, `"`,
			dString	, "`",
			rString	, `r"`,
			qString_brace	, `q"(`,
			qString_square 	, `q"[`,
			qString_curly	, `q"{`,
			qString_angle	, `q"<`,
			qString_slash	, `q"/`,
			qString_id	, `q"`~delimitedStringId~DefaultNewLine,
			tString	, `q{`,
			slashComment	, `//`,
			cComment	, `/*`,
			dComment	, `/+`,
				""
		);
	}
	
	string postfix() const{
		
		string cwd(){ 
			with(CharSize) return charSize==default_ ? "" : charSize.text;
		}
		
		with(Type) return isString ? type.predSwitch(
			cChar	, `'`,
			cString	, `"`,
			dString	, "`",
			rString	, `r"`,
			qString_brace	, `)"`,
			qString_square 	, `]"`,
			qString_curly	, `}"`,
			qString_angle	, `>"`,
			qString_slash	, `/"`,
			qString_id	, DefaultNewLine~delimitedStringId~`"`,
			tString	, `}`
		)~cwd : type.predSwitch(
			slashComment	, DefaultNewLine,
			cComment	, `*/`,
			dComment	, `+/`,
			""
		);
	}
}

static struct CodeColumnBuilder(bool rebuild){ //CodeColumnBuilder /////////////////////////////////////////
	CodeColumn col;
	bool changed;
	TextStyle tsWhitespace, ts;
	SyntaxKind _currentSk=skWhitespace, syntax=skWhitespace;
			
	CodeRow actRow;
	bool skipNextN; //after \r, skip the next \n
	
	void NL(){ 
		col.appendCell(actRow = new CodeRow(col, "", null)); 
	}
	
	void appendChar(dchar ch){ 
		static if(rebuild){
			switch(ch){
				case '\n', '\r', '\u2028', '\u2029':
					if(skipNextN.chkClear && ch=='\n') break;
					skipNextN = ch=='\r';
					NL;
				break;
				default: 
					if(_currentSk.chkSet(syntax))
						applySyntax(ts, syntax);
					actRow.appendSyntaxChar(ch, ts, syntax); 
			}
		}else{
			static assert(0, "Resyntax mode NOTIMPL");
		}
	}

	void appendStr(string str){
		foreach(ch; str) appendChar(ch);
	}
	
	void appendPlain(string sourceText){
		syntax = skIdentifier1; //no skWhiteSpace handling either.
		appendStr(sourceText);
	}
	
	private void appendHighlighted_internal(string sourceText){
		static char categorize(dchar ch){ 
			if(isAlphaNum(ch) || ch.among('_', '#', '@')) return 'a';
			if(ch.among(' ', '\t', '\x0b', '\x0c')) return ' ';
			return '+';
		}
		foreach(s; sourceText.splitWhen!((a, b) => categorize(a) != categorize(b)).map!text){
			switch(s[0]){
				case ' ', '\t', '\x0b', '\x0c': syntax = skWhitespace; break;
				case '0': ..case '9': syntax = skNumber; break;
				case '#': syntax = skDirective; break;
				case '@': syntax = skLabel; break;
				default: 
					if(s[0].isAlpha || s[0]=='_'){ 
						if(auto kw = kwLookup(s)){
							with(KeywordCat) switch(kwCatOf(kw)){
								case Attribute	: syntax = skAttribute	; break;
								case Value	: syntax = skBasicType	; break;
								case BasicType	: syntax = skBasicType	; break;
								case UserDefiniedType 	: syntax = skKeyword	; break;
								case SpecialFunct	: syntax = skAttribute	; break;
								case SpecialKeyword	: syntax = skKeyword	; break;
								default	: syntax = skKeyword	; break;
							}
						}else syntax = skIdentifier1;
					}else if(s[0].isSymbol || s[0].isPunctuation) syntax = skSymbol; 
					else syntax = skIdentifier1;
			}
			
			appendStr(s);
		}
		
		syntax = skIdentifier1;
	}
	
	void appendHighlighted(string sourceText){ 
		auto scanner = sourceText.DLangScanner;
		auto syntaxStack = [syntax];
		while(!scanner.empty){ 
			auto sr = scanner.front;
			scanner.popFront;
			
			bool useSimpleHighlighter;
			switch(sr.op){
				case ScanOp.push:
					syntaxStack ~= syntax;
					switch(sr.src){
						case "//", "/*", "/+"	: syntax = skComment	; appendStr(sr.src);		break;
						case "{", "(", "["	: syntax = skSymbol	; appendStr(sr.src);	 syntax = skWhitespace; 	break;
						case `q{`	: syntax = skString	; appendStr(sr.src);	 syntax = skWhitespace;	break;
						case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`	: syntax = skString	; appendStr(sr.src);		break;
						default	: syntax = skError	; appendStr(sr.src);		break;
						//todo: identifier quoted string `q"id`
					}
				break;
				case ScanOp.pop:
					if(syntaxStack.empty){
						syntax = skError;
						appendStr(sr.src);
					}else{ 
						if(!syntax.among(skComment, skString)) syntax = skSymbol;
						appendStr(sr.src);
						
						syntax = syntaxStack.back;
						syntaxStack.length--;
						//todo: error checking for compatible closing tags. Maybe it can be implemented in the scanner too.
					}
				break;
				//case ScanOp.trans: setSyntax(skError); 	break;
				case ScanOp.content: 
					if(!syntax.among(skComment, skString)){
						appendHighlighted_internal(sr.src);
					}else{
						appendStr(sr.src);
					}
					break;
				default: syntax = skError; appendStr(sr.src); break;
			}
		}
	}
	
	this(CodeColumn col){
		this. col = col;
		
		tsWhitespace 	= tsNormal	; applySyntax(tsWhitespace	, skWhitespace	);
		ts 	= tsWhitespace	; applySyntax(ts	, _currentSk	);
		
		static if(rebuild){
			col.clearSubCells;
			NL; //there must be 1 row always. Empty column is a single empty row.
			changed = true;
		}else{
			static assert(0, "Resyntax mode NOTIMPL");
		}
	}
	
	~this(){
		if(changed) col.needMeasure;
	}
}

class CodeColumn: Column{ // CodeColumn ////////////////////////////////////////////
	//note: this is basically the CodeBlock
	Container parent;

	//CodeContext context;
	enum defaultSpacesPerTab = 4; //default in std library
	int spacesPerTab = defaultSpacesPerTab; //autodetected on load

	deprecated("In the end, multithreaded resyntax wont require this.") DateTime lastResyntaxTime; //needed for the multithreaded syntax highligh processing. It can detect if the delayed syntax highlight is up-to-date or not.

	/// Minimal constructor creating an empty codeColumn with 0 rows.
	deprecated("Only needed for compile.err builder") this(Container parent){
		this.parent = parent;
		id.value = this.identityStr;  //id is not used anymore for this

		needMeasure;  //also sets measureOnlyOnce flag. This is an on-demand realigned Container.
		flags.wordWrap	= false;
		flags.clipSubCells	= true;
		flags.cullSubCells	= true;
		flags.columnElasticTabs = true;

		this.setRoundBorder(8);
		margin = "0.5";
		padding = "0.5 4";
		bkColor = clCodeBackground;
	}

	/// This is the normal constructor. This should be the only one.
	this(Container parent, string sourceText){
		this(parent);
		setSourceText(sourceText);
	}

	auto calcWhitespaceStats(){
		import het.tokenizer : WhitespaceStats;
		WhitespaceStats whitespaceStats;
		foreach(r; rows){ //todo: optimize it somehow... Statistically...
			if(!r.leadingCodeTabs.empty){
				whitespaceStats.tabCnt++;
			}else{
				auto spaceCnt = cast(int)r.leadingCodeSpaces.walkLength;
				whitespaceStats.addSpaceCnt(spaceCnt);
			}
		}
		//note: this is just lame statistics to detect the size of a tab only for converting spaces to tabs.
		return whitespaceStats;
	}
	
	auto rebuilder(){ return CodeColumnBuilder!true(this); }

	void setSourceText(string sourceText){
		/+ old version with SourceCode class
		src.foreachLine( (int idx, string line, ubyte[] syntax) => appendCell(new CodeRow(this, line, syntax)) );
		if(subCells.empty)
			appendCell(new CodeRow(this, "", null)); //always must have at least an empty row+/

		
		const len = sourceText.length, t0 = now; scope(exit) LOG(len, len/(now-t0).value(second)/(1<<20), "MB/s");
		
		//rebuilder.appendPlain(sourceText);
		rebuilder.appendHighlighted(sourceText);
		
		convertSpacesToTabs;
		
	}

	void convertSpacesToTabs(){
		createElasticTabs;
		spacesPerTab = calcWhitespaceStats.detectIndentSize(DefaultIndentSize); //opt: this can be slow. Maybe put it on a keyboard shortcut.
		rows.each!(row => row.convertLeadingSpacesToTabs(spacesPerTab));
		needMeasure;
	}

	void resyntax(SourceCode src){
		//note: IT IS ILLEGAL TO MODIFY the contents in this. Only change to font color and flags are valid.
		
		//todo: resyntax: Problem with the Column Width detection when the longest line is syntax highlighted using bold fonts.
		//todo: resyntax: Space and hex digit sizes are not adjusted after resyntax.
		
		assert(subCells.length>0);
		
		static TextStyle style; //it is needed by appendCode/applySyntax
		
		src.foreachLine( (int idx, string line, ubyte[] syntax){
			if(idx<subCells.length){
				auto row = rows[idx];
				bool wasWidthChange;
				if(row.updateSyntax(line, syntax, (ubyte s){ applySyntax(style, s); }, style, wasWidthChange/+, must paste tabs!!! DefaultIndentSize+/)){
					if(wasWidthChange){
						row.needMeasure;
					}
				}else{
					return false;
				}
			}else{
				return false;
			}
			return true;
		});
	
	}

	override inout(Container) getParent() inout { return parent; }
	override void setParent(Container p){ parent = p; }

	auto const rows(){ return cast(CodeRow[])subCells; }
	int rowCount() const{ return cast(int)subCells.length; }
	int lastRowIdx() const{ return rowCount-1; }
	int lastRowLength() const{ return rows.back.cellCount; }

	auto getRow(int rowIdx){ return rowIdx.inRange(subCells) ? rows[rowIdx] : null; }

	int rowCharCount(int rowIdx) const{	//todo: it's ugly because of the constness. Make it nicer.
		if(rowIdx.inRange(subCells)) return	cast(int)((cast(CodeRow)subCells[rowIdx]).subCells.length);
		return 0;
	}

	string rowSourceText(int rowIdx){
		if(auto row = getRow(rowIdx)) return row.sourceText;
		return "";
	}

	TextCursor homeCursor(){ return TextCursor(this, ivec2(0)); }
	TextCursor endCursor(){ auto res = homeCursor; res.move(ivec2(TextCursor.end, TextCursor.end)); return res; }
	TextSelection allSelection(bool primary){ return TextSelection(homeCursor, endCursor, primary); }

	TextSelection lineSelection(bool selectWholeLine)(int line, bool primary){
		auto y = line-1;
		if(y.inRange(rows)){
			auto ts = TextSelection(TextCursor(this, ivec2(0, y)), primary);
			if(selectWholeLine) ts.cursors[1].move(ivec2(TextCursor.end, 0));
			return ts;
		}
		return TextSelection.init;
	}

	TextSelection lineSelection_home(int line, bool primary){ return lineSelection!false(line, primary); }

	TextSelection cellSelection(int line, int column, bool primary){
		auto ts = lineSelection_home(line, primary);
		if(ts){
			auto dx = (column-1).clamp(0, rowCharCount(ts.cursors[0].pos.y));
			if(dx) ts.move(ivec2(dx, 0), false);
		}
		return ts;
	}


	@property string sourceText() { return rows.map!(r => r.sourceText).join(DefaultNewLine); }  // \r\n is the default in std library

	//index, location calculations
	int maxIdx() const{ //inclusive end position
		assert(rowCount>0);
		return rows.map!(r => r.cellCount + 1/+newLine+/).sum - 1/+except last newLine+/;
	}

	ivec2 idx2pos(int idx) const{
		if(idx<0) return ivec2(0); //clamp to min

		const rowCount = this.rowCount;
		assert(rowCount>0, "One row must present even when the CodeColumn is empty.");
		int y;
		while(1){
			const actRowLen = rows[y].cellCount+1;
			if(idx<actRowLen){
				return ivec2(idx, y);
			}else{
				y++;
				if(y<rowCount){
					idx -= actRowLen;
				}else{
					return ivec2(rows[rowCount-1].cellCount, rowCount-1); //clamp to max
				}
			}
		}
	}

	int pos2idx(ivec2 p) const{
		if(p.y<0) return 0; //clamp to min
		if(p.y>=rowCount) return maxIdx; //lamp to max
		return rows[0..p.y].map!(r => r.cellCount+1).sum + clamp(p.x, 0, rows[p.y].cellCount);
	}


	override void rearrange(){
		//ote: Can't cast to CodeRow because "compiler.err" has Rows. Also CodeNode is a Row.
		auto rows = cast(Row[])subCells;
		assert(rows.map!(a => cast(Row)a).all);

		if(rows.empty){
			innerSize = DefaultFontEmptyEditorSize;
		}else{
			//measure and spread rows vertically rows
			float y=0, maxW=0;
			const totalGap = rows.front.totalGapSize; //note: assume all rows have the same margin, padding, border settings
			foreach(r; rows){
				r.measure;
				r.outerPos = vec2(0, y);
				y += r.innerHeight+totalGap.y;
			}

			processElasticTabs(cast(Cell[])rows); //opt: apply this to a subset that has been remeasured

			const maxInnerWidth = rows.map!"a.contentInnerWidth".maxElement;
			innerSize = vec2(maxInnerWidth + totalGap.x, y);
			//todo: this is not possible with the immediate UI because the autoWidth/autoHeigh information is lost. And there is no functions to return the required content size. The container should have a current size, a minimal required size and separate autoWidth flags.

			if(!flags.dontStretchSubCells)
				foreach(r; rows) r.innerWidth = maxInnerWidth;
		}

		static if(rearrangeLOG) LOG("rearranging", this);
	}

	void createElasticTabs(){
		//const t0=QPS; scope(exit) print(QPS-t0);

		bool detectTab(int x, int y){
			if(cast(uint)y >= rowCount) return false;
			with(rows[y]){
				if(cast(uint)x >= cellCount) return false;
				return isSpaces[x] && (x+1 >= cellCount || !isSpaces[x+1]);
			}
		}

		bool[long] visited;

		static struct TabInfo{ int y, xStart, xTab; }
		TabInfo[] newTabs;

		void flood(int x, int y, bool canGoUp, bool canGoDown, lazy size_t leadingSpaceCount){
			if(!canGoDown && !canGoUp) return;

			//assume: x, y is a valid tab position
			if(visited.get(x+(long(y)<<32))) return;

			int y0 = y;	 if(canGoUp  ) while(y0 > 0	&& detectTab(x, y0-1)) y0--;
			int y1 = y;	 if(canGoDown) while(y1 < rowCount-1	&& detectTab(x, y1+1)) y1++;

			int maxLen = 0, minLen = int.max;
			if(y0<y1) foreach(yy; y0..y1+1) with(rows[yy]) {
				visited[x+(long(yy)<<32)] = true;

				int x0 = x; while(x0 > 0 && isSpaces[x0-1]) x0--;
				int x1 = x;

				int len = x1-x0+1;
				maxLen.maximize(len);
				minLen.minimize(len);
			}

			if(maxLen>1){

				int xStartMin = 0;
				if(!canGoUp) xStartMin = leadingSpaceCount.to!int; //ez egy behuzas. Nem mehet balrabb a tab, mint a legfelso sor indent-je.
				//if(xStartMin>0) "------------------".print;

				foreach(yy; y0..y1+1) with(rows[yy]) {
					int xStart	= x; while(xStart > xStartMin && isSpaces[xStart-1]) xStart--;
					int xTab	= x+1-minLen;

					newTabs ~= TabInfo(yy, xStart, xTab);

					//if(xStartMin>0) print(lines[yy].text, "         ", newTabs.back);
				}
			}
		}

		//scan through all the rows and initiate floodFills
		foreach(y, row; rows) with(row){
			int st = 0;
			foreach(isSpace, len; isSpaces.group){
				const en = st + cast(int)len;

				if(isSpace && st>0){
					bool canGoUp, canGoDown;

					if(len==1 && st>0 && chars[st-1].among('[', '('))	canGoDown = true; //todo: the tabs below this one should inherit the indent of this first line
					else	canGoUp = canGoDown = canGoDown = len>=2;
					
					/+const leftChar = st>0 ? chars[st-1] : '\0';
					const rightChar = en+1<len ? chars[en+1] : '\0';
					if(!(leftChar.isSymbol || rightChar.isSymbol)) canGoUp = canGoDown = false;+/
					
					flood(en-1, cast(int)y, canGoUp, canGoDown, leadingSpaces.walkLength);
				}

				st = en;
			}
		}

		//replace spaces with tabs
		auto sortedTabs = newTabs.sort!((a, b) => cmpChain(cmp(a.y, b.y), cmp(b.xTab, a.xTab))<0); //x is descending!!

		int idx; foreach(const tabInfo; sortedTabs) with(rows[tabInfo.y]){

			//tabs on the previous line will split this tab if it is long enough
			auto tabsOnPrevLine = sortedTabs[0..idx] .retro
																							 .until !(t => t.y< tabInfo.y-1)
																							 .filter!(t => t.y==tabInfo.y-1);
			auto splitThisTabAt = tabsOnPrevLine.map!"a.xTab".filter!(a => a.inRange(tabInfo.xStart, tabInfo.xTab-1));
			const tabCount = 1 + splitThisTabAt.walkLength;
			//print("act", tabInfo, "splitAt", splitAt, "extra tabs", splitAt.walkLength);
			replaceSpacesWithTabs(tabInfo.xStart, tabInfo.xTab, tabCount);

			idx++;
		}

	}

	override void draw(Drawing dr){ // draw ///////////////////////////////////
		super.draw(dr);

		//visualize changed/created/modified
		addGlobalChangeIndicator(dr, this/*, topLeftGapSize*.5f*/);
	}

}

void test_CodeColumn(){

	void test_RowCount(string src, int rowCount, string dst="*"){
		if(dst=="*") dst = src;
		auto cc = scoped!CodeColumn(null, src);
		void expect(T, U)(T a, U b){ if(a!=b) ERR("Test fail: "~[src, rowCount.text, dst].text~" : "~a.text~" != "~b.text); }
		expect(cc.rows.length, rowCount);
		expect(cast(ubyte[])dst, cast(ubyte[])(cc.rows.map!(r => r.sourceText).join('\n')));
	}

	test_RowCount("", 1);
	test_RowCount(" ", 1);
	test_RowCount("\n", 2);
	test_RowCount("\n ", 2, "\n ".replace(" ", "\t")); //todo: a tabokat visszaalakitani space-ra. Csak a leading comment/whitespace-re menjen, az elastic tabokat meg egymas ala kell igazitani space-ekkel. De ezt majd kesobb. Most minden tab lesz.
	test_RowCount("\r\n", 2, "\n");
	test_RowCount(" \n \n \r\n", 4, " \n \n \n".replace(" ", "\t")); //todo: a tabokat visszaalakitani space-ra
	test_RowCount(" \n \n \r\n ", 4, " \n \n \n ".replace(" ", "\t")); //todo: a tabokat visszaalakitani space-ra
}

/// Label //////////////////////////////////////////

enum LabelType{ folder, module_, mainRegion, subRegion }

class Label : Row{
	Cell reference;
	bool alignRight;
	
	this(LabelType labelType, vec2 pos, string str, Cell reference=null){
		this.reference = reference;
		
		auto ts = tsNormal;
		ts.fontColor = clWhite;
		ts.bkColor = clBlack;
		ts.transparent = true;

		with(LabelType){
			const isRegion = labelType.among(mainRegion, subRegion)!=0;
			ts.fontHeight = isRegion ? 180 : 255;
			ts.bold = false && labelType != subRegion;
			alignRight = isRegion;
		}

		with(flags){
			noHitTest = true;
			dontSearch = true;
			dontLocate = true;
			noBackground = true;
		}

		outerPos = pos;

		//icon
		Img icon;
		if(labelType==LabelType.module_) icon = new Img(File(`icon:\`~File(str).ext.lc));
		else if(labelType==LabelType.folder) icon = new Img(File(`icon:\folder\`));

		if(icon){
			icon.innerSize = vec2(ts.fontHeight);
			icon.transparent = true;
			appendCell(icon);
		}

		//text
		appendStr(str, ts);
		measure;
	}
	
	void reposition(){
		if(reference){
			outerX = alignRight ? reference.outerWidth-this.outerWidth : 0;
			outerY = reference.outerY;
		}
	}
}

// FolderLabel //////////////////////////////////

auto cachedFolderLabel(string folderPath){
	return ImStorage!Label.access(srcId(genericId(folderPath)), new Label(LabelType.folder, vec2(0), Path(folderPath).name));
}

// CodeNode //////////////////////////////////////////
class CodeNode : Row{
	Container parent;

	auto subColumns(){ return subCells.map!(a => cast(CodeColumn)a).filter!"a"; }

	this(Container parent){
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

	~this(){
		parent = null;
	}
	
	@property abstract string sourceText();
	

	override inout(Container) getParent() inout { return parent; }
	override void setParent(Container p){ parent = p; }

	override void rearrange(){
		innerSize = vec2(0);
		flags.autoWidth = true;
		flags.autoHeight = true;
		super.rearrange;
		static if(rearrangeLOG) LOG("rearranging", this);
	}

	override void draw(Drawing dr){
		super.draw(dr);

		//visualize changed/created/modified
		addGlobalChangeIndicator(dr, this/*, topLeftGapSize*.5f*/);
	}

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

string encodePrevAndNextSourceText(string prev, string act){  //todo: ezt kiprobalni jsonnal is, hogy van-e egyaltalan ennek a manualis cuccnak valami ertelme
	return prev.length.to!string~"\\"~prev~act;
}

string[2] decodePrevAndNextSourceText(string s){
	auto a = s.splitter("\\");
	if(!a.empty) try{
		auto snum = a.front;
		const prevLen = snum.to!size_t;
		s = s[snum.length+1..$];
		if(prevLen<=s.length) return [s[0..prevLen], s[prevLen..$]];
	}catch(Exception){ }
	return typeof(return).init;
}

struct TextModificationRecord{ string where, what; }

struct TextModification{
	bool isInsert;
	TextModificationRecord[] modifications; //Must preserve order!!!!
}

struct UndoManager{
	//bug: UndoManager is sticking to a module. If the module is renamed, I don't know what happens...
	//opt: Loaded event is wasting a lot of memory. It should use differential text coding. And zip.
	//todo: also store the textSelections in the undoevents

	private uint lastUndoGroupId;

	enum EventType { loaded, saved, modified }

	class Event{
		DateTime id; //unique ID
		EventType type;
		TextModification[] modifications;
		Event[] items;

		Event parent;

		this(Event parent, DateTime id, EventType type, bool isInsert, string where, string what){
			this.parent = parent;
			this.id = id;
			this.type = type;
			modifications ~= TextModification(isInsert, [TextModificationRecord(where, what)]);
		}

		override int opCmp(in Object b) const { auto bb = cast(Event)b;  return cmp(id, bb ? bb.id : DateTime.init); }

		string summaryText(string insMark = "(+)", string delMark = "(-)", string moreMark="...", bool isQuoted=true)(int maxStrLen = 20) const{
			final switch(type){
				case EventType.loaded: return "Loaded";
				case EventType.saved : return "Saved";
				case EventType.modified:{
					string res;
					int actStrLen, actMode; // 1:ins, -1:del
					foreach(const m; modifications){
						const nextMode = m.isInsert ? 1 : -1;
						if(actMode.chkSet(nextMode)){
							const s = actMode>0 ? insMark : delMark;
							res ~= s;
							//no, because it could be a markup symbol: actStrLen += cast(int)s.walkLength;
						}

						//todo: detect backspace (text selections are going backwards, and reverse order)
						foreach(mr; m.modifications) foreach(ch; mr.what){
							if(ch<32){
								static if(isQuoted){
									const s = ch.text.quoted[1..$-1];
									res ~= s;
									actStrLen += s.length.to!int;

									//compact \r\n into \n
									if(res.endsWith(`\r\n`)){
										res = res[0..$-4]~`\n`;
										actStrLen -= 2;
									}
								}else{
									res ~= ('\u2400'+ch); //visual control chars
									actStrLen += 1;
								}
							}else{
								res ~= ch; actStrLen++;
							}

							if(actStrLen>=maxStrLen) return res ~ moreMark;
						}
					}
					return res;
				}
			}
		}

		override string toString() const{ return format!"UndoEvent(%s, %s, items:%d)"(id, summaryText, items.length); }

		Container createUI(Event actEvent){
			static bool tsInitialized;
			static TextStyle tsEvent;
			if(tsInitialized.chkSet){
				tsEvent = tsNormal; //opt: save this
			}

			auto outer = new Row;

			Row inner; with(inner = new Row){
				padding = "2";
				margin = "4";
				border = "1 normal black";

				auto ts = tsEvent;
				inner.appendMarkupLine(this.id.text~"\n"~summaryText!(tag("style fontColor=green"), tag("style fontColor=red"), tag("style fontColor=black")~"\u2026", false), ts);
			}

			Row innerWithArrow; with(innerWithArrow = new Row){
				appendCell(inner);
				innerWithArrow.appendStr(this is actEvent ?  "\U0001F846" : "\u2b95", tsEvent); //arrow
			}
			inner = innerWithArrow;

			outer.appendCell(inner);

			if(items.length==1){
				outer.appendCell(items[0].createUI(actEvent)); //recursive
			}else if(items.length>1){
				auto col = new Column;
				outer.appendCell(col);

				foreach(item; items)
					col.appendCell(item.createUI(actEvent)); //recursive
			}

			return outer;
		}

	}

	Event[DateTime] allEvents;

	private DateTime latestId; //used for unique id generation

	Event actEvent, rootEvent;

	protected bool executing; //when executing, disable the recording of events.

	Event oldestEvent(){ return allEvents.byValue.minElement(null); }
	Event newestEvent(){ return allEvents.byValue.maxElement(null); }

	bool hasAnyModifications() const{ return allEvents.byValue.any!(e => e.type == EventType.modified); }

	void justLoaded	(File file, string contents) { addEvent(0, EventType.loaded		, file.fullName, contents, false); }  //todo: fileName, fileContents for history
	void justSaved	(File file, string contents) { addEvent(0, EventType.saved	  ,	file.fullName, ""      , false); }
	void justInserted	(uint undoGroupId, string where, string what)	 { addEvent(undoGroupId, EventType.modified , where, what, true ); }
	void justRemoved	(uint undoGroupId, string where, string what)	 { addEvent(undoGroupId, EventType.modified , where, what, false); }

	void addEvent(uint undoGroupId, EventType type, string where, string what, bool isInsert){
		if(executing) return;

		//append latest event in the same group
		const extendLastGroup = type==EventType.modified
													&& actEvent && actEvent.type==EventType.modified
													&& actEvent.modifications.length
													&& lastUndoGroupId==undoGroupId;
		if(extendLastGroup){
			assert(actEvent.modifications.back.isInsert==isInsert);
			actEvent.modifications.back.modifications ~= TextModificationRecord(where, what);
		}else{
			lastUndoGroupId = undoGroupId;

			latestId.actualize; //a new unique Id. This garantees that all child is newer than the parent. Takes 150ns to get the precise system time.

			//fusion of modification.
			const fusion =	type == EventType.modified
									 &&	actEvent
									 &&	actEvent.type == EventType.modified
									 &&	latestId-actEvent.id < .75*second;
			if(fusion){
				actEvent.id = latestId;
				actEvent.modifications ~= TextModification(isInsert, [TextModificationRecord(where, what)]);
			}else{
				if(!actEvent) assert(allEvents.empty);
				auto e = new Event(actEvent, latestId, type, isInsert, where, what);
				allEvents[e.id] = e;
				if(actEvent) actEvent.items ~= e;
				actEvent = e; //this is the new act
				if(!rootEvent) rootEvent = e;
			}
		}
	}

	bool canUndo(){
		return actEvent && actEvent !is rootEvent; //rootEvent must be a Load event. That can't be cancelled.
	}

	void undo(void delegate(in TextModification) execute, void delegate(string where, string what) reload){
		assert(!executing);

		if(!canUndo) return;

		executing = true; scope(exit) executing = false;

		bool again;
		do{
			again = false;
			final switch(actEvent.type){
				case EventType.modified: actEvent.modifications.retro.each!execute; break;
				case EventType.saved: again = true; break; //nothing happened, "save event" is it's just a marking for the user
				case EventType.loaded: reload(actEvent.modifications[0].modifications[0].where, actEvent.modifications[0].modifications[0].what.decodePrevAndNextSourceText[0]);  break; //todo: ugly and needs range checking
			}
			actEvent = actEvent.parent;
		}while(again && canUndo);
	}

	bool canRedo(){
		return actEvent && actEvent.items.length;
	}

	void redo(void delegate(in TextModification) execute, void delegate(string where, string what) reload){
		if(!canRedo) return;

		executing = true; scope(exit) executing = false;

		bool again;
		do{
			actEvent = actEvent.items.back; //choose different path optionally

			again = false;
			final switch(actEvent.type){
				case EventType.modified: actEvent.modifications.each!execute; break; //it's in reverse text selection order.
				case EventType.saved: again = true; break; //nothing happened, "save event" is it's just a marking for the user
				case EventType.loaded: reload(actEvent.modifications[0].modifications[0].where, actEvent.modifications[0].modifications[0].what.decodePrevAndNextSourceText[1]); break; //todo: ugly and needs range check
			}
		}while(again && canRedo);

	}

	Container createUI(){
		return rootEvent ? rootEvent.createUI(actEvent) : null;
	}
}

/// Module ///////////////////////////////////////////////
interface WorkspaceInterface{
	@property bool isReadOnly();
}

class Module : CodeNode{ //this is any file in the project
	File file;

	DateTime fileLoaded, fileModified, fileSaved; //opt: detect these times from the outside
	size_t sizeBytes;  //todo: update this form the outside

	//these are the 2 subcells
	CodeColumn code;

	ModuleBuildState buildState;
	bool isCompiling;

	bool isMainExe, isMainDll, isMainLib, isMain, isStdModule, isFileReadOnly;

	UndoManager undoManager;
	
	bool isStructured;

	this(Container parent, File file_){
		bkColor = clModuleBorder;
		super(parent);

		flags.clipSubCells = false; //to show labels

		fileLoaded = now;

		file = file_.actualFile;
		//id = "Module:"~this.file.fullName;

		reload;
	}

	override string sourceText(){
		return code ? code.sourceText : "";
	}

	///It must return the actual logic. Files can be temporarily readonly while being compiled for example.
	bool isReadOnly(){
		//return inputs["ScrollLockState"].active;
		return isCompiling || isFileReadOnly || isStdModule || (cast(WorkspaceInterface)parent).isReadOnly;
	}

	void resetModuleTypeFlags(){
		isMain = isMainExe = isMainDll = isMainLib = isStdModule = isFileReadOnly = false;
	}

	void detectModuleTypeFlags(){
		bool isMainSomething(string ext)(){
			return code && code.getRow(0) && sameText(code.getRow(0).sourceText.stripRight, "//@"~ext);
		}
		isMainExe = isMainSomething!"exe";
		isMainDll = isMainSomething!"dll";
		isMainLib = isMainSomething!"lib";
		isMain = isMainExe || isMainDll || isMainLib;

		isStdModule = file.fullName.isWild(`c:\d\ldc2\import\*`); //todo: detect compiler import path correctly
		isFileReadOnly = isStdModule || file.isReadOnly || file.name.sameText("compile.err"); //todo: periodically chenck if file is exists and other attributes in the IDE
	}

	void resyntax(){
		auto txt = code.sourceText;
		auto src = scoped!SourceCode(txt);

		resyntax_src(src);
	}

	//call it with a freshly parsed SourceCode object
	void resyntax_src(SourceCode src){  //todo: this should go into the column somehow: only codeColumn will have the resyntax/needResyntax functionality and those columns with a Module parent will notify thir own parent after they have the SourceCode parsed.
		code.resyntax(src);
	}

	void reload(Flag!"useExternalContents" useExternalContents = No.useExternalContents, string externalContents=""){
		clearSubCells;

		fileModified = file.modified;
		sizeBytes = file.size;
		resetModuleTypeFlags;

		T0;
		auto prevSourceText = sourceText;
		string sourceText = useExternalContents	? externalContents
			: this.file.readText;
		
		undoManager.justLoaded(this.file, encodePrevAndNextSourceText(prevSourceText, sourceText));
		
		if(isStructured){
			try{
				code = buildStructuredCodeColumn(this, sourceText);
			}catch(Exception e){
				WARN("buildStructuredCodeColumn() failed: "~e.simpleMsg);
				code = buildUnstructuredCodeColumn(this, sourceText);
			}
		}else{
			code = buildUnstructuredCodeColumn(this, sourceText);
		}
		
		static if(LogModuleLoadPerformance) LOG(DT, file);

		appendCell(enforce(code));

		needMeasure;
	}

	size_t linesOfCode(){ return code.subCells.length; } //todo: update this. only good for unstructured code.

	override void rearrange(){
		detectModuleTypeFlags;
		code.measure;
		innerSize = code.outerSize.max(code.outerSize, DefaultFontEmptyEditorSize);
	}

	override void draw(Drawing dr){
		super.draw(dr);
	}

	void save(){
		if(isReadOnly) return;
		sourceText.saveTo(file, Yes.onlyIfChanged);
		clearChanged;
		fileModified = file.modified; //opt: slow
		fileSaved = now;
	}

}


deprecated class ErrorListModule : Module{  // ErrorListModule ////////////////////////////////////////////////////////
	this(Container parent, File file_){
		super(parent, file_);
	}

	override bool isReadOnly(){ return true; }

	override void resyntax(){ }
	override void resyntax_src(SourceCode src){ }

	override void reload(Flag!"useExternalContents" useExternalContents = No.useExternalContents, string contents=""){
		clearSubCells;
		fileModified = now;
		sizeBytes = 0; //todo: note this has no file.
		resetModuleTypeFlags;
		code = createErrorListCodeColumn(this);
		appendCell(enforce(code));
		needMeasure;
	}
}


/+class CodeComment : CodeNode{ // CodeComment //////////////////////////////////////////
	CodeColumn contents;

	this(CodeRow parent){
		super(parent);

		//flags.yAlign = YAlign.top;

//    auto ts = tsSyntax(SyntaxKind.Comment);
		auto ts = tsSyntax(SyntaxKind.Symbol);

		const darkColor	= ts.bkColor,
					brightColor	= ts.fontColor,
					halfColor	= avg(darkColor, brightColor);

		bkColor = halfColor;
		border.color = bkColor;

		ts.fontColor = darkColor;
		ts.bkColor = halfColor;
		ts.bold = true;
//    appendStr("//"~smallSpace, ts);
		appendStr("if", ts);

		contents = new CodeColumn(this, "1+1//This is a test comment");
		contents.bkColor = darkColor;

		subCells ~= contents;

		appendStr("\nthen\t", ts);

		contents = new CodeColumn(this, "//This is a test comment");
		contents.bkColor = darkColor;

		subCells ~= contents;

		appendStr("\nelse\t", ts);

		contents = new CodeColumn(this, "//This is a test comment");
		contents.bkColor = darkColor;

		subCells ~= contents;

		needMeasure;
	}

	override string sourceText(){
		NOTIMPL;
		return "";
	}

	override void rearrange(){
		{
			const c = tsSyntax(SyntaxKind.Comment).bkColor;
			foreach(r; contents.rows){
				r.bkColor = c;
			}
		}

		//measureSubCells;
		super.rearrange;

		//innerSize = subCells.back.outerBottomRight;
	}

	override void draw(Drawing dr){
		super.draw(dr);

		/*dr.lineWidth = -1;
		dr.color = clBlue; dr.drawRect(outerBounds);
		dr.color = clYellow; dr.drawRect(innerBounds);

		dr.color = clAqua; dr.drawRect(contents.outerBounds + innerPos);
		dr.color = clFuchsia; dr.drawRect(contents.borderBounds_outer + innerPos);
		dr.color = clOrange; dr.drawRect(contents.innerBounds + innerPos);*/
	}
}+/

class CodeComment : CodeNode{ // CodeComment //////////////////////////////////////////
	CodeColumn contents;

	this(R)(CodeRow parent, R input) if(isInputRange!R && is(ElementType!R==ScanResult)){
		super(parent);
		
		
		//flags.yAlign = YAlign.top;

//    auto ts = tsSyntax(SyntaxKind.Comment);
		auto ts = tsSyntax(SyntaxKind.Symbol);

		const darkColor	= ts.bkColor,
					brightColor	= ts.fontColor,
					halfColor	= avg(darkColor, brightColor);

		bkColor = halfColor;
		border.color = bkColor;

		ts.fontColor = darkColor;
		ts.bkColor = halfColor;
		ts.bold = true;
//    appendStr("//"~smallSpace, ts);
		appendStr("if", ts);

		contents = new CodeColumn(this, "1+1//This is a test comment");
		contents.bkColor = darkColor;

		subCells ~= contents;

		appendStr("\nthen\t", ts);

		contents = new CodeColumn(this, "//This is a test comment");
		contents.bkColor = darkColor;

		subCells ~= contents;

		appendStr("\nelse\t", ts);

		contents = new CodeColumn(this, "//This is a test comment");
		contents.bkColor = darkColor;

		subCells ~= contents;

		needMeasure;
	}

	override string sourceText(){
		NOTIMPL;
		return "";
	}

	override void rearrange(){
		{
			const c = tsSyntax(SyntaxKind.Comment).bkColor;
			foreach(r; contents.rows){
				r.bkColor = c;
			}
		}

		//measureSubCells;
		super.rearrange;

		//innerSize = subCells.back.outerBottomRight;
	}

	override void draw(Drawing dr){
		super.draw(dr);

		/*dr.lineWidth = -1;
		dr.color = clBlue; dr.drawRect(outerBounds);
		dr.color = clYellow; dr.drawRect(innerBounds);

		dr.color = clAqua; dr.drawRect(contents.outerBounds + innerPos);
		dr.color = clFuchsia; dr.drawRect(contents.borderBounds_outer + innerPos);
		dr.color = clOrange; dr.drawRect(contents.innerBounds + innerPos);*/
	}
}


CodeColumn buildUnstructuredCodeColumn(Container owner, string sourceText){
	return new CodeColumn(owner, sourceText);
}

CodeColumn buildStructuredCodeColumn(Container owner, string sourceText){ // buildStructuredCodeColumn ///////////////////////////////////
	
	return new CodeColumn(owner, sourceText);
	
/*	auto scanner = DLangScanner(src); //this scanner is used by all the nested builder functions.
	
	CodeNode tryBuildComment(){
		if(!scanner.empty && scanner.front.op==ScanOp.push){ 
			if(scanner.front.src=="//"){
				scanner.popFront;
				string s;
				while(!scanner.empty){
					if(scanner.front.op==ScanOp.pop){
						scanner.popFront;
						break;
					}else{
						s ~= scanner.front.src;
						scanner.popFront;
					}
				}
				new CodeComment(null, s);
				scanner.until!(t => t.op==ScanOp.pop);
				auto res = new result;
			}
		}
		return null;
	}
	
	void buildDeclarations(){
		string source;
		CodeNode[] nodes;
		
		foreach(token; scanner){
			print(token);
			
			with(ScanOp) switch(ScanOp){
				case content: source ~= token.src;
				case push: if(token.src.among("//", "/*", "/+")){
					nodes ~= buildComment(token.src);
				}
				case pop:
				
				default: raise("UNHANDLED token: "~token.text);
			}
		}
	}
	
	buildDeclarations;
	raise("FUCK");
	
	return null;*/
}
