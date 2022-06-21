//@exe
///@debug
//@release

//@compile --d-version=stringId


import het, het.ui, het.uibase, het.keywords, het.tokenizer;


int DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.


// utility function ///////////////////////////////////////////////////////

void setRoundBorder(float borderWidth){ with(im){
  border.width = borderWidth;
  border.color = bkColor;
  border.inset = true;
  border.borderFirst = true;
}}


/+
auto withoutOuterComments(Token[] tokens){
  while(tokens.length && tokens[0  ].isComment) tokens = tokens[1..$];
  while(tokens.length && tokens[$-1].isComment) tokens = tokens[0..$-1];
  return tokens;
}

auto withoutOuterCommentsAndRoundBrackets(Token[] tokens){
  tokens = tokens.withoutOuterComments;
  if(tokens.length && tokens[0].among!"(" && tokens[$-1].among!")") tokens = tokens[1..$-1];
  tokens = tokens.withoutOuterComments;
  return tokens;
}

string unindent(string s){
  auto nlCnt = (cast(ubyte[])s).count!"a==10";

  if(nlCnt) return "\n".replicate(nlCnt);
       else return s;
}
+/

class CodeField: Row{ // CodeField class //////////////////////////////////////////////////

  override void draw(Drawing dr){
    if(outerSize.y < dr.invZoomFactor) return; //Simple LOD
    super.draw(dr);
  }

  static if(0) override void draw(Drawing dr){
    super.draw(dr);

    if(dr.clipBounds.valid){
      dr.color = clWhite;
      dr.fontHeight = 3;
      dr.textOut(0, 0, format!"clipBounds: %s"(dr.clipBounds));

      dr.lineWidth = 1;

      iota(0, 1, 1).each!(i => dr.drawRect(mix(outerBounds, dr.inverseInputTransform(dr.clipBounds), (QPS+i).fract)));

      dr.arrowStyle = ArrowStyle.arrow;
      //dr.line(innerSize/2, dr.inverseInputTransform(dr.clipBounds.topLeft));
      //dr.line(innerSize/2, dr.inverseInputTransform(dr.clipBounds.topRight));
      //dr.line(innerSize/2, dr.inverseInputTransform(dr.clipBounds.bottomLeft));
      //dr.line(innerSize/2, dr.inverseInputTransform(dr.clipBounds.bottomRight));
      dr.arrowStyle = ArrowStyle.none;


      /*dr.lineStyle = LineStyle.dash;
      dr.drawRect(dr.inverseInputTransform(dr.clipBounds));
      dr.lineStyle = LineStyle.normal;*/


    }

  }
}

@UI void Field(void delegate() fun){ with(im){
  Container!CodeField({
    //margin = "0 0";
    //padding = "0 0";
    flags.clipSubCells = true;
    flags.cullSubCells = true;

    flags.rowElasticTabs = true;
    flags.yAlign = YAlign.center;
    flags.dontHideSpaces = true;
    style.bkColor = bkColor = clCodeBackground;

    /*border.width = 4;
    border.color = bkColor;
    border.inset = true;
    border.borderFirst = true;*/


    fun();

    //extra padding if there is a compound inside  (0.5*2 = 1 pixel is the gap. Plain text needs no gap.)
    if(subContainers.canFind!(c => c.border.borderFirst)){ padding.top += .5f; padding.bottom += .5f; }

    //default innersize if empty
    if(subCells.empty){
      innerWidth = 0;//;DefaultFontHeight/2;
      innerHeight = DefaultFontHeight;
    }
  });
}}

