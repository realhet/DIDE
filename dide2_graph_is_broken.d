//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId

//@release
///@debug


import het, het.keywords, het.ui, het.graph, buildsys;


/////////////////////////////////////////////
///    Module graph                       ///
/////////////////////////////////////////////

alias ModuleLabel = GraphLabel!ModuleNode;

class ModuleNode : GraphNode!(ModuleGraph, ModuleLabel) { // ModuleNode /////////////////////////////

  File moduleFile;
  string moduleFullName;

  override string name() const {
    return moduleFile.fullName;
  }

  this(ModuleGraph parent, buildsys.ModuleInfo moduleInfo){
    //todo: parent or not...
    //super(parent);
    id = "ModuleNode:"~moduleInfo.moduleFullName;

    moduleFile = moduleInfo.file;
    moduleFullName = moduleInfo.moduleFullName;
    groupName_original = moduleFile.path.fullPath;

    bkColor = clCodeBackground; border = "normal"; border.color = clGroupBorder; padding = "2";
    auto ts = tsNormal;

    //module name
    ts.applySyntax(SyntaxKind.BasicType);
    ts.fontHeight = 18*6;
    {
      auto moduleLabel = new ModuleLabel(this, false, moduleFile.fullName, moduleFullName, ts);
      moduleLabel.id = "ModuleLabel:"~moduleFullName;
      append(moduleLabel);
    }

    //fileName
    ts.fontHeight = 18;
    ts.fontColor = clGray;
    appendStr("\n"~moduleFile.fullName, ts);
    ts.applySyntax(SyntaxKind.Whitespace);

    ts.applySyntax(SyntaxKind.Whitespace);
    ts.fontHeight = 18;
    foreach(i, mFile; moduleInfo.importedFiles){
      appendStr("\n", ts);
      {
        auto importLabel = new ModuleLabel(this, true, mFile.fullName, mFile.fullName, ts);
        importLabel.id = "ImportLabel:" ~ moduleFullName ~ " imports " ~ moduleInfo.importedModuleNames[i];
        append(importLabel);
      }
    }
  }
}

class ModuleGraph : ContainerGraph!(ModuleNode, ModuleLabel) { // ModuleGraph /////////////////////////////

  File extraFile;

  this(File extraFile){
    id = "ModuleGraph:"~(cast(void*)this).text;
    invertEdgeDirection = true;
    this.extraFile = extraFile;
  }

  auto addModule(buildsys.ModuleInfo moduleInfo){
    if(auto n = findNode(moduleInfo.file.fullName)) return n; //already exists

    auto node = new ModuleNode(this, moduleInfo);
    const nextPos = subCells.length ? subCells[$-1].outerBounds.bottomLeft + vec2(0, 10) : vec2(0);
    node.outerPos = nextPos;

    addNode(node.name, node); //todo: this only adds it to the nodeByName map
    return node;
  }

  //bool initiaZoomDone = false;

  void update2(View2D view){
    const screenSearchBezierStart = vec2(view.clientSize.x-70, 20), //should be calculated from the actual UI location of the SearchBox
          P0 = view.invTrans(screenSearchBezierStart),
          P1 = view.invTrans(screenSearchBezierStart+vec2(0, 300));
    flags.targetSurface = 0; //it's on the zoomable surface
    super.update(view, [P0, P1]);

//todo: workarea
/*    view.workArea = workArea;
    if(view.workArea && chkSet(initiaZoomDone)) view.zoomAll;*/
    im.root ~= this; //add it to the IMGUI
  }

  struct ExtraData{ //todo: exportFields, importFields between aggregates
    vec2 outerPos;
  }

  void saveExtraData(){
    nodes.map!(d => tuple(d.name, ExtraData(d.outerPos)))
         .assocArray //todo: ez nem stable ordered!!!
         .toJson
         .saveTo(extraFile, Yes.onlyIfChanged);
  }

  void loadExtraData(){
    ExtraData[string] tmp;
    tmp.fromJson(extraFile.readText(false));
    foreach(name, data; tmp){
      if(auto a = findNode(name)){
        static foreach(field; FieldNameTuple!(typeof(data))){
          mixin("a.$ = data.$;".replace("$", field));
        }
      }
    }
  }

}


//! FrmMain ///////////////////////////////////////////////
class FrmMain : GLWindow { mixin autoCreate;

  ModuleGraph moduleGraph;

  File testProject = File(`c:\D\projects\DIDE\dide2.d`);

  override void onCreate(){
  }

  override void onUpdate(){
    showFPS = true;

    invalidate; //todo: low power usage
    caption = "DLang grammar viewer";
    view.navigate(!im.wantKeys, !im.wantMouse);

    if(!moduleGraph){
      BuildSystem bs;
      BuildSettings settings = { verbose : false };
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
    });

  }

  override void onPaint(){
    gl.clearColor(RGB(0x2d2d2d)); gl.clear(GL_COLOR_BUFFER_BIT);

  }

}