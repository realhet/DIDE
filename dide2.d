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

// LOD //////////////////////////////////////////

struct LodStruct {
  float zoomFactor=1, pixelSize=1;
  int level;

  bool code=true; //level 0
  bool modules; //level 1
}

__gshared const LodStruct lod;

void setLod(float zoomFactor_){
  with(cast(LodStruct*)(&lod)){
    zoomFactor = zoomFactor_;
    pixelSize = 1/zoomFactor;
    level = pixelSize>6 ? 1 : 0;
    code = level==0;
    modules = level==1;
  }
}

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
    if(lod.level>0){
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

  DateTime loaded, saved, modified;

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
      noHitTest = true;
      dontSearch = true;
      dontLocate = true;
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


  this(){
    loaded = now;
  }

  this(File file_){
    this();

    file = file_.normalized;
    id = "Module:"~this.file.fullName;

    rebuild;
  }

  override void draw(Drawing dr){
    overlay.flags.hidden = !lod.modules;
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
        static if(is(a.cachedDrawing))
          a.cachedDrawing.free;
      }
    }


    if(LMB_released){ // left mouse released //

      //...

      mouseOp = MouseOp.idle;
    }
  }

}


/// WorkSpace ///////////////////////////////////////////////
class WorkSpace : Container{ //this is a collection of opened modules
  File file;
  enum defaultExt = ".dide";

  Module[] modules;
  SelectionManager2!Module selectionManager;

  File[] openQueue;

  bool justLoadedSomething;
  bounds2 justLoadedBounds;

