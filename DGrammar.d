//@exe
//@release
///@debug

import het.ui, het.parser; 


/////////////////////////////////////////////
///    Syntax graph for DLang grammar     ///
/////////////////////////////////////////////

alias SyntaxLabel = GraphLabel!SyntaxDefinition; 

class SyntaxDefinition : GraphNode!(SyntaxGraph, SyntaxLabel)
{
	int zIndex; 
	
	this(SyntaxGraph parent, Token[] tokens, SourceCode src)
	{
		super(parent); 
		
		static bool isSyntaxLabel(in Token t)
		{ return (t.isIdentifier) && !t.source.among("Identifier", "IntegerLiteral", "FloatLiteral", "StringLiteral", "CharacterLiteral"); } 
		
		enforce(tokens.length>=3, "Invalid length"); 
		enforce(isSyntaxLabel(tokens[0]), "Syntax label expected instead of: "~tokens[0].text); 
		enforce(tokens[1].isOperator(opcolon)); 
		
		bkColor = clCodeBackground; border = "normal"; border.color = clGroupBorder; padding = "2"; 
		
		int lastIdx = tokens[0].pos; 
		auto ts = tsNormal; 
		foreach(idx, t; tokens)
		{
			//emit whitespace
			if(lastIdx < t.pos)
			{ ts.applySyntax(0); appendStr(src.text[lastIdx..t.pos], ts); }
			
			//emit the actual token
			if(isSyntaxLabel(t))
			{
				const isReference = idx>0; 
				append(new SyntaxLabel(this, isReference, t.source)); 
			}else
			{
				ts.applySyntax(src.syntax[t.pos]); 
				appendStr(t.source, ts); 
			}
			
			lastIdx = t.endPos; 
		}
		
		enforce(nameLabel !is null, "No target GraphLabel found. Unable to get Node's name."); 
	} 
} 

class SyntaxGraph : ContainerGraph!(SyntaxDefinition, SyntaxLabel)
{
	 // SyntaxGraph /////////////////////////////
	
	this(string text)
	{ super(); importGrammar_official(text); } 
	
	File mainFile, extraFile; 
	
	this(File mainFile, File extraFile)
	{
		this.mainFile = mainFile; 
		this.extraFile = extraFile; 
		
		this(mainFile.readText); 
		
		loadExtraData; 
	} 
	
	struct ExtraData
	{
			//Todo: exportFields, importFields between aggregates
		vec2 outerPos; 
		string groupName_override; 
	} 
	
	void saveExtraData()
	{
		nodes.map!(d => tuple(d.name, ExtraData(d.outerPos, d.groupName_override)))
			 .assocArray //Todo: ez nem stable ordered!!!
			 .toJson
			 .saveTo(extraFile, Yes.onlyIfChanged); 
	} 
	
	void loadExtraData()
	{
		ExtraData[string] tmp; 
		tmp.fromJson(extraFile.readText(false)); 
		foreach(name, data; tmp)
		{
			if(auto a = findNode(name))
			{
				static foreach(field; FieldNameTuple!(typeof(data)))
				{ mixin("a.$ = data.$;".replace("$", field)); }
			}
		}
	} 
	
	private void patch_official(ref string text)
	{
		//patch some bugs
		void patch(alias fun=replace)(string old, string new_)
		{
			enforce(text.indexOf(old)>=0, "Unable to do syntax patch "~old.quoted~" -> "~new_.quoted); 
			text = fun(text, old, new_); 
		} 
		
		void patch_removeDuplicate(string head, string contents, string remaining)
		{
			patch(head~contents, remaining); 
			enforce(text.canFind(head), "patch_removeDuplicate failed: "~quoted(head)); 
		} 
		
		patch("\r\nForeachTypeAttributes\r\n", "\r\nForeachTypeAttributes:\r\n"); //forgot :
		patch("\r\nParamClose\r\n", "\r\nParamClose:\r\n");                       //forgot :
		
		//there are 2 definitions of FunctionLiteralBody. The first one is seems outdated.
		patch_removeDuplicate("\r\nFunctionLiteralBody:\r\n", "    BlockStatement\r\n    FunctionContractsopt BodyStatement\r\n", "\r\n"); 
		
		// this part is redundant, also it has bad indentation
		patch(
			[
				"AsmStatement:", "    asm FunctionAttributesopt { AsmInstructionListopt }", "",
						  "    AsmInstructionList:", "        AsmInstruction ;", "        AsmInstruction ; AsmInstructionList"
			].join("\r\n"), ""
		); 
		
		// this garbage is at the end of the Classes section
		patch(["class Identifier : SuperClass Interfaces AggregateBody", "// ...", "new AllocatorArguments Identifier ConstructorArgs"].join("\r\n"), ""); 
		
		if(1)
		{
				//Application Binary Interface patches
			auto abiPos = text.indexOf("Application Binary Interface\r\n"); 
			enforce(abiPos>=0, "Cant fint `Application Binary Interfac` part."); 
			
			auto temp = text[abiPos..$]; 
			foreach(s; ["Type", "Parameter", "Parameters"])
			{
					//these are duplicated identifiers. Must rename them to be placed on the same graph.
				auto to = s~"_"; 
				temp = temp.replaceWords(s, to); 
				enforce(temp.canFind(to), "ABI patch failed: "~quoted(s)); 
			}
			
			text = text[0..abiPos] ~ temp; 
		}
	} 
	
