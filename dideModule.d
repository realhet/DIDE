module didemodule;

import het, het.ui, het.tokenizer, dideui, buildsys;

__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.

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
      //auto br = (cast(FrmMain)mainWindow).buildResult;
      //auto markerLayerHideMask = (cast(FrmMain)mainWindow).workspace.markerLayerHideMask;

      import dide2;
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

