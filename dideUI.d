module dideui;

import het, het.ui, het.tokenizer, buildsys, didemodule;

__gshared float blink;

void updateBlink(){
  blink = float(sqr(sin(blinkf(134.0f/60)*PIf)));
}

void setRoundBorder(Container cntr, float borderWidth){ with(cntr){
  border.width = borderWidth;
  border.color = bkColor;
  border.inset = true;
  border.borderFirst = true;
}}

void RoundBorder(float borderWidth){ with(im){
  border.width = borderWidth;
  border.color = bkColor;
  border.inset = true;
  border.borderFirst = true;
}}

//! UI ///////////////////////////////

static void UI_OuterBlockFrame(T = .Row)(RGB color, void delegate() contents){ with(im) //UI_OuterBlockFrame///////////////////////////
  Container!T({
    margin = "0.5";
    padding = "1.5";
    style.bkColor = bkColor = color;
    style.fontColor = blackOrWhiteFor(color);
    flags.yAlign = YAlign.top;
    RoundBorder(8);
    if(contents) contents();
  });
}

static void UI_InnerBlockFrame(T = .Row)(RGB color, RGB fontColor, void delegate() contents){ with(im) //UI_InnerBlockFrame////////////////////////
  Container!T({
    margin = "0";
    padding = "0 4";
    style.bkColor = bkColor = color;
    style.fontColor = fontColor;
    flags.yAlign = YAlign.top;
    RoundBorder(8);
    if(contents) contents();
  });
}

static void UI_BuildMessageContents(CodeLocation location, string title, void delegate() contents){ with(im){ //UI_BuildMessageContents///////////////////////////////
  location.UI;
  if(title!="") Text(bold(" "~title~" "));
  if(contents) contents();
}}

static void UI_ConsoleTextBlock(string contents){ with(im) //UI_ConsoleTextBlock/////////////////////////////////////
  UI_InnerBlockFrame(clBlack, clWhite, {
    style.font = "Lucida Console";
    Text(contents); //todo: Use codeRow here for optimized LOD. Refer to -> UI_BuildMessageTextBlock()
  });
}

static void UI_CompilerOutput(File file, string text){ //UI_CompilerOutput/////////////////////////////////
  UI_OuterBlockFrame(RGB(0xD0D0D0), {
    UI_BuildMessageContents(CodeLocation(file), "Output:", {
      UI_ConsoleTextBlock(text);
    });
  });
}

void UI(in CodeLocation cl){ with(cl) with(im) //CodeLocation.UI //////////////////////
  UI_InnerBlockFrame(clSilver, clBlack, {
    auto ext = file.ext;
    if(ext!="") Text(tag(format!`img "icon:\%s" height=%f`(ext, fh-2)));

    Text(file.fullName);
    if(column) Text(format!("(%s,%s)")(line, column));
          else if(line) Text(format!("(%s)")(line));
  });
}


void UI(in BuildSystemWorkerState bsws) { with(bsws) with(im){ //BuildSystemWorkerState.UI //////////////////////
  Row({
    width = 6*fh;
    Row({
      if(building) style.fontColor = mix(style.fontColor, style.bkColor, blink);
      Text(cancelling ? "Cancelling" : building ? "Building" : "BuildSys Ready");
    });
    Row({ flex=1; flags.hAlign = HAlign.right;
      if(building && !cancelling && totalModules)
        Text(format!"%d(%d)/%d"(compiledModules, inFlight, totalModules));
      else if(building && cancelling){
        Text(format!"\u2026%d"(inFlight));
      }
    });
  });
}}

void UI_BuildMessageTextBlock(string message, RGB clFont){ //UI_BuildMessageTextBlock//////////////////////////////
  //Apply syntax highlight on the texts between `` quotes.
  auto isCode = new bool[message.length];
  {
    bool inCode = false;
    size_t i;
    foreach(ch; message.byChar){
      if(!inCode){
        if(ch=='`') inCode=true;
      }else{
        if(ch=='`') inCode=false; else isCode[i]=true;
      }
      i++;
    }
  }

  auto codeOnly = message.dup;
  foreach(i, b; isCode) if(!b) codeOnly.ptr[i] = ' ';

  auto sc = scoped!SourceCode(cast(string)codeOnly);

  void appendLine(int idx){ with(im){
    auto cr = cast(CodeRow)actContainer;
    auto r = sc.getLineRange(idx);
    cr.set(message[r[0]..r[1]], sc.syntax[r[0]..r[1]]);
    auto g = cr.glyphs;
    foreach(i, b; isCode[r[0]..r[1]]) if(!b) g[i].fontColor = clFont;
  }}

  const lineCount = sc.lineCount;
  if(lineCount>=1){
    with(im) UI_InnerBlockFrame!CodeColumn(clCodeBackground, clFont, {
      foreach(i; 0..lineCount) Container!CodeRow({ appendLine(i); });
    });
  }
}


void UI(in BuildMessage msg, BuildResult br){ UI(msg, br.subMessagesOf(msg.location)); }

void UI(in BuildMessage msg, in BuildMessage[] subMessages){ with(msg) with(im) // BuildMessage.UI ////////////////////////////
  UI_OuterBlockFrame(type.color, {
    UI_BuildMessageContents(location, parentLocation ? "\u2026" : type.to!string.capitalize~":", {
      const clFont = avg(type.color, clWhite);

      UI_BuildMessageTextBlock(message, clFont);

      foreach(sm; subMessages){
        Text("\n    "); sm.UI([]);
      }
    });
  });
}

//! Draw //////////////////////////////////////////////////////

void drawHighlight(Drawing dr, bounds2 bnd, RGB color, float alpha){
  if(!bnd) return;
  dr.color = color;
  dr.alpha = alpha;
  dr.fillRect(bnd);
  dr.lineWidth = -1;
  dr.drawRect(bnd);
  dr.alpha = 1;
}

void drawHighlight(Drawing dr, Cell c, RGB color, float alpha){
  if(!c) return;
  drawHighlight(dr, c.outerBounds, color, alpha);
}
