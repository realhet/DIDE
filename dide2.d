//@exe
//@import c:\d\libs\het\hldc
//@compile --d-version=stringId,AnimatedCursors,noDebugClient

///@release
//@debug

//note: debug is not needed to get proper exception information

//todo: buildSystem: the caches (objCache, etc) has no limits. Onli a rebuild clears them.

//todo: wholeWords search (eleje/vege kulon)
//todo: filter search results per file and per syntax (comment, string, code, etc)

//todo: Adam Ruppe search tool -> http://search.dpldocs.info/?q=sleep

//todo: het.math.cmp integration with std

//todo: accept repeared keystrokes even when the FPS is low. (Ctrl+X Shift+Del Del Backspace are really slow now.)

//todo: cs Kod szerkesztonek feltetlen csinald meg, hogy kijelolt szovegreszt kulon ablakban tudj editalni tobb ilyen lehessen esetleg ha egy fuggveny felso soran vagy akkor automatikusan rakja ki a fuggveny torzset
//todo: cs lehessen splittelni: pl egyik tab full kod full scren, a masik tabon meg splittelve ket fuggveny

//todo: Ctrl+ 1..9		 Copy to clipboard[n]       Esetleg Ctrl+C+1..9
//todo: Alt + 1..9		 Paste from clipboard[n]
//todo: Ctrl+Shift 1..9   Copy to and append to clipboard[n]

//todo: unstructured syntax highlight optimization: save and reuse tokenizer internal state on each source code blocks. No need to process ALL the source when the position of the modification is known.

//todo: unstructured view: fake local syntax highlight addig, amig a bacground syntax highlighter el nem keszul.
//todo: unstructured view: immediate syntax highlight for smalles modules.

//todo: save/restore buildsystem cache on start/exit
//todo: nem letezo modul import forditasakor CRASH

//todo: Find: display a list of distinct words around the searched text. AKA Autocomplete for search.
//todo: DIDE syntax highlight vector .rgba postfixes
//todo: kinetic scroll

//todo: module hierarchy detector should run ARFTER save when pressing F9 (Not before when the contents is different in the file and in the editor)

//todo: frame time independent lerp for view.zoomAroundMouse() https://youtu.be/YJB1QnEmlTs?t=482

//todo: Search: x=12  match -> x =12,	x =  12 too. Automatic whitespaces.
//todo: Structure error visibility: In	Highighted view, mark the onclosed brackets too. Not just the wrong brackets. c:\dl\broken_structure.d
//bug: F9 -> invalid character FEFF (utf8 BOM)
//todo: isUniAlpha support	(C99 identifier char set)
//todo: MB4 MB5 should only	zoom when mouse is over the screen, not when over other windows.

//todo: markdown a commentekben.

/+todo: Nagy blokkok mellett a magas zarojelek stretchelese: 
	a) A ()[] a kozepen van megtoldva.
	b) A {} a felso es also harmadanal van megtoldva.
	c) A () a felso es also negyede kozott ciklikusan ismetelgetve van
	d) A {} a felso es also harmadanal meg is van toldva illetve a kozepe ciklikusan ismetelgetve van.
+/

//todo: implement culling for Container. Can be tested using Workspace.

@(q{DIDEREGION "Region Name" /DIDEREGION}){
	enum LogRequestPermissions = false;
}
import het, het.keywords, het.tokenizer, het.ui, het.dialogs;
import buildsys, core.thread, std.concurrency;

import dideui, didemodule;

alias blink = dideui.blink;

// ugly globals ////////////////////////////////////////

auto frmMain(){ return (cast(FrmMain)mainWindow); }
auto global_getBuildResult(){ return frmMain.buildResult; }
auto global_getMarkerLayerHideMask(){ return frmMain.workspace.markerLayerHideMask; }

// utils ////////////////////////////////////////

size_t allocatedSize(in Cell c){
	if(!c) return 0;
	import core.memory;
	size_t res = GC.sizeOf(cast(void*)c);
	if(auto co = cast(const Container)c){
		res += co.subCells.map!(allocatedSize).sum;
	}
	return res;
}

//todo: dbgsrv: Disable debugLogClient in DIDE2
//todo: dbgsrv: Use a trick (command line) to specify the client should have to connect somewhere

struct ContainerSelectionManager(T : Container){ // ContainerSelectionManager ///////////////////////////////////////////////
	//this uses Containers. flags.selected, flags.oldSelected

	bounds2 getBounds(T item){ return item.outerBounds; }

	enum MouseOp { idle, moveStart, move, rectSelect }

	MouseOp mouseOp;

	enum SelectOp { none, add, sub, toggle, clearAdd }
	SelectOp selectOp;

	vec2 dragSource;
	bounds2 dragBounds;

	bounds2 selectionBounds(){
		if(mouseOp == MouseOp.rectSelect) return dragBounds;
																 else return bounds2.init;
	}

	//these are calculated after update. No notifications, just keep calling update frequently
	T hoveredItem;

	///must be called after an items removed
	void validateItemReferences(T[] items){
		if(!items.canFind(hoveredItem)) //opt: slow linear search
			hoveredItem = null;
		//todo: maybe use a hovered containerflag.
	}

	private static void select(alias op)(T[] items, T selectItem=null){
		foreach(a; items)
			a.flags.selected = a.flags.selected.unaryFun!op;
			if(selectItem) select!"true"([selectItem]);
	}

	private float mouseTravelDistance = 0;
	private vec2 accumulatedMoveStartDelta, mouseLast;

	void update(
		bool 	mouseEnabled, 
		View2D 	view, 
		T[] 	items, 
		bool 	anyTextSelected, 
		void delegate() 	onResetTextSelection
	){
		//detect mouse travel
		if(inputs.LMB.down){
			mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta);
		}else{
			mouseTravelDistance = 0;
		}

		void selectNone()	    { select!"false"(items); }
		void selectOnly(T item)	    { select!"false"(items, item); }
		void saveOldSelected()	    { foreach(a; items) a.flags.oldSelected = a.flags.selected; }

		auto mouseAct = view.mousePos;//view.invTrans(frmMain.mouse.act.screen.vec2, false/+non animated!!!+/); //note: non animeted view for mouse is better.
		auto mouseDelta = mouseAct-mouseLast;
		mouseLast = mouseAct;

		const LMB	= inputs.LMB.down,
					LMB_pressed	= inputs.LMB.pressed,
					LMB_released	= inputs.LMB.released,
					Shift	= inputs.Shift.down,
					Ctrl	= inputs.Ctrl.down;

		const modNone	 = !Shift && !Ctrl,
					modShift	 =  Shift && !Ctrl,
					modCtrl	 = !Shift &&	 Ctrl,
					modShiftCtrl	 =  Shift &&	 Ctrl;

		const inputChanged = mouseDelta || inputs.LMB.changed || inputs.Shift.changed || inputs.Ctrl.changed;

		// update current selection mode
		if(modNone	) selectOp = SelectOp.clearAdd;
		if(modShift	) selectOp = SelectOp.add;
		if(modCtrl	) selectOp = SelectOp.sub;
		if(modShiftCtrl	) selectOp = SelectOp.toggle;

		// update dragBounds
		if(LMB_pressed) dragSource = mouseAct;
		if(LMB        ) dragBounds = bounds2(dragSource, mouseAct).sorted;

		//update hovered item
		hoveredItem = null;
		if(mouseEnabled) foreach(item; items) if(getBounds(item).contains!"[)"(mouseAct)) hoveredItem = item;

		if(LMB_pressed && mouseEnabled){ // Left Mouse pressed //
			if(hoveredItem){
				if(!anyTextSelected){
					if(modNone){ if(!hoveredItem.flags.selected) selectOnly(hoveredItem);  accumulatedMoveStartDelta = 0; mouseOp = MouseOp.moveStart; }
					if(modShift || modCtrl || modShiftCtrl) hoveredItem.flags.selected = !hoveredItem.flags.selected;
				}else{
					//any mouse operation goes to text selection
				}
			}else{
				mouseOp = MouseOp.rectSelect;
				saveOldSelected;
			}
		}

		{// update ongoing things //
			if(mouseOp == MouseOp.rectSelect && inputChanged){
				foreach(a; items) if(dragBounds.contains!"[]"(getBounds(a))){
					final switch(selectOp){
						case SelectOp.add, SelectOp.clearAdd	: a.flags.selected = true ;	         break;
						case SelectOp.sub	: a.flags.selected = false;	         break;
						case SelectOp.toggle	: a.flags.selected = !a.flags.oldSelected; break;
						case SelectOp.none	:                                break;
					}
				}else{
					a.flags.selected = (selectOp == SelectOp.clearAdd) ? false : a.flags.selected;
				}
			}
		}

		if(mouseOp == MouseOp.moveStart && mouseTravelDistance>4){
			mouseOp = MouseOp.move;
		}

		if(mouseOp == MouseOp.moveStart && mouseDelta) accumulatedMoveStartDelta += mouseDelta;

		if(mouseOp == MouseOp.move && mouseDelta){
			foreach(a; items) if(a.flags.selected){
				a.outerPos += mouseDelta + accumulatedMoveStartDelta;

				accumulatedMoveStartDelta = 0;

				//todo: jelezni kell valahogy az elmozdulast!!!
				version(/+$DIDE_REGION+/none)
				{
					//this is a good example of a disabled DIDE region
					static if(is(a.cachedDrawing))
						a.cachedDrawing.free;
				}
			}
		}


		if(LMB_released){ // left mouse released //
			if(mouseOp == MouseOp.rectSelect){
				onResetTextSelection();
			}
			//...                                               ou

			mouseOp = MouseOp.idle;
			accumulatedMoveStartDelta = 0;
		}
	}

}


// TextSelectionManager /////////////////////////////////////////
struct TextSelectionManager
{
	version(/+$DIDE_REGION declarations+/all)
	{
		struct SELECTIONS;
		@SELECTIONS
		{
			//note: these cursors MUST BE validated!!!!!
			TextCursor	cursorAtMouse, cursorToExtend;
			TextSelection	selectionAtMouse;
			TextSelection[] 	selectionsWhenMouseWasPressed;
		}
	
		bool 	mouseScrolling,
			wordSelecting,
			cursorToExtend_primary;
			
		Nullable!vec2 	scrollInRequest;
		
		version(/+$DIDE_REGION validation of textSelections+/all)
		{
			bool mustValidateInternalSelections;
			
			
			public void invalidateInternalSelections()
			{
				mustValidateInternalSelections = true;
			}
			
			void validateInternalSelections(Workspace workspace)
			{
				if(mustValidateInternalSelections.chkClear)
				{
					//validate all the cursors market with @SELECTIONS UDA
					static foreach(f; FieldNamesWithUDA!(typeof(this), SELECTIONS, false))
						mixin(format!"%s = workspace.validate(%s);"(f, f));
					PING2;
				}
			}
		}
		
		version(/+$DIDE_REGION preprocess mouse input+/all) 
		private
		{
			bool 	opSelectColumn,
				opSelectColumnAdd,
				opSelectAdd,
				opSelectExtend;
			
			DateTime	lastMainMousePressTime;
			ClickDetector 	cdMainMouseButton;
			float	mouseTravelDistance = 0;
			bool	doubleClick;
			
			void updateInputs(in Workspace.MouseMappings mouseMappings)
			{
				//detectMouseTravel
				if(inputs[mouseMappings.main].down)
				{//todo: copy/paste
					mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta);
				}
				else
				{
					mouseTravelDistance = 0;
				}
				
				cdMainMouseButton.update(inputs[mouseMappings.main].down);
				doubleClick = cdMainMouseButton.doubleClicked;
				
				//check if a keycombo modifier with the main mouse button isactive
				bool _kc(string sh){ return KeyCombo([sh, mouseMappings.main].join("+")).active; }
				opSelectColumn	= _kc(mouseMappings.selectColumn	);
				opSelectColumnAdd	= _kc(mouseMappings.selectColumnAdd	);
				opSelectAdd	= _kc(mouseMappings.selectAdd	);
				opSelectExtend	= _kc(mouseMappings.selectExtend	);
				
			}
		}
	}   version(/+$DIDE_REGION+/all)
	{
		void update(
			View2D 	view	, //input: mouse position,  output: zoom/scroll.
			Workspace 	workspace	, //used to access and modify textSelection, create tectCursor at mouse.
			in Workspace.MouseMappings 	mouseMappings	, //mouse buttons, shift modifier settings.
		)
		{
			//todo: make textSelection functional, not a ref
			//opt: only call this when the workspace changed (remove module, cut, paste)
			
			validateInternalSelections(workspace);
			cursorAtMouse = workspace.createCursorAt(view.mousePos);
			
			updateInputs(mouseMappings);
			scrollInRequest.nullify;
			if(doubleClick) wordSelecting = true;
			
			version(/+$DIDE_REGION+/all)
			{
				void initiateMouseOperations()
				{
					if(auto dw = inputs[mouseMappings.zoom].delta) view.zoomAroundMouse(dw*workspace.wheelSpeed);
					if(inputs[mouseMappings.zoomInHold	].down) view.zoomAroundMouse(.125);
					if(inputs[mouseMappings.zoomOutHold	].down) view.zoom/+AroundMouse+/(-.125);
					
					if(inputs[mouseMappings.scroll].pressed) mouseScrolling = true;
					
					if(inputs[mouseMappings.main].pressed)
					{
						if(workspace.textSelectionsGet.hitTest(view.mousePos))
						{
							//todo: start dragging the selection contents and paste on mouse button release
						}
						else if(cursorAtMouse.valid)
						{
							//start selecting with mouse
							selectionsWhenMouseWasPressed = workspace.textSelectionsGet.dup;
							
							if(workspace.textSelectionsGet.empty)
							{
								if(doubleClick)
								{
									selectionAtMouse = TextSelection(cursorAtMouse, false);
									wordSelecting = false;
								}else{
									//single click goes to module selection
								}
							}
							else
							{
								//extension cursor is the nearest selection.cursors[0]
								if(!doubleClick)
								{
									auto selectionToExtend = 	selectionsWhenMouseWasPressed
										.filter!(a => a.codeColumn is cursorAtMouse.codeColumn)
										.minElement!(a => distance(a, cursorAtMouse))(TextSelection.init);
									
									cursorToExtend = selectionToExtend.cursors[0];
									cursorToExtend_primary = selectionToExtend.primary;
								}
								
								if(!cursorToExtend.valid)
								{
									cursorToExtend = cursorAtMouse; //defaults extension pos is mouse press pos.
									cursorToExtend_primary = false;
								}
								
								selectionAtMouse = TextSelection(cursorAtMouse, false);
							}
						}
					}
				}
				
				void updateMouseScrolling() //(middle button panning)
				{
					if(mouseScrolling)
					{
						if(!inputs[mouseMappings.scroll])
							mouseScrolling = false;
						else if(const delta = inputs.mouseDelta)
							view.scroll(delta);
					}
				}
				
				void restrictDraggedMousePos()
				{
					//restrict dragged mousePos to the bounds of the current codeColumn
					if(selectionAtMouse.valid && frmMain.isForeground && inputs[mouseMappings.main])
					{
						auto bnd = worldInnerBounds(selectionAtMouse.codeColumn);
						bnd.high -= 1; //make sure it's inside
						
						const restrictedMousePos = opSelectColumn || opSelectColumnAdd 	? restrictPos_normal(view.mousePos, bnd) //normal clamping for columnSelect
							: restrictPos_editor(view.mousePos, bnd) /+text editor clamping for normal select+/ ;
						
						auto restrictedCursorAtMouse = workspace.createCursorAt(restrictedMousePos);
						
						if(restrictedCursorAtMouse.valid && restrictedCursorAtMouse.codeColumn==selectionAtMouse.codeColumn)
							selectionAtMouse.cursors[1] = restrictedCursorAtMouse;
						
						if(mouseTravelDistance>4)
							scrollInRequest = restrictPos_normal(view.mousePos, bnd); //always normal clipping for mouse focus point
						//todo: only scroll to the mouse when the mouse was dragged for a minimal distance. For a single click, the screen shoud stay where it was.
						//todo: do this scrolling in the ModuleSelectionManager too.
					}
				}
				
				void handleReleasedSelectionButton()
				{
					//resets mouse selection when the button is released
					if(selectionAtMouse.valid && !inputs[mouseMappings.main])
					{
						selectionAtMouse = TextSelection.init;
						selectionsWhenMouseWasPressed = [];
						wordSelecting = false;
					}
				}
			}   version(/+$DIDE_REGION+/all)
			{	
				void combineFinalSelection()
				{
					//combine previous selection with the current mouse selection
					
					if(!selectionAtMouse.valid) return; //nothing to do with an empty selection
					
					//todo: for additive operations, only the selections on the most recent
					
					auto applyWordSelect(TextSelection s){ return wordSelecting ? s.extendToWordsOrSpaces : s; }
					auto applyWordSelectArr(TextSelection[] s){ return wordSelecting ? s.map!(a => a.extendToWordsOrSpaces).array : s; }
					
					TextSelection[] ts; //the new text selection
					
					if(opSelectColumn || opSelectColumnAdd)
					{
						auto getPrimaryCursor()
						{
							auto a = selectionsWhenMouseWasPressed.filter!"a.primary";
							if(!a.empty) return a.front.cursors[0];
							return cursorToExtend;
						}
						
						//Column select
						auto 	c0	= opSelectColumnAdd 	? selectionAtMouse.cursors[0] 
									: getPrimaryCursor,  //bug: what if primary cursor is on another module
							c1	= selectionAtMouse.cursors[1];
							
						const 	downward 	= c0.pos.y<c1.pos.y,
							dir	= downward ? 1 : -1,
							count	= abs(c0.pos.y-c1.pos.y)+1;
						
						auto 	a0 = iota(count).map!((i){ auto res = c0; c0.move(ivec2(0,  dir)); return res; }).array,
							a1 = iota(count).map!((i){ auto res = c1; c1.move(ivec2(0, -dir)); return res; }).array;
						
						if(downward) a1 = a1.retro.array; else a0 = a0.retro.array;
						
						ts = iota(count).map!(i => TextSelection(a0[i], a1[i], false)).array;
						assert(ts.isSorted);
						
						if(opSelectColumn)
						{
							//the first selection created is at the mosue, it must be the primary
							(downward ? ts.front : ts.back).primary = true; 
						}
						
						//if there are any nonZeroLength selections, remove all zeroLength carets
						if(ts.any!"!a.isZeroLength")
							ts = ts.remove!"a.isZeroLength";
						
						//if all are carets, remove those at line ends
						if(ts.all!"a.isZeroLength" && !ts.all!"a.isAtLineStart" && !ts.all!"a.isAtLineEnd")
							ts = ts.remove!"a.isAtLineEnd";
						
						ts = applyWordSelectArr(ts);
						
						if(opSelectColumnAdd) //Ctrl+Alt+Shift = add column selection
							ts = merge(selectionsWhenMouseWasPressed ~ ts);
					
					}
					else if(opSelectAdd || opSelectExtend)
					{
						auto actSelection = applyWordSelect(
							opSelectAdd 	? selectionAtMouse
								: TextSelection(cursorToExtend, selectionAtMouse.caret, cursorToExtend_primary)
								//bug: what if primary cursor to extend is on another module
						);
						//remove touched existing selections first.
						auto baseSelections = selectionsWhenMouseWasPressed.remove!(a => touches(a, actSelection));
						ts = merge(baseSelections ~ actSelection);
					}
					else
					{
						auto s = applyWordSelect(selectionAtMouse);
						ts = [s];
					}
					
					//todo: some selection operations may need 'overlaps' instead of 'touches'. Overlap only touch when on operand is a zeroLength selection.
					//automatically mark primary for single selections
					if(ts.length==1)
						ts[0].primary = true;
					
					workspace.textSelectionsSet = ts;
				}
			}
			
			//selection bussiness logic
			if(!im.wantMouse && frmMain.isForeground && view.isMouseInside) initiateMouseOperations;
			updateMouseScrolling;
			restrictDraggedMousePos;
			handleReleasedSelectionButton;
			combineFinalSelection;
			
		}
	}
}


