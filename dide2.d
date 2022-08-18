//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId,AnimatedCursors

///@release
//@debug

//note: debug is not needed to get proper exception information

//todo: buildSystem: the caches (objCache, etc) has no limits. Onli a rebuild clears them.

//todo: wholeWords search (eleje/vege kulon)
//todo: filter search results per file and per syntax (comment, string, code, etc)

//todo: Adam Ruppe search tool -> http://search.dpldocs.info/?q=sleep

//todo: het.math.cmp integration with std

//todo: accept repeared keystrokes even when the FPS is low. (Ctrl+X Shift+Del Del Backspace are really slow now.)

//todo: cs Kod szerkesztonek feltetlen csinald meg, hogy kijelolt szovegreszt kulon ablakban tudj editalni tobb ilyen lehessen esetleg ha egy fuggveny felso soran vagy akkor automatikusan rakja ki a fuggveny torzset
//todo: cs lehessen splittelni: pl egyik tab full kod full scren, a masik tabon meg splittelve ket fuggveny

//todo: Ctrl+ 1..9   Copy to clipboard[n]       Esetleg Ctrl+C+1..9
//todo: Alt + 1..9   Paste from clipboard[n]
//todo: Ctrl+Shift 1..9   Copy to and append to clipboard[n]

import het, het.keywords, het.tokenizer, het.ui, het.dialogs;
import buildsys, core.thread, std.concurrency;

import dideui, didemodule;

alias blink = dideui.blink;

// ugly globals ////////////////////////////////////////

auto frmMain(){ return (cast(FrmMain)mainWindow); }
auto global_getBuildResult(){ return frmMain.buildResult; }
auto global_getMarkerLayerHideMask(){ return frmMain.workspace.markerLayerHideMask; }

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



struct ContainerSelectionManager(T : Container){ // ContainerSelectionManager ///////////////////////////////////////////////
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


struct TextSelectionManager{ // TextSelectionManager /////////////////////////////////////////

  TextCursor cursorAtMouse, cursorToExtend;
  TextSelection selectionAtMouse;
  TextSelection[] selectionsWhenMouseWasPressed;
  bool mouseScrolling;

  Nullable!vec2 scrollInRequest;

  DateTime lastMainMousePressTime;

  bool wordSelecting;

  ClickDetector cdMainMouseButton;

  void update(View2D view, ref TextSelection[] textSelections, Workspace workspace, in Workspace.MouseMappings mouseMappings){
    scrollInRequest.nullify;

    //detect double click with LMB
    cdMainMouseButton.update(inputs[mouseMappings.main].down);
    const doubleClick = cdMainMouseButton.doubleClicked;

    if(doubleClick) wordSelecting = true;

    //check if a keycombo modifier with the main mouse button isactive
    bool kc(string sh){ return KeyCombo([sh, mouseMappings.main].join("+")).active; }

    auto cursorAtMouse = workspace.cellLocationToTextCursor(workspace.locate(view.mousePos));

    //initiate mouse operations
    if(!im.wantMouse){
      if(view.isMouseInside) if(auto dw = inputs[mouseMappings.zoom].delta) view.zoomAroundMouse(dw*workspace.wheelSpeed);

      if(frmMain.isForeground && view.isMouseInside && inputs[mouseMappings.scroll].pressed) mouseScrolling = true;

      if(frmMain.isForeground && view.isMouseInside && lod.codeLevel) if(inputs[mouseMappings.main].pressed){
        if(textSelections.hitTest(view.mousePos)){ //todo: start dragging

        }else if(cursorAtMouse.valid){ //start selecting with mouse
          selectionsWhenMouseWasPressed = textSelections.dup;

          //extension cursor is the nearest selection.cursors[0]
          if(!doubleClick)
            cursorToExtend = selectionsWhenMouseWasPressed.filter!(a => a.codeColumn is cursorAtMouse.codeColumn)
                                                          .minElement!(a => distance(a, cursorAtMouse))(TextSelection.init)
                                                          .cursors[0];
          if(!cursorToExtend.valid) cursorToExtend = cursorAtMouse; //defaults extension pos is mouse press pos.

          selectionAtMouse = TextSelection([cursorAtMouse, cursorAtMouse]);
        }
      }
    }

    if(mouseScrolling){
      if(!inputs[mouseMappings.scroll]){
        mouseScrolling = false;
      }else{
        if(const delta = inputs.mouseDelta)
          view.scroll(delta);
      }
    }

    if(selectionAtMouse.valid && frmMain.isForeground && inputs[mouseMappings.main]){
      //restrict mousePos to the codeColumn bounds
      auto bnd = worldInnerBounds(selectionAtMouse.codeColumn);
      bnd.high -= 1; //make sure it's inside

      const restrictedMousePos = kc(mouseMappings.selectColumn) || kc(mouseMappings.selectColumnAdd)
                                 ? restrictPos_normal(view.mousePos, bnd) //normal clamping for columnSelect
                                 : restrictPos_editor(view.mousePos, bnd); //text editor clamping for normal select

      auto restrictedCursorAtMouse = workspace.cellLocationToTextCursor(workspace.locate(restrictedMousePos));

      if(restrictedCursorAtMouse.valid && restrictedCursorAtMouse.codeColumn==selectionAtMouse.codeColumn){
        selectionAtMouse.cursors[1] = restrictedCursorAtMouse;
      }

      scrollInRequest = restrictPos_normal(view.mousePos, bnd); //always normal clipping for mouse focus point
    }

    void endMouseSelection(){
      selectionAtMouse = TextSelection.init;
      selectionsWhenMouseWasPressed = [];
      wordSelecting = false;
    }

    //finalize mouse select
    if(selectionAtMouse.valid && !inputs[mouseMappings.main]){
      endMouseSelection;
    }

    //combine selection with mouse selection
    if(selectionAtMouse.valid){
      //todo: for additive operations, only the selections on the most recent

      auto applyWordSelect   (TextSelection   s){ return wordSelecting ? s.extendToWordsOrSpaces : s; }
      auto applyWordSelectArr(TextSelection[] s){ return wordSelecting ? s.map!(a => a.extendToWordsOrSpaces).array : s; }

      if(kc(mouseMappings.selectColumn) || kc(mouseMappings.selectColumnAdd)){
        //Column select
        auto c0 = kc(mouseMappings.selectColumnAdd) ? selectionAtMouse.cursors[0] : cursorToExtend,
             c1 = selectionAtMouse.cursors[1];
        const downward = c0.pos.y<c1.pos.y,
              dir      = downward ? 1 : -1,
              count    = abs(c0.pos.y-c1.pos.y)+1;

        auto a0 = iota(count).map!((i){ auto res = c0; c0.move(ivec2(0,  dir)); return res; }).array,
             a1 = iota(count).map!((i){ auto res = c1; c1.move(ivec2(0, -dir)); return res; }).array;

        if(downward) a1 = a1.retro.array;
                else a0 = a0.retro.array;

        textSelections = iota(count).map!(i => TextSelection([a0[i], a1[i]])).array;
        //textSelections[0].primary = true;//todo: mark primary

        if(!downward) textSelections = textSelections.retro.array; //make it sorted

        //if there are any nonZeroLength selections, remove all zeroLength carets
        if(textSelections.any!"!a.isZeroLength")
          textSelections = textSelections.remove!"a.isZeroLength";

        //if all are carets, remove those at line ends

        if(textSelections.all!"a.isZeroLength" && !textSelections.all!"a.isAtLineStart" && !textSelections.all!"a.isAtLineEnd")
          textSelections = textSelections.remove!"a.isAtLineEnd";

        textSelections = applyWordSelectArr(textSelections);

        if(kc(mouseMappings.selectColumnAdd)){ //Ctrl+Alt+Shift = add column selection
          textSelections = merge(selectionsWhenMouseWasPressed ~ textSelections);
        }

      }else if(kc(mouseMappings.selectAdd)){
        auto s = applyWordSelect(selectionAtMouse);
        textSelections = selectionsWhenMouseWasPressed.filter!(a => !touches(a, s)).array ~ s;
      }else if(kc(mouseMappings.selectExtend)){
        auto s = applyWordSelect(TextSelection([cursorToExtend, selectionAtMouse.caret]));
        textSelections = selectionsWhenMouseWasPressed.filter!(a => !touches(a, s)).array ~ s;
      }else{
        auto s = applyWordSelect(selectionAtMouse);
        textSelections = [s]; //todo: mark this as the primary selection. Extend will work on that.
      }

      //add extra

      //todo: some selection operations may need 'overlaps' instead of 'touches'. Overlap only touch when on operand is a zeroLength selection.
    }
  }

}


/// Workspace ///////////////////////////////////////////////
class Workspace : Container{ //this is a collection of opened modules
  File file; //the file of the workspace
  enum defaultExt = ".dide";

