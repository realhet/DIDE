//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId

//@release
///@debug

//todo: buildSystem: the caches (objCache, etc) has no limits. Onli a rebuild clears them.

import het, het.keywords, het.tokenizer, het.ui, het.dialogs;
import buildsys, core.thread, std.concurrency;

__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.

const clModuleBorder = clGray;
const clModuleText = clBlack;

// utils ////////////////////////////////////////

size_t allocatedSize(in Cell c){
  if(!c) return 0;
  import core.memory;
  size_t res = GC.sizeOf(cast(void*)c);
  if(auto co = cast(const Container)c){
    res += co.subCells.map!(allocatedSize).sum;
  }
  return res;
}


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

void setRoundBorder(Container cntr, float borderWidth){ with(cntr){
  border.width = borderWidth;
  border.color = bkColor;
  border.inset = true;
  border.borderFirst = true;
}}

void RoundBorder(float borderWidth){ with(im){
  border.width = borderWidth;
  border.color = bkColor;
  border.inset = true;
  border.borderFirst = true;
}}

//! UI ///////////////////////////////

static void UI_OuterBlockFrame(T = .Row)(RGB color, void delegate() contents){ with(im) //UI_OuterBlockFrame///////////////////////////
  Container!T({
    margin = "0.5";
    padding = "1.5";
    style.bkColor = bkColor = color;
    style.fontColor = blackOrWhiteFor(color);
    flags.yAlign = YAlign.top;
    RoundBorder(8);
    if(contents) contents();
  });
}

static void UI_InnerBlockFrame(T = .Row)(RGB color, RGB fontColor, void delegate() contents){ with(im) //UI_InnerBlockFrame////////////////////////
  Container!T({
    margin = "0";
    padding = "0 4";
    style.bkColor = bkColor = color;
    style.fontColor = fontColor;
    flags.yAlign = YAlign.top;
    RoundBorder(8);
    if(contents) contents();
  });
}

static void UI_BuildMessageContents(CodeLocation location, string title, void delegate() contents){ with(im){ //UI_BuildMessageContents///////////////////////////////
  location.UI;
  if(title!="") Text(bold(" "~title~" "));
  if(contents) contents();
}}

static void UI_ConsoleTextBlock(string contents){ with(im) //UI_ConsoleTextBlock/////////////////////////////////////
  UI_InnerBlockFrame(clBlack, clWhite, {
    style.font = "Lucida Console";
    Text(contents); //todo: Use codeRow here for optimized LOD. Refer to -> UI_BuildMessageTextBlock()
  });
}

static void UI_CompilerOutput(File file, string text){ //UI_CompilerOutput/////////////////////////////////
  UI_OuterBlockFrame(RGB(0xD0D0D0), {
    UI_BuildMessageContents(CodeLocation(file), "Output:", {
      UI_ConsoleTextBlock(text);
    });
  });
}

void UI(in CodeLocation cl){ with(cl) with(im) //CodeLocation.UI //////////////////////
  UI_InnerBlockFrame(clSilver, clBlack, {
    auto ext = file.ext;
    if(ext!="") Text(tag(format!`img "icon:\%s" height=%f`(ext, fh-2)));

    Text(file.fullName);
    if(column) Text(format!("(%s,%s)")(line, column));
          else if(line) Text(format!("(%s)")(line));
  });
}


void UI(in BuildSystemWorkerState bsws) { with(bsws) with(im){ //BuildSystemWorkerState.UI //////////////////////
  Row({
    width = 6*fh;
    Row({
      if(building) style.fontColor = mix(style.fontColor, style.bkColor, blinkf);
      Text(cancelling ? "Cancelling" : building ? "Building" : "BuildSys Ready");
    });
    Row({ flex=1; flags.hAlign = HAlign.right;
      if(building && !cancelling && totalModules)
        Text(format!"%d(%d)/%d"(compiledModules, inFlight, totalModules));
      else if(building && cancelling){
        Text(format!"\u2026%d"(inFlight));
      }
    });
  });
}}

void UI_BuildMessageTextBlock(string message, RGB clFont){ //UI_BuildMessageTextBlock//////////////////////////////
  //Apply syntax highlight on the texts between `` quotes.
  auto isCode = new bool[message.length];
  {
    bool inCode = false;
    size_t i;
    foreach(ch; message.byChar){
      if(!inCode){
        if(ch=='`') inCode=true;
      }else{
        if(ch=='`') inCode=false; else isCode[i]=true;
      }
      i++;
    }
  }

  auto codeOnly = message.dup;
  foreach(i, b; isCode) if(!b) codeOnly.ptr[i] = ' ';

  auto sc = scoped!SourceCode(cast(string)codeOnly);

  void appendLine(int idx){ with(im){
    auto cr = cast(CodeRow)actContainer;
    auto r = sc.getLineRange(idx);
    cr.set(message[r[0]..r[1]], sc.syntax[r[0]..r[1]]);
    auto g = cr.glyphs;
    foreach(i, b; isCode[r[0]..r[1]]) if(!b) g[i].fontColor = clFont;
  }}

  const lineCount = sc.lineCount;
  if(lineCount>=1){
    with(im) UI_InnerBlockFrame!CodeColumn(clCodeBackground, clFont, {
      foreach(i; 0..lineCount) Container!CodeRow({ appendLine(i); });
    });
  }
}


void UI(in BuildMessage msg, BuildResult br){ UI(msg, br.subMessagesOf(msg.location)); }

void UI(in BuildMessage msg, in BuildMessage[] subMessages){ with(msg) with(im) // BuildMessage.UI ////////////////////////////
  UI_OuterBlockFrame(type.color, {
    UI_BuildMessageContents(location, parentLocation ? "\u2026" : type.to!string.capitalize~":", {
      const clFont = avg(type.color, clWhite);

      UI_BuildMessageTextBlock(message, clFont);

      foreach(sm; subMessages){
        Text("\n    "); sm.UI([]);
      }
    });
  });
}



/// CodeRow ////////////////////////////////////////////////
class CodeRow: Row{
  CodeColumn parent;

  int getIndex(){ foreach(i, c; parent.subCells) if(c is this) return i.to!int; return -1; }

  auto glyphs() { return subCells.map!(c => cast(Glyph)c); } //can return nulls
  auto chars()  { return glyphs.map!"a ? a.ch : '\u26A0'"; }
  string sourceText() { return chars.to!string; }

  int charCount(){ return cast(int)subCells.length; }

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

