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
  if(a) b;
}

public{// Utility stuff ///////////////////////////////////////////////////////////////////

//todo: detectTabs

string transformLeadingSpacesToTabs(string original, int spacesPerTab=2)
in(original != "", "This is here to test a multiline header with a contract.")
//out{ assert(1, "ouch"); }
/*do*/ {

  string process(string s){
    s = stripRight(s);
    int cnt;
    string spaces = " ".replicate(spacesPerTab);
    while(s.startsWith(spaces)){
      s = s[spaces.length..$];
      cnt++;
    }
    s = "\t".replicate(cnt) ~ s;
    return s;
  }

  return original.splitter('\n').map!(s => process(s)).join('\n'); //todo: this is bad for strings
}

string stripAllLines(string original){
  return original.splitter('\n').map!strip.join('\n');
}

auto splitDeclarations(Token[] tokens){
  Token[][] res;

  const level = tokens.baseLevel;

  while(tokens.length){

    //collect the comments first
    if(tokens[0].isComment){
      res ~= [tokens.front];
      tokens.popFront;
      continue;
    }

    //search for the end of the declaration
    auto findDeclarationEnd(){
      bool isAssignExpr;
      foreach(i, ref t; tokens){
        if(t.level == level){
          if(t.isOperator(opsemiColon)) return i;  // ';' is always an end marker
          else if(t.isOperator(opassign)) isAssignExpr = true;  // detect '=' assign expression. Possible struct initializer.
        }else if(t.level == level+1){
          if(t.isOperator(opcurlyBracketClose))
            if(!isAssignExpr) return i; // '}' means end if unless it's an assign expression.
        }
      }
      //raise("Unable to find end of declaration."); it's not an error in enum
      return tokens.length-1;
    }

    auto lastIdx = findDeclarationEnd;
    res ~= tokens[0..lastIdx+1];
    tokens = tokens[lastIdx+1..$];

    // note:
    // if the first nonComment is 'else', the it must be concatenated with the last tokens
    /*const appendToLast = getNonComment(act, 0).isKeyword(kwelse) && res.length;
    if(appendToLast) res[$-1] = res[$-1] ~ act;
                else res ~= act;*/

    //the loop failed to identify the end. But instead of throwing an error, append the last set of tokens.
  }

  return res;
}


auto splitHeaderBlock(Token[] tokens){
  const level = tokens.baseLevel;
  auto st = tokens.countUntil!(t => t.level==level+1 && t.source=="{");
  enforce(st>=0, "No {} block found");
  struct Res{ Token[] header, block; }
  return Res(tokens[0..st], tokens[st+1..$-1]);
}

}public{// Syntax highlight styles ///////////////////////////////////////////////////////

struct SyntaxStyle{
  RGB fontColor, bkColor;
  int fontFlags; //1:b, 2:i, 4:u
}

struct SyntaxStyleRow{
  string kindName;
  SyntaxStyle[] formats;
}


//todo: these should be uploaded to the gpu
//todo: from the program this is NOT extendable
immutable syntaxPresetNames =
                   ["Default"                 , "Classic"                          , "C64"                     , "Dark"                     ];
immutable SyntaxStyleRow[] syntaxTable = [
  {"Whitespace"  , [{clBlack  ,clWhite   ,0}, {clVgaYellow      ,clVgaLowBlue   ,0}, {clC64LBlue  ,clC64Blue   ,0}, {0xc7c5c5 ,0x2d2d2d ,0}]},
  {"Selected"    , [{clWhite  ,10841427  ,0}, {clVgaLowBlue     ,clVgaLightGray ,0}, {clC64Blue   ,clC64LBlue  ,0}, {clBlack  ,0xc7c5c5 ,0}]},
  {"FoundAct"    , [{0xFCFDCD ,clBlack   ,0}, {clVgaLightGray   ,clVgaBlack     ,0}, {clC64LGrey  ,clC64Black  ,0}, {clBlack  ,0xffffff ,0}]},
  {"FoundAlso"   , [{clBlack  ,0x78AAFF  ,0}, {clVgaLightGray   ,clVgaBrown     ,0}, {clC64LGrey  ,clC64DGrey  ,0}, {clBlack  ,0xa7a5a5 ,0}]},
  {"NavLink"     , [{clBlue   ,clWhite   ,4}, {clVgaHighRed     ,clVgaLowBlue   ,4}, {clC64Red    ,clC64Blue   ,0}, {0xFF8888 ,0x2d2d2d ,4}]},
  {"Number"      , [{clBlue   ,clWhite   ,0}, {clVgaYellow      ,clVgaLowBlue   ,0}, {clC64Yellow ,clC64Blue   ,0}, {0x0094FA ,0x2d2d2d ,0}]},
  {"String"      , [{clBlue   ,clSkyBlue ,0}, {clVgaHighCyan    ,clVgaLowBlue   ,0}, {clC64Cyan   ,clC64Blue   ,0}, {0x64E000 ,0x283f28 ,0}]},
  {"Keyword"     , [{clNavy   ,clWhite   ,1}, {clVgaWhite       ,clVgaLowBlue   ,1}, {clC64White  ,clC64Blue   ,0}, {0x5C00F6 ,0x2d2d2d ,1}]},
  {"Symbol"      , [{clBlack  ,clWhite   ,0}, {clVgaYellow      ,clVgaLowBlue   ,0}, {clC64Yellow ,clC64Blue   ,0}, {0x00E2E1 ,0x2d2d2d ,0}]},
  {"Comment"     , [{clNavy   ,clYellow  ,2}, {clVgaLightGray   ,clVgaLowBlue   ,2}, {clC64LGrey  ,clC64Blue   ,0}, {0xf75Dd5 ,0x442d44 ,2}]},
  {"Directive"   , [{clTeal   ,clWhite   ,0}, {clVgaHighGreen   ,clVgaLowBlue   ,0}, {clC64Green  ,clC64Blue   ,0}, {0x4Db5e6 ,0x2d4444 ,0}]},
  {"Identifier1" , [{clBlack  ,clWhite   ,0}, {clVgaYellow      ,clVgaLowBlue   ,0}, {clC64Yellow ,clC64Blue   ,0}, {0xc7c5c5 ,0x2d2d2d ,0}]},
  {"Identifier2" , [{clGreen  ,clWhite   ,0}, {clVgaHighGreen   ,clVgaLowBlue   ,0}, {clC64LGreen ,clC64Blue   ,0}, {clGreen  ,0x2d2d2d ,0}]},
  {"Identifier3" , [{clTeal   ,clWhite   ,0}, {clVgaHighCyan    ,clVgaLowBlue   ,0}, {clC64Cyan   ,clC64Blue   ,0}, {clTeal   ,0x2d2d2d ,0}]},
  {"Identifier4" , [{clPurple ,clWhite   ,0}, {clVgaHighMagenta ,clVgaLowBlue   ,0}, {clC64Purple ,clC64Blue   ,0}, {0xf040e0 ,0x2d2d2d ,0}]},
  {"Identifier5" , [{0x0040b0 ,clWhite   ,0}, {clVgaBrown       ,clVgaLowBlue   ,0}, {clC64Orange ,clC64Blue   ,0}, {0x0060f0 ,0x2d2d2d ,0}]},
  {"Identifier6" , [{0xb04000 ,clWhite   ,0}, {clVgaHighBlue    ,clVgaLowBlue   ,0}, {clC64LBlue  ,clC64Blue   ,0}, {0xf06000 ,0x2d2d2d ,0}]},
  {"Label"       , [{clBlack  ,0xDDFFEE  ,4}, {clBlack          ,clVgaHighCyan  ,0}, {clBlack     ,clC64Cyan   ,0}, {clBlack  ,0x2d2d2d ,4}]},
  {"Attribute"   , [{clPurple ,clWhite   ,1}, {clVgaHighMagenta ,clVgaLowBlue   ,1}, {clC64Purple ,clC64Blue   ,1}, {0xAAB42B ,0x2d2d2d ,1}]},
  {"BasicType"   , [{clTeal   ,clWhite   ,1}, {clVgaHighCyan    ,clVgaLowBlue   ,1}, {clC64Cyan   ,clC64Blue   ,1}, {clWhite  ,0x2d2d2d ,1}]},
  {"Error"       , [{clRed    ,clWhite   ,4}, {clVgaHighRed     ,clVgaLowBlue   ,4}, {clC64Red    ,clC64Blue   ,0}, {0x00FFEF ,0x2d2dFF ,0}]},
  {"Binary1"     , [{clWhite  ,clBlue    ,0}, {clVgaLowBlue     ,clVgaYellow    ,0}, {clC64Blue   ,clC64Yellow ,0}, {0x2d2d2d ,0x20bCFA ,0}]},
];

mixin(format!"enum SyntaxKind   {%s}"(syntaxTable.map!"a.kindName".join(',')));
mixin(format!"enum SyntaxPreset {%s}"(syntaxPresetNames.join(',')));

__gshared defaultSyntaxPreset = SyntaxPreset.Dark;


}public{// UI - Code integration ///////////////////////////////////////////////////

/// Lookup a syntax style and apply it to a TextStyle reference
void applySyntax(ref TextStyle ts, uint syntax, SyntaxPreset preset)
in(syntax<syntaxTable.length)
{
  auto fmt = &syntaxTable[syntax].formats[preset];
  ts.fontColor = fmt.fontColor;
  ts.bkColor   = fmt.bkColor;
  ts.bold      = fmt.fontFlags.getBit(0);
  ts.italic    = fmt.fontFlags.getBit(1);
  ts.underline = fmt.fontFlags.getBit(2);
}

/// Shorthand with global default preset
void applySyntax(ref TextStyle ts, uint syntax){
  applySyntax(ts, syntax, defaultSyntaxPreset);
}

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

//todo: slow, needs a color theme struct
auto syntaxFontColor(string syntax){ return syntaxTable[syntax.to!SyntaxKind.to!int].formats[defaultSyntaxPreset].fontColor; }
auto syntaxBkColor  (string syntax){ return syntaxTable[syntax.to!SyntaxKind.to!int].formats[defaultSyntaxPreset].bkColor  ; }

/*class CodeRow: Row{ //CodeRow //////////////////////////////////////
  SourceCode code;
  int lineIdx;

  this(SourceCode code, int lineIdx, ref TextStyle ts){
    super(ts); //this overwrites bkColor

    this.code = code;
    this.lineIdx = lineIdx;
    bkColor = syntaxTable[0].formats[defaultSyntaxPreset].bkColor; //this also

    flags.canWrap = false;

    auto line = code.getLine(lineIdx);
    this.appendCode(line.text, line.syntax, (s){ ts.applySyntax(s); }, ts);

    //empty row height is half
    if(subCells.empty) {
      innerHeight = ts.fontHeight*0.5;
      bkColor = mix(bkColor, bkColor.l>0x80 ? clWhite : clBlack, 0.0625f);
    }
  }
}

struct CodeMarker{
  int line, col;
} */

/// A block of codeRows or codeBlocks aligned like a Column
/*class CodeBlock : Column { //CodeBlock /////////////////////////////////////
  SourceCode code;

  Drawing cachedDrawing;

  CodeMarker[] markers;

  this(SourceCode code){
    this.code = code;
    auto ts = tsNormal;  ts.applySyntax(0);
    super(ts); //this overwrites bkColor

    auto codeRows = iota(code.lineCount).map!(i => new CodeRow(code, i, ts)).array;
    append(cast(Cell[]) codeRows);

    padding = "4";
    margin = "4";
    border = "1 normal white";
  }

  //Measure only once
  private bool measured;
  override void measure(){ if(measured.chkSet) super.measure; }

  void addMarker(in Token t){
    markers ~= CodeMarker(t.line, t.posInLine);
  }

  void addMarker(size_t i){
    if(i.inRange(code.tokens))
      addMarker(code.tokens[i]);
  }

  auto getMarkerPos(in CodeMarker m){
    vec2 res;
    if(auto codeRow = cast(CodeRow) subCells.get(m.line)){
      if(auto cell = codeRow.subCells.get(m.col)){
        res = codeRow.outerPos + cell.outerPos + cell.innerSize/2;
      }
    }
    return res;
  }

  void drawMarkers(Drawing dr){
    dr.translate(innerPos);
    dr.color = clOrange;
    dr.pointSize = -((sin(QPS.fract*PI*4)+1)^^2*5);
    dr.alpha = 1;

    foreach(ref m; markers){
      auto p = getMarkerPos(m);
      if(!isnull(p)){
        dr.point(p);
      }
    }

    dr.alpha = 1;

    dr.pop;
  }

  override void draw(Drawing dr){
    if(0){
      super.draw(dr);
    }else{ //draw only once
      if(cachedDrawing is null){
        cachedDrawing = dr.clone;
        super.draw(cachedDrawing);
      }
      dr.subDraw(cachedDrawing);
    }

    if(markers.length){
      auto dr2 = dr.clone;
      drawMarkers(dr2);
      dr.subDraw(dr2);
    }
  }
} */

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

//todo: slow, needs a color theme struct
deprecated auto clEmptyLine(){ return mix(syntaxBkColor("Whitespace"), syntaxBkColor("Whitespace").l>0x80 ? clWhite : clBlack, 0.0625f); }

auto clCodeBackground (){ return syntaxBkColor("Whitespace"); }
auto clCodeBorder     (){ return mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .4f); }
auto clGroupBackground(){ return mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .1f); }
auto clGroupBorder    (){ return mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .4f); }

