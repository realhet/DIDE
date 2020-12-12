//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
//@release
///@debug

import het, het.ui, het.tokenizer, het.keywords, het.stream;


// ScrollListBox ///////////////////////////////////////////////

static void ScrollListBox(T, U, string file=__FILE__ , int line=__LINE__)(ref T focusedItem, U items, void delegate(in T) cellFun, int pageSize, ref int topIndex)
if(isInputRange!U && is(ElementType!U == T))
{with(im){
  auto view = items.take(topIndex+pageSize).tail(pageSize).array;
  Row!(file, line)({
    ListBox(focusedItem, view, cellFun);
    Spacer;
    Slider(topIndex, range(max(0, items.walkLength.to!int-pageSize), 0), "width=1x height=12x"/+todo: yalign = stretch+/);
  });
}}


class SelectionManager(T){ // SelectionManager ///////////////////////////////////////////////
  //T should have selected and hovered properties
  vec2 mouseLast;
  T hoveredItem;

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

  void update(bool mouseEnabled, View2D view, T[] items){

    void selectNone()           { foreach(a; items) a.isSelected = false; }
    void selectOnly(T item)     { selectNone; if(item) item.isSelected = true; }
    void selectHoveredOnly()    { selectOnly(hoveredItem); }
    void saveOldSelected()      { foreach(a; items) a.oldSelected = a.isSelected; }

    // acquire mouse positions
    auto mouseAct = view.mousePos;
    auto mouseDelta = mouseAct-mouseLast;
    scope(exit) mouseLast = mouseAct;

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
    if(mouseEnabled) foreach(item; items) if(item.outerBounds.contains!"[)"(mouseAct)) hoveredItem = item;

    if(LMB_pressed && mouseEnabled){ // Left Mouse pressed ///////////////////////////////////////
      if(hoveredItem){
        if(modNone){ if(!hoveredItem.isSelected) selectHoveredOnly;  mouseOp = MouseOp.move; }
        if(modShift || modCtrl || modShiftCtrl) hoveredItem.isSelected.toggle;
      }else{
        mouseOp = MouseOp.rectSelect;
        saveOldSelected;
      }
    }

    {// update ongoing things ////////////////////////////////////////////////////////////
      if(mouseOp == MouseOp.rectSelect && inputChanged){
        foreach(a; items) if(dragBounds.contains!"[]"(a.outerBounds)){
          final switch(selectOp){
            case SelectOp.add, SelectOp.clearAdd : a.isSelected = true ; break;
            case SelectOp.sub                    : a.isSelected = false; break;
            case SelectOp.toggle                 : a.isSelected = !a.oldSelected; break;
            case SelectOp.none                   : break;
          }
        }else{
          a.isSelected = (selectOp == SelectOp.clearAdd) ? false : a.oldSelected;
        }
      }
    }

    if(mouseOp == MouseOp.move && mouseDelta){
      foreach(a; items) if(a.isSelected){
        a.outerPos += mouseDelta;
        a.cachedDrawing.free;
      }
    }


    if(LMB_released){ // left mouse released /////////////////////////////////////

      //...

      mouseOp = MouseOp.idle;
    }
  }

}


bool isSyntaxLabel(in Token t){
  return (t.isIdentifier) && !t.source.among("Identifier", "IntegerLiteral", "FloatLiteral", "StringLiteral", "CharacterLiteral");
}

class SyntaxLabel : Row { // SyntaxLabel /////////////////////////////
  SyntaxDefinition parent;
  bool isLink; // a non reference is the caption of the definition
  string name;

  this(SyntaxDefinition parent, bool isLink, string text, in TextStyle ts){
    this.name = text;
    this.parent = parent;
    this.isLink = isLink;
    appendStr(text, ts);
  }

  auto absOuterBounds() const{ return innerBounds + parent.absInnerPos; };

  auto absOutputPos() const{ return absOuterBounds.rightCenter; }
  auto absInputPos () const{ return absOuterBounds.leftCenter ; }

  auto referencedLabel(){
    if(auto a = name in parent.parent.definitionByName){
      return *a;
    }else{
//      ERR(name);
      return null;
    }
  }
}


class SyntaxDefinition : Row { // SyntaxDefinition /////////////////////////////
  mixin CachedMeasuring;
  mixin CachedDrawing;

