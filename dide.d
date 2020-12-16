//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
//@release
///@debug

///@run $ c:\d\libs\het\test\syntaxTestText.d
//@run $ dide.d
///@run $ c:\D\ldc2\import\std\datetime\systime.d
///@run $ c:\D\libs\het\utils.d
///@run $ c:\D\libs\het\math.d
///@run $ c:\D\libs\het\opengl.d
///@run $ c:\D\libs\het\draw3d.d

import het, het.ui, het.tokenizer, het.keywords;

/*comment1*/@safe void testFunction()(/*comment3*/) /*comment4*/ { //comment2
  if(a) b;
}

public{// Utility stuff ///////////////////////////////////////////////////////////////////

//todo: detectTabs


void applyCodeContainerFlags(Container container){
  // general flags
  with(container.flags){
    canWrap = false;
    dontHideSpaces = true;
    rowElasticTabs = true;
  }
}

}public{// Syntax highlight styles ///////////////////////////////////////////////////////

void appendCode(Row row, Token[] tokens, SourceCode sourceCode, bool setBkColor=true){
  if(setBkColor) row.bkColor = clCodeBackground;
  if(tokens.length){
    auto st = tokens[0].pos, en = tokens[$-1].endPos;
    auto ts = tsNormal;  ts.applySyntax(0);
    het.uibase.appendCode(row, sourceCode.text[st..en], sourceCode.syntax[st..en], s => ts.applySyntax(s), ts);
  }
}

}public{// UI - Code integration ///////////////////////////////////////////////////


void emitStyle(string syntax){
  applySyntax(im.style, syntax.to!SyntaxKind.to!int, defaultSyntaxPreset);
  im.bkColor = im.style.bkColor;
}

void emitStyle_fontOnly(string syntax){
  const oldBkColor = im.bkColor;
  emitStyle(syntax);
  im.bkColor = oldBkColor;
  im.style.bkColor = oldBkColor;
}


}public{// Code classes //////////////////////////////////////////////


/+

// comment
writeln("123");
if(a) b += 1; else { writeln("aaa"); }

Block(
  Comment("// comment"), "\n",
  If(Expr("a"), Statememnt("b += 1;"), Statement(writeln("aaa"))), "\n"
);

+/


enum SplitOperation { none, declarations, statements }

enum CodeFrameType { statement, groupFrame, groupInner }


/// Adds the header of a frame. Usually an expression, but can be a function header too
/*void appendInnerExpression(Row row, Token[] tokens, SourceCode sourceCode){
  auto h = new CodeExpression();
  row.append(h);
  h.appendCode(tokens, sourceCode);
  h.enableCachedDrawing = true;
}  */

/*void appendBranch(Row row, Token[] tokens, SourceCode sourceCode){ with(row){
  auto blocks = splitDeclarations(tokens);
  if(blocks.length){
    auto tsWhitespace = tsNormal;  tsWhitespace.applySyntax(0); //textStyle for whitespace

    void appendWhitespace(int p0, int p1){
      if(p0 < p1)
        sourceCode.text[p0..p1].byDchar.each!(ch => appendg(ch, tsWhitespace));
    }

    auto lastPos = blocks[0][0].pos;
    foreach(tokenBlock; blocks){
      appendWhitespace(lastPos, tokenBlock[0].pos);

      append(new CodeBlock(tokenBlock, sourceCode));

      //advance
      lastPos = tokenBlock[$-1].endPos;
    }
  }
}}*/

/// Base class for everything that is Code related.
class CodeBase : Row{
  mixin CachedMeasuring;

  this(){
    this.applyCodeContainerFlags;
  }
}

/// 'Statement' here is a thing that can't be structured more. Has a border. It can be a declaration too.
class CodeStatement : CodeBase{
  mixin CachedDrawing;

  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    margin = "1";
    border = "normal"; border.color = clCodeBorder ;
    padding = "0 2";
    this.appendCode(tokens, sourceCode);
  }
}

