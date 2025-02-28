module dideui; 

import het.ui; 

import het.parser : CodeLocation; 
import buildsys : BuildSystemWorkerState; 

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