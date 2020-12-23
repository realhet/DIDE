//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
///@release
//@debug

///@run $ c:\d\libs\het\test\syntaxTestText.d
//@run $ dide.d
///@run $ c:\D\ldc2\import\std\datetime\systime.d
///@run $ c:\D\libs\het\utils.d
///@run $ c:\D\libs\het\math.d
///@run $ c:\D\libs\het\opengl.d
///@run $ c:\D\libs\het\draw3d.d

import het, het.ui, het.tokenizer, het.keywords;

/*comment1*/@safe void testFunction()(/*comment3*/) /*comment4*/ { //comment2
  if(a) b!(c) = !(d);

  struct S { int a; };
  S s = { a:5 };
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

bool isSimpleToken(in Token t){
  with(TokenKind) final switch(t.kind){
    //these are always simple, can go into the expression string
    case identifier, keyword, special, literalInt, literalFloat: return true ;
    //these need a sub-container
    case comment, literalString, literalChar                   : return false;
    //there are a few block opening operators, but the rest are simple
    case operator: return !t.id.among(oproundBracketOpen, opsquareBracketOpen, opcurlyBracketOpen, optokenString); // !( is handled later
    //unknown is forbidden
    case unknown: assert(0, "Fatal error: unknown token not allowed here");
  }
}


/+bool previousToken_skipComments(in Token[] tokens, in sizediff_t idxIn, out sizediff_t idxOut){
  auto i = idxIn-1;
  while(i>=0){
    if(tokens[i].isComment){
      i--;
    }else{
      idxOut = i;
      return true;
    }
  }
  return false;
}

bool backTrackTemplateRoundBracketOpen(in Token[] tokens, ref sizediff_t idx){
  if(tokens[idx].isOperator(oproundBracketOpen)){
    auto idx2 = idx;
    if(previousToken_skipComments(tokens, idx, idx2) && tokens[idx2].isOperator(opnot)) {
      idx = idx2;
      return true;
    }
  }
  return false;
}+/

Token[] fetchSimpleTokens(ref Token[] tokens){
  auto idx = tokens.countUntil!(not!isSimpleToken);

  if(idx<0) idx = tokens.length; //take all if -1
  /+else backTrackTemplateRoundBracketOpen(tokens, idx); //handle template !(
    The template parameter token sequence is identifier!( not just !(. It's not reasonable to put it into a container, just handle the ( ), and put the ! in front manually. +/

  auto res = tokens[0..idx];
  tokens = tokens[idx..$];
  return res;
}

void appendCode(Row row, Token[] tokens, SourceCode sourceCode, bool setBkColor=true){
  if(setBkColor) row.bkColor = clCodeBackground;

  auto ts = tsNormal;  ts.applySyntax(0);

  void appendSimpleCode(in Token[] tokens){
    if(tokens.length){
      auto st = tokens[0].pos, en = tokens[$-1].endPos;
      het.uibase.appendCode(row, sourceCode.text[st..en], sourceCode.syntax[st..en], s => ts.applySyntax(s), ts);
    }
  }
  if(tokens.empty) return;

  size_t simpleStartPos = tokens[0].pos,
         simpleEndPos;

  while(tokens.length){
    auto simpleTokens = tokens.fetchSimpleTokens;

    /*assert*/enforce(simpleTokens.length || tokens.length, "At this point it either must have simpleTokens or complicated tokens.");

    simpleEndPos = tokens.length ? tokens.front.pos //if there is a complicated token after this, thake the first complicated token's startpos
                                 : simpleTokens.back.endPos; //last endPos of the simpleTokens.

    //emit simpleTokens as text if there's any
    if(simpleStartPos < simpleEndPos) het.uibase.appendCode(row, sourceCode.text  [simpleStartPos..simpleEndPos],
                                                                 sourceCode.syntax[simpleStartPos..simpleEndPos], s => ts.applySyntax(s), ts);

    if(tokens.length){ //fetch complicated token(s)

      auto searchUntil(int op){
        auto level = tokens[0].level;

        auto res = tokens.countUntil!(t => t.isOperator(op) && t.level==level);
        /*assert*/enforce(res>0, "Fatal error: inconsitstent brackets.");
        return res+1; //include the end bracket too
      }

      //localize the complicated token range
      size_t len, bracketStartIdx/*for template !(*/;
      bool isTemplate;
      with(TokenKind) switch(tokens[0].kind){
        case comment, literalString, literalChar : len = 1; break;
        case operator: {
          switch(tokens[0].id){
            case oproundBracketOpen:  len = searchUntil(oproundBracketClose ); break;
            case opsquareBracketOpen: len = searchUntil(opsquareBracketClose); break;
            case opcurlyBracketOpen:  len = searchUntil(opcurlyBracketClose ); break;
            default: break;
          }
        }
        default: break;
      }

      /*assert*/enforce(len>0, "Unable to fetch complicated token array");

      //actual fetch
      auto complicatedTokens = tokens[0..len];
      tokens = tokens[len..$];

      //save the start of the next simple tokens including whitespace
      simpleStartPos = complicatedTokens.back.endPos;

      //append the complicated object

      auto obj = new Row;
      obj.margin = "2";
      obj.padding = "2";
      obj.border = "1";
      obj.border.color = clFuchsia;

      //het.uibase.appendCode(obj, sourceCode.text[simpleStartPos..simpleEndPos], sourceCode.syntax[simpleStartPos..simpleEndPos], s => ts.applySyntax(s), ts);

      if(len==1){
        if(complicatedTokens[0].isComment){

        }else{ //must be a literal string or char

        }
      }else{
        //recursion
        appendCode(obj, complicatedTokens[bracketStartIdx+1..$-1], sourceCode);
      }

      row.append(obj);

    }
  }

/*  foreach(isSimple, len; tokens.map!isSimpleToken.group){
    //todo if not simple, there must be a special thing that eats up more than one tokens, so .group is not good here

    auto act = tokens.takeExactly(len);
    if(isSimple){
      appendSimpleCode(act);
    }else{
      ts.fontColor = clYellow;
      ts.bkColor = clFuchsia;
      row.appendStr("[...]", ts);
    }

    tokens.popFrontExactly(len);
  }*/
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
    gl.clearColor(clBlack);
    gl.clear(GL_COLOR_BUFFER_BIT);

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