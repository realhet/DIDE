//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
///@release
//@debug

//@RUN $
//@RUN pause

import het, het.ui, het.tokenizer, het.keywords, het.stream;

class GraphLabel(Node) : Row { // GraphLabel /////////////////////////////
  Node parent;
  bool isReference; // a non reference is the caption of the definition
  string name;

  this(){}
  this(Node parent, bool isReference, string text, in TextStyle ts){
    this.name = text;
    this.parent = parent;
    this.isReference = isReference;
    appendStr(text, ts);
  }

  this(Node parent, bool isReference, string text){
    auto ts = tsNormal;
    ts.applySyntax(isReference ? SyntaxKind.Whitespace : SyntaxKind.BasicType);
    ts.underline = isReference;
    ts.italic = true;
    this(parent, isReference, text, ts);
  }

  auto absOuterBounds() const{ return innerBounds + parent.absInnerPos; }
  auto absOutputPos  () const{ return absOuterBounds.rightCenter; }
  auto absInputPos   () const{ return absOuterBounds.leftCenter ; }
}

class GraphNode(Graph, Label) : Row { // GraphNode /////////////////////////////
  mixin CachedMeasuring;
  mixin CachedDrawing;

  Graph parent;

  this(Graph parent){
    this.parent = parent;
  }

  bool isSelected, oldSelected;
  bool isHovered() { return this is parent.hoveredNode; }

  string groupName_original;
  string groupName_override;
  string groupName() const { return groupName_override.length ? groupName_override : groupName_original; }

  string fullName() const { return groupName ~ "/" ~ name; }

  auto labels    (){ return subCells.map!(a => cast(SyntaxLabel)a).filter!"a"; }
  auto targets   (){ return labels.filter!(a => !a.isReference); }
  auto references(){ return labels.filter!(a =>  a.isReference); }

  Label nameLabel(){ foreach(t; targets) return t; return null; }

  string name() const {
    foreach(t; (cast()this).targets) return t.name;
    return "";
  }

  auto absInnerBounds() const{ return innerBounds + parent.innerPos; };
  auto absInnerPos   () const{ return innerPos    + parent.innerPos; };
}

class ContainerGraph(Node : Cell, Label : GraphLabel!Node) : Container { // ContainerGraph ///////////////////////////////////////////
  static assert(__traits(compiles, {
    Node n; string s = n.groupName; //this could be optional.
  }), "Field requirements not met.");

  SelectionManager!Node selection;

  auto nodes        (){ return cast(Node[])subCells; } //note: all subcells' type must be Node
  auto selectedNodes(){ return nodes.filter!(a => a.isSelected); }
  auto hoveredNode  (){ return selection.hoveredItem; }

  private Node[string] _nodeByName;
  auto nodeByName(string name){ auto a = name in _nodeByName; return a ? *a : null; }
  void addNode(string name, Node node){
    enforce(cast(Node)node !is null, "addNode() must be a valid "~Node.stringof);
    enforce((name in _nodeByName)is null, "Node named "~name.quoted~" already exists");
    _nodeByName[name] = node;
  }

  float groupBoundMargin = 30;
  auto nodeGroups(){ return nodes.dup.sort!((a, b) => a.groupName < b.groupName).groupBy; } //note .dup is important because .sort works in place.
  auto groupBounds(){ return nodeGroups.map!(grp => grp.map!(a => a.outerBounds).fold!"a|b".inflated(groupBoundMargin)); }

  Container.SearchResult[] searchResults;
  bool searchBoxVisible;
  string searchText;

  // inputs from outside
  private{
    float viewScale = 1; //used for automatic screenspace linewidth
    vec2[2] searchBezierStart; //first 2 point of search bezier lines. Starting from the GUI matchCount display.
  }

  protected bounds2 _workArea; //calculated in draw
  auto workArea(){ return _workArea; }

  this(){
    bkColor = clBlack;
    selection = new typeof(selection);
  }

  struct Link{ Label from; SyntaxDefinition to; }
  Link[] _links;

  auto links(){
    if(_links.empty)
      foreach(d; nodes)
        foreach(from; d.labels)
          if(from.isReference) if(auto to = nodeByName(from.name))
            _links ~= Link(from, to);
    return _links;
  }

  void update(View2D view, vec2[2] searchBezierStart){
    this.viewScale = view.scale;
    this.searchBezierStart = searchBezierStart;

    selection.update(!im.wantMouse, view, subCells.map!(a => cast(Node)a).array);
  }

  // drawing routines ////////////////////////////////////////////