  this(){
    flags.targetSurface = 0;
    flags.noBackground = true;
    fileDialog = new FileDialog(mainWindow.hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)");
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
      subCells_ = cast(Cell[])modules;
    }
  }

  void clear(){
    modules.clear;
    updateSubCells;
  }

  void loadWorkSpace(string jsonData){
    auto fuck = this; fuck.fromJson(jsonData);
    fromModuleSettings;
    updateSubCells;
  }

  string saveWorkSpace(){
    toModuleSettings;
    return this.toJson;
  }

  void loadWorkSpace(File f){
    loadWorkSpace(f.readText(true));
  }

  void saveWorkSpace(File f){
    f.write(saveWorkSpace);
  }

  Module findModule(File file){ const fn = file.normalized; foreach(m; modules) if(m.file==fn) return m; return null; }

  void closeModule(File file){
    //todo: ask user to save if needed
    if(!file) return;
    const idx = modules.map!(m => m.file).countUntil(file);
    if(idx<0) return;
    modules = modules.remove(idx);
    updateSubCells;
  }

  void closeSelectedModules(){
    //todo: ask user to save if needed
    modules = modules.filter!(m => !m.flags.selected).array;
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
    return loadModule(file, vec2(calcBounds.right+24, 0)); //default position
  }

  bool loadModule(in File file, vec2 targetPos){
    if(!file.exists) return false;
    if(auto m = findModule(file)) return false;

    auto m = new Module(file);
    //m.flags.targetSurface = 0; not needed, workSpace is on s0 already
    m.measure;
    m.outerPos = targetPos;
    modules ~= m;
    updateSubCells;

    justLoadedSomething |= true;
    justLoadedBounds |= m.outerBounds;

    return true;
  }

  File[] allFilesFromModule(File mainFile){
    if(!mainFile.exists) return [];
    //todo: not just for //@exe of //@dll
    BuildSettings settings = { verbose : false };
    return buildSystem.findDependencies(mainFile, settings).map!(m => m.file).array;
  }

  auto loadModuleRecursive(File mainFile){
    allFilesFromModule(mainFile).each!(f => loadModule(f));
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

  void update(View2D view){
    updateOpenQueue(1);
    selectionManager.update(lod.modules, view, modules);
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
        view.zoom(searchResults.map!(r => r.bounds).fold!"a|b", 12);
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

  void drawSearchResults(Drawing dr, RGB clSearchHighLight){ with(dr){
    auto view = im.getView;
    const
      blink = float(sqr(sin(blinkf(134.0f/60)*PIf))),
      arrowSize = 12+6*blink,
      arrowThickness = arrowSize*.2f,

      far = lod.level>0,
      extra = lod.pixelSize*6*blink,
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

    //later pass, so this will always visible
    if(!far){
      foreach(sr; searchResults)
        if(isVisible(sr.bounds))
          sr.drawHighlighted(dr, clSearchHighLight); //close lod
    }
  }}

  void drawModuleHighlights(Drawing dr, RGB c){
    const t0 = now;
    foreach(m; modules){
      const dt = (t0-m.loaded).value(second);
      enum T = 2.5, invT = 1.0f/T;
      if(dt<T){
        float a = dt*invT;

        dr.color = c;
        dr.alpha = sqr(1-a);
        dr.fillRect(m.outerBounds);
        dr.alpha = 1;
      }
    }
  }

  protected void drawSelectedModules(Drawing dr, RGB clSelected, float selectedAlpha, RGB clHovered, float hoveredAlpha){ with(dr){
    void doit(Module m){
      dr.fillRect(m.outerBounds);
      const a = dr.alpha;
      dr.alpha = 1;
      dr.drawRect(m.outerBounds);
      dr.alpha = a;
    }

    dr.lineWidth = -1;
    color = clSelected; alpha = selectedAlpha;  foreach(m; modules) if(m.flags.selected) doit(m);
    color = clHovered ; alpha = hoveredAlpha ;  if(auto m = selectionManager.hoveredItem) doit(m);
    alpha = 1;
  }}

  protected void drawSelectionRect(Drawing dr, RGB clRect){
    if(auto bnd = selectionManager.selectionBounds) with(dr) {
      lineWidth = -1;
      color = clRect;
      drawRect(bnd);
    }
  }

  override void onDraw(Drawing dr){ //onDraw //////////////////////////////
    if(lod.modules) drawSelectedModules(dr, clAccent, .3f, clWhite, .1f);
    drawSelectionRect(dr, clWhite);
    drawModuleHighlights(dr, clYellow);
    drawSearchResults(dr, clYellow);

    /*auto bnd = calcBounds;
    if(!bnd.empty){
      dr.color = clGray;
      dr.lineStyle = LineStyle.dash;
      dr.lineWidth = -1;
      dr.drawRect(bnd.inflated(-36));
      dr.lineStyle = LineStyle.normal;
    }*/
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

//  Module[] modules;
  WorkSpace workSpace;
  MainOverlayContainer overlay;

  @VERB("Alt+F4")       void closeApp            (){ PostMessage(hwnd, WM_CLOSE, 0, 0); }
  @VERB("Ctrl+O")       void openFile            (){ workSpace.openModule; }
  @VERB("Ctrl+Shift+O") void openFileRecursive   (){ workSpace.openModuleRecursive; }
  @VERB("Ctrl+W")       void closeWindow         (){ if(lod.modules) workSpace.closeSelectedModules; }
  @VERB("Ctrl+A")       void selectAll           (){ if(lod.modules && !im.wantKeys) workSpace.selectAllModules; }


  File workSpaceFile;
  bool running;

  override void onCreate(){ //onCreate //////////////////////////////////
    workSpace = new WorkSpace;
    workSpaceFile = File(appPath, "default"~WorkSpace.defaultExt);
    overlay = new MainOverlayContainer;

  }

  override void onDestroy(){
    if(running) workSpace.saveWorkSpace(workSpaceFile);
  }

  override void onUpdate(){ // onUpdate ////////////////////////////////////////
    //showFPS = true;

    if(running.chkSet){
      if(workSpaceFile.exists) workSpace.loadWorkSpace(workSpaceFile);
    }

    invalidate; //todo: low power usage
    caption = "DIDE2";
    view.navigate(!im.wantKeys && !inputs.Ctrl.down && !inputs.Alt.down, !im.wantMouse);
    setLod(view.scale_anim);
    callVerbs(this);

    with(im) Panel(PanelPosition.topClient, { margin = "0"; padding = "0";// border = "1 normal gray";
      Row({ //todo: Panel should be a Row, not a Column...
        Row({ workSpace.UI_ModuleBtns; flex = 1; });
      });
    });

    with(im) Panel(PanelPosition.topRight, { margin = "0"; padding = "0";
      workSpace.UI_SearchBox(view);
    });

    with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
      Row({
        Text(hitTestManager.lastHitStack.map!(a => "["~a.id~"]").join(` `));
        NL;
        if(hitTestManager.lastHitStack.length) Text(hitTestManager.lastHitStack.back.text);


        foreach_reverse(m; workSpace.modules){
          foreach(loc; m.locate(view.mousePos)){
            Text("\n", loc.text);
          }
        }
      });
    });

    im.root ~= workSpace;
    im.root ~= overlay;

    view.subScreenArea = im.clientArea / clientSize;

    workSpace.update(view);

    if(chkClear(workSpace.justLoadedSomething)){
      view.zoom(workSpace.justLoadedBounds | view.subScreenBounds);
      workSpace.justLoadedBounds = bounds2.init;
    }

    //todo:cullSubCells ellenorzese
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
        foreach(loc; workSpace.modules.map!(m => m.locate(pos)).joiner){
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


  }

  //todo: off screen targets

  override void afterPaint(){ // afterPaint //////////////////////////////////
  }

}