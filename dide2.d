//@exe
//@compile --d-version=stringId,AnimatedCursors

//@release
//@debug

/+
	Todo: this crashes the StructureScanner:
	
				}
				
				__gshared const LodStruct lod;
				
				void setLod(float zoomFactor_)
				{
					with(cast(LodStruct*)(&lod))
					{
						zoomFactor = zoomFactor_;
						pixelSize = 1/zoomFactor;
						level = pixelSize>6 ? 2 :
										pixelSize>2 ? 1 : 0;
				
						codeLevel = level==0;
			
	
+/

//Todo: Multiline todo's
//Todo: Ability to change comment type // /+ /*  and also todo: note: bug:
//Todo: Ability to change the whitespace after a proposition: space, tab, newline
//Todo: Handle exceptions.
//Todo: longpressing Ctrl+F2 kill ldc2 processes.
//Todo: Insert unicode chars from other apps.  https://www.amp-what.com/unicode/search/watch
//Todo: Easily Reduce Build Times by Profiling the D Compiler   profiling the LDC2 compiler.
//Todo: WYSIWYG printf editor plan  (emailek kozott)
//Todo: automatic spaces around operators and ligatures.
//Todo: automatic space after ;
//Todo: toggle space/tab/newline after prepositions.
//Todo: Alt+F4 akkor is mukodik, ha nem a DIDE a focused, argh...
version(/+$DIDE_REGION main+/all)
{
	version(/+$DIDE_REGION Todo+/all)
	{
		
		//Note: debug is not needed to get proper exception information
		
		//Todo: buildSystem: the caches (objCache, etc) has no limits. Onli a rebuild clears them.
		
		//Todo: wholeWords search (eleje/vege kulon)
		//Todo: filter search results per file and per syntax (comment, string, code, etc)
		
		//Todo: Adam Ruppe search tool -> http://search.dpldocs.info/?q=sleep
		
		//Todo: het.math.cmp integration with std
		
		//Todo: accept repeared keystrokes even when the FPS is low. (Ctrl+X Shift+Del Del Backspace are really slow now.)
		
		//Todo: cs Kod szerkesztonek feltetlen csinald meg, hogy kijelolt szovegreszt kulon ablakban tudj editalni tobb ilyen lehessen esetleg ha egy fuggveny felso soran vagy akkor automatikusan rakja ki a fuggveny torzset
		//Todo: cs lehessen splittelni: pl egyik tab full kod full scren, a masik tabon meg splittelve ket fuggveny
		
		//Todo: Ctrl+ 1..9		 Copy to clipboard[n]       Esetleg Ctrl+C+1..9
		//Todo: Alt + 1..9		 Paste from clipboard[n]
		//Todo: Ctrl+Shift 1..9   Copy to and append to clipboard[n]
		
		//Todo: unstructured syntax highlight optimization: save and reuse tokenizer internal state on each source code blocks. No need to process ALL the source when the position of the modification is known.
		
		//Todo: unstructured view: fake local syntax highlight addig, amig a bacground syntax highlighter el nem keszul.
		//Todo: unstructured view: immediate syntax highlight for smalles modules.
		
		//Todo: save/restore buildsystem cache on start/exit
		//Todo: nem letezo modul import forditasakor CRASH
		
		//Todo: Find: display a list of distinct words around the searched text. AKA Autocomplete for search.
		//Todo: DIDE syntax highlight vector .rgba postfixes
		//Todo: kinetic scroll
		
		//Todo: module hierarchy detector should run ARFTER save when pressing F9 (Not before when the contents is different in the file and in the editor)
		
		//Todo: frame time independent lerp for view.zoomAroundMouse() https://youtu.be/YJB1QnEmlTs?t=482
		
		//Todo: Search: x=12  match -> x =12,	x =  12 too. Automatic whitespaces.
		//Todo: Structure error visibility: In	Highighted view, mark the onclosed brackets too. Not just the wrong brackets. c:\dl\broken_structure.d
		//Bug: F9 -> invalid character FEFF (utf8 BOM)
		//Todo: isUniAlpha support	(C99 identifier char set)
		//Todo: MB4 MB5 should only	zoom when mouse is over the screen, not when over other windows.
		
		//Todo: markdown a commentekben.
		
		/+
			Todo: Nagy blokkok mellett a magas zarojelek stretchelese: 
						a) A ()[] a kozepen van megtoldva.
						b) A {} a felso es also harmadanal van megtoldva.
						c) A () a felso es also negyede kozott ciklikusan ismetelgetve van
						d) A {} a felso es also harmadanal meg is van toldva illetve a kozepe ciklikusan ismetelgetve van.
		+/
		
		//Todo: implement culling for Container. Can be tested using Workspace.
		
		//Todo: handle newline before and after else.
		//Todo: switch(c){ static foreach(a; b) case a[0]: return a[1]; default: return 0; }    <- It case label must suck statement into it. Not just sop at the :
		//Todo: tab removal from the left side of multiline comments
		
		//Todo: dbgsrv: Disable debugLogClient in DIDE2
		//Todo: dbgsrv: Use a trick (command line) to specify the client should have to connect somewhere
		
		//Todo: search in std, core, etc
		//Todo: winapi help search
		
		//Todo: BOM handling in copy/paste operations
		
		//Todo: inline struct.  Use it to model persistent and calculated fields of a struct/class  -> DConf Online '22 - Model all the Things!
		
		/+
			Todo: Properly handle Noman's land between preposition and the statement next to. It could be space, tab, newline with optional comments.
			Verify it still works in between adjacent preposition.
		+/
		//Todo: Managed level: Multiline //comment at a statement is commenting out the ; symbol at the end.
		//Todo: selection across miltiple pages (vertical tab) is clipped wrongly
		
		//Todo: Implement q"a ... a" identifier-qstring handling in new DIDE DLang Scanner.
		/+
			Todo: CharSetBits is an example to a divergent export import operation. Every save it prepends more tabs in front of it. Delimited string bug.
				const str = q"/ NEWLINE TAB blabla NEWLINE TAB/"; 
		+/
		//Todo: On bracket errors, it should mark the opening bracket too. In the scannet there should be a way to remember the opening brackets in a stack.
		
		//Todo: Szerenyebb legyen az atomvillanas effekt! (module highlight, bele a settingsbe!)
		
		//Todo: Billentyuzetkiosztás beállíthatósága ()
		//Todo: Vízszintes elválasztó vona (Függôleges elválasztó vonal már van: Vertical Tab, azaz a hasábra tördelés)
		//Todo: Specialis karakter: Innentôl jobbra igazítás. Kellene ilyen tipusu Elastic Tab is a számokhoz. Elastic tabs, ami a balra levo szamot jobbra huzza. Ezt ki kell találni, nem kerek.
	}
	
	//globals ////////////////////////////////////////
	
	import het, het.parser, het.ui; 
	import buildsys, core.thread, std.concurrency; 
	
	import didemodule; 
	
	enum LogRequestPermissions	= false; 
	
	enum visualizeMarginsAndPaddingUnderMouse = false; //Todo: make this a debug option in a menu
	
	alias blink = didemodule.blink; 
	
	auto frmMain()
	{ return (cast(FrmMain)mainWindow); } 
	
	auto global_getBuildResult()
	{ return frmMain.buildResult; } 
	
	auto global_getMarkerLayerHideMask()
	{ return frmMain.workspace.markerLayerHideMask; } 
	
	size_t allocatedSize(in Cell c)
	{
		if(!c) return 0; 
		import core.memory; 
		size_t res = GC.sizeOf(cast(void*)c); 
		if(auto co = cast(const Container)c)
		{ res += co.subCells.map!(allocatedSize).sum; }
		return res; 
	} 
	
	//MainOverlay //////////////////////////////////////////////////////////
	class MainOverlayContainer : het.ui.Container {
		this()
		{ flags.targetSurface = 0; } 
		override void onDraw(Drawing dr)
		{ frmMain.drawOverlay(dr); } 
	} 
	
	
	//CellInfo ////////////////////////////////////////////
	
	struct CellInfoStruct
	{
		Cell cell; 
		
		string toString()
		{
			
			auto adjustStr(string s)
			{ return (s.empty || s.canFind('\n')) ? s.quoted : s; } 
			auto containerStr(CodeContainer c, string name)
			{ return name ~ adjustStr(c.prefix ~ c.postfix); } 
			
			return cell.castSwitch!(
				(Module a) 	=> "module", //m.file.name,
				(Declaration a) 	=> adjustStr(a.type ~ (a.opening.text~a.ending).strip),
				(CodeComment a) 	=> containerStr(a, "comment"),
				(CodeString a) 	=> containerStr(a, "string"),
				(CodeBlock a) 	=> containerStr(a, "block"),
				(CodeColumn a) 	=> "\u25a4",
				(CodeRow a) 	=> "\u25a5",
				(Glyph  a) 	=> a.ch<128 ? a.ch.text.quoted: '"'~a.ch.text~'"',
				(Cell a) 	=> typeid(a).name,
				() 	=> "null"
			); 
		} 
	} 
	
	auto cellInfo(Cell cl)
	{ return cl.CellInfoStruct; } 
	auto cellInfo(CellLocation cl)
	{ return cl.cell.CellInfoStruct; } 
	
	auto cellInfoText(T)(T a)
	{ return a.cellInfo.text; } 
	
	//! FrmMain ///////////////////////////////////////////////
	
	class FrmMain : GLWindow
	{
		mixin autoCreate; 
		version(/+$DIDE_REGION+/all)
		{
			
			
			@STORED { bool mainMenuOpened; } 
			
			Workspace workspace; 
			MainOverlayContainer overlay; 
			
			Tid buildSystemWorkerTid; 
			
			BuildResult buildResult; //collects buildMessages and output
			
			Path workPath = Path(`z:\temp2`); 
			
			File workspaceFile; 
			bool initialized; //workspace has been loaded.
			
			string baseCaption; 
			bool isSpecialVersion; //This is a copy of the .exe that is used to cimpile dide2.exe
			
			@VERB("Alt+F4") void closeApp()
			{ import core.sys.windows.windows; PostMessage(hwnd, WM_CLOSE, 0, 0); } 
			
			bool building()const
			{ return buildSystemWorkerState.building; } 
			bool ready()const
			{ return !buildSystemWorkerState.building; } 
			bool cancelling()const
			{ return buildSystemWorkerState.cancelling; } 
			bool running()const
			{ return false; /+Todo: debugServer+/} 
			
			void initBuildSystem()
			{
				buildResult = new BuildResult; 
				buildSystemWorkerTid = spawn(&buildSystemWorker); 
			} 
			
			void updateBuildSystem()
			{
				buildResult.receiveBuildMessages; 
				//Todo: it's only good for ONE workspace!!!
			} 
			
			void destroyBuildSystem()
			{
				buildSystemWorkerTid.send(MsgBuildCommand.shutDown); 
				
				if(building)
				{
					LOG("Waiting for buildsystem to shut down."); 
					while(building) { write('.'); sleep(100); }
				}
			} 
			
			void launchBuildSystem(string command)()
			{
				static assert(command.among("rebuild", "run"), "Invalid command `"~command~"`"); 
				if(building)
				{ beep; return; }
				
				if(!workPath.exists) workPath.make; 
				
				BuildSettings bs = {
					killExe	: true,
					rebuild	: command=="rebuild",
					verbose	: false,
					compileOnly	: command=="rebuild",
					workPath	: this.workPath.fullPath,
					collectTodos	: false,
					generateMap 	: true,
					compileArgs	: ["-wi"], /+"-v" <- not good: it also lists all imports+/
					dideDbgEnv	: dbgsrv.getDataFileName
				}; 
				
				void addOpt(string o)
				{ if(o.length) bs.compileArgs.addIfCan(o); } 
				
				buildSystemWorkerTid.send(cast(immutable)MsgBuildRequest(workspace.mainModuleFile, bs)); 
				//Todo: immutable is needed because of the dynamic arrays in BuildSettings... sigh...
			} 
			
			void resetDbg()
			{
				resetGlobalWatches; 
				dbgsrv.resetBeforeRun; 
			} 
			
			void run()
			{
				resetDbg; 
				launchBuildSystem!"run"; 
			} 
			
			void rebuild()
			{
				resetDbg; 
				launchBuildSystem!"rebuild"; 
			} 
			
			void cancelBuildAndResetApp()
			{
				if(building) buildSystemWorkerTid.send(MsgBuildCommand.cancel); 
				
				dbgsrv.forcedStop; 
				resetDbg; 
				
				//Todo: kill app
				//Todo: debugServer
			} 
			
			override void onCreate()
			{
				//onCreate //////////////////////////////////
				baseCaption = appFile.nameWithoutExt.uc; 
				isSpecialVersion = baseCaption != "DIDE2"; 
				
				{ auto a = this; a.fromJson(ini.read("settings", "")); }//Todo: this.fromJson
				
				initBuildSystem; 
				workspace = new Workspace; 
				workspaceFile = appFile.otherExt(Workspace.defaultExt); 
				overlay = new MainOverlayContainer; 
			} 
			
			override void onDestroy()
			{
				ini.write("settings", this.toJson); 
				if(initialized) workspace.saveWorkspace(workspaceFile); 
				workspace.destroy; 
				destroyBuildSystem; 
			} 
			
			void onDebugLog(string s)
			{
				if(s.isWild("PR(?*(?*)):*"))
				{
					const id = wild[0]~'('~wild[1]~')'; 
					const value = (cast(string)(wild[2].fromBase64)).ifThrown("BASE64 Error"); 
					globalWatches.require(id, Watch(id)).update(value); 
					
					print("Received:", globalWatches[id]); 
				}
				else
				LOG("DBGLOG:", s); 
			} 
			
			void onDebugException(string s)
			{ LOG("DBGEXC:", s); } 
			
			
			
			////////////////////////////////////////////////////////////////////////////////////////////////////
			
			
			
			override void onPaint()
			{
				//onPaint ///////////////////////////////////////
				gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT); 
			} 
			
			void drawOverlay(Drawing dr)
			{
				if(0) dr.mmGrid(view); 
				
				dr.alpha = .5f; 
				dr.lineWidth = -1; 
				if(visualizeMarginsAndPaddingUnderMouse)
				foreach(cl; workspace.locate(view.mousePos.vec2))
				{
					auto rOuter 	= cl.globalOuterBounds; 
					auto rMargin 	= rOuter; 	cl.cell.margin.apply(rMargin); 
					auto rInner 	= rMargin; 	cl.cell.padding.apply(rInner); 
					
					/*
						dr.color = clRed	; dr.drawRect(rOuter);
						dr.color = clGreen	; dr.drawRect(rMargin);
						dr.color = clBlue	; dr.drawRect(rInner);
					*/
					
					void drawDiff(bounds2 o, bounds2 i)
					{
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
				
				/*
					if(workspace.changed) foreach(m; workspace.modules) if(m.changed){
										LOG(m.file);
									} 
				*/
			} 
			
			override void afterPaint()
			{
				//afterPaint //////////////////////////////////
			} 
			
		}version(/+$DIDE_REGION+/all)
		{
					
			override void onUpdate()
			{
				 //onUpdate ////////////////////////////////////////
				//showFPS = true;
				//im.focus
				
				version(/+$DIDE_REGION update a virtual file from clipboard+/all) {
					static uint id; 
					if(id.chkSet(clipboard.sequenceNumber))
					File(`virtual:\clipboard.txt`).write(clipboard.text); 
					//Todo: sinchronize the clipboard both ways.
					//Todo: don't load too big files. And most importantly don't crash.
				}
				
				dbgsrv.onDebugLog = &onDebugLog; 
				dbgsrv.onDebugException = &onDebugException; 
				
				dbgsrv.update; 
				_updateTestProbe; 
				
				if(frmMain.isForeground && view.isMouseInside && (inputs.LMB.pressed || inputs.RMB.pressed))
				{ im.focusNothing; }
				
				updateBlink; 
				
				updateBuildSystem; 
				
				if(application.tick>5 && initialized.chkSet)
				{
					CodeColumn.selfTest; 
					if(workspaceFile.exists) { workspace.loadWorkspace(workspaceFile); }
				}
				
				invalidate; //Todo: low power usage
				caption = format!"%s - [%s]%s %s"(
					baseCaption,
					workspace.mainModuleFile.fullName,
					workspace.modules.any!"a.changed" ? "CHG" : "",
					dbgsrv.pingLedStateText
				); 
				
				/+
					view.navigate(false/+disable keyboard navigation+/ && !im.wantKeys && !inputs.Ctrl.down 
					&& !inputs.Alt.down && isForeground, false/+worksheet.update handles it+/!im.wantMouse && isForeground);
				+/
				view.updateSmartScroll; 
				setLod(view.scale_anim); 
				
				if(canProcessUserInput) callVerbs(this); 
				
				//Menu //////////////////////////////////////////////
				if(1)
				with(im)
				Panel(
					PanelPosition.topLeft, 
					{
						if(!mainMenuOpened) {
							margin = "0"; padding = "0"; /+border = "1 normal gray";+/
							if(Btn("\u2630")) mainMenuOpened = true; 
						}else
						{
							Row({ if(Btn("\u2630")) mainMenuOpened = false; }); 
							with(workspace)
							{
								auto B(string srcModule = __FILE__, size_t srcLine = __LINE__, A...)(string kc, A args)
								{ return Btn!(srcModule, srcLine)({ Text(kc, " ", args); }, /+KeyCombo(kc)+/); } 
								
								Grp!Row(
									"Vertical Tabs in CodeColumns (␋)", 
									{
										if(B("", "Add")) test_realignVerticalTabs; 
										if(B("", "Remove")) test_removeVerticalTabs; 
									}
								); 
								
								Grp!Row(
									"Internal NewLines in Declarations (␊)",
									{
										if(B("", "Add")) test_setInternalNewLine; 
										if(B("", "Remove")) test_clearInternalNewLine; 
									}
								); 
								
								Grp!Column(
									"Watches",
									{
										static float maxLocationWidth; 
										foreach(ref w; globalWatches.byValue)
										{
											auto 	sc = DLangScanner("//$DIDE_LOC "~w.id),
												loc = new CodeComment(null); 
											loc.rebuild(sc); 
											loc.measure; 
											maxLocationWidth.maximize(loc.outerWidth); 
											Row(
												{
													Row(
														{
															width = maxLocationWidth; 
															actContainer.appendCell(loc); 
														}
													); 
													Spacer; 
													Row({ Text(w.value); }); 
												}
											); 
										}
									}
								); 
								
								Grp!Row(
									"Statistics",
									{ if(B("", "Declaration Statistics of all D codebase.")) test_declarationStatistics; }
								); 
								
								/*
									if(B("F1", "autoRealign"	)) test_autoRealign;
									if(B("F2", "StructureMap"	)) test_structureMap;
									if(B("F3", "resyntax"	)) test_resyntax;
									if(B("F4", "declaration"	)) test_declarationStatistics;
								*/
							}
						}
					}
				); 
				
				with(workspace)
				if(!selectedStickers.empty)
				with(im)
				Panel(
					PanelPosition.topCenter, 
					{
						Row(
							{
								foreach(
									colorName; [
										"Yellow", "White", "LightOrange", "Olive", 
										"Green", "PastelBlue", "Aqua", "Blue", 
										"Orange", "Pink", "Red", "Purple"
									].map!"`Sticky` ~ a"
								)
								if(
									Btn(
										{
											Row(
												{
													flags.clickable = false; 
													style.bkColor = (colorName).toRGB; 
													border = "1 normal black"; 
													Text("    "); 
												}
											); 
										}, genericId(colorName)
									)
								)
								{
									foreach(s; selectedStickers)
									if(s.props.color.chkSet(colorName))
									s.needMeasure; 
								}
							}
						); 
					}
				); 
				
				
				if(0)
				with(im)
				Panel(
					PanelPosition.topClient,
					{
						margin = "0"; padding = "0"; //border = "1 normal gray";
						Row(
							{
								 //Todo: Panel should be a Row, not a Column...
								Row({ workspace.UI_ModuleBtns; flex = 1; }); 
							}
						); 
					}
				); 
					
				
				
				with(im)
				Panel(
					PanelPosition.topRight,
					{
						margin = "0"; padding = "0"; 
						workspace.UI_SearchBox(view); 
					}
				); 
				
				
				if(0)
				with(im)
				Panel(
					PanelPosition.bottomClient,
					{
						margin = "0"; padding = "0"; //border = "1 normal gray";
						Row(
							{
								Text(hitTestManager.lastHitStack.map!(a => "["~a.id~"]").join(` `)); 
								NL; 
								if(hitTestManager.lastHitStack.length) Text(hitTestManager.lastHitStack.back.text); 
								
								Text("\n", workspace.locate_snapToRow(view.mousePos.vec2).text); 
							}
						); 
					}
				); 
					
				
				
				//undo debug
				if(0)
				with(im)
				with(workspace)
				Panel(
					PanelPosition.bottomClient,
					{
						margin = "0"; padding = "0"; //border = "1 normal gray";
						if(auto m = moduleWithPrimaryTextSelection)
						{
							Container(
								{
									flags.hScrollState = ScrollState.auto_; 
									actContainer.appendCell(m.undoManager.createUI); 
								}
							); 
						}
					}
				); 
				
				
				if(0)
				with(im)
				with(workspace)
				Panel(
					PanelPosition.bottomClient,
					{
						margin = "0"; padding = "0"; //border = "1 normal gray";
						Column({ UI_ResyntaxQueue; }); 
					}
				); 
				
				
				//error list
				if(workspace.showErrorList)
				with(im)
				Panel(
					PanelPosition.bottomClient,
					{
						margin = "0"; padding = "0"; //border = "1 normal gray";
						outerHeight = 200; 
						workspace.UI_ErrorList; 
					}
				); 
				
				
				void VLine()
				{ with(im) Container({ innerWidth = 1; innerHeight = fh; bkColor = clGray; }); } 
				
				
				
				//StatusBar
				with(im)
				Panel(
					PanelPosition.bottomClient,
					{
						margin = "0"; padding = "0"; 
						Row(
							{
								/*theme = "tool";*/ style.fontHeight = 18; 
								
								//Todo: faszomat ebbe a szarba:
								flags.vAlign = VAlign.center;  //ha ez van, akkot a text kozepre megy, de a VLine nem latszik.
								//flags.yAlign = YAlign.stretch; //ha ez, akkor meg a VLine ki van huzva.
								
								Row(
									{
										 margin = "0 3"; flags.yAlign = YAlign.center; 
										//style.fontHeight = 18+6;
										buildSystemWorkerState.UI; 
									}
								); 
								
								VLine; //---------------------------
								
								Row(
									{
										 flex = 1; margin = "0 3"; flags.yAlign = YAlign.center; flags.clipSubCells = true; 
										//style.fontHeight = 18+6;
										
										if(lod.moduleLevel) workspace.UI_selectedModulesHint; 
										if(!lod.moduleLevel) workspace.UI_mouseLocationHint(view); 
										
										
										enum showMousePosCellInfoHint = false; 
										if(showMousePosCellInfoHint) Text("\n", workspace.locate(view.mousePos.vec2).map!cellInfoText.join(' ')); 
									}
								); 
								
								VLine; //---------------------------
								
								Row(
									{
										 margin = "0 3"; flags.yAlign = YAlign.center; 
										foreach(t; EnumMembers!BuildMessageType) { workspace.UI(t, view); }
									}
								); 
								VLine; //---------------------------
								
								Row(
									{
										 margin = "0 3"; flags.vAlign = VAlign.center; 
										if(Btn("ErrorList")) workspace.showErrorList.toggle; 
										if(Btn("Calc size")) print(workspace.allocatedSize); 
										Text(now.text); 
										Text(" "~log2(lod.pixelSize).format!"%.2f"); 
									}
								); 
								
								if(1)
								{
									VLine; 
									workspace.UI_structureLevel; 
								}
								
								//this applies YAlign.stretch
								with(actContainer) {
									measure; 
									foreach(c; cast(.Container[])subCells) c.measure; 
								}
								
							}
						); 
					}
				); 
				
				
				im.UI_FlashMessages; 
				
				im.root ~= workspace; 
				im.root ~= overlay; 
				
				view.subScreenArea = im.clientArea / clientSize; 
				
				workspace.update(view, buildResult); 
				workspace.UI_Popup; 
				
				//bottomRight hint
				with(im)
				Panel
					(
					PanelPosition.bottomRight,
					{
						margin = "0 24 24 0"; 
						border = Border.init; 
						padding = "0"; 
						flags.noBackground = true; 
						workspace.UI_mouseOverHint; 
					}
				); 
				
				
				//update mouse cursor//////////////////////////
				MouseCursor chooseMouseCursor()
				{
					with(MouseCursor)
					{
						if(cancelling) return NO; 
						if(building) return APPSTARTING; 
						if(im.mouseOverUI || im.wantMouse) return ARROW; //Todo: im.chooseMouseCursor
						with(workspace.moduleSelectionManager)
						{
							if(mouseOp == MouseOp.move) return SIZEALL; 
							if(mouseOp == MouseOp.rectSelect) return CROSS; 
						}
						if(workspace.textSelectionsGet.any)
						{
							return IBEAM; 
							/+
								Bug: ez az IBeam a form jobb oldalan eltunik pont annyi pixelnyire 
															az ablak jobb szeletol, mint ahany pixelre az ablak bal szele van 
															a desktop bal szeletol merve.
							+/
						}
						return ARROW; 
					}
				} 
				
				mouseCursor = chooseMouseCursor; 
				
				//print(lod.zoomFactor*DefaultFontHeight);
			} 
			
		}
	} 
	
}class Workspace : Container, WorkspaceInterface
{
	version(/+$DIDE_REGION Workspace+/all)
	{
		//! Module handling ///////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			//A workspace is a collection of opened modules
			
			enum CodeLocationPrefix 	= "CodeLocation:",
			MatchPrefix	= "Match:"; 
			
			File file; //the file of the workspace
			enum defaultExt = ".dide"; 
			
			File[] openQueue; 
			Module[] modules; 
			
			@STORED File mainModuleFile; 
			@property
			{
				Module mainModule()
				{ return findModule(mainModuleFile); } void mainModule(Module m)
				{
					enforce(modules.canFind(m), "Invalid module."); 
					enforce(m.isMain, "This module can't be selected as main module."); 
					mainModuleFile = m.file; 
				} 
			} 
			
			ContainerSelectionManager!Module moduleSelectionManager; 
			TextSelectionManager textSelectionManager; 
			
			protected TextSelection[] textSelections_internal; 
			bool mustValidateTextSelections; 
			@property
			{
				auto textSelectionsGet()
				{
					validateTextSelectionsIfNeeded; 
					return textSelections_internal; 
				} void textSelectionsSet()(TextSelection[] ts)
				{
					textSelections_internal = ts; 
					invalidateTextSelections; 
				} 
			} 
			
			size_t textSelectionsHash; 
			
			bool searchBoxVisible, searchBoxActivate_request; 
			string searchText; 
			
			@STORED bool showErrorList; 
			Module errorModule; 
			
			
			struct MarkerLayer {
				const BuildMessageType type; 
				Container.SearchResult[] searchResults; 
				bool visible = true; 
			} 
			
			auto markerLayers = (() =>  [EnumMembers!BuildMessageType].map!MarkerLayer.array  )(); 
			//Note: compiler drops weird error. this also works:
			//Writing Explicit type also works:
			//auto markerLayers = (() =>  [EnumMembers!BuildMessageType].map!((BuildMessageType t) => MarkerLayer(t)).array  )();
			
			@STORED vec2[size_t] lastModulePositions; 
			
			
			//Restrict convertBuildResultToSearchResults calls.
			size_t lastBuildStateHash; 
			bool buildStateChanged; 
			
			FileDialog fileDialog; 
			
			Nullable!bounds2 scrollInBoundsRequest; 
			
			struct ResyntaxEntry {
				CodeColumn what; 
				DateTime when; 
			} 
			ResyntaxEntry[] resyntaxQueue; 
			
			SyntaxHighlightWorker syntaxHighlightWorker; 
			
			StructureMap structureMap; 
			
			@STORED StructureLevel desiredStructureLevel = StructureLevel.highlighted; 
			
		}version(/+$DIDE_REGION+/all)
		{
			struct AutoReloader
			{
				@STORED bool enabled; 
				
				size_t idx; 
				
				void update(Module[] modules)
				{
					if(!enabled) return; 
					if(modules.empty) return; 
					
					version(/+$DIDE_REGION advance idx+/all)
					{ idx ++;  if(idx>=modules.length) idx = 0; }
					
					auto m = modules[idx]; 
					if(typeid(m) is typeid(Module) /+Opt: It takes 120us for a file.  It is problematic with the stickers...+/)
					if(!m.changed && m.fileModified < m.file.modified)
					m.reload(m.structureLevel); 
				} 
			} 
			
			@STORED AutoReloader autoReloader; 
			
			this()
			{
				flags.targetSurface = 0; 
				flags.noBackground = true; 
				fileDialog = new FileDialog(mainWindow.hwnd, "Dlang source file", ".d", "DLang sources(*.d), Any files(*.*)"); 
				syntaxHighlightWorker = new SyntaxHighlightWorker; 
				structureMap = new StructureMap; 
				needMeasure; 
			} 
					
			~this()
			{ syntaxHighlightWorker.destroy; } 
					
			override @property bool isReadOnly()
			{
				//return frmMain.building;
				return false; 
				//Note: it's making me angly if I can't modify while it's compiling.
				//Bug: deleting from a readonly module loses its selections.
			} 
					
			override void rearrange()
			{
				super.rearrange; 
				static if(rearrangeLOG)
				LOG("rearranging", this); 
			} 
			
			@STORED @property
			{
				//Note: toJson: this can't be protected. But an array can (mixin() vs. __traits(member, ...).
				size_t markerLayerHideMask() const
				{
					size_t res; 
					foreach(idx, const layer; markerLayers)
					if(!layer.visible)
					res |= 1 << idx; 
					
					return res; 
				} 
				void markerLayerHideMask(size_t v)
				{ foreach(idx, ref layer; markerLayers) layer.visible = ((1<<idx)&v)==0; } 
			} 
		}
	}version(/+$DIDE_REGION Module handling+/all)
	{
		//! Module handling ///////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			version(/+$DIDE_REGION ModuleSettings+/all)
			{
				protected
				{
					//ModuleSettings is a temporal storage for saving and loading the workspace.
					struct ModuleSettings {
						string fileName; 
						vec2 pos; 
					} 
					@STORED ModuleSettings[] moduleSettings; 
					
					void toModuleSettings()
					{ moduleSettings = modules.map!(m => ModuleSettings(m.file.fullName, m.outerPos)).array; } 
					
					void fromModuleSettings()
					{
						clear; 
						
						foreach(ms; moduleSettings)
						{
							try
							{ loadModule(File(ms.fileName), ms.pos); }
							catch(Exception e)
							{ WARN(e.simpleMsg); }
						}
						
						updateSubCells; 
					} 
					
					void updateSubCells()
					{
						invalidateTextSelections; 
						moduleSelectionManager.validateItemReferences(modules); 
						subCells = cast(Cell[])modules; 
					} 
				} 
			}
			
			
			auto calcBounds()
			{ return modules.fold!((a, b)=> a|b.outerBounds)(bounds2.init); } 
			
			void clear()
			{
				modules = []; 
				textSelectionsSet = []; 
				updateSubCells; 
			} 
			
			void loadWorkspace(string jsonData)
			{
				auto fuck = this; fuck.fromJson(jsonData); 
				fromModuleSettings; 
			} 
			
			string saveWorkspace()
			{
				toModuleSettings; 
				return this.toJson; 
			} 
			
			void loadWorkspace(File f)
			{ loadWorkspace(f.readText(true)); } 
			
			void saveWorkspace(File f)
			{ f.write(saveWorkspace); } 
			
			Module findModule(File file)
			{
				foreach(m; modules)
				if(sameText(m.file.fullName, file.fullName))
				return m; 
				
				//Opt: hash table with fileName.lc...
				
				return null; 
			} 
		}version(/+$DIDE_REGION+/all)
		{
			void closeModule(File file)
			{
				//Todo: ask user to save if needed
				if(!file) return; 
				const idx = modules.map!(m => m.file).countUntil(file); 
				if(idx<0) return; 
				modules = modules.remove(idx); 
				updateSubCells; 
			} 
			
			auto selectedModules()
			{ return modules.filter!(m => m.flags.selected).array; } 
			auto unselectedModules()
			{ return modules.filter!(m => !m.flags.selected).array; } 
			auto hoveredModule()
			{ return moduleSelectionManager.hoveredItem; } 
			auto modulesWithTextSelection()
			{ return textSelectionsGet.map!(s => s.moduleOf).nonNulls.uniq; } 
					
			auto primaryTextSelection()
			{
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
					
			auto primaryCaret()
			{ return primaryTextSelection.caret; } 
					
			auto moduleWithPrimaryTextSelection()
			{
				auto res = textSelectionsGet.filter!"a.primary".map!moduleOf.frontOrNull; 
				if(!res) res = textSelectionsGet.map!moduleOf.frontOrNull; //if there is no Primary, pick the front one
				return res; 
			} 
			
			alias primaryModule = moduleWithPrimaryTextSelection; 
			
			Module oneSelectedModule()
			{
				if(selectedModules.take(2).walkLength==1)
				return selectedModules.front; 
				return null; 
			} 
			
			Module expectOneSelectedModule()
			{
				auto m = oneSelectedModule; 
				if(!m)
				im.flashWarning("This operation requires a single selected module."); 
				//Todo: put the operation's name in the message.
				
				return m; 
			} 
			
			Module[] selectedModulesOrAll()
			{
				auto res = selectedModules.array; 
				if(res.empty) res = modules; 
				return res; 
			} 
			
			/+
				+Selects all the CodeColumns under the cursors. 
				If there is none, selects all the modules' content CodeColumns.
			+/
			CodeColumn[] selectedOuterColumns()
			{
				CodeColumn[] cols; 
				
				foreach(c; textSelectionsGet.map!"a.codeColumn")
				if(!cols.canFind(c)) cols ~= c; 
				if(cols.empty)
				foreach(c; selectedModules.map!"a.content")
				cols ~= c; 
				
				return cols; 
			} 
			
			auto selectedStickers()
			{ return selectedModules.map!(m => cast(ScrumSticker) m).filter!"a"; } 
			
			auto changedModules()
			{ modules.filter!"a.changed"; } 
			auto projectModules()
			{ return mainModule ? allFilesFromModule(mainModule.file).map!(f => findModule(f)).nonNulls.array : []; } 
			auto changedProjectModules()
			{ return projectModules.filter!"a.changed"; } 
			void saveChangedProjectModules()
			{ changedProjectModules.each!"a.save"; } 
		}version(/+$DIDE_REGION+/all)
		{
			private void closeSelectedModules_impl()
			{
				//Todo: ask user to save if needed
				modules = unselectedModules; 
				updateSubCells; 
				invalidateTextSelections; 
			} 
			
			private void closeAllModules_impl()
			{
				//Todo: ask user to save if needed
				clear; 
				invalidateTextSelections; 
			} 
			
			private void bringToFrontSelectedModules()
			{
				//Not: Do not raise alwaysOnBottom modules to the top.
				static isSel(Module m)
				{ return m.flags.selected && !m.alwaysOnBottom; } 
				
				modules = chain(
					modules.filter!(m=>!isSel(m)), 
					modules.filter!isSel
				).array; 
				updateSubCells; 
			} 
			
			bool loadModule(in File file)
			{
				const vec2 targetPos = lastModulePositions.get(file.actualFile.hashOf, vec2(calcBounds.right+24, 0)); 
				return loadModule(file, targetPos); //default position
			} 
			
			bool loadModule(in File file, vec2 targetPos)
			{
				if(!file.exists) return false; 
				if(auto m = findModule(file))
				{
					m.fileLoaded = now; //it's just a flash indicator
					frmMain.view.smartScrollTo(m.outerBounds); 
					return false; //no loading was issued
				}
				
				Module m; 
				if(file.extIs("scrum"))	m = new ScrumTable(this, file, desiredStructureLevel); 
				else if(file.extIs("sticker"))	m = new ScrumSticker(this, file, desiredStructureLevel); 
				else	m = new Module(this, file, desiredStructureLevel); 
				
				//m.flags.targetSurface = 0; not needed, workspace is on s0 already
				m.measure; 
				m.outerPos = targetPos; 
				modules ~= m; 
				updateSubCells; 
				
				/+
					justLoadedSomething |= true;
					justLoadedBounds |= m.outerBounds; 
				+/
				
				frmMain.view.smartScrollTo(m.outerBounds); 
				
				return true; 
			} 
			
			File[] allFilesFromModule(File file)
			{
				if(!file.exists) return []; 
				//Todo: not just for //@exe of //@dll
				BuildSettings settings = { verbose : false}; 
				BuildSystem buildSystem; 
				return buildSystem.findDependencies(file, settings).map!(m => m.file).array; 
			} 
			
			auto loadModuleRecursive(File file)
			{ allFilesFromModule(file).each!(f => loadModule(f)); } 
			
			void queueModule(File f)
			{
				//Todo: this workaround is there to let the filedialog handle virtual files like: virtual:\clipboard.txt.  This should be put inside openDialog class.
				if(f.fullName.isWild(`*\?*:*`)) f.fullName = wild[1].split('\\').back~':'~wild[2]; 
				openQueue ~= f; 
			} 
			void queueModuleRecursive(File f)
			{ if(f.exists) openQueue ~= allFilesFromModule(f); } 
			
			void updateOpenQueue(int maxWork)
			{
				while(openQueue.length)
				{
					auto f = openQueue.fetchFront; 
					if(loadModule(f))
					{
						maxWork--; 
						if(maxWork<=0) return; 
					}
				}
			} 
			
			void updateModuleBuildStates(in BuildResult buildResult)
			{
				foreach(m; modules)
				{ m.buildState = buildResult.getBuildStateOfFile(m.file); }
			} 
			
			void updateLastKnownModulePositions()
			{
				foreach(m; modules)
				lastModulePositions[m.file.hashOf] = m.outerPos; 
			} 
			
		}
	}version(/+$DIDE_REGION+/all)
	{
		
		static struct LineIdxLocator
		{
			int lineIdx; 
			string reference; 
			
			Container.SearchResult[] searchResults; 
			
			void visitNode(CodeNode node)
			{
				foreach(col; node.subCells.map!(a => cast(CodeColumn) a).filter!"a")
				visitColumn(col); 
			} 
			
			void visitColumn(CodeColumn col)
			{
				auto rows = col.rows; 
				
				//ignore trailing empty rows
				while(rows.length && !rows.back.lineIdx)
				rows.popBack; 
				
				//ignore all rows higher than lineIdx
				rows = rows[0 .. rows.map!"a.lineIdx".assumeSorted.lowerBound(lineIdx+1).length]; 
				
				//process same lines
				while(rows.length && rows.back.lineIdx==lineIdx)
				{
					visitRow(rows.back); 
					rows.popBack; 
				}
				
				//process one more row whick can contain lineIdx, but starts earlier
				if(rows.length) visitRow(rows.back); 
				
				//unpotimized version -> foreach(row; col.rows) visitRow(row);
			} 
			
			void visitRow(CodeRow row)
			{
				bool glyphIsOnLine(Cell cell)
				{
					if(auto g = cast(Glyph)cell)
					return g.lineIdx && g.lineIdx == lineIdx; 
					
					return false; 
				} 
				
				Container.SearchResult res; 
				res.cells = row.subCells.filter!glyphIsOnLine.array; //Opt: binary search
				if(res.cells.length)
				{
					res.container = row; 
					
					res.absInnerPos = worldInnerPos(res.container); 
					res.reference = reference; 
					
					searchResults ~= res; //Opt: appender
				}
				
				foreach(node; row.subCells.map!(a => cast(CodeNode) a).filter!"a")
				visitNode(node); 
			} 
		} 
		
		Container.SearchResult[] codeLocationToSearchResults(CodeLocation loc)
		{
			//Opt: unoptimal to return a dynamic array
			
			if(!loc) return []; 
			
			if(auto mod = findModule(loc.file.withoutDMixin))
			{
				//Opt: bottleneck! linear search
				//Todo: return the whole module if the line is unspecified, or unable to find
				
				if(!loc.lineIdx)
				{
					//Todo: mark the whole module
					return []; 
				}
				
				auto locator = LineIdxLocator(loc.lineIdx, CodeLocationPrefix ~ loc.text); 
				locator.visitNode(mod); 
				
				auto res = locator.searchResults; 
				
				if(res.length>1) foreach(ref a; res[1..$]) a.showArrow = false; 
				
				return res; 
			}
			else
			{
				//module not loaded
				//LOG(msg);
				//if(msg.location.file.exists) queueModule(msg.location.file);
				return []; 
			}
		} 
		
		
		CodeRow[string] messageUICache; 
		string[string] messageSourceTextByLocation; 
		
		void convertBuildMessagesToSearchResults()
		{
			T0; 
			auto br = frmMain.buildResult; 
			
			const outFile = File(`virtual:\__compilerOutput.d`); 
			
			auto unprocessedSourceTexts = br.unprocessedSourceTexts; 
			auto messageSourceTexts = br.messageSourceTexts; 
			auto allSourceTexts = unprocessedSourceTexts ~ messageSourceTexts; 
			auto output = allSourceTexts.join('\n'); 
			outFile.write(output); 
			
			const tAccessBuildMessages = DT;  //40 ms
			
			errorModule = new Module(null, "", StructureLevel.structured); 
			messageSourceTextByLocation.clear; 
			if(allSourceTexts.length)
			{
				//load all messages through a cache
				float y = 0; 
				errorModule.content.subCells = []; 
				foreach(msg; allSourceTexts)
				{
					//hide messages of unselected markerLayers
					bool messageIsVisible = true; 
					if(msg.isWild("/+?*:*"))
					{
						ignoreExceptions(
							{
								const bmt = wild[0].toLower.to!BuildMessageType; 
								messageIsVisible = markerLayers[bmt].visible; 
							}
						); 
					}
					
					if(!messageIsVisible) continue; 
					
					//extract all locations from the message.
					foreach(s; msg.splitter("/+$"~"DIDE_LOC ").drop(1))
					if(s.isWild("?*+/*"))
					messageSourceTextByLocation[wild[0]] = msg; 
					
					if(msg !in messageUICache)
					{
						auto tempModule = new Module(null, msg, StructureLevel.structured); 
						tempModule.measure; 
						messageUICache[msg] = tempModule.content.rows[0]; 
					}
					errorModule.content.subCells ~= messageUICache[msg]; 
					with(errorModule.content.subCells.back)
					{
						setParent(errorModule.content); 
						outerPos = vec2(0, y); 
						y += outerHeight; 
					}
					
					//Todo: Why I need to spread this shit manually? Why errorModule.measure dont do this?
					//Bug: this cache is never emptied, it keeps growing.
				}
			}
			
			const tLoadErrorModule = DT; //110 ms
			
			errorModule.measure; 
			//Note: This calculates the height and width of the module. It fails to spread the rows vertically.
			
			const tMeasureErrorModule = DT; //0 ms (because of the messageUICache[])
			
			auto buildMessagesAsSearchResults(BuildMessageType type)
			{
				//Todo: opt
				Container.SearchResult[] arr; 
				
				foreach(msgIdx, const msg; br.messages)
				if(msg.type==type)
				arr ~= codeLocationToSearchResults(msg.location); 
				
				return arr; 
			} 
			
			/+
				Opt: it is a waste of time. this should be called only at buildStart, and at buildProgress, 
				module change, module move.
			+/
			//1.5ms, (45ms if not sameText but sameFile(!!!) is used in the linear findModule.)
			foreach(t; EnumMembers!BuildMessageType[1..$])
			markerLayers[t].searchResults = buildMessagesAsSearchResults(t); 
			
			const tBuildSearchResults = DT; //60 ms
			
			//performance timing
			if(0)
			LOG(
				[tAccessBuildMessages, tLoadErrorModule, tMeasureErrorModule, tBuildSearchResults]
				.map!(a => a.value(milli(second))).format!"%(%.0f %)"
			); 
			
		} 
		
		//Todo: since all the code containers have parents, location() is not needed anymore
		
		override CellLocation[] locate(in vec2 mouse, vec2 ofs=vec2(0))
		{
			//locate ////////////////////////////////
			ofs += innerPos; 
			foreach_reverse(m; modules) {
				auto st = m.locate(mouse, ofs); 
				if(st.length) return st; 
			}
			return []; 
		} 
			
		CellLocation[] locate_snapToRow(vec2 mouse, float epsilon = .5f)
		{
			auto st = locate(mouse); 
			
			auto getLastCol() { return cast(CodeColumn) st.map!"a.cell".backOrNull; } 
			
			//try snap it from the edge
			if(auto col = getLastCol)
			{
				const ofs = st.back.calcSnapOffsetFromPadding(epsilon); 
				if(ofs)
				{ mouse += ofs;  st = locate(mouse); }
			}
			
			//try to avoid the gaps if it is a multiPage Column
			if(auto col = getLastCol)
			{
				auto pages = col.getPageRowRanges; 
				if(pages.length>1)
				{
					const p = st.back.localPos; 
					auto xStarts = pages.map!(p => p.front.outerLeft).assumeSorted; 
					size_t idx = (xStarts.length - xStarts.upperBound(p.x).length - 1); 
					if(idx<pages.length-1)
					{
						const 	xLeft	= pages[idx].front.outerRight - epsilon,
							xRight 	= pages[idx+1].front.outerLeft + epsilon,
							xMid	= avg(xLeft, xRight); 
						
						if(p.x.inRange(xLeft, xRight))
						{
							mouse += (p.x<xMid ? xLeft : xRight) - p.x; 
							st = locate(mouse); 
						}
					}
				}
			}
			
			//try to snap up from the bottom of a page
			if(auto col = getLastCol)
			{
				auto pages = col.getPageRowRanges; 
				if(pages.length>1)
				{
					const p = st.back.localPos; 
					auto xStarts = pages.map!(p => p.front.outerLeft).assumeSorted; 
					size_t idx = (xStarts.length - xStarts.upperBound(p.x).length - 1); 
					//Todo: too much copy paste. Must refactor these ifs.
					
					if(idx<pages.length/+it needs only one page, not two+/)
					{
						const limit = pages[idx].back.outerBottom - epsilon; 
						
						if(p.y > limit)
						{
							mouse.y += limit - p.y; 
							st = locate(mouse); 
						}
					}
				}
			}
			
			
			return st; 
		} 
		
		CodeLocation cellLocationToCodeLocation(CellLocation[] st)
		{
			CodeLocation res; 
			if(0)
			{
				//Note: this works only at the first dept level
				//Todo: deprecate this code
				auto a(T)(void delegate(T) f)
				{ if(auto x = cast(T)st.get(0).cell) { st.popFront; f(x); }} 
				a(
					(Module m)
					{
						res.file = m.file; 
						a(
							(CodeColumn col)
								{
								a(
									(CodeRow row)
										{
										if(auto lineIdx = col.subCells.countUntil(row)+1)
										{
											//Todo: parent.subcellindex/child.index
											res.lineIdx = lineIdx.to!int; 
											a(
												(Cell cell)
													{
													if(auto columnIdx = row.subCells.countUntil(cell)+1)
													{
														//Todo: parent.subcellindex/child.index
														res.columnIdx = columnIdx.to!int; 
													}
												}
											); 
										}
									}
								); 
							}
						); 
					}
				); 
			}
			else
			{
				//Todo: it's only detects the lineIdx
				while(st.length) {
					void setLineIdx(int i) { if(!res.lineIdx) res.lineIdx = i; } 
					auto cell = st.back.cell; 
					
					if(auto glyph = cast(Glyph)cell) setLineIdx(glyph.lineIdx); 
					else if(auto node = cast(CodeNode)cell) setLineIdx(node.lineIdx); 
					else if(auto row = cast(CodeRow)cell) {
						setLineIdx(row.lineIdx); 
						/+
							Todo: this should be row.findLineIdx_max,
							because the mouse is at the end of the row
						+/
						
						if(auto mod = moduleOf(row))
						res.file = mod.file; 
						break; 
					}
					//Todo: Tabs would look better in this if chain.
					
					st.popBack; 
				}
			}
			
			return res; 
		} 
		
		static CellLocation[] findLastCodeRow(CellLocation[] st)
		{
			foreach_reverse(i; 0..st.length) {
				//Todo: functinal
				auto row = cast(CodeRow)st[i].cell; 
				if(row) return st[i..$]; 
			}
			return []; 
		} 
			
		TextCursor cellLocationToTextCursor(CellLocation[] st)
		{
			TextCursor res; 
			st = findLastCodeRow(st); 
			if(auto row = cast(CodeRow)st.get(0).cell)
			{
				auto cell = st.get(1).cell; 
				
				//try to find cell with smaller height than the row, vertically at x,
				//   if the mouse is not exactly inside the cell. Also snap from the sides.
				if(!cell) {
					cell = row.subCellAtX(st[0].localPos.x, Yes.snapToNearest); 
					if(cell) {
						st  ~= CellLocation(cell, st[0].localPos-cell.innerPos); 
						//pass in localPos inside the cell
					}
				}
				
				res.codeColumn = row.parent; 
				
				res.desiredX = st[0].localPos.x; 
				res.pos.y = row.index; 
				
				//find x character index
				int x; 
				if(cell)
				{
					x = row.subCellIndex(cell); 
					assert(x>=0); 
					if(st[1].localPos.x>cell.innerWidth/2) x++; 
				}
				else
				{ x = res.desiredX<0 ? 0 : row.cellCount; }
				assert(x.inRange(0, row.cellCount)); 
				res.pos.x = x; 
			}
			
			return validate(res); 
		} 
	}version(/+$DIDE_REGION+/all)
	{
		TextCursor createCursorAt(vec2 p)
		{ return cellLocationToTextCursor(locate_snapToRow(p)); } 
		
		//textSelection, cursor movements /////////////////////////////
			
		int lineSize()
		{ return DefaultFontHeight; } 
		int pageSize()
		{ return (frmMain.view.subScreenBounds_anim.height/lineSize*.9f).iround.clamp(2, 100); } 
		void cursorOp(ivec2 dir, bool select)
		{
			auto arr = textSelectionsGet; 
			foreach(ref ts; arr) ts.move(dir, select); 
			textSelectionsSet = merge(arr); //Todo: maybe merge should reside in validateTextSelections
		} 
			
		void scrollV(float dy)
		{ frmMain.view.scrollV(dy); } 
		void scrollH(float dx)
		{ frmMain.view.scrollH(dx); } 
		void zoom(float log)
		{ frmMain.view.zoom(log); } //Todo: Only zoom when window is foreground
			
		float scrollSpeed()
		{ return frmMain.deltaTime.value(second)*2000; } 
		float zoomSpeed()
		{ return frmMain.deltaTime.value(second)*8; } 
		float wheelSpeed = 0.375f; 
			
		void insertCursor(int dir)
		{
			auto prev = textSelectionsGet,
					 next = prev.dup; 
			
			foreach(ref ts; next)
			foreach(
				ref tc; ts.cursors//Note: It is important to move the cursors separately here.  Don't let TextSelection.move do cursor collapsing.
			)
			tc.move(ivec2(0, dir)); 
			
			textSelectionsSet = merge(prev ~ next); 
		} 
		
		void scrollInModules(Module[] m)
		{ if(m.length) scrollInBoundsRequest = m.map!"a.outerBounds".fold!"a|b"; } 
		
		void scrollInAllModules()
		{ scrollInModules(modules);                             } 
		
		void scrollInModule(Module m)
		{ if(m) scrollInModules([m]);                             } 
		
		void preserveTextSelections(void delegate() fun)
		{
			//Todo: preserve module selections too
			const savedTextSelections = textSelectionsGet.map!(a => a.toReference.text).array; 
			scope(exit) textSelectionsSet = savedTextSelections.map!(a => TextSelection(a, &findModule)).array; 
			if(fun) fun(); 
		} 
		
		auto insertCursorAt___OfEachLineSelected_impl(R)(R textSelections, Flag!"toTheEnd" toTheEnd = Yes.toTheEnd)
		{
			auto res = 	textSelections
				.filter!"a.valid"  //just to make sure
				.map!(
				//create cursors in every lines at the start of the line
				sel => 	iota(sel.start.pos.y, sel.end.pos.y+1)
					.map!(y => TextCursor(sel.codeColumn, ivec2(0, y)))
			)
				.joiner
				.map!(
				(c){
					//move the cursor to the end or home of the line
					if(toTheEnd) c.moveToLineEnd; 
					else c.moveToLineStart; //Todo: it's not functional yet
					return TextSelection(c, c, false); //make a selection out of them
				}
			)
				.merge /+merge it, because there can be duplicates+/; 
			
			if(res.length) res[0].primary = true; //Todo: primary selection is inconsistent when multiselect
			
			return res; 
		} 
		
		auto insertCursorAtStartOfEachLineSelected_impl(R)(R textSelections)
		{ return insertCursorAt___OfEachLineSelected_impl(textSelections, No.toTheEnd); } 
		
		auto insertCursorAtEndOfEachLineSelected_impl(R)(R textSelections)
		{ return insertCursorAt___OfEachLineSelected_impl(textSelections, Yes.toTheEnd); } 
		
		auto selectCharAtEachSelection(R)(R textSelections, dchar ch)
		{
			TextSelection transform(TextSelection sel)
			{
				TextSelection res; 
				if(sel.cursors[0].charAt == ch)
				{
					res = sel.dup; 
					res.cursors[1] = res.cursors[0]; 
					res.cursors[1].moveRight(1); 
				}
				return res; 
			} 
			
			return 	textSelections
				.map!(a => transform(a))
				.cache
				.filter!"a.valid"
				.merge; 
		} 
	}version(/+$DIDE_REGION+/all)
	{
		void selectSearchResults(SearchResult[] arr)
		{
			//selectSearchResults ///////////////////////////
			//Todo: use this as a revalidator after the modules were changed under the search results.
			//Maybe verify the search results while drawing. Cache the last change or something.
			
			TextSelection conv(SearchResult sr)
			{
				if(sr.cells.length)
				if(auto row = cast(CodeRow)sr.container)
				if(auto col = row.parent)
				{
					auto 	rowIdx = row.index,
						//Todo: could find other cells as well.
						//If the user edits the document for example.
						st = row.subCellIndex(sr.cells.front),
						en = row.subCellIndex(sr.cells.back); 
					if(rowIdx>=0 && st>=0 && en>=0)
					{
						auto ts = TextSelection
						(
							TextCursor(col, ivec2(st, rowIdx)), 
							TextCursor(col, ivec2(en+1, rowIdx)),
							false
						); 
						return validate(ts); 
					}
				}
				return TextSelection.init; 
			} 
			
			//T0; scope(exit) DT.LOG;
			textSelectionsSet = merge(arr.map!(a => conv(a)).filter!"a.valid".array); 
		} 
		
		void cancelSelection_impl()
		{
			//cancelSelection_impl //////////////////////////////////////
			auto ts = textSelectionsGet; 
			auto mp = moduleWithPrimaryTextSelection; 
			
			void selectPrimaryModule()
			{
				textSelectionsSet = []; 
				foreach(m; modules) m.flags.selected = m is mp; 
				scrollInModule(mp); 
			} 
			
			//multiTextSelect -> primaryTextSelect
			if(ts.length>1)
			{
				if(auto pts = primaryTextSelection)
				textSelectionsSet = [pts]; 
				else
				selectPrimaryModule; //just for safety
				return; 
			}
			
			if(ts.length>0)
			{
				selectPrimaryModule; 
				return; 
			}
			
			//deselect everything, zoom all
			textSelectionsSet = []; 
			deselectAllModules; 
			scrollInAllModules; 
			
			//auto em = editedModules;
			//if(em.length>1)
			
			//Todo: primary
			
			/*
				   if(lod.moduleLevel){
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
						}
			*/
			
			
		} 
	}version(/+$DIDE_REGION Validate+/all)
	{
		//Validation //////////////////////////////////
		void invalidateTextSelections()
		{
			PING0; 
			mustValidateTextSelections = true; 
			textSelectionManager.invalidateInternalSelections; 
		} 
		
		void validateTextSelectionsIfNeeded()
		{
			if(mustValidateTextSelections.chkClear)
			{
				PING1; 
				textSelections_internal = validate(textSelections_internal); 
			}
		} 
		
		auto validate(TextCursor c)
		{ return validate(TextSelection(c, c, false)).cursors[0]; } 
		
		auto validate(TextSelection s)
		{
			auto ts = validate([s]); 
			return ts.empty ? TextSelection.init : ts[0]; 
		} 
		
		auto validate(TextSelection[] arr)
		{
			Cell cachedExistingModule; 
			
			bool isExistingModule(Cell c)
			{
				if(c is cachedExistingModule) return true; 
				//Opt: this is helping nothing compared to
				
				if(auto m = cast(Module)c)
				if(modules.canFind(m))
				{
					cachedExistingModule = c; 
					return true; 
				}
				return false; 
			} 
				
			bool validate(TextSelection sel)
			{
				if(!sel.valid) return false; 
				auto r = sel.toReference; 
				if(!r.valid) return false; 
				
				auto p = r.cursors[0].path; 
				if(p[0] !is this) return false; 	 //not this workspace
				if(!isExistingModule(p[1])) return false; 	 //module died
				
				//Todo: check if selection is inside row boundaries.
				return true; 
			} 
			return arr.filter!(a => validate(a)).array; //Todo: try to fix partially broken selections
		} 
	}version(/+$DIDE_REGION Permissions+/all)
	{
		protected
		{
			//permissions //////////////////////////////////////
			
			/+
				+ this value is incremented by every cut or paste batch operation.
						This controls undoOperation fuson, in order to preserve the order of
						multiselect cut and paste operations. (cursors are only vanid if they are in order.) 
			+/
			uint undoGroupId; 
			
			bool requestModifyPermission(CodeColumn col)
			{
				//Todo: constness
				assert(col); 
				if(isReadOnly) return false; 
				auto m = moduleOf(col); 
				return !m.isReadOnly; 
			} 
			
			bool requestDeletePermission(TextSelection ts)
			{
				auto s = ts.sourceText; 
				/+
					this can throw if the structured contents are invalid. 
								If that goes into the undo, it would not be redo'd.
				+/
				
				auto res = requestModifyPermission(ts.codeColumn); 
				if(res)
				{
					static if(LogRequestPermissions)
					print(EgaColor.ltRed("DEL"), ts.toReference.text, s.quoted); 
						
					auto m = moduleOf(ts).enforce; 
					m.undoManager.justRemoved(undoGroupId, ts.toReference.text, s); 
				}
				return res; 
			} 
			
			struct CollectedInsertRecord
			{
				int stage; 
				TextSelection textSelection; 
				string contents; 
				void reset()
				{ this = typeof(this).init; }                                                     
			} 
			CollectedInsertRecord collectedInsertRecord; 
			
			bool requestInsertPermission_prepare(TextSelection ts, string str)
			{
				auto res = requestModifyPermission(ts.codeColumn); 
				
				//Todo: there could be additional checks based on the input text
				
				if(str.isValidDLang)
				WARN("Invalid DLang source code inserted.\n"~str); 
				
				if(res) {
					auto m = moduleOf(ts).enforce; 
					static if(LogRequestPermissions)
					print(EgaColor.ltGreen("INS0"), ts.toReference, str.quoted); 
					with(collectedInsertRecord)
					{
						enforce(stage==0, "collectedInsertRecord.stage inconsistency 1"); 
						stage = 1; 
						textSelection = ts; 
						contents = str; 
					}
				}
				return res; 
			} 
			
			void requestInsertPermission_finish(TextSelection ts)
			{
				auto m = moduleOf(ts).enforce; 
				with(collectedInsertRecord)
				{
					enforce(stage==1, "collectedInsertRecord.stage inconsistency 2"); 
					static if(LogRequestPermissions)
					print(EgaColor.ltCyan("INS1"), ts.toReference); 
					
					textSelection.cursors[1] = ts.cursors[1]; 
					m.undoManager.justInserted(undoGroupId, textSelection.toReference.text, contents); 
					reset; 
				}
			} 
		} 
	}version(/+$DIDE_REGION Undo/Redo+/all)
	{
		//Undo/Redo
		
		/+
			 	3 levels
					1. Save, SaveAll (ehhez csak egy olyan kell, hogy a legutolso save/load ota a user 
								 beleirt-e valamit.   Hierarhikus formaban lennenek a changed flag-ek, a soroknal 
								 meg lenne 2 extra: removedNextRow, removedPrevRow)
					2. Opcionalis Undo: ez csak 2 save kozott mukodhetne. Viszont a redo utani modositas
								 nem semmisitene meg az utana levo undokat, hanem csak becsatlakoztatna a graph-ba. 
								 Innentol nem idovonal van, hanem graph.
					3.	Opcionalis history: Egy kulon konyvtarba behany minden menteskori es betolteskori 
						allapotot. Ezt kesobb delta codinggal tomoriteni kell. 
		+/
		
		protected void executeUndoRedoRecord(in bool isUndo, in bool isInsert, in TextModificationRecord rec)
		{
			TextSelection ts; 
			bool decodeTs(bool reduceToStart)
			{
				string where = rec.where; 
				if(reduceToStart) where = where.reduceTextSelectionReferenceStringToStart; 
				ts = TextSelection(where, &findModule); 
				bool res = ts.valid; 
				if(!res) WARN("Invalid ts: "~where); 
				return res; 
			} 
			
			const isCut = isUndo==isInsert; 
			
			if(decodeTs(!isCut))
			{
				if(isCut)
				cut_impl!true([ts]); 
				else
				paste_impl!true([ts], No.fromClipboard, rec.what); 
				
				if(decodeTs(isCut))
				textSelectionsSet = [ts]; 
			}
		} 
		
		protected void executeUndoRedo(bool isUndo)(in TextModification tm)
		{
			static if(isUndo) auto r = tm.modifications.retro; else auto r = tm.modifications; 
			r.each!(m => executeUndoRedoRecord(isUndo, tm.isInsert, m)); 
		} 
		
		protected void execute_undo(in TextModification tm)
		{ executeUndoRedo!true (tm); } protected void execute_redo(in TextModification tm)
		{ executeUndoRedo!false(tm); } 
		
		protected void execute_reload(string where, string what)
		{
			if(auto m=findModule(File(where)))
			{
				m.reload(desiredStructureLevel, nullable(what)); 
				//selectAll
				textSelectionsSet = [m.content.allSelection(true)]; 
				//Todo: refactor codeColumn.allTextSelection(bool primary or not)
			}
			else
			assert(0, "execute_reload: module lost: "~where.quoted); 
			//Todo: somehow signal bact to the undo manager, if an undo operation is failed
		} 
		
		void undoRedo_impl(string what)()
		{
			//Todo: select the latest undo/redo operation if there are more than 
			//one modules selected. If no modules selected: select from all of them.
			if(auto m = moduleWithPrimaryTextSelection)
			{
				//Todo: undo should not remove textSelections on other modules.
				mixin(q{m.undoManager.#(&execute_#, &execute_reload); }.replace("#", what)); 
				invalidateTextSelections; //because executeUndo don't call measure() so desiredX's are invalid.
			}
		} 
	}
	version(/+$DIDE_REGION Cut   +/all)
	{
		///All operations must go through copy_impl or cut_impl. Those are calling 
		///requestModifyPermission and blocks modifications when the module is readonly. Also that is needed for UNDO.
		bool copy_impl(TextSelection[] textSelections)
		{
			//copy_impl ///////////////////////////////////////
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			auto s = textSelections.sourceText; //this can throw if structured declarations has invalid contents
			
			//Bug: Two adjacent slashComnments are not emit a newLine in between them
			
			bool valid = s.length>0; 	
			if(valid) clipboard.text = s; 	//Todo: BOM handling
			return valid; 
		} 
		
		///Ditto
		auto cut_impl(bool dontMeasure=false)(TextSelection[] textSelections, bool* returnSuccess=null)
		{
			//cut_impl ////////////////////////////////////////
			undoGroupId++; 
			
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			auto savedSelections = textSelections.map!"a.toReference".array; 
			
			if(returnSuccess !is null) *returnSuccess = true; //Todo: terrible way to
			
			void cutOne(TextSelection sel)
			{
				if(sel.isZeroLength) return; //nothing to do with empty selection
				if(auto col = sel.codeColumn)
				{
					const 	st = sel.start,
						en = sel.end; 
					
					foreach_reverse(y; st.pos.y..en.pos.y+1)
					{
						 //Todo: this loop is in the draw routine as well. Must refactor and reuse
						if(auto row = col.getRow(y))
						{
							const rowCellCount = row.cellCount; 
							
							const 	isFirstRow	= y==st.pos.y,
								isLastRow	= y==en.pos.y,
								isMidRow	= !isFirstRow && !isLastRow; 
							if(isMidRow)
							{
								 //delete whole row
								col.subCells = col.subCells.remove(y); 
								//Opt: do this in a one run batch operation.
							}
							else
							{
								 //delete partial row
								const	x0 = isFirstRow	? st.pos.x	: 0,
									x1 = isLastRow 	? en.pos.x 	: rowCellCount+1; 
								
								foreach_reverse(x; x0..x1)
								{
									if(x>=0 && x<rowCellCount)
									{
										row.subCells = row.subCells.remove(x); 
										//Opt: this is not so fast. It removes 1 by 1.
									}
									else if(x==rowCellCount)
									{
										 //newLine
										if(auto nextRow = col.getRow(y+1))
										{
											foreach(ref ss; savedSelections)
											{
												//Opt: must not go througn all selection.
												//It could binary search the start position to iterate.
												ss.replaceLatestRow(nextRow, row); 
											}
											
											if(nextRow.subCells.length)
											{
												row.append(nextRow.subCells); 
												row.adoptSubCells; 
												//Note: it seems logical, but not help in tracking.
												//Always mark a cut with changedRemoved: row.setChangedCreated;
											}
											
											nextRow.subCells = []; 
											col.subCells = col.subCells.remove(y+1); 
										}
										else
										assert(0, "TextSelection out of range NL"); 
									}
									else
									assert(0, "TextSelection out of range X"); 
								}
								
								row.refreshTabIdx; 
								row.spreadElasticNeedMeasure; 
								row.setChangedRemoved; 
							}
						}
						else
						assert(0, "TextSelection out of range Y"); 
					}//for y
					
					needResyntax(col); 
				}
				else
				assert(0, "TextSelection invalid CodeColumn"); 
			} 
			
			foreach_reverse(sel; textSelections)
			{
				if(!sel.isZeroLength)
				{
					if(requestDeletePermission(sel))
					{ cutOne(sel); }
					else
					{
						if(returnSuccess !is null) {
							//Todo: maybe it would be better to handle readOnlyness with an exception...
							*returnSuccess = false; 
						}
					}
				}
			}
			
			static if(!dontMeasure)
			measure; //It's needed to calculate TextCursor.desiredX
			//Opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.
			
			return savedSelections.map!"a.fromReference".filter!"a.valid".array; 
		} 
			
		bool cut_impl2(bool dontMeasure=false)(TextSelection[] sel, ref TextSelection[] res)
		{
			//Todo: constness for input
			bool success; 
			auto tmp = cut_impl!dontMeasure(sel, &success); 
			if(success) res = tmp; 
			return success; 
		} 
	}version(/+$DIDE_REGION Paste +/all)
	{
		//Todo: Make a version of copy/cut/paste that works with CodeColumns (multiple rows)
		//Todo: For this CodeColumn deep copy must be implemented somehow.  //Maybe by exporting and rendering it again. Speed is not important
		auto paste_impl(bool dontMeasure=false)(
			TextSelection[] textSelections,
			Flag!"fromClipboard" fromClipboard,
			string input,
			Flag!"duplicateTabs" duplicateTabs = No.duplicateTabs
		)
		{
			//paste_impl //////////////////////////////////
			if(textSelections.empty) return textSelections; //no target
			
			if(fromClipboard)
			input = clipboard.text;  //Todo: BOM handling
			
			auto lines = input.splitLines; 
			if(lines.empty) return textSelections; //nothing to do with an empty clipboard
			
			if(!cut_impl2!dontMeasure(textSelections, /+writes into this if successful -> +/textSelections))
			{
				//Todo: this is terrible. Must refactor.
				return textSelections; 
			}
			
			//from here it's paste -------------------------------------------------
			undoGroupId++; 
			
			TextSelectionReference[] savedSelections; 
			
			//Todo: insertText with fake local syntax highlighting. until the background syntax highlighter finishes.
			
			///inserts text at cursor, moves the corsor to the end of the text
			void insertSingleLine(ref TextSelection ts, string str)
			{
				assert(ts.valid); 
				assert(ts.isZeroLength); 
				assert(ts.caret.pos.y.inRange(ts.codeColumn.subCells)); 
				
				if(auto row = ts.codeColumn.getRow(ts.caret.pos.y))
				{
					if(requestInsertPermission_prepare(ts, str))
					{
						const insertedCnt = row.insertText(ts.caret.pos.x, str); //INS
						//Todo: shift adjust selections that are on this row
						
						//adjust caret and save
						ts.cursors[0].moveRight(insertedCnt); 
						ts.cursors[1] = ts.cursors[0]; 
						
						requestInsertPermission_finish(ts); 
						needResyntax(ts.codeColumn); 
					}
					
					savedSelections ~= ts.toReference; 
				}
				else
				assert("Row out if range"); 
			} void insertMultiLine(ref TextSelection ts, string[] lines )
			{
				assert(ts.valid); 
				assert(ts.isZeroLength); 
				assert(lines.length>=2); 
				
				if(auto row = ts.codeColumn.getRow(ts.caret.pos.y))
				{
					assert(ts.caret.pos.x>=0 && ts.caret.pos.x<=row.subCells.length); 
					
					//handle leadingTab duplication
					if(duplicateTabs && row.leadingCodeTabCount)
					{
						const newTabCnt = min(row.leadingCodeTabCount, ts.caret.pos.x); 
						
						lines = lines.dup; 
							lines.back = "\t".replicate(newTabCnt) ~ lines.back; 
					}
					
					if(requestInsertPermission_prepare(ts, lines.join(DefaultNewLine)))
					{
						//break the row into 2 parts
						//transfer the end of (first)row into a lastRow
						auto lastRow = row.splitRow(ts.caret.pos.x); 
						
						//insert at the end of the first row
						row.insertText(row.cellCount, lines.front);  //INS
						
						//create extra rows in the middle
						Cell[] midRows; 
						foreach(line; lines[1..$-1])
						{
							auto r = new CodeRow(ts.codeColumn, line);  //INS
							//Todo: this should be insertText
							r.setChangedCreated; 
							midRows ~= r; 
						}
						
						//insert at the beginning of the last row
						const insertedCnt = lastRow.insertText(0, lines.back);  //INS
						
						//insert modified rows into column
						ts.codeColumn.subCells 	= ts.codeColumn.subCells[0..ts.caret.pos.y+1]
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
					
					//Todo: update caret
				}
				else
				assert("Row out if range"); 
			} 
			
			///insert all lines into the selection
			void fullInsert(ref TextSelection ts)
			{
				if(lines.length==1)
				{
					//simple text without newline
					insertSingleLine(ts, lines[0]); 
				}
				else if(lines.length>1)
				{
					//insert multiline text
					insertMultiLine(ts, lines); 
				}
			} 
			
			if(textSelections.length==1)
			{
				//put all the clipboard into one place
				fullInsert(textSelections[0]); 
			}
			else if(textSelections.length>1)
			{
				if(lines.length>textSelections.length || duplicateTabs/+this means it is pasting newlines+/)
				{
					//clone the full clipboard into all selections.
					foreach_reverse(ref ts; textSelections)
					fullInsert(ts); 
				}
				else
				{
					 //cyclically paste the lines of the clipboard
					foreach_reverse(ref ts, line; lockstep(textSelections, lines.cycle.take(textSelections.length)))
					insertSingleLine(ts, line); 
				}
			}
			
			static if(!dontMeasure)
			measure; //It's needed to calculate TextCursor.desiredX
			//Opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.
			
			return savedSelections.retro.map!"a.fromReference".filter!"a.valid".array; 
		} 
	}struct ContainerSelectionManager(T : Container)
	{
		version(/+$DIDE_REGION+/all)
		{
			//ContainerSelectionManager ///////////////////////////////////////////////
			//this uses Containers. flags.selected, flags.oldSelected
			
			bounds2 getBounds(T item)
			{ return item.outerBounds; } 
			
			enum MouseOp
			{ idle, beforeMove, move, rectSelect} 
			MouseOp mouseOp; 
			
			enum SelectOp
			{ none, add, sub, toggle, clearAdd} 
			SelectOp selectOp; 
			
			vec2 dragSource; 
			bounds2 dragBounds; 
			
			//these are calculated after update. No notifications, just keep calling update frequently
			T hoveredItem; 
			
			private float mouseTravelDistance = 0; 
			private vec2 accumulatedMoveStartDelta, mouseLast; 
			
			///must be called after an items removed
			void validateItemReferences(T[] items) {
				if(
					!items.canFind(hoveredItem)//Opt: slow linear search
				)
				hoveredItem = null; 
				//Todo: maybe use a hovered containerflag.
			}   private static void select(alias op)(T[] items, T selectItem=null)
			{
				foreach(a; items)
				a.flags.selected = a.flags.selected.unaryFun!op; 
					if(selectItem) select!"true"([selectItem]); 
			}   bounds2 selectionBounds() {
				if(mouseOp == MouseOp.rectSelect)
				return dragBounds; 
				else
				return bounds2.init; 
			} 
			
		}
		void update(
			bool 	mouseEnabled, 
			View2D 	view, 
			T[] 	items, 
			bool 	anyTextSelected, 
			void delegate() 	onResetTextSelection,
			void delegate() 	onMoveStarted
		)
		{
			version(/+$DIDE_REGION+/all)
			{
				version(/+$DIDE_REGION detect mouse travel+/all) {
					if(inputs.LMB.down)
					mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta); 
					else
					mouseTravelDistance = 0; 
				}
				
				void selectNone()
				{ select!"false"(items); } 
				void selectOnly(T item)
				{ select!"false"(items, item); } 
				void saveOldSelected()
				{ foreach(a; items) a.flags.oldSelected = a.flags.selected; } 
				
				auto mouseAct = view.mousePos.vec2; 
				//view.invTrans(frmMain.mouse.act.screen.vec2, false/+non animated!!!+/); //note: non animeted view for mouse is better.
				
				auto mouseDelta = mouseAct-mouseLast; 
				mouseLast = mouseAct; 
				
				const 	LMB	= inputs.LMB.down,
					LMB_pressed	= inputs.LMB.pressed,
					LMB_released	= inputs.LMB.released,
					Shift	= inputs.Shift.down,
					Ctrl	= inputs.Ctrl.down,
					Alt	= inputs.Alt.down; 
				
				const 	modNone	 = !Shift 	&& !Ctrl,
					modShift	 = Shift 	&& !Ctrl,
					modCtrl	 = !Shift 	&& Ctrl,
					modShiftCtrl	 = Shift 	&& Ctrl; 
				
				const inputChanged = mouseDelta || inputs.LMB.changed || inputs.Shift.changed || inputs.Ctrl.changed; 
				
				version(/+$DIDE_REGION update current selection mode+/all) {
					if(modNone) selectOp = SelectOp.clearAdd; 
					if(modShift) selectOp = SelectOp.add; 
					if(modCtrl) selectOp = SelectOp.sub; 
					if(modShiftCtrl) selectOp = SelectOp.toggle; 
				}
				
				version(/+$DIDE_REGION update dragBounds+/all) {
					if(LMB_pressed) dragSource = mouseAct; 
					if(LMB) dragBounds = bounds2(dragSource, mouseAct).sorted; 
				}
				
				version(/+$DIDE_REGION update hovered item+/all) {
					hoveredItem = null; 
					if(mouseEnabled)
					foreach(item; items)
					if(getBounds(item).contains!"[)"(mouseAct))
					hoveredItem = item; 
				}
			}version(/+$DIDE_REGION+/all)
			{
				version(/+$DIDE_REGION LMB was pressed+/all)
				{
					if(LMB_pressed && mouseEnabled)
					{
						if(
							hoveredItem && 
							(
								!hoveredItem.alwaysOnBottom || Alt
								/+
									do rectSelect on alwaysOnBottom modules 
									except when Alt is pressed.
								+/
							)
						)
						{
							if(!anyTextSelected)
							{
								if(modNone)
								{
									if(!hoveredItem.flags.selected)
									selectOnly(hoveredItem); 
									accumulatedMoveStartDelta = 0; 
									mouseOp = MouseOp.beforeMove; 
								}
								if(modShift || modCtrl || modShiftCtrl)
								hoveredItem.flags.selected = !hoveredItem.flags.selected; 
							}
							else
							{
								//any mouse operation goes to text selection
							}
						}
						else
						{
							mouseOp = MouseOp.rectSelect; 
							saveOldSelected; 
						}
					}
				}
				
				version(/+$DIDE_REGION Update ongoing operations+/all)
				{
					
					
					version(/+$DIDE_REGION update rectangle selection+/all)
					{
						if(mouseOp == MouseOp.rectSelect && inputChanged)
						{
							foreach(a; items)
							if(dragBounds.contains!"[]"(getBounds(a)))
							{
								final switch(selectOp)
								{
									case SelectOp.add, SelectOp.clearAdd: 	a.flags.selected = true; 	break; 
									case SelectOp.sub: 	a.flags.selected = false; 	break; 
									case SelectOp.toggle: 	a.flags.selected = !a.flags.oldSelected; 	break; 
									case SelectOp.none: 		break; 
								}
							}
							else
							{ a.flags.selected = (selectOp == SelectOp.clearAdd) ? false : a.flags.selected; }
						}
					}
					
					version(/+$DIDE_REGION trigger selection dragging+/all) {
						if(mouseOp == MouseOp.beforeMove && mouseTravelDistance>4)
						{
							mouseOp = MouseOp.move; 
							if(onMoveStarted)
							onMoveStarted(); 
						}
						
						if(mouseOp == MouseOp.beforeMove && mouseDelta)
						accumulatedMoveStartDelta += mouseDelta; 
					}
					
					version(/+$DIDE_REGION drag the selection+/all)
					{
						if(mouseOp == MouseOp.move && mouseDelta)
						{
							foreach(a; items)
							if(a.flags.selected)
							{
								a.outerPos += mouseDelta + accumulatedMoveStartDelta; 
								
								accumulatedMoveStartDelta = 0; 
								
								//Todo: jelezni kell valahogy az elmozdulast!!!
								version(/+$DIDE_REGION+/none)
								{
									//this is a good example of a disabled DIDE region
									static if(is(a.cachedDrawing))
									a.cachedDrawing.free; 
								}
							}
						}
					}
				}
				version(/+$DIDE_REGION LMB was released+/all)
				{
					if(LMB_released) {
						if(mouseOp == MouseOp.rectSelect) { onResetTextSelection(); }
						//...                                               ou
						
						mouseOp = MouseOp.idle; 
						accumulatedMoveStartDelta = 0; 
					}
				}
			}
		} 
	} struct TextSelectionManager
	{
		
		struct SELECTIONS; 
		@SELECTIONS
		{
			//Note: these cursors MUST BE validated!!!!!
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
			{ mustValidateInternalSelections = true; } 
			
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
		{
			private
			{
				bool 	opSelectColumn,
					opSelectColumnAdd,
					opSelectAdd,
					opSelectExtend; 
				
				DateTime lastMainMousePressTime; 
				ClickDetector cdMainMouseButton; 
				float mouseTravelDistance = 0; 
				bool doubleClick; 
				
				void updateInputs(in Workspace.MouseMappings mouseMappings)
				{
					//detectMouseTravel
					if(inputs[mouseMappings.main].down)
					{
						//Todo: copy/paste
						mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta); 
					}
					else
					{ mouseTravelDistance = 0; }
					
					cdMainMouseButton.update(inputs[mouseMappings.main].down); 
					doubleClick = cdMainMouseButton.doubleClicked; 
					
					//check if a keycombo modifier with the main mouse button isactive
					bool _kc(string sh) { return KeyCombo([sh, mouseMappings.main].join("+")).active; } 
					opSelectColumn = _kc(mouseMappings.selectColumn	); 
					opSelectColumnAdd = _kc(mouseMappings.selectColumnAdd	); 
					opSelectAdd = _kc(mouseMappings.selectAdd	); 
					opSelectExtend = _kc(mouseMappings.selectExtend	); 
					
				} 
			} 
		}
		
		void update(
			View2D 	view	, //input: mouse position,  output: zoom/scroll.
			Workspace 	workspace	, //used to access and modify textSelection, create tectCursor at mouse.
			in Workspace.MouseMappings 	mouseMappings	, //mouse buttons, shift modifier settings.
		)
		{
			//Todo: make textSelection functional, not a ref
			//Opt: only call this when the workspace changed (remove module, cut, paste)
			
			validateInternalSelections(workspace); 
			cursorAtMouse = workspace.createCursorAt(view.mousePos.vec2); 
			
			updateInputs(mouseMappings); 
			scrollInRequest.nullify; 
			if(doubleClick) wordSelecting = true; 
			
			void initiateMouseOperations()
			{
				if(auto dw = inputs[mouseMappings.zoom].delta) view.zoomAroundMouse(dw*workspace.wheelSpeed); 
				if(inputs[mouseMappings.zoomInHold].down) view.zoomAroundMouse(.125); 
				if(inputs[mouseMappings.zoomOutHold].down) view.zoom/+AroundMouse+/(-.125); 
				
				if(inputs[mouseMappings.scroll].pressed) mouseScrolling = true; 
				
				if(inputs[mouseMappings.main].pressed)
				{
					if(workspace.textSelectionsGet.hitTest(view.mousePos.vec2))
					{
						//Todo: start dragging the selection contents and paste on mouse button release
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
							}else {
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
					else if(const delta = ((inputs.mouseDelta).PR!()))
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
					
					const restrictedMousePos = opSelectColumn || opSelectColumnAdd 	? restrictPos_normal(view.mousePos.vec2, bnd) //normal clamping for columnSelect
						: restrictPos_editor(view.mousePos.vec2, bnd) /+text editor clamping for normal select+/; 
					
					auto restrictedCursorAtMouse = workspace.createCursorAt(restrictedMousePos); 
					
					if(restrictedCursorAtMouse.valid && restrictedCursorAtMouse.codeColumn==selectionAtMouse.codeColumn)
					selectionAtMouse.cursors[1] = restrictedCursorAtMouse; 
					
					if(mouseTravelDistance>4)
					scrollInRequest = restrictPos_normal(view.mousePos.vec2, bnd); //always normal clipping for mouse focus point
					//Todo: only scroll to the mouse when the mouse was dragged for a minimal distance. For a single click, the screen shoud stay where it was.
					//Todo: do this scrolling in the ModuleSelectionManager too.
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
			void combineFinalSelection()
			{
				//combine previous selection with the current mouse selection
				
				if(!selectionAtMouse.valid) return; //nothing to do with an empty selection
				
				//Todo: for additive operations, only the selections on the most recent
				
				auto applyWordSelect(TextSelection s) { return wordSelecting ? s.extendToWordsOrSpaces : s; } 
				auto applyWordSelectArr(TextSelection[] s) { return wordSelecting ? s.map!(a => a.extendToWordsOrSpaces).array : s; } 
				
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
								: getPrimaryCursor,  //Bug: what if primary cursor is on another module
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
					
					if(
						opSelectColumnAdd//Ctrl+Alt+Shift = add column selection
					)
					ts = merge(selectionsWhenMouseWasPressed ~ ts); 
					
				}
				else if(opSelectAdd || opSelectExtend)
				{
					auto actSelection = applyWordSelect(
						opSelectAdd 	? selectionAtMouse
							: TextSelection(
							cursorToExtend, 
							selectionAtMouse.caret, 
							cursorToExtend_primary
						)
							//Bug: what if primary cursor to extend is on another module
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
				
				//Todo: some selection operations may need 'overlaps' instead of 'touches'. Overlap only touch when on operand is a zeroLength selection.
				//automatically mark primary for single selections
				if(ts.length==1)
				ts[0].primary = true; 
				
				workspace.textSelectionsSet = ts; 
			} 
			
			
			//selection bussiness logic
			if(!im.wantMouse && frmMain.isForeground && view.isMouseInside) initiateMouseOperations; 
			updateMouseScrolling; 
			restrictDraggedMousePos; 
			handleReleasedSelectionButton; 
			combineFinalSelection; 
			
		} 
		
	} class BackgroundWorker(Obj, alias transformFun, alias keyFun = "a")
	{
		//Todo: make this work
		
		alias Result = ResultType!(unaryFun!transformFun); 
		
		private int destroyLevel; 
		private Obj[] inputQueue; 
		private Result[] outputQueue; 
		
		void put(Obj obj)
		{
			synchronized(this)
				inputQueue = 	inputQueue.remove!(a => unaryFun!keyFun(a) == unaryFun!keyFun(obj)) 
					~ obj; 
		} 
		
		int update(bool delegate(Result) onResult)
		{ return 0; } 
		
	} class SyntaxHighlightWorker
	{
		//SyntaxHighlightWorker ////////////////////////////////////////////
		static struct Job
		{
			DateTime changeId; //must be a globally unique id, also sorted by chronology
			CodeColumn col; //only one object allowed with the same referenceId
			
			bool valid; 
			bool opCast(b:bool)() const { return valid; } 
		} 
		
		private int destroyLevel; 
		private Job[] inputQueue, outputQueue; 
		
		void put(DateTime changeId, CodeColumn col)
		{
			synchronized(this)
				inputQueue = 	inputQueue.remove!(j => j.col is col) 
					~ Job(changeId, col); 
		} 
		
		Job getResult()
		{
			Job res; 
			synchronized(this)
				if(outputQueue.length)
					res = outputQueue.fetchFront; 
			return res; 
		} 
		
		private Job _workerGetJob()
		{
			Job res; 
			synchronized(this)
				if(inputQueue.length) {
				res = inputQueue.fetchBack; 
				res.valid = true; 
			} 
			return res; 
		} 
		
		private void _workerCompleteJob(Job job)
		{
			synchronized(this)
				outputQueue ~= job; 
		} 
		
		static private void worker(shared SyntaxHighlightWorker shw_)
		{
			auto shw = cast()shw_; 
			while(shw.destroyLevel==0)
			{
				if(auto job = shw._workerGetJob)
				{
					//actual work comes here
					shw._workerCompleteJob(job); 
				}
				else
				{
					//LOG("Worker Idling");
					sleep(10); 
				}
			}
			shw.destroyLevel = 2; 
			//LOG("Worker finished");
		} 
		
		this()
		{ spawn(&worker, cast(shared)this); } 
		
		~this()
		{
			destroyLevel = 1; 
			while(destroyLevel==1)
			{
				//LOG("Waiting for worker thread to finish");
				sleep(10); //Todo: it's slow... rewrite to message based
			}
		} 
	} version(/+$DIDE_REGION Resyntax+/all)
	{
		//Resyntax queue ////////////////////////////////////////////////////////
		
		void needResyntax(Cell cell)
		{
			//LOG(cell.text);
			
			static DateTime uniqueTime; 
			if(auto col = cell.thisAndAllParents!CodeColumn.frontOrNull)
			{
				uniqueTime.actualize; 
				
				//fast update last item if possible
				if(resyntaxQueue.map!"a.what".backOrNull is col)
				{
					resyntaxQueue.back.when = uniqueTime; 
					col.lastResyntaxTime = uniqueTime; 
					return; 
				}
				
				//remove if alreay exists
				resyntaxQueue = resyntaxQueue.remove!(e => e.what is col); 
				
				resyntaxQueue ~= ResyntaxEntry(col, uniqueTime); 
				col.lastResyntaxTime = uniqueTime; 
				
			}
			else
			assert(0, "Unhandled type"); 
		} 
		
		void UI_ResyntaxQueue()
		{
			with(im) {
				foreach(e; resyntaxQueue)
				Row(
					{
						Row(e.when.text, { width = fh*9; }); 
						if(auto col = cast(CodeColumn)e.what)
						{
							auto tc = TextCursor(col, ivec2(0, 0)); 
							Row(tc.toReference.text); 
						}
					}
				); 
			}
		} 
		
		void resyntaxNow(CodeColumn col)
		{ col.resyntax; } 
		
		void resyntaxLater(CodeColumn col, DateTime changedId)
		{ syntaxHighlightWorker.put(changedId, col); } 
		
		/// returns true if any work done or queued
		bool updateResyntaxQueue()
		{
			if(auto job = syntaxHighlightWorker.getResult)
			{
				auto col = job.col; 
				if(col.getStructureLevel >= StructureLevel.highlighted)
				{
					static DateTime lastOutdatedResyncTime; 
					if(
						col.lastResyntaxTime==job.changeId || 
						now-lastOutdatedResyncTime > .25*second
					)
					{
						//mod.resyntax_src(job.sourceCode);
						resyntaxNow(col); 
						lastOutdatedResyncTime = now; 
					}
				}
			}
			
			if(resyntaxQueue.empty) return false; 
			
			//limit the frequency of slow sourceText() calls
			static DateTime lastResyntaxLaterTime; 
			if(now-lastResyntaxLaterTime < .25*second) return false; 
			lastResyntaxLaterTime = now; 
			
			auto act = resyntaxQueue.fetchBack; 
			resyntaxLater(act.what, act.when); 
			return true; 
		} 
	}version(/+$DIDE_REGION Update+/all)
	{
		//! Update ///////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			
			//Todo: Ctrl+D word select and find
			
			//Mouse ---------------------------------------------------
			
			struct MouseMappings
			{
				string 	main	= "LMB",
					scroll	= "MMB", //Todo: soft scroll/zoom, fast scroll
					menu	= "RMB",
					zoom	= "MW",
					zoomInHold	= "MB5",
					zoomOutHold	= "MB4",
					selectAdd	= "Alt",
					selectExtend	= "Shift",
					selectColumn	= "Shift+Alt",
					selectColumnAdd 	= "Ctrl+Shift+Alt"; 
			} 
			
			private bool MMBReleasedWithoutScrolling()
			{
				return inputs.MMB.released && frmMain.mouse.hoverMax.screen.manhattanLength<=2; 
				//Todo: Ctrl+left click should be better. I think it will not conflict with the textSelection, only with module selection.
			} 
			
			void handleKeyboard()
			{
				if(!im.wantKeys && frmMain.canProcessUserInput)
				{
					callVerbs(this); 
					
					if(textSelectionsGet.empty)
					{ mainWindow.inputChars = []; }
					else
					{
						//Todo: single window only
						string unprocessed; 
						foreach(ch; mainWindow.inputChars.unTag.byDchar)
						{
							if(ch==9 && ch==10)
							{
								//if(flags.acceptEditorKeys) cmdQueue ~= EditCmd(cInsert, [ch].to!string);
							}
							else if(ch>=32)
							{
								//cmdQueue ~= EditCmd(cInsert, [ch].to!string);
								try
								{
									/+
										if(ch=='`') ch = '\U0001F4A9'; //todo: unable to input emojis
																			from keyboard or clipboard! Maybe it's a bug.
									+/
									auto s = ch.to!string; 
									textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard, s); 
								}
								catch(Exception)
								{ unprocessed ~= ch; }
							}
							else
							{ unprocessed ~= ch; }
						}
						mainWindow.inputChars = unprocessed; 
					}
				}
			} 
			
			void updateCodeLocationJump()
			{
				//jump to locations. A fucking nasty hack.
				
				if(MMBReleasedWithoutScrolling)
				{
					//T0; scope(exit) DT.LOG;
					auto hs = hitTestManager.lastHitStack; 
					if(!hs.empty)
					{ jumpTo(hs.back.id); }
				}
			} 
			
			Nullable!vec2 jumpRequest; 
			
			void jumpTo(in CodeLocation loc)
			{
				if(!loc) return; 
				
				if(auto mod = findModule(loc.file))
				{
					//Todo: load the module automatically
					
					auto searchResults = codeLocationToSearchResults(loc); 
					if(searchResults.length)
					{
						if(const bnd = searchResults.map!(r => r.bounds).fold!"a|b")
						{
							with(frmMain.view) if(scale<0.3f) scale = 1; 
							jumpRequest = nullable(vec2(bnd.center)); 
							return; 
						}
					}
				}
				
				im.flashWarning("Unable to jump to: "~loc.text); 
			} 
			
			void jumpTo(string id)
			{
				if(id.empty) return; 
				
				if(id.startsWith(CodeLocationPrefix))
				{ jumpTo(CodeLocation(id.withoutStarting(CodeLocationPrefix))); }
				else if(id.startsWith(MatchPrefix))
				{ NOTIMPL; }
			} 
			
			void handleXBox()
			{
				static DateTime t0; 
				const df = (now - t0).value((1.0f/60)*second).clamp(0, 10); //1 = 60FPS
				t0 = now; 
				
				if(!frmMain.isForeground) return; 
				
				const ss = df*32, zs = df*.18f; 
				if(auto a = inputs.xiRX.value) scrollH	(-a*ss); 
				if(auto a = inputs.xiRY.value) scrollV	(a*ss); 
				if(auto a = inputs.xiLY.value)
				{
					version(/+$DIDE_REGION move mosuse to subScreen center+/all)
					{
						{
							const p = frmMain.view.subScreenClientCenter; 
							mouseLock(mix(desktopMousePos, frmMain.clientToScreen(p), .125f)); 
							mouseUnlock; 
						}
					}
					
					version(/+$DIDE_REGION zoom around mouse+/all)
					{
						{
							//const p = frmMain.view.subScreenClientCenter;
							const p = frmMain.screenToClient(desktopMousePos); 
							frmMain.view.zoomAround(vec2(p), a*zs); //Todo: ivec2 is not implicitly converted to vec2
						}
					}
				}
			} 
			
			const mouseMappings = MouseMappings.init; 
		}version(/+$DIDE_REGION+/all)
		{
			void UI_Popup()
			{
				version(/+$DIDE_REGION Popup menu+/all)
				{
					static Module popupModule; 
					static vec2 popupGuiPos, popupWorldPos; 
					bool justPopped; 
					
					if(inputs.RMB.pressed)
					if(auto tbl = cast(ScrumTable) moduleSelectionManager.hoveredItem)
					{
						popupModule = tbl; 
						popupGuiPos = frmMain.viewGUI.mousePos.vec2; 
						popupWorldPos = frmMain.view.mousePos.vec2; 
						justPopped = true; 
					}
					
					if(popupModule)
					{
						with(im)
						{
							Column(
								{
									outerPos = popupGuiPos; 
									border = "1 normal black"; padding = "4"; theme = "tool"; 
									Row(
										{
											Text("ScrumTable Menu"); 
											if(Btn(symbol("ChromeClose"))) popupModule = null; 
										}
									); 
									Spacer; 
									if(!modules.canFind(popupModule)) popupModule = null; 
									if(popupModule)
									{
										if(Btn("New Sticker", genericId("New Sticker")).clicked)
										{
											scope(exit) popupModule = null; 
											
											const f = File(popupModule.file.path, now.timestamp ~ `.sticker`); 
											format	!`/+
Note:
+/
/+{  "color": "StickyBlue",  "pos": [%.3f, %.3f]}+/`
												(popupWorldPos.x, popupWorldPos.y)
												.saveTo(f); 
											
											//Ez felesleges volt!!! -> A loadModule() direkt fogadja a poziciot.
											version(/+$DIDE_REGION+/none)
											{
												const ms = ModuleSettings(f.fullName, popupWorldPos); 
												const idx = moduleSettings.map!"a.fileName".countUntil(ms.fileName); 
												if(idx>=0)	moduleSettings[idx] = ms; 
												else	moduleSettings ~= ms; 
											}
											
											loadModule(f, popupWorldPos); 
											
											textSelectionsSet([TextSelectionReference(f.fullName~`|C0|R0|N0|C0|R0|X0*`, &findModule).fromReference]); 
											//Miért kell egy ilyen hosszú izét beírni, hogy beleugorjon a kurzor az új dokumentumba????!!!!!!!!
											
										}
									}
								}
							); 
						}
						
						if(
							inputs.Esc.pressed 
							|| inputs.RMB.pressed && !justPopped 
							|| inputs.LMB.released && false//Todo: MUST NOT!!! Btn can't catch it in the next frame. -> LAME
							|| inputs.MMB.pressed || inputs.MB4.pressed || inputs.MB4.pressed
						)
						popupModule = null; 
					}
				}
			} void update(View2D view, in BuildResult buildResult)
			{
				//update ////////////////////////////////////
				try
				{
					//textSelections = validTextSelections;  //just to make sure. (all verbs can validate by their own will)
					
					//Note: all verbs can optonally validate textSelections by accessing them from validTextSelections
					//all verbs can call invalidateTextSelections if it does something that affects them
					handleXBox; 
					handleKeyboard; 
					
					{
						updateCodeLocationJump; 
						
						if(MMBReleasedWithoutScrolling)
						{
							if(nearestSearchResult.reference!="")
							{
								jumpTo(nearestSearchResult.reference); 
								//Todo: only do this when there was no lmouseTravelSinceLastPress
							}
						}
					}
					
					{ autoReloader.enabled = true; autoReloader.update(modules); }
					
					updateOpenQueue(1); 
					updateResyntaxQueue; 
					
					measure; //measures all containers if needed, updates ElasticTabstops
					//textSelections = validTextSelections;  //this validation is required for the upcoming mouse handling
					//and scene drawing routines.
					
					//From here every positions and sizes are correct -----------------------------------------
					
					
					//Ctrl+Click handling
					if(!im.wantMouse && view.isMouseInside && KeyCombo("Ctrl+LMB").pressed)
					{}
					
					moduleSelectionManager.update(
						!im.wantMouse && mainWindow.canProcessUserInput
						&& view.isMouseInside /+&& lod.moduleLevel+/,
						view, modules, textSelectionsGet.length>0, 
						{ textSelectionsSet = []; },
						{ bringToFrontSelectedModules; }
					); 
					textSelectionManager.update(view, this, mouseMappings); 
					
					//detect textSelection change
					const selectionChanged = textSelectionsHash.chkSet(textSelectionsGet.hashOf); 
					
					//if there are any cursors, module selection if forced to modules with textSelections
					if(selectionChanged && textSelectionsGet.length)
					{
						foreach(m; modules) m.flags.selected = false; 
						foreach(m; modulesWithTextSelection) m.flags.selected = true; 
					}
					
					//focus at selection
					if(!jumpRequest.isNull)
					{ with(frmMain.view) origin = jumpRequest.get - (subScreenOrigin-origin); }
					else if(!scrollInBoundsRequest.isNull)
					{
						const b = scrollInBoundsRequest.get; 
						frmMain.view.scrollZoom(b); 
					}
					else if(!textSelectionManager.scrollInRequest.isNull)
					{
						const p = textSelectionManager.scrollInRequest.get; 
						frmMain.view.scrollZoom(bounds2(p, p)); 
					}
					else if(selectionChanged)
					{
						if(!inputs[mouseMappings.main].down)
						{
							//don't focus to changed selection when the main mouse button is held down
							frmMain.view.scrollZoom(worldBounds(textSelectionsGet)); 
							//Todo: maybe it is problematic when the selection can't fit on the current screen
						}
					}
					scrollInBoundsRequest.nullify; 
					jumpRequest.nullify; 
					
					//animate cursors
					version(AnimatedCursors)
					{
						if(textSelectionsGet.length<=MaxAnimatedCursors)
						{
							const 	animT	= calcAnimationT(application.deltaTime.value(second), .5, .25),
								maxDist 	= 1.0f; 
							
							foreach(ref ts; textSelectionsGet)
							{
								foreach(ref cr; ts.cursors[])
								with(cr)
								{
									targetPos = localPos.pos; //Todo: animate height as well
									if(animatedPos.x.isnan)
									animatedPos = targetPos; 
									else
									animatedPos.follow(targetPos, animT, maxDist); 
								}
							}
						}
					}
					
					//update buildresults if needed (compilation progress or layer mask change)
					size_t calcBuildStateHash()
					{
						return modules	.map!"tuple(a.file, a.outerPos)"
							.array
							.hashOf(
							buildResult.lastUpdateTime.hashOf(
								markerLayerHideMask
								/+to filter compile.err+/
							)
						); 
					} 
					/+
						Opt: outerPos is tracked to detect if a module was moved. It is wastefull to rebuild 
						all the layers with all the info, only move the affected layer items.
					+/
					buildStateChanged = lastBuildStateHash.chkSet(calcBuildStateHash); 
					if(buildStateChanged)
					{
						updateModuleBuildStates(buildResult); 
						convertBuildMessagesToSearchResults; 
					}
					
					updateLastKnownModulePositions; 
					
				}
				catch(Exception e)
				{ im.flashError(e.simpleMsg); }
			} 
		}
	}
	version(/+$DIDE_REGION Keyboard mapping+/all)
	{
		//! Keyboard mapping ///////////////////////////////////////
		version(/+$DIDE_REGION Scroll and zoom view   +/all)
		{
			
			
			
			version(/+$DIDE_REGION press      +/all)
			{
				
				
				
				@VERB("Ctrl+Up") 	void scrollLineUp()
				{ scrollV(DefaultFontHeight); } 
				@VERB("Ctrl+Down") 	void scrollLineDown()
				{ scrollV(-DefaultFontHeight); } 
				@VERB("Alt+PgUp") 	void scrollPageUp()
				{ scrollV(frmMain.clientHeight*.9); } 
				@VERB("Alt+PgDn") 	void scrollPageDown()
				{ scrollV(-frmMain.clientHeight*.9); } 
				@VERB("Ctrl+=") 	void zoomIn()
				{ zoom (.5); } 
				@VERB("Ctrl+-") 	void zoomOut()
				{ zoom (-.5); } 
			}version(/+$DIDE_REGION hold      +/all)
			{
				
				
				
				@HOLD("Ctrl+Num8") void holdScrollUp()
				{ scrollV(scrollSpeed); } 
				@HOLD("Ctrl+Num2") void holdScrollDown()
				{ scrollV(-scrollSpeed); } 
				@HOLD("Ctrl+Num4") void holdScrollLeft()
				{ scrollH(scrollSpeed); } 
				@HOLD("Ctrl+Num6") void holdScrollRight()
				{ scrollH(-scrollSpeed); } 
				@HOLD("Ctrl+Num+") void holdZoomIn()
				{ zoom (zoomSpeed); } 
				@HOLD("Ctrl+Num-") void holdZoomOut()
				{ zoom (-zoomSpeed); } 
			}
			version(/+$DIDE_REGION hold slow  +/all)
			{
				
				
				
				@HOLD("Alt+Ctrl+Num8") void holdScrollUp_slow()
				{ scrollV(scrollSpeed/8); } 
				@HOLD("Alt+Ctrl+Num2") void holdScrollDown_slow()
				{ scrollV(-scrollSpeed/8); } 
				@HOLD("Alt+Ctrl+Num4") void holdScrollLeft_slow()
				{ scrollH(scrollSpeed/8); } 
				@HOLD("Alt+Ctrl+Num6") void holdScrollRight_slow()
				{ scrollH(-scrollSpeed/8); } 
				@HOLD("Alt+Ctrl+Num+") void holdZoomIn_slow()
				{ zoom (zoomSpeed/8); } 
				@HOLD("Alt+Ctrl+Num-") void holdZoomOut_slow()
				{ zoom (-zoomSpeed/8); } 
			}version(/+$DIDE_REGION hold NoSel   +/all)
			{
				//Navigation when there is	no textSelection
				
				@HOLD("W Num8 Up") void holdScrollUp2()
				{ if(textSelectionsGet.empty) scrollV(scrollSpeed); } 
				@HOLD("S Num2 Down") void holdScrollDown2()
				{ if(textSelectionsGet.empty) scrollV(-scrollSpeed); } 
				@HOLD("A Num4 Left") void holdScrollLeft2()
				{ if(textSelectionsGet.empty) scrollH(scrollSpeed); } 
				@HOLD("D Num6 Right") void holdScrollRight2()
				{ if(textSelectionsGet.empty) scrollH(-scrollSpeed); } 
				@HOLD("E Num+ PgUp") void holdZoomIn2()
				{ if(textSelectionsGet.empty) zoom (zoomSpeed); } 
				@HOLD("Q Num- PgDn") void holdZoomOut2()
				{ if(textSelectionsGet.empty) zoom (-zoomSpeed); } 
			}
			version(/+$DIDE_REGION hold slow NoSel+/all)
			{
				//Todo: this is redundant and ugly
				/+
					Bug: When NumLockState=true && key==Num8: if the modifier is released
									after the key, KeyCombo will NEVER detect the release and is stuck!!!
				+/
				@HOLD("Shift+W Shift+Num8 Shift+Up") void holdScrollUp_slow2()
				{ if(textSelectionsGet.empty) scrollV(scrollSpeed/8); } 
				@HOLD("Shift+S Shift+Num2 Shift+Down") void holdScrollDown_slow2()
				{ if(textSelectionsGet.empty) scrollV(-scrollSpeed/8); } 
				@HOLD("Shift+A Shift+Num4 Shift+Left") void holdScrollLeft_slow2()
				{ if(textSelectionsGet.empty) scrollH(scrollSpeed/8); } 
				@HOLD("Shift+D Shift+Num6 Shift+Right") void holdScrollRight_slow2()
				{ if(textSelectionsGet.empty) scrollH(-scrollSpeed/8); } 
				@HOLD("Shift+E Shift+Num+ Shift+PgUp") void holdZoomIn_slow2()
				{ if(textSelectionsGet.empty) zoom (zoomSpeed/8); } 
				@HOLD("Shift+Q Shift+Num- Shift+PgDn") void holdZoomOut_slow2()
				{ if(textSelectionsGet.empty) zoom (-zoomSpeed/8); } 
			}
			@VERB("Home"	) void zoomAll2()
			{ if(textSelectionsGet.empty) frmMain.view.zoom(worldInnerBounds(this), 12); } 
			@VERB("Shift+Home"	) void zoomClose2()
			{ if(textSelectionsGet.empty) frmMain.view.scale = 1; } 
			
		}version(/+$DIDE_REGION Locations, memory slots+/all)
		{
			struct Location
			{
				vec2 origin = vec2(0); 
				float zoomFactor = 1; 
			} 
			
			@STORED Location[10] storedLocations; 
			
			void enforceLocationIndex(int n)
			{
				enforce(
					n.inRange(storedLocations),
					n.format!"Location index out of range: %s"
				); 
			} 
			
			void storeLocation(int n)
			{
				enforceLocationIndex(n); 
				with(storedLocations[n])
				{
					origin	= frmMain.view.origin.vec2,
					zoomFactor 	= frmMain.view.scale; 
				}
				im.flashInfo(n.format!"Location %s stored."); 
			} 
			
			void jumpToLocation(int n)
			{
				enforceLocationIndex(n); 
				if(storedLocations[n] == Location.init)
				{
					im.flashWarning(n.format!"Location %s is uninitialized."); 
					return; 
				}
				with(storedLocations[n])
				{
					frmMain.view.origin	= origin.dvec2,
					frmMain.view.scale 	= zoomFactor; 
				}
			} 
			
			static foreach(i; iota(storedLocations.length).map!text)
			mixin
			(
				q{
					@VERB("Shift+Alt+#") void storeLocation#()
					{ storeLocation(#); } 
					@VERB("Alt+#"     ) void jumpToLocation#()
					{ jumpToLocation(#); } 
				}
				.replace("#", i)
			); 
			
			
			@STORED string[10] storedMemSlots; 
			
			void enforceMemSlotIndex(int n)
			{
				enforce(
					n.inRange(storedMemSlots),
					n.format!"MemSlot index out of range: %s"
				); 
			} 
			
			void copyMemSlot(int n)
			{
				enforceMemSlotIndex(n); 
				auto s = textSelectionsGet.sourceText; 
				storedMemSlots[n] = s; 
				im.flashInfo(format!"MemSlot %s %s."(n, s.empty ? "cleared" : "stored")); 
			} 
			
			void pasteMemSlot(int n)
			{
				enforceMemSlotIndex(n); 
				if(storedMemSlots[n].empty)
				{
					im.flashWarning(n.format!"MemSlot %s is empty."); 
					return; 
				}
				textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard, storedMemSlots[n]); 
			} 
			
			static foreach(i; iota(storedMemSlots.length).map!text)
			mixin
			(
				q{
					@VERB("Shift+Ctrl+#") void copyMemSlot#()
					{ copyMemSlot(#); 	} 
					@VERB("Ctrl+#"	) void pasteMemSlot#()
					{ pasteMemSlot(#); } 
				}
				.replace("#", i)
			); 
			
			
		}version(/+$DIDE_REGION+/all)
		{
			version(/+$DIDE_REGION Cursor movement+/all)
			{
				
				
				
				@VERB("Left") void cursorLeft(bool sel=false)
				{ cursorOp(ivec2(-1, 0), sel); } 
				@VERB("Right") void cursorRight(bool sel=false)
				{ cursorOp(ivec2(1, 0), sel); } 
				@VERB("Ctrl+Left") void cursorWordLeft(bool sel=false)
				{
					//Todo: Inside a node it should jump accross the node surface.
					cursorOp(ivec2(TextCursor.wordLeft, 0), sel); 
				} 
				@VERB("Ctrl+Right") void cursorWordRight(bool sel=false)
				{ cursorOp(ivec2(TextCursor.wordRight, 0), sel); } 
				@VERB("Home") void cursorHome(bool sel=false)
				//Bug: wordRight: This is bugs inside a nested comment.
				{ cursorOp(ivec2(TextCursor.home, 0), sel); } 
				@VERB("End") void cursorEnd(bool sel=false)
				{ cursorOp(ivec2(TextCursor.end, 0), sel); } 
				@VERB("Up") void cursorUp(bool sel=false)
				{ cursorOp(ivec2(0,-1), sel); } 
				/+
					Todo: Dide2: cursorUp: textSelection. non zero length, 
									Left/Right is good, Up/Down is not good. It should emulate 
									a Left/Right selection collapse first. and go Up/Down after.
				+/
				@VERB("Down") void cursorDown(bool sel=false)
				{ cursorOp(ivec2(0, 1), sel); } 
				@VERB("PgUp") void cursorPageUp(bool sel=false)
				{ cursorOp(ivec2(0,-pageSize	), sel); } 
				@VERB("PgDn") void cursorPageDown(bool sel=false)
				{ cursorOp(ivec2(0, pageSize	), sel); } 
				@VERB("Ctrl+Home") void cursorTop(bool sel=false)
				{ cursorOp(ivec2(TextCursor.home		), sel); } 
				@VERB("Ctrl+End") void cursorBottom(bool sel=false)
				{ cursorOp(ivec2(TextCursor.end		), sel); } 
			}
			version(/+$DIDE_REGION Cursor selection+/all)
			{
				@VERB("Shift+Left") void cursorLeftSelect()
				{ cursorLeft(true); } 
				@VERB("Shift+Right") void cursorRightSelect()
				{ cursorRight(true); } 
				@VERB("Shift+Ctrl+Left") void cursorWordLeftSelect()
				{ cursorWordLeft(true); } 
				@VERB("Shift+Ctrl+Right") void cursorWordRightSelect()
				{ cursorWordRight	(true); } 
				@VERB("Shift+Home") void cursorHomeSelect()
				{ cursorHome	(true); } 
				@VERB("Shift+End") void cursorEndSelect()
				{ cursorEnd	(true); } 
				@VERB("Shift+Up Shift+Ctrl+Up") void cursorUpSelect()
				{ cursorUp	(true); } 
				@VERB("Shift+Down Shift+Ctrl+Down") void cursorDownSelect()
				{ cursorDown	(true); } 
				@VERB("Shift+PgUp") void cursorPageUpSelect()
				{ cursorPageUp	(true); } 
				@VERB("Shift+PgDn") void cursorPageDownSelect()
				{ cursorPageDown	(true); } 
				@VERB("Shift+Ctrl+Home") void cursorTopSelect()
				{ cursorTop	(true); } 
				@VERB("Shift+Ctrl+End") void cursorBottomSelect()
				{ cursorBottom	(true); } 
			}
		}version(/+$DIDE_REGION+/all)
		{
			version(/+$DIDE_REGION More text selection+/all)
			{
				@VERB("Ctrl+Alt+Up") void insertCursorAbove()
				{ insertCursor(-1); } @VERB("Ctrl+Alt+Down") void insertCursorBelow()
				{ insertCursor(1); } 
				
				@VERB("Shift+Alt+Left") void shrinkAstSelection()
				{
					//Todo: shrink/extend Ast Selection
				} @VERB("Shift+Alt+Right") void extendAstSelection()
				{} 
				@VERB("Shift+Alt+U") void insertCursorAtStartOfEachLineSelected()
				{ textSelectionsSet = insertCursorAtStartOfEachLineSelected_impl(textSelectionsGet); } 
				
				@VERB("Shift+Alt+I") void insertCursorAtEndOfEachLineSelected()
				{ textSelectionsSet = insertCursorAtEndOfEachLineSelected_impl(textSelectionsGet); } 
				
				@VERB("Ctrl+A") void extendSelectionToModuleContents()
				{
					textSelectionsSet = modulesWithTextSelection
					.map!(m => m.content.allSelection(textSelectionsGet.any!(s => s.primary && s.moduleOf is m))).array; 
				} 
				
				@VERB("Ctrl+Shift+A") void selectAllModules()
				{ textSelectionsSet = []; modules.each!(m => m.flags.selected = true); scrollInAllModules; } 
				@VERB("") void deselectAllModules()
				{
					modules.each!(m => m.flags.selected = false); 
					//Note: this clicking on emptyness does this too.
				} 
				@VERB("Esc") void cancelSelection()
				{
					if(!im.wantKeys) cancelSelection_impl; 
					/+
						Bug: nested	commenten belulrol Escape nyomkodas (kizoomolas) 
												-> access viola: ..., Column.drawSubCells_cull, CodeRow.draw(here!)
					+/
				} 
			}
			version(/+$DIDE_REGION Text editing      +/all)
			{
				
				
				
				
				
				@VERB("Ctrl+C Ctrl+Ins") void copy()
				{
					copy_impl(textSelectionsGet.zeroLengthSelectionsToFullRows); 
					/+
						Bug: selection.isZeroLength Ctrl+C then Ctrl+V	It breaks the line. 
						Ez megjegyzi, hogy volt-e selection extension es	ha igen, akkor sorokon dolgozik. 
						A sorokon dolgozas feltetele az, hogy a target is zeroLength legyen. 
					+/
				} 
				@VERB("Ctrl+X Shift+Del") void cut()
				{
					TextSelection[] s1 = textSelectionsGet.zeroLengthSelectionsToFullRows, s2; 
					copy_impl(s1); cut_impl2(s1, s2); textSelectionsSet = s2; 
				} 
				@VERB("Backspace") void deleteToLeft()
				{
					TextSelection[] s1 = textSelectionsGet.zeroLengthSelectionsToOneLeft , s2; 
					cut_impl2(s1, s2); textSelectionsSet = s2; 
					//Todo: delete all leading tabs when the cursor is right after them
				} 
				@VERB("Del") void deleteFromRight()
				{
					TextSelection[] s1 = textSelectionsGet.zeroLengthSelectionsToOneRight, s2; 
					cut_impl2(s1, s2); textSelectionsSet = s2; 
					/+
						Bug: ha readonly, akkor NE tunjon el a kurzor! Sot, 
						ha van non-readonly selecton is, akkor azt meg el is bassza. 
					+/
					//Bug: delete should remove the leading tabs.
				} 
				
				@VERB("Ctrl+V Shift+Ins") void paste()
				{ textSelectionsSet = paste_impl(textSelectionsGet, Yes.fromClipboard, ""	); } 
				
				@VERB("Tab") void insertTab()
				{ textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard, "\t"); } 
				
				@VERB("Enter") void insertNewLine()
				{
					textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard, "\n", Yes.duplicateTabs); 
					//Todo: Must fix the tabCount on the current line first, and after that it can duplicate.
				} 
				
				@VERB("Ctrl+Enter") void insertNewPage()
				{
					/+
						Todo: it should automatically insert at the end of the selected rows.
						But what if the selection spans across multiple rows...
					+/
					textSelectionsSet = paste_impl(textSelectionsGet, No.fromClipboard, "\v"); 
					//Vertical Tab -> MultiColumn
				} 
				
				@VERB("Ctrl+]") void indent()
				{
					insertCursorAtStartOfEachLineSelected; 
					paste_impl(textSelectionsGet, No.fromClipboard, "\t"); 
				} 
				@VERB("Ctrl+[") void outdent()
				{
					insertCursorAtStartOfEachLineSelected; 
					auto ts = selectCharAtEachSelection(textSelectionsGet, '\t'); 
					if(!ts.empty)
					{
						textSelectionsSet = ts; 
						deleteToLeft; 
					}
					else
					{ im.flashWarning("Unable to outdent."); }
				} 
				
				@VERB("Alt+Up") void moveLineUp()
				{
					//TextSelection[] s1 = textSelectionsGet.zeroLengthSelectionsToFullRows, s2;
					//copy_impl(s1); cut_impl2(s1, s2); textSelectionsSet = s2;
					//Todo: moveLineUp
				} 
				
				@VERB("Alt+Down") void moveLineDown()
				{} 
				
				//Todo: UndoRedo: mindig jelolje ki a szovegreszeket, ahol a valtozasok voltak! MultiSelectionnal az osszeset!
				//Todo: UndoRedo: hash ellenorzes a teljes dokumentumra.
				
				@VERB("Ctrl+Z") void undo()
				{
					if(expectOneSelectedModule)
					undoRedo_impl!"undo"; 
				} @VERB("Ctrl+Y") void redo()
				{
					if(expectOneSelectedModule)
					undoRedo_impl!"redo"; 
				} 
			}
		}version(/+$DIDE_REGION+/all)
		{
			version(/+$DIDE_REGION File operations  +/all)
			{
				@VERB("Ctrl+O") void openModule()
				{ fileDialog.openMulti.each!(f => queueModule(f)); } 
				@VERB("Ctrl+Shift+O") void openModuleRecursive()
				{ fileDialog.openMulti.each!(f => queueModuleRecursive(f)); } 
				@VERB("Alt+O") void revertSelectedModules()
				{
					preserveTextSelections(
						{
							foreach(m; selectedModules)
							{ m.reload(desiredStructureLevel); m.fileLoaded = now; }
						}
					); 
				} 
				@VERB("Alt+S") void saveSelectedModules()
				{ selectedModules.each!"a.save"; } 
				@VERB("Ctrl+S") void saveSelectedModulesIfChanged()
				{ selectedModules.filter!"a.changed".each!"a.save"; } 
				@VERB("Ctrl+Shift+S") void saveAllModulesIfChanged()
				{ modules.filter!"a.changed".each!"a.save"; } 
				@VERB("Ctrl+W") void closeSelectedModules()
				{
					closeSelectedModules_impl; 
					//Todo: this hsould work for selections and modules based on textSelections.empty
				} 
				@VERB("Ctrl+Shift+W") void closeAllModules()
				{ closeAllModules_impl; } 
				
				@VERB("Ctrl+F") void searchBoxActivate()
				{ searchBoxActivate_request = true; } 
				@VERB("Ctrl+Shift+L") void selectSearchResults()
				{ selectSearchResults(markerLayers[BuildMessageType.find].searchResults); } 
				@VERB("F3") void gotoNextFind()
				{ NOTIMPL; } 
				@VERB("Shift+F3") void gotoPrevFind()
				{ NOTIMPL; } 
				
				@VERB("Ctrl+G") void gotoLine()
				{
					if(auto m = expectOneSelectedModule)
					{ searchBoxActivate_request = true; searchText = ":"; }
				} 
				
				@VERB("F8") void gotoNextError()
				{ NOTIMPL; } 
				@VERB("Shift+F8") void gotoPrevError()
				{ NOTIMPL; } 
				
				@VERB("F9") void run()
				{
					with(frmMain)
					if(ready && !running)
					{ saveChangedProjectModules; run; }
				} 
				@VERB("Shift+F9") void rebuild()
				{
					with(frmMain)
					if(ready && !running)
					{
						messageUICache.clear; //Todo: This UI cache should be emptied automatically.
						saveChangedProjectModules; rebuild; 
					}
				} 
				@VERB("Ctrl+F2") void kill()
				{
					with(frmMain)
					if(building || running)
					{ cancelBuildAndResetApp; }
					//Todo: some keycombo to clear error markers
				} 
				
				//@VERB("F5") void toggleBreakpoint() { NOTIMPL; }
				//@VERB("F10") void stepOver() { NOTIMPL; }
				//@VERB("F11") void stepInto() { NOTIMPL; }
			}
		}
		version(/+$DIDE_REGION Test functions+/all)
		{
			//Test functions ///////////////////////////////////////
			
			static void visitNestedCodeColumns(CodeColumn col, void delegate(CodeColumn) fun)
			{
				//only process structured or modular columns
				if(!col.isStructuredCode) return; 
				
				//recursively visit nested columns
				foreach(row; col.rows)
				foreach(cell; row.subCells)
				if(auto node = cast (CodeNode) cell)
				{
					foreach(ncell; node.subCells)
					if(auto ncol = cast(CodeColumn) ncell)
					visitNestedCodeColumns(ncol, fun); 
					
					//process joined prepositions
					if(auto decl = cast(Declaration) node)
					{
						foreach(pp; decl.allJoinedPrepositionsFromThis.drop(1))
						foreach(ppcell; pp.subCells)
						if(auto ppcol = cast(CodeColumn) ppcell)
						visitNestedCodeColumns(ppcol, fun); 
					}
				}
				
				fun(col); //do the job
			} 
			
			static void visitNestedCodeNodes(CodeColumn col, void delegate(CodeNode) fun)
			{
				//only process structured or modular columns
				if(!col.isStructuredCode) return; 
				
				//recursively visit nested columns
				foreach(row; col.rows)
				foreach(cell; row.subCells)
				if(auto node = cast (CodeNode) cell)
				{
					fun(node); 
					foreach(ncell; node.subCells)
					if(auto ncol = cast(CodeColumn) ncell)
					visitNestedCodeNodes(ncol, fun); 
					
					//process joined prepositions
					if(auto decl = cast(Declaration) node)
					foreach(pp; decl.allJoinedPrepositionsFromThis.drop(1))
					{
						fun(pp); 
						foreach(ppcell; pp.subCells)
						if(auto ppcol = cast(CodeColumn) ppcell)
						visitNestedCodeNodes(ppcol, fun); 
					}
				}
			} 
			
			void visitSelectedNestedCodeColumns(void delegate(CodeColumn) fun)
			{
				foreach_reverse(col; selectedOuterColumns)
				visitNestedCodeColumns(col, fun); 
			} 
			
			void visitSelectedNestedCodeNodes(void delegate(CodeNode) fun)
			{
				foreach_reverse(col; selectedOuterColumns)
				visitNestedCodeNodes(col, fun); 
			} 
			
			static bool removeVerticalTabs(CodeColumn col)
			{
				bool anyVT; 
				foreach(row; col.rows)
				if(row.chars.endsWith('\x0b'))
				{
					row.subCells = row.subCells[0 .. $-1]; 
					row.refreshTabIdx; 
					row.needMeasure; 
					anyVT = true; 
				}
				if(anyVT) col.measure; 
				return anyVT; 
			} 
			
			static bool addVerticalTabs(CodeColumn col, float targetHeight, float targetAspect)
			{
				bool anyVT; 
				float y0 = 0; 
				
				auto pageHeight = targetHeight; 
				//pageHeight.maximize(col.outerSize.area.sqrt / targetAspect);
				const totalHeight = col.rows.map!(r => r.outerHeight).sum; 
				const numPages = (totalHeight / pageHeight).iceil.max(1); 
				if(numPages<=1) return false; 
				
				pageHeight = totalHeight / numPages; 
				
				int actPages; 
				foreach(row; col.rows)
				if(row.outerBottom - y0 >= pageHeight)
				{
					static TextStyle tsVT; 
					static bool initialized; 
					if(initialized.chkSet) tsVT.applySyntax(skIdentifier1); //style for vertical tab
					
					y0 = row.outerBottom; 
					row.appendChar('\x0b', tsVT); 
					row.refreshTabIdx; 
					row.needMeasure; 
					anyVT = true; 
					
					actPages++; 
					if(actPages > numPages-1) break; 
				}
				if(anyVT) col.measure; 
				return anyVT; 
			} 
			
			
			
			
			@VERB void test_realignVerticalTabs()
			{
				//Todo: This fucks up Undo/Redo and ignored edit permissions.
				preserveTextSelections(
					{
						visitSelectedNestedCodeColumns((col){ removeVerticalTabs(col); }); 
						visitSelectedNestedCodeColumns((col){ addVerticalTabs(col, 2160, 16.0/9); }); 
					}
				); 
			} 
			
			@VERB void test_removeVerticalTabs()
			{
				//Todo: This fucks up Undo/Redo and ignored edit permissions.
				preserveTextSelections({ visitSelectedNestedCodeColumns((col){ removeVerticalTabs(col); }); }); 
			} 
			
			
			
			
			@VERB void test_setInternalNewLine()
			{
				//Todo: This fucks up Undo/Redo and ignored edit permissions.
				visitSelectedNestedCodeNodes(
					(CodeNode node){
						if(auto decl = cast(Declaration) node)
						{
							decl.internalNewLineCount = 1; 
							decl.needMeasure; 
						}
					}
				); 
			} 
			
			@VERB void test_clearInternalNewLine()
			{
				//Todo: This fucks up Undo/Redo and ignored edit permissions.
				visitSelectedNestedCodeNodes(
					(node){
						if(auto decl = cast(Declaration) node)
						{
							decl.internalNewLineCount = 0; 
							decl.needMeasure; 
						}
					}
				); 
			} 
			
			 @VERB void test_resyntax()
			{
				//foreach(m; modulesWithTextSelection) if(m) m.resyntax; //todo: realing the lines where font.bold has changed.
				
			} 
			
			@VERB void test_declarationStatistics()
			{
				auto files = dirPerS(Path(`c:\d\libs`), "*.d").files.map!"a.file".array; 
				//auto files = [File(`c:\d\libs\het\test\testTokenizerData\CompilerTester.d`)];
				dDeclarationRecords.clear; 
				foreach(i, f; files)
				{
					try
					{
						print(i, files.length, dDeclarationRecords.length, f); 
						auto m = scoped!Module(this, f, StructureLevel.structured); 
						if(m.isStructured) { m.content.processHighLevelPatterns_block; }else { print("Is not structured"); beep; }
					}
					catch(Exception e)
					{ WARN(e.simpleMsg); }
				}
				const fnOut = `c:\D\projects\DIDE\DLangStatistics\dDeclarationRecords.json`; 
				dDeclarationRecords.toJson.saveTo(fnOut); 
				print("DONE. DeclarationStatistics written to:", fnOut); 
				
				/+
					Todo: implement identifier qString  
										 File(`c:\D\ldc2\import\std\json.d`)
										 File(`c:\D\ldc2\import\std\xml.d`)
										 File(`c:\D\ldc-master\tools\ldc-prune-cache.d`) Invalid block closing token
									bad tokenString, not my bad...
										 File(`c:\D\ldc-master\dmd\iasmgcc.d`)
										 File(`c:\D\ldc-master\dmd\mars.d`) Invalid block closing token 
				+/
				
			} 
		}
	}version(/+$DIDE_REGION UI   +/all)
	{
		//! UI /////////////////////////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			
			deprecated void UI_ModuleBtns()
			{
				with(im) {
					File fileToClose; 
					foreach(m; modules)
					{
						if(
							Btn(
								m.file.name,
														hint(m.file.fullName),
														genericId(m.file.fullName),
														selected(0),
														{
									fh = 12; theme="tool"; 
									if(Btn(symbol("Cancel")))
									fileToClose = m.file; 
								}
							)
						) {}
					}
					if(Btn(symbol("Add"))) openModule; 
					
					if(Btn("Close All", KeyCombo("Ctrl+Shift+W"))) { closeAllModules; }
					
					if(fileToClose) closeModule(fileToClose); 
				}
			} 
			
			void UI_structureLevel()
			{
				with(im) {
					BtnRow(
						{
							Module[] modules = selectedModules; 
							if(modules.empty) modules = modulesWithTextSelection.array; 
							
							static foreach(lvl; EnumMembers!StructureLevel)
							{
								{
									const capt = lvl.text[0..1].capitalize; 
									if(
										Btn(
											{
												style.bold = modules.any!(m => m.structureLevel==lvl); 
												Text(capt); 
											}, 
											genericId(capt), 
											selected(desiredStructureLevel==lvl), 
											{ width = fh/4; },
											hint("Select desired StructureLevel.\n(Ctrl = reload and apply)")
										)
									)
									{
										desiredStructureLevel = lvl; 
										
										if(
											inputs.Ctrl.down//apply
										)
										preserveTextSelections(
											{
												Module[] cantReload; 
												foreach(m; modules)
												if(m.structureLevel != desiredStructureLevel)
												{ if(m.changed) { cantReload ~= m; }else { m.reload(desiredStructureLevel); }}
												
												if(!cantReload.empty)
												{
													beep; 
													WARN("Unable to reload modules because they has unsaved changes. ", cantReload.map!"a.file.name"); 
												}
											}
										); 
									}
								}
							}
						}
					); 
				}
			} 
			
			void UI_SearchBox(View2D view)
			{
				//UI_SearchBox /////////////////////////////////////////////
				UI_SearchBox(view, markerLayers[BuildMessageType.find].searchResults); 
			} 
			
			void zoomAt(View2D view, in Container.SearchResult[] searchResults)
			{
				if(searchResults.empty) return; 
				const maxScale = max(view.scale, 1); 
				view.zoom(searchResults.map!(r => r.bounds).fold!"a|b", 12); 
				view.scale = min(view.scale, maxScale); 
			} 
					
			void UI_SearchBox(View2D view, ref Container.SearchResult[] searchResults)
			{
				with(im)
				Row
								(
					{
						//Keyboard shortcuts
						auto 	kcFindZoom	= KeyCombo("Enter"), //only when edit is focused
							kcFindToSelection 	= KeyCombo("Ctrl+Shift+L Alt+Enter"),
							kcFindClose	= KeyCombo("Esc"); //always
						
						//activate searchbox
						bool needFocus; 
						if(!searchBoxVisible && searchBoxActivate_request)
						{ searchBoxVisible = needFocus = true; }
						searchBoxActivate_request = false; 
						
						if(searchBoxVisible)
						{
							width = fh*12; 
							
							Text("Find "); 
							.Container editContainer; 
							
							if(Edit(searchText, genericArg!"focusEnter"(needFocus), { flex = 1; editContainer = actContainer; }))
							{
								//refresh search results
								if(searchText.startsWith(':'))
								{
									//goto line
									//Todo: Ctrl+G not works inside Edit
									//Todo: hint text: Enter line number. Negative line number starts from the end of the module.
									//Todo: ez ugorhatna regionra is.
									searchResults = []; 
									textSelectionsSet = []; 
									if(auto mod = expectOneSelectedModule)
									if(auto col  = mod.content)
									if(auto rowCount = col.cellCount)
									{
										if(auto line = searchText[1..$].to!int.ifThrown(0))
										{
											
											if(line<0 && line>=-rowCount)
											line = rowCount+line+1; //mirror if negative
											
											if(auto ts = col.lineSelection_home(line, true))
											textSelectionsSet = [ts]; 
										}
									}
								}
								else
								{ searchResults = selectedModulesOrAll.map!(m => m.search(searchText)).join; }
							}
							
							//display the number of matches. Also save the location of that number on the screen.
							const matchCnt = searchResults.length; 
							Row({ if(matchCnt) Text(" ", clGray, matchCnt.text, " "); }); 
							
							if(
								Btn(
									symbol("Zoom"), isFocused(editContainer) ? kcFindZoom : KeyCombo(""),
									enable(matchCnt>0), hint("Zoom screen on search results.")
								)
							)
							{ zoomAt(view, searchResults); }
							if(
								Btn(
									"Sel", isFocused(editContainer) ? kcFindToSelection : KeyCombo(""),
									enable(matchCnt>0), hint("Select search results.")
								)
							)
							{ selectSearchResults(searchResults); }
							
							if(Btn(symbol("ChromeClose"), kcFindClose, hint("Close search box.")))
							{
								searchBoxVisible = false; 
								searchText = ""; 
								searchResults = []; 
							}
						}
						else
						{
							if(Btn(symbol("Zoom"), hint("Start searching.")))
							searchBoxActivate; 
							//Todo: this is a @VERB. Button should get the extra info from that VERB somehow.
						}
					}
				); 
				
			} 
		}version(/+$DIDE_REGION+/all)
		{
			void UI(BuildMessageType bmt, View2D view)
			{
				with(im) {
					//UI_BuildMessageTypeBtn ///////////////////////////
					//Todo: ennek nem itt a helye....
					auto hit = Btn(
						{
							const hidden = markerLayers[bmt].visible ? 0 : .75f; 
									
							auto fade(RGB c) { return c.mix(clSilver, hidden); } 
									
							const bmi = buildMessageInfo[bmt]; 
							style.bkColor = bkColor = fade(bmi.syntax.syntaxBkColor); 
							const highContrastFontColor = bmi.syntax.syntaxFontColor; 
							style.fontColor = fade(highContrastFontColor); 
							Text(bmi.caption); 
									
							if(const len = markerLayers[bmt].searchResults.length)
							{
								style.fontColor = highContrastFontColor; 
								Text(" ", len.text); 
							}
						}, genericId(bmt)
					); 
							
					if(mainWindow.isForeground && hit.pressed)
					{
						markerLayers[bmt].visible = true; 
						zoomAt(view, markerLayers[bmt].searchResults); 
					}
							
					if(mainWindow.isForeground && hit.hover && inputs.RMB.pressed)
					{ markerLayers[bmt].visible.toggle; }
				}
			} 
					
			void UI_selectedModulesHint()
			{
				with(im) {
					//UI_selectedModulesHint//////////////////////////
					auto sm = selectedModules; 
					void stats()
					{
						Row(
							format!"(%d LOC, %sB)"(
								sm.map!(m => m.linesOfCode).sum,
								shortSizeText!(1024, " ")(sm.map!(m => m.sizeBytes).sum)
							)
						); 
					} 
					if(sm.length==1)
					{
						auto m = sm.front; 
						Row(
							{ padding="0 8"; }, 
							"Selected module: ", 
							{ CodeLocation(m.file.fullName).UI; },
							{
								if(sameText(m.file.fullName, mainModuleFile.fullName))
								{ Btn("Main", enable(false)); }
								else
								{
									if(m.isMain)
									{ if(Btn("Set Main")) mainModule = m; }
								}
								stats; 
							}
						); 
					}
					else if(sm.length>1)
					{ Row({ padding="0 8"; }, sm.length.text, " modules selected ", { stats; }); }
					else
					{ Row({ padding="0 8"; }, "No modules selected."); }
				}
			} 
					
			void UI_mouseLocationHint(View2D view)
			{
				with(im) {
					if(!view.isMouseInside) return; 
					auto st = locate_snapToRow(view.mousePos.vec2); 
					if(st.length)
					{
						Row(
							{ padding="0 8"; }, "\u2316 ",
												{
								const loc = cellLocationToCodeLocation(st); 
								loc.UI; 
								
								/*
									if(loc.file && loc.line){
																if(loc.column) with(findModule(loc.file).code){
																	const pos = ivec2(loc.column, loc.line)-1;
																	Text("   ", pos.text);
																}else with(findModule(loc.file).code){
																	const pos = ivec2(st.back.localPos.x<=0 ? 0 
																		: rows[loc.line-1].cellCount, loc.line-1);
																	Text("   ", pos.text);
																}
															}
								*/
								
								/*
									auto crsr = cellLocationToTextCursor(st);
									if(crsr.valid){
										Text("   ", crsr.text, "   ", crsr.toReference.text, "   ",
											crsr.worldPos.text, "   ", view.mousePos.text);
									}
								*/
								
								if(textSelectionsGet.length>1)
								{ Text(format!"  Multiple Text Selections: %d  "(textSelectionsGet.length)); }
								else if(textSelectionsGet.length==1)
								{ Text(format!"  Text Selection: %s  "(textSelectionsGet[0].toReference.text)); }
							}
						); 
					}
				}
			} 
		}version(/+$DIDE_REGION+/all)
		{
			auto UI_ErrorList()
			{
				with(im) {
					//UI_ErrorList ////////////////////////////
					auto siz = innerSize; 
					Container
					(
						{
							outerSize = siz; 
							with(flags) {
								clipSubCells = true; 
								vScrollState = ScrollState.auto_; 
								hScrollState = ScrollState.auto_; 
							}
							
							if(auto mod = errorModule)
							{
								if(auto col = mod.content)
								{
									//total size placeholder
									Container({ outerPos = col.outerSize; outerSize = vec2(0); }); 
									
									flags.saveVisibleBounds = true; 
									if(auto visibleBounds = imstVisibleBounds(actId))
									{
										CodeRow[] visibleRows = col.rows.filter!(
											r => r.outerBounds.overlaps(visibleBounds)
											&& r.subCells.length
										).array; 
										//Opt: binary search
										
										actContainer.append(cast(Cell[])visibleRows); 
										//Note: append is important because it already has the spaceHolder Container.
										
										/+
											print("-------------------------------");
											
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
											print("-------------------------------");
										+/
									}
								}
								else
								WARN("Invalid errorList"); 
							}
						}
					); 
				}
			} 
					
			auto findErrorListItemByLocation(string locStr)
			{ if(auto mod = errorModule) if(auto col = mod.content) {}} 
					
					
			string lastNearestSearchResultReference; 
					
			Container mouseOverHintCntr; 
					
			///must be called from root level
			void UI_mouseOverHint()
			{
				with(im) {
					if(lastNearestSearchResultReference.chkSet(nearestSearchResult.reference))
					{
						mouseOverHintCntr = null; 
						
						if(nearestSearchResult.reference!="")
						{
							
							//Todo: this is dead code. ErrorModule has changed a lot.
							/+
								if(auto mod = errorModule)
									if(auto col = mod.content)
									{
										const locationRef = nearestSearchResult.reference;
										foreach(row; col.rows)
										{
											bool found = false;
											void visitLocations(.Container act)
											{
												//Todo: visitor pattern for cells/containers. 
												//Similar to the allParents() thing.
												if(!act) return;
												
												if(auto row = cast(.Row)act)
												{ if(row.id==locationRef) { found = true; } }
												foreach(sc; act.subContainers)
												visitLocations(sc); //recursive
											}
											
											visitLocations(row);
											
											if(found)
											{
												Container(
													{
														border = row.border;
														padding = row.padding;
														bkColor = row.bkColor;
														outerSize = row.outerSize;
														
														actContainer.subCells = row.subCells;
													}
												);
												mouseOverHintCntr = removeLastContainer;
												break;
											}
										}
									}
							+/
							
							//Note: This is the new buildMessage hint
							if(!mouseOverHintCntr)
							if(nearestSearchResult.reference.isWild(CodeLocationPrefix~"*") && wild[0] in messageSourceTextByLocation)
							{
								auto msgSrc = messageSourceTextByLocation[wild[0]]; 
								if(msgSrc in messageUICache) {
									mouseOverHintCntr = cast(.Container)(messageUICache[msgSrc].subCells[0]); 
									//Todo: Highlight the CodeLocation comment which is nerest to the mouse
									//Todo: show bezier arrows from the message hint's codelocations
									//Todo: a way to lock the message hint to be able to interact with it using the mouse
									//Todo: a way to scroll errorlist over the hovered item
								}
							}
							
							//if unable to generate a hint, display the SearchResult.reference:
							if(!mouseOverHintCntr) {
								Text(nearestSearchResult.reference); 
								mouseOverHintCntr = removeLastContainer; 
							}
						}
					}
					
					if(mouseOverHintCntr)
					actContainer.append(mouseOverHintCntr); 
				}
			} 
		}	
	}version(/+$DIDE_REGION Draw   +/all)
	{
		//! draw routines ////////////////////////////////////////////////////
		version(/+$DIDE_REGION+/all)
		{
			SearchResult nearestSearchResult;  //Todo: MMB jumps to nearestSearchResult
			float nearestSearchResult_dist; 
			RGB nearestSearchResult_color, _nearestSearchResult_ActColor; 
					
			void resetNearestSearchResult()
			{
				nearestSearchResult = SearchResult.init; 
				nearestSearchResult_dist = 1e30; 
			} 
					
			void updateNearestSearchResult(float dist, lazy const SearchResult sr)
			{
				if(dist<nearestSearchResult_dist)
				{
					nearestSearchResult_dist = dist; 
					nearestSearchResult = cast()sr; //Todo: constness
					nearestSearchResult_color = _nearestSearchResult_ActColor; 
				}
			} 
					
			void drawSearchResults(Drawing dr, in SearchResult[] searchResults, RGB clSearchHighLight, float extraThickness = 0)
			{
				with(dr) {
					const 	arrowSize = 12+3*blink,
						arrowThickness = arrowSize*.2f,
						
						far = lod.level>1,
						extra = lod.pixelSize* (2.5f*blink+.5f + extraThickness),
						
						clamper = RectClamperF(im.getView, arrowThickness*2); 
					
					bool isVisible(in bounds2 b)
					{ return clamper.overlaps(b); } 
					
					//always draw these
					color = clSearchHighLight; 
					_nearestSearchResult_ActColor = clSearchHighLight; 
					
					auto mp = frmMain.view.mousePos.vec2; 
					
					static float distanceB(in vec2 p, in bounds2 b)
					{
						const 	dx = max(b.low.x - p.x, 0, p.x - b.high.x),
							dy = max(b.low.y - p.y, 0, p.y - b.high.y); 
						return sqrt(dx*dx + dy*dy); 
					} 
					
					foreach(sr; searchResults)
					if(auto b = sr.bounds)
					{
						//Todo: constness
						if(isVisible(b))
						{
							updateNearestSearchResult(distanceB(mp, b), sr); 
							if(far)
							{ fillRect(b.inflated(extra)); }
							else
							{
								lineWidth = extra; 
								arrowStyle = ArrowStyle.none; 
								drawRect(b); 
							}
						}
						else
						{
							if(sr.showArrow)
							{
								lineWidth = -arrowThickness -extraThickness; 
								arrowStyle = ArrowStyle.arrow; 
								
								const p = clamper.clampArrow(b.center); 
								line(p); 
								updateNearestSearchResult(distance(mp, p[1]), sr); 
							}
						}
					}
					
					arrowStyle = ArrowStyle.none; 
					
					//later pass, draw the columns as highlighted so this will always visible
					/*
						if(!far){
											foreach(sr; searchResults)
												if(isVisible(sr.bounds)){
													dr.alpha = .5*blink;
													sr.drawHighlighted(dr, clSearchHighLight); //close lod
												}
										}
										dr.alpha = 1;
					*/
				}
			} 
		}version(/+$DIDE_REGION+/all)
		{
			/// A flashing effect, when right after the module was loaded.
			void drawModuleLoadingHighlights(string field)(Drawing dr, RGB c)
			{
				const t0 = now; 
				foreach(m; modules)
				{
					const dt = (t0-mixin("m."~field)).value(2.5f*second); 
					if(dt<1)
					drawHighlight(dr, m, c, sqr(1-dt)); 
				}
			} 
					
			/*
				protected void drawSelectedModules(Drawing dr, RGB clSelected, float selectedAlpha, RGB clHovered, float hoveredAlpha){ with(dr){
								selectedModules.each!(m => drawHighlight(dr, m, clSelected, selectedAlpha));
								drawHighlight(dr, hoveredModule, clHovered, hoveredAlpha);
							}}
			*/
					
			protected void drawSelectionRect(Drawing dr, RGB clRect)
			{
				if(auto bnd = moduleSelectionManager.selectionBounds)
				with(dr) {
					lineWidth = -1; 
					lineStyle = LineStyle.dash; 
					color = clRect; 
					drawRect(bnd); 
					lineStyle = LineStyle.normal; 
				}
			} 
					
			protected void drawMainModuleOutlines(Drawing dr)
			{
				auto mm=mainModule; 
				foreach(m; modules)
				{
					if(m==mm) { dr.color = RGB(0xFF, 0xD7, 0x00); dr.lineWidth = -2.5f; dr.drawRect(m.outerBounds); }
					else if(m.isMain) { dr.color = clSilver; dr.lineWidth = -1.5f; dr.drawRect(m.outerBounds); }
					//else if(m.file.extIs(".d")){ dr.color = clSilver; dr.lineWidth = 12; dr.drawRect(m.outerBounds); }
				}
			} 
					
			protected void drawFolders(Drawing dr, RGB clFrame, RGB clText)
			{
				//Todo: detect changes and only collect info when changed.
				
				const paths = modules.map!(m => m.file.path.fullPath).array.sort.uniq.array; 
				
				foreach(folderPath; paths)
				{
					bounds2 bnd; 
					foreach(m; modules)
					{
						const modulePath = m.file.path.fullPath; 
						if(modulePath.startsWith(folderPath))
						{
							const intermediateFolderCount = modulePath[folderPath.length..$].filter!`a=='\\'`.walkLength; 
							
							bnd |= m.outerBounds.inflated((1+intermediateFolderCount)*255.0f/*max font size ATM*/); 
						}
					}
					
					if(bnd) {
						dr.lineWidth = -1; 
						dr.color = clFrame; 
						dr.drawRect(bnd); 
					}
							
					with(cachedFolderLabel(folderPath))
					{
						outerPos = bnd.topLeft - vec2(0, 255); 
						draw(dr); 
					}
				}
			} 
			
			void drawModuleBuildStates(Drawing dr)
			{
				with(ModuleBuildState)
				foreach(m; modules)
				if(m.buildState!=notInProject)
				{
					dr.color = moduleBuildStateColors[m.buildState]; 
					dr.lineWidth = -4; 
					//if(m.buildState==compiling) dr.drawRect(m.outerBounds);
					dr.alpha = m.buildState==compiling ? mix(.15f, .55f, blink) : .15f; 
					dr.fillRect(m.outerBounds); 
				}
				dr.alpha = 1; 
			} 
		}version(/+$DIDE_REGION+/all)
		{
			void drawTextSelections(Drawing dr, View2D view)
			{
				//drawTextSelections ////////////////////////////
				version(/+$DIDE_REGION+/all)
				{
					scope(exit) dr.alpha = 1; 
					
					const 	near	= lod.zoomFactor.smoothstep(0.02, 0.1),
						clSelected	= mix(
						mix(RGB(0x404040), clGray, near*.66f),
														mix(clWhite, clGray, near*.66f), blink
					),
						clCaret	= clSilver,
						clPrimaryCaret 	= clWhite,
						alpha	= mix(0.75f, .4f, near); 
					
					const cullBounds = view.subScreenBounds_anim; 
					
					dr.color = clSelected; 
					dr.alpha = alpha; 
					foreach(sel; textSelectionsGet)
					if(!sel.isZeroLength)
					{
						auto col = sel.codeColumn; 
						const 	colInnerPos	= worldInnerPos(col), //Opt: group selections by codeColumn.
							colInnerBounds 	= bounds2(colInnerPos, colInnerPos+col.innerSize); 
						if(cullBounds.overlaps(colInnerBounds))
						{
							const localCullBounds = cullBounds - colInnerPos; 
							auto 	st	= sel.start,
								en 	= sel.end; 
							
							foreach(y; st.pos.y..en.pos.y+1)
							{
								//Todo: this loop is in the copy routine as well. Must refactor and reuse
								auto row = col.rows[y]; 
								const rowCellCount = row.cellCount; 
								
								//culling
								if(row.outerBottom	< localCullBounds.top) continue;  //Opt: trisect
								if(row.outerTop	> localCullBounds.bottom) break; 
								
								const 	isFirstRow 	= y==st.pos.y,
									isLastRow	= y==en.pos.y; 
								const 	x0 	= isFirstRow ? st.pos.x : 0,
									x1	= isLastRow ? en.pos.x : rowCellCount+1; 
								const 	rowInnerPos 	= colInnerPos + row.innerPos; 
								
								dr.translate(rowInnerPos); scope(exit) dr.pop; 
								
								if(lod.level<=1)
								{
									foreach(x; x0..x1)
									{
										
										void fade(bounds2 bnd)
										{
											dr.color = clSelected; 
											dr.alpha = alpha; 
											
											enum gap = .5f; 
											if(isFirstRow)
											{
												bnd.top += gap; 
												if(x==x0) bnd.left += gap; 
											}
											if(isLastRow)
											{
												bnd.bottom -= gap; 
												if(x==x1-1) bnd.right -= gap; 
											}
											dr.fillRect(bnd); 
										} 
										
										assert(x.inRange(0, rowCellCount), "out of range"); 
										if(x<rowCellCount)
										{
											/+
												Todo: make the nice version: the font will be NOT blended to gray, 
												but it hides the markerLayers completely. Should make a 
												text drawer that uses alpha on the background and leaves 
												the font color as is.
											+/
											/+
												if(auto g = row.glyphs[x]){
													const old = tuple(g.bkColor, g.fontColor);
													g.bkColor = mix(g.bkColor, clSelected, alpha);// g.fontColor = clBlack;
													dr.alpha = 1;
													g.draw(dr);
													g.bkColor = old[0]; g.fontColor = old[1];
												}else
											+/
											{ fade(row.subCells[x].outerBounds); }
										}
										else
										{
											//newLine
											auto g = newLineGlyph; 
											g.bkColor = row.bkColor;  g.fontColor = clGray; 
											dr.alpha = 1; 
											g.outerPos = row.newLinePos; 
											g.draw(dr); 
											
											fade(g.outerBounds); 
										}
									}
									
								}
								else
								{
									if(!isFirstRow && !isLastRow)
									{
										if(row.cellCount)
										dr.fillRect(bounds2(0, 0, row.subCells.back.outerRight, row.innerHeight)); 
									}
									else
									{
										dr.fillRect(
											bounds2(
												row.localCaretPos(x0).pos.x, 0, 
												row.localCaretPos(x1).pos.x, row.innerHeight
											)
										); 
									}
								}
							}
							
						}
					}
				}version(/+$DIDE_REGION+/all)
				{
					//caret trail
					version(AnimatedCursors)
					{
						if(textSelectionsGet.length <= MaxAnimatedCursors)
						{
							dr.alpha = blink/2; 
							dr.lineWidth = -1-(blink)*3; 
							dr.color = clCaret; 
							//Opt: culling
							//Opt: limit max munber of animated cursors
							foreach(s; textSelectionsGet)
							{
								CaretPos[3] cp; 
								cp[0] = s.caret.worldPos; 
								cp[1..3] = cp[0]; 
								cp[2].pos += s.caret.animatedPos - s.caret.targetPos; 
								cp[1].pos = mix(cp[0].pos, cp[2].pos, .25f); 
								//Todo: animate caret height too
								
								auto dir = cp[1].pos-cp[2].pos; //Todo: center them on height
								if(dir)
								{
									if(dir.normalize.x.abs<0.05f)
									{
										//vertical line
										vec2[2] p = [cp[1].pos, cp[2].pos]; 
										if(p[0].y<p[1].y) p[1].y += cp[2].height; 
										else p[0].y += cp[1].height; 
										dr.line(p[0], p[1]); 
									}
									else
									{
										//horizontal bar
										vec2[4] p; 
										p[0] = cp[1].pos; 
										p[1] = cp[1].pos + vec2(0, cp[1].height); 
										p[2] = cp[2].pos + vec2(0, cp[2].height); 
										p[3] = cp[2].pos; 
										
										if(p[0].x<p[3].x)
										{
											dr.fillTriangle(p[0], p[1], p[3]); 
											dr.fillTriangle(p[1], p[2], p[3]); 
										}
										else
										{
											dr.fillTriangle(p[3], p[2], p[0]); 
											dr.fillTriangle(p[2], p[1], p[0]); 
										}
									}
								}
							}
						}
					}
					
					
					{
						const clamper = RectClamperF(view, 7*blink+2); 
						
						auto getCaretWorldPos(TextSelection ts)
						{
							CaretPos res = ts.caret.worldPos; 
							
							if(!clamper.overlaps(res.bounds))
							{
								res.pos = clamper.clamp(res.center); 
								res.height = lod.pixelSize; 
							}
							
							return res; 
						} 
						
						auto carets = textSelectionsGet.map!getCaretWorldPos.array; 
						
						void drawCarets(RGB c, float shadow=0)
						{
							dr.alpha = blink; 
							dr.lineWidth = -1-(blink)*3 -shadow; 
							dr.color = c; 
							foreach(cwp; carets) cwp.draw(dr); 
						} 
						
						drawCarets(clBlack, 3); 	//shadow
						drawCarets(clCaret); 	//inner
						
						//primary
						if(auto ts = primaryTextSelection)
						{
							dr.color = clPrimaryCaret; 
							getCaretWorldPos(ts).draw(dr); 
						}
					}
				}
			} 
		}version(/+$DIDE_REGION+/all)
		{
			void customDraw(Drawing dr)
			{
				//customDraw //////////////////////////////
				if(textSelectionsGet.empty)
				{
					//select means module selection
					foreach(m; modules)
					if(m.flags.selected)
					drawHighlight(dr, m, clAccent, .25); 
					if(!lod.codeLevel)
					{
						if(0/+It's annoying, so I disabled it.+/)
						drawHighlight(dr, hoveredModule, clWhite, .125); 
					}
				}
				else
				{
					//select means text editing
					foreach(m; modules)
					if(!m.flags.selected)
					drawHighlight(dr, m, clGray, .25); 
				}
				
				if(lod.moduleLevel || frmMain.building) drawModuleBuildStates(dr); 
				
				drawModuleLoadingHighlights!"fileLoaded"(dr, clAqua  ); 
				drawModuleLoadingHighlights!"fileSaved" (dr, clYellow); 
				
				drawMainModuleOutlines(dr); 
				drawFolders(dr, clGray, clWhite); 
				drawSelectionRect(dr, clAccent); 
				
				resetNearestSearchResult; 
				foreach_reverse(t; EnumMembers!BuildMessageType)
				if(markerLayers[t].visible)
				drawSearchResults(dr, markerLayers[t].searchResults, buildMessageInfo[t].syntax.syntaxBkColor); 
				
				if(nearestSearchResult_dist > frmMain.view.invScale*24)
				nearestSearchResult = SearchResult.init; 
				
				if(nearestSearchResult.bounds)
				{ drawSearchResults(dr, [nearestSearchResult], nearestSearchResult_color.mix(clWhite, .5f)); }
				
				.draw(dr, globalChangeindicatorsAppender[]); globalChangeindicatorsAppender.clear; 
				.drawProbes(dr); globalVisibleProbes.clear; 
				
				drawTextSelections(dr, frmMain.view); //Bug: this will not work for multiple workspace views!!!
				
				void drawProgressBalls()
				{
					//Todo: put this into the drawing module
					dr.pointSize = 25; 
					dr.color = clBlue; 
					foreach(i; -10..10)
					{
						const t = (i + QPS.value(0.5 * second).fract) / 3; 
						dr.point((t+t^^5)*100, 0); 
					}
				} 
			} 
			
			
			override void onDraw(Drawing dr)
			{} 
			
			override void draw(Drawing dr)
			{
				globalChangeindicatorsAppender.clear; 
				
				structureMap.beginCollect; 
				super.draw(dr); 
				structureMap.endCollect(dr); 
				customDraw(dr); 
			} 
		}
	}
} 