// SyntaxHighlightWorker ////////////////////////////////////////////

enum DisableSyntaxHighlightWorkerJob = true;

class SyntaxHighlightWorker{

	static struct Job{
		DateTime changeId; //must be a globally unique id, also sorted by chronology
		string resourceId; //only one object allowed with the same referenceId
		string sourceText;

		static if(!DisableSyntaxHighlightWorkerJob) SourceCode sourceCode; //result

		bool valid() const{ return !changeId.isNull; }
		bool opCast(b:bool)() const{ return valid; }
	}

	private int destroyLevel;
	private Job[] inputQueue, outputQueue;

	void addJob(DateTime changeId, string resourceId, string sourceText){
		synchronized(this)
			inputQueue = inputQueue.remove!(j => j.resourceId==resourceId) ~ Job(changeId, resourceId, sourceText);
	}

	Job getResult(){
		Job res;
		synchronized(this)
			if(outputQueue.length)
				res = outputQueue.fetchFront;
		return res;
	}

	private Job _workerGetJob(){
		Job res;
		synchronized(this)
			if(inputQueue.length)
				res = inputQueue.fetchBack;
		return res;
	}

	private void _workerCompleteJob(Job job){
		synchronized(this)
			outputQueue ~= job;
	}

	static private void worker(shared SyntaxHighlightWorker shw_){
		auto shw = cast()shw_;
		while(shw.destroyLevel==0){
			if(auto job = shw._workerGetJob){
				//LOG("Working on Job: " ~ job.changeId.text ~ " " ~job.resourceId);
				static if(!DisableSyntaxHighlightWorkerJob) job.sourceCode = new SourceCode(job.sourceText);
				//LOG("parsed");
				shw._workerCompleteJob(job);
			}else{
				//LOG("Worker Idling");
				sleep(10);
			}
		}
		shw.destroyLevel = 2;
		//LOG("Worker finished");
	}

	this(){
		spawn(&worker, cast(shared)this);
	}

	~this(){
		destroyLevel = 1;
		while(destroyLevel==1){
			//LOG("Waiting for worker thread to finish");
			sleep(10); //todo: it's slow... rewrite to message based
		}
	}
}


/// Workspace ///////////////////////////////////////////////
class Workspace : Container, WorkspaceInterface { //this is a collection of opened modules
	enum CodeLocationPrefix = "CodeLocation:",
			 MatchPrefix = "Match:";

	File file; //the file of the workspace
	enum defaultExt = ".dide";

	File[] openQueue;
	Module[] modules;

	@STORED File mainModuleFile;
	@property{
		Module mainModule(){ return findModule(mainModuleFile); }
		void mainModule(Module m){ enforce(modules.canFind(m), "Invalid module."); enforce(m.isMain, "This module can't be selected as main module."); mainModuleFile = m.file; }
	}

	ContainerSelectionManager!Module moduleSelectionManager;
	TextSelectionManager textSelectionManager;

	protected TextSelection[] textSelections_internal;
	bool mustValidateTextSelections;
	@property{
		auto textSelectionsGet(){ validateTextSelectionsIfNeeded; return textSelections_internal; }
		void textSelectionsSet()(TextSelection[] ts){ textSelections_internal = ts; invalidateTextSelections; }
	}

	size_t textSelectionsHash;

	bool searchBoxVisible, searchBoxActivate_request;
	string searchText;

	struct MarkerLayer{
		const BuildMessageType type;
		Container.SearchResult[] searchResults;
		bool visible = true;
	}

	auto markerLayers = (() =>  [EnumMembers!BuildMessageType].map!MarkerLayer.array  )();
	//note:	compiler drops weird error. this also works:
	//	Writing Explicit type also works:  auto markerLayers = (() =>  [EnumMembers!BuildMessageType].map!((BuildMessageType t) => MarkerLayer(t)).array  )();

	@STORED vec2[size_t] lastModulePositions;


	//Restrict convertBuildResultToSearchResults calls.
	size_t lastBuildStateHash;
	bool buildStateChanged;

	FileDialog fileDialog;

	Nullable!bounds2 scrollInBoundsRequest;

	struct ResyntaxEntry{ CodeColumn what; DateTime when; }
	ResyntaxEntry[] resyntaxQueue;

	SyntaxHighlightWorker syntaxHighlightWorker;
	
	StructureMap structureMap;
	
	this(){
		flags.targetSurface = 0;
		flags.noBackground = true;
		fileDialog = new FileDialog(mainWindow.hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)");
		syntaxHighlightWorker = new SyntaxHighlightWorker;
		structureMap = new StructureMap;
		needMeasure;
	}

	~this(){
		syntaxHighlightWorker.destroy;
	}

	override @property bool isReadOnly(){
		//return frmMain.building;
		return false;
		//note: it's making me angly if I can't modify while it's compiling.
		//bug: deleting from a readonly module loses its selections.
	}

	override void rearrange(){
		super.rearrange;
		static if(rearrangeLOG) LOG("rearranging", this);
	}

	@STORED @property{ //note: toJson: this can't be protected. But an array can (mixin() vs. __traits(member, ...).
		size_t markerLayerHideMask() const { size_t res; foreach(idx, const layer; markerLayers) if(!layer.visible) res |= 1 << idx; return res; }
		void markerLayerHideMask(size_t v) { foreach(idx, ref layer; markerLayers) layer.visible = ((1<<idx)&v)==0; }
	}

	@STORED bool showErrorList;

	protected{//ModuleSettings is a temporal storage for saving and loading the workspace.

		struct ModuleSettings{ string fileName; vec2 pos; }
		@STORED ModuleSettings[] moduleSettings;

		void toModuleSettings(){
			moduleSettings = modules.map!(m => ModuleSettings(m.file.fullName, m.outerPos)).array;
		}

		void fromModuleSettings(){
			clear;

			foreach(ms; moduleSettings){
				try{
					loadModule(File(ms.fileName), ms.pos);
				}catch(Exception e){
					WARN(e.simpleMsg);
				}
			}

			updateSubCells;
		}

		void updateSubCells(){
			invalidateTextSelections;
			moduleSelectionManager.validateItemReferences(modules);
			subCells = cast(Cell[])modules;
		}
	}

	void clear(){
		modules = [];
		textSelectionsSet = [];
		updateSubCells;
	}

	void loadWorkspace(string jsonData){
		auto fuck = this; fuck.fromJson(jsonData);
		fromModuleSettings;
	}

	string saveWorkspace(){
		toModuleSettings;
		return this.toJson;
	}

	void loadWorkspace(File f){
		loadWorkspace(f.readText(true));
	}

	void saveWorkspace(File f){
		f.write(saveWorkspace);
	}

	Module findModule(File file){
		foreach(m; modules)
			if(sameText(m.file.fullName, file.fullName))
				return m;

		//opt: hash table with fileName.lc...

		return null;
	}

	void closeModule(File file){
		//todo: ask user to save if needed
		if(!file) return;
		const idx = modules.map!(m => m.file).countUntil(file);
		if(idx<0) return;
		modules = modules.remove(idx);
		updateSubCells;
	}

	auto selectedModules()	      {	return modules.filter!(m => m.flags.selected).array; }
	auto unselectedModules()		{ return modules.filter!(m => !m.flags.selected).array; }
	auto hoveredModule()	      { return moduleSelectionManager.hoveredItem; }
	auto modulesWithTextSelection()	      { return textSelectionsGet.map!(s => s.moduleOf).nonNulls.uniq; }

	auto primaryTextSelection(){
		{
			auto a = textSelectionsGet.filter!"a.primary";
			if(!a.empty) return a.front;
		}

		{
			auto a = textSelectionsGet;         //choose the first if none is marked with the primary flag.
			if(!a.empty) return a.front;
		}

		return TextSelection.init;
	}

	auto primaryCaret(){
		return primaryTextSelection.caret;
	}

	auto moduleWithPrimaryTextSelection() {
		auto res = textSelectionsGet.filter!"a.primary".map!moduleOf.frontOrNull;
		if(!res) res = textSelectionsGet.map!moduleOf.frontOrNull; //if there is no Primary, pick the forst one
		return res;
	}

	Module oneSelectedModule(){
		if(selectedModules.take(2).walkLength==1)
			return selectedModules.front;
		return null;
	}

	Module expectOneSelectedModule(){
		auto m = oneSelectedModule;
		if(!m) flashError("This operation requires 1 selected module.");
		return m;
	}

	Module[] selectedModulesOrAll(){
		auto res = selectedModules.array;
		if(res.empty) res = modules;
		return res;
	}

	auto changedModules	(){ modules       .filter!"a.changed"; }
	auto projectModules	(){ return mainModule ? allFilesFromModule(mainModule.file).map!(f => findModule(f)).nonNulls.array : []; }
	auto changedProjectModules	(){ return projectModules.filter!"a.changed"; }
	void saveChangedProjectModules	(){ changedProjectModules.each!"a.save"; }

	private void closeSelectedModules_impl(){
		//todo: ask user to save if needed
		modules = unselectedModules;
		updateSubCells;
		invalidateTextSelections;
	}

	private void closeAllModules_impl(){
		//todo: ask user to save if needed
		clear;
		invalidateTextSelections;
	}

	bool loadModule(in File file){
		const vec2 targetPos = lastModulePositions.get(file.actualFile.hashOf, vec2(calcBounds.right+24, 0));
		return loadModule(file, targetPos); //default position
	}

	bool loadModule(in File file, vec2 targetPos){
		if(!file.exists) return false;
		if(auto m = findModule(file)){
			m.fileLoaded = now; //it's just a flash indicator
			frmMain.view.smartScrollTo(m.outerBounds);
			return false; //no loading was issued
		}

		auto m = new Module(this, file);

		//m.flags.targetSurface = 0; not needed, workspace is on s0 already
		m.measure;
		m.outerPos = targetPos;
		modules ~= m;
		updateSubCells;

		/+justLoadedSomething |= true;
		justLoadedBounds |= m.outerBounds; +/

		frmMain.view.smartScrollTo(m.outerBounds);

		return true;
	}

	File[] allFilesFromModule(File file){
		if(!file.exists) return [];
		//todo: not just for //@exe of //@dll
		BuildSettings settings = { verbose : false };
		BuildSystem buildSystem;
		return buildSystem.findDependencies(file, settings).map!(m => m.file).array;
	}

	auto loadModuleRecursive(File file){
		allFilesFromModule(file).each!(f => loadModule(f));
	}

	void queueModule(File f){ openQueue ~= f; }
	void queueModuleRecursive(File f){ if(f.exists) openQueue ~= allFilesFromModule(f); }