  protected void drawSearchResults(Drawing dr, RGB clSearchHighLight){ with(dr){
    foreach(sr; searchResults)
      sr.drawHighlighted(dr, clSearchHighLight);

    lineWidth = -2 * sqr(sin(QPS.fract*PIf*2));
    alpha = 0.66;
    color = clSearchHighLight;
    foreach(sr; searchResults)
      bezier2(searchBezierStart[0], searchBezierStart[1], sr.absInnerPos + sr.cells.back.outerBounds.rightCenter);

    alpha = 1;
  }}

  protected void drawSelectedItems(Drawing dr, RGB clSelected, float selectedAlpha, RGB clHovered, float hoveredAlpha){ with(dr){
    color = clSelected; alpha = selectedAlpha;  foreach(a; selectedNodes) dr.fillRect(a.outerBounds);
    color = clHovered ; alpha = hoveredAlpha ;  if(hoveredNode !is null) dr.fillRect(hoveredNode.outerBounds);
    alpha = 1;
  }}

  protected void drawSelectionRect(Drawing dr, RGB clRect){
    if(auto bnd = selection.selectionBounds) with(dr) {
      lineWidth = -1;
      color = clRect;
      drawRect(bnd);
    }
  }

  protected void drawGroupBounds(Drawing dr, RGB clGroupFrame){ with(dr){
    color = clGroupFrame;
    lineWidth = -1;
    foreach(bnd; groupBounds) drawRect(bnd);
  }}

  protected void drawLinks(Drawing dr){ with(dr){
    alpha = 0.66;
    foreach(link; links){
      const h1 = link.from.parent.isHovered, h2 = link.to.isHovered;

      //hide interGroup links
      if(!h1 && !h2 && link.from.parent.groupName != link.to.groupName) continue;

      color  = h1 && !h2 ? clAqua
             : h2 && !h1 ? clLime
                         : clSilver;

      lineWidth = viewScale>1 ? 1 : -1; //line can't be thinner than 1 pixel, but can be thicker

      vec2 P0 = link.from.absOutputPos, P4 = link.to.nameLabel.absInputPos;
      float a = min(50, distance(P0, P4)/3);
      vec2 ofs = P0.x<P4.x ? vec2(a, 0) : vec2(a, -a),
           P1 = P0 + ofs,
           P3 = P4 + ofs*vec2(-1, 1),
           P2 = avg(P1, P3);

      bezier2(P0, P1, P2);
      bezier2(P2, P3, P4);
    }
    alpha = 1;
  }}

  protected void drawOverlay(Drawing dr){ with(dr){
    drawLinks(dr);
    drawSelectedItems(dr, clAccent, 0.25, clWhite, 0.2);
    drawSelectionRect(dr, clWhite);
    drawGroupBounds(dr, clSilver);
    drawSearchResults(dr, clYellow);
  }}

  override void draw(Drawing dr){
    super.draw(dr); //draw cached stuff

    auto dr2 = dr.clone;
    drawOverlay(dr2); //draw uncached stuff on top
    dr.subDraw(dr2);

    _workArea = dr.bounds;
  }

  void UI_SearchBox(View2D view){ // UI SearchBox ////////////////////////////////
    with(im) Row({
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
          searchResults = search(searchText);
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
    });
  }

  //scroller state
  SyntaxDefinition actSyntaxDefinition; //state
  auto topIndex = 0; //state
  enum pageSize = 10;

  void UI_Editor(){ with(im){ // UI_Editor ///////////////////////////////////
    // WildCard filter
    static hideUI = true;
    static filterStr = "";
    Row({ ChkBox(hideUI, "Hide Graph UI "); });

    if(!hideUI){

      Row({ Text("Filter "); Edit(filterStr, { flex = 1; }); });

      //filtered data source
      auto filteredDefinitions = nodes.filter!(a => a.name.isWild(filterStr~"*")).array;
      ScrollListBox!SyntaxDefinition(actSyntaxDefinition, filteredDefinitions, (in SyntaxDefinition sd){ Text(sd.name); width = 260; }, pageSize, topIndex);

      Spacer;
      Row({
        auto selected = selectedNodes.array;
        Row({ Text("Selected items: "), Static(selected.length), Text("  Total: "), Static(nodes.length); });

        const selectedGroupNames = selected.map!(a => a.groupName).array.sort.uniq.array;
        static string editedGroupName;
        Row({
          Text("Selected groups: ");
          foreach(i, name; selectedGroupNames)
            if(Btn(name, id(cast(int)i))) editedGroupName = name;
        });

        Spacer;
        Row({
          Text("Group name os felected items: \n");
          Edit(editedGroupName, { width = 200; });
          if(Btn("Set", enable(selected.length>0))) foreach(a; selected) a.groupName_override = editedGroupName;
        });

      });

      Spacer;
      if(Btn("test")){
      }

    }
  }}

}