enum SplitOperation { none, declarations, statements }

enum CodeFrameType { statement, groupFrame, groupInner }


void appendCode(Row row, Token[] tokens, SourceCode sourceCode){
  if(tokens.length){
    auto st = tokens[0].pos, en = tokens[$-1].endPos;
    auto ts = tsNormal;  ts.applySyntax(0);
    het.uibase.appendCode(row, sourceCode.text[st..en], sourceCode.syntax[st..en], s => ts.applySyntax(s), ts);
  }
}


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
protected:

  // cached measuring
  bool measured;
  override void measure(){ if(measured.chkSet) super.measure; }

  // cached drawing   Problem: it's not moveable.
  bool enableCachedDrawing = false;
  Drawing cachedDrawing;

  override void draw(Drawing dr){
    if(enableCachedDrawing){
      if(!cachedDrawing){
        cachedDrawing = dr.clone;
        super.draw(cachedDrawing);
      }
      dr.subDraw(cachedDrawing);
    }else{
      super.draw(dr);
    }
  }

public:

  this(){
    super(tsNormal);

    // general flags
    flags.canWrap = false;
    flags.dontHideSpaces = true;
    flags.rowElasticTabs = true;
  }
}

/// 'Statement' here is a thing that can't be structured more. Has a border. It can be a declaration too.
class CodeStatement : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    margin = "1";
    border = "normal"; border.color = clCodeBorder ;
    padding = "0 2";
    this.appendCode(tokens, sourceCode);
    enableCachedDrawing = true;
  }
}

