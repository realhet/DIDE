module dideoutline; 

import didebase; 
import didemodulemanager : ModuleManager; 
import didetextselectionmanager : TextSelectionManager; 
import didemodule : addInspectorParticle; 

static struct Outline
{
	bool activateRequest; 
	@STORED
	{
		bool visible, setupVisible; 
		string searchText; 
		string extensions = "d di glsl comp"; 
		
		
		@property string rootPaths() const
		=> (cast()(this)).treeView.root.subNodes.filter!((a)=>(a.isPath)).map!((a)=>(a.asPath.fullPath)).join(';'); 
		@property rootPaths(string s)
		{ foreach(p; s.splitter(';').map!Path) addRootPath(p); } 
	} 
	
	version(/+$DIDE_REGION Manage treeView instance+/all)
	{
		alias TreeView = VirtualTreeView!DirNode; 
		private TreeView _treeView; 
		
		
		
		auto treeView()
		{
			if(!_treeView)
			{
				_treeView = new TreeView; 
				with(_treeView)
				{
					showBullet = false; showRoot = false; 
					root = DirNode(Path.init); root.open; 
				}
			}
			return _treeView; 
		} 
		
		auto indexOfRootPath(Path p)
		=> treeView.root.subNodes.map!((a)=>(a.asPath)).countUntil(p); 
		
		void addRootPath(Path p)
		{
			if(p && p.exists)
			{
				p = p.actualPath; 
				if(indexOfRootPath(p)<0)
				with(treeView.root)
				{
					subNodes ~= DirNode(p); 
					subNodes = subNodes.sort!((a, b)=>(a.asPath < b.asPath)).array; 
					treeView.changed = now; 
				}
			}
		} 
		
		void removeRootPath(Path p)
		{
			const idx = indexOfRootPath(p); 
			if(idx>=0)
			with(treeView.root)
			{
				subNodes = subNodes.remove(idx); 
				treeView.changed = now; 
			}
		} 
		
		string lastExtensions; 
		void updateTreeView()
		{
			if(lastExtensions.chkSet(extensions))
			DirNode.pattern = extensions.splitter(' ').map!"`*.`~a".join(';'); 
		} 
	}
	
	void activate()
	{ activateRequest = true; } 
	
	void deactivate()
	{ if(visible.chkClear) { searchText = ""; }} 
	
	DirNode* focusedNode; 
	
	bool UI(ModuleManager modules, TextSelectionManager textSelections, View2D view)
	{
		with(im)
		{
			{
				bool justActivated; 
				if(activateRequest.chkClear)
				{ visible = justActivated = true; }
				
				if(visible)
				{ UI_outlinePanel(modules, textSelections, view, justActivated); }
				
				return visible; 
			}
		}
	} 
	
	
	static struct DirNode
	{
		import std.sumtype; 
		SumType!(File, Path) _node; 
		
		bool opened; 
		DirNode[] subNodes; 
		
		__gshared string rootPaths, pattern="*"; /+Todo: It's lame, but there is only a single workspace.+/
		
		this(File f)
		{ _node = f; } 	 File asFile()
		=> _node.match!(
			((File f)=>(f)), 
			((Path)=>(File.init))
		); 	 	bool isFile()
		=> _node.match!(
			((File f)=>(true)), 
			((Path)=>(false))
		); 
		this(Path p)
		{ _node = p; } 	 Path asPath()
		=> _node.match!(
			((Path p)=>(p)), 
			((File)=>(Path.init))
		); 	 bool isPath()
		=> _node.match!(
			((Path p)=>(true)), 
			((File)=>(false))
		); 
		
		@property string name() const
		=> _node.match!(
			((in File f)=>(f.name)), 
			((in Path p)=>(p.name))
		); 	 bool opEquals(A)(A other) const
		=> _node.match!(
			((in File f)=>(other.isFile && f==other.asFile)), 
			((in Path p)=>(other.isPath && p==other.asPath))
		); 
		
		DirNode[] collectSubNodes()
		{
			return _node.match!
			(
				((Path p){
					if(p)
					{
						subNodes = chain(
							p.paths.filter!((a)=>(
								!a.name.startsWith('.')
								/+exclude ".git" and alike+/
							))	.map!DirNode, 
							p.files(pattern)	.map!DirNode
						).array; 
					}
					else
					{/+Do nothing. root paths are managed from the outside.+/}
					return subNodes; 
				}), 
				((File f)=>(null))
			); 
		} 
		
		@property canOpen()
		=> isPath; 
		
		void open()
		{
			if(canOpen && opened.chkSet)
			subNodes = collectSubNodes; 
		} 	 void close()
		{
			opened = false; 
			subNodes = []; 
		} 	 void toggle()
		{
			if(opened)	close; 
			else	open; 
		} 
		