/////////////////////////////////////////////
///    Syntax graph for DLang grammar     ///
/////////////////////////////////////////////

alias SyntaxLabel = GraphLabel!SyntaxDefinition;

class SyntaxDefinition : GraphNode!(SyntaxGraph, SyntaxLabel) { // SyntaxDefinition /////////////////////////////

  this(SyntaxGraph parent, Token[] tokens, SourceCode src){
    super(parent);

    static bool isSyntaxLabel(in Token t){ return (t.isIdentifier) && !t.source.among("Identifier", "IntegerLiteral", "FloatLiteral", "StringLiteral", "CharacterLiteral"); }

    enforce(tokens.length>=3, "Invalid length");
    enforce(isSyntaxLabel(tokens[0]), "Syntax label expected instead of: "~tokens[0].text);
    enforce(tokens[1].isOperator(opcolon));

    bkColor = clCodeBackground; border = "normal"; border.color = clGroupBorder; padding = "2";

    int lastIdx = tokens[0].pos;
    auto ts = tsNormal;
    foreach(idx, t; tokens){
      //emit whitespace
      if(lastIdx < t.pos){ ts.applySyntax(0); appendStr(src.text[lastIdx..t.pos], ts); }

      //emit the actual token
      if(isSyntaxLabel(t)){
        const isReference = idx>0;
        append(new SyntaxLabel(this, isReference, t.source));
      }else{
        ts.applySyntax(src.syntax[t.pos]);
        appendStr(t.source, ts);
      }

      lastIdx = t.endPos;
    }

    enforce(nameLabel !is null, "No target GraphLabel found. Unable to get Node's name.");
    parent.addNode(name, this);
  }
}

class SyntaxGraph : ContainerGraph!(SyntaxDefinition, SyntaxLabel) { // SyntaxGraph /////////////////////////////

  this(string text){ super(); importGrammar_official(text); }

  File mainFile, extraFile;

  this(File mainFile, File extraFile){
    this.mainFile = mainFile;
    this.extraFile = extraFile;

    this(mainFile.readText);

    loadExtraData;
  }

  struct ExtraData{ //todo: exportFields, importFields between aggregates
    vec2 outerPos;
    string groupName_override;
  }

  void saveExtraData(){
    nodes.map!(d => tuple(d.name, ExtraData(d.outerPos, d.groupName_override)))
         .assocArray //todo: ez nem stable ordered!!!
         .toJson
         .saveTo(extraFile, Yes.onlyIfChanged);
  }

  void loadExtraData(){
    ExtraData[string] tmp;
    tmp.fromJson(extraFile.readText(false));
    foreach(name, data; tmp){
      if(auto a = nodeByName(name)){
        static foreach(field; FieldNameTuple!(typeof(data))){
          mixin("a.$ = data.$;".replace("$", field));
        }
      }
    }
  }

  private void patch_official(ref string text){
    //patch some bugs
    void patch(alias fun=replace)(string old, string new_){
      enforce(text.indexOf(old)>=0, "Unable to do syntax patch "~old.quoted~" -> "~new_.quoted);
      text = fun(text, old, new_);
    }

    void patch_removeDuplicate(string head, string contents, string remaining){
      patch(head~contents, remaining);
      enforce(text.canFind(head), "patch_removeDuplicate failed: "~quoted(head));
    }

    patch("\r\nForeachTypeAttributes\r\n", "\r\nForeachTypeAttributes:\r\n"); //forgot :
    patch("\r\nParamClose\r\n", "\r\nParamClose:\r\n");                       //forgot :

    //there are 2 definitions of FunctionLiteralBody. The first one is seems outdated.
    patch_removeDuplicate("\r\nFunctionLiteralBody:\r\n", "    BlockStatement\r\n    FunctionContractsopt BodyStatement\r\n", "\r\n");

    // this part is redundant, also it has bad indentation
    patch(["AsmStatement:", "    asm FunctionAttributesopt { AsmInstructionListopt }", "",
          "    AsmInstructionList:", "        AsmInstruction ;", "        AsmInstruction ; AsmInstructionList"].join("\r\n"), "");

    // this garbage is at the end of the Classes section
    patch(["class Identifier : SuperClass Interfaces AggregateBody", "// ...", "new AllocatorArguments Identifier ConstructorArgs"].join("\r\n"), "");

    if(1){ //Application Binary Interface patches
      auto abiPos = text.indexOf("Application Binary Interface\r\n");
      enforce(abiPos>=0, "Cant fint `Application Binary Interfac` part.");

      auto temp = text[abiPos..$];
      foreach(s; ["Type", "Parameter", "Parameters"]){ //these are duplicated identifiers. Must rename them to be placed on the same graph.
        auto to = s~"_";
        temp = temp.replaceWords(s, to);
        enforce(temp.canFind(to), "ABI patch failed: "~quoted(s));
      }

      text = text[0..abiPos] ~ temp;
    }
  }

