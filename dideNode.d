module didenode; 

import didebase, het.parser; 

import diderow : SourceTextBuilder; 
import didecolumn : CodeColumnBuilder; 
import didedecl : Declaration; 
import didemodule : addGlobalChangeIndicator, findMultilineMacroBlock; 

version(/+$DIDE_REGION+/all) {
	enum NodeStyle : ubyte 
	{ dim, normal, bright } 
	
	enum specialCommentMarker = "$DIDE_"; //used in /++/ comments to mark DIDE special comments
	
	struct CodeNodeBuilder
	{
		enum UI = true, CODE = !UI; 
		
		CodeNode node; 
		TextStyle style; 
		RGB darkColor, brightColor, halfColor; 
		
		void putNL()
		{ put('\n'); } 
		
		void put(T)(T a)
		{
			static if(isSomeString!T)
			node.appendStr(a, style); 
			else static if(isSomeChar!T)
			node.appendChar(a, style); 
			else static if(is(T:Cell))
			node.appendCell(a); 
			else
			static assert(0, "unhandled type"); 
		} 
		
		void put(string prefix, CodeColumn block, string postfix, bool showFix=true)
		{
			if(showFix) put(prefix); 
			put(block); 
			if(showFix) put(postfix); 
		} 
		
		// helper functions for NiceExpressions ----------------------------
		void setSubscript()
		{ style.fontHeight = DefaultSubScriptFontHeight; node.flags.yAlign = YAlign.bottom; } 
		
		void setFontColor(SyntaxKind sk)
		{ style.fontColor = syntaxFontColor(sk); } 
		
		void withScaledFontHeight(float sc, void delegate() fun)
		{
			const oldFontHeight = style.fontHeight; scope(exit) style.fontHeight = oldFontHeight; 
			style.fontHeight = (cast(ubyte)((iround(DefaultFontHeight * sc)))); 
			fun(); 
		} 
		
		void putNumberSubscript(string s)
		{
			setSubscript; 
			setFontColor(skNumber); 
			style.bold = false; 
			put(s); 
		}  void putTypeSubscript(string s)
		{
			setSubscript; 
			setFontColor(skBasicType); 
			style.bold = false; //not much room
			put(s); 
		} 
	} 
	
	class StructureMap
	{
		//StructureMap //////////////////////////////////////////
		
		private static StructureMap collector; 
		private static bool collecting()
		{ return collector !is null; } 
		
		bool debugTrigger; 
		
		struct Rec
		{ CodeNode node; bounds2 bnd; } 
		Rec[] visibleNamedNodes; 
		
		void beginCollect()
		{
			assert(!collecting); 
			collector = this; 
			
			visibleNamedNodes.clear; 
		} 
		
		void onCollect(Drawing dr, CodeNode node)
		{
			assert(collector is this); 
			
			if(node.caption != "")
			visibleNamedNodes ~= Rec(node, dr.inputTransform(node.outerBounds)); 
		} 
		
		void endCollect(Drawing dr)
		{
			assert(collector is this); 
			collector = null; 
			
			if(debugTrigger.chkClear)
			{
				foreach(n; visibleNamedNodes)
				{ n.node.fullIdentifier.print; }
			}
			
			if(1) {
				
				/*
					dr.color = clFuchsia;
					dr.lineWidth = -1;
					dr.fontHeight = -18;
					foreach(n; visibleNamedNodes){
						//n.node.fullIdentifier.print;
						dr.drawRect(n.bnd);
						dr.textOut(n.bnd.topLeft, n.node.identifier);
						
					}
				*/
				
				
				if(lod.zoomFactor<0.5)
				{
					dr.lineWidth = -1; 
					foreach_reverse(n; visibleNamedNodes)
					{
						dr.fontHeight = min(8512, n.bnd.height); 
						
						const caption = n.node.caption; 
						
						const width = dr.textWidth(caption); 
						if(width > n.bnd.width) dr.fontHeight *= n.bnd.width/width; 
						
						auto visibleHeight = lod.calcVisibleSize(dr.fontHeight); 
						if(!visibleHeight.inRange(4, 64)) continue; 
						
						dr.alpha = 0.5; 
						dr.color = mix(n.node.bkColor, clBlack, 0.75); 
						dr.fillRect(n.bnd); 
						
						dr.alpha = 1; 
						dr.color = n.node.bkColor; 
						dr.drawRect(n.bnd); 
						
						dr.alpha = 1; 
						dr.color = mix(n.node.bkColor, clWhite, 0.75); 
						dr.textOut(n.bnd.topLeft, caption); 
						
					}
				}
			}
		} 
	} 
	
	class CodeNode : Row
	{
		Container parent; 
		
		int lineIdx; 
		NodeStyle nodeStyle; 
		bool 	alwaysOnBottom, 
			rearrangeNodeWasCalled/+
			This can used to track if rearrange was called or not.
			NiceExpression uses it.
		+/,
			isTableCell /+
			Used with MixinTables. 
			The tokenstring should have normal background, not string-like background.
		+/; 
		
		uint buildMessageHash; /+
			Todo: This is only used if this node is a buildMessage. 
			Currently there is a linear search to find duplicated messages.
		+/
		
		auto subColumns()
		{ return subCells.map!(a => cast(CodeColumn)a).filter!"a"; } 
		auto subColumns_backwards()
		{ return subCells.retro.map!(a => cast(CodeColumn)a).filter!"a"; } 
		
		auto columnAfter(CodeColumn act)
		{
			const idx = subCells.countUntil(act); 
			if(idx>=0 && idx+1<subCells.length)
			return subCells[idx+1..$].map!(a => cast(CodeColumn)a).filter!"a".frontOrNull; 
			return null; 
		} 
		
		auto columnBefore(CodeColumn act)
		{
			const idx = subCells.countUntil(act); 
			if(idx>0)
			return subCells[0..idx].retro.map!(a => cast(CodeColumn)a).filter!"a".frontOrNull; 
			return null; 
		} 
		
		auto firstSubColumn()
		{ return subColumns.frontOrNull; } 
		
		auto lastSubColumn()
		{ return subColumns_backwards.frontOrNull; } 
		
		this(Container parent)
		{
			this.parent = parent; 
			id = this.identityStr; 
			
			initializeBorder; 
			
			needMeasure; //enables on-demand measure
			flags.wordWrap	= false,
			flags.clipSubCells	= true,
			flags.cullSubCells	= true,
			flags.rowElasticTabs	= true,
			flags.dontHideSpaces 	= true; 
		} 
		
		~this()
		{ parent = null; } 
		
		override inout(Container) getParent() inout
		{ return parent; } 
		override void setParent(Container p)
		{ parent = p; } 
		
		abstract void buildSourceText(ref SourceTextBuilder builder); 
		
		final string sourceText()
		{
			SourceTextBuilder builder; 
			if(auto mod = (cast(Module)(this))) { builder.updateLineIdx = true; }
			
			buildSourceText(builder); 
			return builder.result; 
		} 
		
		@property string identifier()
		{ return ""; } 
		@property string caption()
		{ return ""; } 
		@property RGB avgColor()
		{ return bkColor; } 
		
		CodeNode parentNode()
		{
			if(auto r = cast(CodeRow) parent)
			if(auto c = cast(CodeColumn) r.parent)
			if(auto n = cast(CodeNode) c.parent)
			return n; 
			return null; 
		} 
		
		TextCursor nodeCursor()
		{
			if(auto row = (cast(CodeRow)(parent)))
			if(auto col = (cast(CodeColumn)(row.parent)))
			return col.cursorOf(this); 
			return TextCursor.init; 
		} 
		
		TextSelection nodeSelection(bool primary=false)
		{
			if(auto c1 = nodeCursor)
			{
				auto c2 = c1; c2.pos.x++; 
				return TextSelection(c1, c2, primary); 
			}
			return TextSelection.init; 
		} 
		
		
		CodeNode namedParentNode()
		{
			for(auto p = parentNode; p; p = p.parentNode)
			{
				auto id = p.identifier; 
				if(id!="") return p; 
			}
			return null; 
		} 
		
		string fullIdentifier()
		{
			/*
				if(identifier=="") return "";
				auto identifierPath = allParents!CodeNode.map!(a => a.identifier).filter!"a.length".array.retro;
				return chain(identifierPath, only(identifier)).join('.');
			*/
			
			auto i = identifier; if(i=="") return ""; 
			
			for(auto n = namedParentNode; n; n = n.namedParentNode)
			i = n.identifier ~ '.' ~ i; 
			
			return i; 
		} 
		
		void initializeBorder()
		{
			this.setRoundBorder(8); 
			margin = Margin(.5, .5, .5, .5); 
			padding = Padding(1, 1.5, 1, 1.5); 
		} 
		
		auto nodeBuilder(SyntaxKind syntax, NodeStyle nodeStyle_, Nullable!RGB customColor = Nullable!RGB.init)
		{
			nodeStyle = nodeStyle_; 
			
			CodeNodeBuilder res; 
			with(res) {
				node 	= this; 
				style 	= tsSyntax(syntax); 	if(!customColor.isNull) style.fontColor = customColor.get; 
				
				darkColor	= style.bkColor,
				brightColor 	= style.fontColor,
				halfColor	= mix(
					darkColor, brightColor, nodeStyle.predSwitch(
						NodeStyle.dim	, .15f, 
						NodeStyle.normal	, .50f, 
						NodeStyle.bright	, 1
					)
				); 
				
				style.bkColor = border.color = bkColor	= halfColor; 
				style.fontColor = nodeStyle!=NodeStyle.dim ? darkColor : brightColor; 
				style.bold = true; 
			}
			
			//initialize node
			subCells = []; //This rebuilds and realigns the whole Row subCells.
			flags.yAlign = YAlign.center; 
			
			return res; 
		} 
		
		final void rearrangeNode()
		{
			innerSize = vec2(0); 
			flags.autoWidth = true; 
			flags.autoHeight = true; 
			
			super.rearrange; 
			
			//Todo: this glyph stretcher should be more specific to a few classes
			enum enableStretchGlyphs = true; 
			if(enableStretchGlyphs && nodeStyle==NodeStyle.dim)
			{
				foreach(i, c; subCells)
				if(auto col = (cast(CodeColumn)(c)))
				{
					//to the left
					if(auto g = (cast(Glyph)(subCells.get(i-1))))
					if(g.ch.among('{', '[', '(', '⎡', '⎣', '⁅', '|', '‖'))
					g.stretch(col.outerTop, col.outerBottom); 
					//to the right
					if(auto g = (cast(Glyph)(subCells.get(i+1))))
					if(g.ch.among('}', ']', ')', '⎤', '⎦', '⁆', '|', '‖'))
					g.stretch(col.outerTop, col.outerBottom); 
				}
			}
			
			
			static if(rearrangeLOG) LOG("rearranging", this); 
			
			rearrangeNodeWasCalled = true; //signal rearrangeNode() completion
		} 
		
		override void rearrange()
		{ rearrangeNode; } 
		
		override void draw(Drawing dr)
		{
			//collect structuremap data (It's preceding draw, to add the parent first)
			if(StructureMap.collector)
			StructureMap.collector.onCollect(dr, this); 
			
			super.draw(dr); 
			
			//visualize changed/created/modified
			addGlobalChangeIndicator(dr, this/*, topLeftGapSize*.5f*/); 
			
			
			enum showDeclarationsWithBadLineIdx = false; 
			static if(showDeclarationsWithBadLineIdx)
			if(lineIdx==0)
			{
				//Mark nodes with no lineIdx
				dr.color = clFuchsia; 
				dr.lineWidth = -5; 
				if(blink>.5)
				dr.drawRect(innerBounds); 
			}
			
			
			if(VisualizeCodeLineIndices) {
				dr.color = clWhite; dr.fontHeight = 1.25; 
				dr.textOut(outerPos, format!"%sN"(lineIdx)); 
			}
			
			static if(0) {
				dr.color = clWhite; dr.fontHeight = 1.25; 
				dr.textOut(outerPos, (cast(void*)(this)).text); 
			}
			
			if(0 && canAcceptBuildMessages)
			{
				dr.color = clWhite; 
				dr.alpha = blink; 
				dr.lineWidth = -2; 
				dr.drawRect(outerBounds); 
				dr.alpha = 1; 
			}
		} 
		
		void fillSyntax(SyntaxKind sk)
		{
			static TextStyle ts; ts.applySyntax(sk); 
			subCells.map!(a => cast(Glyph) a).filter!"a".each
				!((g){
				g.bkColor = ts.bkColor; 
				g.fontColor = ts.fontColor; 
				g.fontFlags = ts.fontFlags;  //Todo: refactor this 3 assignments.
				g.syntax = cast(ubyte) sk; 
			}); 
			bkColor = ts.bkColor; 
		} 
		
		version(/+$DIDE_REGION BuildMessage handling+/all)
		{
			final bool canAcceptBuildMessages()
			{ return !!accessBuildMessageColumn; } 
			
			CodeColumn* accessBuildMessageColumn()
			{ return null; } 
			
			protected void rearrange_appendBuildMessages()
			{
				if(auto col = *accessBuildMessageColumn)
				{
					col.measure; 
					const siz = col.outerSize; 
					
					const oldSize = innerSize; 
					innerSize = vec2(max(oldSize.x, siz.x), oldSize.y + siz.y); 
					
					static if(0 /+no need for a newline here. It's only needed for Row.rearrange, but that's skipped..+/)
					{
						auto ts = tsNormal; applySyntax(ts, skWhitespace	); 
						auto nl = new Glyph('\n', ts); //Todo: cache newline glyph
						subCells ~= nl; 	nl.outerPos = vec2(0, oldSize.y); 
					}
					
					subCells ~= col; 	col.outerPos = vec2(0, oldSize.y); 
					
					strictCellOrder = false; //there are multiple lines, the order is not linear anymore
				}
			} 
			
			bool addBuildMessage(CodeNode msgNode)
			{
				auto col = accessBuildMessageColumn.enforce(typeid(this).name ~ " No storage for BuildMessages."); 
				enforce(msgNode, "msgNode is null"); 
				
				if(!*col)
				{
					*col = new CodeColumn(this); 
					(*col).containsBuildMessages = true; 
					
					auto mod = moduleOf(*col).enforce("addBuildMessage: Can't find parent module."); 
					mod.moduleBuildMessageColumns ~= *col; 
				}
				
				const 	idx = (
					(*col).rows	.map!((r)=>(r.firstNodeOrNull.buildMessageHash))
						.countUntil(msgNode.buildMessageHash)
				),
					isNewMessage = idx<0; 
				//Opt: slow linear search
				
				with(*col)
				{
					if(isNewMessage)
					{
						version(/+$DIDE_REGION Split into multiple columns.  Only for modules.+/all)
						{
							enum maxColumnHeight = 1400; 
							static if(maxColumnHeight>0)
							if((cast(Module)(this/+The receiver node of the message(!)+/)))
							if(
								rowCount>=1 && 
								(
									rows.retro	.until!((r)=>(r.hasVerticalTab))
										.map!((r)=>(r.outerHeight)).sum
								)>maxColumnHeight
								//Opt: Accumulate the size in a variable.
							)
							rows.back.addVerticalTab; 
						}
						
						appendCell(new CodeRow(*col, [msgNode])); 
						rows.back.measure /+must measure the row for the multi-column splitter.+/; 
					}
					else
					{
						auto row = rows[idx]; 
						row.subCells[0] = msgNode; 
						msgNode.setParent(row); 
						
						row.needMeasure; row.measure; 
					}
					
					needMeasure;  //The row is already measured.  Later the column needs to measured too.
				}
				
				return isNewMessage; 
			} 
		}
		
		
	} 
	static void visitNestedCodeColumns(CodeColumn col, void delegate(CodeColumn) fun)
	{
		//only process structured or modular columns
		if(!col.isStructuredCode) return; 
		
		//recursively visit nested columns
		foreach(node; col.byNode)
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
	
	void visitNestedCodeNodes(CodeNode node, void delegate(CodeNode) fun)
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
	
	void visitNestedCodeNodes(CodeColumn col, void delegate(CodeNode) fun)
	{
		//only process structured or modular columns
		if(!col.isStructuredCode) return; 
		
		//recursively visit nested columns
		foreach(node; col.byNode)
		{ visitNestedCodeNodes(node, fun); }
	} 
	
	
	
	void visitNestedCodeNodes(TextSelection sel, void delegate(CodeNode) fun)
	{
		if(sel.isZeroLength) return; //nothing to do with empty selection
		if(auto col = sel.codeColumn)
		{
			const 	st 	= sel.start, 
				en 	= sel.end; 
			
			foreach(y; max(st.pos.y, 0)..min(en.pos.y+1, col.rowCount))
			{
				auto row = col.rows[y]; 
				const 	isFirstRow 	= y==st.pos.y,
					isLastRow	= y==en.pos.y,
					isMidRow	= !isFirstRow && !isLastRow; 
				if(isMidRow)
				{
					foreach(c; row.subCells)
					if(auto n = (cast(CodeNode)(c)))
					visitNestedCodeNodes(n, fun); 
				}
				else
				{
					//delete partial row
					const 	rowCellCount 	= row.cellCount,
						x0 	= isFirstRow	? st.pos.x	: 0,
						x1 	= isLastRow 	? en.pos.x 	: rowCellCount; 
					foreach(x; max(x0, 0)..min(x1, rowCellCount))
					{
						if(auto n = (cast(CodeNode)(row.subCells[x])))
						visitNestedCodeNodes(n, fun); 
					}
				}
			}
		}
	} 
	
	class CodeContainer : CodeNode
	{
		CodeColumn content; 
		
		bool 	noBorder, //omits the texts on the surface of the Node and uses square edges.
			singleBkColor; 
		
		//base properties
		abstract SyntaxKind syntax() const; 
		abstract string prefix() const; 
		abstract string postfix() const; 
		@property NodeStyle nodeStyle() const
		=> NodeStyle.normal; 
		
		override @property RGB avgColor()
		=> mix(bkColor, content.avgColor, .25f); 
		
		//optional overloaded properties for rare cases, defaults to base properties
		/+SyntaxKind innerSyntax() const { return syntax; }+/
		/+
			string visualPrefix() const { return codePrefix; }
				string visualPostfix() const { return codePostfix; }
		+/
		
		this(Container parent)
		{
			super(parent); 
			content = new CodeColumn(this); 
		} 
		
		void fillBkColor(RGB8 c)
		{
			bkColor = c; 
			if(content) content.fillBkColor(c); 
		} 
		
		
		@property prefixStartsWithAlpha() const
		=> prefix.length && prefix.front.isDLangIdentifierCont; 
		
		override void buildSourceText(ref SourceTextBuilder builder)
		{
			//put extra space if needed in front of the prefix
			if(prefixStartsWithAlpha)
			builder.putSeparatorSpace; 
			
			builder.put(prefix, content, postfix); 
		} 
		
		protected T parseBlockPrefix(T, string[] tokens, R)(R scanner) if(isScannerRange!R)
		{
			enforce(!scanner.empty); 
			const sr = scanner.front; 
			enforce(sr.op == ScanOp.push); 
			auto res = tokens.countUntil(sr.src).to!T; 
			scanner.popFront; 
			return res; 
		} 
		
		override void rearrange()
		{
			with(nodeBuilder(syntax, nodeStyle))
			{
				content.bkColor = darkColor; 
				if(singleBkColor) bkColor = darkColor; //Minimalistic table look
				
				if(!noBorder) { if(prefixStartsWithAlpha) put(' '); put(prefix); }
				put(content); 
				if(!noBorder) put(postfix); 
				
				//Todo: //slashComment must ensure that after it there is a newLine
			}
			
			super.rearrange; 
		} 
		
		void applyNoBorder()
		{
			noBorder = true; 
			border = Border.init; 
			content.applyNoBorder; 
			needMeasure; 
		} 
	} 
	class CodeComment : CodeContainer
	{
		//Todo: bug when potting /+link:http://...+/ comments inside /++/  The newline after the // suxx.
		mixin((
			(表([
				[q{/+Note: Type+/},q{/+Note: Prefix+/},q{/+Note: Postfix+/}],
				[q{slashComment},q{"//"},q{""}],
				[q{cComment},q{"/*"},q{"*/"}],
				[q{dComment},q{"/+"},q{"+/"}],
				[q{directive},q{"#"},q{""}],
			]))
		) .GEN!q{GEN_enumTable}); 
		//node: directive is detected by the high level parser, not the structured scanner.
		
		Type type; 
		
		/+
			+ /+Code: customPrefix+/ can be a known directive: "line", "define"
				or a comment prefix: "Todo:", "Error:", "Opt:"
		+/
		string customPrefix; 
		SyntaxKind customSyntax; //it is detected only when rebuilding.
		
		bool isDDoc; 
		
		static immutable
			customDirectivePrefixes = [
			"!", 	//Link: shebang https://dlang.org/spec/lex.html#source_text
			"version", "extension", "line", 	//Link: GLSL directives
			"pragma", "warning", "error", "assert", 	//Link: Opencl directives
			"include", "define", "ifdef", "ifndef", "if", "endif", "undef", "elif", "else" 	//Link: Arduino directives
		],
			customCommentSyntaxes	= [
			skTodo,    skOpt,   skBug,   skNote,   skLink,   skCode, skCode, skCode,  skError,   skException,    skWarning,   skDeprecation,   skConsole,   skComment, 
			/+AI+/ skInteract, skInteract, skInteract, skInteract,
			
			/+text format+//+skInherit, skInherit, skInherit, skInherit, skInherit, skInherit, skInherit, skInherit, skInherit, skInherit+/
			/+Todo: skInherit does not works with insertNode+/
			/+text format+/skInteract, skInteract, skInteract, skInteract, skInteract, skInteract, skInteract, skInteract, skInteract, skInteract
		],
			customCommentPrefixes 	= [
			"Todo:", "Opt:", "Bug:", "Note:", "Link:", "Highlighted:", "Structured:", "Code:", "Error:", "Exception:", "Warning:", "Deprecation:", "Console:", "Hidden:", 
			"AI:", "System:", "User:", "Assistant:",
			"Bold:", "Italic:", "Bullet:", "Para:", "H1:", "H2:", "H3:", "H4:", "H5:", "H6:"
		]
			//() => customSyntaxKinds.map!(a => a.text.capitalize ~ ':').array ();
			; 
		
		static private auto skipNewLineAndTabs(R)(R r)
		{
			//Note: This is for detecting multiline custom comments.
			
			//skip a newline
			if(r.startsWith('\n')) { r.popFront; }
			else if(r.startsWith("\r\n")) { r.popFront; r.popFront; }
			else return r; 
			
			//skip tabs
			while(r.startsWith('\t')) r.popFront; 
			return r; 
		} 
		
		
		static private int detectCustomCommentIdx(R)(R r)
		{
			//this is in human readable comments, so it is case insensitive.
			auto src = skipNewLineAndTabs(r).map!toLower; 
			enum keywords = customCommentPrefixes.map!toLower.array; 
			return src.startsWithKeyword!keywords-1; 
			//return src.startsWith!q{a.toLower == b.toLower}(aliasSeqOf!(customCommentPrefixes)).to!int - 1; 
		} 
		
		
		static private int detectCustomDirectiveIdx(R)(R r)
		{
			//Opt: This whole function is slow
			
			//const t0 = now; 
			
			//const idx = (cast(int)(customDirectivePrefixes.countUntil!((prefix)=>(r.startsWith(prefix))))); /+6.85e-5+/
			//const idx = r.startsWith(aliasSeqOf!(customDirectivePrefixes)).to!int - 1; /+0.000646+/
			const idx = r.startsWithKeyword!customDirectivePrefixes-1; /+
				char: 2.98e-05  
				dchar: 5.77e-05
				+wholeWords: 0.0001232
			+/
			
			//static tSum = 0*second; tSum += now-t0; static tCnt = 0; print(tCnt, tSum); 
			
			return idx; 
		} 
		
		/+protected+/
		void promoteCustomDirective()
		{
			//Note: this is called from #directive detection after manually creating a directive.
			
			//Todo: combine this with new CodeComment(directive)
			
			if(type != Type.directive) return; 
			if(customPrefix != "") return; 
			
			const idx = detectCustomDirectiveIdx(content.rows[0].chars); 
			if(idx>=0) {
				customPrefix = customDirectivePrefixes[idx]; 
				customSyntax = skDirective; 
				
				//Bug: this operation ruins undo/redo
				auto row = content.rows[0]; 
				
				//remove prefix
				row.subCells = row.subCells[customPrefix.walkLength..$]; 
				
				if(auto multilineMacroBlock = findMultilineMacroBlock(row))
				{
					//acquire the contents of the enclosed multilineMacro
					content = multilineMacroBlock.content; 
					content.setParent(this); 
					needMeasure; 
				}
				else
				{
					//remove space
					if(row.chars.startsWith(' '))
					row.subCells = row.subCells[1..$]; 
					
					row.refreshTabIdx; 
					row.needMeasure; 
				}
			}
		} 
		
		const
		{
			override SyntaxKind syntax()
			{
				return customPrefix=="" 	? (type==Type.directive ? skDirective : skComment)
					: customSyntax; ; 
			} 
			
			bool isDirective()
			{ return type == Type.directive; } 
			
			bool isCustom()
			{ return customPrefix != ""; } 
			bool isLink()
			{ return customPrefix == "Link:"; } 
			
			bool isHighlighted()
			=> customPrefix == "Highlighted:"; 
			bool isStructured()
			=> customPrefix == "Structured:"; 
			bool isCode() const
			=> customPrefix == "Code:"; 
			
			bool isCodeRelated() const
			=> isCode || isStructured || isHighlighted; 
			
			
			bool isNote()
			{ return customPrefix == "Note:"; } 
			bool isHidden()
			{ return customPrefix == "Hidden:"; } 
			
			bool isAi() const
			=> customPrefix=="AI:"; 	bool isSystem() const
			=> customPrefix=="System:"; 
			bool isUser() const
			=> customPrefix=="User:"; 	bool isAssistant() const
			=> customPrefix=="Assistant:"; 
			bool isAiRelated() const
			=> isAi || isSystem || isUser || isAssistant; 
			
			bool isFormatBold() const
			=> customPrefix=="Bold:"; 	bool isFormatItalic() const
			=> customPrefix=="Italic:"; 
			bool isFormatBullet() const
			=> customPrefix=="Bullet:"; 	bool isFormatPara() const
			=> customPrefix=="Para:"; 
			int isFormatHeading() const
			=> ((
				customPrefix.length==3 && 
				customPrefix[0]=='H' &&
				customPrefix[1].inRange('1', '6') && 
				customPrefix[2]==':'
			)?(customPrefix[1]-'0'):(0)); 
			bool isFormatRelated() const
			=> isFormatBold || isFormatItalic || isFormatBullet || isFormatPara || isFormatHeading; 
			
			
			/+Todo: refactor this with an enum+/
			
			string commentPrefix()
			{ return typePrefix[type]; } 
			
			override string prefix()
			{
				auto s = commentPrefix; 
				if(customPrefix != "")
				s ~= customPrefix ~ ' '/+Mandatory space after a custom prefix+/; 
				
				return s; 
			} 
			override string postfix()
			{ return typePostfix[type]; } 
		} 
		
		
		this(CodeRow parent)
		{ super(parent); } 
		
		
		
		override void buildSourceText(ref SourceTextBuilder builder)
		{
			enforce(verify, "Invalid comment format"); 
			builder.put(commentPrefix, customPrefix, content, postfix); 
		} 
		
		version(/+$DIDE_REGION BuildMessage handling+/all)
		{
			CodeColumn buildMessageColumn; 
			
			override CodeColumn* accessBuildMessageColumn()
			{ return &buildMessageColumn; } 
		}
		
		
		void rebuild(R)(R scanner) if(isScannerRange!R)
		{
			type = parseBlockPrefix!(Type, typePrefix)(scanner); 
			
			customPrefix = ""; 
			customSyntax = skWhitespace; 
			
			isDDoc = !scanner.empty && scanner.front.op==ScanOp.content && scanner.front.src.startsWith(prefix.back); 
			
			//build content
			auto rebuilder = CodeColumnBuilder!true(content); 
			bool customDetectionComplete; 
			
			while(!scanner.empty)
			{
				if(scanner.front.op==ScanOp.push)
				{
					//opening a new something
					if(scanner.front.src=="/+")
					{
						auto n = new CodeComment(rebuilder.actRow);  //RECURSION!!!!!
						n.rebuild(scanner); 
						rebuilder.appendNode(n); 
						continue; 
					}
					else
					{ enforce(0, "Invalid push: "~scanner.front.src); }
				}
				else if(scanner.front.op==ScanOp.pop)
				{
					//closing token
					scanner.popFront; 
					break; 
				}
				else
				{
					const isContent = scanner.front.op==ScanOp.content; 
					auto s = scanner.front.src; 
					
					//right at the beginning, detect the custom keyword
					if(customDetectionComplete.chkSet && isContent)
					{
						if(type == Type.directive)
						{
							/+
								Note: this is unused because #directive detection is not in 
								the implemented in the scanner, it's a later pass that creates 
								the dirctive comment manually, and calls promoteCustomDirective()
							+/
							enforce(0, "This should be implemented by the scanner. No other ways to call this."); 
							version(/+$DIDE_REGION+/none)
							{
								const idx = detectCustomDirectiveIdx(s); 
								if(idx >= 0)
								{
									customPrefix = customDirectivePrefixes[idx]; 
									customSyntax = skDirective; 
								}
							}
						}
						else
						{
							const idx = detectCustomCommentIdx(s); 
							if(idx >= 0)
							{
								customPrefix = customCommentPrefixes[idx]; 
								customSyntax = customCommentSyntaxes[idx]; 
								
								if(customSyntax==skInherit)
								{
									customSyntax = 	this.allParents!CodeContainer
										.map!((a)=>(a.syntax)).filter!((s)=>(s!=skInherit)).frontOr(skComment); 
								}
							}
						}
						
						//remove customPrefix from content
						if(customPrefix != "")
						{
							static string fetchNewLineAndTabs(ref string s)
							{
								const sFull = s; 
								const fullLength = sFull.length; 
								s = skipNewLineAndTabs(s); 
								const whiteLength = fullLength - s.length; 
								const sWhite = sFull[0 .. whiteLength]; 
								return sWhite; 
							} 
							
							const sWhite = fetchNewLineAndTabs(s); 
							
							assert(s.startsWith!"a.toLower==b.toLower"(customPrefix), "Custom prefix must be exact."); 
							s = sWhite ~ s[customPrefix.length..$].withoutStarting(' '); 
						}
						
						rebuilder.syntax = skComment; 
						/+
							Note: Rebuilder syntax is set to skComment because that can be outdented later.
												After the rebuild, in the realign pass, the proper syntax highlight will be applied.
						+/
					}
					
					if(!isContent) rebuilder.syntax = skError; 
					//Todo: don't add error message as it would be the code text.
					
					rebuilder.appendStr(s); 
				}
				
				//advance
				scanner.popFront; 
			}
			
			content.convertSpacesToTabs(Yes.outdent); 
			needMeasure; 
			
			if(isStructured || isCode && content.rowCount>1)
			{
				try { content = new CodeColumn(this, content.sourceText, TextFormat.managed_optionalBlock, content.rows[0].lineIdx); }
				catch(Exception e) {}
			}
		} 
		
		bool isSpecialComment()
		{
			return content.byShallowChar.startsWith(specialCommentMarker); 
			//Opt: startsWith should get a real range, not a copy of the full string.
		} 
		
		string extractSpecialComment()
		{
			return isSpecialComment ? content.sourceText.withoutStarting(specialCommentMarker) : ""; 
			//Opt: this  builds the whole string, but only extracts the first word.
		} 
		
		bool isSpecialComment(string keyword)
		{ return extractSpecialComment.wordAt(0)==keyword; } 
		
		@property isCodeLocationComment() => isSpecialComment("LOC"); 
		@property isButtonComment() => isSpecialComment("BTN"); 
		
		bool verify(bool markErrors = false)()
		{
			//Todo: fix this whole verification concept!
			
			bool anyErrors; 
			
			RGB errorBkColor, errorFontColor; 
			bool errorColorsValid; 
			
			//fill the whole context with default homogenous syntax
			if(markErrors)
			{
				//Opt: this is only needed when the syntax or the error state has changed.
				
				if(isCodeRelated)
				{
					//just highlighted
					content.resyntax; 
					/+
						Todo: this can change the width of the chars.
						All width changing syntax operations should be 
						handled properly in the resyntaxer.
					+/
					content.needMeasure; /+
						Note: 	This is just a workaround.
						<- 	Calling measure() won't work, because it only 
							works at that level and beyond.
							needMeasure() is recursive through all parents
					+/
				}
				else
				content.fillSyntax(syntax); 
			}
			
			
			void mark(Glyph g)
			{
				if(markErrors)
				if(g) {
					/+
						Todo: There should be a fontFlag: Error, and the GPU should 
						calculate the actual color from a themed palette
					+/
					if(errorColorsValid.chkSet)
					{
						errorBkColor = syntaxBkColor(skError); 
						errorFontColor = syntaxFontColor(skError); 
					}
					
					//Todo: this red shit is fucking annoying!!!
					version(/+$DIDE_REGION RGN+/none)
					{
						g.bkColor = errorBkColor; 
						g.fontColor = errorFontColor; 
					}
				}
				
				anyErrors = true; 
			} 
			
			auto byGlyph()
			{ return content.rows.map!(r => r.glyphs).joiner(only(null)); } 
			
			void checkInvalid(dchar ch)
			{ byGlyph.each!((g){ if(anyErrors || g && g.ch==ch) mark(g); }  ); } 
			
			void checkInvalid2(dchar ch0, dchar ch1)
			{
				bool lastCh0; 
				foreach(g; byGlyph)
				{
					const actCh0 = g && g.ch==ch0; 
					if(anyErrors || lastCh0 && g && g.ch==ch1) mark(g); 
					lastCh0 = actCh0; 
				}
			} 
			
			//Todo: redundant code
			void checkNesting(dchar chOpen, dchar chClose)
			{
				if(chOpen==chClose)
				{ checkInvalid(chOpen); }
				else
				{
					content.fillSyntax(syntax); 
					
					int cnt; 
					byGlyph.each!(
						(g){
							if(g)
							{
								if(g.ch==chOpen) cnt++; 
								else if(g.ch==chClose) cnt--; 
								
								if(anyErrors || cnt<0) mark(g); 
							}
						}  
					); 
					
					if(
						cnt>0//unclosed nesting!
					)
					{
						anyErrors = true; 
						//Todo: mark unclosed nesting
					}
				}
			} 
			
			void checkOneLine()
			{
				if(content.rowCount>1)
				{
					anyErrors = true; 
					if(markErrors)
					{
						auto a = content.rows.drop(1).map!(r => r.glyphs).joiner; 
						a.each!(g => mark(g)); 
					}
				}
			} 
			
			with(Type)
			final switch(type)
			{
				case slashComment: 	checkOneLine; 	break; 
				case cComment: 	checkInvalid2('*', '/'); 	break; 
				case dComment: 	checkInvalid2('+', '/'); checkInvalid2('/', '+'); 	break; 
				case directive: 	checkNesting('(', ')')/+
					it's just a little check, 
					not a complete one...
				+/; 	break; 
			}
			
			//Todo: this red shit is fucking annoying!
			version(/+$DIDE_REGION RGN+/none)
			{
				if(anyErrors && markErrors && !isHighlighted/+highlighted comment can be is partially filled by AI Chat.+/)
				{
					if(!isAiRelated && !isFormatRelated)
					fillSyntax(skError); 
				}
			}
			
			return true; //Todo: This test is temporarily disable, so the Stickers can be edited.
			
			//return !anyErrors; 
		} 
		
		private bool cached_isButtonCommand; 
		
		override void rearrange()
		{
			cached_isButtonCommand = false; 
			
			void defaultRearrange()
			{
				if(isCustom)
				{
					with(nodeBuilder(syntax, ((isDirective)?(NodeStyle.bright) :(NodeStyle.dim))))
					{
						content.bkColor = darkColor; 
						
						if(isHidden)
						{
							margin.set(.5); border.width /= 3; padding.set(1); 
							style.fontHeight = DefaultFontHeight/4; 
							style.italic = false; 
							put(typePrefix[type].back); 
						}
						else
						{
							//Remove underlined style
							const origUnderline = style.underline; style.underline = false; 
							
							if(!isCodeRelated && !isNote && !isFormatRelated)
							put((isDirective ? '#' : ' ') ~ customPrefix ~ ' '); 
							
							style.underline = origUnderline; 
							
							void reformat(alias fun=void)()
							{
								content.fillSyntax(syntax/+This is inherited syntax.+/); 
								static if(!is(fun==void))
								{ foreach(g; content.byGlyph) { fun(g); }}
								
								void removeBorder(Container a)
								{
									a.border 	= Border.init, 
									a.margin 	= Margin.init, 
									a.padding 	= Padding.init; 
								} 
								removeBorder(this); removeBorder(content); 
							} 
							
							if(isFormatBold)	reformat!((g){ g.fontFlags |= 1; }); 
							else if(isFormatItalic)	reformat!((g){ g.fontFlags |= 2; }); 
							else if(
								isFormatPara ||
								isFormatBullet
							)	{
								style.bkColor = bkColor = syntax.syntaxBkColor; 
								if(isFormatBullet) put(` • `); 
								reformat; 
								padding.top = padding.bottom = 3; 
							}
							else if(auto level = isFormatHeading)
							{
								static immutable float[] headingScale = 
								[1, 2, 1.5, 1.17, 1, 0.83, 0.67]; 
								const newHeight = headingScale[level] * DefaultFontHeight; 
								reformat!((g){
									g.outerSize = vec2(((g.outerWidth)/(g.outerHeight))*newHeight, newHeight); 
									g.fontFlags |= 1; 
								}); 
							}
							
							put(content); 
							
							if(isDirective && content.empty)
							content.bkColor = mix(darkColor, brightColor, 0.75f); 
						}
						
						rearrangeNode; 
					}
				}
				else
				super.rearrange; 
				
				if(!isFormatRelated)
				verify!true; 
			} 
			
			
			if(isSpecialComment)
			{
				//Todo: use CommandLine here too
				const 	scmt = extractSpecialComment,
					keyword = scmt.wordAt(0); 
				switch(keyword)
				{
					case "IMG": 
						with(nodeBuilder(syntax, NodeStyle.dim))
					{
						auto cmd = scmt.CommandLine; 
						auto f = cmd.files.get(1);  //first file is command.
						
						if(f.fullName.startsWith(`$\`)/+$\ means the path of this module+/)
						{
							string path; 
							if(auto mod = moduleOf(this))
							path = mod.file.path.fullPath; 
							f = File(path, f.fullName[2..$]); 
						}
						
						style.italic = false; 
						
						const 	maxHeight	= cmd.option("maxHeight", -1),
							noBorder	= cmd.option("noBorder", 0),
							samplerEffectStr 	= cmd.option("samplerEffect", "none"),
							autoRefresh	= cmd.option("autoRefresh", 1); 
						
						//Load it immediatelly.
						auto bmp = bitmaps(f, No.delayed); 
						
						if(!bmp.valid)
						{ put('\U0001F5BC'); }
						else
						{
							if(noBorder)
							{
								padding = Padding(0); 
								border.width = 0; 
							}
							else
							{ padding = "4"; }
							
							auto img = new Img(f, darkColor); 
							
							img.autoRefresh = !!autoRefresh; 
							
							img.flags.autoWidth = false; 
							img.flags.autoHeight = false; 
							img.outerSize = bmp.size.vec2; 
							
							img.samplerEffect = samplerEffectStr	.to!SamplerEffect
								.ifThrown(SamplerEffect.none); 
							
							
							//restrict maxHeight
							if(maxHeight>0 && img.outerHeight>maxHeight)
							{ img.outerSize = vec2(((img.outerWidth*maxHeight)/(img.outerHeight)), maxHeight); }
							
							put(img); 
						}
						
						rearrangeNode; 
					}
						break; 
					case "LOC": 
						with(nodeBuilder(skIdentifier1, NodeStyle.bright))
					{
						with(style) italic = false, bold = false; 
						auto 	locStr 	= scmt[keyword.length..$].stripLeft,
							loc	= CodeLocation(locStr),
							img	= new Img(File(`icon:\`~loc.file.ext), style.bkColor); 
						img.autoRefresh = false; //For 1000 iconst it would be terribly slow!!!
						
						id = "CodeLocation:"~locStr; 
						
						img.height = style.fontHeight; 
						put(img); 
						put(loc.file.path.fullPath); 
						style.bold = true; put(loc.file.nameWithoutExt); style.bold = false; 
						put(loc.file.ext); 
						put(loc.mixinText ~ loc.lineColText); 
						rearrangeNode; 
					}
						break; 
					case "MSG": 
						{
						with(nodeBuilder(skIdentifier1, NodeStyle.bright))
						{
							/+Todo: It's deprecated.+/
							bkColor = clBlue; 
							style.bkColor = clBlue; 
							style.fontColor = blackOrWhiteFor(style.bkColor); 
							with(style) italic = false, bold = false; 
							
							//img = new Img(File(`icon:\`~loc.file.ext), style.bkColor);
							//img.height = style.fontHeight;
							put(content.sourceText); 
							rearrangeNode; 
						}
					}
						break; 
					case "BTN": 
						{
						cached_isButtonCommand = true; 
						with(nodeBuilder(skIdentifier1, NodeStyle.normal))
						{
							with(style) italic = false, bold = false; 
							const params = scmt[keyword.length..$].stripLeft.CommandLine; 
							put("  "~params.names.get(0)~"  "); 
							
							rearrangeNode; 
						}
					}
						break; 
					
					default: 
					//nothing. process it normally like a comment
					defaultRearrange; 
				}
			}
			else
			defaultRearrange; 
			
			rearrange_appendBuildMessages; 
		} 
		
		version(/+$DIDE_REGION UI Interaction+/all)
		{
			override void draw(Drawing dr)
			{
				super.draw(dr); 
				if(cached_isButtonCommand) if(auto m = moduleOf(this)) m.visibleButtonComments ~= this; 
			} 
			
			void generateUI(bool en, int targetSurface_=0)
			{
				if(isSpecialComment)
				{
					auto scmt = extractSpecialComment; 
					const keyword = scmt.wordAt(0); 
					if(keyword=="BTN")
					{
						const 	params = scmt[keyword.length..$].stripLeft,
							cmd = params.CommandLine/+Opt: this is slow to get only the first name+/; 
						with(im)
						if(
							Btn(
								cmd.names.get(0), (("CodeComment_BTN"~this.identityStr).genericArg!q{id}),
								{
									flags.targetSurface = targetSurface_; margin = "0"; 
									outerPos = worldOuterPos(this)-2; outerSize = this.outerSize+4; 
								}
							)
						)
						{
							if(auto m = moduleOf(this))
							if(auto ws = (cast(IWorkspace)(m.parent)))
							ws.handleButtonCommentClick(this, params); 
						}
					}
				}
			} 
		}
	} class CodeString : CodeContainer
	{
		mixin((
			(表([
				[q{/+Note: Type+/},q{/+Note: Prefix+/},q{/+Note: Postfix+/}],
				[q{dString},q{"`"},q{"`"}],
				[q{cChar},q{"'"},q{"'"}],
				[q{cString},q{`"`},q{`"`}],
				[q{rString},q{`r"`},q{`"`}],
				[q{qString_round},q{`q"(`},q{`)"`}],
				[q{qString_square},q{`q"[`},q{`]"`}],
				[q{qString_curly},q{`q"{`},q{`}"`}],
				[q{qString_angle},q{`q"<`},q{`>"`}],
				[q{qString_slash},q{`q"/`},q{`/"`}],
				[q{tokenString},q{`q{`},q{`}`}],
				[q{hexString},q{`x"`},q{`"`}],
				[q{interpolated_cString},q{`i"`},q{`"`}],
				[q{interpolated_dString},q{"i`"},q{"`"}],
				[q{interpolated_tokenString},q{`iq{`},q{`}`}],
				[],
				[q{/+_text variants are converted from: /+Code: i"".text+/+/}],
				[q{interpolated_cString_text},q{`ti"`},q{`"`}],
				[q{interpolated_dString_text},q{"ti`"},q{"`"}],
				[q{interpolated_tokenString_text},q{`tiq{`},q{`}`}],
				[q{interpolated_tokenString_text_mixin},q{`mixin${`},q{`}`}],
				[],
				[q{//Todo: qString_id
				}],
			]))
		).調!(GEN_enumTable)); 
		
		enum CharSize
		{ default_, c, w, d} 
		
		Type type; 
		CharSize charSize; 
		
		string sizePostfix() const
		{ return charSize!=CharSize.default_ ? charSize.text : ""; } 
		
		override SyntaxKind syntax() const
		{
			if(isTableCell && type==Type.tokenString) return skIdentifier1; 
			if(type==Type.interpolated_tokenString_text_mixin) return skSymbol; 
			return skString; 
			/+
				Note: For tokenStrings this must be skString too. So all string's border be the same color.
				(Different behavior  -> isTableCell)
			+/
		} 
		override string prefix() const
		{ return typePrefix[type]; } 
		override string postfix() const
		{ return typePostfix[type]~sizePostfix; } 
		
		@property isSomeTokenString() const
		=> !!type.among(
			Type.tokenString, 
			Type.interpolated_tokenString, 
			Type.interpolated_tokenString_text,
			Type.interpolated_tokenString_text_mixin
		); 
		
		this(CodeRow parent) { super(parent); } 
		
		void rebuild(R)(R scanner) if(isScannerRange!R)
		{
			type = parseBlockPrefix!(Type, typePrefix)(scanner); 
			charSize = CharSize.default_; 
			
			//get content
			auto rebuilder = CodeColumnBuilder!true(content); 
			
			if(isSomeTokenString)
			{
				content.bkColor = mix(syntaxBkColor(skString), clCodeBackground, .75f); 
				//Todo: clCodeBackground should be inherited to all the inner backgrounds.
				//Todo: language dependent keyword coloring
				
				rebuilder.appendStructured(scanner); //this will stop at the closing "}"
				
				if(!scanner.empty && scanner.front.op==ScanOp.pop && scanner.front.src.startsWith("}"))
				{
					//closing token: Decode char/word/dword string element size specifier.
					if(auto cwdIdx = scanner.front.src.back.among('c', 'w', 'd'))
					charSize = cast(CharSize)cwdIdx; 
					
					scanner.popFront; 
				}
				else
				enforce(0, "Invalid tokenstring."); 
			}
			else
			{
				while(!scanner.empty)
				{
					if(
						type.among(Type.interpolated_cString, Type.interpolated_dString) &&
						!scanner.empty && scanner.front.op==ScanOp.push && scanner.front.src=="$("
					)
					{
						rebuilder.appendStructured(scanner); 
						continue; 
					}
					
					if(scanner.front.op==ScanOp.push)
					{ enforce(0, "Invalid push in string literal: "~scanner.front.src); }
					else if(scanner.front.op==ScanOp.pop)
					{
						//closing token: Decode char/word/dword string element size specifier.
						if(auto cwdIdx = scanner.front.src.back.among('c', 'w', 'd'))
						charSize = cast(CharSize)cwdIdx; 
						
						scanner.popFront; 
						break; 
					}
					else
					{
						rebuilder.syntax = scanner.front.op==ScanOp.content ? skString : skError; 
						rebuilder.appendStr(scanner.front.src); 
					}
					scanner.popFront; 
				}
			}
			
			needMeasure; 
		} 
		
		bool verify(bool markErrors = false)()
		{
			bool anyErrors; 
			void mark(Glyph g)
			{
				if(markErrors)
				if(g) {
					//Todo: There should be a fontFlag: Error, and the GPU should calculate the actual color from a themed palette
					g.bkColor = clRed; 
					g.fontColor = clYellow; 
				}
				
				anyErrors = true; 
			} 
			
			auto byGlyph()
			{ return content.rows.map!(r => r.glyphs).joiner(only(null)).filter!"a"; } 
			
			void checkInvalid(dchar ch)
			{
				content.fillSyntax(skString); 
				
				byGlyph.each!((g){ if(anyErrors || g && g.ch==ch) mark(g); }  ); 
			} 
			
			void checkInvalid_escape(dchar ch, dchar escape)
			{
				content.fillSyntax(skString); 
				
				bool lastEscape; 
				foreach(g; byGlyph)
				{
					const actEscape = g && g.ch==escape; 
					if(anyErrors || !lastEscape && g && g.ch==ch) mark(g); 
					lastEscape = actEscape; 
				}
			} 
			
			void checkNesting(dchar chOpen, dchar chClose)
			{
				if(chOpen==chClose)
				{ checkInvalid(chOpen); }
				else
				{
					content.fillSyntax(skString); 
					
					int cnt; 
					byGlyph.each!(
						(g){
							if(g)
							{
								if(g.ch==chOpen) cnt++; 
								else if(g.ch==chClose) cnt--; 
								
								if(anyErrors || cnt<0) mark(g); 
							}
						}  
					); 
					
					if(
						cnt>0//unclosed nesting!
					)
					{
						anyErrors = true; 
						//Todo: mark unclosed nesting
					}
				}
			} 
			
			with(Type)
			final switch(type)
			{
				case cString, cChar, interpolated_cString, interpolated_cString_text: 	checkInvalid_escape(typePrefix[type].back, '\\'); 	break; 
				case dString, rString, interpolated_dString, interpolated_dString_text, hexString: 	checkInvalid(typePrefix[type].back); 	break; 
				case qString_round, qString_square, qString_curly, qString_angle, qString_slash: 	checkNesting(typePrefix[type].back, typePostfix[type].front); 	break; 
				case tokenString, interpolated_tokenString, interpolated_tokenString_text, 
					interpolated_tokenString_text_mixin: 		break; 
				/+Todo: Any symbol can be used, not just slash '/'. The symbol in the qString must be a parameter.+/
				//Todo: Identifier delimited qString.
				//Todo: interpolated string verification.
				//Todo: hexString verification.
			}
			
			
			if(anyErrors && markErrors)
			{ fillSyntax(skError); }
			
			return !anyErrors; 
		} 
		
		override void rearrange()
		{
			super.rearrange; 
			verify!true; 
			rearrange_appendBuildMessages; 
		} 
		
		version(/+$DIDE_REGION BuildMessage handling+/all)
		{
			CodeColumn buildMessageColumn; 
			
			override CodeColumn* accessBuildMessageColumn()
			{ return &buildMessageColumn; } 
		}
		
		override void buildSourceText(ref SourceTextBuilder builder)
		{
			enforce(verify, "Invalid string literal format"); 
			switch(type)
			{
				case	Type.interpolated_cString_text,
					Type.interpolated_dString_text,
					Type.interpolated_tokenString_text: 	{
					builder.putSeparatorSpace; 
					builder.put(prefix.withoutStarting('t'), content, postfix~".text"); 
				}	break; 
				case Type.interpolated_tokenString_text_mixin: 	{
					builder.putSeparatorSpace; 
					builder.put("mixin(iq{", content, postfix~".text)"); 
				}	break; 
				default: 	{ super.buildSourceText(builder); }
			}
		} 
		
		/+Bug: Multiline interpolated string: It can't save the last empty(!) line.+/
		
		void promoteToInterpolatedText(CodeRow row, int cellIdx)
		{
			if(
				const tid = type.among(
					Type.interpolated_cString,
					Type.interpolated_dString,
					Type.interpolated_tokenString
				)
			)
			{
				assert(parent is row); 
				assert(cellIdx==row.subCellIndex(this)); 
				
				enum kw = ".text"; 
				auto chars = row.chars[cellIdx+1..$]; 
				if(
					chars.startsWith(kw) &&
					!isDLangIdentifierCont(chars.drop(kw.length).frontOr(dchar(' ')))
				)
				{
					type = tid.predSwitch(
						1, Type.interpolated_cString_text,
						2, Type.interpolated_dString_text,
						3, Type.interpolated_tokenString_text
					); 
					row.subCells = row.subCells.remove(tuple(cellIdx+1, cellIdx+1+kw.length)); 
					row.refreshTabIdx; 
					row.needMeasure; 
				}
			}
		} 
		
		
		void promoteInterpolatedTokenStringTextMixin(CodeColumn parentCol)
		{
			if(type==CodeString.Type.interpolated_tokenString_text)
			if(auto blk = (cast(CodeBlock)(parentCol.parent)))
			if(blk.type==CodeBlock.Type.stringMixin)
			if(auto blkRow = blk.parent)
			{
				const blkIdx = blkRow.subCellIndex(blk); 
				if(blkIdx>=0)
				{
					blkRow.subCells[blkIdx] = this; 
					this.setParent(blkRow); 
					this.type = CodeString.Type.interpolated_tokenString_text_mixin; 
					this.needMeasure; 
				}
			}
		} 
	} 
	class CodeBlock : CodeContainer
	{
		mixin((
			(表([
				[q{/+Note: Type+/},q{/+Note: Prefix+/},q{/+Note: Postfix+/}],
				[q{block},q{"{"},q{"}"}],
				[q{list},q{"("},q{")"}],
				[q{index},q{"["},q{"]"}],
				[q{interpolation},q{"$("},q{")"}],
				[q{stringMixin},q{"mixin("},q{")"}],
				[q{stringImport},q{"import("},q{")"}],
				[q{traits},q{"__traits("},q{")"}],
				[q{rvalue},q{"__rvalue("},q{")"}],
				[q{ctfeWrite},q{"__ctfeWrite("},q{")"}],
				[q{pragmaExpr},q{"pragma("},q{")"}],
				[q{typeofExpr},q{"typeof("},q{")"}],
				[q{typeidExpr},q{"typeid("},q{")"}],
				[q{isExpr},q{"is("},q{")"}],
			]))
		).調!(GEN_enumTable)); 
		
		Type type; 
		
		override SyntaxKind syntax	() const
		{
			return type<=Type.stringMixin ? skSymbol : 
			type==Type.stringImport ? skIdentifier4 : 
			skAttribute; 
		} 
		override string prefix() const
		{ return typePrefix[type]; } 
		override string postfix() const
		{ return typePostfix[type]; } 
		override @property NodeStyle nodeStyle() const
		=> ((type<=Type.index) ?(NodeStyle.dim):(((type<=Type.stringMixin) ?(NodeStyle.normal):(NodeStyle.bright)))); 
		
		this(Container parent)
		{ super(parent); } 
		
		void rebuild(R)(R scanner) if(isScannerRange!R)
		{
			type = parseBlockPrefix!(Type, typePrefix)(scanner); 
			auto rebuilder = CodeColumnBuilder!true(content); 
			rebuilder.appendStructured(scanner); //this will stop at the closing token
			if(!scanner.empty && scanner.front.op==ScanOp.pop && scanner.front.src==postfix)
			{
				//Note: -> processHighLevel will deal with this later.
				scanner.popFront; 
			}
			else
			enforce(0, "Invalid block closing token"); 
			
			needMeasure; 
		} 
	} 
}