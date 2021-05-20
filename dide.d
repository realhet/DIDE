//@exe
///@release
//@debug

///@run $ c:\d\libs\het\test\syntaxTestText.d
//@run $ c:\d\projects\dide\dide.d
///@run $ c:\D\ldc2\import\std\datetime\systime.d
///@run $ c:\D\libs\het\utils.d
///@run $ c:\D\libs\het\math.d
///@run $ c:\D\libs\het\opengl.d
///@run $ c:\D\libs\het\draw3d.d
///@run $ c:\D\projects\Karc\karcSamples.d.dtest
///@run $ c:\dl\jsexample.js

import het, het.ui, het.tokenizer, het.keywords;

/*comment1*/@safe void testFunction()(/*comment3*/) /*comment4*/ { //comment2
  if(a) b!(c) = !(d);

  struct S { int a; }
  S s = { a:5 };
}

public{// Utility stuff ///////////////////////////////////////////////////////////////////

//todo: detectTabs


void applyCodeContainerFlags(Container container){
  // general flags
  with(container.flags){
    wordWrap = false;
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

Token[] fetchSimpleTokens(ref Token[] tokens){
  auto idx = tokens.countUntil!(not!isSimpleToken);

  if(idx<0) idx = tokens.length; //take all if -1

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
      size_t len;
      bool isTemplate;
      with(TokenKind) switch(tokens[0].kind){
        case comment, literalString, literalChar : len = 1; break;
        case operator: {
          switch(tokens[0].id){
            case oproundBracketOpen:  len = searchUntil(oproundBracketClose ); break;
            case opsquareBracketOpen: len = searchUntil(opsquareBracketClose); break;
            case opcurlyBracketOpen:  len = searchUntil(opcurlyBracketClose ); break;
            case optokenString:       len = searchUntil(opcurlyBracketClose ); break;
            default: break;
          }
          break;
        }
        default: break;
      }

      /*assert*/enforce(len>0, "Unable to fetch complicated token array:" ~ tokens.text);

      //actual fetch
      auto complicatedTokens = tokens[0..len];
      tokens = tokens[len..$];

      //save the start of the next simple tokens including whitespace
      simpleStartPos = complicatedTokens.back.endPos;

      //append the complicated object


      //het.uibase.appendCode(obj, sourceCode.text[simpleStartPos..simpleEndPos], sourceCode.syntax[simpleStartPos..simpleEndPos], s => ts.applySyntax(s), ts);

      if(len==1){
        if(complicatedTokens[0].isComment){
          row.append(new CodeComment(complicatedTokens[0], sourceCode));
        }else{ //must be a literal string or char
          row.append(new CodeStringLiteral(complicatedTokens[0], sourceCode));
        }
      }else{
        if(complicatedTokens[0].source=="("){ //todo: no string check -> isOperator()
          row.append(new CodeRoundBracket(complicatedTokens[1..$-1], sourceCode));
        }else if(complicatedTokens[0].source=="["){
          row.append(new CodeSquareBracket(complicatedTokens[1..$-1], sourceCode));
        }else{
          //recursion
          auto obj = new Row;
          obj.margin = "2";
          obj.padding = "2";
          obj.border = "1";
          obj.border.color = clFuchsia;

          obj.appendCode(complicatedTokens[1..$-1], sourceCode);

          row.append(obj);
        }
      }



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



/// CodeBase ////////////////////////////////

class CodeBase : Row{ /// base class for everything that is Code related.
//  mixin CachedMeasuring;

  bool editable(){ return true; }
  bool selectabe(){ return true; }

  void insetBorder(RGB color){
    border.inset = true;
    border.color = color;
    border.style = BorderStyle.normal;
    border.width = 1;
  }

  auto syntaxStyle(SyntaxKind sk = SyntaxKind.Whitespace){
    auto ts = tsNormal; //todo: unoptimal, should be cached
    ts.applySyntax(sk);
    bkColor = ts.bkColor;
    return ts;
  }

  void lightenBk(ref TextStyle ts){
    ts.bkColor = mix(ts.bkColor, ts.fontColor, .25f);
    bkColor = ts.bkColor;
  }

  auto syntaxStyle_light(SyntaxKind sk = SyntaxKind.Whitespace){
    auto ts = syntaxStyle(sk);
    lightenBk(ts);
    return ts;
  }

  this(){
    this.id = srcId!("CODE", 0)(genericId(this.identityStr)); //todo: give meaningful id's
    this.applyCodeContainerFlags;
  }
}

class CodeComposite : CodeBase{
  // This is a frame which can't be edited, but can interact with.
  // It can only be deleted as a whole.
  // Example: for loop, "string", if then else
  // Editable things are nested inside and are descendants of CodeBase

  override bool editable(){ return false; }
  override bool selectabe(){ return true; }

}

class CodeCommentInner : CodeBase{
  this(string text){
    auto ts = syntaxStyle(SyntaxKind.Comment);
    padding = "0 1";
    this.appendStr(text, ts);
  }
}

class CodeComment : CodeComposite{
  this(Token token, SourceCode sourceCode, bool hasMargin = false)
  in(token.isComment)
  {
    auto ts = syntaxStyle_light(SyntaxKind.Comment);
    insetBorder(ts.bkColor);
    padding = "0 1";

    if(hasMargin) margin = "0.5";

    flags.yAlign = YAlign.top;
    this.appendStr("//", ts);
    this.append(new CodeCommentInner(token.comment));
  }
}

class CodeStringLiteralInner : CodeBase{
  this(string text, RGB lightBkColor, string font){
    auto ts = syntaxStyle(SyntaxKind.String);
    ts.font = font;
    padding = "0";
    bkColor = mix(bkColor, lightBkColor, .5f);
    //flags.dontHideSpaces = true;
    this.appendStr(text, ts);
  }
}

char stringLiteralType(string src){
  char type;
  //extract the type of the string
       if(src.startsWith('"' )) type = '"';  //C string
  else if(src.startsWith('\'')) type = '\''; //C char
  else if(src.startsWith('`' )) type = '`';  //wysiwyg `
  else if(src.startsWith(`r"`)) type = 'r';  //wysiwyg "
  else if(src.startsWith(`q"`)) type = 'q';  //delimited string
  enforce(type != 'q', "Delimited strings not supported.");
  //todo: tokenString
  return type;
}

class CodeStringLiteral : CodeComposite{
  char type; // ' " `  char / string / wysiwygString
  char unit; // c w d

  string decodeStringLiteral(Token token){
    string s;
    auto src = token.source;

    //extract the codeUnit size
    if(src[$-1].among('c', 'w', 'd')){
      unit = src[$-1];
      src = src[0..$-1];
    }else{
      unit = 'c';
    }

    type = stringLiteralType(src);

    return type.among('\'', '"') ? src[1..$-1]
                                 : token.data.text;
  }

  this(Token token, SourceCode sourceCode, bool hasMargin = false){
    auto ts = syntaxStyle_light(SyntaxKind.String);
    insetBorder(ts.bkColor);
    if(hasMargin) margin = "1";

    string s = decodeStringLiteral(token);

    padding = unit=='c' ? "0" : "0 1 0 0";

    if(type != '`') ts.font = "Lucida Console";

    // demo strings
    string sss = " ";
    wstring sss2 = "multi
line blabla
text "w;
    dstring sss3 = `multi
line blabla
text this one is proportional
not monospaced`d;
    wstring sss4 = q{ token string }w;

    flags.yAlign = YAlign.top;
    this.appendStr(type.text ~ (type.isLetter ? `"` : ""), ts);
    this.append(new CodeStringLiteralInner(s, bkColor, ts.font));
    this.appendStr((type.isLetter ? type.text ~ `"` : type.text)~(unit=='c' ? "" : unit.text), ts);
  }

  override void rearrange(){
    super.rearrange;
    foreach(sc; subCells[$ - (unit=='c' ? 1 : 2)..$])
      sc.outerPos.y = innerSize.y - sc.outerSize.y;
  }
}

class CodeRoundBracketInner : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    this.appendCode(tokens, sourceCode);
  }
}

class CodeRoundBracket : CodeComposite{
  this(Token[] tokens, SourceCode sourceCode){
    auto ts = syntaxStyle(SyntaxKind.Symbol);

    flags.yAlign = YAlign.stretch;
    this.appendChar('(', ts);
    this.append(new CodeRoundBracketInner(tokens, sourceCode));
    this.appendChar(')', ts);
  }
}

class CodeSquareBracketInner : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    this.appendCode(tokens, sourceCode);
  }
}

