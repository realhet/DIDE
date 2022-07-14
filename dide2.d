//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId

//@release
///@debug

//todo: buildSystem: the caches (objCache, etc) has no limits. Onli a rebuild clears them.

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

struct CodeLocation{ //CodeLocation ////////////////////////
  File file;
  int line, column;

  bool opCast(T:bool)() const{ return cast(bool)file; }

  int opCmp(in CodeLocation b) const{ return file.opCmp(b.file).cmpChain(cmp(line, b.line)).cmpChain(cmp(column, b.column)); }

  string toString() const{ return format!"%s(%d,%d)"(file.fullName, line, column); }
}


//! Build System /////////////////////////////////////

import buildsys, core.thread, std.concurrency;

// messages sent to buildSystemWorker

enum MsgBuildCommand{ cancel, shutDown }

struct MsgBuildRequest{
  File mainFile;
  BuildSettings settings;
}


// messages received from buildSystemWorker

struct MsgBuildStarted{
  File mainFile;
  immutable File[] filesToCompile, filesInCache;
  immutable string[] todos;
}

struct MsgCompileStarted{
  int fileIdx=-1;    //indexes MsgBuildStarted.filesToCompile
}

struct MsgCompileProgress{
  File file;
  int result;
  string output;
}

struct MsgBuildFinished{
  File mainFile;
  string error;
  string output;
}



struct BuildSystemWorkerState{ //BuildSystemWorkerState /////////////////////////////////
  //worker state that don't need synching.
  bool building, cancelling;
  int totalModules, compiledModules, inFlight;