/+ @UI void Code(SourceCode src, Token[] tokens){ with(im){
  if(tokens.empty) return;
  /*auto st = tokens[0].pos,
       en = tokens[$-1].endPos; //todo: what's with whitespace at the front and back?!!!
  actContainer.appendCode(src.text[st..en], src.syntax[st..en], (ubyte s){ applySyntax(style, s); },  style);*/

  for(;tokens.length; tokens.popFront){
    //note: the very first whitespace is already drawn in the outer container

    //emit token
    if(tokens[0].among!"("){
      auto idx = tokens.countUntil!(t => t.among!")"(tokens[0].level)); //todo: refactor the copypasta
      enforce(idx>0);
      Compound!1(skSymbol, "(", { Field({ Code(src, tokens[1..idx]); }); }, ")");
      tokens = tokens[idx..$];
    }else if(tokens[0].among!"["){
      auto idx = tokens.countUntil!(t => t.among!"]"(tokens[0].level));
      enforce(idx>0);
      Compound!1(skSymbol, "[", { Field({ Code(src, tokens[1..idx]); }); }, "]");
      tokens = tokens[idx..$];
    }else if(tokens[0].among!"{"){
      auto idx = tokens.countUntil!(t => t.among!"}"(tokens[0].level));
      enforce(idx>0);
      Compound!1(skSymbol, "{", { Field({ Statements(src, tokens[1..idx]); }); }, "}"); //todo: what if not statement block, but struct initializer or enum block?!!!
      tokens = tokens[idx..$];
    }else{
      //todo: strings
      with(tokens[0]) actContainer.appendCode(src.text[pos..endPos], src.syntax[pos..endPos], (ubyte s){ applySyntax(style, s); }, style);
    }

    //emit whiteSpace after token  (except the last one);
    if(tokens.length>1) with(tokens[0]) Text(skWhitespace, src.text[endPos .. endPos+postWhite].unindent);
  }

}} +/

@UI void Compound(bool lightColoring=false, Args...)(in SyntaxKind sk, in Args args){ with(im){
  Row({
    style.applySyntax(sk);
    static if(lightColoring){
      const normalBkColor = style.bkColor,
            lightBkColor = mix(normalBkColor, style.fontColor, .1f);
    }else{
      const lightBkColor  = style.fontColor;
      style.fontColor = style.bkColor;
    }

    bkColor = style.bkColor = lightBkColor;

    setRoundBorder(10);

    margin = "0.5 1";
    padding = "1 2";

    flags.rowElasticTabs = true;
    flags.yAlign = YAlign.center;
    flags.dontHideSpaces = true;

    static void emit(A)(in A a){
      alias t = typeof(a);
           static if(isSomeString!t         )   Text(a);
      else static if(__traits(compiles, a()))   a();
      else assert(0,  "Invalid Compound param: "~t.stringof);
    }

    static foreach(idx, a; args){{
     emit(a);
    }}

  });
}}


/+ @UI void Unhandled(SourceCode src, Token[] tokens){ with(im){
  if(tokens.length) Compound(skError, {
    Text("Unhandled");
    Field({
      Text(skError, src.text[tokens[0].pos .. tokens[$-1].endPos]);
      bkColor = style.bkColor;
    });
  });
}}

@UI void CodeComment(in Token t){ with(im){
  enforce(t.isComment);
  string s = t.source,
         prefix  = s[0..2],
         postfix = prefix=="//" ? "" : prefix.retro.text;
  const isDoc = s.get(2)==s[1];

  if(isDoc){ prefix = prefix ~ prefix[1]; }
  s = t.comment[isDoc?1:0..$];

  Compound(skComment,{
    Text(prefix);
    Field({
      Text(skComment, s);
      bkColor = style.bkColor;
    });
    Text(postfix);
  });
}}

+/

        /+if(header.empty){ //attribute{}
          Compound(skAttribute, {
            Field({ Code(src, attrs); });
            Text(isSingleLine ? "" : "\n     ", "{");
            Field({ margin = "4"; Declarations(src, block); });
            Text("}");
          });
        }else if(header[0].among!"class struct interface union template enum unittest" ||  //aggregate {}
                 header.length>1 && (header[0].among!"mixin" && header[1].among!"template")){
          Compound(skKeyword, {
            if(attrs.length) Field({ Code(src, attrs); });
            Text(" ", header[0].source ~ (header[0].among!"mixin" ? " template" : ""), " ");
            if(!header[0].among!"unittest") Field({ /*margin = "4";*/ Code(src, header[1..$]); });
            Text(isSingleLine ? "" : "\n     ", "{");
            Field({ margin = "4"; Declarations(src, block); });
            Text("}");
          });
        }else Unhandled;+/
        /+if(decl[0].among!"module alias enum import"){
          Compound(skIdentifier1, "", {
            if(attrs.length) Field({ Code(src, attrs); });
            Text(" "~decl[0].source~" ");
            Field({ Code(src, decl[1..$-1]); });
            Text(";");
          });
        }else Unhandled;+/


/+ @UI void Statement(SourceCode src, Token[] tokens){ Declaration(src, tokens, true); }

