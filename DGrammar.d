//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
///@release
//@debug

import het, het.ui, het.tokenizer, het.keywords;

bool isSyntaxLabel(in Token t){
  return (t.isKeyword || t.isIdentifier) && !t.source.among("Identifier", "IntegerLiteral", "FloatLiteral", "StringLiteral", "CharacterLiteral", "AsmExp", "functionAttributes", "StringLiteralList");
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
  string name;
  SyntaxLabel title;

  bool isHovered() const{ return this is parent.hoveredDeclaration; }
  bool isSelected;

  this(SyntaxGraph parent, Token[] tokens, SourceCode src){
    this.parent = parent;

    bkColor = clCodeBackground;

    enforce(tokens.length>=3, "Invalid length");
    enforce(tokens[0].isSyntaxLabel, "Syntax label expected instead of: "~tokens[0].text);
    enforce(tokens[1].isOperator(opcolon));
    enforce(tokens[$-1].isOperator(opsemiColon));

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
          title = l;
          parent.declarationByName[t.source] = this;
        }
      }else{
        ts.applySyntax(src.syntax[t.pos]);
        appendStr(t.source, ts);
      }

      lastIdx = t.endPos;
    }

    enforce(title, "No title syntaxLabel found");

    measure;
  }

  auto labels(){ return subCells.map!(a => cast(SyntaxLabel)a).filter!"a"; }
  auto links(){ return labels.filter!(a => a.isLink); }

  auto absInnerBounds() const{ return innerBounds + parent.innerPos; };
  auto absInnerPos   () const{ return innerPos    + parent.innerPos; };
}


class SyntaxGraph : Container { // SyntaxGraph /////////////////////////////
  float viewScale = 1;

  this(string text){
    // grammar graph source: https://libdparse.dlang.io/grammar.html

    bkColor = clBlack;

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

        line2(ArrowStyle.arrow, link.from.absOutputPos, link.to.title.absInputPos);
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

  SyntaxGraph syntaxGraph;

  override void onCreate(){
  }

  void updateSyntaxGraph(){
    if(!syntaxGraph){
      syntaxGraph = new SyntaxGraph(File(appPath, `Dlang grammar.txt`).readText(true));
    }

    with(im) Panel({
      flags.targetSurface = 0; //it's on the zoomable surface
      bkColor = clBlack; margin = "0"; border = "none"; padding = "0";

      actContainer.append(syntaxGraph);
      syntaxGraph.update(view);
    });
  }

  override void onUpdate(){
    invalidate; //opt

    //view.navigate(!im.wantKeys, !im.wantMouse);
    view.navigate(1, 1);

    static actMode = 1;

    with(im) Panel(PanelPosition.topLeft, {
      width = 300;
      vScroll;

//      ListBox(syntaxGraph.)
      Row({
        Btn("Hello!");
      });
    });

    updateSyntaxGraph;

  }

  override void onPaint(){
    dr.clear(clBlack);  drGUI.clear;

    im.draw;

    drawFPS(drGUI);
  }
}