  string groupName_original;
  string groupName_override;
  string groupName() const { return groupName_override.length ? groupName_override : groupName_original; }

  SyntaxGraph parent;
  SyntaxLabel nameLabel;
  string name() const { return nameLabel.name; }

  string fullName() const { return groupName ~ "/" ~ name; }

  bool isHovered() { return this is parent.hoveredDefinition; }
  bool isSelected, oldSelected;

  this(SyntaxGraph parent, Token[] tokens, SourceCode src){
    this.parent = parent;

    bkColor = clCodeBackground;

    enforce(tokens.length>=3, "Invalid length");
    enforce(tokens[0].isSyntaxLabel, "Syntax label expected instead of: "~tokens[0].text);
    enforce(tokens[1].isOperator(opcolon));

    margin = "0"; border = "normal"; border.color = clGroupBorder; padding = "2";

    int lastIdx = tokens[0].pos;
    auto ts = tsNormal;
    foreach(idx, t; tokens){
      //emit whitespace
      if(lastIdx < t.pos){ ts.applySyntax(0); appendStr(src.text[lastIdx..t.pos], ts); }

      if(t.isSyntaxLabel){
        const isLink = idx>0;

        ts.applySyntax(isLink ? SyntaxKind.Whitespace : SyntaxKind.BasicType);
        ts.underline = isLink;
        ts.italic = true;

        auto l = new SyntaxLabel(this, isLink, t.source, ts);
        append(l);
        if(!isLink){
          nameLabel = l;
          if(t.source in parent.definitionByName) ERR("Definition already exists:", t.source);
          parent.definitionByName[t.source] = this;
        }
      }else{
        ts.applySyntax(src.syntax[t.pos]);
        appendStr(t.source, ts);
      }

      lastIdx = t.endPos;
    }

    enforce(nameLabel, "No title syntaxLabel found");

    measure;
  }

  auto labels(){ return subCells.map!(a => cast(SyntaxLabel)a).filter!"a"; }
  auto links(){ return labels.filter!(a => a.isLink); }

  auto absInnerBounds() const{ return innerBounds + parent.innerPos; };
  auto absInnerPos   () const{ return innerPos    + parent.innerPos; };
}

class SyntaxGraph : Container { // SyntaxGraph /////////////////////////////
  float viewScale = 1; //used for automatic screenspace linewidth

  this(){
    bkColor = clBlack;
  }

  this(string text){ this(); importGrammar_official(text); }

  this(File f){ this(f.readText); }

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
    //print("IMPORTING", def);

    const nextPos = subCells.length ? subCells[$-1].outerBounds.bottomLeft + vec2(0, 10) : vec2(0);

    def = def.replace("opt", "?");

    auto src = new SourceCode(def);
    auto a = new SyntaxDefinition(this, src.tokens, src);
    a.groupName_original = groupName;
    a.outerPos = nextPos;
    append(a);
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


  auto definitions(){ return subCells.map!(a => cast(SyntaxDefinition)a); }

  SyntaxDefinition[string] definitionByName;

  struct Link{ SyntaxLabel from; SyntaxDefinition to; }
  Link[] _links;

  auto links(){
    if(_links.empty)
      foreach(d; definitions)
        foreach(l; d.labels)
          if(l.isLink) if(auto rl = l.referencedLabel)
            _links ~= Link(l, rl);
    return _links;
  }

  SelectionManager!SyntaxDefinition selection;

  auto selectedDefinitions(){ return definitions.filter!(a => a.isSelected); }
  auto hoveredDefinition  (){ return selection.hoveredItem; }

  void update(View2D view){
    viewScale = view.scale;

    if(!selection) selection = new typeof(selection);

    selection.update(!im.wantMouse, view, definitions.array);
  }