/// 'Expression' is an embeded thing in a frame. Can be a function header for example. Has no border.
class CodeExpression : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    padding = "0 2";
    this.appendCode(tokens, sourceCode);
    enableCachedDrawing = true;
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
          sourceCode.text[p0..p1].byDchar.each!(ch => appendg(ch, tsWhitespace));
      }

      auto lastPos = blocks[0][0].pos;
      foreach(tokenBlock; blocks){
        appendWhitespace(lastPos, tokenBlock[0].pos);

        if(tokenBlock.length && tokenBlock[$-1].source=="}"){
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

    with(splitHeaderBlock(tokens)){ //this is not a module!!!
      append(new CodeExpression(header, sourceCode));

      auto ts = tsNormal;  ts.applySyntax(SyntaxKind.Keyword); ts.bkColor = bkColor;
      foreach(ch; "\n\t") appendg(ch, ts);

      append(new CodeBlock(block, sourceCode));
    }
  }
}

class CodeModule : CodeBase{
  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clGroupBackground;
    margin = "1"; border = "normal"; border.color = clGroupBorder; padding = "2";

    auto ts = tsNormal;  ts.applySyntax(SyntaxKind.Keyword); ts.bkColor = bkColor;
    foreach(ch; "module\n\t") appendg(ch, ts);