  void UI_StatusItem() const{ with(im){
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
}

__gshared const BuildSystemWorkerState buildSystemWorkerState;

void buildSystemWorker(){ // worker //////////////////////////
  BuildSystem buildSystem;
  auto state = &cast()buildSystemWorkerState;
  bool isDone = false;

  //register events

  void onBuildStarted(File mainFile, in File[] filesToCompile, in File[] filesInCache, in string[] todos){ //todo: rename to buildStart
    with(state){
      totalModules = (filesToCompile.length + filesInCache.length).to!int;
      compiledModules = inFlight = 0;
    }

    //LOG(mainFile, filesToCompile, filesInCache);
    ownerTid.send(MsgBuildStarted(mainFile, filesToCompile.idup, filesInCache.idup, todos.idup));
  }
  buildSystem.onBuildStarted = &onBuildStarted;

  void onCompileProgress(File file, int result, string output){
    state.compiledModules++;
    //LOG(file, result);
    ownerTid.send(MsgCompileProgress(file, result, output));
  }
  buildSystem.onCompileProgress = &onCompileProgress;

  bool onIdle(int inFlight, int justStartedIdx){
    state.inFlight = inFlight;

    if(justStartedIdx>=0)
      ownerTid.send(MsgCompileStarted(justStartedIdx));

    //receive commands from mainThread
    bool cancelRequest = false;
    receiveTimeout(0.msecs,
      (MsgBuildCommand cmd){
        if     (cmd==MsgBuildCommand.shutDown){ cancelRequest = true; isDone = true; state.cancelling = true; }
        else if(cmd==MsgBuildCommand.cancel  ){ cancelRequest = true;                state.cancelling = true; }
      },
      (immutable MsgBuildRequest req){
        WARN("Build request ignored: already building...");
      }
    );

    return cancelRequest;
  }
  buildSystem.onIdle = &onIdle;

  // main worker loop
  while(!isDone) {
    receive(
      (MsgBuildCommand cmd){
        if(cmd==MsgBuildCommand.shutDown) isDone = true;
      },
      (immutable MsgBuildRequest req){
        string error;
        try{
          state.building = true;
          //todo: onIdle
          buildSystem.build(req.mainFile, req.settings);
        }catch(Exception e){
          error = e.simpleMsg;
        }
        ownerTid.send(MsgBuildFinished(req.mainFile, error, buildSystem.sLog));
      }
    );

    state.clear; //must be the last thing in loop to clear this.
  }

}


// BuildMessage //////////////////////////////

enum BuildMessageType{ find, error, bug, warning, deprecation, todo, opt } //todo: In the future it could handle special pragmas: pragma(msg, __FILE__~"("~__LINE__.text~",1): Message: ...");

auto buildMessageTypeColors = [clWhite, clRed, clOrange, clYellow, clAqua, clWowBlue, clWowPurple];
auto color(in BuildMessageType t){ return buildMessageTypeColors[t]; }

auto buildMessageTypeCaptions = [/+im.symbol("Zoom")+/"Find", "Err", "Bug", "Warn", "Depr", "Todo", "Opt"];
auto caption(in BuildMessageType t){ return buildMessageTypeCaptions[t]; }


struct BuildMessage{
  CodeLocation location;
  BuildMessageType type;
  string message;
  CodeLocation parentLocation;  //multiline message lines are linked together using parentLocation

  string toString() const{
    return parentLocation ? format!"%s: %s:        %s"(location, type.text.capitalize, message)
                          : format!"%s: %s: %s"       (location, type.text.capitalize, message);
  }
}

class BuildResult{ // BuildResult //////////////////////////////////////////////
  File mainFile;
  File[] filesToCompile, filesInCache;
  int[File] results; //command line console exit codes
  string[][File] outputs, remainings; //raw output lines, remaining output lines after processing
  BuildMessage[CodeLocation] messages; //all the things referencing a code location

  private{ CodeLocation _lastAddedLocation;
           BuildMessageType _lastAddedType; }

  File[] allFiles;
  bool[File] filesInFlight;
  bool[File] filesInProject;

  mixin ClassMixin_clear;

  auto getBuildStateOfFile(File f) const{ with(Module.BuildState){
    if(f !in filesInProject) return notInProject;
    if(auto r = f in results){
      if(*r) return hasErrors;
      return hasWarnings; //todo: detect hasDeprecations, flawless
    }
    return f in filesInFlight ? compiling : queued;
  }}

  private bool _processLine(string line){
    try{
      if(line.isWild(`?:\?*.d*(?*,?*):?*`)){
        auto location = CodeLocation(File(wild[0]~`:\`~wild[1]~`.d`~wild[2]).normalized, wild[3].to!int, wild[4].to!int),
             content = wild[5];

        void add(BuildMessage bm){
          messages[bm.location] = bm;
          _lastAddedLocation = bm.location;
          _lastAddedType = bm.type;
        }

        if(content.startsWith("  ")){
          enforce(_lastAddedLocation);
          add(BuildMessage(location, _lastAddedType, content.strip, _lastAddedLocation));
          return true;
        }else if(content.isWild(" ?*:?*")){
          const type = wild[0].decapitalize.to!(BuildMessageType); //can throw
          add(BuildMessage(location, type, wild[1].strip));
          return true;
        }
      }
    }catch(Exception e){ }
    return false;
  }


  void receiveBuildMessages(){
    while(receiveTimeout(0.msecs,
      (in MsgBuildStarted msg){
        clear;
        mainFile       = msg.mainFile;
        filesToCompile = msg.filesToCompile.dup;
        filesInCache   = msg.filesInCache.dup;

        allFiles = (filesToCompile~filesInCache);
        allFiles.each!((f){ filesInProject[f] = true; });

        msg.todos.each!(t => _processLine(t));
      },
      (in MsgCompileStarted msg){
        auto f = filesToCompile.get(msg.fileIdx);
        assert(f);
        filesInFlight[f] = true;
      },
      (in MsgCompileProgress msg){

        auto f = msg.file,
             lines = msg.output.splitLines;

        filesInFlight.remove(f);

        string[] remaining;
        foreach(line; lines){
          if(_processLine(line)) continue;
          remaining ~= line;
        }

        if(remaining.length && remaining[$-1]=="") remaining = remaining[0..$-1]; //todo: something puts an extra newline on it...

        results[f] = msg.result;
        outputs[f] = lines;
        remainings[f] = remaining;
      },

      (in MsgBuildFinished msg){
        filesInFlight.clear;

        //todo: clear currently compiling modules.
        //decide the global success of the build procedure
        //todo: there are errors whose source are not specified or not loaded, those must be displayed too. Also the compiler output.

        //dump;
      }

    )){}
  }


  void dumpMessage(in BuildMessage bm, string indent=""){
    writeln(indent, bm);

    foreach(const v; messages.values)
      if(v.parentLocation == bm.location)
        dumpMessage(v, indent~"  ");
  }

  void dumpMessage(in CodeLocation location, string indent=""){
    if(!location) return;
    if(const bm = location in messages)
      dumpMessage(*bm, indent);
  }


  void dump(){
    print("Messages--------------------------");
    foreach(loc; messages.keys.sort){
      const bm = messages[loc];
      if(!bm.parentLocation)
        dumpMessage(bm, "  ");
    }

    print("remainings");
    foreach(f; remainings.keys.sort){
      if(remainings[f].length){
        print("Unprocessed messages of: ", f);
        remainings[f].each!(a => writeln("  ", a));
      }
    }
  }

}

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
    this();
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

  this(SourceCode src){
    this();
    id = "CodeColumns:"~src.file.fullName;
    set(src);
  }

  void set(SourceCode src){
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
    if(labelType==LabelType.module_) icon = new Img(File(`icon:\.d`)); //todo: get the real extension
    else if(labelType==LabelType.folder) icon = new Img(File(`icon:\folder\`));

    if(icon){
      icon.innerSize = vec2(ts.fontHeight);
      icon.transparent = true;
      append(icon);
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


/// Module ///////////////////////////////////////////////
class Module : Container{ //this is any file in the project
  File file;

  DateTime loaded, saved, modified;

  CodeColumn code;
  Container overlay;

  enum BuildState { notInProject, queued, compiling, aborted, hasErrors, hasWarnings, hasDeprecations, flawless }
  enum BuildStateColors = [clBlack, clWhite, clWhite, clGray, clRed, RGB(128, 255, 0), RGB(64, 255, 0), clLime];
  BuildState buildState;

  void rebuild(){
    clearSubCells;

    flags.cullSubCells = true;

    bkColor = clModuleBorder;
    this.setRoundBorder(16);
    padding = "8";

    auto src = new SourceCode(this.file);

    code = new CodeColumn(src);
    code.measure;
    const siz = code.outerSize;
    innerSize = siz;

    overlay = new Container;
    overlay.id = "Overlay:"~file.fullName;
    overlay.outerSize = siz;
    with(overlay.flags){
      noHitTest = true;
      dontSearch = true;
      dontLocate = true;
      noBackground = true;
      //clipSubCells = false;
    }

    overlay.append(new Label(LabelType.module_, vec2(0, -255), file.nameWithoutExt));
    foreach(k; src.bigComments.keys.sort)
      overlay.append(new Label(LabelType.subRegion, vec2(0, k*18), src.bigComments[k], overlay.innerWidth));

    append(code);
    append(overlay);
  }


  this(){
    loaded = now;
  }

  this(File file_){
    this();

    file = file_.actualFile;
    id = "Module:"~this.file.fullName;

    rebuild;
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

// FolderLabel //////////////////////////////////

auto getFolderLabel(string folderPath){
  return ImStorage!Label.access(srcId(genericId(folderPath)), new Label(LabelType.folder, vec2(0), Path(folderPath).name));
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
    BuildSystem buildSystem;
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

  void updateModuleBuildStates(in BuildResult buildResult){
    foreach(m; modules){
      m.buildState = buildResult.getBuildStateOfFile(m.file);
    }
  }

  void convertBuildMessagesToSearchResults(){

    auto buildMessagesAsSearchResults(BuildMessageType type){ //todo: opt
      auto br = (cast(FrmMain)mainWindow).buildResult;
      Container.SearchResult[] res;

      foreach(const msg; br.messages)
      if(msg.type==type)
      if(auto mod = findModule(msg.location.file))    //opt: bottlenect! linear search
      if((msg.location.line-1).inRange(mod.code.subCells)){
        Container.SearchResult sr;
        sr.container = cast(Container)mod.code.subCells[msg.location.line-1];
        sr.absInnerPos = mod.innerPos + mod.code.innerPos + sr.container.innerPos;
        sr.cells = sr.container.subCells;
        res ~= sr;
      }

      return res;
    }

    //opt: it is a waste of time. this should be called only at buildStart, and at buildProgress, module change, module move.
    //1.5ms, (45ms if not sameText but sameFile(!!!) is used in the linear findModule.)
    //const t0 = now;
    foreach(t; EnumMembers!BuildMessageType[1..$])
      markerLayers[t].searchResults = buildMessagesAsSearchResults(t);
    //print(siFormat("%s ms", now-t0));
  }

  void update(View2D view, in BuildResult buildResult){ //update ////////////////////////////////////
    updateOpenQueue(1);
    updateModuleBuildStates(buildResult);
    convertBuildMessagesToSearchResults;
    selectionManager.update(mainWindow.isForeground && lod.moduleLevel, view, modules);
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

  string locationToStr(CellLocation[] st){
    auto a(T)(void delegate(T) f){
      if(auto x = cast(T)st.get(0).cell){ st.popFront; f(x); }
    }

    //opt: linear search...

    string res;
    a((Module m){
      res ~= m.file.fullName;
      a((CodeColumn col){
        a((CodeRow row){
          if(auto line = col.subCells.countUntil(row)+1){
            res ~= format!"(%d"(line);
            a((Cell cell){
              if(auto column = row.subCells.countUntil(cell)+1)
                res ~= format!",%s"(column);
            });
            res ~= ')';
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

      with(getFolderLabel(folderPath)){
        outerPos = bnd.topLeft - vec2(0, 255);
        draw(dr);
      }
    }
  }

  void drawModuleBuildStates(Drawing dr){
    with(Module.BuildState) foreach(m; modules) if(m.buildState!=notInProject){
      dr.color = Module.BuildStateColors[m.buildState.to!int];
      dr.lineWidth = -4;
      //if(m.buildState==compiling) dr.drawRect(m.outerBounds);
      dr.alpha = m.buildState==compiling ? mix(.25f, .75f, blink) : .25f;
      dr.fillRect(m.outerBounds);
    }
    dr.alpha = 1;
  }

  override void onDraw(Drawing dr){ //onDraw //////////////////////////////
    if(lod.moduleLevel){
      drawSelectedModules(dr, clWhite, .3f, clWhite, .1f);
      drawSelectionRect(dr, clWhite);
      drawFolders(dr, clGray, clWhite);
    }
    drawModuleBuildStates(dr);
    drawModuleLoadingHighlights(dr, clYellow);

    foreach_reverse(t; EnumMembers!BuildMessageType)
      if(markerLayers[t].visible)
        drawSearchResults(dr, markerLayers[t].searchResults, t.color);


    //drawSearchResults(dr, searchResults, clWhite);


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

  WorkSpace workSpace;
  MainOverlayContainer overlay;

  Tid buildSystemWorkerTid;

  BuildResult buildResult; //collects buildMessages and output

  Path workPath = Path(`z:\temp2`);
  File mainFile = File(`c:\d\projects\karc\karc2.d`);

  File workSpaceFile;
  bool initialized; //workspace has been loaded.

  @VERB("Alt+F4")       void closeApp            (){ PostMessage(hwnd, WM_CLOSE, 0, 0); }
  @VERB("Ctrl+O")       void openFile            (){ workSpace.openModule; }
  @VERB("Ctrl+Shift+O") void openFileRecursive   (){ workSpace.openModuleRecursive; }
  @VERB("Ctrl+W")       void closeWindow         (){ if(lod.moduleLevel) workSpace.closeSelectedModules; }
  @VERB("Ctrl+A")       void selectAll           (){ if((lod.moduleLevel) && !im.wantKeys) workSpace.selectAllModules; }

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
    buildResult.receiveBuildMessages; //todo: it's only good for ONE workSpace!!!
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

    buildSystemWorkerTid.send(cast(immutable)MsgBuildRequest(mainFile, bs));
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
    workSpace = new WorkSpace;
    workSpaceFile = File(appPath, "default"~WorkSpace.defaultExt);
    overlay = new MainOverlayContainer;
  }

  override void onDestroy(){
    if(initialized) workSpace.saveWorkSpace(workSpaceFile);
    destroyBuildSystem;
  }

  override void onUpdate(){ // onUpdate ////////////////////////////////////////
    //showFPS = true;

    updateBuildSystem;

    if(initialized.chkSet){
      if(workSpaceFile.exists){
        workSpace.loadWorkSpace(workSpaceFile);
      }
    }

    invalidate; //todo: low power usage
    caption = "DIDE2";
    view.navigate(!im.wantKeys && !inputs.Ctrl.down && !inputs.Alt.down && isForeground, !im.wantMouse && isForeground);
    setLod(view.scale_anim);
     if(isForeground) callVerbs(this);

    if(0) with(im) Panel(PanelPosition.topClient, { margin = "0"; padding = "0";// border = "1 normal gray";
      Row({ //todo: Panel should be a Row, not a Column...
        Row({ workSpace.UI_ModuleBtns; flex = 1; });
      });
    });

    with(im) Panel(PanelPosition.topRight, { margin = "0"; padding = "0";
      workSpace.UI_SearchBox(view);
    });

    if(0) with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
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

    void VLine(){ with(im) Container({ innerWidth = 1; innerHeight = fh; bkColor = clGray; }); }

    //StatusBar
    with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";
      Row({
        //todo: faszomat ebbe a szarba:
        flags.vAlign = VAlign.center;  //ha ez van, akkot a text kozepre megy, de a VLine nem latszik.
        //flags.yAlign = YAlign.stretch; //ha ez, akkor meg a VLine ki van huzva.

        Row({ margin = "0 3"; flags.yAlign = YAlign.center;
          style.fontHeight = 18+6;
          buildSystemWorkerState.UI_StatusItem;
        });
        VLine;//---------------------------
        Row({ flex = 1; margin = "0 3"; flags.yAlign = YAlign.center;
          style.fontHeight = 18+6;

          auto st = workSpace.locate(view.mousePos);
          if(st.length){
            Text(workSpace.locationToStr(st));
            //if(auto module_ = cast(Module)) st[0];
          }
        });
        VLine;//---------------------------
        Row({ margin = "0 3"; flags.yAlign = YAlign.center;
          foreach(t; EnumMembers!BuildMessageType){
            workSpace.UI(t, view);
          }
        });
        VLine;//---------------------------
        Row({ margin = "0 3"; flags.vAlign = VAlign.center;
          Text(now.text);
        });

        //this applies YAlign.stretch
        with(actContainer){
          measure;
          foreach(c; cast(.Container[])subCells) c.measure;
        }

      });
    });

    im.root ~= workSpace;
    im.root ~= overlay;

    view.subScreenArea = im.clientArea / clientSize;

    workSpace.update(view, buildResult);

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

//todo: search in std, core, etc
//todo: winapi help search

/// Error collection ///////////////////////////////////
/+

c:\d\libs\het\tokenizer.d(792,41): Deprecation: use `{ }` for an empty statement, not `;`
c:\d\libs\quantities\internal\dimensions.d(101,5): Deprecation: Usage of the `body` keyword is deprecated. Use `do` instead.

C:\D\projects\DIDE\dide2.d(383,22): Error: constructor `dide2.Label.this(int height, bool bold, Vector!(float, 2) pos, string str, bool alignRight, float parentWidth = 0.0F)` is not callable using argument types `(int, bool, string, bool, const(float))`
C:\D\projects\DIDE\dide2.d(383,22):        cannot pass argument `src.bigComments[k]` of type `string` to parameter `Vector!(float, 2) pos`

C:\D\projects\DIDE\dide2.d(338,28): Error: undefined identifier `r`

C:\D\projects\DIDE\dide2.d(324,7): Error: no property `height` for type `het.uibase.TextStyle`
  //todo: no property for type: missleading when the property name is correct but it's private or protected.

C:\D\projects\DIDE\dide2.d(383,59): Error: found `src` when expecting `)`
C:\D\projects\DIDE\dide2.d(383,104): Error: found `)` when expecting `;` following statement
C:\D\projects\DIDE\dide2.d(383,104): Error: found `)` instead of statement

C:\D\projects\DIDE\dide2.d(331,20): Error: cannot implicitly convert expression `isRegion` of type `const(uint)` to `bool`

C:\D\testGetAssociatedIcon.d(29,15): Error: undefined identifier `DestroyIcon`

C:\D\projects\DIDE\dide2.d(51,2): Error: `@identifier` or `@(ArgumentList)` expected, not `@{`

C:\D\projects\DIDE\dide2.d(103,24): Error: found `cmd` when expecting `)`

C:\D\projects\DIDE\dide2.d(103,28): Error: found `{` when expecting `;` following statement

C:\D\projects\DIDE\dide2.d(104,5): Error: found `)` instead of statement

C:\D\projects\DIDE\dide2.d(107,1): Error: unrecognized declaration
+/




immutable builderOutputStr = q"builderOutputStr
c:\d\libs\het\tokenizer.d(792,41): Deprecation: use `{ }` for an empty statement, not `;`
c:\d\libs\quantities\internal\dimensions.d(101,5): Deprecation: Usage of the `body` keyword is deprecated. Use `do` instead.
c:\d\libs\quantities\internal\dimensions.d(136,5): Deprecation: Usage of the `body` keyword is deprecated. Use `do` instead.
C:\D\projects\DIDE\dide2.d(985,51): Error: no property `mlocate` for type `dide2.Module`, did you mean `het.uibase.Container.locate`?
c:\D\ldc2\bin\..\import\std\algorithm\iteration.d(524,16):        instantiated from here: `MapResult!(__lambda2, Module[])`
C:\D\projects\DIDE\dide2.d(985,39):        instantiated from here: `map!(Module[])`

C:\D\projects\DIDE\dide2.d(149,22): Todo: should only be done once at the end...
C:\D\projects\DIDE\dide2.d(153,7): Todo: tab inside string literal. width is too big  File(`c:\D\libs\!shit\_unused.arsd\html.d`)
C:\D\projects\DIDE\dide2.d(161,24): Todo: should only be done once at the end...
C:\D\projects\DIDE\dide2.d(283,79): Todo: the tabs below this one should inherit the indent of this first line
C:\D\projects\DIDE\dide2.d(509,9): Todo: jelezni kell valahogy az elmozdulast!!!
C:\D\projects\DIDE\dide2.d(600,5): Todo: ask user to save if needed
C:\D\projects\DIDE\dide2.d(609,5): Todo: ask user to save if needed
C:\D\projects\DIDE\dide2.d(615,5): Todo: ask user to save if needed
C:\D\projects\DIDE\dide2.d(647,5): Todo: not just for //@exe of //@dll
C:\D\projects\DIDE\dide2.d(710,5): Todo: focus on the edit when turned on
C:\D\projects\DIDE\dide2.d(741,35): Todo: Focus the Edit control
C:\D\projects\DIDE\dide2.d(770,39): Todo: inflate
C:\D\projects\DIDE\dide2.d(835,5): Todo: detect changes and only collect info when changed.
C:\D\projects\DIDE\dide2.d(925,17): Todo: low power usage
C:\D\projects\DIDE\dide2.d(932,13): Todo: Panel should be a Row, not a Column...
C:\D\projects\DIDE\dide2.d(968,5): Todo: cullSubCells ellenorzese
C:\D\projects\DIDE\dide2.d(1003,3): Todo: off screen targets
c:\d\libs\het\opengl.d(20,1): Todo: Ha a glWindow.dr-t hasznalom, akkor a glDraw view es viewGui: tokmindegy a kirajzolasi sorrend, a view van mindig felul, pedig forditva kene.
c:\d\libs\het\opengl.d(21,1): Todo: nincs doUpdate formresize kozben
c:\d\libs\het\opengl.d(653,25): Todo: roviditve a GLXxxxx elotag legyen GlXxxxx
c:\d\libs\het\opengl.d(808,61): Todo: utils. customEnforce() template
c:\d\libs\het\opengl.d(1177,41): Todo: customEnforce
c:\d\libs\het\opengl.d(1179,74): Todo: ennek fatal errornak kene lenni, kiveve ha egy shadertoyszeruseget csinalok...
c:\d\libs\het\opengl.d(1210,5): Todo: a szetvalasztast ugy csinalja, hogy a sorok erintetlenek maradjanak es akkor a hibat ki tudja jelezni az IDE
c:\d\libs\het\opengl.d(1288,3): Todo: az use-ket csak akkor hivni, ha kell
c:\d\libs\het\opengl.d(1289,3): Todo: a getUniformLocation-bol kompilalas kozben listat felepiteni!
c:\d\libs\het\opengl.d(1306,3): Todo: a getUniformLocation-bol kompilalas kozben listat felepiteni!
c:\d\libs\het\opengl.d(1324,38): Todo: disable it afterwards
c:\d\libs\het\opengl.d(1334,38): Todo: disable it afterwards
c:\d\libs\het\opengl.d(1350,5): Todo: working with typenames is compiler-implementation dependent.
c:\d\libs\het\opengl.d(1407,18): Todo: readonly property
c:\d\libs\het\opengl.d(1452,45): Todo: csak akkor bind, ha kell. Ehhez mindig resetelni kell a currentet a rajzolas kezdetekor
c:\d\libs\het\opengl.d(1537,22): Todo: every gltexture is custom because megaTexturing
c:\d\libs\het\opengl.d(1542,83): Todo: enforce with template params
c:\d\libs\het\opengl.d(1555,1): Todo: FileName type
c:\d\libs\het\opengl.d(1592,31): Todo: more texture type support
c:\d\libs\het\opengl.d(1602,3): Todo: ha nincs binding, akkor az access violation megsemmisul, a program meg crashol.
c:\d\libs\het\opengl.d(1604,112): Todo: must bind first! Ez maceras igy, kell valami automatizalas erre.
c:\d\libs\het\opengl.d(1617,26): Todo: rebuild mipmap
c:\d\libs\het\opengl.d(1620,95): Todo: must bind first! Ez maceras igy, kell valami automatizalas erre.
c:\d\libs\het\opengl.d(1632,103): Todo: must bind first! Ez maceras igy, kell valami automatizalas erre.
c:\d\libs\het\opengl.d(1655,67): Todo: must bind first! Ez maceras igy, kell valami automatizalas erre.
c:\d\libs\het\opengl.d(1721,61): Todo: mipmaps
c:\d\libs\het\opengl.d(1770,1): Todo: not just rgba8
c:\d\libs\het\opengl.d(1893,34): Todo: egybeagyazott switch()-ek. Ezeket lehetne grafikusan optolni...
c:\d\libs\het\opengl.d(1896,46): Todo: case 0, case 1 mindegyiknel kozos, ha mar tesztelve van, akkor ki kell pakolni.
c:\d\libs\het\opengl.d(2139,5): Todo: tryInitialZoom should work with the registry also
c:\d\libs\het\opengl.d(2171,5): Todo: bad names: worldRect is "screenBounds in world coords"
c:\d\libs\het\opengl.d(2172,5): Todo: bad names: screenRect is "screenBounds in client coords"
c:\d\libs\het\opengl.d(2216,6): Todo: this is a fix: if the clientSize changes between update() and draw() this will update it. Must rethink the update() draw() thing completely.
c:\d\libs\het\opengl.d(2243,5): Todo: here should be an on OverlayPaint wich is paints on top of the UI
c:\d\libs\het\utils.d(8,1): Todo: msvcrt.lib(initializers.obj): warning LNK4098: defaultlib 'libcmt.lib' conflicts with use of other libs; use /NODEFAULTLIB:library
c:\d\libs\het\utils.d(11,1): Todo: UTILS lots of todes commented out, because of the compile log is small
c:\d\libs\het\utils.d(12,1): Todo: IDE: % as postFix operator: 25% -> (25)*.01
c:\d\libs\het\utils.d(189,37): Todo: should be moved to win.d //Win.d call it from it's own main.
c:\d\libs\het\utils.d(239,18): Todo: ha ezt a writeln-t hivja a gc.collect-bol egy destructor, akkor crash.
c:\d\libs\het\utils.d(294,29): Todo: sync fails here
c:\d\libs\het\utils.d(309,45): Opt: safeUTF8 is fucking slow!!!!
c:\d\libs\het\utils.d(425,40): Todo: ez nem safe, mert a T...-tol is fugg.
c:\d\libs\het\utils.d(565,45): Todo: use countUntil here!
c:\d\libs\het\utils.d(600,66): Todo: this crap drops an ILLEGAL INSTRUCTION exception. At least it works...
c:\d\libs\het\utils.d(653,5): Todo: Try core.runtime.defaultTraceHandler
c:\d\libs\het\utils.d(766,5): Todo: Break point handling
c:\d\libs\het\utils.d(805,1): Todo: selftest skippelesen gondolkozni... A problema, hogy csak akkor kezelheto belul, ha a selftest lazy parametereben tortenik minden.
c:\d\libs\het\utils.d(828,23): Todo: this is a fatal exception, should the IDE know about this also...
c:\d\libs\het\utils.d(883,1): Todo: not sure about where is it used or not used. If float*double(pi) doesnt calculates using double cpu instructions then it is obsolete.
c:\d\libs\het\utils.d(907,27): Todo: opt with fract
c:\d\libs\het\utils.d(933,3): Todo: unittest on a 0..N+1 square. N e 3, 4, 5
c:\d\libs\het\utils.d(937,18): Todo: Ezt megcsinalni SSE-vel
c:\d\libs\het\utils.d(953,1): Todo: unittest nem megy. lehet, hogy az egesz projectet egyszerre kell forditani a DMD-ben?!!!
c:\d\libs\het\utils.d(954,1): Todo: 'in' operator piros, de annak ciankeiknek kene lennie, mint az out-nak. Azazhogy helyzettol figg annak a szine
c:\d\libs\het\utils.d(960,23): Todo: use this in remap
c:\d\libs\het\utils.d(964,1): Todo: remap goes to math
c:\d\libs\het\utils.d(985,1): Todo: rewrite to greaterThan, lessThan
c:\d\libs\het\utils.d(1038,40): Todo: slow
c:\d\libs\het\utils.d(1142,24): Todo: slow
c:\d\libs\het\utils.d(1147,32): Todo: slow
c:\d\libs\het\utils.d(1411,1): Todo: DIDE fails when opening object.d. It should know that's a system module.
c:\d\libs\het\utils.d(1537,3): Todo: refactor this
c:\d\libs\het\utils.d(1592,13): Todo: opt for b1
c:\d\libs\het\utils.d(1648,1): Todo: implement mean for ranges
c:\d\libs\het\utils.d(1750,41): Todo: bitarray-ra megcsinalni a bool-t. Array!bool
c:\d\libs\het\utils.d(1932,18): Todo: tail,head tulcsordulhat 4gb-nel!
c:\d\libs\het\utils.d(1970,1): Todo: a synchronizedet megcsinalni win32-re
c:\d\libs\het\utils.d(2031,44): Todo: gecilassu
c:\d\libs\het\utils.d(2048,33): Opt: cacheolni kene a poziciot es burst-ban nyomni
c:\d\libs\het\utils.d(2112,46): Todo: ez multithread miatt.
c:\d\libs\het\utils.d(2141,16): Todo: sima file-ra lecserelni
c:\d\libs\het\utils.d(2179,42): Todo: const-nak kene lennie...
c:\d\libs\het\utils.d(2193,23): Todo: lame
c:\d\libs\het\utils.d(2256,66): Todo: string.truncate-t megcsinalni unicodeosra rendesen.
c:\d\libs\het\utils.d(2273,60): Todo: unoptimal
c:\d\libs\het\utils.d(2305,86): Todo: inconvenience with includeTrailingPathDelimiter
c:\d\libs\het\utils.d(2310,1): Todo: unittest
c:\d\libs\het\utils.d(2343,1): Todo: revisit string pchar conversion
c:\d\libs\het\utils.d(2378,41): Todo: this is so naive. Must revisit...
c:\d\libs\het\utils.d(2386,49): Todo: this is ultra-lame:  (cast(char[])src)[0..len].to!string
c:\d\libs\het\utils.d(2490,58): Todo: this is ascii!!!! fails if isWordChar contains uni.isAlpha or uni.isNumber!!!!
c:\d\libs\het\utils.d(2517,27): Todo: toLong
c:\d\libs\het\utils.d(2533,18): Todo: compare the speed of this functional approach
c:\d\libs\het\utils.d(2546,1): Todo: isWild variadic return parameters list, like formattedtext
c:\d\libs\het\utils.d(2742,35): Todo: handling quotes
c:\d\libs\het\utils.d(2834,1): Todo: import splitLines from std.string
c:\d\libs\het\utils.d(2845,39): Todo: refactor functionally
c:\d\libs\het\utils.d(2882,29): Todo: this is lame
c:\d\libs\het\utils.d(3013,3): Todo: optimize this
c:\d\libs\het\utils.d(3014,3): Todo: 4096 -> 4k
c:\d\libs\het\utils.d(3083,33): Todo: a kisbetu meg nagybetu legyen konzekvens. A staticMap az kisbetu, ennek is annak kene lennie...
c:\d\libs\het\utils.d(3112,1): Todo: FieldAndFunctionNamesWithUDA should be  FieldsAndPropertiesWithUDA. Functions are actions, not values.
c:\d\libs\het\utils.d(3134,29): Todo: Alias!T alreadyb exists
c:\d\libs\het\utils.d(3261,5): Todo: it could be string in debug mode. Needs a new ide to handle that.
c:\d\libs\het\utils.d(3420,3): Todo: ez egy nagy bug: ha static this, akkor cyclic module initialization. ha shared static this, akkor meg 3 masodperc utan eled csak fel.
c:\d\libs\het\utils.d(3569,3): Todo: kiprobalni stdFile-val is, hogy gyorsabb-e
c:\d\libs\het\utils.d(3645,74): Todo: egy kalap ala hozni a stringest meg a fileost
c:\d\libs\het\utils.d(3767,90): Todo: cast can fail. What to do then?
c:\d\libs\het\utils.d(3778,91): Todo: cast can fail. What to do then?
c:\d\libs\het\utils.d(3850,5): Todo: ez bugos
c:\d\libs\het\utils.d(3858,80): Todo: sse opt
c:\d\libs\het\utils.d(3893,72): Todo: sse opt
c:\d\libs\het\utils.d(4092,47): Todo: it must run at compile time too
c:\d\libs\het\utils.d(4117,15): Todo: this is not working
c:\d\libs\het\utils.d(4218,3): Todo: xxh unittest
c:\d\libs\het\utils.d(4377,48): Todo: const
c:\d\libs\het\utils.d(4431,7): Opt: PREFETCH(in + PREFETCH_DIST);
c:\d\libs\het\utils.d(4599,80): Todo: 0b binary syntax highlight bug in 0x hex literals
c:\d\libs\het\utils.d(4735,44): Todo: ellenorizni ezt es az xxh-t is. Lehet, hogy le kene cserelni norx-ra.
c:\d\libs\het\utils.d(4799,61): Todo: ez qrvalassu
c:\d\libs\het\utils.d(4900,174): Todo: tag checking
c:\d\libs\het\utils.d(4901,174): Todo: tag checking
c:\d\libs\het\utils.d(5000,20): Todo: make a way to set 'resident' bit
c:\d\libs\het\utils.d(5216,76): Todo: common file errors
c:\d\libs\het\utils.d(5431,44): Todo: ez full ganyolas...
c:\d\libs\het\utils.d(5473,136): Todo: void[] kellene ide talan, nem ubyte[] es akkor stringre is menne?
c:\d\libs\het\utils.d(5500,89): Todo: egysegesiteni a file hibauzeneteket
c:\d\libs\het\utils.d(5582,61): Todo: compression, automatic uncompression
c:\d\libs\het\utils.d(5594,41): Todo: test querystrings with bitmap/font renderer
c:\d\libs\het\utils.d(5621,3): Todo: query to map string[string]. It's something like the commandline args and also like the wildcard result struct
c:\d\libs\het\utils.d(5631,100): Todo: combine all saveTo functions into one funct.
c:\d\libs\het\utils.d(5721,3): Todo: implement recursive
c:\d\libs\het\utils.d(5722,3): Todo: onlyFiles && recursive, watch out for ".."!!!
c:\d\libs\het\utils.d(6038,1): Todo: DIDE GotoError must show 5 lines up and down around the error.
c:\d\libs\het\utils.d(6051,16): Todo: tesztelni, hogy a Shader-eket felszabaditja-e es mikor. Elvileg onalloan jol fog mukodni.
c:\d\libs\het\utils.d(6083,56): Todo: fileRead and getDate should be system-wide-atomic
c:\d\libs\het\utils.d(6211,2): Todo: delete old crap from datetime
c:\d\libs\het\utils.d(6322,1): Todo: make more operator overloads for date/time/dateTime
c:\d\libs\het\utils.d(6408,1): Todo: DateTime should be FILETIME based
c:\d\libs\het\utils.d(6700,5): Todo: adjust carry overflow
c:\d\libs\het\utils.d(6859,44): Todo: rename to utcOffset (read aboit it on web first!)
c:\d\libs\het\utils.d(6888,57): Todo: format
c:\d\libs\het\utils.d(6912,20): Todo: not so fast
c:\d\libs\het\utils.d(6929,3): Todo: utcXXX not good! should ude TimeZone as first param
c:\d\libs\het\utils.d(7030,5): Todo: check for digits here, not any chars!
c:\d\libs\het\utils.d(7044,169): Todo: ugly but works
c:\d\libs\het\utils.d(7089,1): Todo: thus should be synchronized with std.singleton
c:\d\libs\het\utils.d(7112,1): Todo: thus should be synchronized with std.singleton
c:\d\libs\het\utils.d(7155,28): Todo: batch overflow when the callbact receives how many times it needs to update
c:\d\libs\het\utils.d(7175,54): Todo: result should be an int counting how many updates missed since last time
c:\d\libs\het\utils.d(7182,3): Todo: revisit this crap
c:\d\libs\het\utils.d(7236,1): Todo: strToDateTime, creators
c:\d\libs\het\utils.d(7253,53): Todo: this is slow
c:\d\libs\het\utils.d(7257,50): Todo: this is also slow
c:\d\libs\het\utils.d(7262,40): Todo: opApply a range helyett!
c:\d\libs\het\utils.d(7479,1): Todo: list members of a module recursively. Adam Ruppe book
c:\d\libs\het\utils.d(7592,20): Todo: bugzik az stdOut fileDelete itt, emiatt nem megy az, hogy a leghamarabb keszen levot ki lehessen jelezni. fuck this shit!
c:\d\libs\het\utils.d(7656,34): Todo: a unittest alatt nem indul ez el.
c:\d\libs\het\utils.d(7657,3): Todo: functional tests: nem ide kene
c:\d\libs\het\utils.d(7717,53): Todo: how to make it readonly?
c:\d\libs\het\debugclient.d(72,1): Todo: (forceExit) a thread which kills the process. for example when readln is active.
c:\d\libs\het\debugclient.d(80,1): Todo: ha relativ a hibauzenetben a filename, akkor egeszitse ki! hdmd!
c:\d\libs\het\debugclient.d(82,23): Todo: rewrite it with utils.sharedMemClient
c:\d\libs\het\math.d(3,1): Todo: vec2 lvalue-be lehessen assignolni ivec2 rvalue-t!
c:\d\libs\het\math.d(4,1): Todo: ldc fast math http://johanengelen.github.io/ldc/2016/10/11/Math-performance-LDC.html
c:\d\libs\het\math.d(52,1): Todo: std.conv.to is flexible, but can be slow, because it calls functions and it checks value ranges. Must be tested and optimized if needed with own version.
c:\d\libs\het\math.d(105,3): Todo: ubyte + ushort should be ushort, not int
c:\d\libs\het\math.d(219,7): Todo: it sometimes give this as false error
c:\d\libs\het\math.d(228,83): Todo: show the error's place in source: __ctor!(int, int, int)
c:\d\libs\het\math.d(241,9): Todo: kulonvalasztani a compile time es a runtime konvertalast. Ha egyaltalan lehet.
c:\d\libs\het\math.d(245,9): Todo: put this in a loop
c:\d\libs\het\math.d(404,84): Todo: refact
c:\d\libs\het\math.d(689,64): Todo: verify abs
c:\d\libs\het\math.d(1311,58): Todo: it's not for ranges, just arrays because []!!! MSE() can't use it.
c:\d\libs\het\math.d(1448,3): Todo: Upgrade to https://val-sagrario.github.io/Dynamics%20of%20First%20Order%20Systems%20for%20game%20devs%20-%20Jan%202020.pdf
c:\d\libs\het\math.d(1633,1): Todo: check these in asm and learn about the compiler.
c:\d\libs\het\math.d(1643,3): Todo: make prettier errors, this needs more IDE integration
c:\d\libs\het\math.d(1703,57): Todo: unittest this with mat2.rotation270*v
c:\d\libs\het\math.d(1739,3): Todo: faceforward, reflect, refract
c:\d\libs\het\math.d(1780,84): Todo: check mat4.det in asm
c:\d\libs\het\math.d(1827,1): Todo: !!!!!!!!!!!!!!! atirni az osszes in-t auto ref-re es merni a sebesseget egy reprezentativ teszt segitsegevel.
c:\d\libs\het\math.d(2033,35): Opt: can be optimized for valid() checking
c:\d\libs\het\math.d(2134,1): Todo: bounds helyett bounds1 jobb lenne, mert a bounds az sokszor masra is hasznalva van: pl. bmp.bounds
c:\d\libs\het\math.d(2317,3): Todo: nem lehet kombinalni az img.retro-t az img.rgb swizzlinggel.   img2 = img.rows.retro.image2D.image2D!"a.b1g";   <-  2x image2D needed
c:\d\libs\het\math.d(2318,3): Todo: img2 = image2D(img.size, (x, y) => img[x, img.height-1-y].lll);  az (x, y) forma sem megy csak az (ivec2 p)
c:\d\libs\het\math.d(2389,40): Todo: it's not 1D compatible.  Vector!(T, 1) should be equal to an alias=T.  In Bounds as well.
c:\d\libs\het\math.d(2445,35): Todo: ezt nem lehet egyszerubben? const vagy nem const. Peldaul "const auto"
c:\d\libs\het\math.d(2456,7): Todo: 2D only
c:\d\libs\het\math.d(2457,62): Todo: 2D only
c:\d\libs\het\math.d(2458,7): Todo: optimize for stride==width case
c:\d\libs\het\math.d(2459,7): Todo: check if dup.join copies 2x or not.
c:\d\libs\het\math.d(2629,60): Todo: refactor this in the same way as generateVector()
c:\d\libs\het\math.d(2635,75): Opt: too much index calculations
c:\d\libs\het\math.d(2645,73): Opt: too much index calculations
c:\d\libs\het\math.d(2681,32): Todo: make it const
c:\d\libs\het\math.d(2683,7): Todo: this is fucking nasty! Should not import hetlib into here!!! Should use a global funct instead which is initialized by het.bitmaps.
c:\d\libs\het\math.d(2684,7): Todo: must do this with a global function!!! The problem is that need to pass the type and elementcount to it.
c:\d\libs\het\math.d(2866,1): Todo: when the ide supports unit testing, this should be private. Also needs real unittest{} blocks.
c:\d\libs\het\color.d(612,20): Todo: user driendly editing of all the colors
c:\d\libs\het\color.d(616,74): Todo: utils
c:\d\libs\het\color.d(621,3): Todo: decapitalize, enforce
c:\d\libs\het\color.d(654,1): Todo: nem jo a color szorzas, mert implicit uint konverzio van
c:\d\libs\het\color.d(659,1): Todo: pragma(msg, "Megcsinalni a szinek listazasat traits-al." ~ [__traits(allMembers, het.color)].filter!(s => s.startsWith("cl")).array);
c:\d\libs\het\color.d(663,1): Todo: there should be a bezier interpolated colormap too. RegressionColorMap is so bad for HSV and JET for example.
c:\d\libs\het\color.d(701,59): Todo: utils
c:\d\libs\het\color.d(712,41): Todo: modf
c:\d\libs\het\color.d(751,3): Todo: Range
c:\d\libs\het\inputs.d(36,1): Todo: atnevezni het.inputs-ra;
c:\d\libs\het\inputs.d(37,1): Todo: tesztelni, hogy 'F5' es 'Shift F5' jol mukodik-e egyutt.
c:\d\libs\het\inputs.d(38,1): Todo: improve mousewheel precision: it is only giving 1's and 2's on 60FPS.
c:\d\libs\het\inputs.d(140,31): Todo: use winuser.GetDoubleClickTime()
c:\d\libs\het\inputs.d(243,23): Todo: Ctrl+KU is sequential!
c:\d\libs\het\inputs.d(300,3): Todo: hova a faszba rakjam ezt...
c:\d\libs\het\inputs.d(330,1): Todo: az egerklikkeles (pressed) csak akkor megy at, ha az update interval rovidebb volt a klikkeles hosszanal. Ezt valahogy javitani.
c:\d\libs\het\inputs.d(429,3): Todo: replace this with DateTime and prioper seconds handling.
c:\d\libs\het\inputs.d(478,55): Todo: this is only needed once a sec, dunno how slow it is.
c:\d\libs\het\inputs.d(493,30): Todo: this should be const. And there should be access(name) which has read/write access.
c:\d\libs\het\inputs.d(558,5): Todo: use KeyCombo struct!
c:\d\libs\het\inputs.d(578,68): Todo: wrong
c:\d\libs\het\inputs.d(579,69): Todo: wrong
c:\d\libs\het\inputs.d(580,1): Todo: wrong
c:\d\libs\het\inputs.d(608,121): Todo: these are slow...
c:\d\libs\het\inputs.d(612,67): Todo: these are slow...
c:\d\libs\het\inputs.d(668,7): Todo: release already pressed modifiers
c:\d\libs\het\inputs.d(669,7): Todo: delays between presses
c:\d\libs\het\inputs.d(679,5): Todo: accent handling
c:\d\libs\het\inputs.d(680,5): Todo: shift symbol handling
c:\d\libs\het\inputs.d(726,17): Todo: at kene terni tick-re...
c:\d\libs\het\inputs.d(889,65): Todo: ` nem lehet, mert valamiert beszarik tole
c:\d\libs\het\inputs.d(939,1): Todo: add multimedia keys
c:\d\libs\het\inputs.d(1625,24): Todo: It is 60 FPS based, not time based
c:\d\libs\het\inputs.d(1669,7): Todo: guide button poller: https://forums.tigsource.com/index.php?topic=26792.0
c:\d\libs\het\inputs.d(1700,5): Todo: get all the states from xinput1_3, not just the guide button
c:\d\libs\het\inputs.d(1751,17): Todo: this is kinda deprecated: the new thing is MenuItem/KeyCombo.
c:\d\libs\het\inputs.d(2004,3): Todo: which is faster?   import core.sys.windows.windows;  or
c:\d\libs\het\win.d(161,1): Todo: ezek a specialis commentek szekciokra oszthatnak a filet es az editorban lehetne maszkalni a szekciok kozott
c:\d\libs\het\win.d(162,1): Todo: Ha a console ablak bezarodik, az ablakozorendszer destruktora akkor is hivodjon meg!
c:\d\libs\het\win.d(164,1): Todo: a sysmenu hasznalatakor ne klikkeljen az alkalmazasba bele
c:\d\libs\het\win.d(361,3): Todo: Mark the unused threads as daemon threads (in karc2.d, utils.d, bitmap.d) and remove this application.exit!!!!
c:\d\libs\het\win.d(573,31): Todo: multiWindow: szolni kene a tobbinek, hogy destroyozzon, vagy nemtom...
c:\d\libs\het\win.d(590,30): Todo: WRONG PLACE!
c:\d\libs\het\win.d(604,1): Todo: multiwindownal a destructort osszerakni, mert most az le van xarva...
c:\d\libs\het\win.d(650,5): Todo: rendesen megcsinalni a game loopot.
c:\d\libs\het\win.d(668,11): Todo: window resize eseten nincs update, csak paint. Emiatt az UI szarul frissul.
c:\d\libs\het\win.d(737,5): Todo: if this is called always, disable the resizeableness of the window automatically
c:\d\libs\het\win.d(825,30): Todo: ezt is meg kell csinalni jobban.
c:\d\libs\het\win.d(906,67): Todo: ez multiWindow-ra nem tudom, hogy hogy fog menni...
c:\d\libs\het\win.d(932,20): Todo: it's single windowed only this way. The update system should be centralized.
c:\d\libs\het\geometry.d(5,1): Todo: implement fast sse approximations
c:\d\libs\het\geometry.d(6,1): Todo: migrate with gl3n
c:\d\libs\het\geometry.d(7,1): Todo: sortBounds() ez nem tul jo nev
c:\d\libs\het\geometry.d(8,1): Todo: a Rect az size-t kap, a bounds csak bound-okat.
c:\d\libs\het\geometry.d(663,15): Todo: make a Segment template struct
c:\d\libs\het\geometry.d(675,42): Todo: rewrite with functional.slide
c:\d\libs\het\geometry.d(696,1): Todo: these should be done with CTCG
c:\d\libs\het\geometry.d(697,107): Todo: support this for all bounds
c:\d\libs\het\geometry.d(699,70): Todo: support this for all bounds
c:\d\libs\het\geometry.d(701,108): Todo: support this for all bounds
c:\d\libs\het\geometry.d(703,71): Todo: support this for all bounds
c:\d\libs\het\geometry.d(705,111): Todo: support this for all bounds
c:\d\libs\het\geometry.d(706,83): Todo: support this for all bounds
c:\d\libs\het\geometry.d(707,69): Todo: support this for all bounds
c:\d\libs\het\geometry.d(723,62): Todo: all of these variation should be refactored with static ifs.
c:\d\libs\het\geometry.d(730,33): Opt: alpha = detA*rcpf_fast(det);
c:\d\libs\het\geometry.d(779,38): Todo: this is lame
c:\d\libs\het\geometry.d(806,1): Todo: segmentPointDistance 3d
c:\d\libs\het\geometry.d(1023,31): Todo: combine Quadratic and linear fitter
c:\d\libs\het\geometry.d(1036,74): Todo: combine this with math.det
c:\d\libs\het\geometry.d(1058,3): Todo: optimize this with .tee or something to access x and y only once
c:\d\libs\het\view.d(65,81): Todo: refactor this redundant crap
c:\d\libs\het\view.d(93,59): Opt: fucking slow, need to be cached
c:\d\libs\het\view.d(104,3): Todo: make this transformation cached and fast!
c:\d\libs\het\view.d(105,127): Opt: fucking slow, need to be cached
c:\d\libs\het\view.d(145,57): Todo: the zoom and the translation amount is not proportional. Fast zooming to the side looks bad. Zoom in center is ok.
c:\d\libs\het\view.d(175,40): Todo: ctrl+s es s (mint move osszeakad!)
c:\d\libs\het\view.d(177,35): Todo: actions are deprecated. This view.navigate function should be replaced with az IMGUI enable flag and a hidden window.
c:\d\libs\het\view.d(197,64): Todo: use quantities.time
c:\d\libs\het\bitmap.d(14,22): Todo: a jpeg ebbol mar nem kell.
c:\d\libs\het\bitmap.d(32,3): Todo: ?thumb32x24  different maxwidth and maxheight
c:\d\libs\het\bitmap.d(33,3): Todo: keep aspect or not
c:\d\libs\het\bitmap.d(34,3): Todo: ?thumb=32w is not possible because processMarkupCommandLine() uses the = pro parameters and it can't passed into this filename.
c:\d\libs\het\bitmap.d(35,3): Todo: cache decoded full size image
c:\d\libs\het\bitmap.d(36,3): Todo: turboJpeg small size extract
c:\d\libs\het\bitmap.d(46,38): Todo: this is lame. This should be solved by registered plugins.
c:\d\libs\het\bitmap.d(97,48): Todo: mipmapped bilinear/trilinear
c:\d\libs\het\bitmap.d(131,1): Todo: ?thumb32x24  different maxwidth and maxheight
c:\d\libs\het\bitmap.d(257,47): Todo: delayed restriction. should refactor this nicely
c:\d\libs\het\bitmap.d(517,80): Todo: make it threadsafe
c:\d\libs\het\bitmap.d(549,1): Todo: ezt is bepakolni a Bitmap class-ba... De kell a delayed betoltes lehetosege is talan...
c:\d\libs\het\bitmap.d(584,3): Todo: handle mustSuccess with an outer try catch{}, not with lots of ifs.
c:\d\libs\het\bitmap.d(601,53): Todo: error handling, mustExists
c:\d\libs\het\bitmap.d(612,39): Todo: monitor indexing
c:\d\libs\het\bitmap.d(618,5): Todo: specify file attributes too that was accessed in FileEntry -> SHGFI_USEFILEATTRIBUTES
c:\d\libs\het\bitmap.d(639,5): Todo: icon loader
c:\d\libs\het\bitmap.d(651,5): Todo: screenshot implementalasa
c:\d\libs\het\bitmap.d(657,1): Todo: bitmap clipboard operations
c:\d\libs\het\bitmap.d(781,54): Todo: unsafe/safe versions, safe with boundary mode and color -> openCV
c:\d\libs\het\bitmap.d(791,88): Opt: it's slow, but universal
c:\d\libs\het\bitmap.d(822,3): Todo: What about pixel center 0.5?  It is now shifting the image.
c:\d\libs\het\bitmap.d(827,1): Todo: should be refactored to an image that handles RGBA types
c:\d\libs\het\bitmap.d(893,1): Todo: az ilyen int3 debuggolasra kitalalni valami jobbat.
c:\d\libs\het\bitmap.d(928,1): Todo: should realloc garbage. also needs a constructor to fill with a specified value
c:\d\libs\het\bitmap.d(1321,26): Todo: these are managed by bitmaps(). Should be protected and readonly.
c:\d\libs\het\bitmap.d(1437,83): Todo: redundant
c:\d\libs\het\bitmap.d(1442,24): Todo: redundant
c:\d\libs\het\bitmap.d(1499,56): Todo: Y, YA plane-kkal megoldani ezeket is
c:\d\libs\het\bitmap.d(1502,3): Todo: tovabbi info a webp-rol: az alpha az csak lossless modon van tomoritve. Lehet, hogy azt is egy Y-al kene megoldani...
c:\d\libs\het\bitmap.d(1518,71): Todo: alpha
c:\d\libs\het\bitmap.d(1519,31): Todo: subsamp-ot kihozni
c:\d\libs\het\bitmap.d(1670,9): Todo: WebPDecodeYUVInto-val megcsinalni az 1 es 2 channelt.
c:\d\libs\het\bitmap.d(1721,9): Todo: Tobb jpeg-bol osszekombinalni a 2-4 channelt.
c:\d\libs\het\bitmap.d(1784,40): Todo: make a unittest out of these
c:\d\libs\het\bitmap.d(2111,40): Todo: SetTextRenderingParams gdi classic-ra allitani, hogy szebb legyen az ui font, ekkor a 3x miatt pont cleartype-ra fog illeszkedni.
c:\d\libs\het\bitmap.d(2310,7): Todo: get space width from DirectWrite
c:\d\libs\het\bitmap.d(2334,59): Todo: this can be null???
c:\d\libs\het\draw2d.d(18,1): Todo: A shader errorokat visszakovetni valahogy: Annyit tudunk rola, hogy a neve az, hogy pl. DrawingShader, ezt a nevet lehetne magabol a shader szovegebol generalni. A GCN compilerbol kell lopkodni, ott mar megy.
c:\d\libs\het\draw2d.d(59,1): Todo: Appendert kell hasznalni!
c:\d\libs\het\draw2d.d(67,29): Todo: immutable
c:\d\libs\het\draw2d.d(118,40): Todo: This keeps the buffer capacity in memory. For 24/7 operation, in every minute is should be shrinked to the half if possible.
c:\d\libs\het\draw2d.d(153,89): Todo: dumb stupid copy paste constructor
c:\d\libs\het\draw2d.d(271,30): Todo: revisit this subdrawing thing
c:\d\libs\het\draw2d.d(287,20): Todo: this is a terrible slow copy
c:\d\libs\het\draw2d.d(345,3): Todo: Examine push VS saveState, seems redundant. UI uses only translate() and pop()
c:\d\libs\het\draw2d.d(419,24): Todo: ezt meg kell csinalni matrixosra.
c:\d\libs\het\draw2d.d(503,94): Todo: slow divide
c:\d\libs\het\draw2d.d(508,3): Todo: rename invScale and invZoomFactor to pixelSize, scale and zoomFactor to scaleFactor.
c:\d\libs\het\draw2d.d(510,3): Todo: zoomFactor naming is incompatible with view.scale
c:\d\libs\het\draw2d.d(560,9): Todo: point2 is not working with appender. should use vec2[]
c:\d\libs\het\draw2d.d(566,36): Todo: refactor this
c:\d\libs\het\draw2d.d(597,29): Todo: const struct->in struct
c:\d\libs\het\draw2d.d(635,1): Todo: static if(is(A == LineStyle)) lineStyle = a;
c:\d\libs\het\draw2d.d(747,79): Todo: ibounds2 automatikusan atalakulhasson bounds2-re
c:\d\libs\het\draw2d.d(773,43): Todo: csunya, kell egy texture wrapper erre
c:\d\libs\het\draw2d.d(782,43): Opt: double call to accessInfo
c:\d\libs\het\draw2d.d(788,5): Todo: Bitmap, Image2D
c:\d\libs\het\draw2d.d(808,3): Todo: ezeket az fv headereket racionalizalni kell
c:\d\libs\het\draw2d.d(857,5): Todo: must combine this with drawGlyph
c:\d\libs\het\draw2d.d(862,1): Todo: csunya, kell egy texture wrapper erre
c:\d\libs\het\draw2d.d(899,5): Todo: this is not working with translate()
c:\d\libs\het\draw2d.d(928,16): Todo: nem tul jo
c:\d\libs\het\draw2d.d(947,36): Todo: lame
c:\d\libs\het\draw2d.d(950,35): Todo: it should be done in the shader
c:\d\libs\het\draw2d.d(966,48): Todo: nem mukodik a negativ lineWidth itt! Sot! Egyaltalan nem mukodik a linewidth
c:\d\libs\het\draw2d.d(971,42): Opt: slow
c:\d\libs\het\draw2d.d(973,48): Todo: nem mukodik a negativ lineWidth itt! Sot! Egyaltalan nem mukodik a linewidth
c:\d\libs\het\draw2d.d(1061,5): Todo: bmp.to    auto tmp = bmp.to!LA8;
c:\d\libs\het\draw2d.d(1103,3): Todo: megaTexMaxCount-ot meg a tobbi konstanst kivulrol szedni
c:\d\libs\het\draw2d.d(1104,3): Todo: arrowless curves could use max vertices
c:\d\libs\het\draw2d.d(1105,3): Todo: arrows -> triangles instead of trapezoids
c:\d\libs\het\draw2d.d(1106,3): Todo: arrows: no curcature needed
c:\d\libs\het\draw2d.d(1107,3): Todo: compress geom shader output size
c:\d\libs\het\draw2d.d(1136,27): Todo: culling in geometry shader
c:\d\libs\het\draw2d.d(1151,5): Todo: 200909 Csobi kartyajan nem megy az uj vertex attribok miatt. -> attribok tomoritese -> MaxCurveRertices hardvertol fuggo szamitasa.
c:\d\libs\het\draw2d.d(1167,25): Todo: osszevonhato lenne az fStipple-vel                                              // 2
c:\d\libs\het\draw2d.d(1526,5): Todo: megatexture error: Maybe it's a fix: wiki glsl samples Non-uniform flow control !!!!!
c:\d\libs\het\draw2d.d(1650,9): Todo: nearest when close and linear when far
c:\d\libs\het\draw2d.d(1865,41): Todo: ezek a vbo hivas elott mehetnek kifele
c:\d\libs\het\draw2d.d(1887,5): Todo: ezeket az allapotokat elmenteni es visszacsinalni, ha kell, de leginkabb bele kene rakni egy nagy functba az egesz hobelevancot...
c:\d\libs\het\draw2d.d(1904,3): Todo: A binaris konstansokat is szemleltethetne az ide!
c:\d\libs\het\draw2d.d(1905,3): Todo: az IDE automatikusan irhatna a bezaro } jelek utan, hogy mit zar az be. Csak annak a scopenak, amiben a cursor van.
c:\d\libs\het\draw2d.d(2043,22): Todo: refactor this funct
c:\d\libs\het\draw2d.d(2083,3): Todo: Editor: linkek highlightolasa es raugras.
c:\d\libs\het\megatexturing.d(22,32): Todo: ensure the safety of this with a setter.
c:\d\libs\het\megatexturing.d(47,1): Todo: !!!!!!!! must be set when app starts
c:\d\libs\het\megatexturing.d(50,1): Todo: !!!!!!!! must be set when app starts
c:\d\libs\het\megatexturing.d(59,27): Todo: !!!!!!!! must be set when app starts
c:\d\libs\het\megatexturing.d(149,129): Todo: MegaTexture.mipmap
c:\d\libs\het\megatexturing.d(169,7): Todo: MegaTexture.repack()
c:\d\libs\het\megatexturing.d(176,86): Todo: MegaTexture.channels = 1, 2, 3, not just 4
c:\d\libs\het\megatexturing.d(237,25): Opt: ezt megcsinalni kotegelt feldolgozasura
c:\d\libs\het\megatexturing.d(249,38): Todo: refactor to isValidIdx
c:\d\libs\het\megatexturing.d(316,5): Todo: feltetelesen fordithatova tenni ezeket a felszabaditas utani zero filleket
c:\d\libs\het\megatexturing.d(350,1): Todo: make the texture class
c:\d\libs\het\megatexturing.d(380,20): Todo: this is useless i think
c:\d\libs\het\megatexturing.d(451,5): Todo: Ugly lag and one frame of garbage when the DefaultFont_subTexIdxMap is cleared.
c:\d\libs\het\megatexturing.d(473,39): Todo: make a texture garbage collect cycle here
c:\d\libs\het\megatexturing.d(500,7): Todo: this is wasting ram and not work with custom non 4ch bitmaps
c:\d\libs\het\megatexturing.d(571,5): Todo: is this rehash useful at all?
c:\d\libs\het\megatexturing.d(598,9): Opt: disable the upload of this texture data
c:\d\libs\het\megatexturing.d(601,49): Opt: slow linear search
c:\d\libs\het\megatexturing.d(639,76): Todo: bugos a delayed leader
c:\d\libs\het\megatexturing.d(644,5): Todo: nonexisting file and/or exception is not handling well here.
c:\d\libs\het\megatexturing.d(648,111): Todo: delayed restriction. should refactor this nicely
c:\d\libs\het\megatexturing.d(680,13): Todo: Nem jo!!! Nem thread safe !!!  WARN("Bitmap decode error. Using errorBitmap", fileName);
c:\d\libs\het\megatexturing.d(682,13): Todo: ezt megoldani a placeholder bitmappal rendesen
c:\d\libs\het\megatexturing.d(686,11): Todo: not just 4 chn bitmap support
c:\d\libs\het\megatexturing.d(695,13): Todo: issue a redraw. it only works for one window apps.
c:\d\libs\het\megatexturing.d(701,11): Todo: upgrade this to be able to prioritize loading order in realtime.
c:\d\libs\het\megatexturing.d(729,69): Todo: ezt megoldani a placeholder bitmappal rendesen
c:\d\libs\het\megatexturing.d(734,9): Todo: not just 4 chn bitmap support
c:\d\libs\het\megatexturing.d(850,5): Todo: this should be the main list.
c:\d\libs\het\megatexturing.d(890,64): Todo: drawRect support for ibounds2
c:\d\libs\het\megatexturing.d(912,51): Todo: deprecate toId and use the DateTime itself
c:\d\libs\het\megatexturing.d(917,7): Todo: ennel az egyenlosegjelnel 2 bug van:
c:\d\libs\het\algorithm.d(123,60): Todo: install latest LDC
c:\d\libs\het\algorithm.d(133,33): Opt: maybe the .array is not needed
c:\d\libs\het\algorithm.d(174,28): Todo: a rectangle bele mehetne a binPacker classba es lehetne generic tipusu a data
c:\d\libs\het\algorithm.d(304,33): Todo: ref if struct!!!
c:\d\libs\het\ui.d(5,1): Todo: Unqual is not needed to check a type. Try to push this idea through a whole testApp.
c:\d\libs\het\ui.d(6,1): Todo: animated caret, Neovide style: https://youtu.be/Vd5AACp6GG0?t=421
c:\d\libs\het\ui.d(14,1): Todo: form resize eseten remeg a viewGUI-ra rajzolt cucc.
c:\d\libs\het\ui.d(16,1): Todo: Beavatkozas / gombnyomas utan NE jojjon elo a Button hint. Meg a tobbi controllon se!
c:\d\libs\het\ui.d(95,3): Todo: this should be the only opportunity to switch between GUI and World. Better that a containerflag that is initialized too late.
c:\d\libs\het\ui.d(118,3): Todo: package visibility is not working as it should -> remains public
c:\d\libs\het\ui.d(180,5): Todo: remove this: applyScrollers(screenBounds);
c:\d\libs\het\ui.d(222,7): Todo: mainWindow.isForeground check
c:\d\libs\het\ui.d(278,59): Todo: problem with hitStack: it is assumed to be on GUI view
c:\d\libs\het\ui.d(283,5): Todo: ezt tesztelni kene sor cell-el is! Hogy mekkorak a gc spyke-ok, ha manualisan destroyozok.
c:\d\libs\het\ui.d(285,5): Todo: if window resizing, draw is called without update!!!  canDraw = false; can detect it.
c:\d\libs\het\ui.d(316,61): Todo: bug: fucking vec2.lerp is broken again
c:\d\libs\het\ui.d(320,7): Todo: put checking for running out of area and scrolling here.
c:\d\libs\het\ui.d(332,92): Todo: multiple Panels, but not call them frames...
c:\d\libs\het\ui.d(335,5): Todo: this should work for all containers, not just high level ones
c:\d\libs\het\ui.d(341,37): Todo: why document? It should be a template parameter!
c:\d\libs\het\ui.d(345,54): Todo: outerSize should be stored, not innerSize, because the padding/border/margin settings after this can fuck up the alignment.
c:\d\libs\het\ui.d(390,35): Todo: ez bugos, mert nem hivodik meg a focusExit, amikor ez elveszi a focust
c:\d\libs\het\ui.d(421,35): Todo: support delegates too
c:\d\libs\het\ui.d(429,54): Todo: delegate too
c:\d\libs\het\ui.d(430,64): Todo: lazyness
c:\d\libs\het\ui.d(488,39): Todo: row kell?
c:\d\libs\het\ui.d(514,7): Todo: HintSettings: on/off, hintLocation:nextTo/statusBar/bottomRight, save to ini
c:\d\libs\het\ui.d(533,3): Todo: ez qrvara megteveszto igy, jobb azonositokat kell kitalalni QPS helyett
c:\d\libs\het\ui.d(535,3): Todo: ezt egy alias this-el egyszerusiteni. Jelenleg az im-ben is meg az im.StackEntry-ben is ugyanaz van redundansan deklaralva
c:\d\libs\het\ui.d(538,51): Todo: style.opDispatch("fontHeight=0.5x")
c:\d\libs\het\ui.d(567,56): Todo: ezt a newId-t ki kell valahogy valtani. im.id-t kell inkabb modositani.
c:\d\libs\het\ui.d(590,5): Todo: the first stack container is always 0.
c:\d\libs\het\ui.d(691,46): Todo: this is an 1D bounds
c:\d\libs\het\ui.d(693,5): Todo: handle invalid intervals
c:\d\libs\het\ui.d(704,64): Todo: handle log(0)
c:\d\libs\het\ui.d(763,54): Todo: quoted filename not works
c:\d\libs\het\ui.d(787,37): Opt: Should combine get offset and getScrollBar
c:\d\libs\het\ui.d(806,5): Opt: assocArray.rehash test
c:\d\libs\het\ui.d(813,5): Todo: IDE: nicer error display, and autoSolve: "undefined identifier `global_updateTick`, did you mean variable `global_UpdateTick`?"
c:\d\libs\het\ui.d(853,48): Todo: scrollbars only work on GUI surface. This flag shlould be inherited automatically, just like the upcoming enabled flag.
c:\d\libs\het\ui.d(860,9): Todo: Because it's after hitTest, interaction will be delayed for 1 frame. But it should not.
c:\d\libs\het\ui.d(861,57): Todo: this is duplicated!!!
c:\d\libs\het\ui.d(870,9): Todo: the hitInfo is for the last frame. It should be processed a bit later
c:\d\libs\het\ui.d(916,37): Todo: miafaszom ez?
c:\d\libs\het\ui.d(977,5): Todo: this check is not working because of the IM gui. When ComboBox1 is pulled down and the user clicks on ComboBox2
c:\d\libs\het\ui.d(996,5): Todo: syntax highlight
c:\d\libs\het\ui.d(1046,1): Todo: flex N is fucked up. Treats N as 1 always.
c:\d\libs\het\ui.d(1047,1): Todo: flex() function cant work because of flex property.
c:\d\libs\het\ui.d(1052,86): Todo: not multiline yet
c:\d\libs\het\ui.d(1083,9): Todo: not clear how it works with multiple parameters. All arg strings should be packed in one string and then processed by lines.
c:\d\libs\het\ui.d(1134,72): Todo: no flex needed, -> center aligned. Constant width is needed however, for different bullet styles.
c:\d\libs\het\ui.d(1205,50): Todo: use it for edit as well
c:\d\libs\het\ui.d(1230,5): Todo: handle focused
c:\d\libs\het\ui.d(1242,32): Todo: nem itt van a helye. minden containernek kezelnie kell a selected generic parametert, a focused mar kozpontositva van. Az enabledet is meg kell igy csinalni.
c:\d\libs\het\ui.d(1254,53): Todo: ez felulirja a
c:\d\libs\het\ui.d(1267,30): Todo: update the backgroundColor of the container. Should be automatic, but how?...
c:\d\libs\het\ui.d(1269,5): Todo: handle focused
c:\d\libs\het\ui.d(1310,53): Todo: range clamp
c:\d\libs\het\ui.d(1334,88): Todo: this is not when dr and drGUI is used concurrently. currentMouse id for drUI only.
c:\d\libs\het\ui.d(1349,11): Todo: this must be rewritten with imStorage bounds.
c:\d\libs\het\ui.d(1363,23): Todo: when to write back? always / only when change/exit?
c:\d\libs\het\ui.d(1372,61): Todo: preprocess: with(a, b) -> with(a)with(b)
c:\d\libs\het\ui.d(1391,88): Todo: When the edit is focused, don't let the view to zoom home. Problem: Editor has a priority here, but the view is checked first.
c:\d\libs\het\ui.d(1400,11): Todo: A KeyCombo az ambiguous... nem jo, ha control is meg az input beli is ugyanolyan nevu.
c:\d\libs\het\ui.d(1436,43): Todo: Container.minInnerSize
c:\d\libs\het\ui.d(1511,41): Todo: Enabled in static???
c:\d\libs\het\ui.d(1572,64): Todo: na itt total nem vilagos, hogy az args hova megy, meg mi a result
c:\d\libs\het\ui.d(1652,51): Todo: it's a copy from ListBox. Refactor needed
c:\d\libs\het\ui.d(1658,3): Todo: (enum, enum[]) is ambiguous!!! only (enum) works on its the full members.
c:\d\libs\het\ui.d(1671,34): Todo: theme selection.  tool, white, material... these are conflicting now.
c:\d\libs\het\ui.d(1713,11): Todo: this is a nasty workaround. Need a completely white Btn (link) for this.
c:\d\libs\het\ui.d(1716,37): Todo: Ez kurvaga'ny! Ez adja at a selectiont a draw callbacknak
c:\d\libs\het\ui.d(1825,5): Todo: This is only the base of a listitem. Later it must communicate with a container
c:\d\libs\het\ui.d(1844,63): Todo: rather use an 50% overlay for disabled?
c:\d\libs\het\ui.d(1852,32): Todo: update the backgroundColor of the container. Should be automatic, but how?...
c:\d\libs\het\ui.d(1985,23): Todo: enabled, tool theme
c:\d\libs\het\ui.d(1994,30): Todo: lame way of passing that fucking genericId
c:\d\libs\het\ui.d(2014,19): Todo: passing that fucking genericId
c:\d\libs\het\ui.d(2019,51): Opt: slow search. iterates items twice: 1. in this, 2. in the main ListBox funct
c:\d\libs\het\ui.d(2032,3): Todo: the parameters of all the ListBox-es, ComboBoxes must be refactored. It's a lot of copy paste and yet it's far from full accessible functionality.
c:\d\libs\het\ui.d(2107,5): Todo: what if callee don't handle it????
c:\d\libs\het\ui.d(2112,5): Todo: enabled
c:\d\libs\het\ui.d(2154,44): Todo: tool theme*/
c:\d\libs\het\ui.d(2159,98): Todo: this translator appending is a big mess
c:\d\libs\het\ui.d(2269,84): Todo: test vertical circular slider jump to the very ends, and see if not jumps to opposite si
c:\d\libs\het\ui.d(2296,30): Todo: it can't modify npos because npos can be an integer too. In this case, the pressed_nPos name is bad.
c:\d\libs\het\ui.d(2297,9): Todo: endless????
c:\d\libs\het\ui.d(2298,9): Todo: ha tulmegy, akkor vinnie kell magaval a base-t is!!!
c:\d\libs\het\ui.d(2299,9): Todo: Ctrl precizitas megoldasa globalisan az inputs.d-ben.
c:\d\libs\het\ui.d(2342,36): Todo: enabled handling
c:\d\libs\het\ui.d(2354,41): Todo: "round" knob never jumps
c:\d\libs\het\ui.d(2355,23): Todo: possible bug when the slider disappears, amd the mouse stays locked forever
c:\d\libs\het\ui.d(2370,9): Todo: this isn't safe! what if the control disappears!!!
c:\d\libs\het\ui.d(2388,5): Todo: shift precise mode: must use float knob position to improve the precision
c:\d\libs\het\ui.d(2464,47): Todo: nem clGray ez, hanem clDisabledText vagy ilyesmi
c:\d\libs\het\ui.d(2567,51): Todo: ezt megcsinalni a range-val
c:\d\libs\het\ui.d(2638,55): Todo: selected???
c:\d\libs\het\ui.d(2647,9): Todo: ennek is
c:\d\libs\het\ui.d(2656,42): Todo: refactor endless wrapCnt stuff
c:\d\libs\het\ui.d(2679,5): Todo: what to return on from slider
c:\d\libs\het\ui.d(2717,41): Todo: hint is annoying here
c:\d\libs\het\ui.d(2725,43): Todo: not precise center!!!
c:\d\libs\het\ui.d(2752,25): Todo: ossze kene tudni kombinalni a szomszedos node-ok bordereit.
c:\d\libs\het\ui.d(2781,5): Todo: node header click = open/close node
c:\d\libs\het\ui.d(2786,5): Todo: warning symbol click = open node
c:\d\libs\het\ui.d(2787,5): Todo: warning symbol hint: error message
c:\d\libs\het\ui.d(2835,29): Todo: it has to be inherited
c:\d\libs\het\ui.d(2842,7): Todo: make mouse clicks fall throug this to the parent container
c:\d\libs\het\ui.d(2894,3): Todo: compile time flexible struct builder. Eg.: FieldProps().caption("Capt").unit("mm").logRange(0.1, 1000)
c:\d\libs\het\ui.d(2930,3): Todo: readonly
c:\d\libs\het\ui.d(2958,3): Todo: ComboBox
c:\d\libs\het\ui.d(2981,38): Todo: im.range() conflict
c:\d\libs\het\ui.d(2982,162): Todo: rightclick
c:\d\libs\het\ui.d(2983,7): Todo: Bigger slider height when (theme!="tool")
c:\d\libs\het\ui.d(2992,38): Todo: im.range() conflict
c:\d\libs\het\ui.d(2993,198): Todo: rightclick
c:\d\libs\het\ui.d(3020,54): Todo: ennek inkabb benne kene lennie a Property class-ban...
c:\d\libs\het\stream.d(5,1): Todo: auto ref parameters.
c:\d\libs\het\stream.d(6,1): Todo: srcFunct seems obsolete.
c:\d\libs\het\stream.d(7,1): Todo: srcFunct seems obsolete.
c:\d\libs\het\stream.d(10,1): Todo: propertySet getters with typed defaults
c:\d\libs\het\stream.d(11,1): Todo: propertySet getters with reference output
c:\d\libs\het\stream.d(12,1): Todo: propertySet export to json with act values (or defaults)
c:\d\libs\het\stream.d(13,1): Todo: propertySet import from json with act values (or defaults)
c:\d\libs\het\stream.d(14,1): Todo: string.fromJson(`"hello"`),   int.fromJson("124");  ...
c:\d\libs\het\stream.d(15,1): Todo: "hello".toJson(),   1234.toJson("fieldName");  ...  //must work on const!
c:\d\libs\het\stream.d(16,1): Todo: import a struct from a propertySet
c:\d\libs\het\stream.d(33,80): Todo: this is lame, must make it better in utils/filename routines
c:\d\libs\het\stream.d(85,72): Todo: tokenize throw errors
c:\d\libs\het\stream.d(104,1): Todo: this should be a nonDestructive overwrite for not just classes but for assocArrays too.
c:\d\libs\het\stream.d(105,1): Todo: New name: addJson or includeJson
c:\d\libs\het\stream.d(113,73): Todo: null should reset all fields
c:\d\libs\het\stream.d(127,3): Todo: this mapping is lame
c:\d\libs\het\stream.d(171,20): Opt: is multiply with 1/-1 better?
c:\d\libs\het\stream.d(195,49): Opt: ez a megoldas igy qrvalassu
c:\d\libs\het\stream.d(249,7): Todo: fix this variant long/ulong bug
c:\d\libs\het\stream.d(277,32): Todo: what happens with old instance???!!!
c:\d\libs\het\stream.d(280,11): Todo: Need an own struct initializer because assignment doesn't work: "cannot modify strict instance 'data' of type ... because it contains 'const' or 'immutable' members.
c:\d\libs\het\stream.d(286,42): Opt: with inherited classes it seeks twice. If the tokenizer would be hierarchical then it wouldn't take any time to extract.
c:\d\libs\het\stream.d(301,9): Todo: error handling when there is no classloader for the class in json
c:\d\libs\het\stream.d(312,11): Todo: ezt felvinni a legtetejere es megcsinalni, hogy csak egyszer legyen a tipus ellenorizve
c:\d\libs\het\stream.d(313,11): Todo: Csak descendant classok letrehozasanak engedelyezese, kulonben accessviola
c:\d\libs\het\stream.d(315,53): Opt: inside here, elementMap is extracted once more
c:\d\libs\het\stream.d(353,10): Todo: error handling
c:\d\libs\het\stream.d(399,28): Todo: cut back the array  !!!!!!!!!!!!!!!! what if these are linked classes !!!!!!!!!!!!!!! managed resize array needed
c:\d\libs\het\stream.d(448,55): Todo: try to understand this
c:\d\libs\het\stream.d(455,11): Todo: error if there is no classSaver, throw error
c:\d\libs\het\stream.d(468,5): Todo: this is unoptimal, but at least safe. It is possible to put this inside the [] and {} loop.
c:\d\libs\het\stream.d(581,35): Todo: use binaryJson
c:\d\libs\het\stream.d(604,3): Todo: would be better to save the last value, than update this (and sometimes forget to update)
c:\d\libs\het\stream.d(732,32): Todo: associativearray.update
c:\d\libs\het\stream.d(828,3): Todo: getDef is a bad name. Should be combined with normal get()
c:\d\libs\het\stream.d(937,3): Todo: more tests!
c:\d\libs\het\tokenizer.d(3,43): Todo: size_t-re atallni
c:\d\libs\het\tokenizer.d(8,1): Todo: __EOF__ means end of file , must work inside a comment as well
c:\d\libs\het\tokenizer.d(10,1): Todo: DIDE jegyezze meg a file kurzor/ablak-poziciokat is
c:\d\libs\het\tokenizer.d(11,1): Todo: kulon kezelni az in-t, mint operator es mint type modifier
c:\d\libs\het\tokenizer.d(12,1): Todo: ha elbaszott string van, a parsolas addigi eredmenye ne vesszen el, hogy a syntaxHighlighter tudjon vele mit kezdeni
c:\d\libs\het\tokenizer.d(13,1): Todo: syntax highlight: a specialis karakter \ dolgoknak a stringekben lehetne masmilyen szine.
c:\d\libs\het\tokenizer.d(14,1): Todo: syntax highlight: a tokenstring egesz hatter alapszine legyen masmilyen. Ezt valahogy bele kell vinni az uj editorba.
c:\d\libs\het\tokenizer.d(15,1): Todo: editor: save form position FFS
c:\d\libs\het\tokenizer.d(16,1): Todo: syntax: x"ab01" hex stringeket kezelni. Bugos
c:\d\libs\het\tokenizer.d(20,1): Todo: camelCase
c:\d\libs\het\tokenizer.d(22,1): Todo: highlight escaped strings
c:\d\libs\het\tokenizer.d(23,1): Todo: highlight regex strings
c:\d\libs\het\tokenizer.d(24,1): Todo: nem kell a token.data-t azonnal kiszamolni. Csak lazy modon.
c:\d\libs\het\tokenizer.d(25,1): Todo: TokenKind. camelCase
c:\d\libs\het\tokenizer.d(27,1): Todo: "/+ newline //+ is bad.
c:\d\libs\het\tokenizer.d(39,33): Todo: nem jo, nincs error visszaadas
c:\d\libs\het\tokenizer.d(190,20): Todo: length OR source is redundant
c:\d\libs\het\tokenizer.d(206,29): Todo: make it accessible from utils
c:\d\libs\het\tokenizer.d(258,33): Todo: slow
c:\d\libs\het\tokenizer.d(262,34): Todo: slow
c:\d\libs\het\tokenizer.d(454,68): Todo: this is bad for strings
c:\d\libs\het\tokenizer.d(470,51): Todo: bad naming!
c:\d\libs\het\tokenizer.d(491,99): Todo: op es kw legyen enum vagy legyen osszevonva. Bugoskohoz vezet, mert atfedesben van.
c:\d\libs\het\tokenizer.d(520,30): Todo: ezt az egeszet lehuzni a token beazonositas gyokereig
c:\d\libs\het\tokenizer.d(573,5): Todo: 'else' and ':' is handled later.
c:\d\libs\het\tokenizer.d(612,35): Todo: it is some garbage, what to do with the error
c:\d\libs\het\tokenizer.d(693,54): Todo: atirni ezeket az int-eket size_t-re es benchmarkolni.
c:\d\libs\het\tokenizer.d(797,5): Todo: __EOF__ handling
c:\d\libs\het\tokenizer.d(876,1): Todo: Ez kurvara nem igy megy: A function helyen kell ezt meghivni.
c:\d\libs\het\tokenizer.d(959,63): Todo: this should be only a warning, not a complete failure
c:\d\libs\het\tokenizer.d(1297,53): Todo: highlight #define macros
c:\d\libs\het\tokenizer.d(1331,1): Todo: !is !in
c:\d\libs\het\tokenizer.d(1398,1): Todo: ezt a kibaszottnagy mess-t rendberakni it fent
c:\d\libs\het\tokenizer.d(1406,3): Todo: a delphis } bracket pa'rkereso is bugos: a stringekben levo {-en is megall.
c:\d\libs\het\tokenizer.d(1407,3): Todo: ezt az enumot kivinni es ubye tipusuva tenni, osszevonni
c:\d\libs\het\tokenizer.d(1447,85): Todo: GCN_options
c:\d\libs\het\tokenizer.d(1490,42): Todo: normalis nevet talalni ennek, vagy bele egy structba
c:\d\libs\het\tokenizer.d(1569,26): Todo: revisit strings
c:\d\libs\het\tokenizer.d(1583,1): Todo: rendberakni a commenteket
c:\d\libs\het\tokenizer.d(1584,1): Todo: unittest
c:\d\libs\het\tokenizer.d(1586,1): Todo: optional string postfixes
c:\d\libs\het\keywords.d(9,1): Todo: some types are no more. Complex numbers for example.
c:\d\libs\het\keywords.d(143,34): Todo: make it a Map, after it has a working static initializer.
c:\d\libs\het\keywords.d(361,54): Todo: atirni among()-ra
c:\d\libs\het\keywords.d(377,3): Todo: make it faster with a map
c:\d\libs\het\keywords.d(433,1): Todo: these should be uploaded to the gpu
c:\d\libs\het\keywords.d(434,1): Todo: from the program this is NOT extendable
c:\d\libs\het\keywords.d(469,1): Todo: slow, needs a color theme struct
c:\d\libs\het\keywords.d(473,1): Todo: slow, needs a color theme struct
c:\d\libs\het\uibase.d(9,21): Todo: bad crosslink for scrollInfo
c:\d\libs\het\uibase.d(22,1): Todo: bug: NormalFontHeight = 18*4  -> RemoteUVC.d crashes.
c:\d\libs\het\uibase.d(50,1): Todo: these ugly things are only here to separate uiBase for ui.
c:\d\libs\het\uibase.d(75,1): Todo: Eliminate this dependency injection: addDrawCallback() should be maintained by het.uibase and not het.ui!!
c:\d\libs\het\uibase.d(115,69): Opt: rcp_fast
c:\d\libs\het\uibase.d(126,1): Opt: rcp_fast
c:\d\libs\het\uibase.d(151,5): Todo: architectural bug: captured is delayed by 1 frame according to repeated
c:\d\libs\het\uibase.d(198,37): Todo: get the mouse state from elsewhere!!!!!!!!!!!!!
c:\d\libs\het\uibase.d(234,67): Todo: architectural bug: captured is delayed by 1 frame according to repeated
c:\d\libs\het\uibase.d(475,65): Todo: slow. 'font' Should be a property.
c:\d\libs\het\uibase.d(570,131): Todo: should be half bold?
c:\d\libs\het\uibase.d(734,44): Todo: too many bits
c:\d\libs\het\uibase.d(751,5): Todo: the properties can be in any order.
c:\d\libs\het\uibase.d(752,5): Todo: support the inset property
c:\d\libs\het\uibase.d(823,1): Todo: ha ez nem shared, akkor beszarik a hatterben betolto jpeg. Miert?
c:\d\libs\het\uibase.d(839,77): Todo: this is bad, but fast. maybe do it with a setter and const ref.
c:\d\libs\het\uibase.d(867,5): Todo: ezt at kell irni, hogy az outerSize legyen a tarolt cucc, ne az inner. Indoklas: az outerSize kizarolag csak az outerSize ertek atriasakor valtozzon meg, a border modositasatol ne. Viszont az autoSizet ekkor mashogy kell majd detektalni...
c:\d\libs\het\uibase.d(920,71): Todo: subCell things should be put in Container!
c:\d\libs\het\uibase.d(925,85): Todo: ezeknek az appendeknek a Container-ben lenne a helyuk
c:\d\libs\het\uibase.d(937,51): Todo: int -> size_t
c:\d\libs\het\uibase.d(987,44): Todo: just a line. Used for Spacer, but it's wrond, because it goes negative
c:\d\libs\het\uibase.d(1014,20): Todo: compress information
c:\d\libs\het\uibase.d(1025,32): Todo: ezt a boolean mess-t kivaltani. a chart meg el kene tarolni. ossz 16byte all rendelkezeser ugyis.
c:\d\libs\het\uibase.d(1061,21): Todo: csak a containernek kell border elvileg, ez hatha gyorsit.
c:\d\libs\het\uibase.d(1142,31): Todo: union
c:\d\libs\het\uibase.d(1266,69): Todo: opt
c:\d\libs\het\uibase.d(1288,15): Opt: binary search? (not important: only 1 screen of information)
c:\d\libs\het\uibase.d(1363,32): Todo: more error checking
c:\d\libs\het\uibase.d(1373,49): Todo: refactor
c:\d\libs\het\uibase.d(1388,7): Todo: this should work all the 3 types of carets: idx, lc and xy
c:\d\libs\het\uibase.d(1410,93): Todo: it only works for the same fontHeight and  monospaced stuff
c:\d\libs\het\uibase.d(1485,7): Todo: cMouse pontatlan.
c:\d\libs\het\uibase.d(1486,7): Todo: minden cursor valtozaskor a caret legyen teljesen fekete
c:\d\libs\het\uibase.d(1612,3): Todo: dchar ch;s test
c:\d\libs\het\uibase.d(1701,3): Todo: outerRight is not const
c:\d\libs\het\uibase.d(1706,56): Todo: assume left is 0
c:\d\libs\het\uibase.d(1807,59): Todo: ezt nem menet kozben, hanem egy eloszamitaskent kene meghivni
c:\d\libs\het\uibase.d(1827,25): Todo: shrink?
c:\d\libs\het\uibase.d(1893,50): Todo: after this, the flex width are fucked up.
c:\d\libs\het\uibase.d(1895,9): Todo: itt ha tordeles van, akkor ez szar.
c:\d\libs\het\uibase.d(1904,11): Todo: flex and tab processing
c:\d\libs\het\uibase.d(1919,1): Todo: this WrappedLine tab processing is terribly unoptimal
c:\d\libs\het\uibase.d(1962,9): Todo: itt ha tordeles van, akkor ez szar.
c:\d\libs\het\uibase.d(1979,1): Todo: break word, spaces on edges, tabs vs wrap???
c:\d\libs\het\uibase.d(1986,3): Todo: do this nicer with a table
c:\d\libs\het\uibase.d(1987,103): Todo: ui editor for this
c:\d\libs\het\uibase.d(2071,13): Todo: ezt a publicot leszedni es megoldani szepen
c:\d\libs\het\uibase.d(2104,48): Todo: ezeknek nem kene virtualnak lennie, csak a containernek van borderje, a glyphnek nincs.
c:\d\libs\het\uibase.d(2109,24): Todo: background struct
c:\d\libs\het\uibase.d(2122,5): Todo: flags.setProps param
c:\d\libs\het\uibase.d(2175,7): Opt: cache calcContentSize. It is called too much
c:\d\libs\het\uibase.d(2176,7): Opt: rearrange should optionally return contentSize
c:\d\libs\het\uibase.d(2224,25): Opt: this rearrange can exit early when the wordWrap and contentheight becomes too much.
c:\d\libs\het\uibase.d(2289,11): Todo: resizeButton area between 2 scrollBars. It is now just ignored.
c:\d\libs\het\uibase.d(2350,5): Todo: automatic measure when needed. Currently it is not so well. Because of elastic tabs.
c:\d\libs\het\uibase.d(2357,36): Todo: refactor backgorund and border drawing to functions
c:\d\libs\het\uibase.d(2405,30): Todo: getHScrollBar?.draw(gl);
c:\d\libs\het\uibase.d(2671,45): Todo: refactor this
c:\d\libs\het\uibase.d(2700,5): Todo: don't do this for the line being edited!!!
c:\d\libs\het\uibase.d(2741,58): Todo: wrapped filter support
c:\d\libs\het\uibase.d(2765,20): Opt: maybe not a full remeasure is necessary, just a realign as the subcells inside that are already ordered.
c:\d\libs\het\uibase.d(2783,63): Todo: ez a flex=1 -el egyutt bugzik.
c:\d\libs\het\uibase.d(2834,1): Todo: Ezt le kell valtani egy container.backgroundImage-al.
c:\d\libs\het\uibase.d(2850,5): Todo: do something to prevent a column to resize this. Current workaround: put the Img inside a Row().
c:\d\libs\het\dialogs.d(67,70): Todo: !!!!!!!!!!!!!! zero terminate strings!!!
c:\d\libs\het\dialogs.d(351,33): Todo: save/load ini
c:\d\libs\het\hldc\buildsys.d(7,1): Todo: syntaxHighlight() returns errors! Build system it must handle those!
c:\d\libs\het\hldc\buildsys.d(8,1): Todo: RUN: set working directory to the main.d
c:\d\libs\het\hldc\buildsys.d(9,1): Todo: editor: goto line
c:\d\libs\het\hldc\buildsys.d(10,1): Todo: a todokat, meg optkat meg warningokat, ne jelolje mar pirossal az editorban a filenevek tabjainal.
c:\d\libs\het\hldc\buildsys.d(11,1): Todo: editor find in project files.
c:\d\libs\het\hldc\buildsys.d(12,1): Todo: editor clear errorline when compiling
c:\d\libs\het\hldc\buildsys.d(13,1): Todo: -g flag: symbolic debug info
c:\d\libs\het\hldc\buildsys.d(14,1): Todo: invalid //@ direktivaknal error
c:\d\libs\het\hldc\buildsys.d(15,1): Todo: a dll kilepeskor takaritsa el az obj fileokat
c:\d\libs\het\hldc\buildsys.d(214,18): Todo: ehhez edditort csinalni az ide-ben
c:\d\libs\het\hldc\buildsys.d(302,1): Todo: editor: amikor higlightolja a szot, amin allok, akkor .-al egyutt is meg . nelkul is kene csinalni.
c:\d\libs\het\hldc\buildsys.d(303,1): Todo: info/error logging kozpontositasa.
c:\d\libs\het\hldc\buildsys.d(311,23): Todo: mi a faszert irja ki allandoan az 1 betus roviditest mindenhez???
c:\d\libs\het\hldc\buildsys.d(390,57): Todo: XXH-ra atirni ezt
c:\d\libs\het\hldc\buildsys.d(436,60): Todo: editor: ha typo-t ejtek, es egy nekifutasra irtam be a szot, akkor magatol korrigaljon!
c:\d\libs\het\hldc\buildsys.d(471,27): Opt: unoptimal
c:\d\libs\het\hldc\buildsys.d(488,1): Todo: editor: ha ilyen bazinagy commentbe irok, akkor a keretet ne csusztassa el a jobbszelen.
c:\d\libs\het\hldc\buildsys.d(489,1): Todo: editor: ha ratehenkedek a //-re, es FOLYAMATOSAN nyomom, akkor egeszitse ki 80 char-ig! Ugyanez --ra meg =-re
c:\d\libs\het\hldc\buildsys.d(490,1): Todo: editor: ha hosszan nyomom az r-t, akkor egeszitse ki return-ra!
c:\d\libs\het\hldc\buildsys.d(491,1): Todo: editor: while, if utan rakjon()-t is leptesse a kurzort!
c:\d\libs\het\hldc\buildsys.d(498,14): Todo: rename it to just 'file'
c:\d\libs\het\hldc\buildsys.d(502,33): Todo: it's fucking lame
c:\d\libs\het\hldc\buildsys.d(519,1): Todo: editor ha egy wordon allok, akkor a tobbi wordot case sensitiven keresse! Ez mar nem pascal!
c:\d\libs\het\hldc\buildsys.d(521,1): Todo: editor: ha kijelolok egy szovegreszt es replacezni akarok akkor az autocomplete legordulobe csak az ott elofordulo szavakat rakja ki!
c:\d\libs\het\hldc\buildsys.d(522,1): Todo: editorban ha typo error van es mar nincs rajta a cursor, akkor villogjon az az error, meg legyen egy gomb, ami javitja is az
c:\d\libs\het\hldc\buildsys.d(530,3): Todo: az addIfCan linearis kereses miatt ez igy szornyen lassu: 209 file-t 1.8sec alatt csinalt meg: kesobb majd meg kell csinalni binaris keresesre vagy ami megjobb: NxN-es boolean matrixosra.
c:\d\libs\het\hldc\buildsys.d(559,93): Opt: ez 2x olyan gyors lehetne filter nelkul
c:\d\libs\het\hldc\buildsys.d(639,44): Todo: redundant
c:\d\libs\het\hldc\buildsys.d(649,66): Todo: redundant
c:\d\libs\het\hldc\buildsys.d(671,51): Todo: belerakni az utils-ba, megcsinalni path-osra a DPath-ot.
c:\d\libs\het\hldc\buildsys.d(716,70): Todo: pathosra
c:\d\libs\het\hldc\buildsys.d(743,13): Todo: filekeresest belerakni a filePath-ba.
c:\d\libs\het\hldc\buildsys.d(753,73): Todo: source file/line number visszajelzes
c:\d\libs\het\hldc\buildsys.d(791,70): Todo: not needed to add these, they're implicit -> try it out!
c:\d\libs\het\hldc\buildsys.d(894,81): Todo: refact multi
c:\d\libs\het\hldc\buildsys.d(910,64): Todo: ezt osszevonni a linkerrel
c:\d\libs\het\hldc\buildsys.d(984,49): Todo: ez igy csunya, ahogy at van passzolva
c:\d\libs\het\hldc\buildsys.d(1011,9): Todo: resource compiler totally bugs on 64bit. Workaround: use resource hacker manually
c:\d\libs\het\hldc\buildsys.d(1033,24): Todo: kideriteni, hogy ez miert kell a windowsos cuccokhoz
c:\d\libs\het\hldc\buildsys.d(1044,5): Todo: /ENTRY, /SUBSYSTEM=CONSOLE/WINDOWS  -> VisualD has help.
c:\d\libs\het\hldc\buildsys.d(1054,82): Todo: the place for these is in DPath
c:\d\libs\het\hldc\buildsys.d(1218,121): Todo: include resource hash
c:\d\libs\het\parser.d(5,1): Todo: editor: mouse back/fwd navigalas, mint delphiben
c:\d\libs\het\parser.d(6,1): Todo: 8K, 8M, 8G should be valid numbers! Preprocessing job...
c:\d\libs\het\parser.d(9,18): Todo: Path-osra atirni
c:\d\libs\het\parser.d(11,1): Todo: it's not good for LDC2
c:\d\libs\het\parser.d(192,5): Todo: use FileName, FilePath
c:\d\libs\het\parser.d(296,3): Todo: errol syntax highlight
c:\d\libs\het\parser.d(304,64): Todo: ezt berakni a tokenizerbe
c:\d\libs\het\parser.d(313,130): Todo: ezt szepen megcsinalni IDkkel
c:\d\libs\het\parser.d(363,3): Todo: ezt megcsinalni, hogy kozos id-je legyen az operatoroknak meg a keyworokdnek is
c:\d\libs\het\parser.d(403,5): Todo: public/static/private imports
builderOutputStr";

