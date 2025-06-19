module didebase; 
import het.ui; 

public import het.ui; 

public import het.parser : CodeLocation, SyntaxKind, syntaxBkColor, syntaxFontColor; 

public import dideselection; 
public import dideselection : wordAt; public import het : wordAt; 
public import dideselection : distance; public import het : distance; 

public import diderow: CodeRow; 
public import didecolumn: CodeColumn; 
public import didenode : CodeNode; 
public import didemodule : Module; 
public import buildmessages: ModuleBuildState, DMDMessage; 

void ShutdownLog(A)(A a, string loc = i"$(__FILE__)($(__LINE__)): ".text)
{
	auto s = loc~"ShutdownLog "~a.text; 
	console.show; 
	print(s); 
	File(`c:\dl\dide shutdown.log`).append(now.text~": "~s~"\r\n"); 
} 


alias SearchResult = Container.SearchResult,
SearchOptions = Container.SearchOptions; 

enum compoundObjectChar = '￼'; 


enum AnimatedCursors 	= (常!(bool)(1)),
MaxAnimatedCursors 	= 100; 

enum autoSpaceAfterDeclarations 	= (常!(bool)(1)) /+automatic space handling right after "statements; " and "labels:" and "blocks{}"+/,
joinSemicolonsAfterBlocks 	= (常!(bool)(1)) /+fixes C style source codes: /+Code: struct { int x; } ;+/  The ';' will be added to the end of the {}+/,
handleMultilineCMacros	= (常!(bool)(1)) /+Multiline C Macro support.+/; 

enum rearrangeLOG 	= false,
rearrangeFlash 	= false;  

enum visualizeStructureLevels = false; 

enum MultiPageGapWidth = DefaultFontHeight; 

enum SubScriptFontScale 	= .6f,
DefaultSubScriptFontHeight 	= iround(DefaultFontHeight * SubScriptFontScale); 

__gshared
	DefaultIndentSize 	= 4	/+global setting that affects freshly loaded source codes.+/,
	DefaultNewLine 	= "\r\n" 	/+this is used for saving source code+/,
	globalVisualizeSpacesAndTabs 	= true; 


enum TextFormat : ubyte
{
	plain, highlighted, cChar, cString, dString, comment, 
	
	managed, managed_block, managed_statement, managed_goInside, managed_optionalBlock,
	managed_first = managed, managed_last = managed_optionalBlock
} 

bool isManaged(TextFormat tf)
{ return tf.inRange(TextFormat.managed_first, TextFormat.managed_last); } 


enum StructureLevel : ubyte
{ plain, highlighted, structured, managed} 


interface INavigator
{
	CellLocation[] locate(in vec2 mouse, vec2 ofs=0); 
	CellLocation[] locate_snapToRow(vec2 mouse, float epsilon = .5f); 
	
	void jumpTo(vec2 pos); 
	void jumpTo(bounds2 bnd); 
	void jumpTo(R)(R searchResults) if(isInputRange!(R, SearchResult)); 
	void jumpTo(Object obj); 
	void jumpTo(in CodeLocation loc); 
	void jumpTo(string id); 
} 

interface IBuildServices
{
	@property
	{
		bool building(); 
		bool ready(); 
		bool cancelling(); 
		bool running(); 
		bool running_console(); 
		bool canKillCompilers(); 
		bool canKillRunningProcess(); 
		bool canKillRunningConsole(); 
		bool canCloseRunningWindow(); 
		bool canTryCloseProcess(); 
	} 
	void run(); 
	void rebuild(); 
	void cancelBuild(); 
	void killCompilers(); 
	void killRunningProcess(); 
	void killRunningConsole(); 
	void closeRunningWindow(); 
	void closeOrKillProcess(); 
} 

interface IWorkspace
{ @property bool isReadOnly(); } 