	void updateOpenQueue(int maxWork){
		while(openQueue.length){
			auto f = openQueue.fetchFront;
			if(loadModule(f)){
				maxWork--;
				if(maxWork<=0) return;
			}
		}
	}

	void updateModuleBuildStates(in BuildResult buildResult){
		foreach(m; modules){
			m.buildState = buildResult.getBuildStateOfFile(m.file);
		}
	}

	ErrorListModule errorList;

	void convertBuildMessagesToSearchResults(){
		auto br = frmMain.buildResult;

		auto outFile = File(`virtual:\compile.err`);
		auto output = br.dump;
		outFile.write(output);
		//LOG(output);
		
		T0;
		//opt: in debug mode this is terribly slow.
		errorList = new ErrorListModule(null, File.init);
		//LOG(siFormat("errorList create %s ms", DT));

		/*if(auto m = findModule(outFile)){
			m.reload;
		}else{
			loadModule(outFile);
		}*/

		auto buildMessagesAsSearchResults(BuildMessageType type){ //todo: opt
			Container.SearchResult[] res;

			foreach(msgIdx, const msg; br.messages) if(msg.type==type){
				
				if(auto mod = findModule(msg.location.file.withoutDMixin)){    //opt: bottleneck! linear search
					if((msg.location.line-1).inRange(mod.content.subCells)){
						Container.SearchResult sr;
						sr.container = cast(Container)mod.content.subCells[msg.location.line-1];
						sr.absInnerPos = mod.innerPos + mod.content.innerPos + sr.container.innerPos;
						sr.cells = sr.container.subCells;
						sr.reference = CodeLocationPrefix~msg.location.text;
						res ~= sr;
					}else{
						//line not found in module
						//LOG(msg);
					}
				}else{
					//module not loaded
					//LOG(msg);

					//if(msg.location.file.exists) queueModule(msg.location.file);
				}
			}

			return res;
		}

		//opt: it is a waste of time. this should be called only at buildStart, and at buildProgress, module change, module move.
		//1.5ms, (45ms if not sameText but sameFile(!!!) is used in the linear findModule.)
		foreach(t; EnumMembers!BuildMessageType[1..$])
			markerLayers[t].searchResults = buildMessagesAsSearchResults(t);
	}


	void updateLastKnownModulePositions(){
		foreach(m; modules)
			lastModulePositions[m.file.hashOf] = m.outerPos;
	}

	//todo: since all the code containers have parents, location() is not needed anymore