/// 'Expression' is an embeded thing in a frame. Can be a function header for example. Has no border.
class CodeExpression : CodeBase{
  mixin CachedDrawing;

  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    padding = "0 2";
    this.appendCode(tokens, sourceCode);
  }
}

/// 'Block' is an array of things
class CodeBlock : CodeBase {
  this(Token[] tokens, SourceCode sourceCode){
    flags.yAlign = YAlign.top;
    bkColor = clCodeBackground;

    auto blocks = splitDeclarations(tokens);
    if(blocks.length){
      auto tsWhitespace = tsNormal;  tsWhitespace.applySyntax(0); //textStyle for whitespace

      void appendWhitespace(int p0, int p1){
        if(p0 < p1)
          appendStr(sourceCode.text[p0..p1], tsWhitespace);
      }

      auto lastPos = blocks[0][0].pos;
      foreach(tokenBlock; blocks){
        appendWhitespace(lastPos, tokenBlock[0].pos);

        if(tokenBlock.length && tokenBlock[$-1].isOperator(opcurlyBracketClose)){
          append(new CodeAggregate(tokenBlock, sourceCode));
        }else{
          append(new CodeStatement(tokenBlock, sourceCode));
        }

        //advance
        lastPos = tokenBlock[$-1].endPos;
      }
    }else{
      innerWidth = 10;
      innerHeight = 10;
    }
  }
}

/// 'Aggregate' is a header plus an array of things. Example: struct{}
class CodeAggregate : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    //this is something like a module!!!
    bkColor = clGroupBackground;
    margin = "1"; border = "normal"; border.color = clGroupBorder; padding = "2";

    with(splitHeaderAndBlock(tokens)){ //this is not a module!!!
      append(new CodeExpression(header, sourceCode));

      auto ts = tsNormal;  ts.applySyntax(SyntaxKind.Keyword); ts.bkColor = bkColor;
      appendStr("\n\t", ts);

      append(new CodeBlock(block, sourceCode));
    }
  }
}

class CodeModule : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clGroupBackground;
    margin = "1"; border = "normal"; border.color = clGroupBorder; padding = "2";

    auto ts = tsNormal;  ts.applySyntax(SyntaxKind.Keyword); ts.bkColor = bkColor;
    appendStr("module\n\t", ts);

    append(new CodeBlock(tokens, sourceCode));
  }
}

}public{ // FrmMain ////////////////////////////
class FrmMain: GLWindow { mixin autoCreate;

  CodeModule codeModule;

  override void onCreate(){
  }

  void updateCodeModule(){
    if(!codeModule){
      auto fn = application.args(1);
      auto src = new SourceCode(File(fn).readText
        //.transformLeadingSpacesToTabs
        .stripAllLines  //todo: this is bogus!!! Can't handle strings and comments!!!!!!!
      );
      codeModule = new CodeModule(src.tokens, src);
    }

    static str = "abcd";

    with(im) Panel({
      flags.targetSurface = 0; //it's on the zoomable surface
      bkColor = clBlack; margin = "0"; border = "none"; padding = "0";

      actContainer.append(codeModule);
    });
  }

  override void onUpdate(){
    invalidate; //opt

    //view.navigate(!im.wantKeys, !im.wantMouse);
    view.navigate(1, 1);

    updateCodeModule;
  }

  override void onPaint(){
    dr.clear(clBlack);
    drGUI.clear;

    im.draw;

    //drawFPS(drGUI);

/*    drGUI.textOut(0,  60, "view: "~view.text);
    drGUI.textOut(0,  80, "mouse in view: "~view.mousePos.text);
    drGUI.textOut(0, 100, "viewGUI: "~viewGUI.text);
    drGUI.textOut(0, 120, "mouse in viewGUI: "~viewGUI.mousePos.text);*/

//    caption = view.text ~ view.trans(g_currentMouse) ~ viewGUI.text;
  }
}

} //region