class CodeSquareBracket : CodeComposite{
  this(Token[] tokens, SourceCode sourceCode){
    auto ts = syntaxStyle(SyntaxKind.Symbol);

    flags.yAlign = YAlign.stretch;
    this.appendChar('[', ts);
    this.append(new CodeSquareBracketInner(tokens, sourceCode));
    this.appendChar(']', ts);
  }
}


/// 'Statement' here is a thing that can't be structured more. Has a border. It can be a declaration too.
/*class CodeStatement : CodeBase{
  mixin CachedDrawing;

  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    margin = "0.5";
    insetBorder(clGroupBackground);
    padding = "0 2";
    this.appendCode(tokens, sourceCode);
  }
}*/

class CodeStatement : CodeComposite{
  this(Token[] tokens, SourceCode sourceCode)
  in(!tokens.empty && tokens[$-1].isOperator(opsemiColon))
  {
    bkColor = clCodeBackground;
    margin = "0.5";
    insetBorder(clGroupBackground);
    padding = "0 1";

    this.append(new CodeExpression(tokens[0..$-1], sourceCode));
    auto ts = syntaxStyle(SyntaxKind.Symbol);
    ts.bkColor = mix(ts.bkColor, clWhite, 0.15f);
    this.appendStr("; ", ts);
  }
}

