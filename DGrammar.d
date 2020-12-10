//@exe
//@import c:\d\libs
//@ldc
//@compile -m64 -mcpu=athlon64-sse3 -mattr=+ssse3
///@release
//@debug

import het, het.ui, het.tokenizer, het.keywords, het.stream;


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

//! C stuff /////////////////////////////////////////////////////////////////////////////////////
immutable oldCStuff = q{
void GlViewer::handleDragSelectRect()
{
  //Set highlighted flags when dragging a rectangle
  if(mouseOp==moDragSelectRect) {

    V2i a = ms.act.pos, b = ms.pressed.pos;
    sort(a.x, b.x); sort(a.y, b.y);

    cam.glSetupCamera(width(), height(), sceneDepth*2/*to select distant objects too*/, true, a.x, a.y, b.x, b.y);
    M44f mVP(glst.mView*glst.mProjection);
    for(int i=0; i<prj->objs.count(); ++i) {
      Obj& obj = prj->objs[i];
      obj.highlighted = obj.frustumCheck_allPointsInside(mVP);
    }

    //finish rect dragging
    if(ms.justReleased){
      mouseOp = moNone;
      for(int i=0; i<prj->objs.count(); ++i) {
        Obj& obj = prj->objs[i];

        if(ms.act.modifiers==0) obj.selected = obj.highlighted;
        if(ms.act.modifiers==modSelectionAdd) obj.selected |= obj.highlighted;
        if(ms.act.modifiers==modSelectionToggle)  obj.selected ^= obj.highlighted;
      }
    }
  }
}

void GlViewer::handleMouseObjEditing()
{
  bool angleSnapEnabled = main->angleSnapEnabled;
  if(ms.act.modifiers & modAngleSnapDisable) angleSnapEnabled = !angleSnapEnabled;
  float angleSnap = rad(ensureRange(!angleSnapEnabled ? 0.0625f : main->angleSnap, 0.01f, 180.f));

  //Handle left click (selecting objects)
  if(ms.justPressed && ms.act.button==Qt::LeftButton){
    mouseOpMinThreshold = 1;
    pressedMousePos = mouseOnObj.point;
    if(mouseOnObj.valid()){ //click on object
      Obj& obj = prj->objs[mouseOnObj.idx];
      if(!(ms.act.modifiers&modInhibitLeftClick) || (ms.act.modifiers&modRatherNotInhibitLeftClick) || (obj.selected && ms.act.modifiers==modSelectionAdd)) {
        if(obj.selected){
        }else{
          prj->selectNone();
          obj.selected = true;  //select it
          mouseOpMinThreshold = 3;
        }

        if(in4(editMode, emMove, emRotate, emScale, emDropPlane)){
          lockedAxis = -1;
          lastInsideDragStart = true;
          old_selectionBounds = prj->selectionBounds();
          mCurrent = identityM44f();
          prj->saveObjMatrices();

          if(editMode==emMove  ) mouseOp = moMove;
          if(editMode==emRotate) mouseOp = moRotate;
          if(editMode==emScale ) mouseOp = moScale;
          if(editMode==emDropPlane){ mouseOp = moDropPlane;
            dropPlaneNormal = mouseOnObj.normal;
            dropPlanePoint = mouseOnObj.point;
            dropPlaneRollAngle = 0;
            dropPlaneModified = false;
            dropPlaneMouseAt.what = 0;
          }
        }
      }
      if(ms.act.modifiers==modSelectionAdd) { obj.selected = true; }
      if(ms.act.modifiers==modSelectionToggle) { obj.selected ^= true; }
    }else if(hoveredSelectionAxis>=0){ //mouse on axis arrow

      lockedAxis = hoveredSelectionAxis;
      old_selectionBounds = prj->selectionBounds();
      mCurrent = identityM44f();

      prj->saveObjMatrices();

      if(editMode==emMove  ) mouseOp = moMoveAxis;
      if(editMode==emRotate) mouseOp = moRotateAxis;
      if(editMode==emScale ) mouseOp = moScaleAxis;

    }else{ //drag selection rectangle
      mouseOp = moDragSelectRect;
    }
  }

  //finish mouse operations
  if(mouseOp!=moNone && !(ms.act.buttons&Qt::LeftButton)){
    QString opName = mouseOpName[mouseOp];

    if(mouseOpTransforming() && mouseOpValid()){ //transformations
      main->clearEdits();

      if(in2(mouseOp, moMove, moMoveAxis)&&(ms.act.modifiers&modClone)){
        opName = "Clone";
        prj->cloneSelectedForMove();
      }

      if(prj->selectedMatricesChanged()) fileOps->chg(opName);
    }
    if(mouseOp==moDropPlane){                   //drop plane
      if(!dropPlaneModified)
        doDropPlane(0);

      if(prj->selectedMatricesChanged()) fileOps->chg(opName);
    }

    mCurrent = identityM44f();
    mouseOp=moNone;
  }

  //check if dragging can locking on an axis
  bool insideDragStart = ms.dragMax.pos.lenManh()<=4;
  bool dragLock = !insideDragStart & lastInsideDragStart;
  lastInsideDragStart = insideDragStart;

  dragging |= !insideDragStart;
  dragging &= mouseOp!=moNone;

  //select mouse cursor
  Qt::CursorShape crsr;
  if(mouseOp>moDragSelectRect) crsr = Qt::ClosedHandCursor;
  else if(mouseOnObj.valid() || hoveredSelectionAxis>=0) crsr = editMode>emSelect ? Qt::OpenHandCursor : Qt::PointingHandCursor;
  else crsr = Qt::ArrowCursor;

  highlightAxis_prio1 = -1;

  //handle mouse operations
  switch(mouseOp){
    case moMove:{
      //intersect mouse ray with plane (plane is perpendicular to an axis and is on moveReference)

      //select a plane
      int an = main->autoDrop ? 1 //vertical axe
                              : getSmallestScreenAxe(glst.mView);

      static V3f lastMoveDelta;
      V3f moveDelta;
      bool valid = intersectPlaneLine(pressedMousePos, main->autoDrop ? sgn(cam.origin().y-pressedMousePos.y) : 0 , an, mouseNear, mouseFar, moveDelta);
      moveDelta -= pressedMousePos;

      if(valid) lastMoveDelta = moveDelta;
           else moveDelta = lastMoveDelta;

      moveDelta.coord(an) = 0; //no float errors*/

      if(ms.act.modifiers&modLockDirection) { //shift = lock direction.
        if(lockedAxis<0 && !insideDragStart) lockedAxis = moveDelta.largestAxisIdx();
        int i = lockedAxis;
        moveDelta = moveDelta * vAxis(i);
      }else{
        lockedAxis = -1;
      }

      //no mouse movement = no operation
      if(ms.drag.pos.isNull()) moveDelta = V3f(0);
      moveDelta *= mouseOpValid();
      if(ms.act.modifiers&modPreciseMove) moveDelta *= preciseModifier;

      //ui feedback
      main->setEditMove(moveDelta);

      //update scene
      setMCurrentAutoDrop(mTranslation(moveDelta));
    break;}
    case moMoveAxis:{
      M44f mAxes = selectionAxes();
      V3f center = mAxes.row(3),
          ax = mAxes.row(lockedAxis),
          a0 = center-ax*1000, a1 = center+ax*1000,
          origin = pointSegmentClosestPoint(pressedMousePos, a0, a1),
          target, dummy;

      segmentSegmentClosestPoint(a0, a1, mouseNear, mouseFar, target, dummy);

      V3f moveDelta = target-origin;

      //no mouse movement = no operation
      if(ms.drag.pos.isNull()) moveDelta = V3f(0);
      moveDelta *= mouseOpValid();
      if(ms.act.modifiers & modPreciseMove) moveDelta *= preciseModifier;

      //ui feedback
      main->setEditMove(moveDelta);

      setMCurrent(mTranslation(moveDelta));
    break;}
    case moRotate:{
      float precise = 1;  if(ms.act.modifiers & modPreciseRotate) precise = preciseModifier;

      //select rotation axis based on ms.drag
      int ax = -1;
      V2f mdrag = V2f(ms.drag.pos.x, -ms.drag.pos.y);
      V2f mdir(0);
      M44f maxes = getScreenAxes(2|4, glst.mView);
      if(!ms.drag.pos.isNull()){
        mdir = mdrag.normalized_fast();
        float maxd = -1;
        for(int i=0; i<3; ++i){
          V2f adir = maxes.col(i).xy().normalized_fast();
          float d = directionDistManh(adir, mdir);
          if(d>maxd){
            maxd = d;
            ax = i;
          }
        }
      }

      if(ax>=0 && (lockedAxis<0 || dragLock)){
        lockedAxis=ax;
      }

      //select final axis depending on roll modifier
      ax = lockedAxis;
      bool roll = (ms.act.modifiers & modRotateRoll);
      if(roll) ax = getSmallestScreenAxe(glst.mView);

      highlightAxis_prio1 = ax;//for display

      //calculate rotation angle
      float angle = 0;
      const float rotSpeed = .01f;

      if(!mdrag.isNull()){
        if(roll){
          angle = mdrag.y * rotSpeed;
          crsr = Qt::SizeVerCursor;
        }else{
          if(lockedAxis>=0) angle = vCrossZ(maxes.col(lockedAxis).xy().normalized_fast(), mdrag) * rotSpeed;
        }
      }

      if(ax<0) { ax=0; angle = 0; } //make valid axis

      angle *= precise;

      if(precise==1)
        angle = iround(angle/(angleSnap))*(angleSnap); //anglesnap

      //ui feedback
      V3f angles(0); angles.coord(ax) = angle; angles *= mouseOpValid();
      main->setEditRot(angles*V3f(1,-1,1)*180/PIf);

      //update scene
      V3f center = old_selectionBounds.center();
      setMCurrentAutoDrop(mTranslation(-center)*mRotation(vAxis(ax), angle)*mTranslation(center));
    break;}
    case moRotateAxis:{
      float precise = 1;  if(ms.act.modifiers & modPreciseRotate) precise = preciseModifier;

      M44f mAxes = selectionAxes();
      V3f center = mAxes.row(3),
          ax = mAxes.row(lockedAxis),
          a0 = center-ax*1000, a1 = center+ax*1000,
          a, b;
      //calculate rotation amount
      segmentSegmentClosestPoint(a0,a1,mouseNear,mouseFar,a,b);
      V3f v1 = a-b, v2 = mouseNear-a;
      float amount = v1.len()/v2.len();
      if(vDot(vCross(v1,ax),v2)<0) amount *= -1;
      amount *= 6*precise; //rotation speed

      if(precise==1)
        amount = iround(amount/(angleSnap))*(angleSnap); //snap

      //no mouse movement = no operation
      if(ms.drag.pos.isNull()) amount = 0;

      main->setEditRot((vAxis(lockedAxis)*deg(amount)*V3f(1,-1,1))*mouseOpValid());

      //update scene
      setMCurrentAutoDrop(mTranslation(-center)*mRotation(ax,amount)*mTranslation(center));
    break;}
    case moScale:{
      float precise = 1; if(ms.act.modifiers & modPreciseScale) precise = preciseModifier;

      M44f m=getScreenAxes(2+4, glst.mView);
      V3f center=old_selectionBounds.bottom();
      V3f v=m.transformProj(V3f(ms.drag.pos.x, -ms.drag.pos.y));

      if(dragLock) lockedAxis = v.largestAxisIdx();

      //remap to percent
      for(int i=0; i<3; ++i) v.coord(i) = ensureRange(v.coord(i)*1.0f+100, 10.0f, 1000.0f);

      if(lockedAxis<0){
        v=V3f(100,100,100);
      }else{
        if(ms.act.modifiers & modNonUniformScale){
          for(int i=0; i<3; ++i) if(i!=lockedAxis) v.coord(i) = 100;
        }else{ //uniform
          //for(int i=0; i<3; ++i) v.setCoord(i, v.coord(lockedAxis));
          v = V3f(100, 100, 100)*pow(1.004, -ms.drag.pos.y*precise); //move the mouse vertically
          crsr = Qt::SizeVerCursor;
        }
      }

      //no mouse movement = no operation
      if(ms.drag.pos.isNull() || !mouseOpValid()) v = V3f(100,100,100);

      main->setEditScale(v);

      //apply transformation
      m=identityM44f(); m.setScale(v*0.01f);
      m=mTranslation(-center)*m*mTranslation(center);

      setMCurrentAutoDrop(m);
    break;}
    case moScaleAxis:{
      float precise = 1; if(ms.act.modifiers & modPreciseScale) precise = preciseModifier;

      M44f mAxes = selectionAxes();
      V3f center = mAxes.row(3),
          ax = mAxes.row(lockedAxis),
          a0 = center-ax*1000, a1 = center+ax*1000,
          origin = pointSegmentClosestPoint(pressedMousePos, a0, a1),
          target, dummy;

      segmentSegmentClosestPoint(a0, a1, mouseNear, mouseFar, target, dummy);

      V3f moveDelta = target-origin; //eddig ua, mint moMoveAxis

      //no mouse movement = no operation
      if(ms.drag.pos.isNull()) moveDelta = V3f(0);

      float scale = precise*2/(mouseNear-center).len();

      V3f v = moveDelta*scale;
      for(int i=0; i<3; ++i) v.coord(i) = ensureRange(expf(v.coord(i)), 0.1f, 10.0f);

      if(!mouseOpValid()) v = V3f(1,1,1);

      //ui feedback
      main->setEditScale(v*100);

      //update scene
      setMCurrentAutoDrop(mTranslation(-center)*mScaling(v)*mTranslation(center));
    break;}
    case moDropPlane:{
      //update roll angle
      bool rolling = ms.act.modifiers & modDropPlaneRoll;
      if(rolling){
        crsr = Qt::SizeHorCursor;
        dropPlaneRollAngle += ms.delta.pos.x*.01f; /*rot speed*/
      }else{
        if(dragging && mouseAt.valid()) dropPlaneMouseAt = mouseAt;
        crsr = Qt::PointingHandCursor;
      }

      if(dropPlaneMouseAt.valid()||rolling){
        float ra = iround(dropPlaneRollAngle/angleSnap)*angleSnap; //snap
        if(dropPlaneMouseAt.valid()) doDropPlane(ra, &dropPlaneMouseAt.point, &dropPlaneMouseAt.normal);
                                else doDropPlane(ra);
        dropPlaneModified = true;
      }
    break;}
    default:break;
  }

  //set cursor
  setCursor(crsr);
}


void GlViewer::onMouseChanged(MouseState &ms)
{
  if(!prj) return;

  if(frmMain && frmMain->btnSys.processMouse(ms, width(), height())) { update(); return; }

  pickAtMouse();
  checkSelectionAxes();
  handleDragSelectRect();
  highlightObjUnderMouse();

  mouseWheelZoom();
  if(ms.act.buttons & (Qt::MiddleButton | Qt::RightButton)){
    if(ms.act.modifiers == modCameraPan) mousePan();
    if(ms.act.modifiers == modLookAround) mouseLookAround();
    if(ms.act.modifiers == 0) mouseRotateAroundCenter();
  }

  if((cam.origin().len())>sceneDepth)
    cam.eye.setRow(3, cam.origin()*(sceneDepth/cam.origin().len()));

  switch(drawMode()){
    case dmObj: handleMouseObjEditing(); break;
    case dmSupport: handleMouseSupportEditing(); break;
    case dmGCode: handleMouseGCodeViewing(); break;
    default: break;
  }

  update();
}


void GlViewer::setEditMode(EditMode m)
{
  if(editMode==m) return;
  editMode = m;
  if(m!=emGCode) lastNonGCodeMode = m;
  if(m<emSupport) lastObjEditMode = m;
  update();
}


void GlViewer::highlightObjUnderMouse()
{
  if(mouseOp==moNone) {
    int oi=-1, si=-1;

    if(drawMode()==dmObj){
      oi = mouseOnObj.idx;
    }else if(drawMode()==dmSupport){
      if(mouseAt.what=='o') oi = mouseAt.idx; else
      if(mouseAt.what=='s') si = mouseAt.idx;
    }
    prj->highlightObj(oi);
    prj->highlightSupportBar(si);
  }
}

};
//! Endo of C stuff ///////////////////////////////////




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

  string group;

  SyntaxGraph parent;
  SyntaxLabel nameLabel;
  string name() const { return nameLabel.name; }

  string fullName() const { return group ~ "/" ~ name; }

  bool isHovered() const{ return this is parent.hoveredDeclaration; }
  bool isSelected;

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
          if(t.source in parent.declarationByName) WARN(t.source, "already exists");
          parent.declarationByName[t.source] = this;
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

  void appendDefinition_official(string def, string group){
    //print("IMPORTING", def);

    const nextPos = subCells.length ? subCells[$-1].outerBounds.bottomLeft + vec2(0, 10) : vec2(0);

    def = def.replace("opt", "?");

    auto src = new SourceCode(def);
    auto a = new SyntaxDeclaration(this, src.tokens, src);
    a.group = group;
    a.outerPos = nextPos;
    append(a);
  }

  void importGrammar_official(string text){
    // text is copied from glang.org/grammar.
    // Sections are marked with an identifier on the start of line:                   |Modules
    // Definitions are starting with an identifier on the start of line and a colon:  |Module:
    // Rules are placed after more than 1 spaces:                                     |   ModuleDeclaration DeclDefs
    // empty lines are ignored

    static bool isSection   (string s){ return s.isIdentifier; }
    static bool isDefinition(string s){ return s.endsWith(':') && s[0..$-1].isIdentifier; }

    string actSection;
    string[] actDefinition;

    void flush(){
      if(actDefinition.length){
        enforce(actSection.length, "Undefined section");
        enforce(actDefinition.length>=2, "Invalid definition. Must be at least 2 lines");

        auto definitionStr = actDefinition.join('\n');
        //print(actSection, "/", definitionStr);
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
      alpha = 0.5;

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
      foreach(link; links) if(link.from.parent.group == link.to.group){
        const h1 = link.from.parent.isHovered, h2 = link.to.isHovered;

        color  = h1 && !h2 ? clYellow
               : h2 && !h1 ? clLime
                           : clSilver;

        lineWidth = viewScale>1 ? 1 : -1;
        line2(ArrowStyle.arrow, /*LineStyle.dash, */link.from.absOutputPos, link.to.nameLabel.absInputPos);
      }

      alpha = 1;
      foreach(decl; declarations) if(decl.isSelected) fillRect2(decl.outerBounds, clAccent, 0.25);
      foreach(decl; declarations) if(decl.isHovered ) fillRect2(decl.outerBounds, clWhite , 0.2);
    }
    dr.subDraw(dr2);
  }

}