    append(new CodeBlock(tokens, sourceCode));
  }
}

/+
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
+/

/+class CodeBlock : CodeBase{

  this(Token[] tokens, SourceCode sourceCode){
    bkColor = clCodeBackground;
    margin = "2"; padding = "0";

    if(tokens.empty){
      innerHeight = NormalFontHeight;
      innerWidth  = NormalFontHeight;
    }else{
      inner.appendBranch(tokens, sourceCode);
    }
  }

  /// create
/*  this(Token[] tokens, SourceCode sourceCode){
    if(tokens.empty){
      this(CodeFrameType.groupInner);
      innerHeight = NormalFontHeight*.5f;
    }else{
      if(tokens.length && tokens[$-1].source=="}"){
        this(CodeFrameType.groupFrame);
        with(splitHeaderBlock(tokens)){

          this.appendInnerExpression(header, sourceCode);

          auto ts = tsNormal;  ts.applySyntax(SyntaxKind.Keyword); ts.bkColor = bkColor;
          foreach(ch; "\n\t") appendg(ch, ts);
          auto inner = new CodeBlock(CodeFrameType.groupInner); append(inner);
          inner.appendBranch(block, sourceCode);
        }
      }else{
        this(CodeFrameType.statement);
        this.appendCode(tokens, sourceCode);
        enableCachedDrawing = true;
      }
    }
  }*/

/*  this(string sourceText, bool isDeclaration=false){
    auto sourceCode = new SourceCode(sourceText);
    this(sourceCode.tokens, sourceCode, isDeclaration);
  }*/

} +/