version(/+$DIDE_REGION+/all) {
	/+Todo: this is redundant. It's also in didemodule+/
	RGB brighter(RGB a, float f)
	{ return (a.from_unorm*(1+f)).to_unorm; } 
	
	enum clPiko : RGB
	{
		G940 	= (RGB(139,  59,  43)).brighter(.25f),
		G239 	= (RGB(245, 156,   0)),
		G231 	= (RGB(238, 114,   3)),
		G119 	= (RGB(221,  11,  47)).brighter(.35f),
		G115 	= (RGB(222,   0, 126)),
		G107 	= (RGB(158,  25, 129)).brighter(.125f),
		G62 	= (RGB( 92,  36, 131)).brighter(.25f),
		R1 	= (RGB( 22, 186, 231)),
		R2 	= (RGB(  0, 134, 192)),
		R3 	= (RGB(  0, 105, 180)),
		R4 	= (RGB(  0,  79, 159)),
		R9 	= (RGB(  0,  48,  93)),
		W 	= (RGB(134, 188,  37)),
		BW 	= (RGB(101, 179,  46)),
		W3 	= (RGB(  0, 120,  88)),
		WY 	= (RGB(  0, 169, 132)),
		K15 	= (RGB(255, 227, 126)),
		K30 	= (RGB(255, 237,   0)),
		DKW 	= (RGB(255, 204,   0)),
		GE31 	= (RGB(157, 157, 156)),
	} 
	
	RGB structuredColor(string name, RGB def = clGray)
	{
		switch(name)
		{
			case "template": 	return clPiko.G940; 
			case "enum": 	return clPiko.G239; 
			case "alias": 	return clPiko.G231; 
			case "if", "switch", "final switch", "else": 	return clPiko.G119.brighter(.25f); 
			case 	"for", "do", "while", "foreach", 
				"foreach_reverse": 	return mix(clOrange, RGB(221, 11, 47), .66f).brighter(.25f); 
			case 	"version", "debug", "static if", 
				"static foreach", "static foreach_reverse", 
				"static assert": 	return mix(clPiko.G115, clPiko.G119, .5f).brighter(.25f); 
			case "module", "import": 	return clPiko.G107; 
			case "unittest": 	return clPiko.G62; 
				
			case "section": 	return clPiko.R1; 
			case "with": 	return clPiko.R2; 
			case "__unused1": 	return clPiko.R4; 
				
			case "class": 	return clPiko.W; 
			case "interface": 	return clPiko.BW; 
			case "struct": 	return clPiko.W3; 
			case "union": 	return clPiko.WY; 
			case "mixin template": 	return clPiko.K15; 
			case "mixin": 	return mix(clPiko.DKW, clPiko.G119, .75f); 
			case "statement": 	return clGray; 
			case "function", "invariant": 	return clSilver; 
			case "__region": 	return clGray; 
				
			case "try": 	return RGB(200, 250, 189); 
			case "scope": 	return RGB(50, 250, 189); 
			case 	"assert", "break", "continue", "goto", 
				"goto case", "return"	, "enforce": 	return mix(RGB(0x5C00F6/+skKeyword+/), clWhite, .5); 
			
			case "auto": 	return clAqua; 
			
			default: 	return def; 
		}
	} 
}

__gshared float blink; 

void updateBlink()
{ blink = float(sqr(sin(blinkf(134.0f/60)*PIf))); } 

void setRoundBorder(Container cntr, float borderWidth)
{
	with(cntr) {
		border.width = borderWidth; 
		border.color = bkColor; 
		border.inset = true; 
		border.borderFirst = true; 
	}
} 

void RoundBorder(float borderWidth)
{
	with(im) {
		border.width = borderWidth; 
		border.color = bkColor; 
		border.inset = true; 
		border.borderFirst = true; 
	}
} 

auto KeyBtn(string srcModule = __FILE__, size_t srcLine = __LINE__, A...)(string kc, A args)
{ with(im) return Btn!(srcModule, srcLine)({ Text(kc, " ", args); }, KeyCombo(kc)); } 