  override void draw(Drawing dr){
    if(lod.level>1){
      const lsCnt = glyphs.until!(g => !g || !g.ch.among(' ', '\t')).walkLength; //opt: this should be memoized
      if(lsCnt<subCells.length){
        const r = bounds2(subCells[lsCnt].outerPos, subCells[$-1].outerBottomRight) + innerPos;
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

}


class CodeColumn: Column{ // CodeColumn ////////////////////////////////////////////
  //note: this is basically the CodeBlock

  auto const rows(){ return cast(CodeRow[])subCells; }
  int rowCount() const{ return cast(int)subCells.length; }
  int lastRowIdx() const{ return rowCount-1; }
  int lastRowLength() const{ return rows[$-1].charCount; }
  int rowCharCount(int rowIdx) const{ if(rowIdx>=0 && rowIdx<rowCount) return rows[rowIdx].charCount; else return 0; }
  @property string sourceText() { return rows.map!(r => r.sourceText).join("\r\n"); }  // \r\n is the default in std library

  enum defaultSpacesPerTab = 4; //default in std library
  int spacesPerTab = defaultSpacesPerTab; //autodetected on load

  //index, location calculations
  int maxIdx(){ //inclusive end position
    assert(rowCount>0);
    return rows.map!(r => r.charCount + 1/+newLine+/).sum - 1/+except last newLine+/;
  }

  ivec2 idx2pos(int idx){
    if(idx<0) return ivec2(0); //clamp to min

    const rowCount = this.rowCount;
    assert(rowCount>0, "One row must present even when the CodeColumn is empty.");
    int y;
    while(1){
      const actRowLen = rows[y].charCount+1;
      if(idx<actRowLen){
        return ivec2(idx, y);
      }else{
        y++;
        if(y<rowCount){
          idx -= actRowLen;
        }else{
          return ivec2(rows[rowCount-1].charCount, rowCount-1); //clamp to max
        }
      }
    }
  }

  int pos2idx(ivec2 p){
    if(p.y<0) return 0; //clamp to min
    if(p.y>=rowCount) return maxIdx; //lamp to max
    return rows[0..p.y].map!(r => r.charCount+1).sum + clamp(p.x, 0, rows[p.y].charCount);
  }


  this(){
    id.value = this.identityStr;

    flags.wordWrap     = false;
    flags.clipSubCells = true;
    flags.cullSubCells = true;

    flags.columnElasticTabs = true;
    bkColor = clCodeBackground;

  }

  this(SourceCode src){
    this();
    id = "CodeColumns:"~src.file.fullName;
    set(src);
  }

  this(string str){
    this(scoped!SourceCode(str));
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
        if(cast(uint)x >= charCount) return false;
        return spaces[x] && (x+1 >= charCount || !spaces[x+1]);
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

          //if(xStartMin>0) print(lines[yy].text, "         ", newTabs[$-1]);
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
    auto cc = scoped!CodeColumn(src);
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


/// Module ///////////////////////////////////////////////
class Module : Container{ //this is any file in the project
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

      code = new CodeColumn;
      code.padding = "1";

      //foreach(line; file.readLines) code.append(new CodeRow(line));

      //todo: this is only working when it's called from update() only!!!!
      auto br = (cast(FrmMain)mainWindow).buildResult;
      auto markerLayerHideMask = (cast(FrmMain)mainWindow).workspace.markerLayerHideMask;

/*  string dumpMessage(in BuildMessage bm, string indent=""){
    string res = indent ~ bm.text ~"\n";

    foreach(const v; messages.values)
      if(v.parentLocation == bm.location)
        res ~= dumpMessage(v, indent~"  ");

    return res;
  }*/
      foreach(file; br.remainings.keys.sort){
        auto pragmas = br.remainings[file];
        if(pragmas.length) code.append({ UI_CompilerOutput(file, pragmas.join('\n')); });
      }

      with(im) code.append({
        foreach(loc; br.messages.keys.sort){
          auto msg = br.messages[loc];
          if(msg.parentLocation) continue;
          if((1<<msg.type) & markerLayerHideMask) continue;
          msg.UI(br.subMessagesOf(msg.location));
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

      code = new CodeColumn(src);

      measureAndPropagateCodeSize;

      overlay.appendCell(new Label(LabelType.module_, vec2(0, -255), file.name/*WithoutExt*/));
      foreach(k; src.bigComments.keys.sort)
        overlay.appendCell(new Label(LabelType.subRegion, vec2(0, /+k*18+/ code.subCells[k-1].outerPos.y), src.bigComments[k], overlay.innerWidth));
    }

    appendCell(enforce(code));
    appendCell(enforce(overlay));
  }


  this(){
    flags.cullSubCells = true;

    bkColor = clModuleBorder;
    this.setRoundBorder(16);
    padding = "8";

    loaded = now;
  }

  this(File file_){
    this();

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


struct SelectionManager2(T : Container){ // SelectionManager2 ///////////////////////////////////////////////
  //this uses Containers. flags.selected, flags.oldSelected

  bounds2 getBounds(T item){ return item.outerBounds; }

  enum MouseOp { idle, move, rectSelect }

  MouseOp mouseOp;

  enum SelectOp { none, add, sub, toggle, clearAdd }
  SelectOp selectOp;

  vec2 dragSource;
  bounds2 dragBounds;

  bounds2 selectionBounds(){
    if(mouseOp == MouseOp.rectSelect) return dragBounds;
                                 else return bounds2.init;
  }

  //these are calculated after update. No notifications, just keep calling update frequently
  T hoveredItem;

  void update(bool mouseEnabled, View2D view, T[] items){

    void selectNone()           { foreach(a; items) a.flags.selected = false; }
    void selectOnly(T item)     { selectNone; if(item) item.flags.selected = true; }
    void selectHoveredOnly()    { selectOnly(hoveredItem); }
    void saveOldSelected()      { foreach(a; items) a.flags.oldSelected = a.flags.selected; }

    // acquire mouse positions
    auto mouseAct = view.mousePos;
    auto mouseDelta = mouseAct-view.mouseLast;

    const LMB          = inputs.LMB.down,
          LMB_pressed  = inputs.LMB.pressed,
          LMB_released = inputs.LMB.released,
          Shift        = inputs.Shift.down,
          Ctrl         = inputs.Ctrl.down;

    const modNone       = !Shift && !Ctrl,
          modShift      =  Shift && !Ctrl,
          modCtrl       = !Shift &&  Ctrl,
          modShiftCtrl  =  Shift &&  Ctrl;

    const inputChanged = mouseDelta || inputs.LMB.changed || inputs.Shift.changed || inputs.Ctrl.changed;

    // update current selection mode
    if(modNone      ) selectOp = SelectOp.clearAdd;
    if(modShift     ) selectOp = SelectOp.add;
    if(modCtrl      ) selectOp = SelectOp.sub;
    if(modShiftCtrl ) selectOp = SelectOp.toggle;

    // update dragBounds
    if(LMB_pressed) dragSource = mouseAct;
    if(LMB        ) dragBounds = bounds2(dragSource, mouseAct).sorted;

    //update hovered item
    hoveredItem = null;
    if(mouseEnabled) foreach(item; items) if(getBounds(item).contains!"[)"(mouseAct)) hoveredItem = item;

    if(LMB_pressed && mouseEnabled){ // Left Mouse pressed //
      if(hoveredItem){
        if(modNone){ if(!hoveredItem.flags.selected) selectHoveredOnly;  mouseOp = MouseOp.move; }
        if(modShift || modCtrl || modShiftCtrl) hoveredItem.flags.selected = !hoveredItem.flags.selected;
      }else{
        mouseOp = MouseOp.rectSelect;
        saveOldSelected;
      }
    }

    {// update ongoing things //
      if(mouseOp == MouseOp.rectSelect && inputChanged){
        foreach(a; items) if(dragBounds.contains!"[]"(getBounds(a))){
          final switch(selectOp){
            case SelectOp.add, SelectOp.clearAdd : a.flags.selected = true ;          break;
            case SelectOp.sub                    : a.flags.selected = false;          break;
            case SelectOp.toggle                 : a.flags.selected = !a.flags.oldSelected; break;
            case SelectOp.none                   :                                break;
          }
        }else{
          a.flags.selected = (selectOp == SelectOp.clearAdd) ? false : a.flags.selected;
        }
      }
    }

    if(mouseOp == MouseOp.move && mouseDelta){
      foreach(a; items) if(a.flags.selected){
        a.outerPos += mouseDelta;

        //todo: jelezni kell valahogy az elmozdulast!!!
        /*static if(is(a.cachedDrawing))
          a.cachedDrawing.free;*/
      }
    }


    if(LMB_released){ // left mouse released //

      //...                                               ou

      mouseOp = MouseOp.idle;
    }
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
  CodeColumn codeColumn;
  ivec2 pos;
  bool forward=true;

  @property dchar front() const{ return charAt(codeColumn, pos); }
  @property bool empty() const{
    if(forward) return codeColumn && TextCursor(pos)>=TextCursor(ivec2(codeColumn.lastRowLength, codeColumn.lastRowIdx));
    else        return codeColumn && TextCursor(pos)< TextCursor(ivec2(0));
  }

  void popFront(){
    if(forward){
      pos.x++;
      if(pos.x>codeColumn.rowCharCount(pos.y)){
        pos.x=0;
        pos.y++;
      }
    }else{
      pos.x--;
      if(pos.x<0){
        pos.y--;
        pos.x=codeColumn.rowCharCount(pos.y);
      }
    }

    //not good because these are clamping.pos = codeColumn.idx2pos(codeColumn.pos2idx(pos)+(forward ? 1 : -1)); //opt: it's slow but simple
  }

  auto save(){ return this; }
}



struct TextCursor{  //TextCursor /////////////////////////////
  ivec2 pos;
  float desiredX=0; //used for up down movement, after left right movements.

  int opCmp    (in TextCursor b) const{ return (cmp(pos.y, b.pos.y)).cmpChain(cmp(pos.x, b.pos.x)); }
  bool opEquals(in TextCursor b) const{ return pos == b.pos; }

  void moveLeft(CodeColumn cc, long delta){ moveRight(cc, -delta); }
  void moveRight(CodeColumn cc, long delta){ moveRight(cc, delta.to!int); }

  //special delta units
  enum home     = int.min,  end       = int.max,
       wordLeft = home+1 ,  wordRight = end-1  ;

  void moveRight(CodeColumn cc, int delta){
    if(!delta) return;
    if(delta==home){
      const ltc = cc.rows[pos.y].leadingTabCount;
      pos.x = pos.x>ltc ? ltc : 0; //first stop is right after leading tabs, then goes to 0
    }else if(delta==end){
      pos.x = cc.rows[pos.y].charCount;
    }else if(delta==wordRight){
      const skip = CharFetcher(cc, pos, true)
                  .chain("\n\n"d) //extra stopping condition when no word boundary found
                  .slide(2)
                  .countUntil!(a => a.isWordBoundary || a.equal("\n\n"d)); //only stop at empty lines (that's 2 newline)
      moveRight(cc, skip+1);
    }else if(delta==wordLeft){
      const skip = CharFetcher(cc, pos, false)
                  .drop(1) //ignore the char at right hand side of the cursor
                  .chain("\n\n"d) //extra stopping condition when no word boundary found
                  .slide(2)
                  .countUntil!(a => a.isWordBoundary || a.drop(1).front=='\n'); //stop at every newline
      moveLeft(cc, skip+1);
    }else{
      pos = cc.idx2pos(cc.pos2idx(pos)+delta); //opt: it's slow but simple
    }
    desiredX = pos.x<=0 ? 0 : cc.rows[pos.y].subCells[pos.x-1].outerBounds.right;
  }

  void moveDown(CodeColumn cc, int delta){
    if(!delta) return;
    if(delta==home) pos.y = 0; //home
    else if(delta==end) pos.y = cc.rowCount-1; //end
    else pos.y = (pos.y+delta).clamp(0, cc.rowCount-1);

    //jump to desired x in actual row
    auto r = cc.rows[pos.y];
    pos.x = iota(r.charCount+1).map!(i => abs((i<=0 ? 0 : r.subCells[i-1].outerBounds.right)-desiredX)).minIndex.to!int;
  }

  void move(CodeColumn cc, ivec2 delta){
    if(!delta) return;
    if(delta==ivec2(home)){
      pos = ivec2(0); desiredX = 0; //this needed to skip the possible stop right after the leading tabs in the first line
    }else{
      moveDown (cc, delta.y);
      moveRight(cc, delta.x);
    }
  }
}

struct TextSelection{ //TextSelection
  CodeColumn codeColumn;
  TextCursor[2] cursors;
  auto ref caret(){ return cursors[1]; }

  @property auto start() const{ return min(cursors[0], cursors[1]); }
  @property auto end  () const{ return max(cursors[0], cursors[1]); }

  int opCmp    (in TextSelection b) const{ return cmp(cast(size_t)(cast(void*)codeColumn), cast(size_t)(cast(void*)b.codeColumn)).cmpChain(myCmp(start, b.start)).cmpChain(myCmp(end, b.end)); }
  bool opEquals(in TextSelection b) const{ return codeColumn==b.codeColumn && start==b.start && end==b.end; }

  void collapseToCaret(){ cursors[0] = cursors[1]; }

  void move(ivec2 delta){
    caret.move(codeColumn, delta);
    collapseToCaret;
  }

}

/// Workspace ///////////////////////////////////////////////
class Workspace : Container{ //this is a collection of opened modules
  File file; //the file of the workspace
  enum defaultExt = ".dide";

  Module[] modules;
  SelectionManager2!Module selectionManager;

  @STORED File mainModuleFile;
  @property Module mainModule(){ return findModule(mainModuleFile); }
  @property void mainModule(Module m){ enforce(modules.canFind(m), "Invalid module."); enforce(m.isMain, "This module can't be selected as main module."); mainModuleFile = m.file; }

  File[] openQueue;

  bool justLoadedSomething;
  bounds2 justLoadedBounds;

  bool searchBoxVisible = false;
  string searchText;

  struct MarkerLayer{
    const BuildMessageType type;
    Container.SearchResult[] searchResults;
    bool visible = true;
  }

  auto markerLayers = (() =>  [EnumMembers!BuildMessageType].map!MarkerLayer.array  )();
  //note: compiler drops weird error. this also works:
  //      Writing Explicit type also works:  auto markerLayers = (() =>  [EnumMembers!BuildMessageType].map!((BuildMessageType t) => MarkerLayer(t)).array  )();

  @STORED vec2[size_t] lastModulePositions;


  //Restrict convertBuildResultToSearchResults calls.
  size_t lastBuildStateHash;
  bool buildStateChanged;

  TextSelection[] textSelections;

  this(){
    flags.targetSurface = 0;
    flags.noBackground = true;
    fileDialog = new FileDialog(mainWindow.hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)");
  }

  @STORED @property{ //note: toJson: this can't be protected. But an array can (mixin() vs. __traits(member, ...).
    size_t markerLayerHideMask() const { size_t res; foreach(idx, const layer; markerLayers) if(!layer.visible) res |= 1 << idx; return res; }
    void markerLayerHideMask(size_t v) { foreach(idx, ref layer; markerLayers) layer.visible = ((1<<idx)&v)==0; }
  }

  protected{//ModuleSettings is a temporal storage for saving and loading the workspace.

    struct ModuleSettings{ string fileName; vec2 pos; }
    @STORED ModuleSettings[] moduleSettings;

    void toModuleSettings(){
      moduleSettings = modules.map!(m => ModuleSettings(m.file.fullName, m.outerPos)).array;
    }

    void fromModuleSettings(){
      clear;

      foreach(ms; moduleSettings){
        try{
          loadModule(File(ms.fileName), ms.pos);
        }catch(Exception e){
          WARN(e.simpleMsg);
        }
      }

      updateSubCells;
    }

    void updateSubCells(){
      subCells = cast(Cell[])modules;
    }
  }

  void clear(){
    modules.clear;
    updateSubCells;
  }

  void loadWorkspace(string jsonData){
    auto fuck = this; fuck.fromJson(jsonData);
    fromModuleSettings;
    updateSubCells;
  }

  string saveWorkspace(){
    toModuleSettings;
    return this.toJson;
  }

  void loadWorkspace(File f){
    loadWorkspace(f.readText(true));
  }

  void saveWorkspace(File f){
    f.write(saveWorkspace);
  }

  Module findModule(File file){
    foreach(m; modules)
      if(sameText(m.file.fullName, file.fullName))
        return m;

    //opt: hash table with fileName.lc...

    return null;
  }

  void closeModule(File file){
    //todo: ask user to save if needed
    if(!file) return;
    const idx = modules.map!(m => m.file).countUntil(file);
    if(idx<0) return;
    modules = modules.remove(idx);
    updateSubCells;
  }

  auto selectedModules(){ return modules.filter!(m => m.flags.selected).array; }
  auto unSelectedModules(){ return modules.filter!(m => !m.flags.selected).array; }

  void closeSelectedModules(){
    //todo: ask user to save if needed
    modules = unSelectedModules;
    updateSubCells;
  }

  void closeAll(){
    //todo: ask user to save if needed
    modules = [];
    updateSubCells;
  }

  void selectAllModules(){
    foreach(ref m; modules) m.flags.selected = true;
  }

  bool loadModule(in File file){
    const vec2 targetPos = lastModulePositions.get(file.actualFile.hashOf, vec2(calcBounds.right+24, 0));
    return loadModule(file, targetPos); //default position
  }

  bool loadModule(in File file, vec2 targetPos){
    if(!file.exists) return false;
    if(auto m = findModule(file)) return false;

    auto m = new Module(file);

    //m.flags.targetSurface = 0; not needed, workspace is on s0 already
    m.measure;
    m.outerPos = targetPos;
    modules ~= m;
    updateSubCells;

    justLoadedSomething |= true;
    justLoadedBounds |= m.outerBounds;

    return true;
  }

  File[] allFilesFromModule(File file){
    if(!file.exists) return [];
    //todo: not just for //@exe of //@dll
    BuildSettings settings = { verbose : false };
    BuildSystem buildSystem;
    return buildSystem.findDependencies(file, settings).map!(m => m.file).array;
  }

  auto loadModuleRecursive(File file){
    allFilesFromModule(file).each!(f => loadModule(f));
  }

  void queueModule(File f){ openQueue ~= f; }
  void queueModuleRecursive(File f){ if(f.exists) openQueue ~= allFilesFromModule(f); }

  FileDialog fileDialog;
  void openModule         () { fileDialog.openMulti.each!(f => queueModule         (f)); }
  void openModuleRecursive() { fileDialog.openMulti.each!(f => queueModuleRecursive(f)); }

  void updateOpenQueue(int maxWork){
    while(openQueue.length){
      auto f = openQueue.fetchFront;
      if(loadModule(f)){
        maxWork--;
        if(maxWork<=0) return;
      }
    }
  }

  void updateModuleBuildStates(in BuildResult buildResult){
    foreach(m; modules){
      m.buildState = buildResult.getBuildStateOfFile(m.file);
    }
  }

  void convertBuildMessagesToSearchResults(){
    auto br = (cast(FrmMain)mainWindow).buildResult;

    auto outFile = File(`virtual:\compile.err`);
    auto output = br.dump;
    outFile.write(output);

    if(auto m = findModule(outFile)){
      m.reload;
    }else{
      loadModule(outFile);
    }

    auto buildMessagesAsSearchResults(BuildMessageType type){ //todo: opt
      Container.SearchResult[] res;

      foreach(const msg; br.messages) if(msg.type==type){
        if(auto mod = findModule(msg.location.file)){    //opt: bottleneck! linear search
          if((msg.location.line-1).inRange(mod.code.subCells)){
            Container.SearchResult sr;
            sr.container = cast(Container)mod.code.subCells[msg.location.line-1];
            sr.absInnerPos = mod.innerPos + mod.code.innerPos + sr.container.innerPos;
            sr.cells = sr.container.subCells;
            res ~= sr;
          }else{
            //line not found in module
            //LOG(msg);
          }
        }else{
          //module not loaded
          //LOG(msg);

          //if(msg.location.file.exists) queueModule(msg.location.file);
        }
      }

      return res;
    }

    //opt: it is a waste of time. this should be called only at buildStart, and at buildProgress, module change, module move.
    //1.5ms, (45ms if not sameText but sameFile(!!!) is used in the linear findModule.)
    foreach(t; EnumMembers!BuildMessageType[1..$])
      markerLayers[t].searchResults = buildMessagesAsSearchResults(t);
  }


  void updateLastKnownModulePositions(){
    foreach(m; modules)
      lastModulePositions[m.file.hashOf] = m.outerPos;
  }

  // textSelection, cursor movements /////////////////////////////

  void updateTextSelections(){

    bool isModuleExists(const TextSelection ts){ return modules.map!(m => m.code).canFind(ts.codeColumn); } //opt: linear

    //validate & sort
    textSelections = textSelections.filter!(ts => isModuleExists(ts)).array.sort.array;

    void doit(alias fun)(){ foreach(ref s; textSelections) unaryFun!fun(s); }

    if(frmMain.isForeground && !im.wantKeys){ // keyboard handling --------------------------------------------------------------------------
      int pageSize(){ return (frmMain.view.subScreenBounds.height/DefaultFontHeight*.8f).iround.clamp(1, 100); }

      foreach(isShift; [false, true]){
        ivec2 dir;

        void a(string key, void delegate() fun){ if(KeyCombo((isShift ? "Shift+" : "")~key).typed) fun(); }

        a("Left"        , { dir.x--;                      });  //todo: formatting test with this and the new UI
        a("Right"       , { dir.x++;                      });
        a("Up"          , { dir.y--;                      });
        a("Down"        , { dir.y++;                      });
        a("PgUp"        , { dir.y -= pageSize;            });
        a("PgDn"        , { dir.y += pageSize;            });
        a("Home"        , { dir.x = TextCursor.home;      });
        a("End"         , { dir.x = TextCursor.end;       });
        a("Ctrl+Home"   , { dir = ivec2(TextCursor.home); });
        a("Ctrl+End"    , { dir = ivec2(TextCursor.end);  });
        a("Ctrl+Left"   , { dir.x = TextCursor.wordLeft;  });
        a("Ctrl+Right"  , { dir.x = TextCursor.wordRight; });

        if(dir) doit!((ref a) => a.move(dir));
      }

      if(textSelections.length>1 && KeyCombo("Esc").typed){
        textSelections.length = 1; //todo: which one to keep... I think VSCode keeps the oldest...
      }

      if(textSelections.length){
        if(KeyCombo("Ctrl+Alt+Up").typed){
          auto ts = textSelections[0];
          ts.move(ivec2(0, -1));
          if(ts!=textSelections[0]) textSelections = ts ~ textSelections;
        }
        if(KeyCombo("Ctrl+Alt+Down").typed){
          auto ts = textSelections[$-1];
          ts.move(ivec2(0, 1));
          if(ts!=textSelections[$-1]) textSelections ~= ts;
        }
      }

    }

    if(frmMain.isForeground && !im.wantMouse){ // mouse handling ----------------------------------------------------------

    }
  }

  void update(View2D view, in BuildResult buildResult){ //update ////////////////////////////////////
    updateOpenQueue(1);

    selectionManager.update(mainWindow.isForeground && lod.moduleLevel && view.mousePos in view.subScreenBounds, view, modules);

    updateTextSelections;

    size_t calcBuildStateHash(){ return modules.map!"tuple(a.file, a.outerPos)".array.hashOf(buildResult.lastUpdateTime.hashOf(markerLayerHideMask/+to filter compile.err+/)); }
    buildStateChanged = lastBuildStateHash.chkSet(calcBuildStateHash);
    if(buildStateChanged){
      updateModuleBuildStates(buildResult);
      convertBuildMessagesToSearchResults; //opt: limit this by change detection
    }

    updateLastKnownModulePositions;
  }

  auto calcBounds(){
    return modules.fold!((a, b)=> a|b.outerBounds)(bounds2.init);
  }

  void UI_ModuleBtns(){ with(im){
    File fileToClose;
    foreach(m; modules){
      if(Btn(m.file.name, hint(m.file.fullName), genericId(m.file.fullName), selected(0), { fh = 12; theme="tool"; if(Btn(symbol("Cancel"))) fileToClose = m.file; })) {}
    }
    if(Btn(symbol("Add"))) openModule;

    if(Btn("Close All", KeyCombo("Ctrl+Shift+W"))){
      closeAll;
    }

    if(fileToClose) closeModule(fileToClose);
  }}


  override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0)){  //locate ////////////////////////////////
    ofs += innerPos;
    foreach_reverse(m; modules){
      auto st = m.locate(mouse, ofs);
      if(st.length) return st;
    }
    return [];
  }

  CodeLocation cellLocationToCodeLocation(CellLocation[] st){
    auto a(T)(void delegate(T) f){
      if(auto x = cast(T)st.get(0).cell){ st.popFront; f(x); }
    }

    //opt: linear search...

    CodeLocation res;
    a((Module m){
      res.file = m.file;
      a((CodeColumn col){
        a((CodeRow row){
          if(auto line = col.subCells.countUntil(row)+1){
            res.line = line.to!int;
            a((Cell cell){
              if(auto column = row.subCells.countUntil(cell)+1)
                res.column = column.to!int;
            });
          }
        });
      });
    });
    return res;
  }

  //! UI /////////////////////////////////////////////////////////

  void UI_SearchBox(View2D view){ UI_SearchBox(view, markerLayers[BuildMessageType.find].searchResults); }  //UI_SearchBox /////////////////////////////////////////////

  void zoomAt(View2D view, in Container.SearchResult[] searchResults){
    if(searchResults.empty) return;
    const maxScale = max(view.scale, 1);
    view.zoom(searchResults.map!(r => r.bounds).fold!"a|b", 12);
    view.scale = min(view.scale, maxScale);
  }

  void UI_SearchBox(View2D view, ref Container.SearchResult[] searchResults){ with(im) Row({
    //Keyboard shortcuts
    auto kcFind      = KeyCombo("Ctrl+F"),
         kcFindZoom  = KeyCombo("Enter"), //only when edit is focused
         kcFindClose = KeyCombo("Esc"); //always

    if(kcFind.pressed) searchBoxVisible = true; //this is needed for 1 frame latency of the Edit
    //todo: focus on the edit when turned on
    if(searchBoxVisible){
      width = fh*12;

      Text("Find ");
      .Container editContainer;
      if(Edit(searchText, kcFind, { flex = 1; editContainer = actContainer; })){
        //refresh search results
        searchResults = modules.map!(m => m.search(searchText)).join;
      }

      // display the number of matches. Also save the location of that number on the screen.
      const matchCnt = searchResults.length;
      Row({
        if(matchCnt) Text(" ", clGray, matchCnt.text, " ");
      });

      if(Btn(symbol("Zoom"), isFocused(editContainer) ? kcFindZoom : KeyCombo(""), enable(matchCnt>0), hint("Zoom screen on search results."))){
        zoomAt(view, searchResults);
      }

      if(Btn(symbol("ChromeClose"), kcFindClose, hint("Close search box."))){
        searchBoxVisible = false;
        searchText = "";
        searchResults = [];
      }
    }else{

      if(Btn(symbol("Zoom"       ), kcFind, hint("Start searching."))){
        searchBoxVisible = true ; //todo: Focus the Edit control
      }
    }
  });}

  void UI(BuildMessageType bmt, View2D view){ with(im){ // UI_BuildMessageTypeBtn ///////////////////////////
    //todo: ennek nem itt a helye....
    auto hit = Btn({
      const hidden = markerLayers[bmt].visible ? 0 : .75f;
      style.bkColor = bkColor = bmt.color.mix(clSilver, hidden);
      style.fontColor = blackOrWhiteFor(bkColor).mix(clSilver, hidden);

      Text(bmt.caption, " ", markerLayers[bmt].searchResults.length);
    }, genericId(bmt));

    if(mainWindow.isForeground && hit.pressed){
      markerLayers[bmt].visible = true;
      zoomAt(view, markerLayers[bmt].searchResults);
    }

    if(mainWindow.isForeground && hit.hover && inputs.RMB.pressed){
      markerLayers[bmt].visible.toggle;
    }
  }}

  void UI_selectedModulesHint(){ with(im){
    auto sm = selectedModules;
    void stats(){ Row(format!"(%d LOC, %sB)"(sm.map!(m => m.linesOfCode).sum, shortSizeText!" "(sm.map!(m => m.sizeBytes).sum))); }
    if(sm.length==1){
      auto m = sm.front;
      Row({ padding="0 8"; }, "Selected module: ", { CodeLocation(m.file).UI; },
        { if(sameText(m.file.fullName, mainModuleFile.fullName)){
            Btn("Main", enable(false));
          }else{
            if(m.isMain){
              if(Btn("Set Main")) mainModule = m;
            }
          }
          stats;
        }
      );
    }else if(sm.length>1){
      Row({ padding="0 8"; }, sm.length.text, " modules selected ", { stats; });
    }else{
      Row({ padding="0 8"; }, "No modules selected.");
    }
  }}

  void UI_mouseLocationHint(View2D view){ with(im){
    auto st = locate(view.mousePos);
    if(st.length){
      Row({ padding="0 8"; }, "\u2316 ", {
        const loc = cellLocationToCodeLocation(st);
        loc.UI;
        const debug_pos2idx=true;
        if(loc.file && loc.line){
          if(loc.column) with(findModule(loc.file).code){
            const pos = ivec2(loc.column, loc.line)-1;
            const idx = pos2idx(pos);
            const pos2 = idx2pos(idx);
            const idx2 = pos2idx(pos2);
            Text("   ", pos.text, idx.text, pos2.text, idx2.text);
          }else with(findModule(loc.file).code){
            const pos = ivec2(st[$-1].localPos.x<=0 ? 0 : rows[loc.line-1].charCount, loc.line-1);
            const idx = pos2idx(pos);
            const pos2 = idx2pos(idx);
            const idx2 = pos2idx(pos2);
            Text("   ", pos.text, idx.text, pos2.text, idx2.text);
          }
        }
      });
    }
  }}

  //! draw routines ////////////////////////////////////////////////////

  void drawSearchResults(Drawing dr, in SearchResult[] searchResults, RGB clSearchHighLight){ with(dr){
    auto view = im.getView;
    const
      blink = float(sqr(sin(blinkf(134.0f/60)*PIf))),
      arrowSize = 12+3*blink,
      arrowThickness = arrowSize*.2f,

      far = lod.level>1,
      extra = lod.pixelSize*2*blink,
      bnd = view.subScreenBounds,
      bndInner = bnd.inflated(-lod.pixelSize*arrowThickness*2),
      bndInnerSizeHalf = bndInner.size/2,
      center = bnd.center;

    color = clSearchHighLight;

    bool isVisible(T)(in T b){ return bnd.overlaps(b); }

    //always draw these
    color = clSearchHighLight;
    foreach(sr; searchResults){
      auto r = sr.bounds;
      if(bnd.overlaps(r)){
        r.topLeft     -= vec2(extra);
        r.bottomRight += vec2(extra); //todo: inflate
        fillRect(r);
      }else{
        dr.lineWidth = -arrowThickness;
        dr.arrowStyle = ArrowStyle.arrow;

        auto v = r.center-center;
        if(v.x >  bndInnerSizeHalf.x) v *=  bndInnerSizeHalf.x/v.x;
        if(v.x < -bndInnerSizeHalf.x) v *= -bndInnerSizeHalf.x/v.x;
        if(v.y >  bndInnerSizeHalf.y) v *=  bndInnerSizeHalf.y/v.y;
        if(v.y < -bndInnerSizeHalf.y) v *= -bndInnerSizeHalf.y/v.y;

        dr.line(center+v*.99f, center+v);
        dr.arrowStyle = ArrowStyle.none;
      }
    }

    //later pass, draw the columns as highlighted so this will always visible
    if(!far){
      foreach(sr; searchResults)
        if(isVisible(sr.bounds))
          sr.drawHighlighted(dr, clSearchHighLight); //close lod
    }
  }}

  protected void drawHighlight(Drawing dr, bounds2 bnd, RGB color, float alpha){
    dr.color = color;
    dr.alpha = alpha;
    dr.fillRect(bnd);
    dr.lineWidth = -1;
    dr.drawRect(bnd);
    dr.alpha = 1;
  }

  protected void drawHighlight(Drawing dr, Cell c, RGB color, float alpha){
    drawHighlight(dr, c.outerBounds, color, alpha);
  }

  /// A flashing effect, when right after the module was loaded.
  void drawModuleLoadingHighlights(Drawing dr, RGB c){
    const t0 = now;
    foreach(m; modules){
      const dt = (t0-m.loaded).value(2.5f*second);
      if(dt<1)
        drawHighlight(dr, m, c, sqr(1-dt));
    }
  }

  protected void drawSelectedModules(Drawing dr, RGB clSelected, float selectedAlpha, RGB clHovered, float hoveredAlpha){ with(dr){
    foreach(m; modules) if(m.flags.selected) drawHighlight(dr, m, clSelected, selectedAlpha);
    if(auto m = selectionManager.hoveredItem) drawHighlight(dr, m, clHovered, hoveredAlpha);
  }}

  protected void drawSelectionRect(Drawing dr, RGB clRect){
    if(auto bnd = selectionManager.selectionBounds) with(dr) {
      lineWidth = -1;
      lineStyle = LineStyle.dash;
      color = clRect;
      drawRect(bnd);
      lineStyle = LineStyle.normal;
    }
  }

  protected void drawMainModules(Drawing dr){
    auto mm=mainModule;
    foreach(m; modules){
      if(m==mm){ dr.color = RGB(0xFF, 0xD7, 0x00); dr.lineWidth = -2.5f; dr.drawRect(m.outerBounds); }
      else if(m.isMain){ dr.color = clSilver; dr.lineWidth = -1.5f; dr.drawRect(m.outerBounds); }
      //else if(m.file.extIs(".d")){ dr.color = clSilver; dr.lineWidth = 12; dr.drawRect(m.outerBounds); }
    }
  }

  protected void drawFolders(Drawing dr, RGB clFrame, RGB clText){
    //todo: detect changes and only collect info when changed.

    const paths = modules.map!(m => m.file.path.fullPath).array.sort.uniq.array;

    foreach(folderPath; paths){
      bounds2 bnd;
      foreach(m; modules){
        const modulePath = m.file.path.fullPath;
        if(modulePath.startsWith(folderPath)){
          const intermediateFolderCount = modulePath[folderPath.length..$].filter!`a=='\\'`.walkLength;

          bnd |= m.outerBounds.inflated((1+intermediateFolderCount)*255.0f/*max font size ATM*/);
        }
      }
      if(bnd){
        dr.lineWidth = -1;
        dr.color = clFrame;
        dr.drawRect(bnd);
      }

      with(cachedFolderLabel(folderPath)){
        outerPos = bnd.topLeft - vec2(0, 255);
        draw(dr);
      }
    }
  }

  void drawModuleBuildStates(Drawing dr){
    with(ModuleBuildState) foreach(m; modules) if(m.buildState!=notInProject){
      dr.color = m.buildState.color;
      dr.lineWidth = -4;
      //if(m.buildState==compiling) dr.drawRect(m.outerBounds);
      dr.alpha = m.buildState==compiling ? mix(.25f, .75f, blink) : .25f;
      dr.fillRect(m.outerBounds);
    }
    dr.alpha = 1;
  }

  void drawTextSelections(Drawing dr){ //drawTextSelections ////////////////////////////
    const blink = float(sqr(sin(blinkf(134.0f/60)*PIf)));
    const clSelected = mix(mix(RGB(0x404040), clSilver, lod.zoomFactor.smoothstep(0.02, 0.1)), clWhite, blink);
    const clCaret = mix(clWhite, clOrange, blink);

    dr.alpha = .35f; //font surface only
    scope(exit) dr.alpha = 1;

    Module moduleOf(in TextSelection ts){
      foreach(m; modules) if(m.code==ts.codeColumn) return m; //opt: linear
      return null;
    }

    foreach(ts; textSelections){
      auto m = moduleOf(ts);
      const codeColumnsInnerPosAbs = m.outerPos             + m.topLeftGapSize +
                                     ts.codeColumn.outerPos + ts.codeColumn.topLeftGapSize;
      dr.translate(codeColumnsInnerPosAbs); scope(exit) dr.pop;
      //draw the selection
      if(ts.cursors[0] != ts.cursors[1]){
        const st=m.code.pos2idx(ts.start.pos),
              en=m.code.pos2idx(ts.end  .pos);
        foreach(i; st..en){
          const pos = m.code.idx2pos(i); //opt: unoptimal conversions between idx and pos
          auto r = m.code.rows[pos.y];
          dr.translate(r.outerPos+r.topLeftGapSize); scope(exit) dr.pop; //opt: really slow at every char

          if(pos.x<r.subCells.length){//highlighted chars
            auto g = r.glyphs[pos.x];
            const old = tuple(g.bkColor, g.fontColor);
            g.bkColor = clSelected; g.fontColor = clBlack;
            g.draw(dr);
            g.bkColor = old[0]; g.fontColor = old[1];
          }else{
            //newLine at the end of the line
            static Glyph gLF; if(!gLF) gLF = new Glyph("\u240A\u2936\u23CE"d[1], tsNormal);
            const x = r.subCells.length ? r.subCells[$-1].outerBounds.right : 0;
            gLF.bkColor = clSelected; gLF.fontColor = clBlack;
            gLF.outerPos = vec2(x, 0);
            gLF.draw(dr);
          }
        }
      }
    }

    //caret
    dr.alpha = blink;
    dr.lineWidth = -1-(blink)*3;
    dr.color = clCaret;
    foreach(ts; textSelections){

      //todo: this is redundant, combine the too loops
      auto m = moduleOf(ts);
      const codeColumnsInnerPosAbs = m.outerPos             + m.topLeftGapSize +
                                     ts.codeColumn.outerPos + ts.codeColumn.topLeftGapSize;

      const pos = ts.cursors[1].pos;
      auto r = m.code.rows[pos.y]; //todo: error check/clamp

      const x = pos.x<=0 ? 0 : r.subCells[pos.x-1].outerBounds.right;
      dr.moveTo(codeColumnsInnerPosAbs+r.outerPos+r.topLeftGapSize+vec2(x, 0));
      dr.lineRel(0, r.innerHeight);
    }

  }

  override void onDraw(Drawing dr){ //onDraw //////////////////////////////
    if(lod.moduleLevel){
      drawSelectedModules(dr, clWhite, .3f, clWhite, .1f);
      drawSelectionRect(dr, clWhite);
      drawFolders(dr, clGray, clWhite);
      drawMainModules(dr);
    }

    if(lod.moduleLevel || (cast(FrmMain)mainWindow).building) drawModuleBuildStates(dr);

    drawModuleLoadingHighlights(dr, clWhite);

    foreach_reverse(t; EnumMembers!BuildMessageType)
      if(markerLayers[t].visible)
        drawSearchResults(dr, markerLayers[t].searchResults, t.color);

/*    {
      auto m = findModule(File(`c:\d\libs\het\utils.d`));
      //textSelections = [TextSelection(m.code, [TextCursor(ivec2(3,0)), TextCursor(ivec2(5,6))])];
      textSelections = iota(100).map!(i => TextSelection(m.code, [TextCursor(m.code.idx2pos(i*140)), TextCursor(m.code.idx2pos(i*140+40))])).array;
    }*/
    if(textSelections.length==0){
      auto m = findModule(File(`c:\d\libs\het\utils.d`));
      textSelections = [TextSelection(m.code, [TextCursor(ivec2(0)), TextCursor(ivec2(0))])];
    }

    drawTextSelections(dr);
  }


}


// MainOverlay //////////////////////////////////////////////////////////
class MainOverlayContainer : het.uibase.Container{
  this(){ flags.targetSurface = 0; }
  override void onDraw(Drawing dr){
    frmMain.drawOverlay(dr);
  }
}

//! FrmMain ///////////////////////////////////////////////
auto frmMain(){ return cast(FrmMain)mainWindow; }

class FrmMain : GLWindow { mixin autoCreate;

  Workspace workspace;
  MainOverlayContainer overlay;

  Tid buildSystemWorkerTid;

  BuildResult buildResult; //collects buildMessages and output

  Path workPath = Path(`z:\temp2`);

  File workspaceFile;
  bool initialized; //workspace has been loaded.

  @VERB("Alt+F4")       void closeApp            (){ PostMessage(hwnd, WM_CLOSE, 0, 0); }
  @VERB("Ctrl+O")       void openFile            (){ workspace.openModule; }
  @VERB("Ctrl+Shift+O") void openFileRecursive   (){ workspace.openModuleRecursive; }
  @VERB("Ctrl+W")       void closeWindow         (){ if(lod.moduleLevel) workspace.closeSelectedModules; }
  @VERB("Ctrl+A")       void selectAll           (){ if((lod.moduleLevel) && !im.wantKeys) workspace.selectAllModules; }

  void onCompileProgress(File file, int result, string output){
    LOG(file, result, output.length);
  }

  bool building()   const{ return buildSystemWorkerState.building; }
  bool ready()      const{ return !buildSystemWorkerState.building; }
  bool cancelling() const{ return buildSystemWorkerState.cancelling; }

  void initBuildSystem(){
    buildResult = new BuildResult;
    buildSystemWorkerTid = spawn(&buildSystemWorker);
  }

  void updateBuildSystem(){
    buildResult.receiveBuildMessages; //todo: it's only good for ONE workspace!!!
  }

  void destroyBuildSystem(){
    buildSystemWorkerTid.send(MsgBuildCommand.shutDown);

    if(building){
      LOG("Waiting for buildsystem to shut down.");
      while(building){ write('.'); sleep(100); }
    }
  }

  void launchBuildSystem(string command)(){
    static assert(command.among("rebuild", "run"), "Invalid command `"~command~"`");
    if(building){ beep; return ; }

    if(!workPath.exists) workPath.make;

    BuildSettings bs = {
      killExe  : true,
      rebuild  : command=="rebuild",
      verbose  : false,
      compileOnly : command=="rebuild",
      workPath : this.workPath.fullPath,
      collectTodos : false,
      compileArgs : ["-wi"],  // "-v" <- not good: it also lists all imports
    };

    buildSystemWorkerTid.send(cast(immutable)MsgBuildRequest(workspace.mainModuleFile, bs));
    //todo: immutable is needed because of the dynamic arrays in BuildSettings... sigh...
  }

  @VERB("F9") void run(){
    launchBuildSystem!"run";
  }

  @VERB("Shift+F9") void rebuild(){
    launchBuildSystem!"rebuild";
  }

  @VERB("Ctrl+F2" ) void cancelBuildAndResetApp(){
    if(building) buildSystemWorkerTid.send(MsgBuildCommand.cancel);
    //todo: kill app
    //todo:
  }

  override void onCreate(){ //onCreate //////////////////////////////////
    initBuildSystem;
    workspace = new Workspace;
    workspaceFile = File(appPath, "default"~Workspace.defaultExt);
    overlay = new MainOverlayContainer;
  }

  override void onDestroy(){
    if(initialized) workspace.saveWorkspace(workspaceFile);
    destroyBuildSystem;
  }

  override void onUpdate(){ // onUpdate ////////////////////////////////////////
    //showFPS = true;

    updateBuildSystem;

    if(initialized.chkSet){
      test_CodeColumn;
      if(workspaceFile.exists){
        workspace.loadWorkspace(workspaceFile);
      }
    }

    invalidate; //todo: low power usage
    caption = "DIDE2";
    view.navigate(false && !im.wantKeys && !inputs.Ctrl.down && !inputs.Alt.down && isForeground, !im.wantMouse && isForeground);
    if(!inputs.LMB && !inputs.RMB) setLod(view.scale_anim);

    if(isForeground) callVerbs(this);

    if(0) with(im) Panel(PanelPosition.topClient, { margin = "0"; padding = "0";// border = "1 normal gray";
      Row({ //todo: Panel should be a Row, not a Column...
        Row({ workspace.UI_ModuleBtns; flex = 1; });
      });
    });

    with(im) Panel(PanelPosition.topRight, { margin = "0"; padding = "0";
      workspace.UI_SearchBox(view);
    });

    if(0) with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
      Row({
        Text(hitTestManager.lastHitStack.map!(a => "["~a.id~"]").join(` `));
        NL;
        if(hitTestManager.lastHitStack.length) Text(hitTestManager.lastHitStack.back.text);


        foreach_reverse(m; workspace.modules){
          foreach(loc; m.locate(view.mousePos)){
            Text("\n", loc.text);
          }
        }
      });
    });

    void VLine(){ with(im) Container({ innerWidth = 1; innerHeight = fh; bkColor = clGray; }); }

    //StatusBar
    with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";
      Row({
        theme = "tool"; style.fontHeight = 18;

        //todo: faszomat ebbe a szarba:
        flags.vAlign = VAlign.center;  //ha ez van, akkot a text kozepre megy, de a VLine nem latszik.
        //flags.yAlign = YAlign.stretch; //ha ez, akkor meg a VLine ki van huzva.

        Row({ margin = "0 3"; flags.yAlign = YAlign.center;
          //style.fontHeight = 18+6;
          buildSystemWorkerState.UI;
        });

        VLine;//---------------------------

        Row({ flex = 1; margin = "0 3"; flags.yAlign = YAlign.center; flags.clipSubCells = true;
          //style.fontHeight = 18+6;

          if(lod.moduleLevel ) workspace.UI_selectedModulesHint;
          if(!lod.moduleLevel) workspace.UI_mouseLocationHint(view);

        });

        VLine;//---------------------------

        Row({ margin = "0 3"; flags.yAlign = YAlign.center;
          foreach(t; EnumMembers!BuildMessageType){
            workspace.UI(t, view);
          }
        });
        VLine;//---------------------------
        Row({ margin = "0 3"; flags.vAlign = VAlign.center;
          Text(now.text);
          if(Btn("Calc size")){
            print(workspace.allocatedSize);
          }
        });

        //this applies YAlign.stretch
        with(actContainer){
          measure;
          foreach(c; cast(.Container[])subCells) c.measure;
        }

      });
    });

    im.root ~= workspace;
    im.root ~= overlay;

    view.subScreenArea = im.clientArea / clientSize;

    workspace.update(view, buildResult);

    if(chkClear(workspace.justLoadedSomething)){
      view.zoom(workspace.justLoadedBounds | view.subScreenBounds);
      workspace.justLoadedBounds = bounds2.init;
    }

    //todo:cullSubCells ellenorzese


    if(0){
      T0;
      int i;
      foreach(m; workspace.modules) if(m.file.name.sameText("utils.d"))
        foreach(r; m.code.rows)
          foreach(g; r.glyphs)
            i++;
      print(DT, i);
    }
  }

  override void onPaint(){ // onPaint ///////////////////////////////////////
    gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT);
  }


  void drawOverlay(Drawing dr){
    //drawSearchResults(dr, clWhite);

    //locate() debug
    if(0){

      void locate(vec2 pos){
        //dr.color = clFuchsia;
        dr.lineWidth = -1;
        foreach(loc; workspace.modules.map!(m => m.locate(pos)).joiner){
          dr.drawRect(loc.globalOuterBounds);

          dr.arrowStyle = ArrowStyle.arrow;
          dr.moveTo(loc.globalOuterBounds.topLeft); dr.lineRel(loc.cell.topLeftGapSize+loc.localPos);
          dr.arrowStyle = ArrowStyle.none;
        }
      }

      foreach(x; 0..10)foreach(y; 0..10){
        dr.color = RGB(x*25.5f, y*25.5f, .5f);
        locate(view.mousePos+vec2(x, y)*2);
      }
    }

    dr.mmGrid(view);


  }

  //todo: off screen targets

  override void afterPaint(){ // afterPaint //////////////////////////////////
  }

}

//todo: search in std, core, etc
//todo: winapi help search