/// A block of codeRows or codeBlocks aligned like a Column
/+class CodeModule : Column { //CodeModule /////////////////////////////////////
  SourceCode sourceCode;
  Drawing cachedDrawing;

  //todo: header:  for module it's the module name.

  this(string sourceText){
    this(new SourceCode(sourceText)); //todo: unoptimal
  }

  this(SourceCode sourceCode){
    this.sourceCode = sourceCode;
    auto ts = tsNormal;  ts.applySyntax(0);
    super(ts); //this overwrites bkColor

    flags.columnElasticTabs = false; // every row will have its own elastic tab processing.

    foreach(tokens; splitDeclarations(sourceCode.tokens, 0)){
      if(!tokens[$-1].isOperator(opcurlyBracketClose)){
        auto blockText = tokensToStr(tokens, sourceCode.text);
        auto codeBlock = new CodeBlock(new SourceCode(blockText));
        append(codeBlock);

//        print(tokens[0]);
        //todo: find opening bracket and get the header, parse recursively the aggregate
      }else{
        auto blockText = tokensToStr(tokens, sourceCode.text);
        auto codeBlock = new CodeBlock(new SourceCode(blockText));
        append(codeBlock);
      }
    }
  }

  //Measure only once
  private bool measured;
  override void measure(){ if(measured.chkSet) super.measure; }

  override void draw(Drawing dr){
    super.draw(dr);
  }
} +/