@UI void Declaration(SourceCode src, Token[] tokens, bool isStatement=false){ with(im){
  void Unhandled(){ .Unhandled(src, tokens); }

  if(tokens.length==1 && tokens[0].isComment){ //single token declarations
    CodeComment(tokens[0]);
  }else{ //multiple tokens
    auto attrs = tokens.getLeadingAttributesAndComments,
         decl  = tokens[attrs.length..$];

    if(decl.length){
      if(decl[$-1].among!"}" && !decl[$-1].isTokenString) with(splitHeaderAndBlock(decl)){ //block {}

        bool isDecl = header.length && header[0].among!"class struct interface union template mixin"; //todo: enum

        Compound(skWhitespace, {
          Field({ Code(src, attrs ~ header); });
          Text(isSingleLine ? "" : "\n     ", "{");
          Field({ margin = "4"; Declarations(src, block, !isDecl); });
          Text("}");
        });

      }else if(decl[$-1].among!";"){  //statement-like ;

        Compound(skWhitespace, "", {
          Field({ Code(src, attrs ~ decl[0..$-1]); });
          Text(";");
        });

      }else if(decl[$-1].among!":"){  //attribute specifier or label:

        Compound(skAttribute, "", {
          Field({ Code(src, attrs ~ decl[0..$-1]); });
          Text(":");
        });

      }else Unhandled;
    }else Unhandled;
  }
}} +/

// @UI void Statements()(SourceCode src, Token[] tokens, bool isStatements=false){ Declarations(src, tokens, true); }

/+@UI void Declarations()(SourceCode src, Token[] tokens, bool isStatements=false){ with(im){
  foreach(idx, decl; tokens.splitDeclarations(isStatements)){

    //emit beginning whiteSpace
    if(idx==0) with(decl[0]) Text(skWhitespace, src.text[pos-preWhite .. pos].unindent);

    Declaration(src, decl, isStatements);

    //emit ending whiteSpace
    with(decl[$-1]) Text(skWhitespace, src.text[endPos .. endPos+postWhite].unindent);
  }

  actContainer.removeLastNewLine;
}} +/

/+ @UI void Module(File file){ with(im){
  Compound(skKeyword, "file ", { Field({ margin = "4"; Text(skIdentifier1, file.fullName); }); },
    "\n",
    { Field({
        margin = "4";
        auto src = scoped!SourceCode(file);
        Declarations(src, src.tokens);
      });
    });
}} +/

class PlainCodeLine: Row{ // PlainCodeLine ////////////////////////////////////////////
//  ubyte[] syntax;

  auto glyphs() { return subCells.map!(c => cast(Glyph)c); } //can return nulls
  auto chars()  { return glyphs.map!"a ? a.ch : '\u26A0'"; }
  string text() { return chars.to!string; }

  int charCount(){ return cast(int)subCells.length; }

  private static bool isSpace(Glyph g){ return g && g.ch==' ' && g.syntax.among(0, 9); }
  private auto spaces() { return glyphs.map!(g => isSpace(g)); }
  private auto leadingSpaces(){ return glyphs.until!(g => !isSpace(g)); }

  this(){
    id.value = this.identityStr;

    flags.wordWrap       = false;
    flags.clipSubCells   = true;
    flags.cullSubCells   = true;
    flags.rowElasticTabs = false;
    flags.dontHideSpaces = true;
    bkColor = clCodeBackground;
    outerHeight = DefaultFontHeight;
    super();
  }

  this(string line, ubyte[] syntax){
    this();
    set(line, syntax);
  }

  static immutable float NormalSpaceWidth  = 7.25f, //same as '0'..'9' and +-_
                         LeadingSpaceWidth = NormalSpaceWidth;

  void adjustCharWidths(){

    bool isLeading = true;
    foreach(g; glyphs) if(g){
      if(isSpace(g)){
        g.outerWidth = isLeading ? LeadingSpaceWidth
                                 : NormalSpaceWidth;
      }else{
        isLeading = false;

        //non-leading char width modifications
        if(g.syntax==5 && g.ch!='.'  //number except '.'
        || g.ch.among('+', '-', '_') //symbols next to numbers
        /* || g.syntax==6/+string+/*/) g.outerWidth = NormalSpaceWidth;
      }
    }else{
      isLeading = false;
    }

    //foreach(g; glyphs) g.outerWidth = NormalSpaceWidth; //monospace everything
  }

  void set(string line, ubyte[] syntax){
    internal_setSubCells([]);

    static TextStyle style; //it is needed by appendCode/applySyntax
    this.appendCode(line, syntax, (ubyte s){ applySyntax(style, s); }, style, DefaultIndentSize);

    adjustCharWidths;
  }