  File[] openQueue;
  Module[] modules;

  @STORED File mainModuleFile;
  @property{
    Module mainModule(){ return findModule(mainModuleFile); }
    void mainModule(Module m){ enforce(modules.canFind(m), "Invalid module."); enforce(m.isMain, "This module can't be selected as main module."); mainModuleFile = m.file; }
  }

  ContainerSelectionManager!Module moduleSelectionManager;
  TextSelectionManager textSelectionManager;

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
  size_t textSelectionsHash;

  FileDialog fileDialog;

  this(){
    flags.targetSurface = 0;
    flags.noBackground = true;
    fileDialog = new FileDialog(mainWindow.hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)");
    needMeasure;
  }

  override void rearrange(){
    super.rearrange;
    static if(rearrangeLOG) LOG("rearranging", this);
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

    void dropInvalidTextSelections(){
      bool isModuleExists(const TextSelection ts){
        return modules.map!(m => m.code).canFind(ts.cursors[0].codeColumn); //opt: linear. Also when a codeColumns dies, it should remove the textSelections too.
      }
      textSelections = textSelections.filter!(ts => isModuleExists(ts)).array;
    }

    void updateSubCells(){
      dropInvalidTextSelections;
      subCells = cast(Cell[])modules;
    }
  }

  void clear(){
    modules = [];
    textSelections = [];
    updateSubCells;
  }

  void loadWorkspace(string jsonData){
    auto fuck = this; fuck.fromJson(jsonData);
    fromModuleSettings;
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
  auto unselectedModules(){ return modules.filter!(m => !m.flags.selected).array; }
  auto hoveredModule(){ return moduleSelectionManager.hoveredItem; }

  private void closeSelectedModules_impl(){
    //todo: ask user to save if needed
    modules = unselectedModules;
    updateSubCells;
  }

  private void closeAllModules_impl(){
    //todo: ask user to save if needed
    clear;
  }

  bool loadModule(in File file){
    const vec2 targetPos = lastModulePositions.get(file.actualFile.hashOf, vec2(calcBounds.right+24, 0));
    return loadModule(file, targetPos); //default position
  }

  bool loadModule(in File file, vec2 targetPos){
    if(!file.exists) return false;
    if(auto m = findModule(file)){
      m.loaded = now; //it's just a flash indicator
      frmMain.view.smartScrollTo(m.outerBounds);
      return false; //no loading was issued
    }

    auto m = new Module(this, file);

    //m.flags.targetSurface = 0; not needed, workspace is on s0 already
    m.measure;
    m.outerPos = targetPos;
    modules ~= m;
    updateSubCells;

    /+justLoadedSomething |= true;
    justLoadedBounds |= m.outerBounds; +/

    frmMain.view.smartScrollTo(m.outerBounds);

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

  override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0)){  //locate ////////////////////////////////
    ofs += innerPos;
    foreach_reverse(m; modules){
      auto st = m.locate(mouse, ofs);
      if(st.length) return st;
    }
    return [];
  }