class FrmGrammar: GLWindow { mixin autoCreate;  //FrmGrammar ////////////////////////////////////////////

  SyntaxGraph graph;

  override void onCreate(){
  }

  auto positionFile(){ return File(appPath, "DLang grammar positions.txt"); }

  void loadGraph(){
    if(graph) return;

    auto text = File(appPath, `Dlang grammar official.txt`).readText;

    //patch some bugs
    void patch(alias fun=replace)(string old, string new_){
      enforce(text.indexOf(old)>=0, "Unable to do syntax patch "~old.quoted~" -> "~new_.quoted);
      text = fun(text, old, new_);
    }

    patch("\r\nForeachTypeAttributes\r\n", "\r\nForeachTypeAttributes:\r\n"); //forgot :
    patch("\r\nParamClose\r\n", "\r\nParamClose:\r\n");                       //forgot :

    //there are 2 declarations of FunctionLiteralBody. The first one is seems outdated.
    patch("\r\nFunctionLiteralBody:\r\n    BlockStatement\r\n    FunctionContractsopt BodyStatement\r\n", "\r\n");
    enforce(text.indexOf("\r\nFunctionLiteralBody:\r\n")>=0, "FunctionLiteralBody patch failed.");

    // this part is redundant, also it has bad indentation
    patch(["AsmStatement:", "    asm FunctionAttributesopt { AsmInstructionListopt }", "",
          "    AsmInstructionList:", "        AsmInstruction ;", "        AsmInstruction ; AsmInstructionList"].join("\r\n"), "");

    //Application Binary Interface patches
    //Type -> Type_
    //Parameter -> Parameter_
    //Parameters -> Parameters_

    auto abiPos = text.indexOf("Application Binary Interface\r\n");
    enforce(abiPos>=0, "Cant fint `Application Binary Interfac` part.");
    //text = text.replaceWords(

    graph = new SyntaxGraph;
    graph.importGrammar_official(text);

    { //load associated positions
      vec2[string] tmp;
      tmp.fromJson(positionFile.readText(false));
      foreach(name, pos; tmp)
        if(auto a = name in graph.declarationByName)
          (*a).outerPos = pos;
    }
  }

  void savePositions(){
    graph.declarations.map!(d => tuple(d.name, d.outerPos)).assocArray.toJson.saveTo(positionFile);
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
      static filterStr = "";
      Row({ Text("Filter "); Edit(filterStr, { flex = 1; }); });

      //filtered data source
      auto filteredDeclarations = graph.declarations.filter!(a => a.name.isWild(filterStr~"*"));

      //scroller state
      static SyntaxDeclaration actSyntaxDeclaration; //state
      static topIndex = 0; //state
      const pageSize = 10;

      ScrollListBox!SyntaxDeclaration(actSyntaxDeclaration, filteredDeclarations, (in SyntaxDeclaration sd){ Text(sd.name); width = 260; }, pageSize, topIndex);

      Spacer;
      if(Btn("test")){
      }

    });

  }

  override void onPaint(){
    dr.clear(clBlack);  drGUI.clear;

    im.draw;

    drawFPS(drGUI);
  }

  override void onDestroy(){
    savePositions;
  }
}