  private void spaceToTab(long i){
    auto g = glyphs[i];
    assert(isSpace(glyphs[i]));
    g.ch = '\t';
    g.isTab = true;
    //note: refreshTabIdx must be called later
  }

  void replaceSpacesWithTabs(int xStart, int xTab, size_t tabCount){
    assert(xStart<=xTab                                 , "invalid xStart, xTab");
    assert(xStart>=0                                    , "xStart out of range");
    assert(xTab<subCells.length                         , "xTab out of range");
    assert(glyphs[xStart..xTab+1].all!(g => isSpace(g)) , "All must be spaces");
    assert(tabCount <= xTab-xStart+1                    , "tabCount too much.");

    auto normalizeLeadingSpaces(Cell[] sc){
      (cast(Glyph[])sc) .until!(a => !(isSpace(a) && a.outerWidth!=NormalSpaceWidth))
                        .each!(a => a.outerWidth = NormalSpaceWidth);
      return sc;
    }

    internal_setSubCells(subCells[0..xStart+tabCount] ~ (xTab+1<subCells.length ? normalizeLeadingSpaces(subCells[xTab+1..$]) : []));
    foreach(i; xStart..xStart+tabCount) spaceToTab(i); //promote spaces to tabs

    refreshTabIdx; //todo: should only be done once at the end...
  }

  void convertLeadingSpacesToTabs(int spaceCnt){
    //todo: tab inside string literal. width is too big  File(`c:\D\libs\!shit\_unused.arsd\html.d`)

    assert(spaceCnt>0);
    const tabCnt = (cast(int)leadingSpaces.walkLength)/spaceCnt;
    if(tabCnt>0){
      const removeCnt = tabCnt*spaceCnt-tabCnt;
      internal_setSubCells(subCells[removeCnt..$]);
      foreach(i; 0..tabCnt) spaceToTab(i);
      refreshTabIdx; //todo: should only be done once at the end...
    }
  }

  override void draw(Drawing dr){
    if(outerSize.y < 2*dr.invZoomFactor){
      //LOD: one straight line

      const lsCnt = glyphs.until!(g => !g || !g.ch.among(' ', '\t')).walkLength;
      if(subCells.length-lsCnt>0){
        const r = bounds2(subCells[lsCnt].outerPos, subCells[$-1].outerBottomRight) + innerPos;
        dr.color = avg(glyphs[lsCnt].bkColor, glyphs[lsCnt].fontColor);
        dr.fillRect(r.inflated(vec2(0, -r.height/4)));
      }
    }else{
      super.draw(dr);
    }
  }

}

class PlainCodeColumn: Column{ // PlainCodeColumn ////////////////////////////////////////////
  auto lines(){ return cast(PlainCodeLine[])subCells; }
  int lineCount(){ return cast(int)subCells.length; }
  @property string text() { return lines.map!"a.text".join("\r\n"); }

  this(){
    id.value = this.identityStr;

    flags.wordWrap     = false;
    flags.clipSubCells = true;
    flags.cullSubCells = true;

    flags.columnElasticTabs = true;
    bkColor = clCodeBackground;

    margin = "4";
  }

  this(File file){
    this();
    auto src = scoped!SourceCode(file);

    src.foreachLine( (int idx, string line, ubyte[] syntax) => append(new PlainCodeLine(line, syntax)) );

    makeElasticTabs;

    const spacesPerTab = src.whiteSpaceStats.detectIndentSize(DefaultIndentSize);
    lines.each!(line => line.convertLeadingSpacesToTabs(spacesPerTab));

    measure;
  }

