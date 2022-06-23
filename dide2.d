//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId

//@release
///@debug


import het, het.keywords, het.tokenizer, het.ui, het.dialogs;

__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.

const clModuleBorder = clGray;
const clModuleText = clBlack;

void setRoundBorder(Container cntr, float borderWidth){ with(cntr){
  border.width = borderWidth;
  border.color = bkColor;
  border.inset = true;
  border.borderFirst = true;
}}

// build system /////////////////////////////////////

import buildsys;

__gshared BuildSystem buildSystem;

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
      if(lsCnt<subCells.length){
        const r = bounds2(subCells[lsCnt].outerPos, subCells[$-1].outerBottomRight) + innerPos;
        dr.color = avg(glyphs[lsCnt].bkColor, glyphs[lsCnt].fontColor);
        //dr.color = application.tick&1 ? clWhite : clBlack;
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

    padding = "1 4";
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
class Module : Container{ //this is any file in the project
  File file;

  CodeColumn code;
  Row overlay;

  void rebuild(){
    clearSubCells;

    flags.cullSubCells = true;

    bkColor = clModuleBorder;
    this.setRoundBorder(16);
    padding = "8";

    code = new CodeColumn(this.file);
    code.measure;
    const siz = code.outerSize;
    innerSize = siz;

    overlay = new Row;
    overlay.id = "Overlay:"~file.fullName;
    overlay.outerSize = siz;
    with(overlay.flags){
      dontSearch = true;
      noBackground = true;
      //clipSubCells = false;
    }

    auto ts = tsNormal;
    ts.fontHeight = 18*12;
    ts.fontColor = clWhite;
    ts.transparent = true;

    overlay.appendStr(file.nameWithoutExt, ts);
    overlay.measure;

    append(code);
    append(overlay);
  }


  this(File file_){
    file = file_.normalized;
    id = "Module:"~this.file.fullName;

    rebuild;
  }

  override void draw(Drawing dr){
    overlay.flags.hidden = 2 > dr.invZoomFactor;
    super.draw(dr);
  }

  override void onDraw(Drawing dr){
    /*dr.color = clGray;
    dr.lineWidth = -2;
    dr.alpha = .5;
    dr.fillRect(0, 0, innerWidth, innerHeight);
    dr.alpha = 1;*/

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

  FileDialog fileDialog;

  Module[] modules;
  MainOverlayContainer overlay;

  Module findModule(File file){ const fn = file.normalized; foreach(m; modules) if(m.file==fn) return m; return null; }

  void closeModule(File file){
    if(!file) return;
    const idx = modules.map!(m => m.file).countUntil(file);
    if(idx<0) return;
    modules = modules.remove(idx);
  }

  void openFile(in File file){
    if(!file.exists) return;
    if(auto m = findModule(file)) return;

    auto m = new Module(file);
    m.flags.targetSurface = 0;
    m.measure;
    if(modules.length) m.outerPos.x = modules[$-1].outerBounds.right+10;
    modules ~= m;
  }

  auto openFileRecursive(File mainFile){
    if(!mainFile.exists) return;

    BuildSettings settings = { verbose : false };
    foreach(m; buildSystem.findDependencies(mainFile, settings))
      openFile(m.file);
  }

  @VERB("Alt+F4")       void closeApp            (){ PostMessage(hwnd, WM_CLOSE, 0, 0); }
  @VERB("Ctrl+O")       void openFile            (){ fileDialog.openMulti.each!(f => openFile         (f)); }
  @VERB("Ctrl+Shift+O") void openFileRecursive   (){ fileDialog.openMulti.each!(f => openFileRecursive(f)); } //project

  //search /////////////////////////////////

  bool searchBoxVisible = false;
  string searchText;
  Container.SearchResult[] searchResults;

  void UI_SearchBox(View2D view){ with(im) Row({
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
        const maxScale = max(view.scale, 1);
        view.zoomBounds(searchResults.map!(r => r.bounds).fold!"a|b", 12);
        view.scale = min(view.scale, maxScale);
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

  override void onCreate(){ //onCreate //////////////////////////////////
    fileDialog = new FileDialog(hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)");
    overlay = new MainOverlayContainer;

  }

  override void onUpdate(){ // onUpdate ////////////////////////////////////////
    //showFPS = true;

    invalidate; //todo: low power usage
    caption = "DIDE2";
    view.navigate(!im.wantKeys, !im.wantMouse);
    callVerbs(this);

    with(im) Panel(PanelPosition.topClient, {
      margin = "0";
      padding = "0";
      border = "1 normal gray";

      //width = 300;
      //flags.vScrollState = ScrollState.auto_;

      //static string actModule;
      //BtnRow(actModule, modules.map!(a => a.file.fullName).array);

      Row({
        Row({
          File fileToClose;
          theme="tool";
          foreach(m; modules){
            if(Btn(m.file.name, hint(m.file.fullName), genericId(m.file.fullName), selected(0), { fh = 12; theme="tool"; if(Btn(symbol("Cancel"))) fileToClose = m.file; })) {}
          }
          if(Btn(symbol("Add"))) openFile;
          if(fileToClose) closeModule(fileToClose);

        });
        Flex;
        UI_SearchBox(view);
      });

    });

    im.root ~= modules;
    im.root ~= overlay;

    view.subScreenArea = im.clientArea / clientSize;
  }

  override void onPaint(){ // onPaint ///////////////////////////////////////
    gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT);
  }

  void drawSearchResults(Drawing dr, RGB clSearchHighLight){ with(dr){
    const
      blink = float(sqr(sin(blinkf(134.0f/60)*PIf))),
      arrowSize = 12+6*blink,
      arrowThickness = arrowSize*.2f,

      far = view.invScale_anim > 6, //todo: this is a lod
      extra = view.invScale_anim*6*blink,
      bnd = view.subScreenBounds,
      bndInner = bnd.inflated(-view.invScale_anim*arrowThickness*2),
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

    //later pass, so this will always visible
    if(!far){
      foreach(sr; searchResults)
        if(isVisible(sr.bounds))
          sr.drawHighlighted(dr, clSearchHighLight); //close lod
    }
  }}

  void drawOverlay(Drawing dr){
    drawSearchResults(dr, clWhite);
  }

  //todo: off screen targets

  override void afterPaint(){ // afterPaint //////////////////////////////////
  }

}