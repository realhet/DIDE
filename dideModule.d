module didemodule; 

import het.ui, het.parser ,buildsys, dideui, didebase; 
import diderow : CodeRow, SourceTextBuilder; 
import didecolumn : CodeColumn, CodeColumnBuilder; 
import didenode : CodeNode, CodeBlock, CodeString, CodeComment; 
import didedecl : Declaration, processHighLevelPatterns_expr, processHighLevelPatterns_block; 
import dideexpr : NiceExpression, processNiceTemplateMixinStatement, processNiceTemplateMixinStatement, processNiceStatementRow, processNiceExpressionBlock; 
version(/+$DIDE_REGION+/all)
{
	//Todo: pragma(msg, __traits(getLocation, print)); Use this to locate precisely anything from any scope. It gives a result in 1-2 seconds.
	//Todo: Multiline #define is NOT allowed in D tokenStrings
	//Todo: Multiline #directeve with \ backslash is not supported at all.
	//Todo: A // comment after a #directive should be possible
	//Todo: Don't apply Italic fontFlag on emojis
	//Todo: Empty () [] synbols should look like they are without inner and outer borders.
	
	/+
		Todo: FocusEditor shortcuts:
		
		Alt+X	Show All Commands
		Ctrl+P	Open File By Name
		Ctrl+O	Navigate To File
		Ctrl+Shift+O 	Navigate To File From Root
		Ctrl+F	Search in Open File
		Alt+F	Search in Open File(DropDown Mode)
		Ctrl+Shift+F	Search in Workspace
	+/
	
	//Todo: Vertical tab a commentbe is.
	
	
	/+
		Todo: Make regions out of attribute blocks: /+
			Code: private /+$DIDE_REGION Comment+/
			{ }
		+/
	+/
	//Todo: .inRange with .. operator	in the parameter list, and || &&	for nice looking parsers
	//Todo: backspace, delete should be sequentially read... Mouse buttons	too.	It's a big change to support crap FPS.
	//Todo: DIDE: Optionally simplify display of long IF chains.  Big example in karc.d.
	//Todo: Vertical tab on end of the longest row should NOT use extra space for itself!
	
	//Todo: hex string literals
	//Todo: import expressions
	
	/+Todo: bug: /+Code: Cₙ,+/ Syntax highlight don't detect coma as a symbol here. -> universal identifier char!!! Here with a space it's ok:/+Code: Cₙ ,+/+/
	
	//Todo: preprocess: with(a, b) -> with(a)with(b)
	
	//Todo: deprecate 'PROBE'
	//Todo: Animated cursor bug when Ctrl+Left -ing out form a node.  if(from_here_to_the_left).  The cursor animates from topleft of the outer block.
	//Todo: Deleting/editing when multiselect and at leas one readonly selection -> fucks up all selection.  It should just ignore the readonly one, keeping all selection.
	//Todo: Experimental color scheme: all function headers could be inverse. That would make a nice contrast.
	/+Todo: /+Code: /+//comment+/+/ if there is no comment, just a // it throws on save...+/
	
	
	alias blink = dideui.blink; 
	
	enum autoSpaceAfterDeclarations 	= (常!(bool)(1)) /+automatic space handling right after "statements; " and "labels:" and "blocks{}"+/,
	joinSemicolonsAfterBlocks 	= (常!(bool)(1)) /+fixes C style source codes: /+Code: struct { int x; } ;+/  The ';' will be added to the end of the {}+/,
	handleMultilineCMacros	= (常!(bool)(1)) /+Multiline C Macro support.+/; 
	
	//version identifiers: AnimatedCursors
	enum AnimatedCursors = (常!(bool)(1)); 
	enum MaxAnimatedCursors = 100; 
	
	enum rearrangeLOG = false;  
	enum rearrangeFlash = false; 
	
	enum LogModuleLoadPerformance = false; 
	
	enum visualizeStructureLevels = false; 
	
	enum MultiPageGapWidth = DefaultFontHeight; 
	
	enum SubScriptFontScale 	= .6f,
	DefaultSubScriptFontHeight 	= iround(DefaultFontHeight * SubScriptFontScale); 
	
	__gshared DefaultIndentSize = 4; //global setting that affects freshly loaded source codes.
	__gshared DefaultNewLine = "\r\n"; //this is used for saving source code
	__gshared globalVisualizeSpacesAndTabs = true; 
	
	const clModuleBorder = clGray; 
	const clModuleText = clBlack; 
	
	enum compoundObjectChar = '￼'; 
	
	
	enum TextFormat : ubyte
	{
		plain, highlighted, cChar, cString, dString, comment, 
		
		managed, managed_block, managed_statement, managed_goInside, managed_optionalBlock,
		managed_first = managed, managed_last = managed_optionalBlock
	} 
	
	bool isManaged(TextFormat tf)
	{ return tf.inRange(TextFormat.managed_first, TextFormat.managed_last); } 
	
	version(/+$DIDE_REGION ChangeIndicator+/all)
	{
		//ChangeIndicator /////////////////////////////////////
		
		struct ChangeIndicator
		{
			//Todo: this is quite similar to CaretPos
			vec2 pos; 
			float height; 
			ubyte thickness; 
			ubyte mask; 
			
			vec2 top() const
			{ return pos; } 
			vec2 center() const
			{ return pos + vec2(0, height/2); } 
			vec2 bottom() const
			{ return pos + vec2(0, height); } 
			bounds2 bounds() const
			{ return bounds2(top, bottom); } 
		} 
		
		Appender!(ChangeIndicator[]) globalChangeindicatorsAppender; 
		
		void addGlobalChangeIndicator(in vec2 pos, in float height, in int thickness, in int mask)
		{ globalChangeindicatorsAppender ~= ChangeIndicator(pos, height, cast(ubyte)thickness, cast(ubyte)mask); } 
		
		void addGlobalChangeIndicator(Drawing dr, Container cntr)
		{
			with(cntr) {
				if(const mask = changedMask)
				{
					enum ofs = vec2(-4, 0); 
					if(cast(CodeRow)cntr)
					addGlobalChangeIndicator(dr.inputTransform(outerPos+ofs), outerHeight, 4, mask); 
					else if(cast(CodeColumn)cntr)
					addGlobalChangeIndicator(dr.inputTransform(innerPos+ofs), innerHeight, 1, mask); 
				}
			}
		} 
		
		void drawChangeIndicators(Drawing dr, in ChangeIndicator[] arr)
		{
			enum palette = [clBlack, clLime, clRed, clYellow]; 
			
			//const clamper = RectClamper(im.getView, 5);
			
			void drawPass(int pass)(in ChangeIndicator ci)
			{
				static if(pass==1) {
					dr.lineWidth = -float(ci.thickness)-1.5f; 
					//opted out: dr.color = clBlack;
				}
				static if(pass==2) {
					dr.lineWidth = -float(ci.thickness); 
					dr.color = palette[ci.mask]; 
				}
						
				//if(clamper.overlaps(ci.bounds)){
					dr.vLine(ci.pos, ci.pos.y + ci.height); 
				//}else{
				//dr.vLine(clamper.clamp(ci.center), lod.pixelSize);  //opt: result of claming should be cached...
				//}
			} 
			
			/+pass 1+/dr.color = clBlack; 	foreach_reverse(const a; arr) drawPass!1(a); 
			/+pass 2+/	foreach_reverse(const a; arr) drawPass!2(a); 
			
		} 
	}
	
	version(/+$DIDE_REGION InspectorFX+/all)
	{
		struct InspectorParticle_shrinkingRect
		{
			vec2 dst, size; 
			float life=0; RGB color; 
			void updateAndDraw(Drawing dr)
			{
				enum scale = 14; 
				if(life>=.05f)
				{
					life *= .91f; 
					const sqLife = ((life)^^(2)); 
					
					auto b = bounds2(((dst).genericArg!q{center}), ((size * (1 + sqLife*scale)).genericArg!q{size})); 
					
					dr.lineWidth = -1-sqLife*10; 
					dr.alpha = 1 - sqLife; 
					dr.color = color; 
					dr.drawRect(b); 
					dr.alpha = 1; 
				}
			} 
			
			void setup(bounds2 dstRect, RGB color_, bounds2 srcRect, float initialLife = 1)
			{
				color = color_; 
				life = initialLife; 
				auto b = dstRect; 
				dst = b.center; 
				size = b.size; 
			} 
		} struct InspectorParticle_shoot
		{
			vec2 pos, velocity, dst; 
			float life=0; float size=1; RGB color; 
			void updateAndDraw(Drawing dr)
			{
				if(life>.5f)
				{
					life -= 0.01f; 
					
					pos += velocity; 
					velocity += vec2(0, 1); //gravity
					
					
					dr.pointSize = -5; 
					dr.color = color; 
					dr.point(mix(pos, dst, ((life.remap(1, .5f, 0, 1))^^(4)))); 
				}
				else if(life>0)
				{
					life -= 0.01f; 
					const 	f = life.remap(.5f, 0, 0, 1),
						a = (1-((1-f)^^(2))),
						r = a*size*4; 
					dr.alpha = a; dr.color = mix(color, clWhite, ((f)^^(2))); dr.pointSize = (1-f)*-12; 
					foreach(i; 0..50)
					{
						auto α = dst.x+dst.y*6+i*123; 
						auto v = dst + r * vec2(sin(α), cos(α))*sin(dst.x*7+dst.y*3+i*23); 
						dr.point(v); 
					}
					dr.alpha = 1; 
				}
			} 
			
			void setup(bounds2 dstRect, RGB color_, bounds2 srcRect, float initialLife = 1)
			{
				color = color_; 
				life = initialLife; 
				{
					auto b = dstRect; 
					dst = b.center; 
				}
				{
					auto b = srcRect; 
					auto rg = randomGaussPair; 
					pos = b.center; 
					size = b.height; 
					velocity = vec2(size*(rg[0]*0.2f), -size*(1+rg[1]*0.2f))*0.3f; 
				}
			} 
		} 
		
		alias InspectorParticle = 
		InspectorParticle_shrinkingRect
		/+InspectorParticle_shoot+/; 
		
		__gshared {
			InspectorParticle[2<<10] inspectorParticles; 
			size_t inspectorParticleIdx = 0; 
		} 
		
		void addInspectorParticle(bounds2 dstWorldBounds, RGB color, bounds2 srcWorldBounds, float initialLife=1)
		{
			inspectorParticleIdx++; 
			if(inspectorParticleIdx>=inspectorParticles.length) inspectorParticleIdx=0; 
			inspectorParticles[inspectorParticleIdx].setup(dstWorldBounds, color, srcWorldBounds, initialLife); 
		} 
		
		void addInspectorParticle(CodeNode node, RGB color, bounds2 srcWorldBounds, float initialLife=1)
		{ addInspectorParticle(node.worldOuterBounds, color, srcWorldBounds, initialLife); } 
	}
}version(/+$DIDE_REGION Utility+/all)
{
	//Utility //////////////////////////////////////////
	
	version(/+$DIDE_REGION+/all)
	{
		auto moduleOf(inout Cell c)
		{ return cast(inout)(c ? c.allParents!Module.frontOrNull : null); } 
		
		auto moduleOf(TextCursor c)
		{ return c.codeColumn.moduleOf; } 
		auto moduleOf(TextSelection s)
		{ return s.caret.codeColumn.moduleOf; } 
		
		bool isReadOnly(in Cell c)
		{ return c.thisAndAllParents!Module.map!"a.isReadOnly".any; } 
		bool isReadOnly(in TextCursor c)
		{ return c.codeColumn.isReadOnly; } 
		bool isReadOnly(in TextSelection s)
		{ return s.caret.codeColumn.isReadOnly; } 
		
		
	}
	version(/+$DIDE_REGION Breadcrumbs+/all)
	{
		struct Breadcrumb
		{
			/+Note: This is a hierarchical path element for navigation.+/
			
			CodeNode node; 
			
			@property valid() const
			{ return !!node; } 
			bool opCast(B : bool)() const { return valid; } 
			
			string toString()
			{
				if(cast(CodeString) node) return "q{}"; 
				if(auto d = cast(Declaration) node) { if(d.isRegion) return d.caption.quoted; }; 
				return node ? node.identifier : "null"; 
			} 
		} 
		
		static toBreadcrumb(Cell cell)
		{
			CodeNode n; 
			if(auto d = cast(Declaration) cell)
			{
				if(
					(d.isBlock && d.identifier!="") ||
					(d.isRegion /+&& d.caption!=""  region can be unnamed+/)
				) n = d; 
			}
			else if(auto m = cast(Module) cell)
			n = m; 
			else if(auto s = cast(CodeString) cell) n = s.isTokenString ? s : null; 
			
			return Breadcrumb(n); 
		} 
		
		Breadcrumb[] toBreadcrumbs(Cell cell)
		{
			if(!cell) return []; 
			return cell.thisAndAllParents.map!toBreadcrumb.filter!"a".array.retro.array; 
		} 
		
		Breadcrumb[] toBreadcrumbs(TextCursor tc)
		{ return tc.codeColumn.toBreadcrumbs; } 
		
		Breadcrumb[] toBreadcrumbs(TextSelection ts)
		{ return ts.codeColumn.toBreadcrumbs; } 
		
		Breadcrumb[] toBreadcrumbs(CellLocation[] arr)
		{
			foreach_reverse(a; arr)
			static foreach(T; AliasSeq!(CodeNode, CodeRow, CodeColumn))
			if(auto b = (cast(T)(a.cell))) return b.toBreadcrumbs; return []; 
		} 
		
		
		bool isTokenString(Cell cell)
		{ if(auto s = cast(CodeString) cell) return s.isTokenString; return false; } 
		bool isModule(Cell cell)
		{ return !!(cast(Module) cell); } 
		bool isDeclaration(Cell cell)
		{ return !!(cast(Declaration) cell); } 
		bool isSimpleBlock(Cell cell)
		{ if(auto d = cast(Declaration) cell) return d.isSimpleBlock; return false; } 
		bool isRegion(Cell cell)
		{ if(auto d = cast(Declaration) cell) return d.isRegion; return false; } 
		bool isFunction(Cell cell)
		{ if(auto d = cast(Declaration) cell) return d.isFunction; return false; } 
		bool isAttributeBlock(Cell cell)
		{ if(auto d = cast(Declaration) cell) return d.isAttributeBlock; return false; } 
		
		static isAnyDeclarationBlock(Cell cell)
		{
			if(auto d = cast(Declaration) cell)
			{
				if(d.isAttributeBlock) return true; 
				if(d.isBlock && d.keyword.among("template", "struct", "union", "class", "interface")) return true; 
			}
			else if(cast(Module) cell)
			return true; 
			
			return false; 
		} 
		
		CodeNode nearestDeclarationBlock(Cell cell)
		{
			auto nodes = cell.thisAndAllParents.map!(c=>cast(CodeNode)c).filter!"a".array.retro; 
			auto skippable = nodes.until!(n=>!n.isAnyDeclarationBlock && !n.isRegion).array; 
			auto unskippable = nodes[skippable.length..$]; 
			
			//a non nested function is a valid candidate
			if(unskippable.length && unskippable.front.isFunction) return unskippable.front; 
			
			return skippable.backOrNull; 
			
			/+Note: Do not deal with tokenStrings, stop at the very first function block.+/
		} 
		
	}	
}version(/+$DIDE_REGION CMacros+/all)
{
	string preprocessMultilineMacros(StructureLevel structureLevel, string sourceText, File file=File.init/+just for info+/)
	{
		if(structureLevel < StructureLevel.structured) return sourceText; 
		
		static if((常!(bool)(0)))
		{
			const t0 = now; 
			scope(exit)
			{
				const t1 = now; __gshared t = 0*second; synchronized t += t1-t0; 
				LOG("Total time checking C Macros:", t); 
			}
		}
		
		
		///It checks if it's on a line ending `\` and the previous line is NOT ending with `\`.
		bool atMultilineMacro(size_t i)
		{
			assert(i+1 < sourceText.length, "Must ensure this from outside!"); 
			if(sourceText[i]=='\\' && sourceText[i+1].among('\n', '\r'))
			{
				foreach_reverse(j; 0..i)
				{
					/+Supports: \n \r\n \r+/
					if(sourceText[j]=='\n')	return sourceText.get(j-1-(sourceText.get(j-1)=='\r'))!='\\'; 
					else if(sourceText[j]=='\r')	return sourceText.get(j-1)!='\\'; 
				}
				return true/+This is the very first line, so it can be a start.+/; 
			}
			return false; 
		} 
		
		
		auto multilineMacroPositions = 	iota((cast(sizediff_t)(sourceText.length))-1)
			.filter!atMultilineMacro.cache
		/+
			This range returns all the positions of sourceText rows 
			that ends with \ and contains a #.
			The returned position is at the \ character, the last char in the row.
		+/; 
		
		if(multilineMacroPositions.empty) return sourceText/+nothing to change+/; 
		
		char[] res = sourceText.dup; 
		
		foreach(pos; multilineMacroPositions)
		{
			try
			{
				enforce(sourceText.get(pos)=='\\', "Backslash expected."); 
				
				sizediff_t findMarkPos()
				{
					sizediff_t markPos = -1; 
					foreach_reverse(j; 0..pos)
					{
						const ch = sourceText[j]; 
						if(ch=='#') markPos = j; 
						else if(ch.among('\r', '\n')) break; 
					}
					return markPos; 
				} 
				
				const startPos = findMarkPos; 
				enforce(startPos>=0, "Can't find start of macro."); 
				
				//Only process valid directives.  Other #things can be parameters.
				if(!startsWithKeyword!(CodeComment.customDirectivePrefixes)(sourceText[startPos+1..$]))
				continue; 
				
				sizediff_t seekNextLine(sizediff_t start)
				{
					foreach(j; start..sourceText.length)
					{
						const ch = sourceText[j]; 
						if(ch=='\n') return j+1; 
						if(ch=='\r') return j+1+(sourceText.get(j+1)=='\n'); 
					}
					return sourceText.length; /+eof+/
				} 
				
				string stripNL(string s)
				=> s.withoutEnding('\n').withoutEnding('\r'); 
				
				bool hasBackslashAtEnd(size_t pos)
				=> stripNL(sourceText[0..pos]).endsWith('\\'); 
				
				size_t[] linePositions = [startPos]; 
				do {
					const nextPos = seekNextLine(linePositions.back); 
					if(nextPos<=linePositions.back/+eof+/) break; 
					linePositions ~= nextPos; 
				}
				while(hasBackslashAtEnd(linePositions.back)); 
				
				static if((常!(bool)(0)))
				LOG(
					file, "\n--------------------\n"~
					linePositions.slide!(No.withPartial)(2)
					.map!((a)=>(stripNL(sourceText[a[0]..a[1]]))).join('\n')
					~"\n--------------------"
				); 
				
				enforce(linePositions.length>=3, "Can't find at least 2 macro lines."); 
				
				{
					size_t openingPos; 
					foreach(i; linePositions[0]..linePositions[1])
					if(res[i].among(' ', '\t', '\\')) { openingPos = i; break; }
					enforce(openingPos, "Can't locate opening pos."); 
					res[openingPos] = '{'; 
				}
				
				void stepBackNL(ref size_t p)
				{
					const p0 = p; 
					if(p>0 && res[p]=='\n') p--; 
					if(p>0 && res[p]=='\r') p--; 
					enforce(p!=p0, "Unable to step back on NewLine."); 
				} 
				
				size_t backslashPos; 
				foreach(a; linePositions[1..$-1])
				{
					backslashPos = a-1; 
					stepBackNL(backslashPos); 
					if(res[backslashPos]!='\\') backslashPos = 0; 
					
					if(backslashPos) res[backslashPos] = ' '; 
				}
				
				enforce(backslashPos, "Can't locate ending pos"); 
				
				size_t endPos = linePositions.back-1; 
				stepBackNL(endPos); 
				res[backslashPos..endPos+1] = res[backslashPos+1..endPos+1]~'}'; 
				
				static if((常!(bool)(0)))
				LOG(
					file, "\n--------------------\n"~
					res[linePositions.front..linePositions.back].idup~
					"\n--------------------"
				); 
				
			}
			catch(Exception e) { WARN("Error processing macro: ", file, pos, e.simpleMsg); }
		}
		
		
		return (cast(string)(res)); 
	} 
	
	///This is called from CodeComment/directive. It finds the content in #define{content}.
	CodeBlock findMultilineMacroBlock(CodeRow row)
	{
		static if(handleMultilineCMacros)
		if(row.subCells.length==1)
		if(auto blk = (cast(CodeBlock)(row.subCells.front)))
		if(blk.type==CodeBlock.Type.block)
		{ return blk; }
		return null; 
	} 
}version(/+$DIDE_REGION+/all)
{
	
	/// Label //////////////////////////////////////////
	
	enum LabelType { folder, module_, mainRegion, subRegion} 
	
	class Label : Row
	{
		Cell reference; 
		bool alignRight; 
		
		this(LabelType labelType, vec2 pos, string str, Cell reference=null)
		{
			this.reference = reference; 
			
			auto ts = tsNormal; 
			ts.fontColor = clWhite; 
			ts.bkColor = clBlack; 
			ts.transparent = true; 
			
			with(LabelType) {
				const isRegion = labelType.among(mainRegion, subRegion)!=0; 
				ts.fontHeight = isRegion ? 180 : 255; 
				ts.bold = false && labelType != subRegion; 
				alignRight = isRegion; 
			}
			
			with(flags) {
				noHitTest = true; 
				dontSearch = true; 
				dontLocate = true; 
				noBackground = true; 
			}
			
			outerPos = pos; 
			
			//icon
			Img icon; 
			if(labelType==LabelType.module_)
			icon = new Img(File(`icon:\`~File(str).ext.lc)); 
			else if(labelType==LabelType.folder)
			icon = new Img(File(`icon:\folder\`)); 
			
			if(icon) {
				icon.innerSize = vec2(ts.fontHeight); 
				icon.transparent = true; 
				appendCell(icon); 
			}
			
			//text
			appendStr(str, ts); 
			measure; 
		} 
		
		void reposition()
		{
			if(reference) {
				outerX = alignRight ? reference.outerWidth-this.outerWidth : 0; 
				outerY = reference.outerY; 
			}
		} 
	} 
	
	//FolderLabel //////////////////////////////////
	
	auto cachedFolderLabel(string folderPath)
	{ return ImStorage!Label.access(srcId(genericId(folderPath)), new Label(LabelType.folder, vec2(0), Path(folderPath).name)); } 
	
	void dumpDDoc(string src)
	{
		print("----Original DDoc---------------------------------------------------"); 
		LOG(src); 
		print("----Processed DDoc-------------------------------------------------"); 
		string stack="*"; 
		auto scanner = src.DDocScanner; 
		if(1)
		f: foreach(sr; scanner)
		{
			with(EgaColor)
			with(StructureScanner)
			switch(sr.op)
			{
				case ScanOp.content: 	{
					if(stack[$-1]=='`') write(ltGreen(sr.src)); 
					else if(stack[$-1]=='*') write(ltWhite(sr.src)); 
					else write(ltBlue(sr.src)); 
				}break; 
				case ScanOp.push: 	{
					write(yellow(sr.src)); 
					stack ~= sr.src[0]; 
				}break; 
				case ScanOp.pop: 	{
					write(yellow(sr.src)); 
					stack.popBack; 
					if(stack.empty) { write(ltRed("Out of stack")); break f; }
				}break; 
				case ScanOp.trans: 	{ write(ltCyan(sr.src)); }break; 
				default: 	{ write(EgaColor.ltRed(sr.op.text~":"~sr.src)); }break; 
			}
			
		}
		
		print("---End of Processed DDoc----------------------------------------------"); 
	} 
	
	
	//! Undo/History System ////////////////////////////////////
	
	string encodePrevAndNextSourceText(string prev, string act)
	{
		//Todo: ezt kiprobalni jsonnal is, hogy van-e egyaltalan ennek a manualis cuccnak valami ertelme
		return prev.length.to!string~"\\"~prev~act; 
	} 
	
	string[2] decodePrevAndNextSourceText(string s)
	{
		auto a = s.splitter("\\"); 
		if(!a.empty)
		try
		{
			auto snum = a.front; 
			const prevLen = snum.to!size_t; 
			s = s[snum.length+1..$]; 
			if(prevLen<=s.length) return [s[0..prevLen], s[prevLen..$]]; 
		}
		catch(Exception)
		{}
		
		return typeof(return).init; 
	} 
	
	struct TextModificationRecord
	{ string where, what; } 
	
	struct TextModification
	{
		bool isInsert; 
		TextModificationRecord[] modifications; //Must preserve order!!!!
	} 
	
}struct UndoManager
{
	version(/+$DIDE_REGION+/all)
	{
			
		//Bug: UndoManager is sticking to a module. If the module is renamed, I don't know what happens...
		//Opt: Loaded event is wasting a lot of memory. It should use differential text coding. And zip.
		//Todo: also store the textSelections in the undoevents
		
		private uint lastUndoGroupId; 
		
		enum EventType
		{ loaded, saved, modified} 
		
		class Event
		{
			DateTime id; //unique ID
			EventType type; 
			TextModification[] modifications; 
			Event[] items; 
			
			Event parent; 
			
			this(Event parent, DateTime id, EventType type, bool isInsert, string where, string what)
			{
				this.parent = parent; 
				this.id = id; 
				this.type = type; 
				modifications ~= TextModification(isInsert, [TextModificationRecord(where, what)]); 
			} 
			
			override int opCmp(in Object b) const
			{
				auto bb = cast(Event)b; 
				return cmp(id, bb ? bb.id : DateTime.init); 
			} 
			
			string summaryText(string insMark = "(+)", string delMark = "(-)", string moreMark="...", bool isQuoted=true)(int maxStrLen = 20) const
			{
				final switch(type)
				{
					case EventType.loaded: return "Loaded"; 
					case EventType.saved: return "Saved"; 
					case EventType.modified: {
						string res; 
						int actStrLen, actMode; //1:ins, -1:del
						foreach(const m; modifications)
						{
							const nextMode = m.isInsert ? 1 : -1; 
							if(actMode.chkSet(nextMode))
							{
								const s = actMode>0 ? insMark : delMark; 
								res ~= s; 
								//no, because it could be a markup symbol: actStrLen += cast(int)s.walkLength;
							}
								
							//Todo: detect backspace (text selections are going backwards, and reverse order)
							foreach(mr; m.modifications)
							foreach(ch; mr.what)
							{
								if(ch<32)
								{
									static if(isQuoted)
									{
										const s = ch.text.quoted[1..$-1]; 
										res ~= s; 
										actStrLen += s.length.to!int; 
											
										//compact \r\n into \n
										if(res.endsWith(`\r\n`)) {
											res = res[0..$-4]~`\n`; 
											actStrLen -= 2; 
										}
									}
									else
									{
										res ~= ('\u2400'+ch); //visual control chars
										actStrLen += 1; 
									}
								}
								else
								{ res ~= ch; actStrLen++; }
								
								if(actStrLen>=maxStrLen)
								return res ~ moreMark; 
							}
						}
						return res; 
					}
				}
			} 
			
			override string toString() const
			{ return format!"UndoEvent(%s, %s, items:%d)"(id, summaryText, items.length); } 
			
			Container createUI(Event actEvent)
			{
				static bool tsInitialized; 
				static TextStyle tsEvent; 
				if(tsInitialized.chkSet) {
					tsEvent = tsNormal; //Opt: save this
				}
				
				auto outer = new Row; 
				
				Row inner; 
				with(inner = new Row)
				{
					padding = "2"; 
					margin = "4"; 
					border = "1 normal black"; 
					
					auto ts = tsEvent; 
					inner.appendMarkupLine(
						this.id.text~"\n"~summaryText!(
							tag("style fontColor=green"),
							tag("style fontColor=red"),
							tag("style fontColor=black")~"\u2026", false
						), ts
					); 
				}
				
				Row innerWithArrow; 
				with(innerWithArrow = new Row)
				{
					appendCell(inner); 
					innerWithArrow.appendStr(this is actEvent ?  "\U0001F846" : "\u2b95", tsEvent); //arrow
				}
				inner = innerWithArrow; 
				
				outer.appendCell(inner); 
				
				if(items.length==1)
				{
					outer.appendCell(items[0].createUI(actEvent)); //recursive
				}
				else if(items.length>1)
				{
					auto col = new Column; 
					outer.appendCell(col); 
					
					foreach(item; items)
					col.appendCell(item.createUI(actEvent)); //recursive
				}
				
				return outer; 
			} 
			
		} 
	}version(/+$DIDE_REGION+/all)
	{
		Event[DateTime] allEvents; 
		
		private DateTime latestId; //used for unique id generation
		
		Event actEvent, rootEvent; 
		
		protected bool executing; //when executing, disable the recording of events.
		
		Event oldestEvent()
		{ return allEvents.byValue.minElement(null); } 
		Event newestEvent()
		{ return allEvents.byValue.maxElement(null); } 
			
		bool hasAnyModifications() const { return allEvents.byValue.any!(e => e.type == EventType.modified); } 
			
		void justLoaded(File file, string contents)
		{ addEvent(0, EventType.loaded, file.fullName, contents, false); }  //Todo: fileName, fileContents for history
		void justSaved(File file, string contents)
		{ addEvent(0, EventType.saved, file.fullName, ""      , false); } 
		void justInserted(uint undoGroupId, string where, string what)
		{ addEvent(undoGroupId, EventType.modified , where, what, true ); } 
		void justRemoved(uint undoGroupId, string where, string what)
		{ addEvent(undoGroupId, EventType.modified , where, what, false); } 
		
		void addEvent(uint undoGroupId, EventType type, string where, string what, bool isInsert)
		{
			if(executing) return; 
			
			//append latest event in the same group
			const	    extendLastGroup = type==EventType.modified
				&& actEvent && actEvent.type==EventType.modified
				&& actEvent.modifications.length
				&& lastUndoGroupId==undoGroupId; 
			if(extendLastGroup)
			{
				assert(actEvent.modifications.back.isInsert==isInsert); 
				actEvent.modifications.back.modifications ~= TextModificationRecord(where, what); 
			}
			else
			{
				lastUndoGroupId = undoGroupId; 
				
				latestId.actualize; 
				//a new unique Id. This garantees that all child is newer than the parent.
				//Takes 150ns to get the precise system time.
				
				//fusion of modification.
				const fusion = 		type == EventType.modified
					&& 	actEvent
					&&	actEvent.type == EventType.modified
					&&	latestId-actEvent.id < .75*second; 
				if(fusion)
				{
					actEvent.id = latestId; 
					actEvent.modifications ~= TextModification(isInsert, [TextModificationRecord(where, what)]); 
				}
				else
				{
					if(!actEvent) assert(allEvents.empty); 
					auto e = new Event(actEvent, latestId, type, isInsert, where, what); 
					allEvents[e.id] = e; 
					if(actEvent) actEvent.items ~= e; 
					actEvent = e; //this is the new act
					if(!rootEvent) rootEvent = e; 
				}
			}
		} 
		
		bool canUndo()
		{
			return actEvent && actEvent !is rootEvent; //rootEvent must be a Load event. That can't be cancelled.
		} 
		
		void undo(void delegate(in TextModification) execute, void delegate(string where, string what) reload)
		{
			assert(!executing); 
			
			if(!canUndo) return; 
			
			executing = true; scope(exit) executing = false; 
			
			bool again; 
			do {
				again = false; 
				final switch(actEvent.type)
				{
					case EventType.modified: 	actEvent.modifications.retro.each!execute; break; 
					case EventType.saved: 	again = true; break; //nothing happened, "save event" is it's just a marking for the user
					case EventType.loaded: 	reload(
						actEvent.modifications[0].modifications[0].where,
												actEvent.modifications[0].modifications[0].what.decodePrevAndNextSourceText[0]
					); break; 
						//Todo: ^^^^^^ ugly and needs range checking
				}
				actEvent = actEvent.parent; 
			}
			while(again && canUndo);     
		} 
		
		bool canRedo()
		{ return actEvent && actEvent.items.length; } 
		
		void redo(void delegate(in TextModification) execute, void delegate(string where, string what) reload)
		{
			//Todo: refactor undo/redo. Too much copy paste.
			if(!canRedo) return; 
			
			executing = true; scope(exit) executing = false; 
			
			bool again; 
			do {
				actEvent = actEvent.items.back; //choose different path optionally
				
				again = false; 
				final switch(actEvent.type)
				{
					case EventType.modified: 	actEvent.modifications.each!execute; break; //it's in reverse text selection order.
					case EventType.saved: 	again = true; break; //nothing happened, "save event" is it's just a marking for the user
					case EventType.loaded: 	reload(
						actEvent.modifications[0].modifications[0].where,
						actEvent.modifications[0].modifications[0].what.decodePrevAndNextSourceText[1]
					); break; 
						//Todo: ^^^^ ugly and needs range check
				}
			}
			while(again && canRedo);     
				
		} 
			
		Container createUI()
		{ return rootEvent ? rootEvent.createUI(actEvent) : null; } 
	}
} version(/+$DIDE_REGION+/all)
{
	/// Module ///////////////////////////////////////////////
	interface WorkspaceInterface
	{ @property bool isReadOnly(); } 
	
	enum StructureLevel : ubyte
	{ plain, highlighted, structured, managed} 
	
	class Module : CodeBlock
	{
		//this is any file in the project
		File file; 
		uint fileNameHash/+It must be uint because Inspector ID is 64 bit total: 32bit nameHash + 32bit line+/; 
		
		DateTime fileLoaded, fileModified, fileSaved; //Opt: detect these times from the outside
		size_t sizeBytes; //Todo: update this form the outside
		
		StructureLevel structureLevel; 
		static foreach(e; EnumMembers!StructureLevel)
		mixin(
			format!q{
				@property is%s() const
				{ return structureLevel == StructureLevel.%s; } 
			}(e.text.capitalize, e.text)
		); 
		
		ModuleBuildState buildState; 
		bool isCompiling, isSaving; 
		
		bool isMainExe, isMainDll, isMainLib, isMain, isStdModule, isFileReadOnly; 
		
		UndoManager undoManager; 
		
		uint 	_rearrangeCounter,
			_updateSearchResults_state; 
		
		float compilationTime=0; 
		Module[] importedModules; 
		
		override SyntaxKind syntax() const
		{ return skWhitespace; } 
		override string prefix() const
		{ return ""; } 
		override string postfix() const
		{ return ""; } 
		
		this(Container parent)
		{
			super(parent); 
			lineIdx = 1; //All modue starts with line 1
			bkColor = clModuleBorder; 
		} 
		
		this(Container parent, File file_, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{
			this(parent); 
			loadFile(file_, desiredStructureLevel); 
		} 
		
		this(Container parent, string contents, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{
			this(parent); 
			loadContents(contents, desiredStructureLevel); 
		} 
		
		void loadFile(File file_, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{
			fileLoaded = now; 
			file = file_.actualFile; 
			fileNameHash = (cast(uint)(file.toHash)); 
			reload(desiredStructureLevel); 
		} 
		
		void loadContents(string contents, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{
			fileLoaded = now; 
			file = File("$nullFileName$"); //Bug: When filename is empty, this fuck is crashing without any errors. ($nullFileName$)
			fileNameHash = 0; 
			reload(desiredStructureLevel, nullable(contents)); 
		} 
		
		override @property string identifier()
		{
			//Todo: process the module statement.
			return file.nameWithoutExt; 
		} 
		
		override @property string caption()
		{ return file.name; } 
		
		///It must return the actual logic. Files can be temporarily readonly while being compiled for example.
		bool isReadOnly()
		{
			//return inputs["ScrollLockState"].active;
			return isCompiling || isFileReadOnly || isStdModule || (cast(WorkspaceInterface)parent).isReadOnly; 
		} 
		
		void resetModuleTypeFlags()
		{ isMain = isMainExe = isMainDll = isMainLib = isStdModule = isFileReadOnly = false; } 
		
		void detectModuleTypeFlags()
		{
			
			bool isMainSomething(string ext)()
			{
				if(content)
				if(auto r = content.getRow(0))
				{
					/+
						Todo: this detector is not so nice...
						Need to develop more advanced source code parsing methods.
					+/
					
					//structured
					if(auto c = cast(CodeComment)(r.subCells.get(0)))
					if(sameText(c.content.shallowText.stripRight, "@"~ext)) return true; 
					//highlighted/plain
					if(sameText(r.shallowText.stripRight, "//@"~ext)) return true; 
				}
				
				return false; 
			} 
			isMainExe = isMainSomething!"exe"; 
			isMainDll = isMainSomething!"dll"; 
			isMainLib = isMainSomething!"lib"; 
			isMain = isMainExe || isMainDll || isMainLib; 
			
			isStdModule = file.fullName.isWild(`c:\d\ldc2\import\*`); 
			//Todo: detect compiler import path correctly
			
			isFileReadOnly = isStdModule || file.isReadOnly || file.name.sameText("compile.err"); 
			//Todo: periodically chenck if file is exists and other attributes in the IDE
			//Note: This is just the file based input of the actual ReadOnly decision in isReadOnly().
		} 
		
		
		
		version(/+$DIDE_REGION BuildMessage handling+/all)
		{
			CodeColumn buildMessageColumn/+This module's own buildMessageColumn+/; 
			override CodeColumn* accessBuildMessageColumn()
			{ return &buildMessageColumn; } 
		}
		
		version(/+$DIDE_REGION BuildMessage database+/all)
		{
			static class Message
			{
				//aggregate class for all these things
				version(/+$DIDE_REGION+/all) {
					DMDMessage message; 
					CodeNode node; 
					SearchResult[] searchResults; 
					this(
						DMDMessage message, 
						CodeNode node, 
						SearchResult[] searchResults
					) {
						this.message 	= message,
						this.node 	= node,
						this.searchResults 	= searchResults; 
					} 
				}
				alias this = message; 
			} 
			
			Message[uint] messageByHash; 
			Message[][EnumMembers!(DMDMessage.Type).length] messagesByType; 
			CodeColumn[] moduleBuildMessageColumns; //all columns containing buildmessages
			
			SearchResult[] findSearchResults; //this is for the text search
			SearchResult[][CodeLocation] searchResultsByCodeLocation;  //this is a lineIdx->searchResults cache
			
			void resetBuildMessages()
			{
				/+
					Note: /+Code: moduleBuildMessageColumns+/ contains all the columns inside this module.
					It doesn't always include the buildMessageColumn of this module.
				+/
				
				foreach(col; moduleBuildMessageColumns)
				{
					col.parent.needMeasure; //Mark all the nodes to measure later.
					*((cast(CodeNode)(col.parent)).accessBuildMessageColumn) = null; //Remove reference.
				}
				moduleBuildMessageColumns = []; /+
					Remove central column references from the module.
					GC will do the rest for the rowss and messages..
				+/
				messageByHash.clear; 
				foreach(ref msgs; messagesByType) msgs = []; 
				
				//measure; //Immediately do the actual realign without the buildMessages.
			} 
			
			void resetSearchResults()
			{
				findSearchResults = []; 
				searchResultsByCodeLocation.clear; 
			} 
			
			auto addModuleMessage(bool isNew, DMDMessage msg, CodeNode node, SearchResult[] searchResults)
			{
				auto mm = new Message(msg, node, searchResults); 
				foreach(ref sr; mm.searchResults) sr.reference = mm; //own all searchResults
				
				if(mm.hash) messageByHash[mm.hash] = mm; 
				
				ref auto mta() { return messagesByType[mm.type]; } 
				if(isNew)
				{ mta ~= mm; }
				else
				{
					const idx = mta.map!"a.hash".countUntil(mm.hash); //Opt: linear search
					if(idx>=0)	{ mta[idx] = mm; }
					else	{
						mta ~= mm; 
						WARN("BuildMessage marked as non new, but found.\n"~mm.message.text); 
					}
				}
				
				return mm; 
			} 
		}
		
		void updateSearchResults()
		{
			if(_updateSearchResults_state.chkSet(_rearrangeCounter + [outerPos].xxh32))
			{
				bool doit(ref SearchResult[] srs)
				{
					bool anyRemoved; 
					foreach(ref sr; srs)
					{
						sr.absInnerPos = sr.container.worldInnerPos; 
						anyRemoved |= sr.container.flags.removed; 
					}
					if(anyRemoved)
					srs = srs.remove!((sr)=>(sr.container.flags.removed)); 
					return srs.empty; 
				} 
				
				doit(findSearchResults); 
				
				{
					Message[] removedMessages; 
					foreach(msg; messageByHash.byValue)
					{ if(doit(msg.searchResults)) removedMessages ~= msg; }
					foreach(rm; removedMessages)
					{
						const hash = rm.message.hash, type = rm.message.type; 
						messageByHash.remove(hash); 
						messagesByType[type] = messagesByType[type].remove!((m)=>(m is rm)); 
					}
				}
				
				{
					CodeLocation[] removedLocations; 
					foreach(loc, ref sr; searchResultsByCodeLocation)
					{ if(doit(sr)) removedLocations ~= loc; }
					foreach(loc; removedLocations)
					searchResultsByCodeLocation.remove(loc); 
				}
				
				moduleBuildMessageColumns = moduleBuildMessageColumns.remove!((c)=>(c.flags.removed)); 
			}
		} 
		void resetInspectors()
		{ NOTIMPL; } 
		
		void reload(StructureLevel desiredStructureLevel, Nullable!string externalContents = Nullable!string.init)
		{
			resetBuildMessages; resetSearchResults; clearInspectors; 
			
			fileModified = file.modified; 
			sizeBytes = file.size; 
			resetModuleTypeFlags; 
			structureLevel = StructureLevel.plain; //reset to the most basic level
			
			auto prevSourceText = sourceText; 
			string sourceText = !externalContents.isNull 	? externalContents.get
				: this.file.readText; 
			
			undoManager.justLoaded(this.file, encodePrevAndNextSourceText(prevSourceText, sourceText)); 
			
			//undo is storing original text before resolving C macros
			
			static if(handleMultilineCMacros)
			sourceText = preprocessMultilineMacros(desiredStructureLevel, sourceText, file); 
			
			CodeColumnBuilder!true.staticLineCounter = 1; 
			
			void doPlain()
			{
				try
				{
					content.rebuilder.appendPlain(sourceText); 
					structureLevel = StructureLevel.plain; 
				}
				catch(Exception e)
				{ raise("Fatal error. Unable to load module even in plain mode. "~file.text~"\n"~e.simpleMsg); }
			} 
			
			void doHighlighted()
			{
				try
				{
					content.rebuilder.appendHighlighted(sourceText); 
					/+
						Todo: this is NOT raising an exception, only draws the error with 
						red and and display a WARN. It should revert to plain...
					+/
					structureLevel = StructureLevel.highlighted; 
				}
				catch(Exception e)
				{
					WARN("Unable to load module in highlighted mode. "~file.text~"\n"~e.simpleMsg); 
					doPlain; 
				}
			} 
			
			void doStructured()
			{
				try
				{
					content.rebuilder.appendStructured(sourceText); 
					structureLevel = StructureLevel.structured; 
				}
				catch(Exception e)
				{
					WARN("Unable to load module in structured mode. "~file.text~"\n"~e.simpleMsg); 
					doHighlighted; 
				}
			} 
			
			void doManaged()
			{
				doStructured; 
				if(isStructured)
				{
					try
					{
						
						//simple expression detection: Last node must be a () block
						bool isExpr()
						{
							foreach(r; content.rows.retro)
							foreach(c; r.subCells.retro)
							{
								if((cast(CodeComment)(c))) continue; 
								if(auto blk = (cast(CodeBlock)(c)))
								if(blk.type==CodeBlock.Type.list) return true; 
								return false; 
							}
							return false; 
						} 
						
						if(isExpr)	processHighLevelPatterns_expr(content); 
						else	processHighLevelPatterns_block(content); 
						
						/+
							content.refreshLineIdx; /+
								Todo: Why is this needed?
								And why only at the module level?
								processHighLevelPatterns somehow zeroes out 
								the structured row lineIndices of the module...
							+/
							//note: CodeColumn.RefreshLineIdx is flawed
							/+
								Bug: regenerate the fucking lineIndices because processHighLevelPatterns fucks those up.
								losing 1.5 sec because of this on dide2.startup.load.
							+/
						+/
						{
							//static Time allT = 0*second; T0; 
							refreshLineIdx; 
							//allT += DT; print(allT.value(milli(second))); 
						}
						
						structureLevel = StructureLevel.managed; 
					}
					catch(Exception e)
					{
						WARN("Unable to load module in managed mode. "~file.text~"\n"~e.simpleMsg); 
						doStructured; 
					}
				}
			} 
			
			[&doPlain, &doHighlighted, &doStructured, &doManaged][desiredStructureLevel](); 
			
			needMeasure; 
		} 
		
		void refreshLineIdx()
		{
			lineIdx = 1; //first line is always 1.  ignoring the #line directive.
			
			SourceTextBuilder builder; 
			builder.updateLineIdx = true; 
			
			with(builder)
			{
				foreach(idx, row; content.rows) {
					put(row); 
					putNL; 
				}
			}
			
			//Opt: It's ineffective, because it generates text.
		} 
		
		size_t linesOfCode()
		{
			return content.rowCount; 
			//Todo: update this. only good for unstructured code.
		} 
		
		override void rearrange()
		{
			detectModuleTypeFlags; 
			super.rearrange; 
			rearrange_appendBuildMessages; 
			_rearrangeCounter++; 
		} 
		
		void save()
		{
			if(isReadOnly) return; 
			clearInspectors; 
			isSaving = true; scope(exit) isSaving = false; 
			sourceText.saveTo(file, Yes.onlyIfChanged); //sourceText can throw
			clearChanged; 
			fileModified = file.modified; //Opt: slow
			fileSaved = now; 
		} 
		
		void UI_PopupMenu()
		{
			with(im)
			{
				Column(
					{
						Text(
							"Experimental
	popup menu"
						); 
						if(Btn("New Sticker")) beep; 
					}  
				); 
				popupState.cell = removeLastContainer; 
				popupState.parent = null; 
				
				popupState.cell.outerPos = mainWindow.screenToClient(inputs.mouseAct); 
			}
		} 
		
		
		
		version(/+$DIDE_REGION Inspector handling+/all)
		{
			
			protected
			{
				CodeNode[uint] inspectorNodeById; 
				uint[CodeNode] inspectorIdByNode; 
			} 
			
			void clearInspectors()
			{
				inspectorNodeById.clear; 
				inspectorIdByNode.clear; 
			} 
			
			auto getInspectorId(CodeNode node)
			{
				ulong loc = inspectorIdByNode.get(node, 0); 
				if(loc) loc = (ulong(loc)<<32) | fileNameHash; 
				return loc; 
			} 
			
			auto getInspectorNode(uint id)
			{ return inspectorNodeById.get(id, null); } 
			
			
			auto addInspector(CodeNode node, uint id)
			{
				inspectorNodeById[id] = node; 
				inspectorIdByNode[node] = id; 
				return (ulong(id)<<32) | fileNameHash; 
			} 
		}
		
		
		version(/+$DIDE_REGION Constant Node handling+/all)
		{
			CodeNode[] visibleConstantNodes; 
			
			void UI_constantNodes(bool en, int targetSurface_=0)
			{
				foreach(node; visibleConstantNodes.map!((a)=>(cast(NiceExpression)(a))).filter!"a")
				{ node.generateUI(en, targetSurface_); }
			} 
		}
		
		
	} 
}version(/+$DIDE_REGION SCRUM+/all)
{
	class ScrumTable: Module
	{
		/+Bug: Ctrl+R closes the sticker. (Acts like Ctrl+W)+/
		
		this(Container parent)
		{
			super(parent); bkColor = clWhite; 
			alwaysOnBottom = true; 
		} 
		
		this(Container parent, File file_, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{ this(parent); loadFile(file_, desiredStructureLevel); } 
		
		this(Container parent, string contents, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{ this(parent); loadContents(contents, desiredStructureLevel); } 
		
		override SyntaxKind syntax() const
		{ return skWhitespace; } 
		
		override bool isReadOnly()
		{ return true; } 
		
		
		enum Stages {
			iceBox, 
			emergency, 
			inProgress, 
			testing, 
			complete
		} immutable StageCaptions = [
			"ICE BOX",
			"EMEGRENCY",
			"IN PROGRESS",
			"TESTING",
			"COMPLETE"
		]; 
		
		struct Props
		{ int width=1920, height=1080; } 
		
		Props props; 
		
		CodeColumn hiddenColumn; 
		
		override void reload(
			StructureLevel desiredStructureLevel, 
			Nullable!string externalContents = Nullable!string.init
		)
		{
			super.reload(StructureLevel.plain, externalContents); 
			
			/+Note: .scrum file format: -> ScrumTable.Props.toJson+/
			
			ignoreExceptions({ props.fromJson(sourceText); }  ); 
			
			bkColor = clWhite; 
		} 
		
		void rebuild(R)(R scanner) if(isScannerRange!R)
		{
			//completely igniore content
			return; 
		} 
		
		override void rearrange()
		{
			subCells = []; 
			innerWidth = props.width; 
			innerHeight = props.height; 
		} 
		
		override void draw(Drawing dr)
		{
			super.draw(dr); 
			
			with(dr)
			{
				translate(outerPos); scope(exit) pop; 
				
				fontHeight = width/32; 
				lineWidth = fontHeight/8; 
				const stageWidth = outerWidth / StageCaptions.length; 
				foreach(i, capt; StageCaptions)
				{
					color = i==1 ? clRed : clBlack; 
					textOut(vec2(i*stageWidth, fontHeight/4), capt, stageWidth, HAlign.center); 
					
					color = clGray; 
					if(i) dr.vLine(i*stageWidth, 0, outerHeight); 
				}
				hLine(0, fontHeight*1.5, outerWidth); 
			}
		} 
		
		
	}  class ScrumSticker: Module
	{
		this(Container parent)
		{ super(parent); bkColor = clWhite; } 
		
		this(Container parent, File file_, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{ this(parent); loadFile(file_, desiredStructureLevel); } 
		
		this(Container parent, string contents, StructureLevel desiredStructureLevel = StructureLevel.plain)
		{ this(parent); 	loadContents(contents, desiredStructureLevel); } 
		
		override SyntaxKind syntax() const
		{ return skWhitespace; } 
		
		override bool isReadOnly()
		{ return false; } 
		
		override @property string identifier()
		{ return ""; } 
		
		override @property string caption()
		{ return ""; } 
		
		struct Props
		{
			string color="StickyYellow"; 
			vec2 pos; 
		} 
		
		Props props; 
		size_t props_hash; 
		
		override void reload(
			StructureLevel desiredStructureLevel, 
			Nullable!string externalContents = Nullable!string.init
		)
		{ super.reload(StructureLevel.managed, externalContents); } 
		
		void extractStickerProps()
		{
			/+
				Note: .sticker file format:
				
				Stickers are CodeComments: Note, Bug, Todo, etc.
				
				The second comment:  ScrumSticker.Props.toJson
			+/
			
			if(auto col = cast(CodeColumn) this.subCells.get(0))
			{
				if(auto row = cast(CodeRow) col.subCells.get(1))
				if(auto cmt = cast(CodeComment) row.subCells.get(0))
				{
					ignoreExceptions(
						{
							props.pos = outerPos; 
							props.fromJson(cmt.content.sourceText); 
							outerPos = props.pos; 
							//Todo: This conflicts with modules.lastKnownPosition and Ctrl+R reload.
							/+
								Note: This position will be overwritten by IDE.settings if it is exists there.
								But it is used to export stickers.
							+/
							
							props_hash = hashOf(props); 
						}  
					); 
					
					//only keep the first row with the sticky note comment
					col.subCells = col.subCells[0..1]; 
				}
			}
		} 
		
		void unpackSticker()
		{
			if(auto col = cast(CodeColumn) this.subCells.get(0))
			if(auto row = cast(CodeRow) col.subCells.get(0))
			{
				row.subCells = row.subCells[0..1]; //keep only the first row
				if(auto cmt = cast(CodeComment) row.subCells.get(0))
				{
					row.subCells = row.subCells[0..1]; //keep only the first cell
					
					//remove the codecolumn around the comment.
					
					//remove borders
					void removeBorder(Container a)
					{
						a.margin = Margin.init; 
						a.border = Border.init; 
						a.padding = Padding.init; 
						a.outerSize = a.calcContentSize; 
					} 
					only(cmt, row, col, this).each!((a){ removeBorder(a); }  ); 
					
					ignoreExceptions
					({ cmt.fillBkColor(props.color.toRGB(true)); }  ); 
					
					innerSize = cmt.outerSize; 
				}
			}
		} 
		
		override void rearrange()
		{
			super.rearrange; 
			
			extractStickerProps; 
			unpackSticker; 
		} 
		
		override void buildSourceText(ref SourceTextBuilder builder)
		{
			super.buildSourceText(builder); 
			builder.putNL; 
			
			builder.put("/+"); 
			props.pos = outerPos; 
			foreach(line; props.toJson.replace("/+", "/ +").replace("+/", "+ /").splitLines)
			builder.put(line); 
			builder.put("+/"); 
		} 
		
		override void save()
		{
			super.save; 
			props_hash = hashOf(props); 
		} 
		
		override void draw(Drawing dr)
		{
			with(dr)
			{
				color = clBlack; 
				lineWidth = 2; 
				drawRect(outerBounds.inflated(.5)); 
			}
			
			super.draw(dr); 
			
			if(!content.changed && props_hash!=hashOf(props))
			{
				content.setChanged; 
				content.edited = true; 
			}
			
		} 
		
		/+
			override void draw()
					{} 
		+/
		
	} 
	
}