		void UI(void delegate() fun=null)
		{
			with(im)
			{
				void Img(string s) { Spacer(4); im.Img(`icon:\`~s~`&small`); Spacer(4); } 
				_node.match!
				(
					((in File  f){ Img('.'~f.ext); if(fun) fun(); Text(f.name); }), 
					((in Path p){ Img(((p.fullPath.isWild("?:")) ?(p.fullPath):(`folder`))~'\\'); if(fun) fun(); Text(bold(p.name)); })
				); 
			}
		} 
	} 
	void UI_outlinePanel(ModuleManager modules, TextSelectionManager textSelections, View2D view, bool justActivated)
	{
		with(im)
		{
			Column
			(
				{
					//Keyboard shortcuts
					auto 	kcOutlineZoom	= KeyCombo("Enter"), //only when edit is focused
						kcOutlineClose	= KeyCombo("Esc"); //always
					
					void sw() { outerWidth = fh*16; } 
					
					Row(
						{
							sw; Text("Outline"); .Container editContainer; 
							
							const searcHash = searchText.hashOf; 
							static size_t lastSearchHash; //Todo: static is ugly. It's a workspace property
							const searchHashChanged = lastSearchHash.chkSet(searcHash); 
							
							
							if(
								Edit(searchText, ((justActivated).genericArg!q{focusEnter}), { flex = 1; editContainer = actContainer; })
								|| justActivated || searchHashChanged
							)
							{ NOTIMPL; }
							
							BtnRow(
								{
									if(Btn("⚙", hint("Setup"), selected(setupVisible)))
									setupVisible.toggle; 
								}
							); 
							
							if(
								Btn(
									bold(symbol("ChevronRight")), { innerWidth = fh; }, 
									kcOutlineClose, hint("Close panel.")
								)
							)
							{ deactivate; }
						}
					); 
					
					updateTreeView; 
					
					const treeIsEmpty = treeView.root.subNodes.empty; 
					
					if(treeIsEmpty) setupVisible = true; 
					
					if(setupVisible)
					{
						Row(
							{
								sw; Text("Exts: "); 
								Edit(extensions, { flex = 1; }); 
							}
						); 
						Row(
							{
								sw; Text("Paths: "); 
								if(Btn("Add", selected(treeIsEmpty ? blink>.5f : false)))
								{
									static Path lastPath; 
									auto p = browseForFolder(mainWindow.hwnd, "Add path to Outline.", lastPath); 
									if(p) { lastPath = p; addRootPath(p); }
								}
								
								const canRemove = 	focusedNode && focusedNode.isPath && 
									indexOfRootPath(focusedNode.asPath)>=0; 
								if(Btn("Remove", enable(canRemove)))
								{
									removeRootPath(focusedNode.asPath); 
									focusedNode = null; 
								}
							}
						); 
					}
					
					
					actContainer.measure; 
					const treeHeight = mainWindow.clientHeight - outerHeight - 50; /+Todo: fucking lame. Fix aligning engine.+/
					
					treeView.UI
					(
						{
							sw; outerHeight = treeHeight; 
							/+Bug: When lots of items in the tree, moving the window by mouse become fucking slow. <1FPS 🤬 -> bitmaps()+/
						},
						((DirNode* n) {
							const 	isFile = n.isFile, 
								isPath = n.isPath,
							fullName = 	isFile 	? n.asFile.fullName : 
								isPath 	? n.asPath.fullPath : ""; 
							Module mod; if(isFile && fullName!="")
							mod = modules.findModule(fullName.File/+Opt: this is a slow query+/); 
							const canSelectModules = textSelections.empty /+Only synch module selection when no text selected.+/; 
							
							if(
								WhiteBtn
								(
									{
										border.width = 0; padding = "0 4 0 0"; margin = "0"; 
										if(mod && mod.flags.selected) style.bkColor = bkColor = mix(bkColor, clAccent, .25f); 
										n.UI(
											{
												if(isFile)
												{
													float spc = 1; 
													if(mod)	{ Led(true, ((mod.changed)?(clYellow):(clLime))); spc -= .7; }
													
													/+Todo: not works -> Spacer(spc); +/
													Text(' '); actContainer.subCells.back.outerWidth = fh*spc; 
												}
											}
										); 
										if(auto img = (cast(.Img)(actContainer.subCells.frontOrNull)))
										{
											img.flags.clickable = false; 
											img.bkColor = bkColor; 
										}
									}, 
									((n.identityStr).genericArg!q{id}), selected(focusedNode==n)
								)
							)
							{
								version(/+$DIDE_REGION onClick+/all)
								{
									focusedNode=n; 
									
									auto matchingModules(string prefix)
									{
										auto p = prefix.lc; 
										return modules.modules.filter!((m)=>(m.file.fullName.map!toLower.startsWith(p))).cache; 
									} 
									
									auto calcBounds(A)(A a)
									=> a.map!((m)=>(m.outerBounds)).fold!"a|b"(bounds2.init); 
									
									void jumpTo(string prefix, bool doZoom=false)
									{
										if(const bnd = calcBounds(matchingModules(prefix)))
										{
											addInspectorParticle(bnd, clWhite, bounds2(bnd.center, ((1).genericArg!q{radius})), .125f); 
											
											with(view)
											{
												if(doZoom)	{ scrollZoomIn(bnd); }
												else	{ scrollZoom(bnd); }
											}
										}
									} 
									
									version(/+$DIDE_REGION Detect doubleClick+/all)
									{ static string lastFullName; static DateTime lastClickTime; /+Todo: nasty static+/}
									
									
									if(fullName!="")
									{
										const isDoubleClick = lastFullName==fullName && now-lastClickTime < 0.4*second; 
										lastClickTime = now; 	lastFullName = fullName; 
										
										if(isFile && isDoubleClick && !mod)
										{
											const f = fullName.File; 
											modules.loadModule(f); 
											if(inputs.Alt.down)
											modules.queueModuleRecursive(f); 
										}else { jumpTo(fullName, isDoubleClick); }
										
										if(canSelectModules)
										{
											foreach(m; modules.modules) m.flags.selected = false; 
											foreach(m; matchingModules(fullName)) m.flags.selected = true; 
										}
									}
								}
							}
						})
					); 
				}
			); 
		}
		
	} 
} 