	override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0)){  //locate ////////////////////////////////
		ofs += innerPos;
		foreach_reverse(m; modules){
			auto st = m.locate(mouse, ofs);
			if(st.length) return st;
		}
		return [];
	}

	CellLocation[] locate_snapToRow(in vec2 mouse){
		auto st = locate(mouse);

		if(st.length) with(st.back) if(auto col = cast(CodeColumn)cell){
			const ofs = calcSnapOffsetFromPadding;
			if(ofs) st = locate(mouse+ofs);
		}

		return st;
	}

	CodeLocation cellLocationToCodeLocation(CellLocation[] st){
		auto a(T)(void delegate(T) f){ if(auto x = cast(T)st.get(0).cell){ st.popFront; f(x); } }

		//note: this works only at the first dept level

		CodeLocation res;
		a((Module m){
			res.file = m.file;
			a((CodeColumn col){
				a((CodeRow row){
					if(auto line = col.subCells.countUntil(row)+1){   //todo: parent.subcellindex/child.index
						res.line = line.to!int;
						a((Cell cell){
							if(auto column = row.subCells.countUntil(cell)+1) //todo: parent.subcellindex/child.index
								res.column = column.to!int;
						});
					}
				});
			});
		});
		return res;
	}

	static CellLocation[] findLastCodeRow(CellLocation[] st){
		foreach_reverse(i; 0..st.length){  //todo: functinal
			auto row = cast(CodeRow)st[i].cell;
			if(row) return st[i..$];
		}
		return [];
	}

	TextCursor cellLocationToTextCursor(CellLocation[] st){
		TextCursor res;
		st = findLastCodeRow(st);
		if(auto row = cast(CodeRow)st.get(0).cell){
			auto cell = st.get(1).cell;

			//try to find cell with smaller height than the row, vertically at x, if the mouse is not exactly inside the cell. Also snap from the sides.
			if(!cell){
				cell = row.subCellAtX(st[0].localPos.x, Yes.snapToNearest);
				if(cell)
					st  ~= CellLocation(cell, st[0].localPos-cell.innerPos); //pass in localPos inside the cell
			}

			res.codeColumn = row.parent;

			res.desiredX = st[0].localPos.x;
			res.pos.y = row.index;

			//find x character index
			int x;
			if(cell){
				x = row.subCellIndex(cell);
				assert(x>=0);
				if(st[1].localPos.x>cell.innerWidth/2) x++;
			}else{
				x = res.desiredX<0 ? 0 : row.cellCount;
			}
			assert(x.inRange(0, row.cellCount));
			res.pos.x = x;
		}

		return validate(res);
	}

	TextCursor createCursorAt(vec2 p){
		return cellLocationToTextCursor(locate_snapToRow(p));
	}

	// textSelection, cursor movements /////////////////////////////

	int lineSize(){ return DefaultFontHeight; }
	int pageSize(){ return (frmMain.view.subScreenBounds_anim.height/lineSize*.9f).iround.clamp(2, 100); }
	void cursorOp(ivec2 dir, bool select){
		auto arr = textSelectionsGet;
		foreach(ref ts; arr) ts.move(dir, select);
		textSelectionsSet = merge(arr); //todo: maybe merge should reside in validateTextSelections
	}

	void scrollV(float dy){ frmMain.view.scrollV(dy); }
	void scrollH(float dx){ frmMain.view.scrollH(dx); }
	void zoom(float log){ frmMain.view.zoom(log); } //todo: Only zoom when window is foreground

	float scrollSpeed(){ return frmMain.deltaTime.value(second)*2000; }
	float zoomSpeed(){ return frmMain.deltaTime.value(second)*8; }
	float wheelSpeed = 0.375f;

	void insertCursor(int dir){
		auto prev = textSelectionsGet,
				 next = prev.dup;

		foreach(ref ts; next)
			foreach(ref tc; ts.cursors)  //note: It is important to move the cursors separately here.  Don't let TextSelection.move do cursor collapsing.
				tc.move(ivec2(0, dir));

		textSelectionsSet = merge(prev ~ next);
	}

	auto insertCursorAtEndOfEachLineSelected_impl(R)(R textSelections){
		auto res = textSelections
			.filter!"a.valid"  //just to make sure
			.map!(sel => iota(sel.start.pos.y, sel.end.pos.y+1).map!(y => TextCursor(sel.codeColumn, ivec2(0, y)))) //create cursors in every lines at the start of the line
			.joiner
			.map!((c){ //move the cursor to	the end of the line
				c.moveRight(TextCursor.end);	//todo: it's not functional yet
				return TextSelection(c, c, false); //make a selection out of them
			}).merge;   //merge it, because there can be duplicates

		if(res.length) res[0].primary = true;

		return res;
	}


	void scrollInModules(Module[] m){
		if(m.length) scrollInBoundsRequest = m.map!"a.outerBounds".fold!"a|b";
	}

	void scrollInAllModules(){
		scrollInModules(modules);
	}

	void scrollInModule(Module m){
		if(m) scrollInModules([m]);
	}

	void cancelSelection_impl(){ // cancelSelection_impl //////////////////////////////////////
		auto ts = textSelectionsGet;
		auto mp = moduleWithPrimaryTextSelection;

		void selectPrimaryModule(){
			textSelectionsSet = [];
			foreach(m; modules) m.flags.selected = m is mp;
			scrollInModule(mp);
		}

		//multiTextSelect -> primaryTextSelect
		if(ts.length>1){
			if(auto pts = primaryTextSelection) textSelectionsSet = [pts];
																		 else selectPrimaryModule; //just for safety
			return;
		}

		if(ts.length>0){
			selectPrimaryModule;
			return;
		}

		//deselect everything, zoom all
		textSelectionsSet = [];
		deselectAllModules;
		scrollInAllModules;


		//auto em = editedModules;
		//if(em.length>1)

		//todo: primary

/*	   if(lod.moduleLevel){
	   deselectAllModules;
		}

		if(lod.codeLevel){
			auto ts =
			if(textSelectionsGet.length>1){
				textSelectionsSet.length = 1;
				with(textSelections[0]){
					scrollInBoundsRequest = worldBounds(textSelections);
				}
				//todo: scroll in
			}else if(textSelections.length==1) with(textSelections[0]){
				if(valid && !isZeroLength){
					cursors[0] = cursors[1];
					scrollInBoundsRequest = worldBounds(textSelections);
				}else{
					textSelections = [];
					scrollInAllModules;
				}
			}
		}*/


	}

	void selectSearchResults(SearchResult[] arr){ // selectSearchResults ///////////////////////////

		//todo: use this as a revalidator after the modules were changed under the search results. Maybe verify the search results while drawing. Cache the last change or something.

		TextSelection conv(SearchResult sr){
			if(sr.cells.length) if(auto row = cast(CodeRow)sr.container) if(auto col = row.parent){
				auto rowIdx = row.index,
						 st = row.subCellIndex(sr.cells.front), //todo: could find other cells as well. If the user edits the document for example.
						 en = row.subCellIndex(sr.cells.back);
				if(rowIdx>=0 && st>=0 && en>=0){
					auto ts = TextSelection(TextCursor(col, ivec2(st, rowIdx)), TextCursor(col, ivec2(en+1, rowIdx)), false);
					return validate(ts);
				}
			}
			return TextSelection.init;
		}

		//T0; scope(exit) DT.LOG;
		textSelectionsSet = merge(arr.map!(a => conv(a)).filter!"a.valid".array);
	}

	//todo: BOM handling for copy and paste. To be able to communicate with other apps.

	// Undo/Redo/History ///////////////////////////////////////////

	// request edit permissions //////////////////////////////////////

	protected uint undoGroupId; //this value is incremented by every cut or paste batch operation. Theis controls undoOperation fuson, in order to preserve the order of multiselect cut and paste operations. (cursors are only vanid if they are in order.)

	protected bool requestModifyPermission(CodeColumn col){  //todo: constness
		assert(col);
		if(isReadOnly) return false;
		auto m = moduleOf(col);
		return !m.isReadOnly;
	}

	protected bool requestDeletePermission(TextSelection ts){
		auto res = requestModifyPermission(ts.codeColumn);
		if(res){
			static if(LogRequestPermissions) print(EgaColor.ltRed("DEL"), ts.toReference.text, ts.sourceText.quoted);

			auto m = moduleOf(ts).enforce;
			m.undoManager.justRemoved(undoGroupId, ts.toReference.text, ts.sourceText);
		}
		return res;
	}

	protected struct CollectedInsertRecord{
		int stage;
		TextSelection textSelection;
		string contents;
		void reset(){ this = typeof(this).init; }
	}
	protected CollectedInsertRecord collectedInsertRecord;

	protected bool requestInsertPermission_prepare(TextSelection ts, string str){
		auto res = requestModifyPermission(ts.codeColumn);

		if(res){
			auto m = moduleOf(ts).enforce;
			static if(LogRequestPermissions) print(EgaColor.ltGreen("INS0"), ts.toReference, str.quoted);
			with(collectedInsertRecord){
				enforce(stage==0, "collectedInsertRecord.stage inconsistency 1");
				stage = 1;
				textSelection = ts;
				contents = str;
			}
		}
		return res;
	}

	protected void requestInsertPermission_finish(TextSelection ts){
		auto m = moduleOf(ts).enforce;
		with(collectedInsertRecord){
			enforce(stage==1, "collectedInsertRecord.stage inconsistency 2");
			static if(LogRequestPermissions) print(EgaColor.ltCyan("INS1"), ts.toReference);

			textSelection.cursors[1] = ts.cursors[1];
			m.undoManager.justInserted(undoGroupId, textSelection.toReference.text, contents);
			reset;
		}
	}

	//Resyntax queue ////////////////////////////////////////////////////////

	void needResyntax(Cell cell){
		//LOG(cell.text);

		static DateTime resyntaxNow;
		if(auto col = cell.thisAndAllParents!CodeColumn.frontOrNull){
			resyntaxNow.actualize;

			//fast update last item if possible
			if(resyntaxQueue.map!"a.what".backOrNull is col){
				resyntaxQueue.back.when = resyntaxNow;
				col.lastResyntaxTime = resyntaxNow;
				return;
			}

			//remove if alreay exists
			resyntaxQueue = resyntaxQueue.remove!(e => e.what is col);

			resyntaxQueue ~= ResyntaxEntry(col, resyntaxNow);
			col.lastResyntaxTime = resyntaxNow;

		}else assert(0, "Unhandled type");
	}

	void UI_ResyntaxQueue(){ with(im){
		foreach(e; resyntaxQueue)Row({
			Row(e.when.text, { width = fh*9; });
			if(auto col = cast(CodeColumn)e.what){
				auto tc = TextCursor(col, ivec2(0, 0));
				Row(tc.toReference.text);
			}
		});
	}}

	bool resyntaxNowOrLater(Cell cell, DateTime changedId, Flag!"later" later){
		if(auto col = cast(CodeColumn)cell){
			if(later){
				syntaxHighlightWorker.addJob(changedId, TextCursor(col, ivec2(0)).toReference.text, /*col.sourceText*/ "UNUSED");
			}else{
				if(auto mod = col.moduleOf){
					mod.resyntax;
				}else assert(0, "Unable to resyntax: No module");
			}
			return true;
		}else assert(0, "Unable to resyntax: No CodeColumn");
	}

	/// returns true if any work done or queued
	bool updateResyntaxQueue(){

		if(auto job = syntaxHighlightWorker.getResult){
			auto selRef = TextSelectionReference(job.resourceId, &findModule); //todo: This string -> Object mapping is not flexible. Should work for Cursor and also for Column or Row or Node
			if(selRef.valid){
				auto sel = selRef.fromReference;
				if(sel.valid){
					auto col = sel.codeColumn;
					auto mod = col.moduleOf;
					enforce(mod && mod.content is col, "syntaxHighlightWorker.getResult: only codeColumns that has a Module parent are supported");

					static DateTime lastOutdatedResyncTime;
					if(col.lastResyntaxTime==job.changeId || now-lastOutdatedResyncTime > .25*second){
						//mod.resyntax_src(job.sourceCode);
						mod.resyntax;
						lastOutdatedResyncTime = now;
					}
				}
			}
		}

		if(resyntaxQueue.empty) return false;

		//limit the frequency of slow sourceText() calls
		static DateTime lastResyntaxLaterTime;
		if(now-lastResyntaxLaterTime < .25*second) return false;
		lastResyntaxLaterTime = now;

		auto act = resyntaxQueue.fetchBack;
		return resyntaxNowOrLater(act.what, act.when, Yes.later);
	}

	///All operations must go through copy_impl or cut_impl. Those are calling requestModifyPermission and blocks modifications when the module is readonly. Also that is needed for UNDO.
	bool copy_impl(TextSelection[] textSelections){  // copy_impl ///////////////////////////////////////
		assert(textSelections.map!"a.valid".all && textSelections.isSorted); //todo: merge check

		auto copiedSourceText = textSelections.sourceText;
		bool valid = copiedSourceText.length>0;
		if(valid) clipboard.asText = copiedSourceText;  //todo: BOM handling
		return valid;
	}

	///Ditto
	auto cut_impl(bool dontMeasure=false)(TextSelection[] textSelections, bool* returnSuccess=null){  // cut_impl ////////////////////////////////////////
		undoGroupId++;

		assert(textSelections.map!"a.valid".all && textSelections.isSorted); //todo: merge check

		auto savedSelections = textSelections.map!"a.toReference".array;

		if(returnSuccess !is null) *returnSuccess = true; //todo: terrible way to

		void cutOne(TextSelection sel){
			if(sel.isZeroLength) return; //nothing to do with empty selection
			if(auto col = sel.codeColumn){
				const st = sel.start,
							en = sel.end;

				foreach_reverse(y; st.pos.y..en.pos.y+1){ //todo: this loop is in the draw routine as well. Must refactor and reuse
					if(auto row = col.getRow(y)){
						const rowCellCount = row.cellCount;

						const isFirstRow	= y==st.pos.y,
									isLastRow	= y==en.pos.y,
									isMidRow	= !isFirstRow && !isLastRow;
						if(isMidRow){ //delete whole row
							col.subCells = col.subCells.remove(y); //opt: do this in a one run batch operation.
						}else{ //delete partial row
							const	x0 = isFirstRow	? st.pos.x : 0,
								x1 = isLastRow	? en.pos.x : rowCellCount+1;

							foreach_reverse(x; x0..x1){
								if(x>=0 && x<rowCellCount){
									row.subCells = row.subCells.remove(x);  //opt: this is not so fast. It removes 1 by 1.
								}else if(x==rowCellCount){ //newLine
									if(auto nextRow = col.getRow(y+1)){
										foreach(ref ss; savedSelections)   //opt: must not go througn all selection. It could binary search the start position to iterate.
											ss.replaceLatestRow(nextRow, row);

										if(nextRow.subCells.length){
											row.append(nextRow.subCells);
											row.adoptSubCells;
											//note: it seems logical, but not help in tracking. Always mark a cut with changedRemoved: row.setChangedCreated;
										}

										nextRow.subCells = [];
										col.subCells = col.subCells.remove(y+1);
									}else assert(0, "TextSelection out of range NL");
								}else assert(0, "TextSelection out of range X");
							}

							row.refreshTabIdx;
							row.spreadElasticNeedMeasure;
							row.setChangedRemoved;
						}

					}else assert(0, "TextSelection out of range Y");
				}//for y

				needResyntax(col);
			}else assert(0, "TextSelection invalid CodeColumn");
		}

		foreach_reverse(sel; textSelections){
			if(!sel.isZeroLength){
				if(requestDeletePermission(sel)){
					cutOne(sel);
				}else{
					if(returnSuccess !is null)     //todo: maybe it would be better to handle readOnlyness with an exception...
						*returnSuccess = false;
				}
			}
		}

		static if(!dontMeasure)
			measure; //It's needed to calculate TextCursor.desiredX
		//opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.

		return savedSelections.map!"a.fromReference".filter!"a.valid".array;
	}

	bool cut_impl2(bool dontMeasure=false)(TextSelection[] sel, ref TextSelection[] res){    //todo: constness for input
		bool success;
		auto tmp = cut_impl!dontMeasure(sel, &success);
		if(success) res = tmp;
		return success;
	}

	auto paste_impl(bool dontMeasure=false)(TextSelection[] textSelections, Flag!"fromClipboard" fromClipboard, string input, Flag!"duplicateTabs" duplicateTabs = No.duplicateTabs){ // paste_impl //////////////////////////////////
		if(textSelections.empty) return textSelections; //no target

		if(fromClipboard)
			input = clipboard.asText;  //todo: BOM handling

		auto lines = input.splitLines;
		if(lines.empty) return textSelections; //nothing to do with an empty clipboard

		if(!cut_impl2!dontMeasure(textSelections, /+writes into this if successful -> +/textSelections))  //todo: this is terrible. Must refactor.
			return textSelections;

		//from here it's paste -------------------------------------------------
		undoGroupId++;

		TextSelectionReference[] savedSelections;

		//todo: insertText with fake local syntax highlighting. until the background syntax highlighter finishes.

		///inserts text at cursor, moves the corsor to the end of the text
		void simpleInsert(ref TextSelection ts, string str){
			assert(ts.valid);
			assert(ts.isZeroLength);
			assert(ts.caret.pos.y.inRange(ts.codeColumn.subCells));

			if(auto row = ts.codeColumn.getRow(ts.caret.pos.y)){

				if(requestInsertPermission_prepare(ts, str)){
					const insertedCnt = row.insertText(ts.caret.pos.x, str); //todo: shift adjust selections that are on this row

					//adjust caret and save
					ts.cursors[0].moveRight(insertedCnt);
					ts.cursors[1] = ts.cursors[0];

					requestInsertPermission_finish(ts);
					needResyntax(ts.codeColumn);
				}

				savedSelections ~= ts.toReference;
			}else assert("Row out if range");
		}

		void multiInsert(ref TextSelection ts, string[] lines ){
			assert(ts.valid);
			assert(ts.isZeroLength);
			assert(lines.length>=2);

			if(auto row = ts.codeColumn.getRow(ts.caret.pos.y)){
				assert(ts.caret.pos.x>=0 && ts.caret.pos.x<=row.subCells.length);

				//handle leadingTab duplication
				if(duplicateTabs && row.leadingCodeTabCount){
					lines = lines.dup;
					lines.back = "\t".replicate(row.leadingCodeTabCount) ~ lines.back;
				}

				if(requestInsertPermission_prepare(ts, lines.join(DefaultNewLine))){
					//break the row into 2 parts
					//transfer the end of (first)row into a lastRow
					auto lastRow = row.splitRow(ts.caret.pos.x);

					//insert at the end of the first row
					row.insertText(row.cellCount, lines.front);

					//create extra rows in the middle
					Cell[] midRows;
					foreach(line; lines[1..$-1]){
						auto r = new CodeRow(ts.codeColumn, line); //todo: this should be insertText
						r.setChangedCreated;
						midRows ~= r;
					}

					//insert at the beginning of the last row
					const insertedCnt = lastRow.insertText(0, lines.back);

					//insert modified rows into column
					ts.codeColumn.subCells	= ts.codeColumn.subCells[0..ts.caret.pos.y+1]
						~ midRows
						~ lastRow
						~ ts.codeColumn.subCells[ts.caret.pos.y+1..$];

					//adjust caret and save as reference
					ts.cursors[0].pos.y += lines.length.to!int-1;
					ts.cursors[0].pos.x = insertedCnt;
					ts.cursors[1] = ts.cursors[0];

					requestInsertPermission_finish(ts);
					needResyntax(ts.codeColumn);
				}

				savedSelections ~= ts.toReference;

				//todo:update caret
			}else assert("Row out if range");
		}

		///insert all lines into the selection
		void fullInsert(ref TextSelection ts){
			if(lines.length==1){ //simple text without newline
				simpleInsert(ts, lines[0]);
			}else if(lines.length>1){ //insert multiline text
				multiInsert(ts, lines);
			}
		}

		if(textSelections.length==1){ //put all the clipboard into one place
			fullInsert(textSelections[0]);
		}else if(textSelections.length>1){
			if(lines.length>textSelections.length || duplicateTabs/+this means it is pasting newlines+/){ //clone the full clipboard into all selections.
				foreach_reverse(ref ts; textSelections)
					fullInsert(ts);
			}else{ //cyclically paste the lines of the clipboard
				foreach_reverse(ref ts, line; lockstep(textSelections, lines.cycle.take(textSelections.length)))
					simpleInsert(ts, line);
			}
		}

		static if(!dontMeasure)
			measure; //It's needed to calculate TextCursor.desiredX
		//opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.

		return savedSelections.retro.map!"a.fromReference".filter!"a.valid".array;
	}

	// execute undo/redo //////////////////////////////////////////////////

	protected void executeUndoRedoRecord(in bool isUndo, in bool isInsert, in TextModificationRecord rec){

		TextSelection ts;
		bool decodeTs(bool reduceToStart){
			string where = rec.where;
			if(reduceToStart) where = where.reduceTextSelectionReferenceStringToStart;
			ts = TextSelection(where, &findModule);
			bool res = ts.valid;
			if(!res) WARN("Invalid ts: "~where);
			return res;
		}

		const isCut = isUndo==isInsert;

		if(decodeTs(!isCut)){

			if(isCut) cut_impl!true([ts]);
					 else paste_impl!true([ts], No.fromClipboard, rec.what);

			if(decodeTs(isCut))
				textSelectionsSet = [ts];
		}

	}

	protected void executeUndoRedo(bool isUndo)(in TextModification tm){
		static if(isUndo) auto r = tm.modifications.retro; else auto r = tm.modifications;
		r.each!(m => executeUndoRedoRecord(isUndo, tm.isInsert, m));
	}

	protected void execute_undo(in TextModification tm){ executeUndoRedo!true (tm); }
	protected void execute_redo(in TextModification tm){ executeUndoRedo!false(tm); }

	protected void execute_reload(string where, string what){
		if(auto m=findModule(File(where))){
			m.reload(Yes.useExternalContents, what);
			//selectAll
			textSelectionsSet = [m.content.allSelection(true)]; //todo: refactor codeColumn.allTextSelection(bool primary or not)
		}else assert(0, "execute_reload: module lost: "~where.quoted);
		//todo: somehow signal bact to the undo manager, if an undo operation is failed
	}

	void undoRedo_impl(string what)(){ //todo: select the latest undo/redo operation if there are more than one modules selected. If no modules selected: select from all of them.
		if(auto m = moduleWithPrimaryTextSelection){ //todo: undo should not remove textSelections on other modules.
			mixin(q{ m.undoManager.#(&execute_#, &execute_reload); }.replace("#", what));
			invalidateTextSelections; //because executeUndo don't call measure() so desiredX's are invalid.
		}
	}

	//! Keyboard mapping ///////////////////////////////////////

	// Navigation ---------------------------------------------

	@VERB("Ctrl+Up"	) void scrollLineUp	(){ scrollV( DefaultFontHeight); }
	@VERB("Ctrl+Down"	) void scrollLineDown	(){ scrollV(-DefaultFontHeight); }
	@VERB("Alt+PgUp"	) void scrollPageUp	(){ scrollV( frmMain.clientHeight*.9); }
	@VERB("Alt+PgDn"	) void scrollPageDown	(){ scrollV(-frmMain.clientHeight*.9); }
	@VERB("Ctrl+="	) void zoomIn	(){ zoom ( .5); }
	@VERB("Ctrl+-"	) void zoomOut	(){ zoom (-.5); }
			
	@HOLD("Ctrl+Num8"	) void holdScrollUp	(){ scrollV( scrollSpeed); }
	@HOLD("Ctrl+Num2"	) void holdScrollDown	(){ scrollV(-scrollSpeed); }
	@HOLD("Ctrl+Num4"	) void holdScrollLeft	(){ scrollH( scrollSpeed); }
	@HOLD("Ctrl+Num6"	) void holdScrollRight	(){ scrollH(-scrollSpeed); }
	@HOLD("Ctrl+Num+"	) void holdZoomIn	(){ zoom ( zoomSpeed); }
	@HOLD("Ctrl+Num-"	) void holdZoomOut	(){ zoom (-zoomSpeed); }
			
	@HOLD("Alt+Ctrl+Num8"	) void holdScrollUp_slow	(){ scrollV( scrollSpeed/8); }
	@HOLD("Alt+Ctrl+Num2"	) void holdScrollDown_slow	(){ scrollV(-scrollSpeed/8); }
	@HOLD("Alt+Ctrl+Num4"	) void holdScrollLeft_slow	(){ scrollH( scrollSpeed/8); }
	@HOLD("Alt+Ctrl+Num6"	) void holdScrollRight_slow	(){ scrollH(-scrollSpeed/8); }
	@HOLD("Alt+Ctrl+Num+"	) void holdZoomIn_slow	(){ zoom ( zoomSpeed/8); }
	@HOLD("Alt+Ctrl+Num-"	) void holdZoomOut_slow	(){ zoom (-zoomSpeed/8); }

	// Navigation when there is	no textSelection ////////////////////////////////////
	@HOLD("W Num8 Up"	) void holdScrollUp2	(){ if(textSelectionsGet.empty) scrollV( scrollSpeed); }
	@HOLD("S Num2 Down"	) void holdScrollDown2	(){ if(textSelectionsGet.empty) scrollV(-scrollSpeed); }
	@HOLD("A Num4 Left"	) void holdScrollLeft2	(){ if(textSelectionsGet.empty) scrollH( scrollSpeed); }
	@HOLD("D Num6 Right"	) void holdScrollRight2	(){ if(textSelectionsGet.empty) scrollH(-scrollSpeed); }
	@HOLD("E Num+ PgUp"	) void holdZoomIn2	(){ if(textSelectionsGet.empty) zoom ( zoomSpeed); }
	@HOLD("Q Num- PgDn"	) void holdZoomOut2	(){ if(textSelectionsGet.empty) zoom (-zoomSpeed); }

	//todo: this is redundant and ugly
	//bug: When NumLockState=true && key==Num8: if the modifier is released after the key, KeyCombo will NEVER detect the release and is stuck!!!
	@HOLD("Shift+W Shift+Num8 Shift+Up"	) void holdScrollUp_slow2	(){ if(textSelectionsGet.empty) scrollV( scrollSpeed/8); }
	@HOLD("Shift+S Shift+Num2 Shift+Down"	) void holdScrollDown_slow2	(){ if(textSelectionsGet.empty) scrollV(-scrollSpeed/8); }
	@HOLD("Shift+A Shift+Num4 Shift+Left"	) void holdScrollLeft_slow2	(){ if(textSelectionsGet.empty) scrollH( scrollSpeed/8); }
	@HOLD("Shift+D Shift+Num6 Shift+Right"	) void holdScrollRight_slow2	(){ if(textSelectionsGet.empty) scrollH(-scrollSpeed/8); }
	@HOLD("Shift+E Shift+Num+ Shift+PgUp"	) void holdZoomIn_slow2	(){ if(textSelectionsGet.empty) zoom ( zoomSpeed/8); }
	@HOLD("Shift+Q Shift+Num- Shift+PgDn"	) void holdZoomOut_slow2	(){ if(textSelectionsGet.empty) zoom (-zoomSpeed/8); }
			
	@VERB("Home"	) void zoomAll2()	{ if(textSelectionsGet.empty) frmMain.view.zoom(worldInnerBounds(this), 12); }
	@VERB("Shift+Home"	) void zoomClose2()	{ if(textSelectionsGet.empty) frmMain.view.scale = 1; }
	

	// Cursor and text selection ----------------------------------------
	@VERB("Left"	) void cursorLeft	(bool sel=false){ cursorOp(ivec2(-1	, 0	), sel); }
	@VERB("Right"	) void cursorRight	(bool sel=false){ cursorOp(ivec2( 1	, 0	), sel); }
	@VERB("Ctrl+Left"	) void cursorWordLeft	(bool sel=false){ cursorOp(ivec2(TextCursor.wordLeft	, 0	), sel); }
	@VERB("Ctrl+Right"	) void cursorWordRight	(bool sel=false){ cursorOp(ivec2(TextCursor.wordRight	, 0	), sel); }  //bug: This is bugs inside a nested comment.
	@VERB("Home"	) void cursorHome	(bool sel=false){ cursorOp(ivec2(TextCursor.home	, 0	), sel); }
	@VERB("End"	) void cursorEnd	(bool sel=false){ cursorOp(ivec2(TextCursor.end	,	0	), sel); }
	@VERB("Up"	) void cursorUp	(bool sel=false){ cursorOp(ivec2( 0	,-1	), sel); }		//todo: Dide2: textSelection. non zero length, Left/Right is good, Up/Down is not good. It should emulate a Left/Right selection collapse first. and go Up/Down after.
	@VERB("Down"	) void cursorDown	(bool sel=false){ cursorOp(ivec2( 0	, 1	), sel); }
	@VERB("PgUp"	) void cursorPageUp	(bool sel=false){ cursorOp(ivec2( 0	,-pageSize	), sel); }
	@VERB("PgDn"	) void cursorPageDown	(bool sel=false){ cursorOp(ivec2( 0	, pageSize	), sel); }
	@VERB("Ctrl+Home"	) void cursorTop	(bool sel=false){ cursorOp(ivec2(TextCursor.home		), sel); }
	@VERB("Ctrl+End"	) void cursorBottom	(bool sel=false){ cursorOp(ivec2(TextCursor.end		), sel); }
			
	@VERB("Shift+Left"	) void cursorLeftSelect	(){ cursorLeft	(true); }
	@VERB("Shift+Right"	) void cursorRightSelect	(){ cursorRight	(true); }
	@VERB("Shift+Ctrl+Left"	) void cursorWordLeftSelect	(){ cursorWordLeft	(true); }
	@VERB("Shift+Ctrl+Right"	) void cursorWordRightSelect	(){ cursorWordRight	(true); }
	@VERB("Shift+Home"	) void cursorHomeSelect	(){ cursorHome	(true); }
	@VERB("Shift+End"	) void cursorEndSelect	(){ cursorEnd	(true); }
	@VERB("Shift+Up Shift+Ctrl+Up"	) void cursorUpSelect	(){ cursorUp	(true); }
	@VERB("Shift+Down Shift+Ctrl+Down"	) void cursorDownSelect	(){ cursorDown	(true); }
	@VERB("Shift+PgUp"	) void cursorPageUpSelect	(){ cursorPageUp	(true); }
	@VERB("Shift+PgDn"	) void cursorPageDownSelect	(){ cursorPageDown	(true); }
	@VERB("Shift+Ctrl+Home"	) void cursorTopSelect	(){ cursorTop	(true); }
	@VERB("Shift+Ctrl+End"	) void cursorBottomSelect	(){ cursorBottom	(true); }
			
	@VERB("Ctrl+Alt+Up"	) void insertCursorAbove	(){ insertCursor(-1); }
	@VERB("Ctrl+Alt+Down"	) void insertCursorBelow	(){ insertCursor( 1); }
			
	@VERB("Shift+Alt+Left"	) void shrinkAstSelection	(){ }  //todo: shrink/extend Ast Selection
	@VERB("Shift+Alt+Right"	) void extendAstSelection	(){ }
	@VERB("Shift+Alt+I"	) void insertCursorAtEndOfEachLineSelected	(){ textSelectionsSet = insertCursorAtEndOfEachLineSelected_impl(textSelectionsGet); }
			
	@VERB("Ctrl+A"	) void selectAllText	(){ textSelectionsSet = modulesWithTextSelection.map!(m => m.content.allSelection(textSelectionsGet.any!(s => s.primary && s.moduleOf is m))).array; }
	@VERB("Ctrl+Shift+A"	) void selectAllModules	(){ textSelectionsSet = []; modules.each!(m => m.flags.selected = true); scrollInAllModules; }
	@VERB(""	) void deselectAllModules	(){ modules.each!(m => m.flags.selected = false); } //note: this clicking on emptyness does this too.
	@VERB("Esc"	) void cancelSelection	(){ if(!im.wantKeys) cancelSelection_impl; }  //bug: nested commenten belulrol Escape nyomkodas (kizoomolas) = access viola: ..., Column.drawSubCells_cull, CodeRow.draw(here!)

	// Editing ------------------------------------------------

	@VERB("Ctrl+C Ctrl+Ins"	) void copy	(){ copy_impl(textSelectionsGet.zeroLengthSelectionsToFullRows); } //bug: selection.isZeroLength Ctrl+C then Ctrl+V   It breaks the line. Ez megjegyzi, hogy volt-e selection extension es ha igen, akkor sorokon dolgozik. A sorokon dolgozas feltetele az, hogy a target is zeroLength legyen.
	@VERB("Ctrl+X Shift+Del"	) void cut	(){ TextSelection[]	s1 = textSelectionsGet.zeroLengthSelectionsToFullRows	, s2; copy_impl(s1);	 cut_impl2(s1, s2);	 textSelectionsSet = s2; }
	@VERB("Backspace"	) void deleteToLeft	(){ TextSelection[]	s1 = textSelectionsGet.zeroLengthSelectionsToOneLeft	, s2; cut_impl2(s1, s2);		 textSelectionsSet = s2; } //todo: delete all leading tabs when the cursor is right after them
	@VERB("Del"	) void deleteFromRight	(){ TextSelection[]	s1 = textSelectionsGet.zeroLengthSelectionsToOneRight	, s2; cut_impl2(s1, s2);		 textSelectionsSet = s2; } //bug: ha readonly, akkor NE tunjon el a kurzor! Sot, ha van non-readonly selecton is, akkor azt meg el is bassza.
			
	@VERB("Ctrl+V Shift+Ins"	) void paste	(){ textSelectionsSet = paste_impl(textSelectionsGet, Yes.fromClipboard	, ""	); }
	@VERB("Tab"	) void insertTab	(){ textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard	, "\t"	); } //todo: tab and shift+tab when multiple lines are selected
	@VERB("Enter"	) void insertNewLine	(){ textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard	, "\n", Yes.duplicateTabs	); } //todo: Must fix the tabCount on the current line first, and after that it can duplicate.