	void appendDefinition_official(string def, string groupName)
	{
		def = def.replace("opt", "?"); 
		
		auto src = new SourceCode(def); 
		auto node = new SyntaxDefinition(this, src.tokens, src); 
		node.groupName_original = groupName; 
		const nextPos = subCells.length ? subCells[$-1].outerBounds.bottomLeft + vec2(0, 10) : vec2(0); 
		node.outerPos = nextPos; 
		addNode(node.name, node); 
	} 
	
	void importGrammar_official(string text)
	{
		// text is copied from glang.org/grammar.
		// Sections are marked with an identifier on the start of line:                   |Modules
		// Definitions are starting with an identifier on the start of line and a colon:  |Module:
		// Rules are placed after more than 1 spaces:                                     |   ModuleDefinition DeclDefs
		// empty lines are ignored
		
		patch_official(text); 
		
		static bool isSection   (string s)
		{ return isWordChar(s[0]) && s.map!(ch => isWordChar(ch) || ch==' ').all; } 
		static bool isDefinition(string s)
		{ return s.endsWith(':') && s[0..$-1].isIdentifier; } 
		
		string actSection; 
		string[] actDefinition; 
		
		enum logDefinitions = false; 
		
		void flush()
		{
			if(actDefinition.length)
			{
				enforce(actSection.length, "Undefined section"); 
				enforce(actDefinition.length>=2, "Invalid definition. Must be at least 2 lines"); 
				
				auto definitionStr = actDefinition.join('\n'); 
				if(logDefinitions)
				print(actSection, " / ", actDefinition[0]); 
				appendDefinition_official(definitionStr, actSection); 
				
				actDefinition = []; 
			}
		} 
		
		//Imput conditioning split lines, strip from right, drop empty lines
		foreach(line; text.split('\n').map!stripRight.filter!"a.length")
		{
			if(isSection(line))
			{
				flush; 
				actSection = line; 
			}else
			{
				if(isDefinition(line))
				flush; 
				actDefinition ~= line; 
			}
		}
		flush; 
	} 
	
} 

struct DlangGrammarGraph
{
	 // DlangGrammarGraph ////////////////////////////
	private SyntaxGraph graph_; 
	bool initiaZoomDone = false; 
	
	auto graph()
	{
		if(graph_ is null)
		graph_ = new SyntaxGraph(
			File(appPath, `Dlang grammar official.txt`  ),
										   File(appPath, `DLang grammar extra data.txt`)
		); 
		return graph_; 
	} 
	
	void update(View2D view)
	{
		const screenSearchBezierStart = vec2(view.clientSize.x-70, 20), //should be calculated from the actual UI location of the SearchBox
					P0 = view.invTrans(screenSearchBezierStart),
					P1 = view.invTrans(screenSearchBezierStart+vec2(0, 300)); 
		graph.flags.targetSurface = 0; //it's on the zoomable surface
		graph.update(view, [P0, P1]); 
		/+
			view.workArea = graph.workArea; 
			if(view.workArea && chkSet(initiaZoomDone))
			view.zoomAll; 
		+/
		im.root ~= graph; //add it to the IMGUI
	} 
	
	~this()
	{
		if(graph_)
		graph_.saveExtraData; 
	} 
} 

/////////////////////////////////////////////
///    Module graph                       ///
/////////////////////////////////////////////

import buildsys; 

alias ModuleLabel = GraphLabel!ModuleNode; 

class ModuleNode : GraphNode!(ModuleGraph, ModuleLabel)
{
	 // ModuleNode /////////////////////////////
	
	File moduleFile; 
	string moduleFullName; 
	int zIndex; 
	
	override string name() const
	{ return moduleFile.fullName; } 
	
	this(ModuleGraph parent, buildsys.ModuleInfo moduleInfo)
	{
		super(parent); //Todo: this is copy paste. This should be done automatically.
		
		moduleFile = moduleInfo.file; 
		moduleFullName = moduleInfo.moduleFullName; 
		groupName_original = moduleFile.path.fullPath; 
		
		bkColor = clCodeBackground; border = "normal"; border.color = clGroupBorder; padding = "2"; 
		auto ts = tsNormal; 
		
		//module name
		ts.applySyntax(SyntaxKind.BasicType); 
		ts.fontHeight = 18*2; 
		append(new ModuleLabel(this, false, moduleFile.fullName, moduleFullName, ts)); 
		
		//fileName
		ts.fontHeight = 18/3; 
		ts.fontColor = clGray; 
		appendStr("\n"~moduleFile.fullName, ts); 
		ts.applySyntax(SyntaxKind.Whitespace); 
		
		ts.applySyntax(SyntaxKind.Whitespace); 
		ts.fontHeight = 18/3; 
		foreach(mFile; moduleInfo.importedFiles)
		{
			appendStr("\n", ts); 
			append(new ModuleLabel(this, true, mFile.fullName, mFile.fullName, ts)); 
		}
	} 
} 

