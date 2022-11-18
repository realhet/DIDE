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
	vec2	pos;
	float	height;
	ubyte	thickness;
	ubyte 	mask;

	vec2	top	() const{ return pos; }
	vec2	center	() const{ return pos + vec2(0, height/2); }
	vec2	bottom	() const{ return pos + vec2(0, height); }
	bounds2	bounds	() const{ return bounds2(top, bottom); }
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
			const ltc = codeColumn.rows[pos.y].leadingCodeTabCount; //unsafe
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
	
	bool empty() const{ return subCells.empty; }

	auto glyphs()	{ return subCells.map!(c => cast(Glyph)c); } //can return nulls
	auto chars()	{ return glyphs.map!"a ? a.ch : '\u26A0'"; }
	
	string shallowText() { return chars.to!string; } //todo: combine this with extractThisLevelDString

	string deepText() { 
		string res; //opt: appender
		foreach(c; subCells){
			if(auto g = cast(Glyph)c){
				res ~= g.ch;
			}else if(auto n = cast(CodeNode)c){
				res ~= n.sourceText;
			}else{
				enforce(0, "deepText: unsupported obj");
			}
		}
		return res;
	}

	//todo: mode isSpace inside elastic tab detection, it's way too specialized

	private static bool isCodeSpace	(Cell c){ if(auto g = cast(Glyph)c) return g.ch==' ' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; return false; }
	private static bool isCodeTab	(Cell c){ if(auto g = cast(Glyph)c) return g.ch=='\t' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; return false; }
	private static bool isAnyWhitespace	(Cell c){ if(auto g = cast(Glyph)c) return !!g.ch.among(' ', '\t'); return false; }
	private auto isCodeSpaces() { return subCells.map!isCodeSpace; }
	
	auto leadingCodeSpaces	(){ return subCells.until!(not!isCodeSpace	); }
	auto leadingCodeTabs	(){ return subCells.until!(not!isCodeTab	); }
	auto leadingAnyWhitespaces	(){ return subCells.until!(not!isAnyWhitespace	); }
	
	auto leadingCodeSpaceCount	(){ return cast(int)leadingCodeSpaces	.walkLength; }
	auto leadingCodeTabCount	(){ return cast(int)leadingCodeTabs	.walkLength; }
	auto leadingAnyWhitespaceCount	(){ return cast(int)leadingAnyWhitespaces	.walkLength; }

	this(CodeColumn parent_){
		parent = enforce(parent_);
		id.value = this.identityStr;

		needMeasure;  //also	sets measureOnlyOnce flag. This is an on-demand realigned Container.
		flags.wordWrap	= false;
		flags.clipSubCells	= true;
		flags.cullSubCells	= true;
		flags.rowElasticTabs	= false;
		flags.dontHideSpaces	= true;
		flags.noBackground	= true;
		
		//bkColor = parent.bkColor;
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
	
	this(CodeColumn parent_, Cell[] cells){
		this(parent_);
		
		//take ownership of the cells.
		cells.each!(c => c.setParent(this));
		subCells = cells;
		refreshTabIdx;
		needMeasure;
	}

	void set(string line, ubyte[] syntax){
		internal_setSubCells([]);

		static TextStyle style; //it is needed by appendCode/applySyntax
		this.appendCode(line, syntax, (ubyte s){ applySyntax(style, s); }, style/+, must paste tabs!!! DefaultIndentSize+/);

		//note: tabIdx is already refreshed by appendCode
		spreadElasticNeedMeasure;
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
		spreadElasticNeedMeasure;

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
		only(this, nextRow).each!"a.spreadElasticNeedMeasure";

		return nextRow;
	}

	///must be called after the code changed. It tracks elasticTabs, and realigns if needed
	void spreadElasticNeedMeasure(){ //todo: such beautyful name... NOT!
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
			foreach(g; glyphs) if(g){ //todo: make this nicer
				if(isCodeSpace(g)){
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
			assert(isCodeSpace(g));
			g.ch = '\t';
			g.isTab = true;
			//note: refreshTabIdx must be called later
		}

		void replaceSpacesWithTabs(int xStart, int xTab, size_t tabCount){
			assert(xStart<=xTab	, "invalid xStart, xTab");
			assert(xStart>=0	, "xStart out of range");
			assert(xTab<subCells.length	, "xTab out of range");
			assert(glyphs[xStart..xTab+1].all!(g => isCodeSpace(g))	, "All must be spaces");
			assert(tabCount <= xTab-xStart+1	, "tabCount too much.");

			auto normalizeLeadingSpaces(Cell[] sc){
				sc	.until!(a => !(isCodeSpace(a) && a.outerWidth!=NormalSpaceWidth))
					.each!(a => a.outerWidth = NormalSpaceWidth);
				return sc;
			}

			internal_setSubCells(subCells[0..xStart+tabCount] ~ (xTab+1<subCells.length ? normalizeLeadingSpaces(subCells[xTab+1..$]) : []));
			foreach(i; xStart..xStart+tabCount) spaceToTab(i); //promote spaces to tabs

			refreshTabIdx; //todo: should only be done once at the end...
		}

		void convertLeadingSpacesToTabs(int spaceCnt){
			//todo: tab inside string literal. width is too big  File(`c:\D\libs\!shit\_unused.arsd\html.d`)
			//subCells.each!LOG;
			assert(spaceCnt>0);
			const tabCnt = leadingCodeSpaceCount/spaceCnt;
			//LOG(leadingCodeSpaceCount, spaceCnt);
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
				const lwsCnt = leadingAnyWhitespaceCount; //opt: this should be memoized
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


static struct CodeColumnBuilder(bool rebuild){ //CodeColumnBuilder /////////////////////////////////////////
	enum resyntax = !rebuild;

	CodeColumn col;
	TextStyle tsWhitespace, ts;
	SyntaxKind _currentSk=skWhitespace, syntax=skWhitespace;
			
	CodeRow actRow;
	bool skipNextN; //after \r, skip the next \n
	
	static if(rebuild){
		void NL(){ 
			col.appendCell(actRow = new CodeRow(col, "", null)); 
		}
		
		void initialize(){
			col.clearSubCells;
			NL; //there must be 1 row always. Empty column is a single empty row.
		}
		
		void appendChar(dchar ch){
			switch(ch){
				case '\n', '\r', '\u2028', '\u2029':
					if(skipNextN.chkClear && ch=='\n') break;
					skipNextN = ch=='\r';
					NL;
				break;
				default: 
					//update cached textStyle
					if(_currentSk.chkSet(syntax))
						applySyntax(ts, syntax);
					
					actRow.appendSyntaxChar(ch, ts, syntax); 
			}
		}
		
		void appendNode(CodeNode node){
			assert(node);
			assert(node.parent is actRow);
			actRow.appendCell(node);
		}
	}
	
	static if(resyntax){
		
		ivec2 actPos;
		
		void initialize(){
			//seek to the first character
			actPos = ivec2(0);
			actRow = col.rowCount ? col.rows[0] : null; //todo: there must be a first row.
			enforce(actRow, "Resyntax: Invalid CodeColumn: No rows at all.");
		}
		
		void moveToNextRow(){
			enforce(actRow.cellCount==actPos.x, "Resyntax: Longer row than expected. "~actPos.text);
			actPos.y++;
			actPos.x = 0;
			actRow = actPos.y<col.rowCount ? col.rows[actPos.y] : null;
			enforce("Resyntax: More rows expected. "~actPos.text);
		}
		
		void moveToNextChar(){ 
			actPos.x++; //this position is allowed to be out of range, because here comes the newline
		}
		
		void appendChar(dchar ch){
			switch(ch){
				case '\n', '\r', '\u2028', '\u2029':
					if(skipNextN.chkClear && ch=='\n') break;
					skipNextN = ch=='\r';
					moveToNextRow;
				break;
				default: 
					/+debug+/ //const prevSyntax = syntax; if(ch=='a') syntax = skKeyword; scope(exit) if(ch=='a') syntax = prevSyntax;
					
					//update cached textStyle
					if(_currentSk.chkSet(syntax))
						applySyntax(ts, syntax);
					
					auto g = cast(Glyph)(actRow.subCells.get(actPos.x)); //opt: cache this array per each row
					enforce(g, "Resyntax: Glyph expected "~actPos.text);
					enforce(g.ch == ch, "Resyntax: Glyph char changed "~actPos.text);
					if(g.syntax.chkSet(syntax)){
						//syntaxChanged = true;
						g.bkColor	= ts.bkColor;
						g.fontColor	= ts.fontColor;

						const prevFontFlags = g.fontFlags;
						g.fontFlags = ts.fontFlags;
						if(auto delta = g.adjustBoldWidth(prevFontFlags)){
							actRow.needMeasure; 
							//opt: cache this and call only once per each row
							//todo: Ensure elastic tabs recursive spread.
						}
					}
					moveToNextChar;
			}
		}
		
		void appendNode(CodeNode node){
			auto n = cast(CodeNode)(actRow.subCells.get(actPos.x)); //opt: cache this array per each row
			enforce(n, "Resyntax: Glyph expected "~actPos.text);
			
			//no need to check anything
			//opt: no need to rebuild the node, only skip it.
			
			moveToNextChar;
		}
	}
	
	void appendStr(string str){
		foreach(dchar ch; str) appendChar(ch);
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
	
	void appendHighlighted	(string sourceText){ appendHighlighted	(sourceText.DLangScanner); }
	void appendStructured	(string sourceText){ appendStructured	(sourceText.DLangScanner); }

	void appendHighlighted	(R)(R scanner) if(isScannerRange!R) { appendHighlightedOrStructured!false	(scanner); }
	void appendStructured	(R)(R scanner) if(isScannerRange!R) { appendHighlightedOrStructured!true	(scanner); }
	
	void appendHighlightedOrStructured(bool structured=false, R)(R scanner)
	if(isScannerRange!R)
	{
		auto syntaxStack = [syntax];
		while(!scanner.empty){ 
			auto sr = scanner.front;
			
			//structural exit handling
			static if(structured){
				if(syntaxStack.length==1 && sr.op==ScanOp.pop){
					//only read until the end of the current level
					break; 
				}
			}
			
			void handleHighlightedPush(){
				syntaxStack ~= syntax;
				switch(sr.src){
					case "//", "/*", "/+"	: syntax = skComment	; appendStr(sr.src);		break;
					case "{", "(", "["	: syntax = skSymbol	; appendStr(sr.src);	 syntax = skWhitespace; 	break;
					case `q{`	: syntax = skString	; appendStr(sr.src);	 syntax = skWhitespace;	break;
					case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`	: syntax = skString	; appendStr(sr.src);		break;
					default	: syntax = skError	; appendStr(sr.src);		break;
					//todo: identifier quoted string `q"id`
				}
			}
			
			switch(sr.op){
				case ScanOp.push:{
					static if(structured){
						auto N(T)(){ auto c = new T(actRow); c.rebuild(scanner); appendNode(c); }
						switch(sr.src){
							case "//"	: N!CodeComment; appendChar('\n'); 	continue; //todo: //comment must ensure that after it, there will be a NewLine
							case "/*", "/+",	: N!CodeComment;	continue; 
							case "`", "'", `"`, `r"`, `q"(`, `q"[`, `q"{`, `q"<`, `q"/`, `q{`	: N!CodeString;	continue;
							case "{", "(", "["	: N!CodeBlock;	continue;
							default: handleHighlightedPush;
						}
					}else{
						handleHighlightedPush;
					}
				break;}
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
					if(syntax.among(skComment, skString)){
						appendStr(sr.src); 
						//todo: highlight string escapes
						//todo: advanced comment formatting
					}else{
						appendHighlighted_internal(sr.src);
					}
					break;
				default: syntax = skError; appendStr(sr.src); break;
			}
			
			scanner.popFront;
		}
		
		col.convertSpacesToTabs(Yes.outdent);
		col.needMeasure;
	}
	
	
	this(CodeColumn col){
		this. col = col;
		
		tsWhitespace 	= tsNormal	; applySyntax(tsWhitespace	, skWhitespace	);
		ts 	= tsWhitespace	; applySyntax(ts	, _currentSk	);
		
		initialize;
	}
	
}

class CodeColumn: Column{ // CodeColumn ////////////////////////////////////////////
	//note: this is basically the CodeBlock
	Container parent;
	//CodeContext context;
	
	enum defaultSpacesPerTab = 4; //default in std library
	int spacesPerTab = defaultSpacesPerTab; //autodetected on load

	DateTime lastResyntaxTime; //needed for the multithreaded syntax highligh processing. It can detect if the delayed syntax highlight is up-to-date or not.

	/+deprecated("Only needed for compile.err builder") this(Container parent){
		this(parent, ccPlain);
	}+/

	/// Minimal constructor creating an empty codeColumn with 0 rows.
	this(Container parent){
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
	
	this(Container parent_, Cell[][] cells){
		this(parent_);
		subCells = cast(Cell[])(cells.map!(r => new CodeRow(this, r)).array);
		
		//one row must always present.
		if(subCells.empty) subCells ~= new CodeRow(this);
	}
	
	bool empty() const{ return !rows.length || rows.length==1 && rows[0].empty; }
	
	auto rebuilder	(){ return CodeColumnBuilder!true	(this); }
	auto resyntaxer	(){ return CodeColumnBuilder!false	(this); }
	
	auto calcWhitespaceStats(){
		import het.tokenizer : WhitespaceStats;
		WhitespaceStats whitespaceStats;
		foreach(r; rows){ //todo: optimize it somehow... Statistically...
			if(!r.leadingCodeTabs.empty){
				whitespaceStats.tabCnt++;
			}else{
				auto spaceCnt = r.leadingCodeSpaceCount;
				whitespaceStats.addSpaceCnt(spaceCnt);
			}
		}
		//note: this is just lame statistics to detect the size of a tab only for converting spaces to tabs.
		return whitespaceStats;
	}
	
	void convertSpacesToTabs(Flag!"outdent" outdent){ 
		//todo: this can only be called after the rows were created. Because it doesn't call needMeasure_elastic()
		createElasticTabs;
		spacesPerTab = calcWhitespaceStats.detectIndentSize(DefaultIndentSize); //opt: this can be slow. Maybe put it on a keyboard shortcut.
		rows.each!(row => row.convertLeadingSpacesToTabs(spacesPerTab));
		
		//outdent
		if(outdent){
			
			bool isWhitespaceRow(CodeRow r){
				return r.subCells.empty || r.subCells.all!((c){
					if(auto g = cast(Glyph)c)
						if(g.ch.isDLangWhitespace && g.syntax.among(0/+whitespace+/, 9/+comment+/)) return true;
					return false;
				});
				//return r.leadingCodeTabCount<r.cellCount; 
			}
			
			//remove first and last whitespace row
			if(subCells.length>1 && isWhitespaceRow(rows[0])) subCells = subCells[1..$];
			if(subCells.length>1 && isWhitespaceRow(rows[$-1])) subCells = subCells[0..$-1];
			
			//only rows that not only tabs are relevant
			bool relevant(CodeRow r){
				return r.subCells.any!((c){
					if(auto g = cast(Glyph)c){
						if(g.ch.among(' ', '\t') && g.syntax.among(0/+whitespace+/, 9/+comment+/)) return false;
						return true;
					}
					if(cast(CodeComment)c) return false; //comments are irrelevant
					return true;
				});
				//return r.leadingCodeTabCount<r.cellCount; 
			}
			//find minimum amount of tabs
			auto relevantRows = rows.filter!relevant;
			if(!relevantRows.empty){
				const numTabs = relevantRows.map!"a.leadingCodeTabCount".minElement;
				if(numTabs) foreach(r; rows) if(r.leadingCodeTabCount>=numTabs){
					r.subCells = r.subCells[numTabs..$];
					r.refreshTabIdx;
					//note: no need to call needRefresh_elastic because all rows will be refreshed. It's in convertSpacesToTabs which only kicks right after row creation.
				}
			}
		}
		
		needMeasure;
	}

	void resyntax(string sourceText){
		//note: IT IS ILLEGAL TO MODIFY the contents in this. Only change to font color and flags are valid.
		//todo: older todo: resyntax: Problem with the Column Width detection when the longest line is syntax highlighted using bold fonts.
		//todo: older todo: resyntax: Space and hex digit sizes are not adjusted after resyntax.
		try{ 
			resyntaxer.appendHighlighted(sourceText);
		}catch(Exception e){
			WARN(e.simpleMsg);
		}
	}

	override inout(Container) getParent() inout { return parent; }
	override void setParent(Container p){ parent = p; }

	override void appendCell(Cell cell){
		assert(cast(CodeRow)cell);
		super.appendCell(cell);
	}

	auto const rows(){ return cast(CodeRow[])subCells; }
	int rowCount() const{ return cast(int)subCells.length; }
	int lastRowIdx() const{ return rowCount-1; }
	int lastRowLength() const{ return rows.back.cellCount; }

	auto getRow(int rowIdx){ return rowIdx.inRange(subCells) ? rows[rowIdx] : null; }

	int rowCharCount(int rowIdx) const{
		//todo: it's ugly because of the constness. Make it nicer.
		if(rowIdx.inRange(subCells)) return cast(int)((cast(CodeRow)subCells[rowIdx]).subCells.length);
		return 0;
	}

	string rowShallowText	(int rowIdx){ if(auto row = getRow(rowIdx)) return row.shallowText	; return ""; }
	string rowDeepText	(int rowIdx){ if(auto row = getRow(rowIdx)) return row.deepText	; return ""; }

	TextCursor homeCursor(){ return TextCursor(this, ivec2(0)); }
	TextCursor endCursor(){ 
		return TextCursor(this, ivec2(rowCount-1, lastRowLength)); 
		/* auto res = homeCursor; res.move(ivec2(TextCursor.end, TextCursor.end)); return res; */ 
	}
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


	@property string shallowText	() { return rows.map!(r => r.shallowText	).join(DefaultNewLine); }  // \r\n is the default in std library
	@property string deepText	() { return rows.map!(r => r.deepText	).join(DefaultNewLine); }

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

	void setupBorder(){
		this.setRoundBorder(8);
		margin.set(.5);
		padding.set(.5, 4);
	}

	override void rearrange(){
		setupBorder;
		
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
				return isCodeSpaces[x] && (x+1 >= cellCount || !isCodeSpaces[x+1]);
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

				int x0 = x; while(x0 > 0 && isCodeSpaces[x0-1]) x0--;
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
					int xStart	= x; while(xStart > xStartMin && isCodeSpaces[xStart-1]) xStart--;
					int xTab	= x+1-minLen;

					newTabs ~= TabInfo(yy, xStart, xTab);

					//if(xStartMin>0) print(lines[yy].text, "         ", newTabs.back);
				}
			}
		}

		//scan through all the rows and initiate floodFills
		foreach(y, row; rows) with(row){
			int st = 0;
			foreach(isSpace, len; isCodeSpaces.group){
				const en = st + cast(int)len;

				if(isSpace && st>0){
					bool canGoUp, canGoDown;

					if(len==1 && st>0 && chars[st-1].among('[', '('))	canGoDown = true; //todo: the tabs below this one should inherit the indent of this first line
					else	canGoUp = canGoDown = canGoDown = len>=2;
					
					/+const leftChar = st>0 ? chars[st-1] : '\0';
					const rightChar = en+1<len ? chars[en+1] : '\0';
					if(!(leftChar.isSymbol || rightChar.isSymbol)) canGoUp = canGoDown = false;+/
					
					flood(en-1, cast(int)y, canGoUp, canGoDown, leadingCodeSpaceCount);
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
		auto cc = scoped!CodeColumn(null);
		cc.rebuilder.appendPlain(src);
		void expect(T, U)(T a, U b){ if(a!=b) ERR("Test fail: "~[src, rowCount.text, dst].text~" : "~a.text~" != "~b.text); }
		expect(cc.rows.length, rowCount);
		expect(cast(ubyte[])dst, cast(ubyte[])(cc.rows.map!(r => r.shallowText).join('\n')));
	}

	test_RowCount("", 1);
	test_RowCount(" ", 1);
	test_RowCount("\n", 2);
	test_RowCount("\n ", 2, "\n "); //todo: a tabokat visszaalakitani space-ra. Csak a leading comment/whitespace-re menjen, az elastic tabokat meg egymas ala kell igazitani space-ekkel. De ezt majd kesobb. Most minden tab lesz.
	test_RowCount("\r\n", 2, "\n");
	test_RowCount(" \n \n \r\n", 4, " \n \n \n"); //todo: a tabokat visszaalakitani space-ra
	test_RowCount(" \n \n \r\n ", 4, " \n \n \n "); //todo: a tabokat visszaalakitani space-ra
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

void dumpDDoc(string src){
	print("----Original DDoc---------------------------------------------------");
	LOG(src);
	print("----Processed DDoc-------------------------------------------------");
	string stack="*";
	auto scanner = src.DDocScanner;
	if(1) f: foreach(sr; scanner){
		with(EgaColor) switch(sr.op){
			case ScanOp.content:{
				if(stack[$-1]=='`') write(ltGreen(sr.src));
				else if(stack[$-1]=='*') write(ltWhite(sr.src));
				else write(ltBlue(sr.src));
			} break;
			case ScanOp.push:{
				write(yellow(sr.src));
				stack ~= sr.src[0];
			} break;
			case ScanOp.pop:{
				write(yellow(sr.src));
				stack.popBack;
				if(stack.empty){ write(ltRed("Out of stack")); break f; }
			} break;
			case ScanOp.trans:{
				write(ltCyan(sr.src));
			} break;
			default:{
				write(EgaColor.ltRed(sr.op.text~":"~sr.src));
			} break;
		}
	}
	print("---End of Processed DDoc----------------------------------------------");
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

	auto rearrangeHelper(SyntaxKind syntax, int inverse_, Nullable!RGB customColor = Nullable!RGB.init){
		
		struct Helper{
			CodeNode node;
			TextStyle ts;
			int inverse; //0, 1, 2
			RGB darkColor, brightColor, halfColor;
			
			void put(T)(T a){ 
				static if(isSomeString!T	) node.appendStr(a, ts);
				else static if(isSomeChar!T	) node.appendChar(a, ts);
				else static if(is(T:Cell)	) node.appendCell(a);
				else static assert(0, "unhandled type");
			}
		}
		
		Helper res; with(res){
			node 	= this;
			ts 	= tsSyntax(syntax);  if(!customColor.isNull) ts.fontColor = customColor.get;
			inverse 	= inverse_;
			darkColor	= ts.bkColor,
			brightColor	= ts.fontColor,
			halfColor	= mix(darkColor, brightColor, inverse.predSwitch(0, .15f, 1, .5f, 1));
			
			ts.bkColor = border.color = bkColor	= halfColor; 
			ts.fontColor	= inverse ? darkColor : brightColor;
			ts.bold 	= true;
		}

		//initialize node
		subCells = []; //This rebuilds and realigns the whole Row subCells.
		flags.yAlign = YAlign.center;
		
		return res;
	}
	
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


class CodeContainer : CodeNode{ // CodeContainer /////////////////////////////
	CodeColumn content;
	
	abstract SyntaxKind syntax	() const;
	abstract string prefix	() const;
	abstract string postfix	() const;
	
	this(Container parent){
		super(parent);
		content = new CodeColumn(this);
	}
	
	override string sourceText(){
		//todo: handle invalid characters.
		return prefix~content.deepText~postfix;
	}
	
	protected T parseBlockPrefix(T, string[] tokens, R)(R scanner) if(isScannerRange!R){
		enforce(!scanner.empty);
		const sr = scanner.front;
		enforce(sr.op == ScanOp.push);
		auto res = tokens.countUntil(sr.src).to!T;
		scanner.popFront;
		return res;
	}
	
	override void rearrange(){
		with(rearrangeHelper(syntax, prefix.among("[", "(", "{") ? 0 : 1)){
			content.bkColor = darkColor;
		
			put(prefix); 	const i0 = subCells.length;
			put(content);	const i2 = subCells.length;
			put(postfix); //todo: //slashComment must ensure that after it there is a newLine
		
			super.rearrange;
		
		//yAlign prefix and postfix
			if(content.rowCount>1){
				foreach(c; subCells[0..i0]) c.outerPos.y = 0;
				foreach(c; subCells[i2..$]) c.outerPos.y = innerHeight-c.outerHeight;
			}
		}
	}

}

class CodeComment : CodeContainer{ // CodeComment //////////////////////////////////////////
	enum Type {slashComment, cComment, dComment}
	enum TypePrefix 	= ["//"	, "/*", "/+"];
	enum TypePostfix 	= [""	, "*/", "+/"];
	
	Type type;
	bool isDDoc;
	
	override SyntaxKind syntax	() const{ return skComment; }
	override string prefix	() const{ return TypePrefix[type]; }
	override string postfix	() const{ return TypePostfix[type]; }
	
	this(CodeRow parent){ 
		super(parent); 
	}
	
	void rebuild(R)(R scanner) if(isScannerRange!R){
		type = parseBlockPrefix!(Type, TypePrefix)(scanner);
		isDDoc = !scanner.empty && scanner.front.op==ScanOp.content && scanner.front.src.startsWith(prefix.back);
		
		//get content
		auto rebuilder = CodeColumnBuilder!true(content);
		while(!scanner.empty){
			if(scanner.front.op==ScanOp.push){
				//opening a new something
				if(scanner.front.src=="/+"){
					auto n = new CodeComment(rebuilder.actRow);  //RECURSION!!!!!
					n.rebuild(scanner);
					rebuilder.appendNode(n);
					continue;
				}else{
					enforce(0, "Invalid push: "~scanner.front.src);
				}
			}else if(scanner.front.op==ScanOp.pop){
				//closing token
				scanner.popFront;
				break;
			}else{
				rebuilder.syntax = scanner.front.op==ScanOp.content ? skComment : skError;
				rebuilder.appendStr(scanner.front.src);
				
				//if(isDDoc) dumpDDoc(scanner.front.src); //todo: DDoc parser
			}
			scanner.popFront;
		}
		
		needMeasure;
	}

}

class CodeString : CodeContainer{ // CodeString //////////////////////////////////////////
	//todo: qString_id
	enum Type 		{ dString	, cChar	, cString	, rString	, qString_round	, qString_square	, qString_curly	, qString_angle	, qString_slash	, tokenString	}
	enum TypePrefix 	= 	["`"	, "'"	, `"`	, `r"`	, `q"(`	, `q"[`	, `q"{`	, `q"<`	, `q"/`	, `q{`	];
	enum TypePostfix 	= 	["`"	, "'"	, `"`	, `"`	, `)"`	, `]"`	, `}"`	, `>"`	, `/"`	, `}`	];
	
	enum CharSize {default_, c, w, d}
	
	Type type;
	CharSize charSize;
	
	override SyntaxKind syntax	() const{ return skString; }
	override string prefix	() const{ return TypePrefix[type]; }
	override string postfix	() const{ return TypePostfix[type]~sizePostfix; }
	string sizePostfix	() const{ return charSize!=CharSize.default_ ? charSize.text : ""; }
	
	this(CodeRow parent){ 
		super(parent); 
	}
	
	void rebuild(R)(R scanner) if(isScannerRange!R){
		type = parseBlockPrefix!(Type, TypePrefix)(scanner);
		charSize = CharSize.default_;
		
		//get content
		auto rebuilder = CodeColumnBuilder!true(content);
		
		if(type==Type.tokenString){
			content.bkColor = mix(syntaxBkColor(skString), clCodeBackground, .75f);
			//todo: clCodeBackground should be inherited to all the inner backgrounds.
			//todo: language dependent keyword coloring
			
			rebuilder.appendStructured(scanner); //this will stop at the closing "}"
			
			if(!scanner.empty && scanner.front.op==ScanOp.pop && scanner.front.src.startsWith("}")){
				//closing token: Decode char/word/dword string element size specifier.
				if(auto cwdIdx = scanner.front.src.back.among('c', 'w', 'd'))
					charSize = cast(CharSize)cwdIdx;
				
				scanner.popFront;
			}else enforce(0, "Invalid tokenstring");
		}else{ 
			while(!scanner.empty){
				if(scanner.front.op==ScanOp.push){
					enforce(0, "Invalid push: "~scanner.front.src);
				}else if(scanner.front.op==ScanOp.pop){
					//closing token: Decode char/word/dword string element size specifier.
					if(auto cwdIdx = scanner.front.src.back.among('c', 'w', 'd'))
						charSize = cast(CharSize)cwdIdx;
					
					scanner.popFront;
					break;
				}else{
					rebuilder.syntax = scanner.front.op==ScanOp.content ? skString : skError;
					rebuilder.appendStr(scanner.front.src);
				}
				scanner.popFront;
			}
		}
		
		needMeasure;
	}

}


class CodeBlock : CodeContainer{ // CodeBlock //////////////////////////////////////////
	enum Type 		{ block	, list	, index	}
	enum TypePrefix 	= 	["{"	, "("	, `[`	];
	enum TypePostfix 	= 	["}"	, ")"	, `]`	];
	
	Type type;
	
	override SyntaxKind syntax	() const{ return skSymbol; }
	override string prefix	() const{ return TypePrefix	[type]; }
	override string postfix	() const{ return TypePostfix	[type]; }
	
	this(Container parent){ 
		super(parent); 
	}
	
	void rebuild(R)(R scanner) if(isScannerRange!R){
		type = parseBlockPrefix!(Type, TypePrefix)(scanner);
		auto rebuilder = CodeColumnBuilder!true(content);
		rebuilder.appendStructured(scanner); //this will stop at the closing token
		if(!scanner.empty && scanner.front.op==ScanOp.pop && scanner.front.src==postfix){
			//analize patterns
			//note: -> processHighLevel
			/*if(scanner.front.src=="}"){
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
			}*/
			
			//closing token
			scanner.popFront;
		}else enforce(0, "Invalid block closing token");
		
		/+if(type!=Type.block){
			content.setRoundBorder(2);
			content.margin = "0.25";
			content.padding = "0.25 4";
			
			this.setRoundBorder(2);
			this.margin = "0.25";
			this.padding = ".6 .75";
		}+/
		
		needMeasure;
	}

}

/// Module ///////////////////////////////////////////////
interface WorkspaceInterface{
	@property bool isReadOnly();
}

enum StructureLevel : ubyte { plain, highlighted, structured, managed }

class Module : CodeBlock{ //this is any file in the project
	File file;

	DateTime fileLoaded, fileModified, fileSaved; //opt: detect these times from the outside
	size_t sizeBytes;  //todo: update this form the outside

	StructureLevel structureLevel;
	static foreach(e; EnumMembers!StructureLevel) mixin(format!q{ @property is%s() const{ return structureLevel == StructureLevel.%s; } }(e.text.capitalize, e.text));

	ModuleBuildState buildState;
	bool isCompiling;

	bool isMainExe, isMainDll, isMainLib, isMain, isStdModule, isFileReadOnly;

	UndoManager undoManager;
	
	override SyntaxKind syntax	() const{ return skWhitespace; }
	override string prefix	() const{ return ""; }
	override string postfix	() const{ return ""; }

	this(Container parent, File file_){
		super(parent);
		bkColor = clModuleBorder;
		fileLoaded = now;
		file = file_.actualFile;
		reload;
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
			if(content) if(auto r = content.getRow(0)){ 
				//todo: this detector is not so nice... Need to develop more advanced source code parsing methods.
				
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

		isStdModule = file.fullName.isWild(`c:\d\ldc2\import\*`); //todo: detect compiler import path correctly
		isFileReadOnly = isStdModule || file.isReadOnly || file.name.sameText("compile.err"); //todo: periodically chenck if file is exists and other attributes in the IDE
	}

	void resyntax(){
		content.resyntax("UNUSED0"/*code.sourceText*/);
	}

	void reload(Flag!"useExternalContents" useExternalContents = No.useExternalContents, string externalContents=""){
		fileModified = file.modified;
		sizeBytes = file.size;
		resetModuleTypeFlags;

		auto prevSourceText = sourceText;
		string sourceText = useExternalContents	? externalContents
			: this.file.readText;
		undoManager.justLoaded(this.file, encodePrevAndNextSourceText(prevSourceText, sourceText));
		
		void doPlain(){
			try{
				content.rebuilder.appendPlain(sourceText);
				structureLevel = StructureLevel.plain;
			}catch(Exception e){
				raise("Fatal error. Unable to load module even in plain mode. "~file.text~"\n"~e.simpleMsg);
			}
		}
		
		void doHighlighted(){
			try{
				content.rebuilder.appendHighlighted(sourceText);  //todo: this is NOT raising an exception, only draws the error with red and and display a WARN. It should revert to plain...
				structureLevel = StructureLevel.highlighted;
			}catch(Exception e){
				WARN("Unable to load module in highlighted mode. "~file.text~"\n"~e.simpleMsg);
				doPlain;
			}
		}
		
		void doStructured(){
			try{
				content.rebuilder.appendStructured(sourceText); 
				structureLevel = StructureLevel.structured;
			}catch(Exception e){
				WARN("Unable to load module in structured mode. "~file.text~"\n"~e.simpleMsg);
				doHighlighted;
			}
		}
		
		void doManaged(){
			doManaged; 
			if(isStructured){
				try{
					processHighLevelPatterns(content);
					structureLevel = StructureLevel.managed;
				}catch(Exception e){
					WARN("Unable to load module in managed mode. "~file.text~"\n"~e.simpleMsg);
					doManaged;
				}
			}
		}
		
		enum targetLevel = StructureLevel.structured;
		[&doPlain, &doHighlighted, &doStructured, &doManaged][targetLevel]();
		
		needMeasure;
	}

	size_t linesOfCode(){ return content.rowCount; } //todo: update this. only good for unstructured code.

	override void rearrange(){
		detectModuleTypeFlags;
		super.rearrange;
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


//bug: ErrorListModule is fucked up
deprecated class ErrorListModule : Module{  // ErrorListModule ////////////////////////////////////////////////////////
	this(Container parent, File file_){
		super(parent, file_);
		
		reload;
	}

	override bool isReadOnly(){ return true; }

	override void resyntax(){ }

	override void reload(Flag!"useExternalContents" useExternalContents = No.useExternalContents, string contents=""){
		clearSubCells;
		fileModified = now;
		sizeBytes = 0; //todo: note this has no file.
		resetModuleTypeFlags;
		content = createErrorListCodeColumn(this); //todo: remake this with a parser
		appendCell(enforce(content));
		needMeasure;
	}
}


// High level stuff ///////////////////////////////////

RGB brighter(RGB a, float f){
	return (a.rgbToFloat*(1+f)).floatToRgb;
}

enum clPiko : RGB8 {
	G940 	= RGB(139, 59, 43).brighter(.25f),
	G239 	= RGB(245, 156, 0),
	G231 	= RGB(238, 114, 3),
	G119 	= RGB(221, 11, 47).brighter(.25f),
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
}

RGB structuredColor(string name, RGB def = clGray){
	switch(name){
		case "template"	: return clPiko.G940;
		case "enum"	: return clPiko.G239;
		case "alias"	: return clPiko.G231;
		case "if", "switch", "final switch", "for", "do", "while", "foreach", "foreach_reverse", "else"	: return clPiko.G119;
		case "version", "debug", "static if", "static foreach"	: return clPiko.G115;
		case "module", "import"	: return clPiko.G107;
		case "unittest"	: return clPiko.G62;
			
		case "section"	: return clPiko.R1;
		case "with"	: return clPiko.R2;
		case "__unused1"	: return clPiko.R4;
			
		case "class"	: return clPiko.W;
		case "interface"	: return clPiko.BW;
		case "struct"	: return clPiko.W3;
		case "union"	: return clPiko.WY;
		case "mixin template"	: return clPiko.K15;
		case "mixin"	: return clPiko.DKW;
		case "statement"	: return clGray;
		case "function"	: return clSilver;
		default	: return def;
	}
}

// keyword tables /////////////////////////////////////

static immutable namedSymbols = [ //["none", ""] is mandatory
	["none"	, ""	],   	["semicolon"	, ";"	],   	["colon"	, ":"	],   	["comma"	, ","	],
	["equal"	, "="	],   	["question"	, "?"	],   	["block"	, "{"	],   	["params"	, "("	],
];

static immutable sentenceDetectionRules = [
	["; = ? module import alias"	, ";"	],
	["{ template unittest"	, "{"	],
	["enum struct union class interface"	, "; {"	],
	[":"	, ":"	],
];

static immutable prepositionPatterns = [
	"with (",
	"for (", 	"foreach (", 	"foreach_reverse (", 	"static foreach (", 	"static foreach_reverse (",
	"while (", 	"do",		
	"version (", 	"debug (",  	"debug", 	
	"if (", 	"static if (", 	"else if (", 	"else static if (",
	"else", 	"else version (", 	"else debug (", 	"else debug", 
	"switch (", 	"final switch (",		
	"try", 	"catch (", 	"finally",	
	"debug =",	"else debug =", //special case: debug = is a statement, not a preposition!.
	//"scope (", "synchronized (", "synchronized" //todo: These are for statements only! 
].sort!"a>b".array; //note: descending order is important.  "debug (" must be checked before "debug"

static immutable attributeKeywords = [
	"extern", "align", "deprecated",
	"private", "package", "package", "protected", "public", "export",
	"pragma", "static", "abstract ", "final", "override", "synchronized", "auto", "scope", 
	"const", "immutable", "inout", "shared", "__gshared", 
	"nothrow", "pure", "ref", "return"
];

// keyword helper functions ///////////////////////////////////////////////

alias nameOfSymbol = arraySwitch!(namedSymbols[].map!"a[1]", namedSymbols[].map!"a[0]");
alias symbolOfName = arraySwitch!(namedSymbols[].map!"a[0]", namedSymbols[].map!"a[1]");

bool isNamedSymbol(string symbol){ return namedSymbols.map!"a[1]".canFind(symbol); }
bool isSymbolName(string name){ return namedSymbols.map!"a[0]".canFind(name); }

string toSymbolEnum(string s){
	return isNamedSymbol(s) ? nameOfSymbol(s) : "_"~s;
}

/// do conversion from simple string symbols/identifiers to enum members
/// "; : alias if" -> "semicolon, colon, _alias, _if"
string toSymbolEnumList(string s){
	return s.split.filter!"a.length".map!toSymbolEnum.join(", ");
}


//todo: move to utils
bool isDLangIdentifier(alias fStart=isDLangIdentifierStart, alias fCont=isDLangIdentifierCont, S)(in S s){
	auto a = s.byDchar;
	if(a.empty) return false;
	if(!a.front.unaryFun!fStart) return false;
	a.popFront;
	return a.all!(unaryFun!fCont);
}

alias isDLangNumber(S) = isDLangIdentifier!(isDLangNumberStart, isDLangNumberCont, S);

auto genExtractIdentifiers(string ending)(){ 
	return ending.format!q{ 
		sentenceDetectionRules.filter!"a[1].canFind(`%s`)".map!"a[0].split".join.filter!(a => a.length && a[0].isDLangIdentifierStart).array //todo: isDLangIdentifier
	};
}

static immutable 	prepositionKeywords 	= prepositionPatterns.map!(a => a.stripRight(" (=")).array.sort.uniq.array, 
 	blockKeywords 	= mixin(genExtractIdentifiers!"{"),
	statementKeywords 	= mixin(genExtractIdentifiers!";");

static foreach(name; "preposition attribute statement block".split){
	mixin( format!q{
		bool is%sKeyword	(string s){ return %sKeywords	.canFind(s); } 
	}(name.capitalize, name) );
}


//getLeadingAttributesAndComments /////////////////////////////////////////

/+auto getLeadingAttributesAndComments(Token[] tokens){
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
}+/


auto withoutStartingSpace(Cell[][] a){
	if(a.length && a.front.length) if(auto g = cast(Glyph)a.front.front) if(g.ch==' ') a.front = a.front[1..$];
	return a;
}

auto withoutEndingSpace(Cell[][] a){
	if(a.length && a.back.length) if(auto g = cast(Glyph)a.back.back) if(g.ch==' ') a.back = a.back[0..$-1];
	return a;
}


class Declaration : CodeNode { // Declaration /////////////////////////////
	CodeColumn attributes;
	string keyword;
	CodeColumn header, block;
	char ending;
	
	bool isBlock	() const{ return ending=='}'; }
	bool isStatement	() const{ return ending==';'; }
	bool isSection	() const{ return ending==':'; }
	bool isPreposition	() const{ return ending==')'; }
	
	bool hasHeader() const{
		if(keyword.among("else", "unittest")) return false;
		return true;
	}
	
	void verify(){
		if(isBlock){
			enforce(block, "Invalid null block.");
			enforce(keyword=="" || keyword.isBlockKeyword, "Invalid declaration block keyword: "~keyword.quoted);
		}else if(isStatement){
			enforce(keyword=="" || keyword.isStatementKeyword, "Invalid declaration statement keyword: "~keyword.quoted);
		}else if(isSection){
			enforce(keyword.among(""), "Invalid declaration section keyword: "~keyword.quoted);
		}else if(isPreposition){
			enforce(keyword.isPrepositionKeyword, "Invalid declaration preposition keyword: "~keyword.quoted);
		}else enforce(0, "Invalid declaration ending: "~ending.text.quoted);
	}
	
	this(Container parent, Cell[][] attrCells, string keyword, Cell[][] headerCells, CodeColumn block, char ending){
		super(parent);
		this.keyword = keyword;
		this.ending = ending;
		this.attributes 	= new CodeColumn(this, attrCells	.withoutStartingSpace.withoutEndingSpace);
		this.header 	= new CodeColumn(this, headerCells	.withoutStartingSpace.withoutEndingSpace);
		this.block	= block; if(block) block.setParent(this);
		verify;
		if(isBlock && keyword!="enum") processHighLevelPatterns(block); //RECURSIVE!!!
	}
	
	override string sourceText(){
		//todo: handle invalid characters. Ensure valid syntax.
		if(isPreposition) return keyword ~ (hasHeader ? "("~header.deepText~")" : ""); 
		return only(attributes.deepText, keyword, header.deepText, isBlock ? "{"~block.deepText~"}" : ending.text).filter!"a.length".join(' ');
	}
	
	string type() const{
		if(keyword.length	) return keyword;
		if(isStatement	) return "statement";
		if(isSection	) return "section";
		if(isPreposition	) return "preposition";
		if(isBlock	) return "function";
		return "";
	}
	
	char opening() const{ return ending.predSwitch('}', '{', ')', '(', ' '); }
	
	bool isLabel() const{
		if(!isSection) return false;
		auto src = header.rows.map!(row => row.subCells.map!structuredCellToChar).joiner(" ");
		
		while(!src.empty && src.front==' ') src.popFront;
		
		if(src.empty || !src.front.isDLangIdentifierStart) return false;
		
		string id = src.front.text;
		src.popFront;
		while(!src.empty && src.front.isDLangIdentifierCont){
			id ~= src.front.text;
			src.popFront;
		}
		
		if(isAttributeKeyword(id)) return false;
		
		if(!src.all!"a==' '") return false; //something els at the end
		
		return true;;
	}
	
	override void rearrange(){
		with(rearrangeHelper(skWhitespace, isStatement && keyword=="" ? 0 : 2, structuredColor(type).nullable)){
			
			//set subColumn bkColors
			if(isBlock || isPreposition) block.bkColor = mix(darkColor, brightColor, 0.125f);
			foreach(a; only(attributes, header)) if(a){
				a.bkColor = darkColor;
				if(a.empty) a.bkColor	 = mix(darkColor, brightColor, 0.75f);
			}

			if(isBlock){
				if(keyword!=""){ put(attributes); put(" "~keyword~" "); }
				if(hasHeader){ put(header); put(' '); } 
				put(opening); put(block); put(ending); put(' ');
			}else if(isPreposition){
				put(keyword~' ');
				if(hasHeader){ put('('); put(header); put(") "); }
				put(block); 
			}else{
				if(keyword!=""){ put(attributes); put(" "~keyword~" "); }
				if(hasHeader){ put(header); } 
				put(ending); put(' ');
			}
			
			super.rearrange;
		}
	}

}


// parsing helper functions ////////////////////////////////////////////////

dchar structuredCellToChar(Cell c){
	return c.castSwitch!(
		(Glyph	g) 	=> isDLangWhitespace(g.ch) ? ' ' : g.ch	,
		(CodeComment 	_) 	=> ' '	,
		(CodeString	_) 	=> '"'	,
		(CodeBlock	b) 	=> b.prefix[0]	,
	);
}

dstring extractThisLevelDString(CodeColumn col){
	
	static dstring rowToDString(CodeRow row){
		return row.subCells.map!structuredCellToChar.dtext;
	}
	
	//every chacacter or node maps to exactly one character (including newline)
	const str = col.rows.map!rowToDString.join("\n");
	return str;
}


alias 	removeFront = removeImpl!true, 
	removeBack = removeImpl!false;
	
auto removeImpl(bool fromFront, alias filter="true")(ref Cell[][] rows, size_t idx){
	
	struct RemovedCells{
		CodeComment[] comments;
		Cell lastCell;
		int newLineCount;
		int removedCount;
		bool overflow;
	}
	RemovedCells res;
	
	while(idx>0){
		if(rows.empty){ res.overflow = true; break; }
		
		static if(fromFront) 	auto actRow = rows.front; 
		else 	auto actRow = rows.back;
		
		if(!actRow.empty){  //opt: this is unoptimal but simple
			static if(fromFront) 	auto actCell = actRow.front; 
			else 	auto actCell = actRow.back;
			
			if(!actCell.unaryFun!filter) break;
			
			res.lastCell = actCell; //LOG(structuredCellToChar(actCell));
			if(auto cmt = cast(CodeComment) actCell) 
				res.comments ~= cmt;
			
			static if(fromFront) 	rows.front = rows.front[1..$];
			else	rows.back = rows.back[0..$-1];
			
			res.removedCount ++;
		}else{ 
			if(rows.length>1){
				static if(fromFront) 	rows = rows[1..$];
				else	rows = rows[0..$-1];
				
				res.newLineCount ++;
				res.removedCount ++;
			}else{ res.overflow = true; break; }
		}
		
		idx--;
	}
	return res;
}


struct TokenProcessor(Token){ // TokenProcessor /////////////////////////////////
	
	private static{ //Helpers functions
	
		auto strToToken(alias E)(string s){
			static assert(is(E==enum));
			static assert(E.none == 0);
			
			static string strFromToken(E)(E e) if(is(E==enum)){
				const a = e.text;
				if(a.startsWith('_')) return a[1..$];
				return a.symbolOfName;
			}
		
			enum	 members = [EnumMembers!E],
				 m = assocArray(members.map!(a => strFromToken(a)), members);
			if(auto a = s in m) return *a;
			return E.none;
		}
		
		struct TokenLocation(Token){ 
			int pos, len; Token token; 
			@property int end() const{ return pos+len; }
		} 
		
		auto findTokenLocations(Token)(dstring str){
			auto res = appender!(TokenLocation!Token[]);
			
			void tryAppend(dstring s, size_t pos){ 
				const token = strToToken!Token(s.text); //opt: this conversion from dstring to string is slow and only string identifiers and symbols are in the keywords and in the symbols.
				if(token != Token.none)
					res ~= TokenLocation!Token(cast(int)pos, cast(int)s.length, token);
			}
			
			static void categorizeDlangChar(dchar ch, ref char s/+state+/){
				if(s=='a'){
					if(!isDLangIdentifierCont(ch)) s = ' ';
				}else if(s=='0'){
					if(!isDLangNumberCont(ch)) s = ' ';
				}else{
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
			foreach(idx, dchar ch; str){ 
					
				//detect words and symbols
				auto lastState = actState;
				bool wordFound = false;
				categorizeDlangChar(ch, actState);
				if(lastState!=actState){
					if(actState=='a') actWord = "";  //note: this parser ignores numbers
					else if(lastState=='a') wordFound = true;
				}
				if(actState=='a') actWord ~= ch;  //note: this parser ignores numbers
				if(wordFound) tryAppend(actWord, idx-actWord.length); //note: no 'else' here!!!
				if(actState==' ') tryAppend(ch.dtext, idx); //symbol
			}
			if(actState=='a') tryAppend(actWord, str.length-actWord.length); //note: ignores numbers
				
			return res[];	
		}

	}
	
	
	CodeColumn col;
	const dstring srcDStr; //this-level symbolic dchars.  a=identifier, 0=number, space=whitespace or comment, \n is newLine. all other chars are preserved
	
	TokenLocation!Token[] tokens;
	
	TokenLocation!Token[] sentence; //fetchTokenSentence's result
	
	CodeRow[] dst;
	
	void appendNewLine(){ 
		dst ~= new CodeRow(col); 
	}
	
	void appendCell(Cell c){
		if(c){ 
			dst.back.subCells ~= c; 
			c.setParent = dst.back;
		}
	}
	
	int 	srcIdx;
	ivec2 srcPos;
	
	Cell[][] resultCells; //the temporal result of operations

	this(CodeColumn col){
		this.col = col;
		srcDStr = extractThisLevelDString(col);
		tokens = findTokenLocations!Token(srcDStr);
		
		appendNewLine;
	}
	
	~this(){ //finalize and refresh the column
		transferUntil(cast(int)srcDStr.length);
		
		col.subCells = cast(Cell[])dst;
		foreach(r; col.rows){
			r.refreshTabIdx;
			r.needMeasure;
		}
	}
	
	void fetchTokens(Token[] term)(){
		const idx = tokens.map!(t => term.canFind(t.token)).countUntil(true);
		enforce(idx>=0, "ECFT:" ~ tokens.text);
		sentence = tokens[0..idx+1];
		tokens = tokens[idx+1..$];
	}
	
	void fetchSingleToken(){
		enforce(tokens.length);
		sentence = tokens[0..1];
		tokens.popFront;
	}

	enum Operation { skip, transfer, fetch }
	
	void processSrc(Operation op, bool whitespaceAndCommentOnly = false)(int targetIdx){
		assert(srcIdx <= targetIdx);
		assert(srcPos.y.inRange(col.rows));
		assert(srcPos.x.inRange(0, col.rowCharCount(srcPos.y)));
		
		static if(op==Operation.fetch){ resultCells = null; resultCells.length = 1; }
		
		while(srcIdx < targetIdx){
			auto srcRow = col.rows[srcPos.y]; //opt: only fetch row when needed
			if(srcPos.x<srcRow.subCells.length){ //Cell
				auto cell = srcRow.subCells[srcPos.x];

				static if(whitespaceAndCommentOnly){
					bool isComment(){
						if(cast(CodeComment)cell) return true;
						if(auto g = cast(Glyph)cell) if(g.ch.isDLangWhitespace) return true;
						return false;
					}
					if(!isComment) break;
				}
				
				static if(op==Operation.transfer) appendCell(cell);
				static if(op==Operation.fetch) resultCells.back ~= cell;
				
				srcPos.x ++;
			}else{ //NewLine
				static if(op==Operation.transfer) appendNewLine;
				static if(op==Operation.fetch) resultCells.length ++;
				
				srcPos = ivec2(0, srcPos.y+1);
			}
			srcIdx++;
		}
	}
	
	alias transferUntil = processSrc!(Operation.transfer);
	alias skipUntil = processSrc!(Operation.skip);
	auto fetchUntil(int targetIdx){ processSrc!(Operation.fetch)(targetIdx); return resultCells; }
	void transferWhitespaceAndComments(){ processSrc!(Operation.transfer, true)(srcDStr.length.to!int); }
	
}

auto findCellPattern(string[] patterns)(ref Cell[][] cellRows){ //findCellPattern ////////////////////////////////
	
	struct Result{
		string pattern;
		size_t idx;
		bool opCast(T : bool)() const { return pattern!=""; }
	}
	Result res;
	
	foreach(pattern; patterns){
		auto src = cellRows.map!(row => row.map!structuredCellToChar).joiner([dchar('\n')]);
		size_t idx;
		bool match=true;
		foreach(dchar pch; pattern){
			void step(){ src.popFront; idx++; }
			if(pch==' '){
				while(!src.empty && src.front.among(' ', '\n')) step;
			}else{
				if(!src.empty && pch==src.front){ 
					step;
				}else{
					match = false; 
					break; 
				}
			}
		}
		if(match){
			res.pattern = pattern;
			res.idx = idx;
			break;
		}
	}
	
	return res;
}


Declaration[] extractPrepositions(ref Cell[][] cellRows){ // extractPrepositions ///////////////////////////////
	
	///remove from cellRows, return last removed cell
	Cell skip(size_t idx){ return cellRows.removeFront(idx).lastCell; }

	auto skipWhite(){ 
		with(cellRows.removeImpl!(true, c => c.structuredCellToChar==' ')(int.max)){
			//todo: handle newLineCount
			//todo: put the comments inside the ( )
			if(!comments.empty) WARN("There were skipped comments:\n"~comments.map!"a.sourceText".join('\n'));
		} 
	}
	
	Declaration[] res;
	
	void append(string keyword, Cell[][] paramCells){
		//write("	"~keyword~"  "); //todo
		res ~= new	Declaration(null, null, keyword, paramCells, new CodeColumn(null, []), ')');
	}
	
	while(auto match = cellRows.findCellPattern!prepositionPatterns) with(match){
		
		if(pattern[$-1]=='='){ //special terminal patterns.
			if(pattern=="debug ="){
				//it's a statement, not a preposition
			}else if(pattern=="else debug ="){ 
				skip(4);
				append("else", []);
				skipWhite;
			}else enforce(0, "Unhandled terminal preposition =");
			break;
		}else if(pattern[$-1]=='('){
			auto param = (cast(CodeBlock) skip(idx)); 
			assert(param && param.prefix=="(");
			append(pattern.withoutEnding(" ("), param.content.rows.map!(r => r.subCells).array);
		}else{
			skip(idx);
			append(pattern, []);
		}
		
		skipWhite;
	}
	
	return res;
}


struct DDeclarationRecord{
	string type;
	string header;
}
DDeclarationRecord[] dDeclarationRecords;


void processHighLevelPatterns(CodeColumn col_){ // processHighLevelPatterns ////////////////////////////////
	
	//enum DeclToken{ none, semicolon, colon, equal, question, block, _module, _import, _enum, _alias, _struct, _union, _class, _interface, _template, _unittest}
	
	mixin( format!"enum DeclToken{ none, %s }"(sentenceDetectionRules.map!"a[0].split".join.map!toSymbolEnum.join(", ")) );
	
	auto proc = TokenProcessor!DeclToken(col_);
	with(proc) with(DeclToken){
		
		Declaration receiver;
		void appendDeclaration(Declaration decl){
			if(receiver){
				auto row = receiver.block.rows.back;
				decl.setParent(row);
				row.appendCell(decl);
				
				if(decl.isPreposition) 	receiver = decl;
				else if(decl.isStatement || decl.isBlock) 	receiver = null;
				else if(decl.isSection) 	{ if(!decl.isLabel) receiver = null; /+note: A preposition can receive any number of labels, but only one attribute section. +/ } 
				else 	assert(0, "Unidentified declaration type");
			}else{
				proc.appendCell(decl);
				
				if(decl.isPreposition) receiver = decl;
			}
		}
		
		while(tokens.length){
			transferWhitespaceAndComments;
			
			const main = tokens.front;
			auto mainIsKeyword(){ return main.token.functionSwitch!"a.text.startsWith('_')"; }
			sw: switch(main.token){
				/+case semicolon, equal, question,   _module, _import, _alias:	fetchTokens!([semicolon	]); break;
				case block,    _template, _unittest:	fetchTokens!([block	]); break;
				case _enum, _struct, _union, _class, _interface: 	fetchTokens!([semicolon, block	]); break;
				case colon:	fetchTokens!([colon	]); break;+/
				
				static foreach(a; sentenceDetectionRules)
					mixin( format!q{ case %s: fetchTokens!([%s]); break sw; }(a[0].toSymbolEnumList, a[1].toSymbolEnumList));
					
				default:	fetchSingleToken;
			}
			const ending = sentence.back;
			
			const endingChar = ending.token.predSwitch(semicolon, ';', colon, ':', block, '}', ' ');
			const keyword = endingChar.among(';', '}') && mainIsKeyword ? main.token.text[1..$] : "";
			
			if(endingChar.among(';', '}', ':')){
				
				Cell[][] attrs;
				if(keyword != ""){
					attrs = fetchUntil(main.pos);
					skipUntil(main.end);
				}
				
				auto header = fetchUntil(ending.pos);
				
				CodeColumn block;
				if(endingChar.among(';', ':', '(')){
					skipUntil(ending.end);
				}else if(endingChar == '}'){
					auto container = fetchUntil(ending.end);
					block = (cast(CodeBlock) container.front.front).content;
				}else enforce(0, "Unhandled endingChar: "~endingChar.text.quoted);
				
				
				auto declarationChain = 	extractPrepositions(attrs.length ? attrs : header) ~
					new Declaration(null, attrs, keyword, header, block, endingChar);
				
				foreach(decl; declarationChain) appendDeclaration(decl);
				
				//collect statistics
				/+if(1) dDeclarationRecords ~= DDeclarationRecord(
					only(keyword, decl.isStatement ? ";" : decl.isSection ? ":" : decl.isBlock ? "}" : "").join,
					(decl.attributes.empty ? decl.header : decl.attributes).extractThisLevelDString.text
				);+/
				
				//print(dDeclarationRecords.back);
			}else{
				ERR("Unhandled token"~ending.text);
				transferUntil(ending.end);
			}
		
		}
	}
}


// Test codes ////////////////////////////////////////

unittest { hello; }public mixin template TestMixinTemplate(){ int a; int b; }
public template TestTemplate(){ int a; int b; }
public alias aaa = TestClass2;
public enum TestEnum = 5, TestEnum2 = 6;
public enum TestBlock : int {a = 5, b = a}
public struct TestStruct{ int a; int b; }
public union TestUnion{ int a; int b; }
public class TestClass1 { int a; int b; }
public class TestClass2 : TestClass1 { }
public interface TestInterface { int a(); int b(); }
public:
public{
	public int kkk;
	public int iii=5, jjj=6;
	const xxxx0 = 0x0.5p3;
	public int function() funcptrdecl;
	public int forward();
	public int hello(){ label1: label2: return 1 ? 2 : 3; }
}

struct OpaqueStruct; union OpaqueUnion; class OpaqueClass; interface OpaqueInterface;

static if(1==1):

struct SSSS1{
	static if(0) private: public:  //must encapsulate only "private:" 
}

version(abcd){
	//nothing
}else debug{

	int testStatements(){
		ivec2 v2 = {[1, 2]};
		with(TestClass2) static int i=5;
		with(TestClass1){
			if(1==2){} else {}
			if(1==2) sleep(1); else {}
			if(1==2) {} else sleep(1);
			if(1==2) {} else if(2==3) {} else sleep(1);
			
			for(int i; i++; i<10) writeln(i);
			label1: foreach(i; 0..10){ writeln(i); break label1; }
			static foreach_reverse(i; 0..10){{ writeln(i); continue; }}
			while(0){ }
			do sleep(1); while(0);
			do { sleep(1); } while(0);
			
			switch(5){
				case 6: break;
				case 7:..case 9: break;
				case 10, 11, 12: break;
				default: 
			}
			
			return typeof(return).max;
			
			static if(0) label1: label2: writeln; //if/else must encapsulate all the labels
			else label3: label4: { label5: }
		}
	}
	
	debug(blabla):
}else{
	
	auto testfun = (){
		//todo: process lambda's  =>{ or (){ , but not ={
		do sleep(1); while(0);
	};
}

debug debug = hehehe; else version = hahaha;

static if(0) /*skipped comment*/ //after a newline too
	static foreach(ch; ['a', 'b']): //this must be the last test
		mixin(format!"enum testEnum", ch, "='", ch, "';");
		pragma(msg, mixin("testEnum", ch));