//todo: UndoRedo: mindig jelolje ki a szovegreszeket, ahol a valtozasok voltak! MultiSelectionnal az osszeset!
//todo: UndoRedo: hash ellenorzes a teljes dokumentumra.

	@VERB("Ctrl+Z"	) void undo	(){ if(expectOneSelectedModule) undoRedo_impl!"undo"	; }
	@VERB("Ctrl+Y"	) void redo	(){ if(expectOneSelectedModule) undoRedo_impl!"redo"	; }

	// Module and File operations ------------------------------------------------

	@VERB("Ctrl+O"	) void openModule	() { fileDialog.openMulti.each!(f => queueModule(f)); }
	@VERB("Ctrl+Shift+O"	) void openModuleRecursive	() { fileDialog.openMulti.each!(f => queueModuleRecursive(f)); }
	@VERB("Alt+O"	) void revertSelectedModules	() { preserveTextSelections({  foreach(m; selectedModules){ m.reload; m.fileLoaded = now; } }); }
	@VERB("Alt+S"	) void saveSelectedModules	() { selectedModules.each!"a.save"; }
	@VERB("Ctrl+S"	) void saveSelectedModulesIfChanged	() { selectedModules.filter!"a.changed".each!"a.save"; }
	@VERB("Ctrl+Shift+S"	) void saveAllModulesIfChanged	() { modules.filter!"a.changed".each!"a.save"; }
	@VERB("Ctrl+W"	) void closeSelectedModules	() { closeSelectedModules_impl; } //todo: this hsould work for selections and modules based on textSelections.empty
	@VERB("Ctrl+Shift+W"	) void closeAllModules	() { closeAllModules_impl; }
			
	@VERB("Ctrl+F"	) void searchBoxActivate	() { searchBoxActivate_request = true; }
	@VERB("Ctrl+Shift+L"	) void selectSearchResults	() { selectSearchResults(markerLayers[BuildMessageType.find].searchResults); }
	@VERB("F3"	) void gotoNextFind	() { NOTIMPL; }
	@VERB("Shift+F3"	) void gotoPrevFind	() { NOTIMPL; }
			
	@VERB("Ctrl+G"	) void gotoLine	() { if(auto m = expectOneSelectedModule){ searchBoxActivate_request = true; searchText = ":"; } }
			
	@VERB("F8"	) void gotoNextError	() { NOTIMPL; }
	@VERB("Shift+F8"	) void gotoPrevError	() { NOTIMPL; }
		
	@VERB("F9"	) void run	(){ with(frmMain) if(ready && !running	){ saveChangedProjectModules; run; 	} }
	@VERB("Shift+F9"	) void rebuild	(){ with(frmMain) if(ready && !running	){ saveChangedProjectModules; rebuild; 	} }
	@VERB("Ctrl+F2"	) void kill	(){ with(frmMain) if(building || running	){ cancelBuildAndResetApp; 	} } //todo: some keycombo to clear error markers