/// creates a code block from source text
/+auto newCodeBlock(string text){

//  foreach(batch; 0..2){ print("------------------batch #", batch);
    SourceCode sourceCode;
    CodeBlock codeBlock;

    PERF("1. processLeadingSpaces"         , { text = text.transformLeadingSpacesToTabs; });
    PERF("2. tokenize/syntaxHighlight"     , { sourceCode = new SourceCode(text); });
    PERF("3. create CodeBlock"             , { codeBlock = new CodeBlock(sourceCode); });
    PERF("4. CodeBlock.measure"            , { codeBlock.measure; }); //not needed it just mearues the time here
    PERF.report.print;
//  }

  //parseDeclarations(code);

/+  bool ignoreColon = false;
  int[] delims;
  foreach(idx, const t; code.tokens){
    void add(){ delims ~= cast(int)idx; }
    if(t.level==0 && t.source==";" || t.level==1 && t.source=="}" && code.syntax[t.pos]==8/*skSymbol*/){ add; ignoreColon = false; }
    else if(t.level==0 && t.source.among("class", "enum", "import", "interface")) ignoreColon = true;
    else if(!ignoreColon && t.level==0 && t.source==":") add;
  }                                      //todo: tenary:, struct initializer:, static if():

  foreach(i; delims){
    codeBlock.addMarker(i);
  }+/

  return codeBlock;
}+/
}public{ // FrmMain ////////////////////////////
class FrmMain: GLWindow { mixin autoCreate;

  CodeModule codeModule;

  override void onCreate(){
  }

  override void onUpdate(){
    invalidate; //opt

    //view.navigate(!im.wantKeys, !im.wantMouse);
    view.navigate(1, 1);

    if(!codeModule){
      auto fn = application.args(1);
      auto src = new SourceCode(File(fn).readText
        //.transformLeadingSpacesToTabs
        .stripAllLines
      );
      codeModule = new CodeModule(src.tokens, src);
    }

    static str = "abcd";

    with(im) Panel({
      flags.targetSurface = 0; //it's on the zoomable surface
      bkColor = clBlack;
      border = "none";
      padding = "0";
      margin = "0";

      actContainer.append(codeModule);
    });

    with(im) Panel({
      width = clientWidth;
      Row({
        Text("Hello World  ");
        Btn("Press me!"); Edit(str);
      });

      static expr = "a == 42", onTrue = "write(`hello`);\nwriteln(`one more line`);\n//many lines on a block", onFalse = "beep;";

/*      static void ui_If(string expr, string then, string else_=""){

        bool extractFirstNewLine(ref string s){
          const res = s.startsWith(newLine);
          if(res) s = s[1..$];
          return res;
        }

        const hasElse = (!else_.strip.empty); //this should be a flag!
        const nl_then = extractFirstNewLine(then );
        const nl_else = extractFirstNewLine(else_) && hasElse;
        const nl_code = (nl_then ? 2 : 0)
                      + (nl_else ? 1 : 0);

        void setupFrame(){
          flags.rowElasticTabs = true;
          margin = "2";
          border = "normal";
          padding = "2";


        }

        final switch(nl_code){
          0:{
            Row({ setupFrame;
              Text(bold("if"), "\t"); Edit(expr); Text("\t"); Edit(then); if(hasElse){ Text(bold("else")); Edit(else_); }
            });
          } break;
          1:{

          }
        }
      }        */
/+
      static GroupFrame(void delegate() content){
        Row({
          style.bkColor = mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .1f);
          bkColor = style.bkColor;
          //flags.yAlign = YAlign.top;

          flags.columnElasticTabs = false;
          flags.rowElasticTabs = true;
          margin = "2 4";
          border = "normal";
          border.color = mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .2f);
          padding = "2 0 2 4";

          content();
        });
      }

      static Edit(string expr){
        auto a = new CodeBlock(expr);
        with(a){
          margin = "2 4";
          border = "normal"; border.color = mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .2f);
          padding = "0 4";
        }
        im.actContainer.append(a);

        /*Row({
          emitStyle("Whitespace");
          Text(expr);
          margin = "2 4";
          border = "normal"; border.color = mix(syntaxBkColor("Whitespace"), syntaxFontColor("Whitespace"), .2f);
          padding = "0 4";
          bkColor = style.bkColor;
        });*/
      }

      static IfExpr(string expr, string afterIf=""){
        emitStyle_fontOnly("Keyword"); Text("if"); emitStyle_fontOnly("Symbol"); Text("(");
        Edit(expr);
        Text(")"~afterIf);
      }

      static ThenBlock(string statements){
        Edit(statements);
      }

      static ElseBlock(string statements, string afterElse=""){
        emitStyle_fontOnly("Keyword");
        Text("else"~afterElse);
        ThenBlock(statements);
      }

      static SkipElse(){ //skips the same size as the "else" text
        emitStyle_fontOnly("Keyword");
        style.fontColor = style.bkColor;
        Text("else\t");
      }

      if(0) Row({
        emitStyle("Whitespace");

        flags.rowElasticTabs = true;
        Text("\n0: One line\t");
        GroupFrame({
          IfExpr(expr); Text(" "); ThenBlock(onTrue); ElseBlock(onFalse);
        });

        Text("\n1: Two lines / 1\t");
        GroupFrame({
          IfExpr(expr, "\t"); ThenBlock(onTrue);
          Text("\n"); ElseBlock(onFalse, "\t");
        });

        Text("\n2: Two lines / 2\t");
        GroupFrame({
          IfExpr(expr, "\n");
          SkipElse; ThenBlock(onTrue); ElseBlock(onFalse);
        });

        Text("\n3: Three lines\t");
        GroupFrame({
          IfExpr(expr); Text("\n\t");
          ThenBlock(onTrue); Text("\n");
          ElseBlock(onFalse, "\t");
        });
      }); +/

    });
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