class ModuleGraph : ContainerGraph!(ModuleNode, ModuleLabel)
{
	 // ModuleGraph /////////////////////////////
	
	File extraFile; 
	
	this(File extraFile)
	{
		super(); 
		invertEdgeDirection = true; 
		this.extraFile = extraFile; 
	} 
	
	auto addModule(buildsys.ModuleInfo moduleInfo)
	{
		if(auto n = findNode(moduleInfo.file.fullName))
		return n; //already exists
		
		auto node = new ModuleNode(this, moduleInfo); 
		const nextPos = subCells.length ? subCells[$-1].outerBounds.bottomLeft + vec2(0, 10) : vec2(0); 
		node.outerPos = nextPos; 
		
		addNode(node.name, node); //Todo: this only adds it to the nodeByName map
		return node; 
	} 
	
	bool initiaZoomDone = false; 
	
	void update2(View2D view)
	{
		const screenSearchBezierStart = vec2(view.clientSize.x-70, 20), //should be calculated from the actual UI location of the SearchBox
					P0 = view.invTrans(screenSearchBezierStart),
					P1 = view.invTrans(screenSearchBezierStart+vec2(0, 300)); 
		flags.targetSurface = 0; //it's on the zoomable surface
		super.update(view, [P0, P1]); 
		/+
			view.workArea = workArea; 
			if(view.workArea && chkSet(initiaZoomDone))
			view.zoomAll; 
		+/
		im.root ~= this; //add it to the IMGUI
	} 
	
	struct ExtraData
	{
			//Todo: exportFields, importFields between aggregates
		vec2 outerPos; 
	} 
	
	void saveExtraData()
	{
		nodes.map!(d => tuple(d.name, ExtraData(d.outerPos)))
			 .assocArray //Todo: ez nem stable ordered!!!
			 .toJson
			 .saveTo(extraFile, Yes.onlyIfChanged); 
	} 
	
	void loadExtraData()
	{
		ExtraData[string] tmp; 
		tmp.fromJson(extraFile.readText(false)); 
		foreach(name, data; tmp)
		{
			if(auto a = findNode(name))
			{
				static foreach(field; FieldNameTuple!(typeof(data)))
				{ mixin("a.$ = data.$;".replace("$", field)); }
			}
		}
	} 
	
} 


auto testProject = File(`c:\D\projects\Karc\karc.d`); 

void testBuildSys()
{
	BuildSystem bs; 
	BuildSettings settings = { verbose : true }; 
	bs.findDependencies(testProject, settings); 
} 

class FrmGrammar: GLWindow
{
	mixin autoCreate; 
	DlangGrammarGraph dlangGrammarGraph; 
	
	ModuleGraph moduleGraph; 
	
	override void onCreate()
	{
		//logFileOps = true;
	} 
	
	override void onUpdate()
	{
		caption = "DLang grammar viewer"; 
		view.navigate(!im.wantKeys, !im.wantMouse); 
		
		if(!moduleGraph)
		{
			BuildSystem bs; 
			BuildSettings settings = { verbose : false }; 
			auto modules = bs.findDependencies(testProject, settings); 
			
			moduleGraph = new ModuleGraph(File(appPath, "Module extra data.txt")); 
			
			foreach(m; modules)
			moduleGraph.addModule(m); 
			moduleGraph.loadExtraData; 
		}
		
		enum Pages
		{ dGrammar, modules } 
		//static actPage = Pages.dGrammar; 
		static actPage = Pages.modules; 
		
		with(im)
		Panel(
			PanelPosition.topClient, {
				Row(
					{
						Text("View "); BtnRow(actPage); 
						
						Flex; 
						
						if(actPage == Pages.dGrammar)
						dlangGrammarGraph.graph.UI_SearchBox(view); 
						if(actPage == Pages.modules)
						moduleGraph.UI_SearchBox(view); 
					}
				); 
			}
		); 
		
		
		if(actPage == Pages.dGrammar)
		dlangGrammarGraph.update(view); 
		if(actPage == Pages.modules)
		moduleGraph.update2(view); 
		
		with(im)
		Panel(
			PanelPosition.topLeft, {
				width = 300; 
				flags.vScrollState = ScrollState.auto_; 
				
				if(actPage == Pages.dGrammar)
				dlangGrammarGraph.graph.UI_Editor; 
				if(actPage == Pages.modules)
				moduleGraph.UI_Editor; 
			}
		); 
		
		invalidate; //opt
	} 
	
	override void onPaint()
	{
		gl.clearColor(clBlack); 
		gl.clear(GL_COLOR_BUFFER_BIT); 
		
		showFPS = true; 
	} 
	
	override void onDestroy()
	{ moduleGraph.saveExtraData; } 
	
} 