static void UI_OuterBlockFrame(T = .Row)(RGB color, void delegate() contents)
{
	with(im)
	Container!T(
		{
			margin = "0.5"; 
			padding = "1.5"; 
			style.bkColor = bkColor = color; 
			style.fontColor = blackOrWhiteFor(color); 
			flags.yAlign = YAlign.top; 
			RoundBorder(8); 
			if(contents) contents(); 
		}  
	); 
} 

static void UI_InnerBlockFrame(T = .Row)(RGB color, RGB fontColor, void delegate() contents)
{
	with(im)
	Container!T(
		{
			margin = "0"; 
			padding = "0 4"; 
			style.bkColor = bkColor = color; 
			style.fontColor = fontColor; 
			flags.yAlign = YAlign.top; 
			RoundBorder(8); 
			if(contents) contents(); 
		}  
	); 
} 

//! UI ///////////////////////////////

void UI(in CodeLocation cl)
{
	with(cl)
	with(im)
	UI_InnerBlockFrame(
		clSilver, clBlack, {
			auto s = cl.text; 
			actContainer.id = "CodeLocation:"~s; 
			FileIcon_small(file.ext); 
			Text(s); 
		}  
	); 
} 

/+
	void UI(in BuildSystemWorkerState bsws)
	{
		with(bsws)
		with(im) {
			Row(
				{
					width = 6*fh; 
					Row(
						{
							if(building) style.fontColor = mix(style.fontColor, style.bkColor, blink); 
							Text(cancelling ? "Cancelling" : building ? "Building" : "BuildSys Ready"); 
						}  
					); 
					Row(
						{
							flex=1; flags.hAlign = HAlign.right; 
							if(building && !cancelling && totalModules)
							Text(format!"%d(%d)/%d"(compiledModules, inFlight, totalModules)); 
							else if(building && cancelling) { Text(format!"\u2026%d"(inFlight)); }
						}  
					); 
				}  
			); 
		}
	} 
+/

//! Draw //////////////////////////////////////////////////////

version(/+$DIDE_REGION LOD   +/all)
{
	//LOD //////////////////////////////////////////
	
	struct LodStruct
	{
		float zoomFactor=1, pixelSize=1; 
		int level; 
		
		bool codeLevel = true; //level 0
		bool moduleLevel = false; //level 1/*code text visible*/, 2/*code text invisible*/
		
		float calcVisibleSize(float worldSize) const
		{ return worldSize * zoomFactor; } 
	} 
	
	__gshared const LodStruct lod; 
	
	void setLod(float zoomFactor_)
	{
		with(cast(LodStruct*)(&lod))
		{
			zoomFactor = zoomFactor_; 
			pixelSize = 1/zoomFactor; 
			level = 	pixelSize>6 ? 2 :
				pixelSize>2 ? 1 : 0; 
			
			codeLevel = level==0; 
			moduleLevel = level>0; 
		}
	} 
	
}

void drawHighlight(Drawing dr, bounds2 bnd, RGB color, float alpha)
{
	if(!bnd) return; 
	dr.color = color; 
	dr.alpha = alpha; 
	dr.fillRect(bnd); 
	dr.lineWidth = -1; 
	dr.drawRect(bnd); 
	dr.alpha = 1; 
} 

void drawHighlight(Drawing dr, Cell c, RGB color, float alpha)
{
	if(!c) return; 
	drawHighlight(dr, c.outerBounds, color, alpha); 
} 



struct bloodScreenEffect
{
	private __gshared float intensity = 0; 
	
	static {
		void activate()
		{ intensity = 1; } 
		
		void update()
		{ intensity.follow(0, calcAnimationT(application.deltaTime.value(second), .9, .2), .05f); } 
		
		void glDraw()
		{
			if(intensity)
			{
				with((cast(GLWindow)(mainWindow)))
				with(scoped!Drawing)
				{
					color = clRed; alpha = 1-(1-intensity)^^2; 
					fillRect(clientBounds); 
					glDraw(viewGUI); 
				}
			}
		} 
	} 
} 

version(/+$DIDE_REGION+/all) {}