  CodeLocation cellLocationToCodeLocation(CellLocation[] st){
    auto a(T)(void delegate(T) f){ if(auto x = cast(T)st.get(0).cell){ st.popFront; f(x); } }

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

  static CellLocation[] findLastCodeRow(CellLocation[] st){
    foreach_reverse(i; 0..st.length){
      auto row = cast(CodeRow)st[i].cell;
      if(row) return st[i..$];
    }
    return [];
  }

  TextCursor cellLocationToTextCursor(CellLocation[] st){ //todo: TextCursor should contain the codeRow, not the textSelection.
    TextCursor res;
    st = findLastCodeRow(st);
    if(auto row = cast(CodeRow)st.get(0).cell){
      auto cell = st.get(1).cell;
      res.codeColumn = row.parent;

      res.desiredX = st[0].localPos.x;
      res.pos.y = row.index;

      //find x character index
      int x;
      if(cell){
        x = row.subCellIndex(cell);
        assert(x>=0);
        if(st[1].localPos.x>cell.innerWidth/2) x++;
      }else{
        x = res.desiredX<0 ? 0 : row.cellCount;
      }
      assert(x.inRange(0, row.cellCount));
      res.pos.x = x;
    }
    return res;
  }

  // textSelection, cursor movements /////////////////////////////

  int lineSize(){ return DefaultFontHeight; }
  int pageSize(){ return (frmMain.view.subScreenBounds_anim.height/lineSize*.9f).iround.clamp(2, 100); }
  void cursorOp(ivec2 dir, bool select){
    foreach(ref ts; textSelections) ts.move(dir, select);
    textSelections = merge(textSelections);
  }

  void scrollV(float dy){ frmMain.view.scrollV(dy); }
  void scrollH(float dx){ frmMain.view.scrollH(dx); }
  void zoom(float log){ frmMain.view.zoom(log); }

  float scrollSpeed(){ return frmMain.deltaTime.value(second)*2000; }
  float zoomSpeed(){ return frmMain.deltaTime.value(second)*8; }
  float wheelSpeed = 0.375f;

  void insertCursor(int dir){
    auto newTextSelections = textSelections.dup;
    foreach(ref ts; newTextSelections){
      ts.cursors[0].move(ivec2(0, dir));
      ts.cursors[1].move(ivec2(0, dir));
    }

    textSelections = merge(textSelections ~ newTextSelections);
  }

  bool copy_impl(TextSelection[] textSelections){  // copy ///////////////////////////////////////
    auto copiedSourceText = textSelections.exportSourceText;
    bool valid = copiedSourceText.length>0;
    if(valid) clipboard.asText = copiedSourceText;
    return valid;
  }

  void cut_impl(TextSelection[] textSelections, void delegate(CodeRow left, CodeRow right) onRowJoin){  // cut ////////////////////////////////////////

    foreach_reverse(sel; textSelections) if(!sel.isZeroLength)if(auto col = sel.codeColumn){
      const st = sel.start,
            en = sel.end;

      foreach_reverse(y; st.pos.y..en.pos.y+1){ //todo: this loop is in the draw routine as well. Must refactor and reuse
        if(auto row = col.getRow(y)){
          const rowCellCount = row.cellCount;

          const isFirstRow = y==st.pos.y,
                isLastRow  = y==en.pos.y,
                isMidRow   = !isFirstRow && !isLastRow;
          if(isMidRow){ //delete whole row
            col.subCells = col.subCells.remove(y);
          }else{ //delete partial row
            const x0 = isFirstRow ? st.pos.x : 0,
                  x1 = isLastRow  ? en.pos.x : rowCellCount+1;
            foreach_reverse(x; x0..x1){
              if(x>=0 && x<rowCellCount){
                row.subCells = row.subCells.remove(x);  //opt: this is not so fast. It removes 1 by 1.
              }else if(x==rowCellCount){ //newLine
                if(auto nextRow = col.getRow(y+1)){
                  onRowJoin(row, nextRow);

                  row.append(nextRow.subCells);
                  row.adoptSubCells;

                  nextRow.subCells = [];
                  col.subCells = col.subCells.remove(y+1);
                }else assert(0, "TextSelection out of range NL");
              }else assert(0, "TextSelection out of range X");
            }
            row.refreshTabIdx;
            row.refresh;
          }

        }else assert(0, "TextSelection out of range Y");
      }//for y

      if(st.pos.x==0 && en.pos.x==0){
        if(auto r = col.getRow(st.pos.y-1)) r.setChangedRemovedNext;
        if(auto r = col.getRow(st.pos.y  )) r.setChangedRemovedPrev;
      }else{
        if(auto r = col.getRow(st.pos.y  )) r.setChangedModified;
      }

    }else assert(0, "TextSelection invalid CodeColumn");
  }

  void paste_impl(Flag!"fromClipboard" fromClipboard, string input, Flag!"duplicateTabs" duplicateTabs = No.duplicateTabs){ // paste //////////////////////////////////
    if(textSelections.filter!"a.valid".empty) return; //no target

    if(fromClipboard)
      input = clipboard.asText;

    auto lines = input.splitLines;
    if(lines.empty) return; //nothing to do with an empty clipboard

    cut(No.copy, No.fullRows);

    TextSelectionReference[] savedSelections;

    ///inserts text at cursor, moves the corsor to the end of the text
    void simpleInsert(ref TextSelection ts, string str){
      assert(ts.valid);  assert(ts.isZeroLength);  assert(ts.caret.pos.y.inRange(ts.codeColumn.subCells));
      if(auto row = ts.codeColumn.getRow(ts.caret.pos.y)){
        row.setChangedModified;

        const insertedCnt = row.insertText(ts.caret.pos.x, str); //todo: shift adjust selections that are on this row

        //adjust caret and save
        ts.cursors[0].moveRight(insertedCnt);
        ts.cursors[1] = ts.cursors[0];
        savedSelections ~= ts.toReference;
      }else assert("Row out if range");
    }

    void multiInsert(ref TextSelection ts, string[] lines ){
      assert(ts.valid);  assert(ts.isZeroLength);  assert(lines.length>=2);
      if(auto row = ts.codeColumn.getRow(ts.caret.pos.y)){
        assert(ts.caret.pos.x>=0 && ts.caret.pos.x<=row.subCells.length);

        //handle leadingTab duplication
        const extraLeadingTabs = "\t".replicate(duplicateTabs ? row.leadingTabCount : 0);

        //break the row into 2 parts
        //transfer the end of (first)row into a lastRow
        auto lastRow = row.splitRow(ts.caret.pos.x);
        if(lastRow.cellCount) row.setChangedModified;
        lastRow.setChangedCreated;

        //insert at the end of the first row
        if(row.insertText(row.cellCount, lines.front)) row.setChangedModified;

        //create extra rows in the middle
        Cell[] midRows;
        foreach(line; lines[1..$-1]){
          auto r = new CodeRow(ts.codeColumn, line);
          r.setChangedCreated;
          midRows ~= r;
        }

        //insert at the beginning of the last row
        const insertedCnt = lastRow.insertText(0, extraLeadingTabs ~ lines.back);
        if(insertedCnt) lastRow.setChangedModified;

        //insert modified rows into column
        ts.codeColumn.subCells = ts.codeColumn.subCells[0..ts.caret.pos.y+1]
                               ~ midRows
                               ~ lastRow
                               ~ ts.codeColumn.subCells[ts.caret.pos.y+1..$];

        //adjust caret and save as reference
        ts.cursors[0].pos.y += lines.length.to!int-1;
        ts.cursors[0].pos.x = insertedCnt;
        ts.cursors[1] = ts.cursors[0];
        savedSelections ~= ts.toReference;

        //todo:update caret
      }else assert("Row out if range");
    }

    ///insert all lines into the selection
    void fullInsert(ref TextSelection ts){
      if(lines.length==1){ //simple text without newline
        simpleInsert(ts, lines[0]);
      }else if(lines.length>1){ //insert multiline text
        multiInsert(ts, lines);
      }
    }

    if(textSelections.length==1){ //put all the clipboard into one place
      fullInsert(textSelections[0]);
    }else if(textSelections.length>1){
      if(lines.length>textSelections.length){ //clone the full clipboard into all selections.
        foreach_reverse(ref ts; textSelections)
          fullInsert(ts);
      }else{ //cyclically paste the lines of the clipboard
        foreach_reverse(ref ts, line; lockstep(textSelections, lines.cycle.take(textSelections.length)))
          simpleInsert(ts, line);
      }
    }

    measure;
    textSelections = savedSelections.retro.map!"a.fromReference".filter!"a.valid".array;
  }


  // Module operations ------------------------------------------------
  Nullable!bounds2 scrollInBoundsRequest;

  @VERB("Ctrl+O"                        ) void openModule           () { fileDialog.openMulti.each!(f => queueModule         (f)); }
  @VERB("Ctrl+Shift+O"                  ) void openModuleRecursive  () { fileDialog.openMulti.each!(f => queueModuleRecursive(f)); }
  @VERB("Ctrl+A"                        ) void selectAllModules     () { modules.each!(m => m.flags.selected = true);} //todo: selectAll for the editors
  @VERB(""                              ) void deselectAllModules   () { modules.each!(m => m.flags.selected = false); }
  @VERB("Ctrl+W"                        ) void closeSelectedModules () { closeSelectedModules_impl; }
  @VERB("Ctrl+Shift+W"                  ) void closeAllModules      () { closeAllModules_impl; }
  @VERB("Esc"                           ) void cancelSelection      () {
    if(lod.moduleLevel){
      deselectAllModules;
    }

    if(lod.codeLevel){
      if(textSelections.length>1){
        textSelections.length = 1;
        with(textSelections[0]){
          scrollInBoundsRequest = worldBounds(textSelections);
        }
        //todo: scroll in
      }else if(textSelections.length==1) with(textSelections[0]){
        if(valid && !isZeroLength){
          cursors[0] = cursors[1];
          scrollInBoundsRequest = worldBounds(textSelections);
        }else{
          textSelections = [];
          if(modules.length) scrollInBoundsRequest = modules.map!"a.outerBounds".fold!"a|b";
        }
      }
    }
  }

  /+todo: uzemmod fuggest megoldani: A Ctrl+A ha editing van, akkor az editalt modulra vonatkozzon, tavoli nezetben viszont a kivalasztott modulokra. Ezt a kettot valahogy ossze kellene egysegesiteni.
          nem vilagos, hogy a ctrl+W az mire vonatkozik...+/

  // Cursor and text selection ----------------------------------------

  @VERB("Left"                          ) void cursorLeft       (bool sel=false){ cursorOp(ivec2(-1,  0)                 , sel); }
  @VERB("Right"                         ) void cursorRight      (bool sel=false){ cursorOp(ivec2( 1,  0)                 , sel); }
  @VERB("Ctrl+Left"                     ) void cursorWordLeft   (bool sel=false){ cursorOp(ivec2(TextCursor.wordLeft , 0), sel); }
  @VERB("Ctrl+Right"                    ) void cursorWordRight  (bool sel=false){ cursorOp(ivec2(TextCursor.wordRight, 0), sel); }
  @VERB("Home"                          ) void cursorHome       (bool sel=false){ cursorOp(ivec2(TextCursor.home     , 0), sel); }
  @VERB("End"                           ) void cursorEnd        (bool sel=false){ cursorOp(ivec2(TextCursor.end      , 0), sel); }
  @VERB("Up"                            ) void cursorUp         (bool sel=false){ cursorOp(ivec2( 0, -1)                 , sel); }
  @VERB("Down"                          ) void cursorDown       (bool sel=false){ cursorOp(ivec2( 0,  1)                 , sel); }
  @VERB("PgUp"                          ) void cursorPageUp     (bool sel=false){ cursorOp(ivec2( 0, -pageSize)          , sel); }
  @VERB("PgDn"                          ) void cursorPageDown   (bool sel=false){ cursorOp(ivec2( 0,  pageSize)          , sel); }
  @VERB("Ctrl+Home"                     ) void cursorTop        (bool sel=false){ cursorOp(ivec2(TextCursor.home)        , sel); }
  @VERB("Ctrl+End"                      ) void cursorBottom     (bool sel=false){ cursorOp(ivec2(TextCursor.end )        , sel); }

  @VERB("Shift+Left"                    ) void cursorLeftSelect       (){ cursorLeft       (true); }  //bug: shift+left many times, then Down: nem a caret ala' ugrik, hanem a cursors[0] ala'
  @VERB("Shift+Right"                   ) void cursorRightSelect      (){ cursorRight      (true); }
  @VERB("Shift+Ctrl+Left"               ) void cursorWordLeftSelect   (){ cursorWordLeft   (true); }
  @VERB("Shift+Ctrl+Right"              ) void cursorWordRightSelect  (){ cursorWordRight  (true); }
  @VERB("Shift+Home"                    ) void cursorHomeSelect       (){ cursorHome       (true); }
  @VERB("Shift+End"                     ) void cursorEndSelect        (){ cursorEnd        (true); }
  @VERB("Shift+Up Shift+Ctrl+Up"        ) void cursorUpSelect         (){ cursorUp         (true); }
  @VERB("Shift+Down Shift+Ctrl+Down"    ) void cursorDownSelect       (){ cursorDown       (true); }
  @VERB("Shift+PgUp"                    ) void cursorPageUpSelect     (){ cursorPageUp     (true); }
  @VERB("Shift+PgDn"                    ) void cursorPageDownSelect   (){ cursorPageDown   (true); }
  @VERB("Shift+Ctrl+Home"               ) void cursorTopSelect        (){ cursorTop        (true); }
  @VERB("Shift+Ctrl+End"                ) void cursorBottomSelect     (){ cursorBottom     (true); }  //bug: 1. press [Shift End], 2. press[End]   //same with home

  @VERB("Ctrl+Alt+Up"                   ) void insertCursorAbove      (){ insertCursor(-1); }
  @VERB("Ctrl+Alt+Down"                 ) void insertCursorBelow      (){ insertCursor( 1); }

  @VERB("Shift+Alt+Left"                ) void shrinkAstSelection     (){  }  //todo: shrink/extend Ast Selection
  @VERB("Shift+Alt+Right"               ) void extendAstSelection     (){  }
  @VERB("Shift+Alt+I"                   ) void insertCursorAtEndOfEachLineSelected (){  }

  // Navigation ---------------------------------------------

  @VERB("Ctrl+Up"             ) void scrollLineUp           (){ scrollV( DefaultFontHeight); }
  @VERB("Ctrl+Down"           ) void scrollLineDown         (){ scrollV(-DefaultFontHeight); }
  @VERB("Alt+PgUp"            ) void scrollPageUp           (){ scrollV( frmMain.clientHeight*.9); }
  @VERB("Alt+PgDn"            ) void scrollPageDown         (){ scrollV(-frmMain.clientHeight*.9); }
  @VERB("Ctrl+="              ) void zoomIn                 (){ zoom( .5); }
  @VERB("Ctrl+-"              ) void zoomOut                (){ zoom(-.5); }

  @HOLD("Ctrl+Num8"           ) void holdScrollUp           (){ scrollV( scrollSpeed); }
  @HOLD("Ctrl+Num2"           ) void holdScrollDown         (){ scrollV(-scrollSpeed); }
  @HOLD("Ctrl+Num4"           ) void holdScrollLeft         (){ scrollH( scrollSpeed); }
  @HOLD("Ctrl+Num6"           ) void holdScrollRight        (){ scrollH(-scrollSpeed); }
  @HOLD("Ctrl+Num+"           ) void holdZoomIn             (){ zoom( zoomSpeed); }
  @HOLD("Ctrl+Num-"           ) void holdZoomOut            (){ zoom(-zoomSpeed); }

  @HOLD("Alt+Ctrl+Num8"       ) void holdScrollUp_slow      (){ scrollV( scrollSpeed/8); }
  @HOLD("Alt+Ctrl+Num2"       ) void holdScrollDown_slow    (){ scrollV(-scrollSpeed/8); }
  @HOLD("Alt+Ctrl+Num4"       ) void holdScrollLeft_slow    (){ scrollH( scrollSpeed/8); }
  @HOLD("Alt+Ctrl+Num6"       ) void holdScrollRight_slow   (){ scrollH(-scrollSpeed/8); }
  @HOLD("Alt+Ctrl+Num+"       ) void holdZoomIn_slow        (){ zoom( zoomSpeed/8); }
  @HOLD("Alt+Ctrl+Num-"       ) void holdZoomOut_slow       (){ zoom(-zoomSpeed/8); }

  // Editing ------------------------------------------------

  @VERB("Ctrl+X Shift+Del"    ) void cut(Flag!"copy" doCopy = Yes.copy, Flag!"fullRows" doFullRows = Yes.fullRows){

    //prepare textSelections
    textSelections = doFullRows ? textSelections.zeroLengthSelectionsToFullRowsAndMerge
                                : textSelections.merge;

    auto savedSelections = textSelections.map!"a.toReference".array;

    if(doCopy) copy_impl(textSelections);

    cut_impl(textSelections, (left, right){
      foreach(ref ss; savedSelections)   //opt: must not go througn all selection. It could binary search the start position to iterate.
        ss.replaceLatestRow(right, left);
    });

    measure;
    textSelections = savedSelections.map!"a.fromReference".filter!"a.valid".array;
  }

  protected void deleteAtLeastOneChar(Flag!"toLeft" toLeft){
    //extend zero length selections to the lefto or to the right with 1 char
    const dir = toLeft ? -1 : 1;

    textSelections.each!((ref s){
      if(s.valid && s.isZeroLength)
        s.move(ivec2(dir, 0), true);
    });

    cut(No.copy, No.fullRows);
  }

  @VERB("Ctrl+C Ctrl+Ins"     ) void copy             (){ copy_impl(textSelections.zeroLengthSelectionsToFullRowsAndMerge); }
  //bug: selection.isZeroLength Ctrl+C then Ctrl+V   It breaks the line.  Ez megjegyzi, hogy volt-e selection extension es ha igen,
  //akkor sorokon dolgozik. A sorokon tolgozas feltetele az, hogy a target is zeroLength legyen.

  //todo: paste replace leading spaces with tabs. !!! -> Not good when pasting string literals.

  @VERB("Backspace"           ) void deleteToLeft     (){ deleteAtLeastOneChar(Yes.toLeft); } //todo: delete leading tabs in one step.
  @VERB("Del"                 ) void deleteFromRight  (){ deleteAtLeastOneChar(No .toLeft); }

  @VERB("Ctrl+V Shift+Ins"    ) void paste            (){ paste_impl(Yes.fromClipboard, ""); }

  @VERB("Tab"                 ) void insertTab        (){ paste_impl(No.fromClipboard, "\t"); }
  @VERB("Enter"               ) void insertNewLine    (){ paste_impl(No.fromClipboard, "\n", Yes.duplicateTabs); }

  //todo: Ctrl+D word select and find

  // Mouse ---------------------------------------------------

  struct MouseMappings{
    string main                  = "LMB",
           scroll                = "MMB",   //todo: soft scroll/zoom, fast scroll
           menu                  = "RMB",
           zoom                  = "MW",
           selectAdd             = "Alt",
           selectExtend          = "Shift",
           selectColumn          = "Shift+Alt",
           selectColumnAdd       = "Ctrl+Shift+Alt";
  }

  void handleKeyboard(){
    if(!im.wantKeys && frmMain.isForeground){
      callVerbs(this);

      //todo: single window only
      string unprocessed;
      foreach(ch; mainWindow.inputChars.unTag.byDchar){
        if(ch==9 && ch==10){
          //if(flags.acceptEditorKeys) cmdQueue ~= EditCmd(cInsert, [ch].to!string);
        }else if(ch>=32){
          //cmdQueue ~= EditCmd(cInsert, [ch].to!string);
          try{
            //if(ch=='`') ch = '\U0001F4A9'; //todo: unable to input emojis from keyboard or clipboard! Maybe it's a bug.
            auto s = ch.to!string;
            paste_impl(No.fromClipboard, s);
          }catch(Exception){
            unprocessed ~= ch;
          }

        }else{
          unprocessed ~= ch;
        }
      }
      mainWindow.inputChars = unprocessed;

    }
  }

  void update(View2D view, in BuildResult buildResult){ //update ////////////////////////////////////

    // Start of possible modifications ----------------------------------------------------

    handleKeyboard;
    updateOpenQueue(1);
    moduleSelectionManager.update(!im.wantMouse && mainWindow.isForeground && view.isMouseInside && lod.moduleLevel, view, modules);
    textSelectionManager  .update(view, textSelections, this, MouseMappings.init);

    // End of modifications ----------------------------------------------------
    measure;
/*    foreach(m; modules){
      if(m.flags.
    }*/



    //detect textSelection change
    const selectionChanged = textSelectionsHash.chkSet(textSelections.hashOf);

    //focus at selection
    if(!scrollInBoundsRequest.isNull){
      const b = scrollInBoundsRequest.get;
      frmMain.view.scrollZoom(b);
    }else if(!textSelectionManager.scrollInRequest.isNull){
      const p = textSelectionManager.scrollInRequest.get;
      frmMain.view.scrollZoom(bounds2(p, p));
    }else if(selectionChanged){
      frmMain.view.scrollZoom(worldBounds(textSelections)); //todo: focus the extents of the changed areas, not just the carets... This should be controlled by the direction of the operation...
    }
    scrollInBoundsRequest.nullify;

    //animate cursors
    version(AnimatedCursors){
      if(textSelections.length<=MaxAnimatedCursors){
        const animT = calcAnimationT(application.deltaTime.value(second), .5, .25),
              maxDist = 1.0f;

        foreach(ref ts; textSelections){
          foreach(ref cr; ts.cursors[]) with(cr){
           targetPos = localPos.pos; //todo: animate height as well
           if(animatedPos.x.isnan) animatedPos = targetPos;
                                 else animatedPos.follow(targetPos, animT, maxDist);
          }
        }
      }
    }

    //update buildresults if needed (compilation progress or layer mask change)
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

  deprecated void UI_ModuleBtns(){ with(im){
    File fileToClose;
    foreach(m; modules){
      if(Btn(m.file.name, hint(m.file.fullName), genericId(m.file.fullName), selected(0), { fh = 12; theme="tool"; if(Btn(symbol("Cancel"))) fileToClose = m.file; })) {}
    }
    if(Btn(symbol("Add"))) openModule;

    if(Btn("Close All", KeyCombo("Ctrl+Shift+W"))){
      closeAllModules;
    }

    if(fileToClose) closeModule(fileToClose);
  }}

  //! Save/Undo/History system ////////////////////////////////////////////////

  // 3 levels
  // 1. Save, SaveAll (ehhez csak egy olyan kell, hogy a legutolso save/load ota a user beleirt-e valamit.   Hierarhikus formaban lennenek a changed flag-ek, a soroknal meg lenne 2 extra: removedNextRow, removedPrevRow)
  // 2. Opcionalis Undo: ez csak 2 save kozott mukodhetne. Viszont a redo utani modositas nem semmisitene meg az utana levo undokat, hanem csak becsatlakoztatna a graph-ba. Innentol nem idovonal van, hanem graph.
  // 3. Opcionalis history: Egy kulon konyvtarba behany minden menteskori es betolteskori allapotot. Ezt kesobb delta codinggal tomoriteni kell.


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

        /*if(loc.file && loc.line){
          if(loc.column) with(findModule(loc.file).code){
            const pos = ivec2(loc.column, loc.line)-1;
            Text("   ", pos.text);
          }else with(findModule(loc.file).code){
            const pos = ivec2(st.back.localPos.x<=0 ? 0 : rows[loc.line-1].cellCount, loc.line-1);
            Text("   ", pos.text);
          }
        }*/

        /*auto crsr = cellLocationToTextCursor(st);
        if(crsr.valid){
          Text("   ", crsr.text, "   ", crsr.toReference.text, "   ", crsr.worldPos.text, "   ", view.mousePos.text);
        }*/

        foreach(sel; textSelections.take(3)){
          Text("\n", sel.toReference.text, "\n    ", sel.toReference.fromReference.text);
        }
      });
    }
  }}

  //! draw routines ////////////////////////////////////////////////////

  void drawSearchResults(Drawing dr, in SearchResult[] searchResults, RGB clSearchHighLight){ with(dr){
    auto view = im.getView;
    const
      arrowSize = 12+3*blink,
      arrowThickness = arrowSize*.2f,

      far = lod.level>1,
      extra = lod.pixelSize*2*blink,
      bnd = view.subScreenBounds_anim,
      bndInner = bnd.inflated(-lod.pixelSize*arrowThickness*2),
      bndInnerSizeHalf = bndInner.size/2,
      center = bnd.center;

    color = clSearchHighLight;

    bool isVisible(T)(in T b){ return bnd.overlaps(b); }

    //always draw these
    color = clSearchHighLight;
    foreach(sr; searchResults) if(sr.cells.length){
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
    selectedModules.each!(m => drawHighlight(dr, m, clSelected, selectedAlpha));
    drawHighlight(dr, hoveredModule, clHovered, hoveredAlpha);
  }}

  protected void drawSelectionRect(Drawing dr, RGB clRect){
    if(auto bnd = moduleSelectionManager.selectionBounds) with(dr) {
      lineWidth = -1;
      lineStyle = LineStyle.dash;
      color = clRect;
      drawRect(bnd);
      lineStyle = LineStyle.normal;
    }
  }

  protected void drawMainModuleOutlines(Drawing dr){
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

  void drawTextSelections(Drawing dr, View2D view){ //drawTextSelections ////////////////////////////
    scope(exit) dr.alpha = 1;

    const near       = lod.zoomFactor.smoothstep(0.02, 0.1);
    const clSelected = mix(mix(RGB(0x404040), clGray, near*.66f),
                           mix(clWhite      , clGray, near*.66f), blink);
    const clCaret    = clWhite;
    const alpha = mix(0.75f, .4f, near);

    const cullBounds = view.subScreenBounds_anim;

    dr.color = clSelected;
    dr.alpha = alpha;
    foreach(sel; textSelections) if(!sel.isZeroLength){
      auto col = sel.codeColumn;
      const colInnerPos = worldInnerPos(col), //opt: group selections by codeColumn.
            colInnerBounds = bounds2(colInnerPos, colInnerPos+col.innerSize);
      if(cullBounds.overlaps(colInnerBounds)){
        const localCullBounds = cullBounds - colInnerPos;
        auto st = sel.start,
             en = sel.end;

        foreach(y; st.pos.y..en.pos.y+1){ //todo: this loop is in the copy routine as well. Must refactor and reuse
          auto row = col.rows[y];
          const rowCellCount = row.cellCount;

          //culling
          if(row.outerBottom < localCullBounds.top   ) continue;  //opt: trisect
          if(row.outerTop    > localCullBounds.bottom) break;

          const isFirstRow = y==st.pos.y,
                isLastRow  = y==en.pos.y;
          const x0 = isFirstRow ? st.pos.x : 0,
                x1 = isLastRow  ? en.pos.x : rowCellCount+1;
          const rowInnerPos = colInnerPos + row.innerPos;

          dr.translate(rowInnerPos); scope(exit) dr.pop;

          if(lod.level<=1){
            foreach(x; x0..x1){

              void fade(bounds2 bnd){
                dr.color = clSelected;
                dr.alpha = alpha;

                enum gap = .5f;
                if(isFirstRow){ bnd.top    += gap; if(x==x0  ) bnd.left  += gap; }
                if(isLastRow ){ bnd.bottom -= gap; if(x==x1-1) bnd.right -= gap; }
                dr.fillRect(bnd);
              }

              assert(x.inRange(0, rowCellCount), "out of range");
              if(x<rowCellCount){
                //todo: make the nice version: the font will be NOT blended to gray, but it hides the markerLayers completely. Should make a text drawer that uses alpha on the background and leaves the font color as is.
                /+if(auto g = row.glyphs[x]){
                  const old = tuple(g.bkColor, g.fontColor);
                  g.bkColor = mix(g.bkColor, clSelected, alpha);// g.fontColor = clBlack;
                  dr.alpha = 1;
                  g.draw(dr);
                  g.bkColor = old[0]; g.fontColor = old[1];
                }else+/{
                  fade(row.subCells[x].outerBounds);
                }
              }else{ //newLine
                auto g = newLineGlyph;
                g.bkColor = row.bkColor;  g.fontColor = clGray;
                dr.alpha = 1;
                g.outerPos = row.newLinePos;
                g.draw(dr);

                fade(g.outerBounds);
              }
            }

          }else{
            if(!isFirstRow && !isLastRow){
              if(row.cellCount)
                dr.fillRect(bounds2(0, 0, row.subCells.back.outerRight, row.innerHeight));
            }else{
              dr.fillRect(bounds2(row.localCaretPos(x0).pos.x, 0, row.localCaretPos(x1).pos.x, row.innerHeight));
            }

          }
        }

      }
    }

    //caret trail
    version(AnimatedCursors){
      if(textSelections.length <= MaxAnimatedCursors){
        dr.alpha = blink/2;
        dr.lineWidth = -1-(blink)*3;
        dr.color = clCaret;
        //opt: culling
        //opt: limit max munber of animated cursors
        foreach(s; textSelections){
          CaretPos[3] cp;
          cp[0] = s.caret.worldPos;
          cp[1..3] = cp[0];
          cp[2].pos += s.caret.animatedPos - s.caret.targetPos;
          cp[1].pos = mix(cp[0].pos, cp[2].pos, .25f);
          //todo: animate caret height too

          auto dir = cp[1].pos-cp[2].pos; //todo: center them on height
          if(dir){
            if(dir.normalize.x.abs<0.05f){ //vertical line
              vec2[2] p = [cp[1].pos, cp[2].pos];
              if(p[0].y<p[1].y) p[1].y += cp[2].height;
              else              p[0].y += cp[1].height;
              dr.line(p[0], p[1]);
            }else{ //horizontal bar
              vec2[4] p;
              p[0] = cp[1].pos;
              p[1] = cp[1].pos + vec2(0, cp[1].height);
              p[2] = cp[2].pos + vec2(0, cp[2].height);
              p[3] = cp[2].pos;

              if(p[0].x<p[3].x) { dr.fillTriangle(p[0], p[1], p[3]); dr.fillTriangle(p[1], p[2], p[3]); }
              else              { dr.fillTriangle(p[3], p[2], p[0]); dr.fillTriangle(p[2], p[1], p[0]); }
            }
          }
        }
      }
    }

    dr.alpha = blink;  //opt: culling
    dr.lineWidth = -1-(blink)*3;
    dr.color = clCaret;
    foreach(s; textSelections)
      s.caret.worldPos.draw(dr);

    dr.alpha = 1;
  }

  override void onDraw(Drawing dr){ //onDraw //////////////////////////////
    if(lod.moduleLevel){
      drawSelectedModules(dr, clWhite, .3f, clWhite, .1f);
      drawSelectionRect(dr, clWhite);
      drawFolders(dr, clGray, clWhite);
      drawMainModuleOutlines(dr);
    }

    if(lod.moduleLevel || (cast(FrmMain)mainWindow).building) drawModuleBuildStates(dr);

    drawModuleLoadingHighlights(dr, clWhite);

    foreach_reverse(t; EnumMembers!BuildMessageType)
      if(markerLayers[t].visible)
        drawSearchResults(dr, markerLayers[t].searchResults, t.color);

    drawTextSelections(dr, frmMain.view); //bug: this will not work for multiple workspace views!!!
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

class FrmMain : GLWindow { mixin autoCreate;

  Workspace workspace;
  MainOverlayContainer overlay;

  Tid buildSystemWorkerTid;

  BuildResult buildResult; //collects buildMessages and output

  Path workPath = Path(`z:\temp2`);

  File workspaceFile;
  bool initialized; //workspace has been loaded.

  @VERB("Alt+F4")       void closeApp            (){ PostMessage(hwnd, WM_CLOSE, 0, 0); }

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

    updateBlink;

    updateBuildSystem;

    if(initialized.chkSet){
      test_CodeColumn;
      if(workspaceFile.exists){
        workspace.loadWorkspace(workspaceFile);
      }
    }

    invalidate; //todo: low power usage
    caption = "DIDE2";
    //view.navigate(false/+disable keyboard navigation+/ && !im.wantKeys && !inputs.Ctrl.down && !inputs.Alt.down && isForeground, false/+worksheet.update handles it+/!im.wantMouse && isForeground);
    view.updateSmartScroll;
    setLod(view.scale_anim);

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
  }

  override void onPaint(){ // onPaint ///////////////////////////////////////
    gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT);
  }


  void drawOverlay(Drawing dr){
    //dr.mmGrid(view);

    if(workspace.flags.changedModified) foreach(m; workspace.modules) if(m.flags.changedModified){
      LOG(m.file);
    }
  }

  override void afterPaint(){ // afterPaint //////////////////////////////////

  }

}

//todo: search in std, core, etc
//todo: winapi help search

