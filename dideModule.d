module didemodule;

import het, het.ui, het.tokenizer, dideui, buildsys;

__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.
__gshared DefaultNewLine = "\r\n"; //this is used for saving source code

const clModuleBorder = clGray;
const clModuleText = clBlack;

// LOD //////////////////////////////////////////

struct LodStruct {
  float zoomFactor=1, pixelSize=1;
  int level;

  bool codeLevel      = true; //level 0
  bool moduleLevel    = false; //level 1/*code text visible*/, 2/*code text invisible*/
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
    if(forward) return cursor.pos.y>=cursor.codeColumn.lastRowIdx;
    else        return cursor.pos.y<0;
  }

  void popFront(){
    if(forward) cursor.moveRight_unsafe;
           else cursor.moveLeft_unsafe;
  }

  auto save(){ return this; }
}


// parent stuff: worldPos, parentChain ////////////////////////////

Container parentOf(Cell cell){
  if(auto r = cast(CodeRow   )cell) return r.parent;
  if(auto c = cast(CodeColumn)cell) return c.parent;
  if(auto n = cast(CodeNode  )cell) return n.parent;
  return null;
}

vec2 worldOuterPos(Cell cell){
  if(!cell) return vec2(0);
  if(auto parent = parentOf(cell)) return worldInnerPos(parent)+cell.outerPos;
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

auto parentChain(Cell act){
  Cell[] res;

  while(act){
    res ~= act;
    act = parentOf(act);
  }

  return res.retro.array;
}


/// A caret's graphical position in world coords
static struct CaretPos{ // CaretPos ///////////////////////////////////
  vec2 pos;
  float height=0;
  bool valid()const{ return height>0; }

  void draw(Drawing dr){
    if(valid)
      dr.vLine(pos, pos.y+height);
  }
}


struct TextCursor{  //TextCursor /////////////////////////////
//todo: to be able to edit and preserve the textcursor indices, textcursor should target objects, not indices. [codeRow, cell] would be the minimum. codeRow.subCellIdx(cell) and codeRow.index should be cached.
  CodeColumn codeColumn;

  @property bool valid() const{ return (codeColumn !is null) && pos.x>=0 && pos.y>=0; }

  ivec2 pos;
  float desiredX=0; //used for up down movement, after left right movements.

  int opCmp    (in TextCursor b) const{ return cmpChain(cmp(cast(long)cast(void*)codeColumn, cast(long)cast(void*)b.codeColumn), cmp(pos.y, b.pos.y), cmp(pos.x, b.pos.x)); }
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
  enum home     = int.min,  end       = int.max,
       wordLeft = home+1 ,  wordRight = end-1  ;

  void moveRight(int delta){
    if(!delta) return;
    if(delta==home){
      const ltc = codeColumn.rows[pos.y].leadingTabCount;
      pos.x = pos.x>ltc ? ltc : 0; //first stop is right after leading tabs, then goes to 0
    }else if(delta==end){
      pos.x = codeColumn.rows[pos.y].cellCount;
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
    desiredX = pos.x<=0 ? 0 : codeColumn.rows[pos.y].subCells[pos.x-1].outerBounds.right;
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

  auto toReference(){
    TextCursorReference res;
    if(valid) if(auto row = codeColumn.getRow(pos.y)){
      res.path = row.parentChain;
      res.left  = row.subCells.get(pos.x-1);
      res.right = row.subCells.get(pos.x);
    }
    return res;
  }

}


/// Used to store a TextCursor temporarily. After editing operations these cursors can be converted back to normal cursora.
/// Also used to get a textual absolute path of the cursor location.
struct TextCursorReference{ // TextCursorReference ////////////////////////////////////
  Cell[] path;       //must end with a codeRow. Starts with a root container.  Normally: root module column row
  Cell left, right;  //(null, null) is valid. -> That is an empty row.

  bool valid() const{
    return path.length && cast(CodeRow)path.back;
  }

  bool exists(){
    if(!valid) return false;
    auto p = path;

    //Note: It goes from parent to child and searches child in parent.subCells[]. Fails at any error.

    auto parent = cast(Container)p.fetchFront;  if(!parent) return false;

    bool checkChild(Cell c){ return c && parent && parent.subCellIndex(c)>=0; }

    do{
      auto act = cast(Container)p.fetchFront;
      if(!checkChild(act)) return false;
      parent = act;
    }while(p.length);

    return (!left && !right) //this means that the row was empty and the caret is at the beginning od the row.
           || checkChild(left) || checkChild(right);
  }

  string toString(){
    if(!valid) return "";

    auto p = path;
    string res;

    Container parent = null;
    do{
      auto act = cast(Container)p.fetchFront;
      if(!act){ res ~= "?NULL?"; break; }

      if(!parent){ //root element
        if(auto cntr=cast(Container)act){
          res ~= ""; //todo: expect Module after this
        }else{
          res ~= format!"?UNKNOWN_ROOT:%s?"(typeid(act).name); break;
        }
      }else{ //subsequent elements
        auto idx = parent.subCellIndex(act);
        if(idx<0){ res ~= format!"?LOST:%s?"((typeid(act).name)); break; }

        if(auto col = cast(CodeColumn)act){
          res ~= format!"[%d].Col"(idx); //todo: expect codeRow after this
        }else if(auto row = cast(CodeRow)act){
          res ~= format!"[%d].Row"(idx); //todo: expect codeColumn or codeNode after this
        }else if(auto mod = cast(Module)act){
          res ~= mod.file.fullName;      //todo: except codecolumn after this
        }else{
          res ~= format!"?UNKNOWN:%s?"(typeid(act).name); break;  //todo: CodeNode handling
        }
      }

      parent = act;
    }while(p.length);

    //this special processing is for the caret. Decide the idx from the left and right cells.
    if(!left && !right) res ~= "[0]";
    else{
      const leftIdx  = left  ? parent.subCellIndex(left ) : -1;
      const rightIdx = right ? parent.subCellIndex(right) : -1;

      auto idx = -1;
      if     (rightIdx>=0) idx = rightIdx; //select one valid
      else if(leftIdx >=0) idx = leftIdx+1; //add 1, because it's on the left side of the caret!

      if(idx>=0) res ~= format!"[%d]"(idx);
      else       res ~= format!"?LOST_LR?";
    }

    return res;
  }

  TextCursor fromReference(){
    TextCursor res;

    if(exists && path.length>=2)
    if(auto col = cast(CodeColumn)path[$-2])
    if(auto row = cast(CodeRow)path[$-1]){
    if(row.parent is col)
      res.codeColumn = col;
      res.pos.y = row.index;
      res.pos.x = 0;
      void calcDesiredX(){ res.desiredX = row.localCaretPos(res.pos.x).pos.x; }
      if(right){
        res.pos.x = row.subCellIndex(right);
        calcDesiredX;
      }else if(left){
        res.pos.x = row.subCellIndex(left);
        if(res.pos.x>=0){
          res.pos.x++;
          calcDesiredX;
        }
      }
    }

    return res.valid ? res : TextCursor.init;
  }
}

struct TextSelection{ //TextSelection ///////////////////////////////
  TextCursor[2] cursors;

  ref caret(){ return cursors[1]; }
  ref const caret(){ return cursors[1]; }

  auto codeColumn(){ return cursors[0].codeColumn; }

  @property bool valid() const{ return cursors[].map!"a.valid".all && cursors[0].codeColumn is cursors[1].codeColumn; }

  @property auto start() const{ return min(cursors[0], cursors[1]); }
  @property auto end  () const{ return max(cursors[0], cursors[1]); }

  @property bool isZeroLength() const{ return cursors[0]==cursors[1]; }
  @property bool isSingleLine() const{ return cursors[0].pos.y==cursors[1].pos.y; }
  @property bool isMultiLine() const{ return !isSingleLine; }

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

      //if it is only a left/right move, then stop at the end of the selection.
      if(!delta.y && delta.x){
        if(delta.x.among(TextCursor.wordLeft, TextCursor.wordRight)) delta.x = 0; //wordLeft/wordRight stops at the end of the selection
        else delta.x -= sign(delta.x); //normal left/right also wordLeft/wordRight stops at the end of the selection
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
            auto g = row.glyphs[crsr.pos.x];
            if(g){
              res ~= g.ch;
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

  auto toReference(){
    return TextSelectionReference([cursors[0].toReference, cursors[1].toReference]);
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

bool touches(TextSelection a, TextSelection b){

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
  auto res = TextSelection([min(a.start, b.start), max(a.end, b.end)]);
  if(backward) swap(res.cursors[0], res.cursors[1]);
  return res;
}

TextSelection[] merge(TextSelection[] arr){
  auto sorted = arr.sort.array;  //opt: on demand sorting

  arr = [];
  foreach(a; sorted){
    if(arr.length && touches(a, arr.back)){
      arr.back = merge(a, arr.back);
    }else{
      arr ~= a;
    }
  }

  return arr;
}

string sourceText(TextSelection[] ts){
  return ts
    .filter!"a.valid && !a.isZeroLength"
    .array.sort.array      //opt: on demand sorting
    .map!"a.sourceText"
    .join(DefaultNewLine);
}

bool hitTest(TextSelection[] ts, vec2 p){
  return ts.map!(a => a.hitTest(p)).any; //todo: this should be in the draw routine with automatic mouse hittest
}


struct TextSelectionReference{ // TextSelectionReference //////////////////////////////
  TextCursorReference[2] cursors;

  TextSelection fromReference(){
    auto res = TextSelection([cursors[0].fromReference, cursors[1].fromReference]);
    return res.valid ? res : TextSelection.init;
  }
}


/// CodeRow ////////////////////////////////////////////////

class CodeRow: Row{
  CodeColumn parent;

  int index(){ return parent.subCellIndex(this); }

  auto glyphs() { return subCells.map!(c => cast(Glyph)c); } //can return nulls
  auto chars()  { return glyphs.map!"a ? a.ch : '\u26A0'"; }
  string sourceText() { return chars.to!string; }

  private static bool isSpace(Glyph g){ return g && g.ch==' ' && g.syntax.among(0/*whitespace*/, 9/*comment*/)/+don't count string literals+/; }
  private auto spaces() { return glyphs.map!(g => isSpace(g)); }
  private auto leadingSpaces(){ return glyphs.until!(g => !isSpace(g)); }

  int leadingTabCount(){
    static bool isTab(Glyph g){ return g && g.ch=='\t' /+any syntax counts for tabs +/; }
    return glyphs.countUntil!(g => !isTab(g)).to!int;
  }

  this(CodeColumn parent_){
    parent = enforce(parent_);
    id.value = this.identityStr;

    padding = "0 4";

    flags.wordWrap       = false;
    flags.clipSubCells   = true;
    flags.cullSubCells   = true;
    flags.rowElasticTabs = false;
    flags.dontHideSpaces = true;
    bkColor = clCodeBackground;
    outerHeight = DefaultFontHeight;
    super();
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
    this.appendCode(line, syntax, (ubyte s){ applySyntax(style, s); }, style, DefaultIndentSize);

    adjustCharWidths;
  }

  protected{
    static immutable float NormalSpaceWidth  = 7.25f, //same as '0'..'9' and +-_
                           LeadingSpaceWidth = NormalSpaceWidth;

    void adjustCharWidths(){

      bool isLeading = true;
      foreach(g; glyphs) if(g){
        if(isSpace(g)){
          g.outerWidth = isLeading ? LeadingSpaceWidth
                                   : NormalSpaceWidth;
        }else{
          isLeading = false;

          //non-leading char width modifications
          if(g.syntax==5 && g.ch!='.'  //number except '.'
          || g.ch.among('+', '-', '_') //symbols next to numbers
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
      assert(xStart<=xTab                                 , "invalid xStart, xTab");
      assert(xStart>=0                                    , "xStart out of range");
      assert(xTab<subCells.length                         , "xTab out of range");
      assert(glyphs[xStart..xTab+1].all!(g => isSpace(g)) , "All must be spaces");
      assert(tabCount <= xTab-xStart+1                    , "tabCount too much.");

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

  override void draw(Drawing dr){
    if(lod.level>1){
      const lsCnt = glyphs.until!(g => !g || !g.ch.among(' ', '\t')).walkLength; //opt: this should be memoized
      if(lsCnt<subCells.length){
        const r = bounds2(subCells[lsCnt].outerPos, subCells.back.outerBottomRight) + innerPos;
        dr.color = avg(glyphs[lsCnt].bkColor, glyphs[lsCnt].fontColor);
        dr.fillRect(r.inflated(vec2(0, -r.height/4)));
      }
    }else{
      super.draw(dr);

      /*dr.fontHeight = 18;
      dr.color = clFuchsia;
      dr.textOut(outerPos.x, outerPos.y, getIndex.text);*/
    }
  }

  bounds2 newLineBounds(){
    auto bnd = bounds2(vec2(0), vec2(max(innerHeight, DefaultFontHeight))*vec2(.5f, 1));
    if(cellCount)
      bnd += vec2(subCells.back.outerRight, 0);
    //todo: vertical align
    return bnd;
  }

}


class CodeColumn: Column{ // CodeColumn ////////////////////////////////////////////
  //note: this is basically the CodeBlock
  Container parent;

  auto const rows(){ return cast(CodeRow[])subCells; }
  int rowCount() const{ return cast(int)subCells.length; }
  int lastRowIdx() const{ return rowCount-1; }
  int lastRowLength() const{ return rows.back.cellCount; }

  auto getRow(int rowIdx){ return rowIdx.inRange(subCells) ? rows[rowIdx] : null; }

  int rowCharCount(int rowIdx){
    if(auto row = getRow(rowIdx)) return row.cellCount;
    return 0;
  }

  string rowSourceText(int rowIdx){
    if(auto row = getRow(rowIdx)) return row.sourceText;
    return "";
  }

  @property string sourceText() { return rows.map!(r => r.sourceText).join(DefaultNewLine); }  // \r\n is the default in std library

  enum defaultSpacesPerTab = 4; //default in std library
  int spacesPerTab = defaultSpacesPerTab; //autodetected on load

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


  this(Container parent){
    this.parent = parent;
    id.value = this.identityStr;

    flags.wordWrap     = false;
    flags.clipSubCells = true;
    flags.cullSubCells = true;

    flags.columnElasticTabs = true;
    bkColor = clCodeBackground;

  }

  this(Container parent, SourceCode src){
    this(parent);
    id = "CodeColumns:"~src.file.fullName;
    set(src);
  }

  this(Container parent, string str){
    this(parent, scoped!SourceCode(str));
  }

  void set(SourceCode src){
    clearSubCells;

    src.foreachLine( (int idx, string line, ubyte[] syntax) => appendCell(new CodeRow(this, line, syntax)) );
    if(subCells.empty)
      appendCell(new CodeRow(this, "", null)); //always must have at least an empty row

    makeElasticTabs;

    spacesPerTab = src.whiteSpaceStats.detectIndentSize(DefaultIndentSize);
    rows.each!(row => row.convertLeadingSpacesToTabs(spacesPerTab));

    measure;
  }

  void makeElasticTabs(){
    //const t0=QPS; scope(exit) print(QPS-t0);

    bool detectTab(int x, int y){
      if(cast(uint)y >= rowCount) return false;
      with(rows[y]){
        if(cast(uint)x >= cellCount) return false;
        return spaces[x] && (x+1 >= cellCount || !spaces[x+1]);
      }
    }

    bool[long] visited;

    static struct TabInfo{ int y, xStart, xTab; }
    TabInfo[] newTabs;

    void flood(int x, int y, bool canGoUp, bool canGoDown, lazy size_t leadingSpaceCount){
      if(!canGoDown && !canGoUp) return;

      //assume: x, y is a valid tab position
      if(visited.get(x+(long(y)<<32))) return;

      int y0 = y;  if(canGoUp  ) while(y0 > 0          && detectTab(x, y0-1)) y0--;
      int y1 = y;  if(canGoDown) while(y1 < rowCount-1 && detectTab(x, y1+1)) y1++;

      int maxLen = 0, minLen = int.max;
      if(y0<y1) foreach(yy; y0..y1+1) with(rows[yy]) {
        visited[x+(long(yy)<<32)] = true;

        int x0 = x; while(x0 > 0 && spaces[x0-1]) x0--;
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
          int xStart = x; while(xStart > xStartMin && spaces[xStart-1]) xStart--;
          int xTab   = x+1-minLen;

          newTabs ~= TabInfo(yy, xStart, xTab);

          //if(xStartMin>0) print(lines[yy].text, "         ", newTabs.back);
        }
      }
    }

    //scan through all the rows and initiate floodFills
    foreach(y, row; rows) with(row){
      int st = 0;
      foreach(isSpace, len; spaces.group){
        const en = st + cast(int)len;

        if(isSpace && st>0){
          bool canGoUp, canGoDown;

          if(len==1 && st>0 && chars[st-1].among('[', '(')) canGoDown = true; //todo: the tabs below this one should inherit the indent of this first line
          else                                              canGoUp = canGoDown = canGoDown = len>=2;

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

  this(LabelType labelType, vec2 pos, string str, float parentWidth=0){
    auto ts = tsNormal;
    ts.fontColor = clWhite;
    ts.bkColor = clBlack;
    ts.transparent = true;

    bool alignRight;
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
    if(alignRight){
      assert(parentWidth);
      outerX = parentWidth-outerWidth;
    }
  }

}

// FolderLabel //////////////////////////////////

auto cachedFolderLabel(string folderPath){
  return ImStorage!Label.access(srcId(genericId(folderPath)), new Label(LabelType.folder, vec2(0), Path(folderPath).name));
}

// CodeNode //////////////////////////////////////////
class CodeNode : Container{
  Container parent;

  this(Container parent){
    this.parent = parent;
  }

  ~this(){
    parent = null;
  }
}

/// Module ///////////////////////////////////////////////
class Module : CodeNode{ //this is any file in the project
  Container parent; //to be able to have a root.
  //todo: should be descended from a common CodeCode class.
  File file;

  DateTime loaded, saved, modified;

  CodeColumn code;
  Container overlay;

  ModuleBuildState buildState;

  size_t linesOfCode(){ return code.subCells.length; } //todo: update this
  size_t sizeBytes;  //todo: update this
  bool isMainExe, isMainDll, isMainLib, isMain;

  void reload(){
    clearSubCells;

    modified = file.modified;
    sizeBytes = file.size;

    overlay = new Container;
    overlay.id = "Overlay:"~file.fullName;
    with(overlay.flags){
      noHitTest = true;
      dontSearch = true;
      dontLocate = true;
      noBackground = true;
      //clipSubCells = false;
    }

    void measureAndPropagateCodeSize(){ code.measure; innerSize = code.outerSize; overlay.outerSize = code.outerSize; }

    isMain = isMainExe = isMainDll = isMainLib = false;

    if(file.extIs(".err")){

      code = new CodeColumn(this);
      code.padding = "1";

      //foreach(line; file.readLines) code.append(new CodeRow(line));

      //todo: this is only working when it's called from update() only!!!!
      //auto br = (cast(FrmMain)mainWindow).buildResult;
      //auto markerLayerHideMask = (cast(FrmMain)mainWindow).workspace.markerLayerHideMask;

      import dide2; //todo: should not import main module.
      auto buildResult = global_getBuildResult;
      auto markerLayerHideMask = global_getMarkerLayerHideMask;

/*  string dumpMessage(in BuildMessage bm, string indent=""){
    string res = indent ~ bm.text ~"\n";

    foreach(const v; messages.values)
      if(v.parentLocation == bm.location)
        res ~= dumpMessage(v, indent~"  ");

    return res;
  }*/
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

        //code.append(im.removeLastContainer); //a nasty trick to be able to call msg.UI;


      measureAndPropagateCodeSize;

      overlay.appendCell(new Label(LabelType.module_, vec2(0, -255), file.name/*WithoutExt*/));
    }else{
      auto src = new SourceCode(this.file);

      bool isMainSomething(string ext)(){
        return src && src.tokens.length && src.tokens[0].isComment && sameText(src.tokens[0].source.stripRight, "//@"~ext);
      }
      isMainExe = isMainSomething!"exe";
      isMainDll = isMainSomething!"dll";
      isMainLib = isMainSomething!"lib";
      isMain = isMainExe || isMainDll || isMainLib;

      code = new CodeColumn(this, src);

      measureAndPropagateCodeSize;

      overlay.appendCell(new Label(LabelType.module_, vec2(0, -255), file.name/*WithoutExt*/));
      foreach(k; src.bigComments.keys.sort)
        overlay.appendCell(new Label(LabelType.subRegion, vec2(0, /+k*18+/ code.subCells[k-1].outerPos.y), src.bigComments[k], overlay.innerWidth));
    }

    appendCell(enforce(code));
    appendCell(enforce(overlay));
  }


  this(Container parent){
    super(parent);

    flags.cullSubCells = true;

    bkColor = clModuleBorder;
    this.setRoundBorder(16);
    padding = "8";

    loaded = now;
  }

  this(Container parent, File file_){
    this(parent);

    file = file_.actualFile;
    id = "Module:"~this.file.fullName;

    reload;
  }

  override void draw(Drawing dr){
    overlay.flags.hidden = lod.codeLevel;
    if(overlay.subCells.length)
      (cast(.Container)(overlay.subCells[0])).flags.hidden = !lod.moduleLevel;

    super.draw(dr);
  }

  override void onDraw(Drawing dr){
    /*if(lod.moduleLevel){
      dr.color = clBlack;
      dr.alpha = .33;
      dr.fillRect(0, 0, innerWidth, innerHeight);
      dr.alpha = 1;
    }*/
  }
}