//	 @VERB("F5"	                          ) void toggleBreakpoint	            () { NOTIMPL; }
//	 @VERB("F10"																										 ) void stepOver												 () { NOTIMPL; }
//	 @VERB("F11"																										 ) void stepInto												 () { NOTIMPL; }

	void preserveTextSelections(void delegate() fun){ //todo: preserve module selections too
		const savedTextSelections = textSelectionsGet.map!(a => a.toReference.text).array;
		scope(exit) textSelectionsSet = savedTextSelections.map!(a => TextSelection(a, &findModule)).array;
		if(fun) fun();
	}

	//todo: Ctrl+D word select and find

	// Mouse ---------------------------------------------------

	struct MouseMappings{
		string main	      =	"LMB",
					 scroll="MMB",	//todo: soft scroll/zoom, fast scroll
					 menu="RMB",
					 zoom="MW",
					 zoomInHold="MB5",
					 zoomOutHold="MB4",
					 selectAdd="Alt",
					 selectExtend="Shift",
					 selectColumn						 = "Shift+Alt",
					 selectColumnAdd	      = "Ctrl+Shift+Alt";
	}

	void handleKeyboard(){
		if(!im.wantKeys && frmMain.canProcessUserInput){
			callVerbs(this);

			if(textSelectionsGet.empty){
				mainWindow.inputChars = [];
			}else{
				//todo: single window only
				string unprocessed;
				foreach(ch; mainWindow.inputChars.unTag.byDchar){
					if(ch==9 && ch==10){
						//if(flags.acceptEditorKeys) cmdQueue ~= EditCmd(cInsert, [ch].to!string);
					}else if(ch>=32){
						//cmdQueue ~= EditCmd(cInsert, [ch].to!string);
						try{
							//if(ch=='`') ch = '\U0001F4A9'; //todo: unable to input emojis from keyboard or clipboard! Maybe it's a bug.
							auto s = ch.to!string;
							textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard, s);
						}catch(Exception){
							unprocessed ~= ch;
						}

					}else{
						unprocessed ~= ch;
					}
				}
				mainWindow.inputChars = unprocessed;
			}

		}
	}

	void invalidateTextSelections(){
		PING0;
		mustValidateTextSelections = true;
		textSelectionManager.invalidateInternalSelections;
	}

	void validateTextSelectionsIfNeeded(){
		if(mustValidateTextSelections.chkClear){
			PING1;
			textSelections_internal = validate(textSelections_internal);
		}
	}


	auto validate(TextCursor c){
		return validate(TextSelection(c, c, false)).cursors[0];
	}

	auto validate(TextSelection s){
		auto ts = validate([s]);
		return ts.empty ? TextSelection.init : ts[0];
	}

	auto validate(TextSelection[] arr){
		Cell cachedExistingModule;

		bool isExistingModule(Cell c){
			if(c is cachedExistingModule) return true; //opt: this is helping nothing compared to
			if(auto m = cast(Module)c)
				if(modules.canFind(m)){
					cachedExistingModule = c;
					return true;
				}
			return false;
		}

		bool validate(TextSelection sel){
			if(!sel.valid) return false;
			auto r = sel.toReference;
			if(!r.valid) return false;

			auto p = r.cursors[0].path;
			if(p[0] !is this) return false;	 //not this workspace
			if(!isExistingModule(p[1])) return false;	 //module died

			//todo: check if selection is inside row boundaries.
			return true;
		}

		return arr.filter!(a => validate(a)).array; //todo: try to fix partially broken selections
	}

	void updateCodeLocationJump(){
		//jump to locations. A fucking nasty hack.
		if(inputs.LMB.pressed){
			//T0; scope(exit) DT.LOG;
			auto hs = hitTestManager.lastHitStack;
			if(!hs.empty){
				jumpTo(hs.back.id);
			}
		}
	}

	Nullable!vec2 jumpRequest;

	void jumpTo(in CodeLocation loc){
		if(loc){
			//print("LOC:", loc);
			if(auto mod = findModule(loc.file)){ //todo: load the module automatically
				if(auto ts = mod.content.cellSelection(loc.line, loc.column, true)){
					textSelectionsSet = [ts]; //todo: doubleClick = zoomclose
					with(frmMain.view){
						if(scale<0.3f) scale = 1;
						jumpRequest = nullable(vec2(ts.caret.worldBounds.center));
					}
				}else{ beep; WARN("selectCursor fail: "~loc.text); } //todo: at least select the line, or the module.
			}else{ beep; WARN("Can't find module: "~loc.text); }
		}
	}

	auto codeLocationFromStr(string s){
		if(s.isWild(CodeLocationPrefix~"*")) s = wild[1];

		CodeLocation loc;
		if(s.isWild(`?:\?*.d*(?*,?*)`)) try{  //todo: refactor this into CodeLocation struct
			string fn = wild[0]~`:\`~wild[1]~`.d`;
			//string mixinPostfix = wild[2];
			loc = CodeLocation(File(fn), wild[3].to!int, wild[4].to!int);
		}catch(Exception){ WARN("Invalid CodeLocation format: "~s.quoted); }
		return loc;
	}


	void jumpTo(string id){
		if(id.isWild(CodeLocationPrefix~"*")){
			jumpTo(codeLocationFromStr(wild[0]));
		}else if(id.isWild(MatchPrefix~"*")){
			NOTIMPL;
		}
	}

	void handleXBox(){
		static DateTime t0;
		const df = (now - t0).value((1.0f/60)*second).clamp(0, 10); //1 = 60FPS
		t0 = now;
		
		if(!frmMain.isForeground) return;
		
		const ss = df*32, zs = df*.18f;
		if(auto a = inputs.xiRX.value)	scrollH	(-a*ss);
		if(auto a = inputs.xiRY.value)	scrollV	( a*ss);
		if(auto a = inputs.xiLY.value){
			{//move mosuse to subScreen center
				const p = frmMain.view.subScreenClientCenter;
				mouseLock(mix(winMousePos, frmMain.clientToScreen(p), .125f));
				mouseUnlock;
			}
			
			{//zoom around mouse
				//const p = frmMain.view.subScreenClientCenter;
				const p = frmMain.screenToClient(winMousePos);
				frmMain.view.zoomAround(vec2(p), a*zs); //todo: ivec2 is not implicitly converted to vec2
			}
		}
	}

	const mouseMappings = MouseMappings.init;

	void update(View2D view, in BuildResult buildResult){ //update ////////////////////////////////////
		//textSelections = validTextSelections;  //just to make sure. (all verbs can validate by their own will)

		//note:	all verbs can optonally validate textSelections by accessing them from validTextSelections
		//	all verbs can call invalidateTextSelections if it does something that affects them
		handleXBox;
		handleKeyboard;
		updateCodeLocationJump;  if(KeyCombo("MMB").released/+pressed is not good because when I pan I don't see where the mouse is.+/ && nearestSearchResult.reference!="") jumpTo(nearestSearchResult.reference);  //todo: only do this when there was no lmouseTravelSinceLastPress
		updateOpenQueue(1);
		updateResyntaxQueue;

		measure;   //measures all containers if needed, updates ElasticTabstops
		//textSelections = validTextSelections;  //this validation is required for the upcoming mouse handling and scene drawing routines.

		// From here every positions and sizes are correct

		moduleSelectionManager.update(!im.wantMouse && mainWindow.canProcessUserInput && view.isMouseInside /+&& lod.moduleLevel+/, view, modules, textSelectionsGet.length>0, { textSelectionsSet = []; });
		textSelectionManager  .update(view, this, mouseMappings);

		//detect textSelection change
		const selectionChanged = textSelectionsHash.chkSet(textSelectionsGet.hashOf);

		//if there are any cursors, module selection if forced to modules with textSelections
		if(selectionChanged && textSelectionsGet.length){
			foreach(m; modules) m.flags.selected = false;
			foreach(m; modulesWithTextSelection) m.flags.selected = true;
		}

		//focus at selection
		if(!jumpRequest.isNull){
			with(frmMain.view) origin = jumpRequest.get - (subScreenOrigin-origin);
		}else if(!scrollInBoundsRequest.isNull){
			const b = scrollInBoundsRequest.get;
			frmMain.view.scrollZoom(b);
		}else if(!textSelectionManager.scrollInRequest.isNull){
			const p = textSelectionManager.scrollInRequest.get;
			frmMain.view.scrollZoom(bounds2(p, p));
		}else if(selectionChanged){
			if(!inputs[mouseMappings.main].down){ //don't focus to changed selection when the main mouse button is held down
				frmMain.view.scrollZoom(worldBounds(textSelectionsGet)); //todo: maybe it is problematic when the selection can't fit on the current screen
			}
		}
		scrollInBoundsRequest.nullify;
		jumpRequest.nullify;

		//animate cursors
		version(AnimatedCursors){
			if(textSelectionsGet.length<=MaxAnimatedCursors){
				const animT = calcAnimationT(application.deltaTime.value(second), .5, .25),
							maxDist = 1.0f;

				foreach(ref ts; textSelectionsGet){
					foreach(ref cr; ts.cursors[]) with(cr){
					 targetPos = localPos.pos; //todo: animate height as well
					 if(animatedPos.x.isnan) animatedPos = targetPos;
															else animatedPos.follow(targetPos, animT, maxDist);
					}
				}
			}
		}

		//update buildresults if needed (compilation progress or layer mask change)
		size_t calcBuildStateHash(){ return modules.map!"tuple(a.file, a.outerPos)".array.hashOf(buildResult.lastUpdateTime.hashOf(markerLayerHideMask/+to filter compile.err+/)); }
		//opt: outerPos is tracked to detect if a module was moved. It is wastefull to rebuild all the layers with all the info, only move the affected layer items.
		buildStateChanged = lastBuildStateHash.chkSet(calcBuildStateHash);
		if(buildStateChanged){
			updateModuleBuildStates(buildResult);
			convertBuildMessagesToSearchResults; //opt: limit this by change detection
		}

		updateLastKnownModulePositions;
	}

	auto calcBounds(){
		return modules.fold!((a, b)=> a|b.outerBounds)(bounds2.init);
	}

	deprecated void UI_ModuleBtns(){ with(im){
		File fileToClose;
		foreach(m; modules){
			if(Btn(m.file.name, hint(m.file.fullName), genericId(m.file.fullName), selected(0), { fh = 12; theme="tool"; if(Btn(symbol("Cancel"))) fileToClose = m.file; })) {}
		}
		if(Btn(symbol("Add"))) openModule;

		if(Btn("Close All", KeyCombo("Ctrl+Shift+W"))){
			closeAllModules;
		}

		if(fileToClose) closeModule(fileToClose);
	}}

	//! Save/Undo/History system ////////////////////////////////////////////////

	// 3 levels
	// 1. Save, SaveAll (ehhez csak egy olyan kell, hogy a legutolso save/load ota a user beleirt-e valamit.   Hierarhikus formaban lennenek a changed flag-ek, a soroknal meg lenne 2 extra: removedNextRow, removedPrevRow)
	// 2. Opcionalis Undo: ez csak 2 save kozott mukodhetne. Viszont a redo utani modositas nem semmisitene meg az utana levo undokat, hanem csak becsatlakoztatna a graph-ba. Innentol nem idovonal van, hanem graph.
	// 3. Opcionalis history: Egy kulon konyvtarba behany minden menteskori es betolteskori allapotot. Ezt kesobb delta codinggal tomoriteni kell.


	//! UI /////////////////////////////////////////////////////////

	void UI_SearchBox(View2D view){ UI_SearchBox(view, markerLayers[BuildMessageType.find].searchResults); }  //UI_SearchBox /////////////////////////////////////////////

	void zoomAt(View2D view, in Container.SearchResult[] searchResults){
		if(searchResults.empty) return;
		const maxScale = max(view.scale, 1);
		view.zoom(searchResults.map!(r => r.bounds).fold!"a|b", 12);
		view.scale = min(view.scale, maxScale);
	}

	void UI_SearchBox(View2D view, ref Container.SearchResult[] searchResults){ with(im) Row({
		//Keyboard shortcuts
		auto kcFindZoom	 = KeyCombo("Enter"), //only when edit is focused
				 kcFindToSelection	 = KeyCombo("Ctrl+Shift+L Alt+Enter"),
				 kcFindClose	 = KeyCombo("Esc"); //always

		//activate searchbox
		bool needFocus;
		if(!searchBoxVisible && searchBoxActivate_request){
			searchBoxVisible = needFocus = true;
		}
		searchBoxActivate_request = false;

		if(searchBoxVisible){
			width = fh*12;

			Text("Find ");
			.Container editContainer;

			if(Edit(searchText, genericArg!"focusEnter"(needFocus), { flex = 1; editContainer = actContainer; })){
				//refresh search results
				if(searchText.startsWith(':')){ //goto line
					//todo: Ctrl+G not works inside Edit
					//todo: hint text: Enter line number. Negative line number starts from the end of the module.
					//todo: ez ugorhatna regionra is.
					searchResults = [];
					textSelectionsSet = [];
					if(auto mod = expectOneSelectedModule) if(auto col  = mod.content) if(auto rowCount = col.cellCount){
						if(auto line = searchText[1..$].to!int.ifThrown(0)){

							if(line<0 && line>=-rowCount)
								line = rowCount+line+1; //mirror if negative

							if(auto ts = col.lineSelection_home(line, true))
								textSelectionsSet = [ts];
						}
					}
				}else{
					searchResults = selectedModulesOrAll.map!(m => m.search(searchText)).join;
				}
			}

			// display the number of matches. Also save the location of that number on the screen.
			const matchCnt = searchResults.length;
			Row({
				if(matchCnt) Text(" ", clGray, matchCnt.text, " ");
			});

			if(Btn(symbol("Zoom"), isFocused(editContainer) ? kcFindZoom : KeyCombo(""), enable(matchCnt>0), hint("Zoom screen on search results."))){
				zoomAt(view, searchResults);
			}

			if(Btn("Sel", isFocused(editContainer) ? kcFindToSelection : KeyCombo(""), enable(matchCnt>0), hint("Select search results."))){
				selectSearchResults(searchResults);
			}

			if(Btn(symbol("ChromeClose"), kcFindClose, hint("Close search box."))){
				searchBoxVisible = false;
				searchText = "";
				searchResults = [];
			}
		}else{

			if(Btn(symbol("Zoom"), hint("Start searching.")))
				searchBoxActivate; //todo: this is a @VERB. Button should get the extra info from that VERB somehow.
		}
	});}

	void UI(BuildMessageType bmt, View2D view){ with(im){ // UI_BuildMessageTypeBtn ///////////////////////////
		//todo: ennek nem itt a helye....
		auto hit = Btn({
			const hidden = markerLayers[bmt].visible ? 0 : .75f;

			auto fade(RGB c){ return c.mix(clSilver, hidden); }

			style.bkColor = bkColor = fade(bmt.color);
			const highContrastFontColor = blackOrWhiteFor(bkColor);
			style.fontColor = fade(highContrastFontColor);
			Text(bmt.caption);

			if(const len = markerLayers[bmt].searchResults.length){
				style.fontColor = highContrastFontColor;
				Text(" ", len.text);
			}
		}, genericId(bmt));

		if(mainWindow.isForeground && hit.pressed){
			markerLayers[bmt].visible = true;
			zoomAt(view, markerLayers[bmt].searchResults);
		}

		if(mainWindow.isForeground && hit.hover && inputs.RMB.pressed){
			markerLayers[bmt].visible.toggle;
		}
	}}

	void UI_selectedModulesHint(){ with(im){ // UI_selectedModulesHint//////////////////////////
		auto sm = selectedModules;
		void stats(){ Row(format!"(%d LOC, %sB)"(sm.map!(m => m.linesOfCode).sum, shortSizeText!(1024, " ")(sm.map!(m => m.sizeBytes).sum))); }
		if(sm.length==1){
			auto m = sm.front;
			Row({ padding="0 8"; }, "Selected module: ", { CodeLocation(m.file).UI; },
				{ if(sameText(m.file.fullName, mainModuleFile.fullName)){
						Btn("Main", enable(false));
					}else{
						if(m.isMain){
							if(Btn("Set Main")) mainModule = m;
						}
					}
					stats;
				}
			);
		}else if(sm.length>1){
			Row({ padding="0 8"; }, sm.length.text, " modules selected ", { stats; });
		}else{
			Row({ padding="0 8"; }, "No modules selected.");
		}
	}}

	void UI_mouseLocationHint(View2D view){ with(im){ // UI_mouseLocationHint //////////////////////////
		if(!view.isMouseInside) return;
		auto st = locate_snapToRow(view.mousePos);
		if(st.length){
			Row({ padding="0 8"; }, "\u2316 ", {
				const loc = cellLocationToCodeLocation(st);
				loc.UI;

				/*if(loc.file && loc.line){
					if(loc.column) with(findModule(loc.file).code){
						const pos = ivec2(loc.column, loc.line)-1;
						Text("   ", pos.text);
					}else with(findModule(loc.file).code){
						const pos = ivec2(st.back.localPos.x<=0 ? 0 : rows[loc.line-1].cellCount, loc.line-1);
						Text("   ", pos.text);
					}
				}*/

				/*auto crsr = cellLocationToTextCursor(st);
				if(crsr.valid){
					Text("   ", crsr.text, "   ", crsr.toReference.text, "   ", crsr.worldPos.text, "   ", view.mousePos.text);
				}*/

				if(textSelectionsGet.length>1){
					Text(format!"  Multiple Text Selections: %d  "(textSelectionsGet.length));
				}else if(textSelectionsGet.length==1){
					Text(format!"  Text Selection: %s  "(textSelectionsGet[0].toReference.text));
				}
			});
		}
	}}

	auto UI_ErrorList(){ with(im){ // UI_ErrorList ////////////////////////////
		/+with(im) Container(this.genericId, {
			margin = "2";
			border = "1 normal gray";
			innerHeight = 8*DefaultFontHeight;
			//innerHeight = 500;
			bkColor = clWinBackground;

			if(setupFun) setupFun();

			const rowHeight = KarcFileEntry.thumbHeight + KarcFileEntry.totalPadding;

			const totalHeight = mod.items.rowHeight*items.length;

			//size placeholder
			Container({ outerSize = vec2(0); outerPos = vec2(maxWidth, totalHeight); });

			with(flags){
				clipSubCells = true;
				vScrollState = ScrollState.auto_;
				wordWrap = false;
				hScrollState = ScrollState.auto_;
			}

			flags.saveVisibleBounds = true;
			auto visibleBounds = imstVisibleBounds(actId);

			if(visibleBounds.height>0 && items.length){
				int st = clamp((visibleBounds.top   /rowHeight).ifloor,  0, items.length.to!int-1);
				int en = clamp((visibleBounds.bottom/rowHeight).iceil , st, items.length.to!int-1);

				foreach(idx;  st..en+1){
					auto selected(){ return idx==itemIdx; }

					Row(genericId(idx), {
						auto hit = hitTest(true/*enabled*/);

						if(application.isForeground && hit.hover && (inputs.LMB.pressed || inputs.RMB.pressed)){

							//todo: this mouse getting thing is fucking lame. actMousePos should be accessible at all times, and flags.targetSurface should be inherited.
							const clientMouseX = im.actView.mousePos.x - hit.hitBounds.left - actContainer.topLeftGapSize.x,
										thumbOuterWidth = KarcFileEntry.thumbWidth + KarcFileEntry.totalPadding,
										clickedThumbIdx = (clientMouseX / thumbOuterWidth).ifloor,
										clickedThumbIdxValid = clickedThumbIdx.inRange(0, 1);

							void doClickOnItem(){ clicked = true; itemIdx = idx; }

							with(items[idx]) switch(karcCnt){
								case 2:{
									doClickOnItem;
									if(clickedThumbIdxValid) sensorIdx = clickedThumbIdx;
									break;
								}
								case 1:{
									if(clickedThumbIdxValid && clickedThumbIdx!=anyKarcIdx){
										//beep; //no image present at that clicked slot
										//todo: do a little error animation
									}else{
										doClickOnItem;
										sensorIdx = anyKarcIdx;
									}
									break;
								}
								default: doClickOnItem;
							}

						}

						style.bkColor = bkColor = mix(bkColor, clAccent, max(selected ? .5f:0, hit.hover_smooth*.25f));

						items[idx].UI(sensorIdx);
					});

					with(lastContainer){
						measure;
						outerPos.y = idx*rowHeight;

						maxWidth.maximize(outerWidth);

						//todo: autoWidth wont reset automatically when setting outterWidth
						flags.autoWidth = false;
						outerWidth = maxWidth;
					}
				}
			}
		});

		return clicked; +/


		auto siz = innerSize;
		Container({
			outerSize = siz;
			with(flags){
				clipSubCells = true;
				vScrollState = ScrollState.auto_;
				hScrollState = ScrollState.auto_;
			}

			if(auto mod = errorList){ 
				if(auto col = mod.content){
	
					//total size placeholder
					Container({ outerPos = col.outerSize; outerSize = vec2(0); });
	
					flags.saveVisibleBounds = true;
					if(auto visibleBounds = imstVisibleBounds(actId)){
						CodeRow[] visibleRows = col.rows.filter!(r => r.outerBounds.overlaps(visibleBounds) && r.subCells.length).array; //opt: binary search
						actContainer.append(cast(Cell[])visibleRows); //note: append is important because it already has the spaceHolder Container.
	
						/+print("-------------------------------");
	
						//print(frmMain.viewGUI.mousePos-hit.hitBounds.topLeft);
	
						void visitLocations(.Container act){
							if(!act) return;
	
							if(auto row = cast(.Row)act){
								enum prefix = "CodeLocation:";
								if(row.id.isWild(prefix~"*")){
									print("LOC:", wild[0]);
								}
							}
							foreach(sc; act.subContainers)
								visitLocations(sc); //recursive
						}
						visitLocations(actContainer);
						print("-------------------------------");+/
	
					}
	
				}else WARN("Invalid errorList");
			}
		});

	}}

	auto findErrorListItemByLocation(string locStr){
		if(auto mod = errorList) if(auto col = mod.content){

		}
	}


	string lastNearestSearchResultReference;

	Container mouseOverHintCntr;

	///must be called from root level
	void UI_mouseOverHint(){ with(im){ //UI_mouseOverHint ///////////////////////
		if(lastNearestSearchResultReference.chkSet(nearestSearchResult.reference)){
			mouseOverHintCntr = null;

			if(nearestSearchResult.reference!=""){

				if(auto mod = errorList) if(auto col = mod.content){

					const locationRef = nearestSearchResult.reference;
					foreach(row; col.rows){
						bool found = false;
						void visitLocations(.Container act){      //todo: visitor pattern for cells/containers. Similar to the allParents() thing.
							if(!act) return;

							if(auto row = cast(.Row)act){
								if(row.id==locationRef){
									found = true;
								}
							}
							foreach(sc; act.subContainers)
								visitLocations(sc); //recursive
						}

						visitLocations(row);

						if(found){
							Container({
								border = row.border;
								padding = row.padding;
								bkColor = row.bkColor;
								outerSize = row.outerSize;

								actContainer.subCells = row.subCells;
							});
							mouseOverHintCntr = removeLastContainer;
							break;
						}
					}

				}

				//if unable to generate a hint, display the SearchResult.reference:
				if(!mouseOverHintCntr){
					Text(nearestSearchResult.reference);
					mouseOverHintCntr = removeLastContainer;
				}

			}
		}

		if(mouseOverHintCntr)
			actContainer.append(mouseOverHintCntr);
	}}



	///Brings up an error message on the center of the screen for a short duration
	void flashError(string msg){
		if(msg=="") return;
		//todo: implement flashing error UI
		beep;
	}


	//! draw routines ////////////////////////////////////////////////////

	SearchResult nearestSearchResult;  //todo: MMB jumps to nearestSearchResult
	float nearestSearchResult_dist;
	RGB nearestSearchResult_color, _nearestSearchResult_ActColor;

	void resetNearestSearchResult(){
		nearestSearchResult = SearchResult.init;
		nearestSearchResult_dist = 1e30;
	}

	void updateNearestSearchResult(float dist, lazy const SearchResult sr){
		if(dist<nearestSearchResult_dist){
			nearestSearchResult_dist = dist;
			nearestSearchResult = cast()sr; //todo: constness
			nearestSearchResult_color = _nearestSearchResult_ActColor;
		}
	}

	void drawSearchResults(Drawing dr, in SearchResult[] searchResults, RGB clSearchHighLight, float extraThickness = 0){ with(dr){
		const
			arrowSize = 12+3*blink,
			arrowThickness = arrowSize*.2f,

			far = lod.level>1,
			extra = lod.pixelSize* (2.5f*blink+.5f + extraThickness),

			clamper = RectClamper(im.getView, arrowThickness*2);

		bool isVisible(in bounds2 b){ return clamper.overlaps(b); }

		//always draw these
		color = clSearchHighLight;
		_nearestSearchResult_ActColor = clSearchHighLight;

		auto mp = frmMain.view.mousePos;

		static float distanceB(in vec2 p, in bounds2 b){
			const dx = max(b.low.x - p.x, 0, p.x - b.high.x),
						dy = max(b.low.y - p.y, 0, p.y - b.high.y);
			return sqrt(dx*dx + dy*dy);
		}

		foreach(sr; searchResults) if(auto b = sr.bounds){ //todo: constness
			if(isVisible(b)){
				updateNearestSearchResult(distanceB(mp, b), sr);
				if(far){
					fillRect(b.inflated(extra));
				}else{
					lineWidth = extra;
					arrowStyle = ArrowStyle.none;
					drawRect(b);
				}
			}else{
				lineWidth = -arrowThickness -extraThickness;
				arrowStyle = ArrowStyle.arrow;

				const p = clamper.clampArrow(b.center);
				line(p);
				updateNearestSearchResult(distance(mp, p[1]), sr);
			}
		}

		arrowStyle = ArrowStyle.none;

		//later pass, draw the columns as highlighted so this will always visible
		/*if(!far){
			foreach(sr; searchResults)
				if(isVisible(sr.bounds)){
					dr.alpha = .5*blink;
					sr.drawHighlighted(dr, clSearchHighLight); //close lod
				}
		}
		dr.alpha = 1;*/
	}}

	/// A flashing effect, when right after the module was loaded.
	void drawModuleLoadingHighlights(string field)(Drawing dr, RGB c){
		const t0 = now;
		foreach(m; modules){
			const dt = (t0-mixin("m."~field)).value(2.5f*second);
			if(dt<1)
				drawHighlight(dr, m, c, sqr(1-dt));
		}
	}

	/*protected void drawSelectedModules(Drawing dr, RGB clSelected, float selectedAlpha, RGB clHovered, float hoveredAlpha){ with(dr){
		selectedModules.each!(m => drawHighlight(dr, m, clSelected, selectedAlpha));
		drawHighlight(dr, hoveredModule, clHovered, hoveredAlpha);
	}}*/

	protected void drawSelectionRect(Drawing dr, RGB clRect){
		if(auto bnd = moduleSelectionManager.selectionBounds) with(dr) {
			lineWidth = -1;
			lineStyle = LineStyle.dash;
			color = clRect;
			drawRect(bnd);
			lineStyle = LineStyle.normal;
		}
	}

	protected void drawMainModuleOutlines(Drawing dr){
		auto mm=mainModule;
		foreach(m; modules){
			if(m==mm){ dr.color = RGB(0xFF, 0xD7, 0x00); dr.lineWidth = -2.5f; dr.drawRect(m.outerBounds); }
			else if(m.isMain){ dr.color = clSilver; dr.lineWidth = -1.5f; dr.drawRect(m.outerBounds); }
			//else if(m.file.extIs(".d")){ dr.color = clSilver; dr.lineWidth = 12; dr.drawRect(m.outerBounds); }
		}
	}

	protected void drawFolders(Drawing dr, RGB clFrame, RGB clText){
		//todo: detect changes and only collect info when changed.

		const paths = modules.map!(m => m.file.path.fullPath).array.sort.uniq.array;

		foreach(folderPath; paths){
			bounds2 bnd;
			foreach(m; modules){
				const modulePath = m.file.path.fullPath;
				if(modulePath.startsWith(folderPath)){
					const intermediateFolderCount = modulePath[folderPath.length..$].filter!`a=='\\'`.walkLength;

					bnd |= m.outerBounds.inflated((1+intermediateFolderCount)*255.0f/*max font size ATM*/);
				}
			}
			if(bnd){
				dr.lineWidth = -1;
				dr.color = clFrame;
				dr.drawRect(bnd);
			}

			with(cachedFolderLabel(folderPath)){
				outerPos = bnd.topLeft - vec2(0, 255);
				draw(dr);
			}
		}
	}

	void drawModuleBuildStates(Drawing dr){
		with(ModuleBuildState) foreach(m; modules) if(m.buildState!=notInProject){
			dr.color = m.buildState.color;
			dr.lineWidth = -4;
			//if(m.buildState==compiling) dr.drawRect(m.outerBounds);
			dr.alpha = m.buildState==compiling ? mix(.15f, .55f, blink) : .15f;
			dr.fillRect(m.outerBounds);
		}
		dr.alpha = 1;
	}

	void drawTextSelections(Drawing dr, View2D view){ //drawTextSelections ////////////////////////////
		scope(exit) dr.alpha = 1;

		const
			near	= lod.zoomFactor.smoothstep(0.02, 0.1),
			clSelected	= mix(mix(RGB(0x404040), clGray, near*.66f),
											 mix(clWhite, clGray, near*.66f), blink),
			clCaret	= clSilver,
			clPrimaryCaret	= clWhite,
			alpha = mix(0.75f, .4f, near);

		const cullBounds = view.subScreenBounds_anim;

		dr.color = clSelected;
		dr.alpha = alpha;
		foreach(sel; textSelectionsGet) if(!sel.isZeroLength){
			auto col = sel.codeColumn;
			const colInnerPos = worldInnerPos(col), //opt: group selections by codeColumn.
						colInnerBounds = bounds2(colInnerPos, colInnerPos+col.innerSize);
			if(cullBounds.overlaps(colInnerBounds)){
				const localCullBounds = cullBounds - colInnerPos;
				auto st = sel.start,
						 en = sel.end;

				foreach(y; st.pos.y..en.pos.y+1){ //todo: this loop is in the copy routine as well. Must refactor and reuse
					auto row = col.rows[y];
					const rowCellCount = row.cellCount;

					//culling
					if(row.outerBottom	< localCullBounds.top   ) continue;  //opt: trisect
					if(row.outerTop	> localCullBounds.bottom) break;

					const isFirstRow	= y==st.pos.y,
								isLastRow	= y==en.pos.y;
					const x0 = isFirstRow	? st.pos.x : 0,
								x1 = isLastRow	? en.pos.x : rowCellCount+1;
					const rowInnerPos = colInnerPos + row.innerPos;

					dr.translate(rowInnerPos); scope(exit) dr.pop;

					if(lod.level<=1){
						foreach(x; x0..x1){

							void fade(bounds2 bnd){
								dr.color = clSelected;
								dr.alpha = alpha;

								enum gap = .5f;
								if(isFirstRow){ bnd.top	+= gap; if(x==x0  ) bnd.left	+= gap; }
								if(isLastRow ){ bnd.bottom	-= gap; if(x==x1-1) bnd.right	-= gap; }
								dr.fillRect(bnd);
							}

							assert(x.inRange(0, rowCellCount), "out of range");
							if(x<rowCellCount){
								//todo: make the nice version: the font will be NOT blended to gray, but it hides the markerLayers completely. Should make a text drawer that uses alpha on the background and leaves the font color as is.
								/+if(auto g = row.glyphs[x]){
									const old = tuple(g.bkColor, g.fontColor);
									g.bkColor = mix(g.bkColor, clSelected, alpha);// g.fontColor = clBlack;
									dr.alpha = 1;
									g.draw(dr);
									g.bkColor = old[0]; g.fontColor = old[1];
								}else+/{
									fade(row.subCells[x].outerBounds);
								}
							}else{ //newLine
								auto g = newLineGlyph;
								g.bkColor = row.bkColor;  g.fontColor = clGray;
								dr.alpha = 1;
								g.outerPos = row.newLinePos;
								g.draw(dr);

								fade(g.outerBounds);
							}
						}

					}else{
						if(!isFirstRow && !isLastRow){
							if(row.cellCount)
								dr.fillRect(bounds2(0, 0, row.subCells.back.outerRight, row.innerHeight));
						}else{
							dr.fillRect(bounds2(row.localCaretPos(x0).pos.x, 0, row.localCaretPos(x1).pos.x, row.innerHeight));
						}

					}
				}

			}
		}

		//caret trail
		version(AnimatedCursors){
			if(textSelectionsGet.length <= MaxAnimatedCursors){
				dr.alpha = blink/2;
				dr.lineWidth = -1-(blink)*3;
				dr.color = clCaret;
				//opt: culling
				//opt: limit max munber of animated cursors
				foreach(s; textSelectionsGet){
					CaretPos[3] cp;
					cp[0] = s.caret.worldPos;
					cp[1..3] = cp[0];
					cp[2].pos += s.caret.animatedPos - s.caret.targetPos;
					cp[1].pos = mix(cp[0].pos, cp[2].pos, .25f);
					//todo: animate caret height too

					auto dir = cp[1].pos-cp[2].pos; //todo: center them on height
					if(dir){
						if(dir.normalize.x.abs<0.05f){ //vertical line
							vec2[2] p = [cp[1].pos, cp[2].pos];
							if(p[0].y<p[1].y)	p[1].y += cp[2].height;
							else	p[0].y += cp[1].height;
							dr.line(p[0], p[1]);
						}else{ //horizontal bar
							vec2[4] p;
							p[0] = cp[1].pos;
							p[1] = cp[1].pos + vec2(0, cp[1].height);
							p[2] = cp[2].pos + vec2(0, cp[2].height);
							p[3] = cp[2].pos;

							if(p[0].x<p[3].x)	{ dr.fillTriangle(p[0], p[1], p[3]); dr.fillTriangle(p[1], p[2], p[3]); }
							else	{ dr.fillTriangle(p[3], p[2], p[0]); dr.fillTriangle(p[2], p[1], p[0]); }
						}
					}
				}
			}
		}


		{
			const clamper = RectClamper(view, 7*blink+2);

			auto getCaretWorldPos(TextSelection ts){
				CaretPos res = ts.caret.worldPos;

				if(!clamper.overlaps(res.bounds)){
					res.pos = clamper.clamp(res.center);
					res.height = lod.pixelSize;
				}

				return res;
			}

			auto carets = textSelectionsGet.map!getCaretWorldPos.array;

			void drawCarets(RGB c, float shadow=0){
				dr.alpha = blink;
				dr.lineWidth = -1-(blink)*3 -shadow;
				dr.color = c;
				foreach(cwp; carets) cwp.draw(dr);
			}

			drawCarets(clBlack, 3);	//shadow
			drawCarets(clCaret);	//inner

			//primary
			if(auto ts = primaryTextSelection){
				dr.color = clPrimaryCaret;
				getCaretWorldPos(ts).draw(dr);
			}
		}

	}

	override void onDraw(Drawing dr){ //onDraw //////////////////////////////
		if(textSelectionsGet.empty){ //select means module selection
			foreach(m; modules) if(m.flags.selected) drawHighlight(dr, m, clAccent, .25);
			if(!lod.codeLevel) { if(0/+ It's annoying, so I disabled it.+/) drawHighlight(dr, hoveredModule, clWhite, .125);  }
		}else{ //select means text editing
			foreach(m; modules) if(!m.flags.selected) drawHighlight(dr, m, clGray, .25);
		}

		if(lod.moduleLevel || frmMain.building) drawModuleBuildStates(dr);

		drawModuleLoadingHighlights!"fileLoaded"(dr, clAqua  );
		drawModuleLoadingHighlights!"fileSaved" (dr, clYellow);

		drawMainModuleOutlines(dr);
		drawFolders(dr, clGray, clWhite);
		drawSelectionRect(dr, clWhite);

		resetNearestSearchResult;
		foreach_reverse(t; EnumMembers!BuildMessageType)
			if(markerLayers[t].visible)
				drawSearchResults(dr, markerLayers[t].searchResults, t.color);

		if(nearestSearchResult_dist > frmMain.view.invScale*24) nearestSearchResult = SearchResult.init;

		if(nearestSearchResult.bounds){
			drawSearchResults(dr, [nearestSearchResult], nearestSearchResult_color.mix(clWhite, .5f));
		}
		
		.draw(dr, globalChangeindicatorsAppender[]); globalChangeindicatorsAppender.clear;
		
		drawTextSelections(dr, frmMain.view); //bug: this will not work for multiple workspace views!!!
	}

	override void draw(Drawing dr){
		globalChangeindicatorsAppender.clear;
		
		structureMap.beginCollect;
		super.draw(dr);
		structureMap.endCollect(dr);
	}

	// Test functions ///////////////////////////////////////
	
	void test_insert(){
		auto ts = textSelectionsGet;
		if(ts.length==1){
			auto sel = ts.front;
			if(sel.valid){
				if(auto row = sel.codeColumn.getRow(sel.caret.pos.y)){
					row.insertSomething(sel.caret.pos.x, {
						//row.append(new CodeComment(row, CommentType.slash, "Comment"));
						
						row.moduleOf.print;
						(cast(const)row).moduleOf.print;
						(cast(const)row).thisAndAllParents.each!print;
						
					});
				}
			}
		}
	}
	
	
	void test_structureMap(){
		foreach(m; selectedModules){
			if(m.isStructured){
				processHighLevelPatterns(m.content);
				m.structureLevel = StructureLevel.managed;
			};
			//m.content.needMeasure;
			//m.content.measure;
			//m.isStructured = true;
			//m.reload;
		}
		
		structureMap.debugTrigger = true;
	}
	
	
	void test_resyntax(){
		//foreach(m; modulesWithTextSelection) if(m) m.resyntax; //todo: realing the lines where font.bold has changed.
		
	}
	
	void test_declarationStatistics(){
		auto files = dirPerS(Path(`c:\d`), "*.d").files.map!"a.file".array;
		//auto files = [File(`c:\d\libs\het\test\testTokenizerData\CompilerTester.d`)];
		dDeclarationRecords.clear;
		foreach(i, f; files){
			print(i, files.length, dDeclarationRecords.length, f);
			auto m = scoped!Module(this, f);
			if(m.isStructured){
				m.content.processHighLevelPatterns;
			}else	{ print("Is not structured"); beep; }
		}
		dDeclarationRecords.toJson.saveTo(`c:\D\projects\DIDE\DLangStatistics\dDeclarationRecords.json`);
		print("DONE.");
		
		//todo: implement identifier qString  File(`c:\D\ldc2\import\std\json.d`) File(`c:\D\ldc2\import\std\xml.d`) File(`c:\D\ldc-master\tools\ldc-prune-cache.d`) Invalid block closing token
		//bad tokenString, not my bad...  File(`c:\D\ldc-master\dmd\iasmgcc.d`) File(`c:\D\ldc-master\dmd\mars.d`) Invalid block closing token
		
	}

	
	
}


// MainOverlay //////////////////////////////////////////////////////////
class MainOverlayContainer : het.uibase.Container{
	this(){ flags.targetSurface = 0; }
	override void onDraw(Drawing dr){
		frmMain.drawOverlay(dr);
	}
}


// CellInfo ////////////////////////////////////////////

struct CellInfoStruct{
	Cell cell;
	
	string toString(){
		
		auto adjustStr(string s){ return (s.empty || s.canFind('\n')) ? s.quoted : s; }
		auto containerStr(CodeContainer c, string name){ return name ~ adjustStr(c.prefix ~ c.postfix); }
		
		return cell.castSwitch!(
			(Module	a) => "module", //m.file.name,
			(Declaration	a) => adjustStr(a.type ~ (a.opening.text~a.ending).strip),
			(CodeComment	a) => containerStr(a, "comment"),
			(CodeString	a) => containerStr(a, "string"),
			(CodeBlock	a) => containerStr(a, "block"),
			(CodeColumn	a) => "\u25a4",
			(CodeRow	a) => "\u25a5",
			(Glyph 	a) => a.ch<128 ? a.ch.text.quoted: '"'~a.ch.text~'"',
			(Cell	a) => typeid(a).name,
			(	 ) => "null"
		);
	}
}

auto cellInfo(Cell cl)	{ return cl.CellInfoStruct; 	}
auto cellInfo(CellLocation cl)	{ return cl.cell.CellInfoStruct; 	}

auto cellInfoText(T)(T a){ return a.cellInfo.text; }

//! FrmMain ///////////////////////////////////////////////

class FrmMain : GLWindow { mixin autoCreate;
	
	@STORED{
		bool mainMenuOpened;
	}
	
	Workspace workspace;
	MainOverlayContainer overlay;

	Tid buildSystemWorkerTid;

	BuildResult buildResult; //collects buildMessages and output

	Path workPath = Path(`z:\temp2`);

	File workspaceFile;
	bool initialized; //workspace has been loaded.
	
	string baseCaption;
	bool isSpecialVersion; //This is a copy of the .exe that is used to cimpile dide2.exe

	@VERB("Alt+F4")       void closeApp            (){ PostMessage(hwnd, WM_CLOSE, 0, 0); }

	bool building()	const{ return buildSystemWorkerState.building; }
	bool ready()	const{ return !buildSystemWorkerState.building; }
	bool cancelling()	const{ return buildSystemWorkerState.cancelling; }
	bool running()	const{ return false; } //todo: debugServer

	void initBuildSystem(){
		buildResult = new BuildResult;
		buildSystemWorkerTid = spawn(&buildSystemWorker);
	}

	void updateBuildSystem(){
		buildResult.receiveBuildMessages; //todo: it's only good for ONE workspace!!!
	}

	void destroyBuildSystem(){
		buildSystemWorkerTid.send(MsgBuildCommand.shutDown);

		if(building){
			LOG("Waiting for buildsystem to shut down.");
			while(building){ write('.'); sleep(100); }
		}
	}

	void launchBuildSystem(string command)(){
		static assert(command.among("rebuild", "run"), "Invalid command `"~command~"`");
		if(building){ beep; return ; }

		if(!workPath.exists) workPath.make;

		BuildSettings bs = {
			killExe	 : true,
			rebuild	 : command=="rebuild",
			verbose	 : false,
			compileOnly : command=="rebuild",
			workPath : this.workPath.fullPath,
			collectTodos : false,
			generateMap : true,
			compileArgs : ["-wi"],  // "-v" <- not good: it also lists all imports
		};

		void addOpt(string o){ if(o.length) bs.compileArgs.addIfCan(o);}

		buildSystemWorkerTid.send(cast(immutable)MsgBuildRequest(workspace.mainModuleFile, bs));
		//todo: immutable is needed because of the dynamic arrays in BuildSettings... sigh...
	}

	void run(){
		dbgsrv.resetBeforeRun;
		launchBuildSystem!"run";
	}

	void rebuild(){
		dbgsrv.resetBeforeRun;
		launchBuildSystem!"rebuild";
	}

	void cancelBuildAndResetApp(){
		if(building) buildSystemWorkerTid.send(MsgBuildCommand.cancel);

		dbgsrv.forcedStop;

		//todo: kill app
		//todo: debugServer
	}

	override void onCreate(){ //onCreate //////////////////////////////////
		baseCaption = appFile.nameWithoutExt.uc;
		isSpecialVersion = baseCaption != "DIDE2";
		
		{ auto a = this; a.fromJson(ini.read("settings", "")); } //todo: this.fromJson
		
		initBuildSystem;
		workspace = new Workspace;
		workspaceFile = appFile.otherExt(Workspace.defaultExt);
		overlay = new MainOverlayContainer;
		
		
	}

	override void onDestroy(){
		ini.write("settings", this.toJson);
		if(initialized) workspace.saveWorkspace(workspaceFile);
		workspace.destroy;
		destroyBuildSystem;
	}

	void onDebugLog      (string s){ LOG("DBGLOG:", s); }
	void onDebugException(string s){ LOG("DBGEXC:", s); }

	override void onUpdate(){ // onUpdate ////////////////////////////////////////
		//showFPS = true;
		//im.focus
		dbgsrv.onDebugLog = &onDebugLog;
		dbgsrv.onDebugException = &onDebugException;

		dbgsrv.update;

		if(frmMain.isForeground && view.isMouseInside && (inputs.LMB.pressed || inputs.RMB.pressed)){ im.focusNothing; }

		updateBlink;

		updateBuildSystem;

		if(application.tick>5 && initialized.chkSet){
			test_CodeColumn;
			if(workspaceFile.exists){
				workspace.loadWorkspace(workspaceFile);
			}
		}

		invalidate; //todo: low power usage
		caption = format!"%s - [%s]%s %s"(baseCaption, workspace.mainModuleFile.fullName, workspace.modules.any!"a.changed" ? "CHG" : "", dbgsrv.pingLedStateText);
		
		//view.navigate(false/+disable keyboard navigation+/ && !im.wantKeys && !inputs.Ctrl.down && !inputs.Alt.down && isForeground, false/+worksheet.update handles it+/!im.wantMouse && isForeground);
		view.updateSmartScroll;
		setLod(view.scale_anim);

		if(canProcessUserInput) callVerbs(this);

		// Menu //////////////////////////////////////////////
		if(1) with(im) Panel(PanelPosition.topLeft, { margin = "0"; padding = "0";// border = "1 normal gray";
			Row({
				if(Btn("\u2630")) mainMenuOpened.toggle;
				
				if(mainMenuOpened){
					
					with(workspace){
						auto B(string srcModule = __FILE__, size_t srcLine = __LINE__, A...)(string kc, A args){
							return Btn!(srcModule, srcLine)({ Text(kc, " ", args); }, KeyCombo(kc)); 
						}
						
						if(B("F1", "insert"	)) test_insert;
						if(B("F2", "StructureMap"	)) test_structureMap;
						if(B("F3", "resyntax"	)) test_resyntax;
						if(B("F4", "declaration"	)) test_declarationStatistics;
					}
					
				}
			});
		});

		if(0) with(im) Panel(PanelPosition.topClient, { margin = "0"; padding = "0";// border = "1 normal gray";
			Row({ //todo: Panel should be a Row, not a Column...
				Row({ workspace.UI_ModuleBtns; flex = 1; });
			});
		});

		with(im) Panel(PanelPosition.topRight, { margin = "0"; padding = "0";
			workspace.UI_SearchBox(view);
		});

		if(0) with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
			Row({
				Text(hitTestManager.lastHitStack.map!(a => "["~a.id~"]").join(` `));
				NL;
				if(hitTestManager.lastHitStack.length) Text(hitTestManager.lastHitStack.back.text);

				Text("\n", workspace.locate_snapToRow(view.mousePos).text);
			});
		});

		//undo debug
		if(0) with(im) with(workspace) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
			if(auto m = moduleWithPrimaryTextSelection){
				Container({
					flags.hScrollState = ScrollState.auto_;
					actContainer.appendCell(m.undoManager.createUI);
				});
			}
		});

		if(0) with(im) with(workspace) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
			Column({
				UI_ResyntaxQueue;
			});
		});

		//error list
		if(workspace.showErrorList) with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";// border = "1 normal gray";
			outerHeight = 200;

			workspace.UI_ErrorList;
		});

		void VLine(){ with(im) Container({ innerWidth = 1; innerHeight = fh; bkColor = clGray; }); }

		
		
		//StatusBar
		with(im) Panel(PanelPosition.bottomClient, { margin = "0"; padding = "0";
			Row({
				/*theme = "tool";*/ style.fontHeight = 18;

				//todo: faszomat ebbe a szarba:
				flags.vAlign = VAlign.center;  //ha ez van, akkot a text kozepre megy, de a VLine nem latszik.
				//flags.yAlign = YAlign.stretch; //ha ez, akkor meg a VLine ki van huzva.

				Row({ margin = "0 3"; flags.yAlign = YAlign.center;
					//style.fontHeight = 18+6;
					buildSystemWorkerState.UI;
				});

				VLine;//---------------------------

				Row({ flex = 1; margin = "0 3"; flags.yAlign = YAlign.center; flags.clipSubCells = true;
					//style.fontHeight = 18+6;

					if(lod.moduleLevel ) workspace.UI_selectedModulesHint;
					if(!lod.moduleLevel) workspace.UI_mouseLocationHint(view);
					
					Text("\n");
					
					Text(workspace.locate(view.mousePos).map!cellInfoText.join(' '));
				});

				VLine;//---------------------------

				Row({ margin = "0 3"; flags.yAlign = YAlign.center;
					foreach(t; EnumMembers!BuildMessageType){
						workspace.UI(t, view);
					}
				});
				VLine;//---------------------------

				Row({ margin = "0 3"; flags.vAlign = VAlign.center;
					if(Btn("ErrorList")) workspace.showErrorList.toggle;
					if(Btn("Calc size")) print(workspace.allocatedSize);
					Text(now.text);
					Text(" "~log2(lod.pixelSize).format!"%.2f");
				});

				//this applies YAlign.stretch
				with(actContainer){
					measure;
					foreach(c; cast(.Container[])subCells) c.measure;
				}

			});
		});

		im.root ~= workspace;
		im.root ~= overlay;

		view.subScreenArea = im.clientArea / clientSize;

		workspace.update(view, buildResult);

		//bottomRight hint
		with(im) Panel(PanelPosition.bottomRight, {
			margin = "0 24 24 0";
			border = Border.init;
			padding = "0";
			flags.noBackground = true;
			workspace.UI_mouseOverHint;
		});

		//update mouse cursor//////////////////////////
		MouseCursor chooseMouseCursor(){ with(MouseCursor){
			if(cancelling) return NO;
			if(building) return APPSTARTING;
			if(im.mouseOverUI || im.wantMouse) return ARROW; //todo: im.chooseMouseCursor
			with(workspace.moduleSelectionManager){
				if(mouseOp == MouseOp.move) return SIZEALL;
				if(mouseOp == MouseOp.rectSelect) return CROSS;
			}
			if(workspace.textSelectionsGet.any) return IBEAM; //bug: ez az IBeam a form jobb oldalan eltunik pont annyi pixelnyire az ablak jobb szeletol, mint ahany pixelre az ablak bal szele van a desktop bal szeletol merve.
			return ARROW;
		}}

		mouseCursor = chooseMouseCursor;
		
		//print(lod.zoomFactor*DefaultFontHeight);
	}

	override void onPaint(){ // onPaint ///////////////////////////////////////
		gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT);
	}


	void drawOverlay(Drawing dr){
		//dr.mmGrid(view);
		
		enum visualizeMarginsAndPaddingUnderMouse = false; //todo: make this a debug option in a menu
		
		dr.alpha = .5f;
		dr.lineWidth = -1;
		if(visualizeMarginsAndPaddingUnderMouse) foreach(cl; workspace.locate(view.mousePos)){
			auto rOuter 	= cl.globalOuterBounds;
			auto rMargin 	= rOuter;	cl.cell.margin.apply(rMargin);
			auto rInner 	= rMargin; 	cl.cell.padding.apply(rInner);
			
			/*dr.color = clRed	; dr.drawRect(rOuter);
			dr.color = clGreen	; dr.drawRect(rMargin);
			dr.color = clBlue	; dr.drawRect(rInner);*/
			
			void drawDiff(bounds2 o, bounds2 i){
				if(o.top 	!= i.top	) dr.fillRect(o.left, o.top, o.right, i.top);
				if(o.bottom 	!= i.bottom	) dr.fillRect(o.left, i.bottom, o.right, o.bottom);
				if(o.left 	!= i.left	) dr.fillRect(o.left, i.top, i.left, i.bottom);
				if(o.right 	!= i.right	) dr.fillRect(i.right, i.top, o.right, i.bottom);
			}
			
			dr.color = clWhite; dr.drawRect(rOuter);
			dr.color = clWhite; dr.drawRect(rMargin);
			dr.color = clWhite; dr.drawRect(rInner);
			dr.color = clYellow; drawDiff(rOuter, rMargin);
			dr.color = clAqua; drawDiff(rMargin, rInner);
			
		}
		
		/*if(workspace.changed) foreach(m; workspace.modules) if(m.changed){
			LOG(m.file);
		} */
	}

	override void afterPaint(){ // afterPaint //////////////////////////////////
	}

}

//todo: search in std, core, etc
//todo: winapi help search