  void appendDefinition_official(string def, string groupName){
    def = def.replace("opt", "?");

    auto src = new SourceCode(def);
    auto node = new SyntaxDefinition(this, src.tokens, src);
    node.groupName_original = groupName;
    const nextPos = subCells.length ? subCells[$-1].outerBounds.bottomLeft + vec2(0, 10) : vec2(0);
    node.outerPos = nextPos;
    append(node);
  }

  void importGrammar_official(string text){
    // text is copied from glang.org/grammar.
    // Sections are marked with an identifier on the start of line:                   |Modules
    // Definitions are starting with an identifier on the start of line and a colon:  |Module:
    // Rules are placed after more than 1 spaces:                                     |   ModuleDefinition DeclDefs
    // empty lines are ignored

    patch_official(text);

    static bool isSection   (string s){ return isWordChar(s[0]) && s.map!(ch => isWordChar(ch) || ch==' ').all; }
    static bool isDefinition(string s){ return s.endsWith(':') && s[0..$-1].isIdentifier; }

    string actSection;
    string[] actDefinition;

    enum logDefinitions = false;

    void flush(){
      if(actDefinition.length){
        enforce(actSection.length, "Undefined section");
        enforce(actDefinition.length>=2, "Invalid definition. Must be at least 2 lines");

        auto definitionStr = actDefinition.join('\n');
        if(logDefinitions) print(actSection, " / ", actDefinition[0]);
        appendDefinition_official(definitionStr, actSection);

        actDefinition = [];
      }
    }

    //Imput conditioning split lines, strip from right, drop empty lines
    foreach(line; text.split('\n').map!stripRight.filter!"a.length"){
      if(isSection(line)){
        flush;
        actSection = line;
      }else{
        if(isDefinition(line)) flush;
        actDefinition ~= line;
      }
    }
    flush;
  }

}

struct DlangGrammarGraph { // DlangGrammarGraph ////////////////////////////
  private SyntaxGraph graph_;
  bool initiaZoomDone = false;

  auto graph(){
    if(graph_ is null)
      graph_ = new SyntaxGraph(File(appPath, `Dlang grammar official.txt`  ),
                               File(appPath, `DLang grammar extra data.txt`));
    return graph_;
  }

  void update(View2D view){
    const screenSearchBezierStart = vec2(view.clientSize.x-70, 20), //should be calculated from the actual UI location of the SearchBox
          P0 = view.invTrans(screenSearchBezierStart),
          P1 = view.invTrans(screenSearchBezierStart+vec2(0, 300));
    graph.flags.targetSurface = 0; //it's on the zoomable surface
    graph.update(view, [P0, P1]);
    view.workArea = graph.workArea;
    if(view.workArea && chkSet(initiaZoomDone)) view.zoomAll;
    im.root ~= graph; //add it to the IMGUI
  }

  ~this(){
    if(graph_) graph_.saveExtraData;
  }

}

class FrmGrammar: GLWindow { mixin autoCreate;  //!FrmGrammar ////////////////////////////////////////////

  DlangGrammarGraph dlangGrammarGraph;

  override void onCreate(){
    //logFileOps = true;
  }

  override void onUpdate(){
    caption = "DLang grammar viewer";
    view.navigate(!im.wantKeys, !im.wantMouse);

    dlangGrammarGraph.update(view);

    if(1) with(im) Panel(PanelPosition.topLeft, {
      width = 300;
      vScroll;

      dlangGrammarGraph.graph.UI_Editor;
    });

    with(im) Panel(PanelPosition.topRight, {
      dlangGrammarGraph.graph.UI_SearchBox(view);
    });

    invalidate; //opt
  }

  override void onPaint(){
    gl.clearColor(clBlack);
    gl.clear(GL_COLOR_BUFFER_BIT);

    im.draw;

    if(1){
      auto dr = scoped!Drawing;
      drawFPS(dr);
      dr.glDraw(viewGUI);
    }
  }

  override void onDestroy(){
  }

}