  void makeElasticTabs(){
    //const t0=QPS; scope(exit) print(QPS-t0);

    bool detectTab(int x, int y){
      if(cast(uint)y >= lineCount) return false;
      with(lines[y]){
        if(cast(uint)x >= charCount) return false;
        return spaces[x] && (x+1 >= charCount || !spaces[x+1]);
      }
    }

    bool[long] visited;

    static struct TabInfo{ int y, xStart, xTab; }
    TabInfo[] newTabs;

    void flood(int x, int y, bool canGoUp, bool canGoDown, lazy size_t leadingSpaceCount){
      if(!canGoDown && !canGoUp) return;

      //assume: x, y is a valid tab position
      if(visited.get(x+(long(y)<<32))) return;

      int y0 = y;  if(canGoUp  ) while(y0 > 0           && detectTab(x, y0-1)) y0--;
      int y1 = y;  if(canGoDown) while(y1 < lineCount-1 && detectTab(x, y1+1)) y1++;

      int maxLen = 0, minLen = int.max;
      if(y0<y1) foreach(yy; y0..y1+1) with(lines[yy]) {
        visited[x+(long(yy)<<32)] = true;

        int x0 = x; while(x0 > 0 && spaces[x0-1]) x0--;
        int x1 = x;

        int len = x1-x0+1;
        maxLen.maximize(len);
        minLen.minimize(len);
      }

      if(maxLen>1){

        int xStartMin = 0;
        if(!canGoUp) xStartMin = leadingSpaceCount.to!int; //ez egy behuzas. Nem mehet balrabb a tab, mint a legfelso sor indent-je.
        //if(xStartMin>0) "------------------".print;

        foreach(yy; y0..y1+1) with(lines[yy]) {
          int xStart = x; while(xStart > xStartMin && spaces[xStart-1]) xStart--;
          int xTab   = x+1-minLen;

          newTabs ~= TabInfo(yy, xStart, xTab);

          //if(xStartMin>0) print(lines[yy].text, "         ", newTabs[$-1]);
        }
      }
    }

    //scan through all the rows and initiate floodFills
    foreach(y, line; lines) with(line){
      int st = 0;
      foreach(isSpace, len; spaces.group){
        const en = st + cast(int)len;

        if(isSpace && st>0){
          bool canGoUp, canGoDown;

          if(len==1 && st>0 && chars[st-1].among('[', '(')) canGoDown = true; //todo: the tabs below this one should inherit the indent of this first line
          else                                              canGoUp = canGoDown = canGoDown = len>=2;

          flood(en-1, cast(int)y, canGoUp, canGoDown, leadingSpaces.walkLength);
        }

        st = en;
      }
    }

    //replace spaces with tabs
    auto sortedTabs = newTabs.sort!((a, b) => cmpChain(cmp(a.y, b.y), cmp(b.xTab, a.xTab))<0); //x is descending!!

    int idx; foreach(const tabInfo; sortedTabs) with(lines[tabInfo.y]){

      //tabs on the previous line will split this tab if it is long enough
      auto tabsOnPrevLine = sortedTabs[0..idx] .retro
                                               .until !(t => t.y< tabInfo.y-1)
                                               .filter!(t => t.y==tabInfo.y-1);
      auto splitThisTabAt = tabsOnPrevLine.map!"a.xTab".filter!(a => a.inRange(tabInfo.xStart, tabInfo.xTab-1));
      const tabCount = 1 + splitThisTabAt.walkLength;
      //print("act", tabInfo, "splitAt", splitAt, "extra tabs", splitAt.walkLength);
      replaceSpacesWithTabs(tabInfo.xStart, tabInfo.xTab, tabCount);

      idx++;
    }

  }

}

@UI void PlainModule(File file){ with(im){
  Compound(skKeyword, "file ", { Field({ margin = "4"; Text(skIdentifier1, file.fullName); }); },
    "\n",
    {
      actContainer.append(new PlainCodeColumn(file));
    }
  );
}}


class FrmHelloGUI: GLWindow { mixin autoCreate;

  Container module1;

  Container[] modules;

  override void onCreate(){
  }

