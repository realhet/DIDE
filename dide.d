//@exe
//@debug
//@release

//@compile --d-version=stringId
//@compile --d-version=VulkanUI

import core.thread, std.concurrency; 

import didebase, dideSyntaxExamples; 

import didenode : CodeComment, CodeContainer, CodeString, CodeBlock; 
import didedecl : Declaration; 
import dideexpr : ToolPalette; 
import didebuilder : Builder; 
import dideworkspace : Workspace; 

import het.inputs : callVerbs; 

/+
	Todo: /+H1: VulkanUI transition+/
	[ ] afterPaint, bloodScreenEffect.glDraw
	[ ] a legvegen a version(VulkanUI) dolgokat eltavolitani.
+/

//import het.opengl : gl, GL_COLOR_BUFFER_BIT; 
//import het.win : _createMainWindow; 

version(/+$DIDE_REGION+/all)
{
	//Todo: Ability to change comment type // /+ /*	and also todo: note: bug:
	//Todo: Ability to change the whitespace after a	preposition: space, tab, newline
	//Todo: toggle space/tab/newline after prepositions.
	//Todo: Easily Reduce Build Times by Profiling	the D Compiler   profiling the LDC2 compiler.  ldc2 -ftime-trace,  timetrace2txt, -> web perfetto.ui
	//Todo: automatic spaces around operators and ligatures.
	
	//Todo: dide builder to ignore unknown modules, like: derelict.util.loader    Because sometimes (version()) they will not be compiled at all.
	
	//Todo: wholeWords search (eleje/vege kulon)
	//Todo: filter search results per file and per syntax (comment, string, code, etc)
	
	//Todo: het.math.cmp integration with std
	
	//Todo: accept repeared keystrokes even when the FPS is low. (Ctrl+X Shift+Del Del Backspace are really slow now.)
	
	/+
		Todo: cs Kod szerkesztonek feltetlen csinald meg, hogy kijelolt szovegreszt kulon ablakban tudj editalni tobb ilyen 
		lehessen esetleg ha egy fuggveny felso soran vagy akkor automatikusan rakja ki a fuggveny torzset
	+/
	//Todo: cs lehessen splittelni: pl egyik tab full kod full scren, a masik tabon meg splittelve ket fuggveny
	
	//Todo: save/restore buildsystem cache on start/exit
	
	//Todo: Find: display a list of distinct words around the searched text. AKA Autocomplete for search.
	//Todo: kinetic scroll
	
	//Todo: module hierarchy detector should run ARFTER save when pressing F9 (Not before when the contents is different in the file and in the editor)
	
	//Todo: frame time independent lerp for view.zoomAroundMouse() https://youtu.be/YJB1QnEmlTs?t=482
	
	//Todo: Search: x=12  match -> x =12,	x =  12 too. Automatic whitespaces.
	//Todo: Structure error visibility: In	Highighted view, mark the onclosed brackets too. Not just the wrong brackets. c:\dl\broken_structure.d
	
	//Todo: markdown a commentekben.
	
	//Todo: handle newline before and after else.
	//Todo: switch(c){ static foreach(a; b) case a[0]: return a[1]; default: return 0; }    <- It case label must suck statement into it. Not just sop at the :
	//Todo: tab removal from the left side of multiline comments
	
	//Todo: inline struct.  Use it to model persistent and calculated fields of a struct/class  -> DConf Online '22 - Model all the Things!
	
	/+
		Todo: Properly handle Noman's land between preposition and the statement next to. It could be space, tab, newline with optional comments.
		Verify it still works in between adjacent preposition.
	+/
	
	//Todo: Implement q"a ... a" identifier-qstring handling in new DIDE DLang Scanner.
	/+
		Todo: CharSetBits is an example to a divergent export import operation. Every save it prepends more tabs in front of it. Delimited string bug.
			const str = q"/ NEWLINE TAB blabla NEWLINE TAB/"; 
	+/
	
	//Todo: Szerenyebb legyen az atomvillanas effekt! (module highlight, bele a settingsbe!)
	
	//Todo: Vízszintes elválasztó vonal (0x000C szabad): FormFeed. (Függôleges elválasztó vonal már van: Vertical Tab, azaz a hasábra tördelés)
	/+
		Todo: Specialis karakter: Innentôl jobbra igazítás. Kellene ilyen tipusu Elastic Tab is a számokhoz. 
		Elastic tabs, ami a balra levo szamot jobbra huzza. Ezt ki kell találni, nem kerek.
	+/
	
	//Todo: Location Slots: These should actively updated when selected.  Not just saved/loaded.  Should be always saved.
	
	//Todo: UndoRedo: mindig jelolje ki a szovegreszeket, ahol a valtozasok voltak! MultiSelectionnal az osszeset!
	//Todo: UndoRedo: hash ellenorzes a teljes dokumentumra.
	//Bug: multiselect.copy -> items are in RANDOM order
	
	//Todo: Doodling layer. (rajzolgatas, bekarikazas, nyilazas, satirozas)
	
	//Todo: find: There must be a button to repeat find operation. The [Find] caption itself...
	/+Todo: Nem megy az Alt+. emoji beszuras, mert elveszti a fokiszt es akkor eltunteti a selections.+/
	/+
		Todo: ha kijelolok tobb szoveget, akkor a masolas utan beillesztve random sorrendben fogja azokat beszurni. 
		Kibaszottul idegesítô! 
	+/
	/+Todo: Implement predSwitch as a 2 column grid!+/
	/+
		Todo: single clicking on a module which is not has a cursor, should only deselect the existing cursors and select the whole module. 
		After this on a successful doubleclict, it could place a new cursor there, (only when modifiers = none)
	+/
	
	/+
		Todo: Better debug/unittesting/code coverage
		-d-debug=...
		-unittest
		-cov
		-release
		/+
			Code: auto UT(alias fun)()
			{
				bool chk() { fun(); return true; } 
				assert(chk); 
				static assert(chk); 
			} 
			
			unittest
			{
				debug(test01)
				UT!((){
					int a=4; 
					assert(a==6, "hat"); 
					assert(a==5); 
				}); 
			} 
			
			unittest {
				debug(test02)
				UT!((){
					int a=6; 
					assert(a==6, "hat"); 
				}); 
			} 
		+/
	+/
	
	enum visualizeMarginsAndPaddingUnderMouse = (常!(bool)(0)); //Todo: make this a debug option in a menu
	
	auto frmMain()
	{ return (cast(FrmMain)mainWindow); } 
	
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
		{ flags.targetSurface = TargetSurface.world; } 
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
	
	
	class FrmMain : UIWindow
	{
		mixin autoCreate; mixin SetupMegaShader!""; 
		
		
		@STORED {
			bool mainMenuOpened; 
			
			enum MenuPage { Tools, Palette, Settings, ResMon } 
			MenuPage menuPage; 
			string toolPalettePage; 
			
			bool showModuleButtons, showTextSelectionDebugInfo, showHitTest, showUndoStack, showResyntaxQueue; 
			
			bool rightMenuOpened; 
		} 
		
		@STORED Builder builder; 
		
		Workspace workspace; 
		File workspaceFile; 
		bool initialized; //workspace has been loaded.
		
		MainOverlayContainer overlay; 
		
		string baseCaption; 
		bool isSpecialVersion; //This is a copy of the .exe that is used to cimpile dide2.exe
		
		MSQueue!string dbgRerouteQueue; 
		
		
		ToolPalette _toolPalette; @property toolPalette()
		{ if(!_toolPalette) _toolPalette = new ToolPalette; return _toolPalette; } 
		
		override void onCreate()
		{
			//onCreate //////////////////////////////////
			baseCaption = appFile.nameWithoutExt.uc; 
			isSpecialVersion = baseCaption != "DIDE2"; 
			
			builder = new Builder(
				null, null/+
					Todo: These will be initialized later.
					builder and workspace are concurrently created...
					It's bad.
				+/
			); 
			workspace = new Workspace(view, (cast(IBuildServices)(builder))); 
			
			builder.modules = workspace.modules; 
			builder.buildMessages = workspace.buildMessages; 
			
			{
				auto a = this; a.fromJson(ini.read("settings", "")); 
				//Todo: this.fromJson
			}
			
			workspaceFile = appFile.otherExt(Workspace.defaultExt); 
			overlay = new MainOverlayContainer; 
			
			dbgRerouteQueue = new MSQueue!string; 
			globalDbgRerouteQueue = dbgRerouteQueue; 
		} 
		
		override void onDestroy()
		{
			ShutdownLog(100); 
			ini.write("settings", this.toJson); 
			if(initialized) workspace.saveWorkspace(workspaceFile); 
			
			ShutdownLog(101); 
			builder.shutdown; 
			ShutdownLog(102); 
			builder.free; //builder is the first, because it uses modules, and buildMessages.
			ShutdownLog(103); 
			workspace.free; 
			ShutdownLog(104); 
		} 
		
		@VERB("Alt+F4") void closeApp()
		{ import core.sys.windows.windows; PostMessage(hwnd, WM_CLOSE, 0, 0); } 
		
		
		
		////////////////////////////////////////////////////////////////////////////////////////////////////
		
		
		
		override void onPaint()
		{
			//onPaint ///////////////////////////////////////
			version(VulkanUI)
			{ NOTIMPL("Set screen background color in vulkan"); }
			else
			{ gl.clearColor(clBlack); gl.clear(GL_COLOR_BUFFER_BIT); }
			
			toolPalette.visibleConstantNodes.clear; 
			toolPalette.visibleButtonComments.clear; 
		} 
		
		void drawOverlay(Drawing dr)
		{
			version(/+$DIDE_REGION+/none) { if(0) dr.mmGrid(view); }
			
			workspace.customDraw(dr); 
			
			scope(exit) dr.alpha = 1; 
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
		
		version(VulkanUI)
		{
			/+Todo: repair this override +/
			override void afterImDraw()
			{ NOTIMPL("bloodScreenEffect.glDraw"); } 
		}
		else
		{
			override void afterPaint()
			{ bloodScreenEffect.glDraw; } 
		}
		
		
		
		
		override void onUpdate()
		{
			workspace.mainIsForeground 	= this.isForeground; 
			//showFPS = true;
			//im.focus
			
			version(/+$DIDE_REGION update a virtual file from clipboard+/all) {
				static uint id; 
				if(id.chkSet(clipboard.sequenceNumber))
				File(`virtual:\clipboard.txt`).write(clipboard.text); 
				//Todo: sinchronize the clipboard both ways.
				//Todo: don't load too big files. And most importantly don't crash.
			}
			
			if(frmMain.isForeground && view.isMouseInside && (inputs.LMB.pressed || inputs.RMB.pressed))
			{ im.focusNothing; }
			
			updateBlink; 
			bloodScreenEffect.update; 
			
			builder.updateBuildSystem(&workspace.insight.processIncomingProjectJson/+Todo: ugly way to connect objects+/); 
			
			if(application.tick>5 && initialized.chkSet)
			{
				CodeColumn.selfTest; 
				if(workspaceFile.exists) { workspace.loadWorkspace(workspaceFile); }
			}
			
			if(dbgRerouteQueue)
			dbgRerouteQueue.fetchAll.each!((msg){
				print("Local debug mgs:", msg); 
				//Todo: convert these into flashmessages
			}); 
			
			invalidate; //Todo: low power usage
			
			version(D_Optimized)	enum D_Optimized = true; 
			else	enum D_Optimized = false; //Todo: exeBuildInfo struct into het.utils
			
			caption = format!"%s%s - [%s] %s %s"(
				baseCaption,
				D_Optimized ? " (opt)" : "",
				workspace.modules.mainModuleFile.fullName,
				workspace.modules.modules.any!"a.changed" ? "Edited" : "",
				builder.stateText
				/+
					dbgsrv.pingLedStateText,
					dbgsrv.exe_pid ? dbgsrv.exe_pid.format!"PID:%s" : "",
					dbgsrv.console_hwnd ? dbgsrv.console_hwnd.format!"CON:%s" : ""
				+/
			); 
			
			/+
				view.navigate(false/+disable keyboard navigation+/ && !im.wantKeys && !inputs.Ctrl.down 
				&& !inputs.Alt.down && isForeground, false/+worksheet.update handles it+/!im.wantMouse && isForeground);
			+/
			view.updateSmartScroll; 
			view.animSpeed = mix(view.animSpeed, 0.3f, .01f); //slowly goes to it.
			setLod(view.scale_anim); 
			
			if(canProcessUserInput) callVerbs(this); 
			
			//Menu //////////////////////////////////////////////
			if(1)
			with(im)
			{
				Panel(
					PanelPosition.topLeft, 
					{
						if(!mainMenuOpened) {
							margin = "0"; padding = "0"; /+border = "1 normal gray";+/
							if(Btn(symbol("GlobalNavigationButton"), { innerWidth = fh; })) mainMenuOpened = true; 
						}
						else {
							margin = "0"; padding = "0"; 
							Row(
								{
									if(Btn(bold(symbol("ChevronLeft")), { innerWidth = fh; })) mainMenuOpened = false; 
									BtnRow(menuPage); 
								}
							); 
							Column(
								{
									padding = "2"; 
									with(workspace)
									{
										final switch(menuPage)
										{
											case MenuPage.Tools: 	{
												UI_refactor; 
												
												Grp!Column
												(
													"Show Debug Info",
													{
														ChkBox(showModuleButtons, "Module buttons"); 
														ChkBox(showHitTest, "HitTest"); 
														ChkBox(showUndoStack, "Undo stack"); 
														ChkBox(showResyntaxQueue, "Resyntax Queue"); 
														ChkBox(showFPS	, "Show FPS Graph"); 
													}
												); 
											}	break; 
													
											case MenuPage.Palette: 	with(toolPalette) {
												UI(toolPalettePage); 
												if(templateSource!="" && KeyCombo("LMB").pressed && isForeground)
												workspace.editor.insertNode(templateSource, subColumnIdx); 
											}	break; 
													
											case MenuPage.Settings: 	Grp!Column("BuildSystem: Launch Requirements", { builder.UI_Settings; }); 	break; 
													
											case MenuPage.ResMon: 	resourceMonitor.UI(400); 	break; 
										}
									}
								}
							); 
						}
					}
				); 
				if(!mainMenuOpened)
				{
					const vec2 shiftOut = (magnitude(max((viewGUI.mousePos - lastContainer.outerBounds.bottomLeft) * vec2(1, 1), 0) * .02f))^^2 * vec2(-1, -1); 
					lastContainer.outerPos += shiftOut; 
				}
			}
			
			with(workspace)
			if(!modules.selectedStickers.empty)
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
								foreach(s; modules.selectedStickers)
								if(s.props.color.chkSet(colorName))
								s.needMeasure; 
							}
						}
					); 
				}
			); 
			
			if(showModuleButtons)
			with(im)
			Panel(
				PanelPosition.topClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					Row(
						{
							 //Todo: Panel should be a Row, not a Column...
							Row({ workspace.modules.UI_ModuleBtns; flex = 1; }); 
						}
					); 
				}
			); 
			
			if(showTextSelectionDebugInfo)
			with(im)
			with(workspace)
			{
				if(textSelections[].length)
				{
					NL; 
					if(textSelections[].length>1)
					{ Text(format!"  Multiple Text Selections: %d  "(textSelections.length)); }
					else if(textSelections[].length==1)
					{ Text(format!"  Text Selection: %s  "(textSelections[0].toReference.text)); }
				}
			}
			
			if(showHitTest)
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					Row(
						{
							Text(hitTestManager.lastHitStack.map!(a => "["~a.id.text~"]").join(` `)); 
							NL; 
							if(hitTestManager.lastHitStack.length) Text(hitTestManager.lastHitStack.back.text); 
							
							Text("\n", workspace.navig.locate_snapToRow(view.mousePos.vec2).text); 
						}
					); 
				}
			); 
			
			if(showUndoStack)
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					if(auto m = workspace.modules.primaryModule)
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
			
			
			if(showResyntaxQueue)
			with(im)
			Panel(
				PanelPosition.bottomClient,
				{
					margin = "0"; padding = "0"; //border = "1 normal gray";
					Column({ workspace.editor.UI_ResyntaxQueue; }); 
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
							
							builder.UI; 
							
							VLine; //---------------------------
							
							Row(
								{
									 flex = 1; margin = "0 3"; flags.yAlign = YAlign.center; flags.clipSubCells = true; 
									//style.fontHeight = 18+6;
									
									if(lod.moduleLevel) workspace.modules.UI_selectedModulesHint; 
									if(!lod.moduleLevel) workspace.help.UI_mouseLocationHint(workspace.navig, view); 
									
									
									enum showMousePosCellInfoHint = false; 
									if(showMousePosCellInfoHint) Text("\n", workspace.locate(view.mousePos.vec2).map!cellInfoText.join(' ')); 
								}
							); 
							
							VLine; //---------------------------
							
							BtnRow(
								{
									margin = "0 3"; 
									workspace.buildMessages.UI_LayerBtns(view); 
								}
							); 
							VLine; //---------------------------
							
							Row(
								{
									margin = "0 3"; flags.vAlign = VAlign.center; 
									version(/+$DIDE_REGION+/none) {
										if(Btn("ErrorList")) workspace.showErrorList.toggle; 
										if(Btn("Calc size")) print(workspace.allocatedSize); 
									}
									Text(
										i"$(now)
FPS=$(FPS
.format!"%.0f")  Z=$(log2(lod.pixelSize)
.format!"%.2f")  A=$(view.animSpeed
.format!"%.2f")".text
									); 
								}
							); 
							
							if(1)
							{
								VLine; 
								workspace.textSelections.UI_structureLevel; 
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
			
			with(im)
			{
				bool anyVisible; 
				Panel(
					workspace.outline.visible || workspace.insight.visible ? PanelPosition.rightClient : PanelPosition.topRight,
					{
						margin = "0"; padding = "0"; 
						bool[] vis = [
							workspace.search.UI(workspace.modules, workspace.textSelections, workspace.buildMessages, workspace.navig, view),
							workspace.insight.UI(workspace.modules, workspace.textSelections, workspace.editor, workspace.navig, view),
							workspace.outline.UI(workspace.modules, workspace.textSelections, view)
						]; /+Todo: refactor this terrible menu+/
						anyVisible = vis.any; 
						
						if(!anyVisible)
						{
							if(rightMenuOpened)
							{
								Row(
									{
										BtnRow(
											{
												if(Btn("📁", hint("Outline"))) { workspace.outlineActivate; }
												if(Btn("💡", hint("Insight"))) { workspace.insightActivate; }
												if(Btn("🔍", hint("Search"))) workspace.searchBoxActivate; 
											}
										); 
										if(Btn(bold(symbol("ChevronRight")), { innerWidth = fh; })) rightMenuOpened = false; 
									}
								); 
							}
							else
							{ if(Btn(symbol("GlobalNavigationButton"), { innerWidth = fh; })) rightMenuOpened = true; }
						}
					}
				); 
				if(!rightMenuOpened && !anyVisible)
				{
					const vec2 shiftOut = (magnitude(max((viewGUI.mousePos - lastContainer.outerBounds.bottomLeft) * vec2(-1, 1), 0) * .02f))^^2 * vec2(1, -1); 
					lastContainer.outerPos += shiftOut; 
				}
			}
			
			im.UI_FlashMessages; 
			
			workspace.update(view, builder.buildResult); 
			im.root ~= workspace; 
			
			
			version(/+$DIDE_REGION Interactive controls on modules+/all)
			{
				with(im)
				{
					Container
					(
						{
							version(/+$DIDE_REGION Temporarily switch to 'view' surface. Slider needs the correct mousePos.+/all)
							{ selectTargetSurface(TargetSurface.world); scope(exit) selectTargetSurface(TargetSurface.gui); }
							auto enabledModule = workspace.modules.primaryModule; 
							const oldStyle = style; scope(exit) style = oldStyle; 
							
							mixin(求each(q{m},q{workspace.modules.modules},q{
								const moduleIsEnabled = m is enabledModule && !m.isReadOnly; 
								m.UI_constantNodes(moduleIsEnabled, TargetSurface.world); 
							})); 
							
							const oldTheme = theme; scope(exit) style = oldStyle; 
							theme = "tool"; mixin(求each(q{m},q{workspace.modules.modules},q{m.UI_buttonComments(!m.isReadOnly, TargetSurface.world); })); 
						}
					); 
					
					root ~= removeLastContainer.subCells; //no need for the container, just the controls
				}
				
				if(dbgsrv.isActive /+Remove 'hold' on modified values. (Only hold them for a short period)+/)
				{
					const t0 = application.tick; 
					foreach(ref t; dbgsrv.data.interactiveValues.ticks) if(t<t0) t = 0; 
				}
			}
			
			im.root ~= overlay; 
			
			view.subScreenArea = im.clientArea / clientSize; 
			
			workspace.modules.UI_PopupScrumMenu(view.mousePos.vec2); 
			
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
					workspace.help.UI_mouseOverHint(workspace.buildMessages, workspace.outerWidth); 
				}
			); 
			
			
			//update mouse cursor//////////////////////////
			MouseCursor chooseMouseCursor()
			{
				with(MouseCursor)
				{
					if(builder.cancelling) return NO; 
					if(builder.building) return APPSTARTING; 
					if(im.mouseOverUI || im.wantMouse) return ARROW; //Todo: im.chooseMouseCursor
					with(workspace.modules.moduleSelectionManager)
					{
						if(mouseOp == MouseOp.move) return SIZEALL; 
						if(mouseOp == MouseOp.rectSelect) return CROSS; 
					}
					if(workspace.textSelections[].any)
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