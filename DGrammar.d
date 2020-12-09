//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
///@release
//@debug

import het, het.ui, het.tokenizer, het.keywords;

SyntaxGraph[] parseGrammar_official(string text){
  // text is copied from glang.org/grammar.
  // Sections are marked with an identifier on the start of line:                   |Modules
  // Definitions are starting with an identifier on the start of line and a colon:  |Module:
  // Rules are placed after more than 1 spaces:                                     |   ModuleDeclaration DeclDefs
  // empty lines are ignored

  SyntaxGraph[] res;

  static bool isSection   (string s){ return s.isIdentifier; }
  static bool isDefinition(string s){ return s.endsWith(':') && s[0..$-1].isIdentifier; }

  string actSection;
  string[] actDefinition;

  void flush(){
    if(actDefinition.length){
      enforce(actSection.length, "Undefined section");
      enforce(actDefinition.length>=2, "Invalid definition. Must be at least 2 lines");

      //add new graph
      if(res.empty || res[$-1].name != actSection)
        res ~= new SyntaxGraph(actSection);

      auto definitionStr = actDefinition.join('\n');
      //print(actSection, "/", definitionStr);
      res[$-1].appendDefinition_official(definitionStr);

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

  return res;
}



bool isSyntaxLabel(in Token t){
  return (t.isIdentifier) && !t.source.among("Identifier", "IntegerLiteral", "FloatLiteral", "StringLiteral", "CharacterLiteral");
}

class SyntaxLabel : Row { // SyntaxLabel /////////////////////////////
  SyntaxDeclaration parent;
  bool isLink; // a non reference is the caption of the declaration
  string name;

  this(SyntaxDeclaration parent, bool isLink, string text, in TextStyle ts){
    this.name = text;
    this.parent = parent;
    this.isLink = isLink;
    margin = "1";
    border = "normal"; border.color = clCodeBorder;
    appendStr(text, ts);
  }

  auto absOuterBounds() const{ return innerBounds + parent.absInnerPos; };

  auto absOutputPos() const{ return absOuterBounds.rightCenter; }
  auto absInputPos () const{ return absOuterBounds.leftCenter ; }

  auto referencedLabel(){
    if(auto a = name in parent.parent.declarationByName){
      return *a;
    }else{
//      ERR(name);
      return null;
    }
  }
}


class SyntaxDeclaration : Row { // SyntaxDeclaration /////////////////////////////
  mixin CachedMeasuring;
  mixin CachedDrawing;

  SyntaxGraph parent;
  SyntaxLabel titleLabel;
  string title() const { return titleLabel.name; }

  bool isHovered() const{ return this is parent.hoveredDeclaration; }
  bool isSelected;

  this(SyntaxGraph parent, Token[] tokens, SourceCode src){
    this.parent = parent;

    bkColor = clCodeBackground;

    enforce(tokens.length>=3, "Invalid length");
    enforce(tokens[0].isSyntaxLabel, "Syntax label expected instead of: "~tokens[0].text);
    enforce(tokens[1].isOperator(opcolon));

    tokens.popBack; // remove ';'

    margin = "0"; border = "normal"; border.color = clGroupBorder; padding = "2";

    int lastIdx = tokens[0].pos;
    auto ts = tsNormal;
    foreach(idx, t; tokens){
      //emit whitespace
      if(lastIdx < t.pos){ ts.applySyntax(0); appendStr(src.text[lastIdx..t.pos], ts); }

      if(t.isSyntaxLabel){
        const isLink = idx>0;
        ts.applySyntax(isLink ? SyntaxKind.Whitespace : SyntaxKind.BasicType);
        auto l = new SyntaxLabel(this, isLink, t.source, ts);
        append(l);
        if(!isLink){
          titleLabel = l;
          parent.declarationByName[t.source] = this;
        }
      }else{
        ts.applySyntax(src.syntax[t.pos]);
        appendStr(t.source, ts);
      }

      lastIdx = t.endPos;
    }

    enforce(titleLabel, "No title syntaxLabel found");

    measure;
  }

  auto labels(){ return subCells.map!(a => cast(SyntaxLabel)a).filter!"a"; }
  auto links(){ return labels.filter!(a => a.isLink); }

  auto absInnerBounds() const{ return innerBounds + parent.innerPos; };
  auto absInnerPos   () const{ return innerPos    + parent.innerPos; };
}

vec2 importCursor;


class SyntaxGraph : Container { // SyntaxGraph /////////////////////////////
  string name;

  float viewScale = 1;

  void appendDefinition_official(string def){
    print("IMPORTING", def);

    auto src = new SourceCode(def);
    auto a = new SyntaxDeclaration(this, src.tokens, src);
    append(a);

    a.measure;

    a.outerPos = importCursor;
    importCursor.y += a.innerHeight + 10;
  }

/*  void import_dparser(string text){
    // grammar graph source: https://libdparse.dlang.io/grammar.html

    //patch some bugs
    void patch(string old, string new_){
      enforce(text.indexOf(old)>=0, "Unable to do syntax patch "~old.quoted~" -> "~new_.quoted);
      text = text.replace(old, new_);
    }

    patch(`ifCondition:`, `;ifCondition:`); //missing ;
    patch(`identifier`, `Identifier`); //caps
    patch(`stringLiteral`, `StringLiteral`); //caps
    patch(`type2`, `basicType`); //wrong naming: type2 is basicType
    patch(`("(") IdentifierChain "")?`, `('(' IdentifierChain ')')?`); //wrong construct
    patch(`'(') parameters '' *`, `('(' parameters ')')?`); //wrong construct
    patch(`'`, `"`);

    auto src = new SourceCode(text);
    auto declarations = src.tokens.splitDeclarations;
    foreach(idx, blk; declarations){
      auto n = new SyntaxDeclaration(this, blk, src);
      append(n);

      n.outerPos = vec2(-5000, 0).rotate(idx* PIf*2/declarations.length);
    }
  }*/

  this(string name){
    this.name = name;
    bkColor = clBlack;
  }

  auto declarations(){ return subCells.map!(a => cast(SyntaxDeclaration)a); }
  auto selectedDeclarations(){ return declarations.filter!(a => a.isSelected); }

  SyntaxDeclaration[string] declarationByName;

  SyntaxDeclaration hoveredDeclaration;

  struct Link{ SyntaxLabel from; SyntaxDeclaration to; }
  Link[] _links;

  auto links(){
    if(_links.empty)
      foreach(d; declarations)
        foreach(l; d.labels)
          if(l.isLink) if(auto rl = l.referencedLabel)
            _links ~= Link(l, rl);
    return _links;
  }


  vec2 lastMp;
  bool dragging;
  vec2 dragSource;

  void update(View2D view){
    viewScale = view.scale;

    auto mp = view.mousePos,
         md = mp-lastMp;
    lastMp = mp;

    //update focused
    hoveredDeclaration = null;
    foreach(d; declarations) if(d.outerBounds.contains!"[)"(mp)) hoveredDeclaration = d;

    if(inputs.LMB.released) dragging = false;
    if(inputs.LMB.pressed){
      if(hoveredDeclaration && inputs.Shift.down) hoveredDeclaration.isSelected = true;
      if(hoveredDeclaration && inputs.Ctrl .down) hoveredDeclaration.isSelected.toggle;
      if(hoveredDeclaration && !inputs.Shift.down && !inputs.Ctrl.down){
        if(!hoveredDeclaration.isSelected) declarations.each!(a => a.isSelected = a == hoveredDeclaration);
        dragging = true; dragSource = mp;
      }
    }

    if(dragging && md.length){
      foreach(a; selectedDeclarations){
        a.outerPos += md;
        a.cachedDrawing.free;
      }
    }
  }

  override void draw(Drawing dr){
    super.draw(dr);

    auto dr2 = dr.clone;
    with(dr2){
      void markLine(RGB c){ color = c; lineWidth = viewScale>1 ? 1 : -1; }

      foreach(link; links){
        color = RGB(128, 128, 128);
        lineWidth = 1;

        auto h1 = link.from.parent.isHovered, h2 = link.to.isHovered;
        if(h1 && !h2) markLine(clYellow);
        else if(h2 && !h1) markLine(clLime  );

        line2(ArrowStyle.arrow, link.from.absOutputPos, link.to.titleLabel.absInputPos);
      }

      color = clBlue;
      foreach(decl; declarations) if(decl.isSelected){
        lineWidth = -1; drawRect(decl.outerBounds);
        lineWidth =  1; drawRect(decl.outerBounds);
      }

      color = clWhite;
      foreach(decl; declarations) if(decl.isHovered){
        lineWidth = -1; drawRect(decl.outerBounds.inflated(2));
        lineWidth =  1; drawRect(decl.outerBounds.inflated(2));
      }

    }
    dr.subDraw(dr2);
  }

}

class FrmGrammar: GLWindow { mixin autoCreate;  //FrmGrammar ////////////////////////////////////////////

  SyntaxGraph[] graphs;

  override void onCreate(){
  }

  void updateGraphs(){

    // load graphs
    if(graphs.empty){
      auto text = File(appPath, `Dlang grammar official.txt`).readText;

      //patch some bugs
      void patch(string old, string new_){
        enforce(text.indexOf(old)>=0, "Unable to do syntax patch "~old.quoted~" -> "~new_.quoted);
        text = text.replace(old, new_);
      }

      patch("\r\nForeachTypeAttributes\r\n", "\r\nForeachTypeAttributes:\r\n"); //forgot :
      patch("\r\nParamClose\r\n", "\r\nParamClose:\r\n");                       //forgot :

      graphs = parseGrammar_official(text);
    }

    with(im) Panel({
      flags.targetSurface = 0; //it's on the zoomable surface
      bkColor = clBlack; margin = "0"; border = "none"; padding = "0";

      foreach(g; graphs){
        actContainer.append(g);
        g.update(view);
      }
    });
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
      static filterStr = "";
      Row({ Text("Filter "); Edit(filterStr, { flex = 1; }); });

      //filtered data source
      auto table = graphs[0].declarations.filter!(a => a.title.isWild(filterStr~"*"));

      //scroller state
      static topIndex = 0;
      const pageSize = 10;

      //scrolled visible data view
      auto view = table.take(topIndex+pageSize).tail(pageSize).array;

      //focused item
      static SyntaxDeclaration actSyntaxDeclaration;
      Row({
        ListBox(actSyntaxDeclaration, view, (in SyntaxDeclaration sd){ Text(sd.title); }, { width = 270; });
        Spacer;
        Slider(topIndex, range(max(0, table.walkLength.to!int-pageSize), 0), "width=1x height=12x");
      });


    });

  }

  override void onPaint(){
    dr.clear(clBlack);  drGUI.clear;

    im.draw;

    drawFPS(drGUI);
  }
}




