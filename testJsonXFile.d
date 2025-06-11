//@exe
//@debug
//@release

import het.ui, dideinsight; 

version(all)
{
	/+
		ChatGPT query:
		In dlang I have an array of strings.
		The strings contain fully qualified names of an identifier, with the full path, separated by dot '.' character.
		The individual parts can contain a template parameter list after the identifier eg: "id!(1, 2)" These are part of the identifier, this specifies a single path location.
		After the last identifier with optional template parameters, there can be a parameter list, it that particular item is a function. Example: "fun(int param1, string param2) : string"
		Your task is to process the alphabetically ordered input string array with the fully qualified names and produce a hierarchical text output with visual block drawing characters. It should look like the result of the DOS tree command.
	+/
	
	
	import std.regex; 
	
	
	// Structure to represent a node in the hierarchy
	struct TreeNode(T)
	{
		T data; 
		TreeNode[] children; 
		
		this(T data) { this.data = data; } 
		
		void addChild(TreeNode node) { children ~= node; } 
	} 
	
	// Parse a fully qualified name into its components
	string[] parseQualifiedName(string fullyQualifiedName)
	{
		//auto regex = ctRegex!`(?<!\w)([a-zA-Z_][a-zA-Z0-9_]*!(\([^)]*\))?|[a-zA-Z_][a-zA-Z0-9_]*)(\([^)]*\)\s*:\s*[a-zA-Z_][a-zA-Z0-9_]*\s*)?`; 
		//auto regex = ctRegex!`([a-zA-Z_][a-zA-Z0-9_]*!(\\([^)]*\\))?|[a-zA-Z_][a-zA-Z0-9_]*)(\\([^)]*\\)\\s*:\\s*[a-zA-Z_][a-zA-Z0-9_]*|\\([^)]*\\))?`; 
		auto regex = ctRegex!`[a-zA-Z_][a-zA-Z0-9_]*(?:!(\\([^)]*\\)))?(?:\\([^)]*\\))?`; 
		return fullyQualifiedName.matchAll(regex).map!(m => m.hit).array; 
	} 
	
	// Add a fully qualified name to the tree
	void addQualifiedName(ref TreeNode!string root, string[] parts)
	{
		auto current = &root; 
		
		foreach(part; parts) {
			auto child = current.children.find!(c => c.data == part); 
			if(child.empty) {
				current.children ~= TreeNode!string(part); 
				current = &current.children[$ - 1]; 
			}else { current = &child.front; }
		}
	} 
	
	// Generate the hierarchical tree output
	static if(0)
	void printTree(TreeNode!string node, string prefix = "")
	{
		writeln(prefix, node.data); 
		
		foreach(i, child; node.children) {
			string newPrefix = prefix ~ (i == node.children.length - 1 ? "  └─" : "  ├─"); 
			printTree(child, newPrefix); 
		}
		
		/+
			- Thank you! There were some errors, but I was able to fix.  It was DLang specific stuff, I know your knowledge is mainly C++.  Dlang is an exotic language..
			GPT: You're welcome! I'm glad you could resolve the issues—it's always impressive to work with such a niche language like DLang. If you need help fine-tuning or exploring other ideas, just let me know!
			
			- But the result is not perfect:
			root
				 └─com
				 └─	 └─example
				 └─	 └─	 ├─Class!(int, string)
				 └─	 └─	 ├─  └─method(int x, int y) : void
				 └─	 └─	 └─OtherClass
				 └─	 └─	 └─  └─subMethod!(true)
			GPT: Thank you for pointing that out! The issue lies in the incorrect use of block-drawing characters in the tree output. Specifically, the prefixes (├─, └─, etc.) aren't being constructed properly when traversing multiple levels of the tree.
			
			Here's the fixed version of the printTree function that ensures the tree structure renders correctly:
		+/
	} 
	
	// Generate the hierarchical tree output
	void printTree(in TreeNode!string node, string prefix = "", bool isLast = true)
	{
		// Print the current node
		if(node.data != "root") { writeln(prefix ~ (isLast ? "└─ " : "├─ ") ~ node.data); }
		
		// Update the prefix for children
		auto newPrefix = prefix ~ (isLast ? "   " : "│  "); 
		
		foreach(i, child; node.children) { printTree(child, newPrefix, i == node.children.length - 1); }
	} 
	
	void treeFqn(string[] input)
	{
		// Input: Alphabetically sorted array of fully qualified names
		static if(0)
		input = [
			"com.example.Class!(int, string)",
			"com.example.Class!(int, string).method(int x, int y) : void",
			"com.example.OtherClass",
			"com.example.OtherClass.subMethod!(true)"
		]; 
		
		// Root of the tree
		auto root = TreeNode!string("root"); 
		
		// Build the tree
		foreach(name; input) {
			auto parts = parseQualifiedName(name); 
			addQualifiedName(root, parts); 
		}
		
		// Print the tree
		printTree(root); 
	} 
}

