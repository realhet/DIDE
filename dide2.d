//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId

//@release
///@debug


import het, het.keywords, het.tokenizer, het.ui, het.dialogs;

int DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.

// build system /////////////////////////////////////

import buildsys;

BuildSystem buildSystem;
BuildSettings buildSettings = { verbose : false };


/// CodeRow ////////////////////////////////////////////////
class CodeRow: Row{
  auto glyphs() { return subCells.map!(c => cast(Glyph)c); } //can return nulls
  auto chars()  { return glyphs.map!"a ? a.ch : '\u26A0'"; }
  string text() { return chars.to!string; }

  int charCount(){ return cast(int)subCells.length; }

  private static bool isSpace(Glyph g){ return g && g.ch==' ' && g.syntax.among(0, 9); }
  private auto spaces() { return glyphs.map!(g => isSpace(g)); }
  private auto leadingSpaces(){ return glyphs.until!(g => !isSpace(g)); }

  this(){
    id.value = this.identityStr;

    flags.wordWrap       = false;
    flags.clipSubCells   = true;
    flags.cullSubCells   = true;
    flags.rowElasticTabs = false;
    flags.dontHideSpaces = true;
    bkColor = clCodeBackground;
    outerHeight = DefaultFontHeight;
    super();
  }

  this(string line, ubyte[] syntax){
    assert(line.length==syntax.length);
    this();
    set(line, syntax);
  }

  this(string line){
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
    enum smallestHeight = 3;

    if(outerSize.y < smallestHeight*dr.invZoomFactor){
      //LOD: one straight line

      const lsCnt = glyphs.until!(g => !g || !g.ch.among(' ', '\t')).walkLength;
      if(subCells.length-lsCnt>0){
        const r = bounds2(subCells[lsCnt].outerPos, subCells[$-1].outerBottomRight) + innerPos;
        dr.color = avg(glyphs[lsCnt].bkColor, glyphs[lsCnt].fontColor);
        dr.fillRect(r.inflated(vec2(0, -r.height/4)));
      }
    }else{
      super.draw(dr);
    }
  }

}


class CodeColumn: Column{ // CodeColumn ////////////////////////////////////////////
  auto rows(){ return cast(CodeRow[])subCells; }
  int rowCount(){ return cast(int)subCells.length; }
  @property string text() { return rows.map!"a.text".join("\r\n"); }

  this(){
    id.value = this.identityStr;

    flags.wordWrap     = false;
    flags.clipSubCells = true;
    flags.cullSubCells = true;

    flags.columnElasticTabs = true;
    bkColor = clCodeBackground;

    margin = "4";
  }

  this(File file){
    this();
    id = "CodeColumns:"~file.fullName;
    set(file);
  }

  void set(File file){
    auto src = scoped!SourceCode(file);

    clearSubCells;

    src.foreachLine( (int idx, string line, ubyte[] syntax) => append(new CodeRow(line, syntax)) );

    makeElasticTabs;

    const spacesPerTab = src.whiteSpaceStats.detectIndentSize(DefaultIndentSize);
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


/// Module ///////////////////////////////////////////////
class Module : Row{ //this is any file in the project
  File file;

  this(File file_){
    file = file_.normalized;

    id = "Module:"~this.file.fullName;

    append(new CodeColumn(this.file));
  }

  override void onDraw(Drawing dr){
    dr.color = clGray;
    dr.lineWidth = -2;
    dr.alpha = .5;
    dr.fillRect(0, 0, innerWidth, innerHeight);
    dr.alpha = 1;

  }
}



//! FrmMain ///////////////////////////////////////////////
class FrmMain : GLWindow { mixin autoCreate;

  FileDialog fileDialog;

  Module[] modules;

  Module findModule(File file){ const fn = file.normalized; foreach(m; modules) if(m.file==fn) return m; return null; }

  void closeModule(File file){
    if(!file) return;
    const idx = modules.map!(m => m.file).countUntil(file);
    if(idx<0) return;
    modules = modules.remove(idx);
  }

  @VERB("Ctrl+O") void openFile(){
    //todo: handle "Open as read-only"
    foreach(f; fileDialog.openMulti) openFile(f);
  }

  @VERB void openFile(in File file){
    if(!file.exists) return;
    if(auto m = findModule(file)) return;

    auto m = new Module(file);
    m.flags.targetSurface = 0;
    m.measure;
    if(modules.length) m.outerPos.x = modules[$-1].outerBounds.right+10;
    modules ~= m;
  }

  auto findImportedModules(File projectFile){
  }

  File testProject = File(`c:\D\projects\DIDE\dide2.d`);

  override void onCreate(){
    fileDialog = new FileDialog(hwnd, "Dlang source file", ".d", "Sources(*.d)");
  }

  override void onUpdate(){
    //showFPS = true;

    invalidate; //todo: low power usage
    caption = "DIDE2";
    view.navigate(!im.wantKeys, !im.wantMouse);
    callVerbs(this);

    with(im) Panel(PanelPosition.topClient, {
      margin = "2";
      padding = "0";

      //width = 300;
      //flags.vScrollState = ScrollState.auto_;

      //static string actModule;
      //BtnRow(actModule, modules.map!(a => a.file.fullName).array);

      Row({
        File fileToClose;
        theme="tool";
        foreach(m; modules){
          if(Btn(m.file.name, hint(m.file.fullName), genericId(m.file.fullName), selected(0), { fh = 12; theme="tool"; if(Btn(symbol("Cancel"))) fileToClose = m.file; })) {}
        }
        if(Btn(symbol("Add"))) openFile;
        if(fileToClose) closeModule(fileToClose);
      });

    });

    im.root ~= modules;

/*    if(!moduleGraph){
      BuildSystem bs;
      auto modules = bs.findDependencies(testProject, settings);

      moduleGraph = new ModuleGraph(File(appPath, "Module extra data.txt"));

      foreach(m; modules) moduleGraph.addModule(m);
      moduleGraph.loadExtraData;
    }

    with(im) Panel(PanelPosition.topClient, {
      Row({
        moduleGraph.UI_SearchBox(view);
      });
    });

    moduleGraph.update2(view);

    with(im) Panel(PanelPosition.topLeft, {
      width = 300;
      flags.vScrollState = ScrollState.auto_;

      moduleGraph.UI_Editor;
    });*/

  }

  override void onPaint(){
    gl.clearColor(RGB(0x2d2d2d)); gl.clear(GL_COLOR_BUFFER_BIT);

  }

}