  override void draw(Drawing dr){
    super.draw(dr);

    auto dr2 = dr.clone;
    with(dr2){
      /// sets a linewidth that can't be smaller than 1 (or lw)
      void setHighlightLineWidth(float lw = 1){
        dr2.lineWidth = (viewScale>1 ? 1 : -1)*lw;
      }

      /// draws a always visible rect
      void drawRect2(in bounds2 bnd, RGB c){ with(dr2){
        color = c;
        lineWidth = viewScale>1 ? 1 : -1;
        drawRect(bnd);
      }}

      void fillRect2(in bounds2 bnd, RGB c, float a){ with(dr2){
        alpha = a;
        color = c;
        fillRect(bnd);
        alpha = 1;
      }}

      //draw arrows
      alpha = 0.5;
      foreach(link; links) if(link.from.parent.groupName == link.to.groupName){
        const h1 = link.from.parent.isHovered, h2 = link.to.isHovered;

        color  = h1 && !h2 ? clYellow
               : h2 && !h1 ? clLime
                           : clSilver;

        lineWidth = viewScale>1 ? 1 : -1;
        line2(ArrowStyle.arrow, /*LineStyle.dash, */link.from.absOutputPos, link.to.nameLabel.absInputPos);
      }
      alpha = 1;

      foreach(decl; definitions) if(decl.isSelected) fillRect2(decl.outerBounds, clAccent, 0.25);
      foreach(decl; definitions) if(decl.isHovered ) fillRect2(decl.outerBounds, clWhite , 0.2);

      if(auto bnd = selection.selectionBounds){
        dbounds2 db;
        db = cast(dbounds2)bnd;
        lineWidth = -1;
        color = clWhite;
        drawRect(bnd);
      }

      foreach(grp; definitions.array.sort!((a, b) => a.groupName < b.groupName).groupBy){
        bounds2 bnd;
        foreach(a; grp.map!(a => a.outerBounds)) bnd |= a;

        color = clSilver;
        lineWidth = -1;
        drawRect(bnd.inflated(20));
      }

    }
    dr.subDraw(dr2);
  }

}

class FrmGrammar: GLWindow { mixin autoCreate;  //FrmGrammar ////////////////////////////////////////////

  SyntaxGraph graph;

  override void onCreate(){
  }

  auto extraFile   (){ return File(appPath, "DLang grammar extra data.txt"); }

  struct ExtraData{ //todo: exportFields, importFields  between aggregates
    vec2 outerPos;
    string groupName_override;
  }

  void loadGraph(){
    if(graph) return;

    graph = new SyntaxGraph(File(appPath, `Dlang grammar official.txt`));

    ExtraData[string] tmp;
    tmp.fromJson(extraFile.readText(false));
    foreach(name, data; tmp){
      if(auto a = name in graph.definitionByName){
        static foreach(field; FieldNameTuple!(typeof(data))){
          mixin("(*a).$ = data.$;".replace("$", field));
        }
      }
    }
  }

  void saveExtraData(){
    graph.definitions.map!(d => tuple(d.name, ExtraData(d.outerPos, d.groupName_override))).assocArray.toJson.saveTo(extraFile);
  }

  void updateGraphs(){
    loadGraph;

    graph.flags.targetSurface = 0; //it's on the zoomable surface
    im.root ~= graph;
    graph.update(view);
  }

  override void onUpdate(){
    updateGraphs;

    view.navigate(!im.wantKeys, !im.wantMouse);

    invalidate; //opt

    static actMode = 1;

    with(im) Panel(PanelPosition.topLeft, {
      width = 300;
      vScroll;

      // WildCard filter
      static hideUI = false;
      static filterStr = "";
      Row({ ChkBox(hideUI, "Hide UI "); Text("Filter "); Edit(filterStr, { flex = 1; }); });

      if(!hideUI){

        //filtered data source
        auto filteredDefinitions = graph.definitions.filter!(a => a.name.isWild(filterStr~"*"));

        //scroller state
        static SyntaxDefinition actSyntaxDefinition; //state
        static topIndex = 0; //state
        const pageSize = 10;

        ScrollListBox!SyntaxDefinition(actSyntaxDefinition, filteredDefinitions, (in SyntaxDefinition sd){ Text(sd.name); width = 260; }, pageSize, topIndex);

        Spacer;
        Row({
          auto selected = graph.selectedDefinitions.array;
          Row({ Text("Selected items: "), Static(selected.length), Text("  Total: "), Static(graph.definitions.length); });

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

    });

  }

  override void onPaint(){
    dr.clear(clBlack);  drGUI.clear;

    im.draw;

    drawFPS(drGUI);
  }

  override void onDestroy(){
    saveExtraData;
  }
}