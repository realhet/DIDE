module didebase; 
import het.ui; 

public import het.ui; 

public import het.parser : CodeLocation, SyntaxKind, syntaxBkColor, syntaxFontColor, structuredColor; 

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
{
	@property bool isReadOnly(); 
	void handleButtonCommentClick(Object cmt, string params); 
} 

__gshared float blink; 

void updateBlink()
{ blink = float(sqr(sin(blinkf(134.0f/60)*PIf))); } 

void setRoundBorder(Container cntr, float borderWidth, bool inward)
{
	with(cntr) {
		border.width = borderWidth; 
		border.color = bkColor; 
		border.inset = true /+border doesn't take up space+/; 
		border.borderFirst = true; 
		border.style = inward ? BorderStyle.halfFilletIn : BorderStyle.halfFilletOut; 
		cntr.flags.noBackground = true /+because fillet border already draws that.+/; 
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
			im.actContainer.setRoundBorder(8, inward:false); 
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
			background = style.bkColor = color; 
			style.fontColor = fontColor; 
			static if(is(T : .Row)) rowFlags.yAlign = YAlign.top; 
			im.actContainer.setRoundBorder(8, inward:true); 
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
		
		void draw(IDrawing dr)
		{
			with(dr)
			{
				if(intensity)
				{
					color = clRed; alpha = 1-(1-intensity)^^2; 
					fillRect(mainWindow.clientBounds.bounds2); alpha = 1; 
				}
			}
		} 
	} 
} 

version(/+$DIDE_REGION+/all) {}