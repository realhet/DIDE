//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
//@release
///@debug

///@run $ c:\d\libs\het\test\syntaxTestText.d
///@run $ dide.d
///@run $ c:\D\ldc2\import\std\datetime\systime.d
///@run $ c:\D\libs\het\math.d
///@run $ c:\D\libs\het\opengl.d
//@run $ c:\D\libs\het\draw3d.d



import het, het.ui, het.tokenizer, het.keywords;

// Utility stuff ///////////////////////////////////////////////////////////////////

string transformLeadingSpacesToTabs(string original, int spacesPerTab=2){

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

  return original.split('\n').map!(s => process(s)).join('\n'); //todo: this is bad for strings
}

// Syntax highlight styles ///////////////////////////////////////////////////////

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


// UI - Code integration ///////////////////////////////////////////////////

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

class CodeBlock2 : Row{
  SourceCode sourceCode;

  this(SourceCode sourceCode){
    this.sourceCode = sourceCode;
    auto ts = tsNormal;  ts.applySyntax(0);
    super(ts); //this overwrites bkColor

    padding = "4";
    margin = "4";
    border = "1 normal white";

    flags.canWrap = false;
    flags.dontHideSpaces = true;
    flags.rowElasticTabs = true;

    this.appendCode(sourceCode.text, sourceCode.syntax, s => ts.applySyntax(s), ts);

    //empty row height is half
    if(subCells.empty) {
      innerHeight = ts.fontHeight*0.5;
      bkColor = mix(bkColor, bkColor.l>0x80 ? clWhite : clBlack, 0.0625f);
    }
  }

  this(string sourceText){
    this(new SourceCode(sourceText));
  }

  private bool measured;
  override void measure(){ if(measured.chkSet) super.measure; }

  private Drawing cachedDrawing;
  override void draw(Drawing dr){
    if(!cachedDrawing){
      cachedDrawing = dr.clone;
      super.draw(cachedDrawing);
    }
    dr.subDraw(cachedDrawing);
  }

}


/// A block of codeRows or codeBlocks aligned like a Column
class CodeModule : Column { //CodeModule /////////////////////////////////////
  SourceCode sourceCode;
  Drawing cachedDrawing;

  this(SourceCode sourceCode){
    this.sourceCode = sourceCode;
    auto ts = tsNormal;  ts.applySyntax(0);
    super(ts); //this overwrites bkColor

    flags.columnElasticTabs = false; // every row will hav its own elastic tab processing.

    foreach(tokens; splitDeclarations(sourceCode.tokens, 0)){
      auto blockText = tokensToStr(tokens, sourceCode.text);
      auto codeBlock = new CodeBlock2(new SourceCode(blockText));
      append(codeBlock);
    }
  }

  //Measure only once
  private bool measured;
  override void measure(){ if(measured.chkSet) super.measure; }

  override void draw(Drawing dr){
    super.draw(dr);
  }
}


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


auto splitDeclarations(Token[] tokens, int level){
  Token[][] res;

  re: while(tokens.length){

    void append(size_t lastIdx){
      auto act = tokens[0..lastIdx+1];
      tokens = tokens[lastIdx+1..$];

      // if the first nonComment is 'else', the it must be concatenated with the last tokens
      const appendToLast = getNonComment(act, 0).isKeyword(kwelse) && res.length;
      if(appendToLast) res[$-1] = res[$-1] ~ act;
                  else res ~= act;
    }

    bool isAssignExpr;
    foreach(i, ref t; tokens){
      if(t.level == level){
        if(t.isOperator(opsemiColon)){ append(i); continue re; }  // ';' is always an end marker
        else if(t.isOperator(opassign)) isAssignExpr = true;  // detect '=' assign expression. Possible struct initializer.
      }else if(t.level == level+1){
        if(t.isOperator(opcurlyBracketClose)){ if(!isAssignExpr) { append(i); continue re; } } // '}' means end if it is not an assign expression.
      }
    }

    //the loop failed to identify the end. But instead of throwing an error, append the last set of tokens.
    res ~= tokens;
    break;
  }

  return res;
}

class FrmMain: GLWindow { mixin autoCreate; // FrmMain ////////////////////////////

  CodeModule codeModule;

  override void onCreate(){
  }

  override void onUpdate(){
    invalidate; //opt
    //view.navigate(!im.wantKeys, !im.wantMouse);
    view.navigate(1, 1);

    if(!codeModule){
      auto fn = application.args(1);
      auto src = new SourceCode(File(fn).readText.transformLeadingSpacesToTabs);
      codeModule = new CodeModule(src);
      codeModule.append(new CodeBlock2(File(`c:\dl\a.a`).readText));
    }

    with(im) Panel({
      //width = clientWidth;
      //vScroll;

      //style.applySyntax(0);
      //Row({ style.fontHeight=50; Text("FUCK"); });
      actContainer.append(codeModule);
    });
  }

  override void onPaint(){
    dr.clear(clBlack);
    drGUI.clear;
    im.draw(dr);

    drawFPS(drGUI);
  }
}