import het, het.parser; 

import std.parallelism; 








struct DirNode
{
	import std.sumtype; 
	SumType!(File, Path) _node; 
	
	bool opened; 
	DirNode[] subNodes; 
	
	__gshared string rootPaths, pattern="*"; 
	
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
		return _node.match!(
			((Path p){
				if(p)
				{
					subNodes = chain(
						p.paths	.map!DirNode, 
						p.files(pattern)	.map!DirNode
					).array; 
				}
				else
				{ subNodes = rootPaths.split(';').map!strip.array.sort.map!Path.map!DirNode.array; }
				return subNodes; 
			}), ((File f)=>(null))
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
		/+
			remember
			opened items
		+/
	} 	 void toggle()
	{
		if(opened)	close; 
		else	open; 
	} 
	
	void UI()
	{
		with(im)
		{
			void Img(string s) { Spacer(4); im.Img(`icon:\`~s~`&small`); Spacer(4); } 
			_node.match!
			(
				((in File  f){ Img('.'~f.ext); Text(f.name); }), 
				((in Path p){ Img(((p.fullPath.isWild("?:")) ?(p.fullPath):(`folder`))~'\\'); Text(bold(p.name)); })
			); 
		}
	} 
} 

class MainForm : GLWindow
{
	mixin autoCreate; 
	
	version(/+$DIDE_REGION+/all) {
		const hetlibFiles = 
		[
			`c:\d\libs\het\package.d`,
			`c:\d\libs\het\quantities.d`,
			`c:\d\libs\het\math.d`,
			`c:\d\libs\het\inputs.d`,
			`c:\d\libs\het\parser.d`,
			`c:\d\libs\het\ui.d`,
			`c:\d\libs\het\opengl.d`,
			`c:\d\libs\het\win.d`,
			`c:\d\libs\het\algorithm.d`,
			`c:\d\libs\het\draw2d.d`,
			`c:\d\libs\het\bitmap.d`,
			`c:\d\libs\het\http.d`,
			`c:\d\libs\het\db.d`,
			`c:\d\libs\het\mcu.d`,
			`c:\d\libs\het\com.d`,
			`c:\d\libs\het\vulkan.d`,
			`c:\d\libs\common\libueye.d`,
		]
		.map!File.array; 
		const dideFiles = 
		[
			`c:\d\projects\dide\dide2.d`,
			`c:\d\projects\dide\buildsys.d`,
			`c:\d\projects\dide\didemodule.d`,
		]
		.map!File.array; 
		const dideArgs = ["--d-version=stringId"]; 
		
		const karcFiles = 
		[
			`c:\d\projects\karc\karc.d`,
			`c:\d\projects\karc\karcbox.d`,
			`c:\d\projects\karc\karcpneumatic.d`,
			`c:\d\projects\karc\karctrigger.d`,
			`c:\d\projects\karc\karclogger.d`,
			`c:\d\projects\karc\karcdetect.d`,
			`c:\d\projects\karc\karcthreshold.d`,
			`c:\d\projects\karc\karcocr.d`,
		]
		.map!File.array; 
		const string[] karcArgs = []; 
	}
	
	DDB ddb; 
	string searchText; 
	
	
	VirtualTreeView!(DDB.PathNode) treeView, resultTreeView; 
	
	VirtualTreeView!DirNode dirTreeView; 
	
	override void onCreate()
	{
		ddb = new DDB(
			Path(`z:\temp2`),
			Path(`c:\d\ldc2\import`),
			Path(`c:\d\libs`),
			File(`z:\temp2\$stdlib_cache.dat`)
		); 
		treeView = new typeof(treeView); 
		enforce(chain(hetlibFiles, dideFiles, karcFiles).all!"a.exists"); 
		
		resultTreeView = new typeof(resultTreeView); 
	} 
	
	override void onUpdate()
	{
		view.navigate(!im.wantKeys, !im.wantMouse); 
		invalidate; 
		
		with(im)
		{
			Panel(
				PanelPosition.topClient, 
				{
					with(ddb)
					{
						Row(
							{
								Grp!Row(
									"Wipe", {
										if(Btn("all")) wipeAll; 
										if(Btn("project")) wipeProject; 
									}
								); 
								Grp!Row(
									"Regenerate", {
										if(Btn("phobos")) regenerateStd/+75.8MB+/; 
										if(Btn("hetLib")) regenerateLib(hetlibFiles)/+14.2MB+/; 
										if(Btn("dide")) regenerateProject(dideFiles, dideArgs)/+2.1MB+/; 
										if(Btn("karc")) regenerateProject(karcFiles, karcArgs)/+0.75MB+/; 
									} 
								); 
								Grp!Row(
									"Operations", {
										if(Btn("Save cache")) saveCache; 
										if(Btn("Load cache")) loadCache; 
										if(Btn("Stats")) generateMemberStats.print; 
										if(Btn("Export source"))
										{
											SourceTextOptions so; 
											root.sourceText(so).saveTo(File(`z:\declarations.d`)); 
											so.toJson.print; 
										}
									}
								); 
								Grp!Row(
									"State",
									{
										Text("modules: "); Static(moduleCount, { width = 3*fh; }); Spacer; 
										Text("members: "); Static(memberCount, { width = 3*fh; }); 
									}
								); 
								Grp!Row(
									"Search",
									{
										Edit(searchText, { width = fh*22; }); 
										if(Btn("Go")) {
											resultTreeView.root_ = search(searchText); 
											resultTreeView.changed = now; 
											/+Todo: This change mechanic is not so clear.+/
										}
									}
								); 
							}
						); 
					}
				}
			); 
			
			Panel(
				PanelPosition.leftClient, 
				{
					with(ddb)
					{
						treeView.root = PathNode(root); 
						treeView.UI(
							{
								outerWidth = 400; 
								outerHeight = clientHeight - 100/+this is lame...+/; 
							}
						); 
					}
				}
			); 
			Panel(
				PanelPosition.leftClient, 
				{
					resultTreeView.UI(
						{
							outerWidth = 400; 
							outerHeight = clientHeight - 100/+this is lame...+/; 
						}
					); 
				}
			); 
			
			Panel(
				PanelPosition.rightClient, 
				{
					if(!dirTreeView)
					{
						dirTreeView = new typeof(dirTreeView); 
						with(dirTreeView)
						{
							showBullet = false; showRoot = false; 
							DirNode.rootPaths = `c:\d;c:\d\libs;c:\d\projects;c:\d\ldc2\import`; 
							DirNode.pattern = `*.d;*.di;*.glsl;*.comp`; 
							root = DirNode(Path.init); 
							root.open; 
						}
					}
					dirTreeView.UI({ outerSize = vec2(300, clientHeight - 100/+this is lame...+/); }); 
				}
			); 
		}
		
	} 
} 