/// 'Expression' is an embeded thing in a frame. Can be a function header for example. Has no border.
class CodeExpression : CodeBase{
//  mixin CachedDrawing;
  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    padding = "0 2";
    this.appendCode(tokens, sourceCode);
  }
}

/// 'Block' is an array of things
class CodeBlock : CodeBase {
  this(Token[] tokens, SourceCode sourceCode){
    padding = "0.5";
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
          if(tokenBlock.length==1 && tokenBlock[0].isComment){
            append(new CodeComment(tokenBlock[0], sourceCode, true));
          }else{
            append(new CodeStatement(tokenBlock, sourceCode));
          }
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

  Tuple!(Cell, vec2)[] hoveredStack, pressedStack, commonStack, selection;

  void updateCodeModule(){
    if(!codeModule){
      auto fn = application.args(1);
      auto src = new SourceCode(File(fn).readText
        //.transformLeadingSpacesToTabs
        .stripAllLines  //todo: this is bogus!!! Can't handle strings and comments!!!!!!!
      );
      codeModule = new CodeModule(src.tokens, src);
    }

    codeModule.flags.targetSurface = 0;
    im.root ~= codeModule;

    hoveredStack = codeModule.contains(view.mousePos);

    //don't select characters on composite containers.
    if(hoveredStack.length>=2 && cast(Glyph)hoveredStack[$-1][0]){
      auto a = hoveredStack[$-2][0];
      if(cast(CodeComposite)a !is null)
        hoveredStack.popBack;
    }

    if(inputs.LMB.pressed){ pressedStack = hoveredStack; selection = []; }
    commonStack = inputs.LMB.down ? commonPrefix(pressedStack, hoveredStack) : [];

    if(inputs.LMB.down){
      //update selection
      if(const cLen = commonStack.length){
        if(cLen == pressedStack.length){ // single element
          selection = [ commonStack.back ];
        }else if(hoveredStack.length>cLen && pressedStack.length>cLen){ // range of elements
          auto cells = commonStack.back[0].subCells;
          auto i0 = cells.countUntil(pressedStack[cLen][0]),
               i1 = cells.countUntil(hoveredStack[cLen][0]);
          if(i0>=0 && i1>=0){
            sort(i0, i1);
            auto ofs = commonStack.back[1] + commonStack.back[0].innerPos;
            selection = cells[i0..i1+1].map!(c => tuple(c, ofs)).array;
          }
        }
      }else{
        if(pressedStack.length)
          selection = [ pressedStack.back ];
      }
    }

    print("update");
    with(im) Panel(PanelPosition.topLeft, {
      //bkColor = clBlack; margin = "0"; border = "none"; padding = "0";

      if(1) Row({
        flags.yAlign = YAlign.stretch;
        margin = "2";

        void list(T)(string caption, T stack){
          Row({
            padding = "4";
            margin = "2";
            border = "1";
            Text("# \t", bold(caption ~ "\n"));
            Cell last;
            foreach(c; stack){
              auto act = c[0];
              auto idx = last ? last.subCells.countUntil!(a => a is act) : 0;
              Text(idx, " \t", typeid(act).name.withoutStarting("dide."), "\n");
              last = act;
            }
          });
        }

        list("pressed", pressedStack);
        list("hovered", hoveredStack);
        list("common" , commonStack );
      });


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
    //gl.polygonMode(GL_FRONT_AND_BACK, GL_LINE);

    //im.draw;

    //drawFPS(drGUI);

/*    drGUI.textOut(0,  60, "view: "~view.text);
    drGUI.textOut(0,  80, "mouse in view: "~view.mousePos.text);
    drGUI.textOut(0, 100, "viewGUI: "~viewGUI.text);
    drGUI.textOut(0, 120, "mouse in viewGUI: "~viewGUI.mousePos.text);*/

//    caption = view.text ~ view.trans(g_currentMouse) ~ viewGUI.text;
  }

  override void afterPaint(){
    auto dr = scoped!Drawing;
    dr.color = clAccent;
    dr.alpha = .25;
    foreach(a; selection[]) dr.fillRect((a[0].outerBounds + a[1]));
    dr.glDraw(view);
  }
}

} //region