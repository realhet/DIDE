module didemodulemanager; 

import het.ui, dideui, didebase; 
import het.parser : CodeLocation; 
import didemodule : Module, StructureLevel, ScrumTable, ScrumSticker, cachedFolderLabel; 
import buildsys : BuildResult, ModuleBuildState, allProjectFilesFromModule, moduleBuildStateColors, buildStateIsCompleted; 
alias blink = dideui.blink; 

struct ContainerSelectionManager(T : Container)
{
	version(/+$DIDE_REGION+/all)
	{
		//Todo: Combine and refactor this with the one inside het.ui
		
		//T must have some bool properties:
		static if(1)
		static assert(
			__traits(
				compiles, {
					T a; 
					a.setSelected(a.getSelected); 
					a.setOldSelected(a.getOldSelected); 
					bounds2 b = a.getBounds; 
				}
			), "Field requirements not met."
		); 
		
		enum MouseOp
		{ idle, beforeMove, move, rectSelect} 
		MouseOp mouseOp; 
		
		enum SelectOp
		{ none, add, sub, toggle, clearAdd} 
		SelectOp selectOp; 
		
		vec2 dragSource; 
		bounds2 dragBounds;   //Todo: rect selection: if start.x>end.x then touching_select, not contain_select
		
		//these are calculated after update. No notifications, just keep calling update frequently
		T hoveredItem; 
		
		private float mouseTravelDistance = 0; 
		private vec2 accumulatedMoveStartDelta, mouseLast; 
		
		///must be called after an items removed
		void validateItemReferences(T[] items)
		{
			if(
				!items.canFind(hoveredItem)//Opt: slow linear search
			)
			hoveredItem = null; 
			//Todo: maybe use a hovered containerflag.
		}  
		
		 private static void select(alias op)(T[] items, T selectItem=null)
		{
			foreach(a; items)
			a.setSelected = a.getSelected.unaryFun!op; 
			if(selectItem) select!"true"([selectItem]); 
		}   
		
		bounds2 selectionBounds()
		{
			if(mouseOp == MouseOp.rectSelect)
			return dragBounds /+Note: It's sorted.+/; 
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
		{ foreach(a; items) a.setOldSelected = a.getSelected; } 
		
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
			if(item.getBounds.contains!"[)"(mouseAct))
			hoveredItem = item; 
		}
		version(/+$DIDE_REGION LMB was pressed+/all)
		{
			if(LMB_pressed && mouseEnabled)
			{
				if(
					hoveredItem && 
					(
						!hoveredItem.alwaysOnBottom || Alt || hoveredItem.flags.selected
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
					if(dragBounds.contains!"[]"(a.getBounds))
					{
						final switch(selectOp)
						{
							case 	SelectOp.add, 
								SelectOp.clearAdd: 	a.flags.selected = true; 	break; 
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
} class ModuleManager
{
	Module[] modules; //alias this = modules; 
	Module[ulong] moduleByHash; 
	ContainerSelectionManager!Module moduleSelectionManager; 
	File[] loadQueue/+modules queued to load+/; 
	size_t autoReloadIdx; 
	
	@STORED File mainModuleFile; 
	@STORED StructureLevel desiredStructureLevel = StructureLevel.highlighted; 
	
	//ModuleSettings is a temporal storage for saving and loading the workspace.
	struct ModuleSettings { string fileName; vec2 pos; } 
	@STORED ModuleSettings[] moduleSettings/+The current workspace+/; 
	@STORED vec2[ulong] lastModulePositions/+An ever growing list of positions for modules+/; 
	
	FileDialog fileDialog; 
	
	//outside commands.  Should do with in interfaces later.
	Container parent; 
	void delegate() afterModulesChanged; 
	void delegate(bounds2) onSmartScrollTo; 
	Module delegate() onGetPrimaryModule; 
	void delegate(string) onSetTextSelectionReference; 
	
	this()
	{
		fileDialog = new FileDialog(
			mainWindow.hwnd, "Dlang source file", ".d", 
			"DLang sources(*.d), Any files(*.*)"
		); 
	} 
	
	protected void modulesChanged()
	{
		moduleSelectionManager.validateItemReferences(modules); 
		afterModulesChanged(); 
	} 
	
	
	/+
		Todo: This saving/loading should be solved by 
		- a stored getter/setter
		- beforeSave/afterLoad
	+/
	
	void toModuleSettings()
	{ moduleSettings = modules.map!(m => ModuleSettings(m.file.fullName, m.outerPos)).array; } 
	
	void fromModuleSettings()
	{
		closeAllModules; 
		
		foreach(ms; moduleSettings)
		{
			try { loadModule(File(ms.fileName), ms.pos); }
			catch(Exception e) { WARN(e.simpleMsg); }
		}
		
		modulesChanged; 
	} 
	
	Module findModule(File file)
	{
		if(auto m = file.hashOf in moduleByHash) return *m; 
		return null; 
		/+
			//Todo: use hash of LC fileNames
				foreach(m; modules)
				if(sameText(m.file.fullName, file.fullName))
				{ WARN("slow find", "\n"~file.fullName, "\n"~m.file.fullName); return m; }
				//Opt: hash table with fileName.lc...
		+/
	} 
	
	@property Module mainModule()
	=> findModule(mainModuleFile); 
	@property void mainModule(Module m)
	{
		enforce(modules.canFind(m), "Invalid module."); 
		enforce(m.isMain, "This module can't be selected as main module."); 
		mainModuleFile = m.file; 
	} 
	
	
	auto calcBounds()
	=> modules.fold!((a, b)=>(a|b.outerBounds))(bounds2.init); 
	
	auto primaryModule()
	=> onGetPrimaryModule(); 
	
	auto selectedModules()
	=> modules.filter!((m)=>(m.flags.selected)).array; 
	
	auto unselectedModules()
	=> modules.filter!((m)=>(!m.flags.selected)).array; 
	
	auto selectedModulesOrAll()
	{
		auto a = selectedModules.array; 
		return ((a.length)?(a):(modules)); 
	} 
	
	auto hoveredModule()
	=> moduleSelectionManager.hoveredItem; 
	
	auto changedModules()
	=> modules.filter!((m)=>(m.changed)); 
	
	auto selectedStickers()
	=> selectedModules.map!((m)=>((cast(ScrumSticker)(m)))).filter!"a"; 
	
	auto projectModules()
	=> ((mainModule)?(
		allProjectFilesFromModule(mainModule.file)
		.map!((f)=>(findModule(f))).nonNulls.array
	):([])); 
	
	auto changedProjectModules()
	=> projectModules.filter!"a.changed"; 
	
	Module oneSelectedModule()
	{
		auto a = selectedModules; 
		return a.length==1 ? a[0] : null; 
	} 
	
	Module singleSelectedModule()
	{ return oneSelectedModule.ifz(primaryModule); } 
	
	Module expectOneSelectedModule()
	{
		auto m = oneSelectedModule; 
		if(!m)
		im.flashWarning("This operation requires a single selected module."); 
		//Todo: put the operation's name in the message.
		
		return m; 
	} 
	
	
	
	bool loadModule(File file)
	{
		file = file.actualFile; 
		const vec2 targetPos = lastModulePositions.get(file.hashOf, vec2(calcBounds.right+24, 0)); 
		return loadModule(file, targetPos); //default position
	} 
	
	bool loadModule(File file, vec2 targetPos)
	{
		file = file.actualFile; 
		
		if(!file.exists) return false; 
		if(auto m = findModule(file))
		{
			m.fileLoaded = now; //it's just a flash indicator
			onSmartScrollTo(m.outerBounds); 
			return false; //no loading was issued
		}
		
		Module m; 
		if(file.extIs("scrum"))	m = new ScrumTable(parent, file, desiredStructureLevel); 
		else if(file.extIs("sticker"))	m = new ScrumSticker(parent, file, desiredStructureLevel); 
		else	m = new Module(parent, file, desiredStructureLevel); 
		
		//m.flags.targetSurface = 0; not needed, workspace is on s0 already
		m.measure; 
		m.outerPos = targetPos; 
		modules ~= m; 
		moduleByHash[m.fileNameHash] = m; 
		modulesChanged; 
		
		onSmartScrollTo(m.outerBounds); 
		
		return true; 
	} 
	
	auto loadModuleRecursive(File file)
	{ allProjectFilesFromModule(file).each!((f)=>(loadModule(f))); } 
	
	void bringToFrontSelectedModules()
	{
		//Note: Do not raise alwaysOnBottom modules to the top.
		static isSel(Module m)
		{ return m.flags.selected && !m.alwaysOnBottom; } 
		
		modules = chain(
			modules.filter!(m=>!isSel(m)), 
			modules.filter!isSel
		).array; 
		
		modulesChanged; 
	} 
	
	void saveChangedProjectModules()
	{ changedProjectModules.each!"a.save"; } 
	
	void closeModule(File file)
	{
		if(auto m = findModule(file))
		{
			moduleByHash.remove(m.fileNameHash); 
			modules = modules.remove!((a)=>(a is m)); 
			modulesChanged; 
		}
	} 
	
	void closeSelectedModules()
	{
		//Todo: ask user to save if needed
		modules = unselectedModules; 
		moduleByHash = assocArray(modules.map!"a.fileNameHash".array, modules); 
		modulesChanged; 
	} 
	
	void closeAllModules()
	{
		//Todo: ask user to save if needed
		modules = []; 
		moduleByHash.clear; 
		
		modulesChanged; 
	} 
	void queueModule(File f)
	{
		/+
			Todo: this workaround is there to let the filedialog handle 
			virtual files like: virtual:\clipboard.txt.  This should be put inside openDialog class.
		+/
		if(f.fullName.isWild(`*\?*:*`)) f.fullName = wild[1].split('\\').back~':'~wild[2]; 
		loadQueue ~= f; 
	} 
	
	void queueModuleRecursive(File f)
	{ loadQueue ~= allProjectFilesFromModule(f); } 
	
	void openModule()
	{ fileDialog.openMulti.each!((f)=>(queueModule(f))); } 
	
	void openModuleRecursive()
	{ fileDialog.openMulti.each!((f)=>(queueModuleRecursive(f))); } 
	
	void updateLoadQueue(int maxWork)
	{
		while(loadQueue.length) {
			auto f = loadQueue.fetchFront; 
			if(loadModule(f)) {
				maxWork--; 
				if(maxWork<=0) return; 
			}
		}
	} 
	
	void updateModuleBuildStates(in BuildResult buildResult)
	{ foreach(m; modules) { m.buildState = buildResult.getBuildStateOfFile(m.file); }} 
	
	void updateLastKnownModulePositions()
	{ foreach(m; modules) lastModulePositions[m.fileNameHash] = m.outerPos; } 
	
	void updateAutoReload()
	{
		if(modules.empty) return; 
		
		version(/+$DIDE_REGION advance idx+/all)
		{ if(++autoReloadIdx>=modules.length) autoReloadIdx = 0; }
		
		auto m = modules[autoReloadIdx]; 
		if(typeid(m) is typeid(Module))
		if(
			!m.changed && m.fileModified < m.file.modified
			/+Opt: It takes 120us for a file.  It is problematic with the stickers...+/
			/+Todo: use windows file change notifications+/
		)
		m.reload(m.structureLevel); 
	} 
	
	void UI_selectedModulesHint()
	{
		with(im) {
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
	
	void UI_ModuleBtns()
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
	
	void UI_PopupScrumMenu(vec2 mainViewMousePos)
	{
		version(/+$DIDE_REGION Popup menu+/all)
		{
			static Module popupModule; 
			static vec2 popupGuiPos, popupWorldPos; 
			bool justPopped; 
			
			if(inputs.RMB.pressed)
			if(auto tbl = (cast(ScrumTable)(hoveredModule)))
			{
				popupModule = tbl; 
				popupGuiPos = (cast(GLWindow)(mainWindow)).viewGUI.mousePos.vec2; 
				popupWorldPos = mainViewMousePos; 
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
									format	!`/+Note:+/
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
									
									onSetTextSelectionReference(f.fullName~`|C0|R0|N0|C0|R0|X0*`); 
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
	} 
	void drawSelectionRect(Drawing dr, RGB clRect)
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
	
	void drawMainModuleOutlines(Drawing dr)
	{
		auto mm = mainModule; 
		foreach(m; modules)
		{
			if(m==mm) { dr.color = RGB(0xFF, 0xD7, 0x00); dr.lineWidth = -2.5f; dr.drawRect(m.outerBounds); }
			else if(m.isMain) { dr.color = clSilver; dr.lineWidth = -1.5f; dr.drawRect(m.outerBounds); }
			//else if(m.file.extIs(".d")){ dr.color = clSilver; dr.lineWidth = 12; dr.drawRect(m.outerBounds); }
		}
	} 
	
	void drawFolders(Drawing dr, RGB clFrame, RGB clText)
	{
		//Opt: detect changes and only collect info when changed.
		
		const paths = modules.map!((m)=>(m.file.path.fullPath)).array.sort.uniq.array; 
		
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
				dr.lineWidth = -1; dr.color = clFrame; 
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
			const bnd = m.outerBounds; 
			dr.fillRect(bnd); 
			
			if(
				lod.zoomFactor<((1.0f)/(16)) && (
					m.buildState.buildStateIsCompleted && 
					m.compilationTime>0
				)
			)
			{
				//draw a stopper clock with the latest compile time
				const 	c = bnd.center,
					r = 320; 
				dr.lineWidth = 32; 
				dr.alpha = .1; 
				
				void drawR(int deg, float r0=0, float r1=1)
				{
					const d = vec2(0, -r).rotate(deg.radians); 
					dr.line(c+d*r0, c+d*r1); 
				} 
				
				{
					const N = m.compilationTime.ifloor; 
					const cl = N<15 ? clLime : N<20 ? clYellow : N<30 ? clOrange : clRed; 
					dr.color = cl.darken(.66); dr.alpha = .25; mixin(求each(q{0<=i<60},q{},q{drawR(i*(360/60))})); dr.alpha = 1; 
					dr.color = cl; 
					mixin(求each(q{0<=i<=N},q{},q{drawR(i*(360/60))})); 
				}
				
				{
					enum N = 12; dr.color = clWhite; 
					mixin(求each(q{0<=i<N},q{},q{drawR(i*(360/N), .8)})); 
					const prevlw = dr.lineWidth; scope(exit) dr.lineWidth = prevlw; 
					dr.lineWidth = dr.lineWidth * 1.5f; 
					drawR(0, 1, 1.3); drawR(40, 1, 1.15); 
				}
				
				{ dr.color = clWhite; dr.circle(c, r); }
			}
		}
		dr.alpha = 1; 
	} 
	
	void drawModuleImportGraph(Drawing dr)
	{
		if(lod.zoomFactor<((1.0f)/(16)))
		{
			dr.arrowStyle = ArrowStyle.arrow; 
			dr.lineStyle = LineStyle.normal; 
			
			dr.lineWidth = 40; 
			dr.color = clWhite; 
			foreach(importer; modules)
			{
				const dst = importer.outerBounds.center; 
				foreach(imported; importer.importedModules)
				{
					const 	src 	= imported.outerBounds.center,
						d 	= (normalize(dst-src))*400; 
					dr.line(src+d, dst-d); 
				}
			}
			
			dr.alpha = 1; 
			dr.arrowStyle = ArrowStyle.none; 
			dr.lineStyle = LineStyle.normal; 
		}
	} 
} 