  override void onUpdate(){
    view.navigate(!im.wantKeys, !im.wantMouse);
    invalidate;

    showFPS = true;
    caption = FPS.text;

    //VSynch = FPS>=58;

    with(im){
      /+if(modul is null){
        modul = new TextModule(File(`c:\D\ldc2\import\std\datetime\systime.d`).readText/* "Hello\nWorld"*/);
        modul.flags.targetSurface = 0;
        modul.subCells.length.print;
      }

      im.root ~= modul;+/

/*      foreach(c; modul.subCells){
        if(auto co = cast(het.uibase.Container)c){
          auto hit = im.hitTest(co, true);
          if(hit.hover) print(co);
        }
      }*/

      if(modules.empty)foreach(batch; 0..2){
        int xpos;
        //File(`c:\D\projects\karc\karc2.d`)]
        modules =
`c:\D\libs\common\gcode.d
c:\D\libs\common\gcodeShader.d
c:\D\libs\dvulkan\functions.d
c:\D\libs\dvulkan\global.d
c:\D\libs\dvulkan\package.d
c:\D\libs\dvulkan\types.d
c:\D\libs\het\Algorithm.d
c:\D\libs\het\Bitmap.d
c:\D\libs\het\Color.d
c:\D\libs\het\Com.d
c:\D\libs\het\DB.d
c:\D\libs\het\DebugClient.d
c:\D\libs\het\Dialogs.d
c:\D\libs\het\Draw2D.d
c:\D\libs\het\Draw3D.d
c:\D\libs\het\FileOps.d
c:\D\libs\het\Geometry.d
c:\D\libs\het\Graph.d
c:\D\libs\het\HLDC\BuildSys.d
c:\D\libs\het\HLDC\HLDC.d
c:\D\libs\het\Http.d
c:\D\libs\het\Inputs.d
c:\D\libs\het\Keywords.d
c:\D\libs\het\LibVlc.d
c:\D\libs\het\Math.d
c:\D\libs\het\MCU.d
c:\D\libs\het\MegaTexturing.d
c:\D\libs\het\Obj.d
c:\D\libs\het\OpenCL.d
c:\D\libs\het\OpenGL.d
c:\D\libs\het\Package.d
c:\D\libs\het\Parser.d
c:\D\libs\het\Stream.d
c:\D\libs\het\Tokenizer.d
c:\D\libs\het\UI.d
c:\D\libs\het\UIBase.d
c:\D\libs\het\Utils.d
c:\D\libs\het\View.d
c:\D\libs\het\Win.d
c:\D\libs\imageformats\bmp.d
c:\D\libs\imageformats\jpeg.d
c:\D\libs\imageformats\package.d
c:\D\libs\imageformats\png.d
c:\D\libs\imageformats\tga.d
c:\D\libs\quantities\common.d
c:\D\libs\quantities\compiletime.d
c:\D\libs\quantities\internal\dimensions.d
c:\D\libs\quantities\internal\si.d
c:\D\libs\quantities\package.d
c:\D\libs\quantities\parsing.d
c:\D\libs\quantities\runtime.d
c:\D\libs\quantities\si.d
c:\D\libs\turbojpeg\turbojpeg.d
c:\D\libs\webp\decode.d
c:\D\libs\webp\encode.d
c:\D\projects\Karc\karc2.d
c:\D\projects\Karc\KarcBox.d
c:\D\projects\Karc\KarcBoxTester.d
c:\D\projects\Karc\KarcDetect.d
c:\D\projects\Karc\KarcFile.d
c:\D\projects\Karc\KarcQueue.d
c:\D\projects\Karc\KarcSample.d
c:\D\projects\Karc\KarcSensor.d
c:\D\projects\Karc\KarcSimulator.d`
.splitLines
        .map!((fn){
        //modules = [File(`c:\D\libs\het\math.d`)]/*chain(Path(`c:\d\libs\het`).files("*.d"), [File(`c:\d\projects\karc\karc2.d`), File(`c:\d\testMultilineEdit.d`)]).*/ .map!((f){
        //modules = chain(Path(`c:\d\libs\het`).files("*.d"), [File(`c:\d\projects\karc\karc2.d`), File(`c:\d\testMultilineEdit.d`)]).map!((f){
          //const t0 = QPS; scope(exit) print(QPS-t0);
          LOG(fn);
          PlainModule(File(fn));
          auto res = removeLastContainer.enforce;
          res.measure;
          res.outerPos.x = xpos;
          xpos += res.outerWidth+8;
          res.flags.targetSurface = 0;
          return res;
        }).array;
      }



      Panel(PanelPosition.topClient, {
        //bkColor = clSkyBlue;
        Text("Test MultilineEdit \U0001F512");

        //[ ] refactor CodeCompound


        Row({
          bkColor = style.bkColor = RGB(0x2d2d2d);
          padding = "8.5"; //0.5 padding is important because of the 0.5 compound margin.

          Text("\n\n");
        });

        //static string str = "";
        //Edit(str);
      });

      Panel(PanelPosition.leftClient, {
        width = 340;
        resourceMonitor.ui(innerWidth-16);


      });


      //module1.flags.targetSurface = 0;
      //root ~= module1;

      root ~= modules;
    } //im



  }

  override void onPaint(){
    gl.clearColor(RGB(0x2d2d2d)); gl.clear(GL_COLOR_BUFFER_BIT);

    if(1){
      auto dr = new Drawing; scope(exit) dr.glDraw(view);

      //draw something
      dr.textOut(0, -20, "Hello");

      view.workArea = dr.bounds;
    }
  }
}