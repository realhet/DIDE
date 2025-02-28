module dideexpr; 

import het.ui, het.parser, dideui, didebase; 
import diderow : CodeRow, SourceTextBuilder; 
import didecolumn : CodeColumn; 
import didenode : NodeStyle, CodeNode, CodeContainer, CodeString, CodeBlock, CodeComment, CodeNodeBuilder; 
import didedecl : Declaration, extractThisLevelDString, isBreakRow; 
import didemodule : Module, TextFormat, StructureLevel, DefaultSubScriptFontHeight, moduleOf; 


alias blink = dideui.blink; 


version(/+$DIDE_REGION+/all) {
	version(/+$DIDE_REGION+/all)
	{
		enum lowestSpecialUnicodeChar = '\u3000' /+Contains all chinese chars used in NiceExpressions+/; 
		
		mixin((
			(表([
				[q{/+Note: NiceExpressionPattern : ubyte+/},q{/+Note: OpCnt+/},q{/+Note: Text#+/}],
				[q{null_},q{0},q{/+Code:+/},q{/+Note:+/}],
				[q{unaryOp},q{1},q{/+Code: op(expr)+/},q{/+Note: ^^  .pow+/}],
				[q{binaryOp},q{2},q{/+Code: (expr)op(expr)+/},q{/+Note: sqrt RGB+/}],
				[q{tenaryOp},q{3},q{/+Code: (expr)op(expr)op(expr)+/},q{/+Note: ?:+/}],
				[q{castOp},q{2},q{/+Code: op(expr)(expr)+/},q{/+Note: cast+/}],
				[q{namedUnaryOp},q{2},q{/+Code: (expr)opq{code}+/},q{/+Note: genericArg!+/}],
				[q{binaryTokenStringOp},q{2},q{/+Code: op(q{},q{})+/},q{/+Note: 表! (old MixinTable)+/}],
				[q{tenaryTokenStringOp},q{3},q{/+Code: op(q{},q{},q{})+/},q{/+Note: Sigma operations+/}],
				[q{twoParamOp},q{2},q{/+Code: op((expr),(expr))+/},q{/+Note:+/}],
				[q{threeParamOp},q{3},q{/+Code: op((expr),(expr),(expr))+/},q{/+Note:+/}],
				[q{twoParamEQOp},q{2},q{/+Code: op((expr),q{})+/},q{/+Note:+/}],
				[q{threeParamEQEOp},q{3},q{/+Code: op((expr),q{},(expr))+/},q{/+Note:+/}],
				[q{mixinTableInjectorOp},q{2},q{/+Code: (){with(op(expr)){expr}}()+/},q{/+Note: 表 new MixinTable+/}],
				[q{anonymMethod},q{2},q{/+Code: (expr)op{code}+/},q{/+Note: anonym method (without attrs)+/}],
				[],
				[q{/+Note: special statement: any single row statement where the last char must is a unicode special char+/}],
				[q{specialStatementOp},q{0},q{/+Code: specialStatement+/},q{/+Note: auto 間T=now間+/}],
			]))
		).調!(GEN_enumTable)); 
		
		mixin((
			(表([
				[q{/+Note: NiceExpressionBlockType : ubyte+/},q{/+Note: Prefix+/},q{/+Note: Postfix+/}],
				[q{list},q{"("},q{")"}],
				[q{stringMixin},q{"mixin("},q{")"}],
				[q{templateMixin},q{"mixin "},q{""}],
				[q{specialStatement},q{""},q{""}],
			]))
		).調!(GEN_enumTable)); 
		
		enum NiceExpressionClass
		{
			NiceExpression, 
			ColorNode, 
			MixinNode, 
			MixinGenerator, 
			MixinTable, 
			SigmaOp, 
			Inspector, 
			InteractiveValue 
		} 
		
		
		private alias NEB = NiceExpressionBlockType; 
		private alias NEP = NiceExpressionPattern; 
		private alias NEC = NiceExpressionClass; 
		
		
		static if(
			0//Todo: tenary lambda.  (a lambdra which is evaluated)
		)
		auto aaaa = ((){ with(op(expr1)) { expr2; }}()); 
		
		
		struct NiceExpressionTemplate
		{
			string name; 
			NiceExpressionBlockType blockType; 
			NiceExpressionPattern pattern; 
			SyntaxKind syntax; 
			NodeStyle invertMode; 
			string example, operator; 
			string textCode, rearrangeCode, drawCode, initCode, uiCode; 
			NiceExpressionClass customClass; 
			
			
			@property string combinedPattern() const
			=> niceExpressionBlockTypePrefix[blockType]~
			niceExpressionPatternText[pattern]~
			niceExpressionBlockTypePostfix[blockType]; 
			
			@property void combinedPattern(string ptn)
			{
				void setNEP(NEB bt, string ptn)
				{
					this.blockType = bt; 
					try this.pattern = 	niceExpressionPatternText.countUntil(ptn).to!NEP; 
					catch(Exception e) raise("Unknown NEP: "~ptn.quoted); 
				} 
				if(ptn.startsWith('(') && ptn.endsWith(')'))
				setNEP(NEB.list, ptn.withoutStartingEnding('(',')')); 
				else if(ptn.startsWith("mixin(") && ptn.endsWith(')'))
				setNEP(NEB.stringMixin, ptn.withoutStartingEnding("mixin(", ')')); 
				else if(ptn.startsWith("mixin "))
				setNEP(NEB.templateMixin, ptn.withoutStarting("mixin ")); 
				else if(ptn=="specialStatement")
				setNEP(NEB.specialStatement, "specialStatement"); 
				else if(ptn!="" /+for null_ it's ok+/)
				raise("Unknown NEP contaner: "~ptn.quoted); 
			} 
		} 
		
		string exportNiceExpressionTemplate(NiceExpressionTemplate net) 
		{
			with(net)
			{
				auto ts(string s) => "q{"~s~"}"; 
				auto str(string s) => ts('"'~s~'"'); 
				auto cmtCode(string s) => ts("/+Code: "~s~"+/"); 
				auto src(string label, string s) => ((s!="")?("@"~label~": "~s):("")); 
				return "["~only
				(
					ts(name), ts(example), 
					cmtCode(combinedPattern), 
					str(operator), ts(invertMode.text), ts(syntax.text), ts(customClass.text), 
					ts(
						src("init", initCode)	~ src("text", textCode)	~
						src("node", rearrangeCode)	~ src("draw", drawCode)	~
						src("ui", uiCode)
					)
				)
				.join(',')~"],\n"; 
			}
		} 
		
		auto makeNiceExpressionTemplate(string[] a...)
		{
			NiceExpressionTemplate res; 
			with(res)
			{
				name 	= a[0],
				example 	= a[1],
				combinedPattern 	= a[2].unpackDComment!"Code",
				operator 	= a[3].withoutStartingEnding('"','"'),
				invertMode 	= a[4].to!NodeStyle,
				syntax 	= a[5].to!SyntaxKind,
				customClass 	= a[6].to!NiceExpressionClass; 
				
				const scr = a[7]; 
				auto scrFields = [&textCode, &rearrangeCode, &drawCode, &initCode, &uiCode]; 
				enum ids = ["text", "node", "draw", "init", "ui"]; 
				const positions = ids.map!((id)=>(scr.indexOf("@"~id~":"))).array; 
				foreach(i, pos; positions)
				if(pos>=0)
				{
					auto higher = positions.filter!((a)=>(a>pos)); 
					const nextPos = ((higher.empty)?(scr.length):(higher.minElement)); 
					*(scrFields[i]) = scr[pos+1+ids[i].length+1 .. nextPos]; 
				}
			}
			return res; 
		} 
		
		version(/+$DIDE_REGION Mixin Table helpers+/all)
		{
			alias MixinTableContainerClass = CodeContainer
			/+The root class of all type of table cells.+/; 
			
			static bool isMixinTableCell(Cell a)
			{ return !!(cast(MixinTableContainerClass)(a)); } 
			
			static bool mixinTableSplitFun(Cell a, Cell b)
			{ return isMixinTableCell(a) || isMixinTableCell(b); } 
		}
		
		
		int[Tuple!(immutable(NEB), immutable(NEP), string)] niceExpressionTemplateIdxByTypeOperator; 
		
		shared static this()
		{
			foreach(idx, const ref t; niceExpressionTemplates)
			niceExpressionTemplateIdxByTypeOperator[tuple(t.blockType, t.pattern, t.operator)] = idx.to!int; 
		} 
		
		int findNiceExpressionTemplateIdx(NEB bt, NEP ptn, string operator)
		{
			auto a = tuple(cast(immutable)bt, cast(immutable)ptn, operator) in niceExpressionTemplateIdxByTypeOperator; 
			return a ? *a : 0; 
			
			//Todo: This should be an enum.
		} 
		
		struct InteractiveControlProps
		{
			float w=0, h=0, min=0, max=1, step = 0.1; 
			int type; /*0: linear, 1:logarithmic, 2:circular 3:endless*/
			int hideExpr; 
			int halfSize; 
			int newLine, sameBk; 
			int rulerSides, /+bit0:topLeft, bit1:bottomRight+/
				rulerDiv0, rulerDiv1; 
			
			int btnEvent; //0 = no button, 1=hold
			string btnCaption; 
		} 
		
		string extractTrailingCommentText(string prefix)(CodeColumn col)
		{
			if(col)
			{
				if(auto cmt = col.lastComment)
				if(cmt.content.firstRow.chars.startsWith(prefix))
				{
					auto res = cmt.content.shallowText; 
					col.rows.back.subCells.length--; //remove the comment
					return res; 
				}
			}
			return ""; 
		} 
		
		auto commandLineToStruct(S)(string txt)
		{
			S res; 
			if(txt.length)
			{
				auto props = txt.CommandLine; 
				static foreach(field; FieldAndFunctionNamesWithUDA!(S, STORED, true))
				{
					{
						alias f = __traits(getMember, res, field); 
						__traits(getMember, res, field) = props.option(field, __traits(getMember, res, field)); 
						/+Opt: This is too slow for sparse settings.+/
					}
				}
			}
			return res; 
		} 
		
		version(/+$DIDE_REGION ProcessNiceExpr. helpers+/all)
		{
			auto asCodeBlock(string expectedType="")(Cell cell)
			{
				static if(expectedType=="tokenString")	alias T = CodeString; 
				else	alias T = CodeBlock; 
				if(auto blk = (cast(T)(cell)))
				{
					if(
						expectedType=="" || 
						blk.type==mixin(q{T.Type.}~expectedType)
					) return blk; 
				}
				return null; 
			} 
			alias asListBlock 	= asCodeBlock!q{list},
			asStringMixinBlock 	= asCodeBlock!q{stringMixin},
			asTokenStringBlock 	= asCodeBlock!q{tokenString}; 
			
			static auto asStatementBlockDeclaration(Cell cell)
			{ if(auto dcl = (cast(Declaration)(cell))) if(dcl.isBlock && dcl.keyword=="" && dcl.attributes.empty) return dcl; return null; } 
			static CodeColumn asStatementBlockContents(Cell cell)
			{
				if(auto dcl = asStatementBlockDeclaration(cell)) return dcl.block; 
				if(auto blk = (cast(CodeBlock)(cell))) if(blk.type==CodeBlock.Type.block) return blk.content; 
				return null; 
			} 
			
			static CodeColumn[] extractCodeColumnParams(string what)(CodeColumn col)
			{
				//unpacks (*,*,...)
				if(col.rowCount==1)
				{
					auto row = col.rows[0]; 
					const cc = row.cellCount; 
					if((cc&1) /+cellCount must be odd+/)
					{
						if(iota(1, cc, 2).all!((i)=>(row.chars[i]==','))/+must be separated by commas+/)
						{
							static if(what=="q{}")
							{
								auto params = iota(0, cc, 2).map!((i)=>((cast(CodeString)(row.subCells[i])))).array; 
								if(params.all!((s)=>(s && s.type==CodeString.Type.tokenString)))
								{ return params.map!((p)=>(p.content)).array; }
							}
							else if(what=="()")
							{
								auto params = iota(0, cc, 2).map!((i)=>((cast(CodeBlock)(row.subCells[i])))).array; 
								if(params.all!((b)=>(b && b.type==CodeBlock.Type.list)))
								{ return params.map!((p)=>(p.content)).array; }
							}
							else if(what=="()q{}"/+the 2nd param is a tokenString, rest are brackets+/)
							{
								auto params = iota(0, cc, 2).map!
								((i){
									auto c = (cast(CodeContainer)(row.subCells[i])); 
									if(i==2)	{
										if(auto s=(cast(CodeString)(c)))
										if(s.type==CodeString.Type.tokenString) return c; 
									}
									else	{
										if(auto b=(cast(CodeBlock)(c)))
										if(b.type==CodeBlock.Type.list) return c; 
									}
									return null; 
								}).array; 
								if(params.all)
								{ return params.map!((p)=>(p.content)).array; }
							}
						}
					}
				}
				return []; 
			} 
			
			alias extractTokenStringParams 	= extractCodeColumnParams!"q{}",
			extractListParams 	= extractCodeColumnParams!"()",
			extractListTokenStringParams 	= extractCodeColumnParams!"()q{}"; 
			
		}
		
		void processNiceExpressionSingleRow(CodeRow row, NEB bt, CodeRow newParent, void delegate(NiceExpression) onSuccess)
		{
			if(
				!row.length.inRange(2, 16) 
				/+
					It's an optimization for the size range.  
					Must update and verify!!!
				+/
			) return; 
			
			bool TRY(Args...)(Args args)
			{
				//try to add a NiceExpression template.
				static if(is(Unqual!(Args[0])==int))
				{
					if(args[0]) {
						newParent.enforce("newParent can't be null"); 
						onSuccess(NiceExpression.create(newParent, args[0], args[1..$])); 
						return true; 
					}
					return false; 
				}
				else
				{ return TRY(findNiceExpressionTemplateIdx(args[0], args[1], args[2]), args[3..$]); }
			} 
			
			void processOpList(string op, CodeColumn content)
			{
				if(TRY(bt, (mixin(舉!((NiceExpressionPattern),q{unaryOp}))) /+Note: op(expr)+/, op, content)) return; 
				
				bool doit(NEP ptn, alias exractor, int len)()
				{
					if(const tIdx = findNiceExpressionTemplateIdx(bt, ptn, op))
					{
						auto params = exractor(content); 
						if(params.length==len && TRY(tIdx, params[0], params[1], params.get(2)))
						return true; 
					}
					return false; 
				} 
				
				if(doit!(mixin(舉!((NiceExpressionPattern),q{binaryTokenStringOp})), extractTokenStringParams   , 2 /+Note: op(q{},q{})+/       )) return; 
				if(doit!(mixin(舉!((NiceExpressionPattern),q{tenaryTokenStringOp})), extractTokenStringParams   , 3 /+Note: op(q{},q{},q{})+/    )) return; 
				if(doit!(mixin(舉!((NiceExpressionPattern),q{twoParamOp}))       , extractListParams          , 2 /+Note: op(expr,expr)+/    )) return; 
				if(doit!(mixin(舉!((NiceExpressionPattern),q{threeParamOp}))      , extractListParams          , 3 /+Note: op(expr,expr,expr)+/)) return; 
				if(doit!(mixin(舉!((NiceExpressionPattern),q{twoParamEQOp}))     , extractListTokenStringParams, 2 /+Note: op(expr,q{})+/     )) return; 
				if(doit!(mixin(舉!((NiceExpressionPattern),q{threeParamEQEOp}))   , extractListTokenStringParams, 3 /+Note: op(expr,q{},expr)+/ )) return; 
			} 
			
			void processListOpList(string op, CodeColumn leftContent, CodeColumn rightContent)
			{
				if(TRY(bt, mixin(舉!((NiceExpressionPattern),q{binaryOp})) /+Note: (expr)op(expr)+/, op, leftContent, rightContent)) return; 
				if(const tIdx = findNiceExpressionTemplateIdx(bt, (mixin(舉!((NiceExpressionPattern),q{tenaryOp}))) /+Note: (expr)op(expr)op(expr)+/, op))
				{
					const mIdx = op.countUntil('￼'); 
					if(mIdx>=0)
					{
						if(auto middle = asListBlock(row.subCells.get(mIdx + 1/+0th is left operand+/)))
						{ if(TRY(tIdx, leftContent, middle.content, rightContent)) return; }
					}
				}
				if(row.length==3 && leftContent.empty && rightContent.empty)
				if(auto mid = asStatementBlockDeclaration(row.subCells[1]))
				if(mid.block)
				if(auto with_ = (cast(Declaration)(mid.block.singleCellOrNull)))
				if(with_.isPreposition && with_.keyword=="with" && with_.header && with_.block)
				if(with_.header.rowCount==1)
				{
					auto headerRow = with_.header.rows[0]; 
					if(headerRow.subCells.length.inRange(2, 16))
					if(auto expr1 = asListBlock(headerRow.subCells.back))
					if(expr1.content)
					{
						const innerOp = headerRow.chars[0..$-1].text; 
						if(
							TRY(
								bt, (mixin(舉!((NiceExpressionPattern),q{mixinTableInjectorOp}))) /+Note: (){with(op(expr)){expr}}()+/, 
								innerOp, expr1.content, with_.block
							)
						) return; 
					}
				}
			} 
			
			if(auto right = asListBlock(row.subCells.back))
			{
				if(auto left = asListBlock(row.subCells.front))
				{
					const op = row.chars[1..$-1].text; 
					if(left.content && right.content)
					{ processListOpList(op, left.content, right.content); }
				}
				else
				{
					const op = row.chars[0..$-1].text; 
					if(op.endsWith('￼'))
					{
						if(auto mid = asListBlock(row.subCells.get(row.subCells.length-2)))
						{ { if(TRY(bt, (mixin(舉!((NiceExpressionPattern),q{castOp}))) /+Note: op(expr)(expr)+/, op.withoutEnding('￼'), mid.content, right.content)) return; }}
					}
					else
					{ processOpList(op, right.content); }
				}
			}
			else if(auto right = asTokenStringBlock(row.subCells.back))
			{
				if(auto left = asListBlock(row.subCells.front))
				{
					{
						const op = row.chars[1..$-1].text; //Example: op = .genericArg!`
						if(TRY(bt, (mixin(舉!((NiceExpressionPattern),q{namedUnaryOp}))) /+Note: (expr)op q{code}+/, op, left.content, right.content)) return; 
					}
				}
			}
			else if(auto rightContent = asStatementBlockContents(row.subCells.back))
			{
				if(auto left = asListBlock(row.subCells.front))
				if(left.content)
				{
					const op = row.chars[1..$-1].text; //No attributes handled here.
					{ if(TRY(bt, (mixin(舉!((NiceExpressionPattern),q{anonymMethod}))) /+Note: (expr)op{code}+/, op, left.content, rightContent)) return; }
				}
			}
		} 
		
		version(/+$DIDE_REGION+/all) {
			void processNiceExpressionBlock(ref Cell outerCell) /+Note: This is called on each expressiob block. /+Code: (expr)+/+/
			{
				if(auto blk = (cast(CodeBlock)(outerCell)))
				if(blk.content && blk.content.rowCount==1)
				{
					//Todo: Double _ could be a subText. Example: dir__start
					//Todo: ((.1).mul(second))   nice scientific measurement unit display: .1 s
					
					processNiceExpressionSingleRow(
						blk.content.rows[0], ((blk.type==CodeBlock.Type.stringMixin) ?(NEB.stringMixin):(NEB.list)), 
						(cast(CodeRow)(blk.parent)), ((ne){ outerCell = ne; })
					); 
				}
			} 
			
			void processNiceTemplateMixinStatement(Declaration decl) /+Note: This is called on each /+Code: mixin Template;+/ statement.+/
			{
				if(decl.isStatement && decl.keyword=="mixin")
				if(decl.header && decl.header.rowCount==1)
				{
					auto row = decl.header.rows[0]; 
					processNiceExpressionSingleRow(
						row, NEB.templateMixin,
						row, ((ne){
							decl.keyword = ""; //Not a mixin anymore
							with(row) { subCells = [ne]; refreshTabIdx; needMeasure; }
						})
					); 
				}
			} 
			
			void processNiceStatementRow(CodeRow statementRow)
			{
				assert(statementRow); 
				
				void ADD(Args...)(int tIdx, Args args)
				{
					with(statementRow)
					{ clearSubCells; appendCell(NiceExpression.create(statementRow, tIdx, args)); needMeasure; }
				} 
				bool TRY(Args...)(NiceExpressionPattern pattern, string op, Args args)
				{
					if(const tIdx = findNiceExpressionTemplateIdx(NEB.specialStatement, pattern, op))
					{ ADD(tIdx, args); return true; }
					return false; 
				} 
				
				if(statementRow.subCells.empty) return; 
				const lastCh = statementRow.chars.back; 
				if(lastCh>=lowestSpecialUnicodeChar && lastCh!='￼')
				{
					const op = statementRow.chars.text; 
					{ if(TRY((mixin(舉!((NiceExpressionPattern),q{specialStatementOp}))) /+Note: op  //last char is special unicode+/, op)) return; }
				}
			} 
		}
		
		
		
		mixin 入 !((
			(表([
				[q{/+Note: Name+/},q{/+Note: Example+/},q{/+Note: Pattern+/},q{/+Note: op+/},q{/+Note: Style+/},q{/+Note: Syntax+/},q{/+Note: Class+/},q{/+Note: Scripts @init: @text @node @draw @ui+/}],
				[q{null_},q{},q{/+Code:+/},q{""},q{dim},q{Whitespace},q{NiceExpression},q{}],
				[q{magnitude},q{(magnitude(a))},q{/+Code: (op(expr))+/},q{"magnitude"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('|'); op(0); put('|'); }],
				[q{normalize},q{(normalize(a))},q{/+Code: (op(expr))+/},q{"normalize"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('‖'); op(0); put('‖'); }],
				[q{float_},q{(float(a))},q{/+Code: (op(expr))+/},q{"float"},q{bright},q{Number},q{NiceExpression},q{@text: put(operator); op(0); @node: op(0); setSubscript; put("F"); }],
				[q{double_},q{(double(a))},q{/+Code: (op(expr))+/},q{"double"},q{bright},q{Number},q{NiceExpression},q{@text: put(operator); op(0); @node: op(0); setSubscript; put("D"); }],
				[q{real_},q{(real(a))},q{/+Code: (op(expr))+/},q{"real"},q{bright},q{Number},q{NiceExpression},q{@text: put(operator); op(0); @node: op(0); setSubscript; put("real"); }],
				[q{RGB},q{(RGB(64, 128, 255))},q{/+Code: (op(expr))+/},q{"RGB"},q{dim},q{BasicType},q{ColorNode},q{}],
				[q{RGBA},q{(RGBA(0xFF8040AA))},q{/+Code: (op(expr))+/},q{"RGBA"},q{dim},q{BasicType},q{ColorNode},q{}],
				[q{floor},q{(floor(a))},q{/+Code: (op(expr))+/},q{"floor"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎣'); op(0); put('⎦'); }],
				[q{ceil},q{(ceil(a))},q{/+Code: (op(expr))+/},q{"ceil"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎡'); op(0); put('⎤'); }],
				[q{round},q{(round(a))},q{/+Code: (op(expr))+/},q{"round"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⁅'); op(0); put('⁆'); }],
				[q{trunc},q{(trunc(a))},q{/+Code: (op(expr))+/},q{"trunc"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎡'); op(0); put('⎦'); }],
				[q{ifloor},q{(ifloor(a))},q{/+Code: (op(expr))+/},q{"ifloor"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎣'); op(0); put('⎦'); putTypeSubscript("int"); }],
				[q{iceil},q{(iceil(a))},q{/+Code: (op(expr))+/},q{"iceil"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎡'); op(0); put('⎤'); putTypeSubscript("int"); }],
				[q{iround},q{(iround(a))},q{/+Code: (op(expr))+/},q{"iround"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⁅'); op(0); put('⁆'); putTypeSubscript("int"); }],
				[q{itrunc},q{(itrunc(a))},q{/+Code: (op(expr))+/},q{"itrunc"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎡'); op(0); put('⎦'); putTypeSubscript("int"); }],
				[q{lfloor},q{(lfloor(a))},q{/+Code: (op(expr))+/},q{"lfloor"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎣'); op(0); put('⎦'); putTypeSubscript("long"); }],
				[q{lceil},q{(lceil(a))},q{/+Code: (op(expr))+/},q{"lceil"},q{dim},q{Symbol},q{NiceExpression},q{@text: put(operator); op(0); @node: put('⎡'); op(0); put('⎤'); putTypeSubscript("long"); }],
				[q{lround},q{(lround(a))},q{/+Code: (op(expr))+/},q{"lround"},q{dim},q{Symbol},q{NiceExpression},q{
					@text: 	put(operator); op(0); 
					@node: 	{
						put('⁅'); op(0); put('⁆'); putTypeSubscript("long"); 
						super.rearrange; stretchGlyphs(0, 2); 
					}
				}],
				[q{ltrunc},q{(ltrunc(a))},q{/+Code: (op(expr))+/},q{"ltrunc"},q{dim},q{Symbol},q{NiceExpression},q{
					@text: 	put(operator); op(0); 
					@node: 	{
						put('⎡'); op(0); put('⎦'); putTypeSubscript("long"); 
						super.rearrange; stretchGlyphs(0, 2); 
					}
				}],
				[q{divide},q{((a)/(b))},q{/+Code: ((expr)op(expr))+/},q{"/"},q{dim},q{Symbol},q{NiceExpression},q{
					@text: 	op(0); put(operator); op(1); 
					@node: 	{
						op(0); putNL; op(1); super.rearrange; 
						foreach(o; operands[0..2]) o.outerPos.x += (innerWidth - o.outerWidth)/2; 
						const h = 2; operands[1].outerPos.y += h; outerHeight += h; 
					}
					@draw: 	{
						setupLine; 
						hLine(innerPos.x, innerPos.y + operands[1].outerPos.y - 1, innerPos.x + innerWidth); 
					}
				}],
				[q{power},q{((a)^^(b))},q{/+Code: ((expr)op(expr))+/},q{"^^"},q{dim},q{Symbol},q{NiceExpression},q{@text: op(0); put(operator); op(1); @node: arrangeRootPower; }],
				[q{root},q{((a).root(b))},q{/+Code: ((expr)op(expr))+/},q{".root"},q{dim},q{Symbol},q{NiceExpression},q{@text: op(0); put(operator); op(1); @node: arrangeRootPower(Yes.leftRightSwap); @draw: drawRoot; }],
				[q{sqrt},q{(sqrt(a))},q{/+Code: (op(expr))+/},q{"sqrt"},q{dim},q{Symbol},q{NiceExpression},q{
					@text: 	put(operator); op(0); 
					@node: 	{
						op(0); super.rearrange; 
						const adjust = vec2(
							4/+width if the root symbol+/, 
							2/+Height of the horizontal root line+/
						); 
						operands[0].outerPos += adjust; outerSize += adjust; 
					}
					@draw: 	drawRoot; 
				}],
				[q{mul},q{((a)*(b))},q{/+Code: ((expr)op(expr))+/},q{"*"},q{dim},q{Symbol},q{NiceExpression},q{@text: op(0); put(operator); op(1); @node: op(0); op(1); }],
				[q{mul3},q{((a)*(b)*(c))},q{/+Code: ((expr)op(expr)op(expr))+/},q{"*￼*"},q{dim},q{Symbol},q{NiceExpression},q{@text: op(0); put('*'); op(1); put('*'); op(2); @node: op(0); op(1); op(2); }],
				[q{dot},q{((a).dot(b))},q{/+Code: ((expr)op(expr))+/},q{".dot"},q{dim},q{Symbol},q{NiceExpression},q{@text: op(0); put(operator); op(1); @node: op(0); put('\u22C5'); op(1); }],
				[q{cross},q{((a).cross(b))},q{/+Code: ((expr)op(expr))+/},q{".cross"},q{dim},q{Symbol},q{NiceExpression},q{@text: op(0); put(operator); op(1); @node: op(0); put('\u2A2F'); op(1); }],
				[],
				[q{tenary_0},q{((a)?(b):(c))},q{/+Code: ((expr)op(expr)op(expr))+/},q{"?￼:"},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put('?'); op(1); put(':'); op(2); 
					@node: put(' '); op(0); put(" ? "); op(1); put(" : "); op(2); put(' '); 
				}],
				[q{tenary_1},q{((a) ?(b):(c))},q{/+Code: ((expr)op(expr)op(expr))+/},q{" ?￼:"},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put(" ?"); op(1); put(':'); op(2); 
					@node: 	put(' '); op(0); 	put(' '); putNL; 
						put(" ? "); op(1); put(" : "); op(2); 	put(' '); 
				}],
				[q{tenary_2},q{((a)?(b) :(c))},q{/+Code: ((expr)op(expr)op(expr))+/},q{"?￼ :"},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put('?'); op(1); put(" :"); op(2); 
					@node: 	put(' '); op(0); 	put("\t?\t"); 	op(1); put(' '); putNL; 
						put(' '); 	put("\t:\t"); 	op(2); put(' '); 
						super.rearrange; /+Todo: align the condition centered+/
				}],
				[q{tenary_2b},q{((a)?(b) : (c))},q{/+Code: ((expr)op(expr)op(expr))+/},q{"?￼ : "},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put('?'); op(1); put(" : "); op(2); 
					@node: 	put(' '); op(0); put(" ? "); op(1); put(' '); putNL; 
						put(" : "); op(2); put(' '); 
				}],
				[q{tenary_3},q{((a) ?(b) :(c))},q{/+Code: ((expr)op(expr)op(expr))+/},q{" ?￼ :"},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put(" ?"); op(1); put(" :"); op(2); 
					@node: 	put(' '); op(0); 		put(' '); putNL; 
						put(" ?\t"); 	op(1); 	put(' '); putNL; 
						put(" :\t"); 	op(2); 	put(' '); 
				}],
				[q{lambda_0},q{((a)=>(a+1))},q{/+Code: ((expr)op(expr))+/},q{"=>"},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put("=>"); op(1); @node: op(0); put('⇒'); op(1); 
					/+Todo: This is a very repetitive pattern: .filter!((a)=>(a.file.extIs("d", "di")))  put the .filter into the third operand!+/
				}],
				[q{lambda_1},q{((a) =>(a+1))},q{/+Code: ((expr)op(expr))+/},q{" =>"},q{bright},q{Symbol},q{NiceExpression},q{@text: op(0); put(" =>"); op(1); @node: op(0); putNL; put('⇒'); op(1); }],
				[q{anonymMethod_0},q{((){}) ((a){ a; })},q{/+Code: ((expr)op{code})+/},q{""},q{bright},q{Symbol},q{NiceExpression},q{@text: op(0); put("{", operands[1], "}"); @node: op(0); put("{", operands[1], "}"); }],
				[q{anonymMethod_1},q{
					(() {}) ((x) {
						a; 
						b; 
					})
				},q{/+Code: ((expr)op{code})+/},q{" "},q{bright},q{Symbol},q{NiceExpression},q{
					@text: op(0); put(" "); put("{", operands[1], "}"); 
					@node: op(0); putNL; put("{", operands[1], "}"); 
				}],
				[q{tenary_eq_eq},q{mixin(等(q{a},q{b},q{c}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"等"},q{bright},q{Symbol},q{NiceExpression},q{@text: buildTenaryRelation; @node: arrangeTenaryRelation('=', '='); }],
				[q{tenary_g_g},q{mixin(界0(q{a},q{b},q{c}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"界0"},q{bright},q{Symbol},q{NiceExpression},q{@text: buildTenaryRelation; @node: arrangeTenaryRelation('<', '<'); }],
				[q{tenary_ge_g},q{mixin(界1(q{a},q{b},q{c}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"界1"},q{bright},q{Symbol},q{NiceExpression},q{@text: buildTenaryRelation; @node: arrangeTenaryRelation('≤', '<'); }],
				[q{tenary_g_ge},q{mixin(界2(q{a},q{b},q{c}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"界2"},q{bright},q{Symbol},q{NiceExpression},q{@text: buildTenaryRelation; @node: arrangeTenaryRelation('<', '≤'); }],
				[q{tenary_ge_ge},q{mixin(界3(q{a},q{b},q{c}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"界3"},q{bright},q{Symbol},q{NiceExpression},q{@text: buildTenaryRelation; @node: arrangeTenaryRelation('≤', '≤'); }],
				[q{index},q{mixin(指(q{a},q{2}))},q{/+Code: mixin(op(q{},q{}))+/},q{"指"},q{dim},q{Symbol},q{NiceExpression},q{
					@text: 	put(operator); put('('); 
							put("q{", operands[0], "}"); put(','); 		put("q{", operands[1], "}"); 
						put(')'); 
					@node: arrangeSubscript; 
				}],
				[q{tupleAssign},q{mixin(配(q{x,y},q{=},q{y,x}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"配"},q{normal},q{Identifier1},q{NiceExpression},q{
					@text: 	{
						put(operator); put("("); 
							foreach(i, o; operands[0..3])
						{ if(i) put(','); put("q{", o, "}"); }
						put(")"); 
					}
					@node: 	{
						operands[1].fillColor(syntaxFontColor(skSymbol), bkColor); 
						operands[1].border.width=0; 
						operands[1].padding = Padding.init; 
						operands[1].margin = Margin.init; 
						
						foreach(o; operands) put(o); 
					}
				}],
				[q{genericArg},q{((value).genericArg!q{name})},q{/+Code: ((expr)opq{code})+/},q{".genericArg!"},q{bright},q{Identifier1},q{NiceExpression},q{
					@text: 	op(0); put(operator); put("q{"); put(opAsIdentifier(1)); put('}'); 
					@node: 	operands[1].fillColor(darkColor, bkColor); 
						put(operands[1]); put(':'); put(operands[0]); 
						/+Todo: Use chinese symbol for genericArg!+/
				}],
				[],
				[q{cast_0},q{(cast(Type)(expr))},q{/+Code: (op(expr)(expr))+/},q{"cast"},q{bright},q{Attribute},q{NiceExpression},q{@text: put("cast"); op(0); op(1); @node: op(1); put(0 ? ".cast" : "↦"); op(0); }],
				[q{cast_1},q{(cast (Type)(expr))},q{/+Code: (op(expr)(expr))+/},q{"cast "},q{bright},q{Attribute},q{NiceExpression},q{
					@text: 	put("cast "); op(0); op(1); 
					@node: 	{
						op(1); 
						putNL; flags.hAlign = HAlign.right; 
						put(0 ? ".cast" : "↦"); op(0); 
						super.rearrange; 
						subCells[0].outerPos.x = 0; 
					}
				}],
				[q{mixinStruct},q{(mixin(體!((Type),q{field: value, ...})))},q{/+Code: mixin(op((expr),q{}))+/},q{"體!"},q{bright},q{Identifier1},q{MixinNode},q{@node: customRearrange(builder, structuredColor("struct"), "{", "}"); }],
				[q{mixinEnum},q{(mixin(舉!((Enum),q{member})))},q{/+Code: mixin(op((expr),q{}))+/},q{"舉!"},q{bright},q{Identifier1},q{MixinNode},q{@node: customRearrange(builder, structuredColor("enum"), ".", ""); }],
				[q{mixinFlags},q{(mixin(幟!((Enum),q{member1 | ...})))},q{/+Code: mixin(op((expr),q{}))+/},q{"幟!"},q{bright},q{Identifier1},q{MixinNode},q{@node: customRearrange(builder, structuredColor("enum"), "(", ")"); }],
				[q{mixinTable1},q{
					(表([
						[q{/+Note: Hdr+/}],
						[q{Cell}],
					])); 
				},q{/+Code: (op(expr))+/},q{"表"},q{bright},q{Identifier1},q{MixinTable},q{
					@init: 	doubleGridStyle 	= 1,
					gridStyle 	= 1; /+
						gridStyle: 	0 simple grid
							1 +darker background
							2 double line grid
					+/
				}],
				[q{mixinTable2},q{((){with(表([[q{/+Note: Hdr+/},q{Cell}],])){ return scr; }}())},q{/+Code: ((){with(op(expr)){expr}}())+/},q{"表"},q{bright},q{Identifier1},q{MixinTable},q{
					@init: 	doubleGridStyle 	= 1,
					gridStyle 	= 1; 
				}],
				[],
				[q{stringMixin1},q{mixin((expr).GEN!q{scr}); },q{/+Code: mixin((expr)opq{code})+/},q{".GEN!"},q{normal},q{Symbol},q{MixinGenerator},q{}],
				[q{stringMixin2},q{mixin((expr) .GEN!q{scr}); },q{/+Code: mixin((expr)opq{code})+/},q{" .GEN!"},q{normal},q{Symbol},q{MixinGenerator},q{@init: isMultiLine = true; }],
				[q{stringMixin3},q{mixin((expr).調!(fun, args...)); },q{/+Code: mixin((expr)op(expr))+/},q{".調!"},q{normal},q{Symbol},q{MixinGenerator},q{@init: isFunctionCall = true; }],
				[],
				[q{templateMixin1},q{mixin 入!((expr),q{scr}); },q{/+Code: mixin op((expr),q{})+/},q{"入!"},q{bright},q{Symbol},q{MixinGenerator},q{@init: isTemplate = true; }],
				[q{templateMixin2},q{mixin 入 !((expr),q{scr}); },q{/+Code: mixin op((expr),q{})+/},q{"入 !"},q{bright},q{Symbol},q{MixinGenerator},q{@init: isTemplate = true; isMultiLine = true; }],
				[],
				[q{iteration_map},q{mixin(求map(q{i=0},q{N-1},q{expr}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"求map"},q{dim},q{Symbol},q{SigmaOp},q{@init: symbol = '⇶'; }],
				[q{iteration_eachExpr},q{mixin(求each(q{i=0},q{N-1},q{expr})); },q{/+Code: mixin(op(q{},q{},q{}))+/},q{"求each"},q{dim},q{Symbol},q{SigmaOp},q{@init: symbol = '∀'; }],
				[q{iteration_sum},q{mixin(求sum(q{i},q{1, 2, 3},q{expr}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"求sum"},q{dim},q{Symbol},q{SigmaOp},q{@init: symbol = '∑'; }],
				[q{iteration_product},q{mixin(求product(q{i=0},q{N-1},q{expr}))},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"求product"},q{dim},q{Symbol},q{SigmaOp},q{@init: symbol = '∏'; }],
				[q{perf_start},q{auto _間=init間; },q{/+Code: specialStatement+/},q{"auto _間=init間"},q{bright},q{BasicType},q{NiceExpression},q{
					@text: 	put(operator); 
					@node: 	style.bold = false; put("⏱.init"); 
				}],
				[q{perf_measure},q{
					(update間(_間)); 
					/+
						Todo: ⏱.max, ⏱.avg
						⏱.sum,
						⏱.perc(1)
					+/
				},q{/+Code: (op(expr))+/},q{"update間"},q{bright},q{BasicType},q{NiceExpression},q{
					@text: 	put(operator); put("(_間)"); 
					@node: 	style.bold = false; put("⏱"); 
				}],
				[q{inspect1},q{((0x7FABD091A191).檢(expr))},q{/+Code: ((expr)op(expr))+/},q{".檢"},q{dim},q{Identifier1},q{Inspector},q{}],
				[q{inspect2},q{((0x802ED091A191).檢 (expr))},q{/+Code: ((expr)op(expr))+/},q{".檢 "},q{dim},q{Identifier1},q{Inspector},q{}],
				[q{constValue},q{
					(常!(bool)(0))(常!(bool)(1))
					(常!(float/+w=6+/)(0.300))
				},q{/+Code: (op(expr)(expr))+/},q{"常!"},q{dim},q{Identifier1},q{InteractiveValue},q{
					@text: 	const 	ctwc 	= controlTypeWithComment,
						cvt	= controlValueText; 
						put(iq{$(operator)($(ctwc))($(cvt))}.text); 
					@node: 	customRearrange(builder, false); 
					@ui: 	interactiveUI(false, enabled_, targetSurface_); 
				}],
				[q{interactiveValue},q{
					(互!((bool),(0),(0x827BD091A191)))(互!((bool),(1),(0x829ED091A191)))(互!((bool/+btnEvent=1 h=1 btnCaption=Btn+/),(0),(0x82C1D091A191)))
					(互!((float/+w=6+/),(1.000),(0x830CD091A191)))
				},q{/+Code: (op((expr),(expr),(expr)))+/},q{"互!"},q{dim},q{Interact},q{InteractiveValue},q{
					@text: 	const 	ctwc 	= controlTypeWithComment,
						cvt	= controlValueText,
						id	= generateIdStr(result.length); 
						put(iq{$(operator)(($(ctwc)),($(cvt)),($(id)))}.text); 
					@node: 	customRearrange(builder, false); 
					@ui: 	interactiveUI(!!dbgsrv.exe_pid, enabled_, targetSurface_); 
				}],
				[q{synchedValue},q{
					mixin(同!(q{bool/+hideExpr=1+/},q{select},q{0x8502D091A191}))mixin(同!(q{int/+w=2 h=1 min=0 max=2 hideExpr=1 rulerSides=1 rulerDiv0=3+/},q{select},q{0x8540D091A191}))
					mixin(同!(q{float/+w=3 h=2.5 min=0 max=1 newLine=1 sameBk=1 rulerSides=1 rulerDiv0=11+/},q{level},q{0x85B1D091A191}))
					mixin(同!(q{float/+w=1.5 h=6.6 min=0 max=1 newLine=1 sameBk=1 rulerSides=3 rulerDiv0=11+/},q{level},q{0x862FD091A191}))
				},q{/+Code: mixin(op(q{},q{},q{}))+/},q{"同!"},q{dim},q{Interact},q{InteractiveValue},q{
					@text: 	static ts(string s) => "q{"~s~'}'; 
						const 	ctwc	= ts(controlTypeWithComment),
						op1src 	= ts(operands[1].sourceText),
						id	= ts(generateIdStr(result.length)); 
						put(iq{$(operator)($(ctwc),$(op1src),$(id))}.text); 
					@node: 	customRearrange(builder, true); 
					@ui: 	interactiveUI(!!dbgsrv.exe_pid, enabled_, targetSurface_); 
				}],
			]))
		),q{
			static if((常!(bool)(1))/+Note: fast way+/) {
				mixin(iq{enum NiceExpressionTemplateEnum : ubyte {$(_data.rows.map!"a[0]".join(','))} }.text); 
				static immutable niceExpressionTemplates = _data.rows.map!makeNiceExpressionTemplate.array; /+Note: <- ✔ This is the preferable way!+/
			}else {
				mixin(
					iq{
						enum NiceExpressionTemplateEnum : ubyte {$(_data.rows.map!"a[0]".join(','))} 
						static immutable niceExpressionTemplates = $(_data.text/+Note: <- ❌ Extremely slow text conversion.+/).rows.map!makeNiceExpressionTemplate.array; 
					}.text
				); 
			}
		}); 
		static assert(niceExpressionTemplates[0].name=="null_"); /+Todo: Enum legyen a templateIdx!+/
		
		
		class ToolPalette : Module
		{
			Page[] pages = /+Todo: Indentation is a problem here.  Ineffective and for multiline strings it's unreliable.+/ /+/+Link: https://en.wikipedia.org/wiki/Greek_letters_used_in_mathematics,_science,_and_engineering+/+/
			[
				{
					"Symbols, math", "α",
					q{
						(表([
							[q{"expression blocks"},q{
								lbl: 	st; 	{blk}	(ex)	[idx] 
								"s"	`s`	q{s}	r"s"	'\0'
								i"s"	i`s`	iq{s}	$(a)	x"00"
								mixin() __traits() pragma()
								
							}],
							[q{"spec. statements"},q{
								return; 	return x; 
								break; 	break lb; 
								continue; 	continue lb; 
								goto case; 	goto case lb; 
								goto lb; 	static assert(); 
								assert(a); 	enforce(a); 
							}],
							[q{"math letters"},q{π ℯ ℂ α β γ µ σ Δ δ ϕ ϑ ε ω}],
							[q{"symbols"},q{"° ℃ ± ∞ ↔ → ∈ ∉"}],
							[q{"float, double, real"},q{(float(x)) (double(x)) (real(x))}],
							[q{"floor, 
ceil, 
round, 
trunc"},q{
								(floor(x)) (ifloor(x)) (lfloor(x))
								(ceil(x)) (iceil(x)) (lceil(x))
								(round(x)) (iround(x)) (lround(x))
								(trunc(x)) (itrunc(x)) (ltrunc(x))
							}],
							[q{"abs, normalize"},q{(magnitude(a)) (normalize(a))}],
							[q{"multiply,
dot, cross"},q{((a)*(b)) ((a)*(b)*(c)) ((a).dot(b)) ((a).cross(b))}],
							[q{"divide, sqrt, root, 
power, index"},q{((a)/(b)) (sqrt(a)) ((a).root(b)) ((a)^^(b)) mixin(指(q{a},q{b}))}],
							[q{"tenary relation"},q{
								mixin(等(q{a},q{b},q{c}))
								mixin(界0(q{a},q{b},q{c})) mixin(界1(q{a},q{b},q{c}))
								mixin(界2(q{a},q{b},q{c})) mixin(界3(q{a},q{b},q{c}))
							}],
							[q{"color literals"},q{(RGB()) (RGBA())}],
						]))
					}
				},
				{
					"Expressions", "(1)", 
					q{
						(表([
							[q{"tenary operator"},q{
								((a)?(b):(c))	((a)?(b) :(c)) 
								((a) ?(b):(c)) ((a)?(b) : (c)) ((a) ?(b) :(c))
							}],
							[q{"lambda, 
anonym method"},q{
								((a)=>(a+1)) 	((a){ f; })
								((a) =>(a+1))	((a) { f; })
							}],
							[q{"tuple operation"},q{mixin(配(q{x,y},q{=},q{y,x}))}],
							[q{"named param, 
struct initializer"},q{((value).genericArg!q{name}) mixin(體!((Type),q{name: val, ...}))}],
							[q{"enum member 
blocks"},q{mixin(舉!((Enum),q{member})) mixin(幟!((Enum),q{member | ...}))}],
							[q{"cast operator"},q{(cast(Type)(expr)) (cast (Type)(expr))}],
							[q{"debug inspector"},q{((0x9510D091A191).檢(expr)) ((0x952DD091A191).檢 (expr))}],
							[q{"stop watch"},q{auto _間=init間; ((0x957CD091A191).檢((update間(_間)))); }],
							[q{"interactive literals"},q{
								(常!(bool)(0)) (常!(bool)(1)) (常!(float/+w=6+/)(0.300))
								(互!((bool),(0),(0x961FD091A191))) (互!((bool),(1),(0x9643D091A191))) (互!((float/+w=6+/),(1.000),(0x9667D091A191)))
								mixin(同!(q{bool/+hideExpr=1+/},q{select},q{0x96A5D091A191})) mixin(同!(q{int/+w=2 h=1 min=0 max=2 hideExpr=1 rulerSides=1 rulerDiv0=3+/},q{select},q{0x96E4D091A191})) mixin(同!(q{float/+w=2.5 h=2.5 min=0 max=1 newLine=1 sameBk=1 rulerSides=1 rulerDiv0=11+/},q{level},q{0x974FD091A191}))
								mixin(同!(q{float/+w=6 h=1 min=0 max=1 sameBk=1 rulerSides=3 rulerDiv0=11+/},q{level},q{0x97D1D091A191}))
								/+Opt: Big perf. impact!!!+/
							}],
						]))
					}
				},
				{
					"Expressions", "(2)", 
					q{
						(表([
							[q{"table blocks"},q{
								(表([
									[q{/+Note: Hdr+/}],
									[q{Cell}],
								])) ((){with(表([[q{/+Note: Hdr+/},q{Cell}],])){ return script; }}())
							}],
							[q{"string mixins"},q{
								mixin((src) .GEN!q{script}); mixin((expr).調!(fun)); 
								mixin((src).GEN!q{script}); 
							}],
							[q{"template mixins"},q{
								mixin 入 !((src),q{script}); 
								mixin 入!((src),q{script}); 
							}],
							[q{`map`},q{mixin(求map(q{i=0},q{N},q{expr}))mixin(求map(q{0<i<N},q{},q{expr}))mixin(求map(q{i},q{1, 2, 3},q{expr}))}],
							[q{`sum`},q{mixin(求sum(q{i=0},q{N},q{expr}))mixin(求sum(q{0<i<N},q{},q{expr}))mixin(求sum(q{i},q{1, 2, 3},q{expr}))}],
							[q{`product`},q{mixin(求product(q{i=0},q{N},q{expr}))mixin(求product(q{0<i<N},q{},q{expr}))mixin(求product(q{i},q{1, 2, 3},q{expr}))}],
							[q{"each"},q{mixin(求each(q{i=0},q{N},q{f})); mixin(求each(q{0<i<N},q{},q{f})); mixin(求each(q{i},q{1, 2, 3},q{f})); }],
						]))
					}
				},
				{
					"Comments", "//",
					q{
						(表([
							[q{"comments"},q{
								/+cmt+/ 
								/*cmt*/ //cmt
								/+Note: note+/ /+Code: code+/ /+Hidden:+/
								/+Link: cmt+/ /+$DIDE_IMG+/
								/+Todo: cmt+/ 
								/+Opt: cmt+/ /+Bug: cmt+/
								/+Error: cmt+/ 
								/+Exception: cmt+/ 
								/+Warning: cmt+/ 
								/+Deprecation: cmt+/
								/+Console: cmt+/
								//$DIDE_LOC file.d(1,2)
							}],
							[q{"regions"},q{
								version(/+$DIDE_REGION RGN+/all)
								{ s; }version(/+$DIDE_REGION RGN+/none)
								{ s; }
								version(/+$DIDE_REGION RGN+/all) { s; }version(/+$DIDE_REGION+/all) { s; }
								version(/+$DIDE_REGION RGN+/none) { s; }version(/+$DIDE_REGION+/none) { s; }
							}],
							[q{"directives"},q{
								#
								#!
								#line 5
								#define
								#ifdef
								#else
								s; 
							}],
							[q{"ai"},q{
								/+AI:+/	/+System:+/
								/+User:+/	/+Assistant:+/
							}],
						]))
					}
				},
				{
					"Blocks", "{ }",
					q{
						(表([[q{`declaration blocks`},q{
							s; 	auto f()
							{ s; } 
							auto f() => x; 	auto f()
							=> x; 
							import; 	alias id; 
							enum id; 	enum id
							{} 
							struct id
							{ s; } 	union id
							{ s; } 
							class id
							{ s; } 	interface id
							{ s; } 
							@(u)
							{ s; } 	private
							{ s; } 
							public
							{ s; } 	protected
							{ s; } 
							unittest
							{ s; } 	invariant
							{ s; } 
							template id
							{ s; } 	mixin T; 
							mixin template id
							{ s; } 	mixin(); 
						}],]))
					}
				},
				{
					"Statement blocks", "RT",
					q{
						(表([
							[q{"if blocks"},q{
								if(c) { f; }
								if(c) { f; }else { g; }
								if(c)
								{}if(c)	{ f; }
								else	{ g; }
								if(c)	{ f; }
								else if(d)	{ g; }
								else	{ h; }
								else { f; }else
								{ f; }
							}],
							[q{"swicth case block"},q{
								switch(c)
								{
									case: 
									break; 
									default: 
								}
							}],
							[q{"with block"},q{
								with(a)
								{ f; }with(a) { f; }
							}],
							[q{"scope"},q{
								scope(exit)
								{ a; }
								scope(exit) { a; }
							}],
						]))
					}
				},
				{
					"Loops Exceptions", "LE",
					q{
						(表([
							[q{"while blocks"},q{
								while(a)
								{ f; }while(a) { f; }
							}],
							[q{"do while blocks"},q{
								do { f; }
								while(c); 
								do { f; }while(c); 
							}],
							[q{"for loops"},q{
								for(; ;)
								{ f; }for(; ;) { f; }
								foreach(;)
								{ f; }
								foreach(;) { f; }
								foreach_reverse(;)
								{ f; }
								foreach_reverse(;) { f; }
							}],
							[q{"try catch finally"},q{
								try
								{}
								catch(a)
								{}try
								{}
								finally
								{}
								try {}catch(a) {}
								try {}finally {}
							}],
						]))
					}
				},
				{
					"Compile time blocks", "CT",
					q{
						(表([
							[q{"static foreach"},q{
								static foreach(;)
								{ f; }
								static foreach(;) { f; }
								static foreach_reverse(;)
								{ f; }
								static foreach_reverse(;) { f; }
							}],
							[q{"static if blocks"},q{
								static if(c) { f; }
								static if(c) { f; }else { g; }
								static if(c)
								{ f; }static if(c)	{ f; }
								else	{ g; }
								static if(c)	{ f; }
								else static if(d)	{ g; }
								else static assert 0,; 
							}],
						]))
					}
				},
				{
					"Compile time blocks", "VD",
					q{
						(表([
							[q{"version blocks"},q{
								version(v) { f; }
								version(v) { f; }else { g; }
								version(v)
								{ f; }version(v)	{ f; }
								else	{ g; }
								version(v)	{ f; }
								else version(w)	{ g; }
								else	{ h; }
							}],
							[q{"debug blocks"},q{
								debug { f; }
								debug { f; }else { g; }
								debug
								{ f; }debug	{ f; }
								else	{ g; }
							}],
							[q{"debug blocks
	with condition"},q{
								debug(d) { f; }
								debug(d) { f; }else { g; }
								debug(d)
								{ f; }debug(d)	{ f; }
								else	{ g; }
								debug(d)	{ f; }
								else debug(e)	{ g; }
								else	{ h; }
								/+
									Todo: When the operand of 
									debug() becomes empty, 
									it disappears. 🤬
								+/
							}],
						]))
					}
				}
			]; 
			version(/+$DIDE_REGION+/all) {
				struct Page
				{
					string title, caption, source; 
					
					Module _module; 
					static struct Entry { Cell cell; string comment; } 
					Entry[] entries; 
					
					void initialize(Container parent)
					{
						_module = new Module(null, source, StructureLevel.managed); 
						if(_module)
						{
							if(auto mCol = _module.content)
							if(auto table = (cast(NiceExpression)(mCol.singleCellOrNull)))
							if(auto tCol = table.operands[0])
							foreach(tRow; tCol.rows)
							if(auto cntr1 = (cast(CodeContainer)(tRow.subCells.get(1))))
							{
								string comment; 
								if(auto cntr0 = (cast(CodeContainer)(tRow.subCells.get(0))))
								comment = cntr0.content.sourceText; 
								//Todo: implement ?. null coalescing NiceExpression from C#
								entries ~= Entry(cntr1, comment); 
								cntr1.setParent(parent); //from here worldPos() calculations work
								cntr1.measure; 
							}
						}
					} 
				} 
				
				string[] captions; 
				
				this()
				{
					super(null); 
					id = "$ToolPalette$"; 
					file = File(id); 
					
					
					mixin(求each(q{ref a},q{pages},q{a.initialize(this)})); captions = mixin(求map(q{ref a},q{pages},q{a.caption})).array; 
				} 
				Page* actPage, lastPage; //cached
				uint lastTick; 
				
				private enum enableDebug = false; 
				private void DBG(A...)(A a)
				{
					static if(enableDebug)
					im.Text(text(a)); 
				} 
				
				override void rearrange()
				{
					if(actPage)	subCells = actPage.entries.map!"a.cell".array; 
					else	subCells = []; 
					
					const maxW = subCells.map!"a.outerWidth".maxElement(0); 
					subCells.each!((a){ a.outerWidth = maxW; }); 
					subCells.spreadV; 
					innerSize = calcContentSize; 
					
					bkColor = syntaxBkColor(skWhitespace); 
				} 
				
				void UI(ref string actPageCaption)
				{
					im.BtnRow(actPageCaption, captions); 
					auto actPageIdx = pages.map!"a.caption".countUntil(actPageCaption); 
					if(actPageIdx<0 && pages.length) actPageIdx = 0; //select first page if anything...
					actPage = actPageIdx.inRange(pages) ? &pages[actPageIdx] : null; 
					
					if(lastPage.chkSet(actPage))
					{
						needMeasure; 
						/+Todo: Column aligning is totally fucked up...+/
					}
					
					measure; 
					
					im.Container(
						{
							im.actContainer.id = "$ToolPaletteContainer$"; 
							if(actPage) im.actContainer.appendCell(this); 
							this.UI_constantNodes(false, 1); 
						}
					); 
					
					detectMouseLocation; 
					detectTemplate; 
				} 
				CodeRow hoveredRow; //only for the glyph
				Cell hoveredCell; 
				CodeColumn innerCol; 
				
				@property hoveredGlyph()
				{ return (cast(Glyph)(hoveredCell)); } 
				@property hoveredNode()
				{ return (cast(CodeNode)(hoveredCell)); } 
				
				void detectMouseLocation()
				{
					hoveredRow=null; hoveredCell = null; innerCol =  null; 
					auto hs = hitTestManager.lastHitStack; 
					
					//Todo: Can't ssubstitute label in "goto label;"
					
					//print(hs.enumerate.map!(a=>(a.index.text~":"~a.value.id)).join("|")); 
					
					if(hs.length && hs.back.id.isWild("$ToolPaletteContainer$.*[NiceExpression(*)]"))
					{
						//interactive constantNode
						hoveredCell = (cast(NiceExpression)((cast(void*)(wild[1].to!ulong(16))))); 
					}
					else
					{
						const toolPaletteIdx = hs.map!"a.id".countUntil(this.id); 
						if(toolPaletteIdx>=0)
						{
							hs = hs[toolPaletteIdx..$]; 
							T idTo(T)(string id)
							{
								if(id.isWild(T.stringof~"(*)"))	return (cast(T)((cast(void*)(wild[0].to!ulong(16))))); 
								else	return null; 
							} 
							
							if(auto node = idTo!CodeNode(hs.get(4).id))
							{
								hoveredCell = node; 
								innerCol = idTo!CodeColumn(hs.get(5).id); 
							}
							else if(auto row = idTo!CodeRow(hs.get(3).id))
							if(auto glyph = (cast(Glyph)(row.subCellAtX(hs[3].localPos.x, Yes.snapToNearest))))
							if(!glyph.isWhite)
							{
								hoveredCell = glyph; 
								hoveredRow = row; 
							}
						}
					}
				} 
				
				string templateSource; 
				int subColumnIdx = -1; 
				
				void detectTemplate()
				{
					//Todo: support mixinStatement
					templateSource=""; subColumnIdx=-1; 
					if(hoveredNode)
					{
						auto src = hoveredNode.sourceText.strip; DBG(src); 
						auto subColumns = hoveredNode.subCells.map!((a)=>((cast(CodeColumn)(a)))).filter!"a".array; 
						foreach(idx, sc; subColumns)
						{
							string marker = ""; 
							if(
								sc is 
								innerCol
							) {
								subColumnIdx = (cast(int)(idx)); 
								marker = "\0"; 	//ASCII 0 is the market. It's nasty...
							}
							
							auto s = sc.sourceText; DBG(s); 
							
							if(s=="id")
							{
								//s has no brackets.
								src = src.replaceWords(s, marker); 
							}
							else
							{
								string t; 
								if(s=="i=0")	t = "="; 
								else if(s=="0<i<N")	t = "<<"; /+
									Todo: this is way too 
									Sigma specific
								+/
								
								t ~= marker; //copied text will go here
								
								foreach(q; [["(", ")"], ["q{", "}"], ["{ ", "}"], [" ", ";"]])
								src = src.replace(
									q[0]~s~q[1], 
									((q[0]=="{ ")?("{"):(q[0]))~t~q[1].strip
								); 
							}
						}
						templateSource = src; 
					}
					else if(hoveredGlyph)
					{ templateSource = hoveredGlyph.ch.text; }
					
					if(templateSource!="")
					{
						auto col(string s) { return het.ui.tag("style fontColor="~s); } 
						auto s = col("black")~templateSource.replace("\0", col("red")~"⌖"~col("black")); 
						im.Text(s); 
					}
				} 
				
				override void draw(Drawing dr)
				{
					super.draw(dr); 
					
					dr.color = mix(clAccent, clWhite, blink); 
					dr.lineWidth = -(4*blink+1); 
					
					if(hoveredNode)
					{
						dr.drawRect(hoveredNode.worldOuterBounds.inflated(2)); 
						if(innerCol)
						{ dr.drawRect(innerCol.worldOuterBounds.inflated(-2)); }
					}
					else if(hoveredGlyph)
					{
						const idx = hoveredRow.subCells.countUntil(hoveredCell); 
						if(idx>=0)
						{
							const bnd = hoveredGlyph.outerBounds + hoveredRow.worldInnerPos; 
							dr.drawRect(bnd.inflated(2)); 
						}
					}
				} 
				
				
			}
		} 
		
		
		
		
		
	}
	class NiceExpression : CodeNode
	{
		int templateIdx;  //Todo: 0 should mean invalid
		CodeColumn[3] operands; 
		
		version(/+$DIDE_REGION Controller / Interactive value+/all)
		{
			string controlType; 
			float controlValue; 
			
			ulong controlId; 
			int controlIndex=-1; 
			
			string controlPropsText; 
			InteractiveControlProps controlProps; 
			
			@property controlTypeWithComment() 
			=> controlType ~ 	((controlPropsText.empty)?(""):("/+"~controlPropsText~"+/")); 
			
			const @property controlValueText() 
			=> controlType.predSwitch	(
				"bool", 	((controlValue)?("1"):("0")),
				"float", 	controlValue.format!"%.3f",
					controlValue.text
			); 
		}
		
		//Todo: Nicexpressions should work inside (parameter) block too!
		
		const @property validTemplate()
		{ return templateIdx.inRange(niceExpressionTemplates); } 
		
		const ref getTemplate()
		{
			enforce(validTemplate); 
			return niceExpressionTemplates[templateIdx]; 
		} 
		
		@property syntax()
		{ return getTemplate.syntax; } 
		
		@property operator()
		{ return getTemplate.operator; } 
		
		@property operandCount()
		{ return niceExpressionPatternOpCnt[getTemplate.pattern]; } 
		
		@property templateName()
		{ return getTemplate.name; } 
		
		@property isProbe()
		{
			return templateName=="probe"; 
			/+Todo: Need a faster way to identify+/
		} 
		
		override @property RGB avgColor()
		{
			RGBSum sum; 
			foreach(col; operands)
			if(col) sum.add(col.avgColor, col.outerSize.area); 
			return sum.avg(bkColor); 
		} 
		
		this(
			Container parent, int templateIdx_, 
			CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
		)
		{
			super(parent); 
			
			templateIdx = templateIdx_; 
			enforce(validTemplate, "Invalid NiceExpressionTemplate idx."); 
			
			if(col0) lineIdx = col0.rows.front.lineIdx; 
			
			static foreach(i; 0..operands.length)
			{
				if(i<operandCount)
				{
					operands[i] = mixin("col" ~ i.text).enforce; 
					operands[i].setParent(this); 
				}
			}
			
			initialize; 
		} 
		
		static NiceExpression create(
			Container parent, int templateIdx_, 
			CodeColumn col0=null, CodeColumn col1 = null, 
			CodeColumn col2 = null
		)
		{
			//this constructor will create the appropriate class.
			enforce(templateIdx_.inRange(niceExpressionTemplates)); 
			
			final switch(niceExpressionTemplates[templateIdx_].customClass)
			{
				static foreach(n; EnumMemberNames!NEC)
				mixin(
					iq{
						case NEC.$(n): 
						return new $(n)(__traits(parameters)); 
					}.text
				); 
			}
			
		} 
		
		version(/+$DIDE_REGION BuildMessage handling+/all)
		{
			CodeColumn buildMessageColumn; 
			
			override CodeColumn* accessBuildMessageColumn()
			{ return &buildMessageColumn; } 
		}
		
		version(/+$DIDE_REGION DebugValue support+/all)
		{
			string debugValue; 
			DateTime prevDebugValueUpdatedTime, debugValueUpdatedTime, debugValueChangedTime; 
			//Todo: should be in another class... It's inspector exclusive.
			
			void updateDebugValue(string value)
			{
				prevDebugValueUpdatedTime = debugValueUpdatedTime; 
				debugValueUpdatedTime = application.tickTime; 
				if(debugValue.chkSet(value))
				{
					debugValueChangedTime = debugValueUpdatedTime; 
					needMeasure; 
				}
			} 
			
			float debugValueDiminisingIntensity()
			{
				//If the frequency of an event is too high, it's visualization will be less intense.
				const Δt = (float((debugValueUpdatedTime - prevDebugValueUpdatedTime).value(((2)*(second))))); 
				return ((Δt>=1)?(1):(max(sqrt(Δt), .1f))); 
			} 
		}
		
		static private string GEN_switch(string field)
		=> q{
			{
				sw: switch(templateIdx)
				{
					static foreach(a; niceExpressionTemplates.map!"a.$".enumerate)
					{
						case a.index: 
						with((cast(mixin(niceExpressionTemplates[a.index].customClass.text))(this)))
						{ mixin(a.value); }
						break sw; 
					}
					default: 
				}
			}
		}
		.replace("$", field); 
		
		final void initialize()
		{ mixin(("initCode").調!(GEN_switch)); } 
		
		final override void buildSourceText(ref SourceTextBuilder builder)
		{
			with(builder) {
				final switch(getTemplate.blockType)
				{
					case NEB.list: 	put('('); 	break; 
					case NEB.stringMixin,: 	putSeparatorSpace; put(`mixin(`); 	break; 
					case NEB.templateMixin: 	putSeparatorSpace; put(`mixin `); 	break; 
					case NEB.specialStatement: 		break; 
				}
				
				doBuildSourceText(builder); 
				
				final switch(getTemplate.blockType)
				{
					case 	NEB.list, 
						NEB.stringMixin: 	put(')'); 	break; 
					case 	NEB.specialStatement,
						NEB.templateMixin: 		break; 
				}
			}
		} 
		
		void doBuildSourceText(ref SourceTextBuilder builder)
		{
			with(builder)
			{
				void op(int i)
				{ put("(", operands[i], ")"); } 
				
				string opAsIdentifier(int i)
				{
					//Todo: some error checking would be better.
					return operands[i].shallowText.filter!isDLangIdentifierCont.text; 
				} 
				
				void buildTenaryRelation()
				{
					put(operator); put('('); 
					foreach(i; 0..3) { if(i) put(','); put("q{", operands[i], "}"); }
					put(')'); 
				} 
				
				//------------------------------------------------------------------------
				
				mixin(("textCode").調!(GEN_switch)); 
			}
		} 
		
		final override void rearrange()
		{
			const inverseMode = getTemplate.invertMode; 
			rearrangeNodeWasCalled = false; //this flag will be set inside CodeNode.rearrange()
			auto builder = nodeBuilder(syntax, inverseMode); 
			with(builder)
			{
				version(/+$DIDE_REGION initialize stuff+/all)
				{
					if(!inverseMode) style.bkColor = bkColor = mix(darkColor, halfColor, .3f); 
					
					//style.bold = syntax!=skSymbol; 
					//Todo: Create bold/darkening settings UI. It is now bold because all the text in the node surface is bold.
					
					foreach(o; operands[].filter!"a")	o.bkColor = darkColor; 
				}
				
				doRearrange(builder); 
				
				version(/+$DIDE_REGION finalize+/all)
				{
					if(!rearrangeNodeWasCalled)
					{
						//If super.rearrange() is not called in the plugins, this will call now.
						super.rearrange; 
					}
					
					rearrange_appendBuildMessages; 
				}
			}
		} 
		
		void doRearrange(ref CodeNodeBuilder builder)
		{
			with(builder)
			{
				version(/+$DIDE_REGION scripting helper functions+/all)
				{
					void op(int i)
					{ put(operands[i]); } 
				}
				
				//--------------------------- Custom helper functions -----------------------------------------------
				
				void arrangeRootPower(Flag!"leftRightSwap" leftRightSwap = No.leftRightSwap)
				{
					auto 	bigger 	= operands[0],
						smaller 	= operands[1]; auto 	left 	= bigger, 
						right 	= smaller; if(leftRightSwap) swap(left, right); 
					
					//Todo: SuperScript with style: smaller font. Maybe recursively smaller...
					static immutable 	superScriptShift	= 0.25f,
						superScriptOffset 	= round(DefaultFontHeight * superScriptShift); 
					
					/+
						Todo: HalfSize
						if(type==Type.power) smaller.applyHalfSize(style.fontColor, bkColor); 
						It's more complex: Needs to be resized recursively, also resize Nodes/Columns, not just Glyphs.
					+/
					
					smaller.applyHalfSize; 
					put(left); put(right); 
					super.rearrange;  /+
						Note: It's in the middle, called manually. 
						At the end int's automatic.
					+/
					
					bigger.outerPos.y = innerHeight - bigger.outerHeight; 
					smaller.outerPos.y = 0; 
					
					/+
						Make sure that the superscript is higher than the bigger part
						check the upper and the bigger edges too.
						Both of them should indicate that one of the two operands is in superscript position.
					+/
					foreach(i; 0..2) {
						auto getY(CodeColumn col)
						{ return i ? col.outerTop : col.outerBottom; } 
						const diff = getY(bigger) - getY(smaller); 
						if(diff < superScriptOffset)
						{
							const extra = superScriptOffset - diff; 
							bigger.outerPos.y += extra; 
							outerHeight += extra; 
						}
					}
				} 
				
				void arrangeSubscript()
				{
					operands[1].applyHalfSize; put(operands[0]); put(operands[1]); super.rearrange; 
					subCells.back.outerPos.y = innerHeight - subCells.back.outerHeight; 
					const extra =  DefaultFontHeight * .125f; 
					subCells.back.outerPos.y 	+= extra,
					outerSize.y 	+= extra; 
				} 
				
				void arrangeTenaryRelation(dchar op1, dchar op2)
				{
					void putOp(dchar op)
					{
						if(op=='=') { put('='); subCells.back.outerSize.x *= 1.815f; }
						else { put(' '); put(op); put(' '); }
					} 
					put(' '); op(0); putOp(op1); op(1); putOp(op2); op(2); put(' '); 
				} 
				
				///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
				
				mixin(("rearrangeCode").調!(GEN_switch)); 
			}
		} 
		
		
		
		override void draw(Drawing dr)
		{
			super.draw(dr); 
			
			with(dr)
			{
				void setupLine()
				{
					color = syntaxFontColor(skSymbol); 
					lineWidth = 1.5;  //Todo: lineWidth settings: this should follow the boldness of the NodeStyle
				} 
				
				void drawRoot()
				{
					setupLine; 
					moveTo(innerPos + operands[0].outerPos + ivec2(0, operands[0].outerHeight)); 
					moveRel(-4, -12); 
					lineRel(1, 0); 
					lineRel(2, 5); 
					lineTo(innerPos + operands[0].outerPos + ivec2(2, -1)); 
					lineRel(operands[0].outerWidth-4, 0); 
				} 
				
				mixin(("drawCode").調!(GEN_switch)); 
			}
		} 
		
		final void generateUI(bool enabled_, int targetSurface_=1)
		{ with(im) { mixin(("uiCode").調!(GEN_switch)); }} 
		
		static class ColorNode : NiceExpression
		{
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{ super(__traits(parameters)); } 
			
			override void doBuildSourceText(ref SourceTextBuilder builder)
			{
				with(builder)
				{ put(operator); put("(", operands[0], ")"); }
			} 
			
			override void doRearrange(ref CodeNodeBuilder builder)
			{
				with(builder)
				{
					put(operator); 
					applySyntax(style, skSymbol); 
					style.bkColor = bkColor; //preserve the bkColor
					style.bold = true; //Todo: it's config.NodeStyleBold
					put('('); put(operands[0]); put(')'); CodeNode.rearrange; 
					
					//decode the color
					//Todo: make a good rgba decoder here!
					RGB decodeColor()
					{
						//Todo: copy this RGB decoder into Colors.d
						const parts = operands[0].shallowText.split(',').map!strip.array; 
						switch(parts.length)
						{
							case 1: 	return RGB(parts[0].toInt!uint); //Todo: support # formats
							case 3, 4: 	return RGB(parts.map!(toInt!ubyte).take(3).array); //Todo: support float formats
							default: 	raise("unknown format"); assert(0); 
						}
					} 
					
					ignoreExceptions
					(
						{
							const 	c = decodeColor, 
								bw = blackOrWhiteFor(c); 
							operands[0].fillColor(bw, c); 
							//Todo: Do something if decoding fails.
						}  
					); 
				}
			} 
		} 
		
		static class MixinNode : NiceExpression
		{
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{ super(__traits(parameters)); } 
			
			override void doBuildSourceText(ref SourceTextBuilder builder)
			{
				with(builder)
				{
					put(operator); 
					put('('); 
						put("(", operands[0], ")"); put(','); put("q{", operands[1], "}"); 
					put(')'); 
				}
			} 
			
			void customRearrange(ref CodeNodeBuilder builder, RGB targetColor, string prefix, string postfix)
			{
				with(builder)
				{
					//Note: Instead of overloading, it calls this member from script with extra parameters.
					const sk = skIdentifier1; 
					style.fontColor = sk.syntaxBkColor; 
					style.bkColor = bkColor = mix(sk.syntaxFontColor, targetColor, .38f); 
					
					if(
						operands[0].isDLangIdentifier
						/+
							operands[0].rowCount==1 &&
							operands[0].rows[0].subCells.all!((c)=>((cast(Glyph)(c)) !is null))
						+/
					)
					with(operands[0]) {
						fillColor(style.fontColor, style.bkColor); 
						applyHalfSize; 
					}
					
					put(operands[0]); putNL; put(prefix); put(operands[1]); put(postfix); 
				}
			} 
		} 
		
		static class MixinGenerator : NiceExpression
		{
			bool 	isMultiLine, 
				isFunctionCall,
				isTemplate; 
			
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{ super(__traits(parameters)); } 
			
			override void doBuildSourceText(ref SourceTextBuilder builder)
			{
				with(builder)
				{
					if(isTemplate)
					{
						put(operator); put('('); 
							put("(", operands[0], ")"); put(','); 
							put("q{", operands[1], "}"); 
						put(')'); 
					}
					else
					{
						put("(", operands[0], ")"); put(operator); 
						if(isFunctionCall)	{ put("(", operands[1], ")"); }
						else	{ put("q{", operands[1], "}"); }
					}
				}
			} 
			
			override void doRearrange(ref CodeNodeBuilder builder)
			{
				with(builder)
				{
					//style.bkColor = bkColor = structuredColor("static if"); 
					if(isTemplate)
					style.bkColor = bkColor = structuredColor("mixin")
					/+
						Todo: String Mixin's color is set by syntaxKind=skSymbol,
						but this one has no syntaxkind. (yet)
					+/; 
					
					
					void setupSmallFont()
					{
						if(
							!operands[1].empty && 
							operands[1].rows.map!((r)=>(r.subCells.all!((c)=>(!!(cast(Glyph)(c)))))).all
						)
						{
							with(operands[1]) {
								fillColor(style.fontColor, style.bkColor); 
								applyHalfSize; 
							}
							style.fontHeight = DefaultSubScriptFontHeight; 
						}
					} 
					
					const label = " mixin" ~ ((isTemplate)?(""):("()")) ~ " "; 
					
					if(isFunctionCall)
					{
						setupSmallFont; 
						
						put(label); put(operands[1]); 
						putNL; put(operands[0]); 
					}
					else
					{
						if(isMultiLine) flags.hAlign = HAlign.right; 
						put(operands[0]); if(isMultiLine) putNL; 
						put(label); put(operands[1]); 
						
						CodeNode.rearrange; subCells[0].outerPos.x = 0; 
					}
				}
			} 
		} 
		
		static class MixinTable : NiceExpression
		{
			int doubleGridStyle, gridStyle; 
			
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{
				super(__traits(parameters)); 
				
				static isFiller(Cell c)
				{
					const g = cast(Glyph)c; 
					return g && g.ch.among(' ', '\t'); 
				} 
				static isMarker(Cell c)
				{
					const g = cast(Glyph)c; 
					return g && g.ch=='ʰ'; 
				} 
				static isValidContainer(Cell c)
				{
					auto cntr = cast(CodeContainer)c; 
					return cntr && cntr.prefix.among("(", "q{", "\"", "`", "/+"); 
				} 
				
				/+
					Note: Preprocess rows: 
					 •	Only keep valid blocks right after the  marker chars.
					 •	Remove all marker chars.
					 •	Insert a single space for empty cells.
					 •	Error handling: Putting all unknown things into an /+Error:+/ comment. 
						That is a valid cell, so later it can be reloaded without recursion problems.
				+/
				
				auto tbl = operands[0]; 
				
				static CodeBlock detectOuterBlock(CodeColumn col)
				{
					const dstr = col.extractThisLevelDString; 
					if(dstr.strip=="[")
					{
						const idx = dstr.countUntil('['); 
						if(idx>=0)
						return (cast(CodeBlock)(col.byCell.drop(idx).front)); 
					}
					return null; 
				} 
				if(auto outerBlock = detectOuterBlock(operands[0]))
				{
					if(outerBlock.content.extractThisLevelDString.all!(a=>a.among('[', ' ', '\n', ',')))
					{
						auto innerBlocks = outerBlock.content.byNode!CodeBlock.array; 
						if(innerBlocks.all!(blk=>blk.content.extractThisLevelDString.all!(a=>a.among('"', ' ', '\n', ','))))
						{
							auto rows = innerBlocks.map!
								(
								(blk){
									auto row = blk.content.rows[0]; //reuse row instance to keep lineIdx
									
									//vertical tab detection   blk = CodeBlock: [a, b, c, ....]
									const hasVerticalTab = (){
										if(auto blkParentRow = (cast(CodeRow)(blk.parent)))
										return blkParentRow.isBreakRow; 
										return false; 
									}(); 
									
									row.setParent(tbl); 
									auto tableCells = (cast(CodeContainer[])(blk.content.byNode!CodeString.array)); 
									
									//unpack single composite cells
									foreach(ref c; tableCells)
									{
										if(auto sc = (cast(CodeContainer)(c.content.singleCellOrNull)))
										{
											if((cast(CodeComment)(sc)) || (cast(CodeString)(sc)))
											c = sc; 
										}
									}
									
									row.subCells = (cast(Cell[])(tableCells)); 
									tableCells.each!(
										(c){
											c.setParent(row); 
											c.applyNoBorder; 
											c.isTableCell = true; 
											if(doubleGridStyle<=1)	c.singleBkColor=true; 
											else if(doubleGridStyle==2)	{ c.padding.set(.5); }
										}  
									); 
									row.clearTabIdx; //Freshly loaded MixinTable: It has no TABs
									row.flags.yAlign = YAlign.top; 
									
									if(hasVerticalTab) {
										auto ts = tsNormal; ts.applySyntax(skIdentifier1); 
										row.appendChar('\v', ts); 
									}
									
									row.needMeasure; //Todo: Spread the cells
									return row; 
								}  
							).array; 
							
							tbl.flags.columnIsTable	= true,
							tbl.flags.columnElasticTabs 	= false; 
							tbl.applyNoBorder; 
							
							//Todo: Make tables compatible with multiple pages (vertical Tab)  (Storage too!!!)
							if(rows.length)
							{
								tbl.subCells = (cast(Cell[])(rows)); 
								//Todo: spread the rows
							}
							else
							{
								tbl.subCells.length = 1; 
								tbl.rows[0].clearSubCells; 
							}
							
							if(doubleGridStyle==1) tbl.padding.set(1); 
							
							tbl.needMeasure; 
						}
					}
				}
			} 
			override void doBuildSourceText(ref SourceTextBuilder builder)
			{
				with(builder)
				{
					auto tbl = operands[0], scr = operands[1]; 
					void putTable()
					{
						version(/+$DIDE_REGION+/all) {
							if(!tbl.flags.columnIsTable)
							{
								put(tbl); 
								return; //D compiler will fail on it, but it keeps the unknown content.
							}
							
							put("["); 
							
							const isMultiLine = tbl.rows.length>1; 
							
							if(isMultiLine) indentCount++; 
						}/+
							Note: Mixin Table format
							
							Rows are /+Code: string[]+/ arrays.  And the whole table is an array of those rows:  /+Code: string[][]+/
							
							Cell type  	Manual entry  	Stored on disk	Internal CodeContainer
							cString	/+Code: "blabla\t"+/	/+Code: q{"blabla\t"}+/	/+Code: "blabla\t"+/	//escaped string, only if entered as single token
							dString	/+Code: `blabla\t`+/	/+Code: `blabla\t`+/	/+Code: `blabla	`+/	//WYSIWYG string, only if entered as single token
							code	/+Code: fun*1+2+/	/+Code: q{fun*1+2}+/	/+Code: q{fun*1+2}+/	//when unable to detect a single string
							dComment	/+Code: /+cmt+/+/	/+Code: q{/+cmt+/}+/ 	/+Code: /+cmt+/+/	//The comment must be extracted from the tokenString.
							last resolt		/+Code: q{/+Error: cmt+/}+/	/+Code: /+Error: cmt+/+/	//Displayed without the `Error:` title
							
							If a row only has a single /+Code: [q{/+comment+/}]+/, thats a grouping row. That must be stretched horizontally.
						+/
						foreach(row; tbl.rows)
						{
							//ignore ending VT, but append it at the end of the [] line.
							const hasVerticalTab = row.isBreakRow; 
							
							if(isMultiLine) putNL; put("["); 
							
							bool anyItems = false; void beforeItem() { if(anyItems) put(','); anyItems = true; } 
							
							foreach(entry; row.subCells[0 .. $-hasVerticalTab].splitWhen!mixinTableSplitFun.array)
							{
								bool tryPutContainer(Cell node)
								{
									if(auto str = (cast(CodeString)(node)))
									{
										beforeItem; 
										if(str.type == CodeString.Type.tokenString)	{ { put(str); }}
										else
										{
											put("q{"); 
											put(str); 
											put("}"); 
											/+
												Only tokenString will left unchanged.
												Other strings will be placed 
												into a tonekString.
											+/
										}
									}
									else if(auto cmt = (cast(CodeComment)(node)))
									{
										beforeItem; 
										put("q{"); 
										put(cmt); 
										if(cmt.prefix.among("//","#")) putNL; 
										put("}"); 
									}
									else if(auto cntr = (cast(CodeContainer)(node)))
									{
										beforeItem; 
										put("q{"); 
										put(cntr); //akarmi lehet ez...
										put("}"); 
									}
									else
									{ return false; }
									return true; 
								} void putSource(string src)
								{
									if(src.isValidDLang)
									{
										/+Note: First, it tries to detect complete string literals or comments.+/
										enum enableSingleDString 	= false, 
										enableSingleCString 	= false; 
										if(enableSingleDString && isSingleDString(src))
										{ beforeItem; put(src); }
										else if(enableSingleCString && isSingleCString(src))
										{ beforeItem; put(src); }
										else if(isSingleDComment(src))
										{ beforeItem; put("q{"~src~"}"); }
										else
										{
											/+
												Note: Then it tries a complete re-parse, to detect 
												multiple composite parts, without any text in between them.
											+/
											auto mod = scoped!Module(null, src, StructureLevel.managed); 
											if(mod && mod.content.byCell.all!isMixinTableCell)
											{
												/+
													Note: All the cells in the src text are composite objects.
													No tabs are handled here. because the 
													copy operation can't produce them.
												+/
												foreach(node; mod.content.byNode)
												{ tryPutContainer(node); }
											}
											else
											{
												//Note: Text only solution.  Last resort.  LDC2 will verify this anyways.
												beforeItem; 
												put("q{"); 
												put(src); if(
													src.canFind("//") || 
													src.canFind('#')
													/+Todo: search this for the last row only.+/
												) putNL; 
												put("}"); 
											}
										}
									}
									else
									{
										beforeItem; 
										put(
											"q{/+Error:" ~ (
												src	.replace("/+", "/ +")
													.replace("+/", "+ /")
											) ~ "+/}"
										); 
									}
								} if(!tryPutContainer(entry.front))
								{
									void putAsStringLiteral(R)(R entry)
									{
										//process fresh manual input
										SourceTextBuilder builder; 
										builder.put(entry); 
										putSource(builder.result); 
									} 
									foreach(
										tabSeparatedEntry; entry.splitter!(
											a=>	(cast(Glyph)(a)) &&
												(cast(Glyph)(a)).ch=='\t'
										)
									)
									{ putAsStringLiteral(tabSeparatedEntry); }
								}
							}
							
							put("]"); put(","); /+Extra comma at end, but IDC...+/
							if(hasVerticalTab) put('\v'); 
						}
						if(isMultiLine) { indentCount--; putNL; }
						put("]"); 
					} 
					
					
					/+
						Todo: Must support multiline cells.
						It should be a preprocessing algo: 
							It goes through every row and tries to fetch one cell at a time.
							If it is needed, it can look ahead to the next rows, until a valid mixinTableCell
					+/
					
					//Todo: error handling for both operands! They must be in D syntax!
					if(scr !is null)
					{
						//((){with(op(expr)){expr}}())
						put("()"); 
						put("{"); 
							put("with"); put("("); 
								put(operator); put("("); putTable; put(")"); 
							put(")"); 
							put("{", scr, "}"); 
						put("}"); 
						put("()"); 
					}
					else
					{
						//Single operand version: (op(expr))
						put(operator); put("("); putTable; put(")"); 
					}
				}
			} 
			override void doRearrange(ref CodeNodeBuilder builder)
			{
				with(builder)
				{
					if(operands[1])
					{
						//Table + script
						put(operands[0]); putNL; 
						put("↦"); put(operands[1]); flags.hAlign = HAlign.right; 
						with(padding) left = right = top = 5; 
					}
					else
					{
						//Single operand table.  It has no script.
						put(operands[0]); padding.set(5); 
					}
					
					CodeNode.rearrange; 
					
					if(operands[1]) { subCells[0].outerPos.x = 0; }
					
					
					
					if(doubleGridStyle==0)
					{
						operands[0].bkColor = bkColor; 
						/+
							Minimalistic table look: The color of the table grid is
							inherited from the Node's surface.
						+/
					}
					else if(doubleGridStyle==1)
					{ operands[0].bkColor = mix(style.fontColor, bkColor, .33f); }
				}
			} 
		} 
		static class SigmaOp : NiceExpression
		{
			dchar symbol; 
			
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{ super(__traits(parameters)); } 
			
			override void doBuildSourceText(ref SourceTextBuilder builder)
			{
				with(builder)
				{
					put(operator~'('); 
					foreach(i; 0..3) { if(i) put(","); put("q{", operands[i], "}"); }
					put(')'); 
				}
			} 
			
			override void doRearrange(ref CodeNodeBuilder builder)
			{
				with(builder)
				{
					version(/+$DIDE_REGION prepare and measure operands+/all)
					{
						assert(operands[0..3].all); 
						auto 	cLow 	= operands[0], 
							cHigh 	= operands[1], 
							cExpr 	= operands[2]; 
						operands[0..2].each!((a){ a.applyHalfSize; }); 
						operands[0..3].each!((a){ a.measure; }); 
					}
					
					enum Layout { A, B, C } 
					const layout = ((){
						bool check(dstring s, char separ, int len)
						{ return s.splitter(separ).take(len+1).walkLength==len; } 
						const low = cLow.extractThisLevelDString; 
						if(check(low, '<', 3)) return cHigh.empty ? Layout.B : Layout.A; 
						if(check(low, '=', 2)) return Layout.A; 
						return Layout.C; 
					})(); 
					
					style.bold = false; 
					with(flags) { hAlign = HAlign.center; yAlign = YAlign.center; }
					style.fontHeight = DefaultSubScriptFontHeight; 
					
					enum symbolScale = 2; 
					const reduceSymbolHeight = ((symbol.among('∑', '∏'))?(2.5f):(0)) * symbolScale; 
					
					Cell cSymbol; 
					void putSymbol()
					{
						withScaledFontHeight(symbolScale, { put(symbol); }); 
						cSymbol = subCells.back; 
						cSymbol.outerHeight -= reduceSymbolHeight; 
					} 
					
					final switch(layout)
					{
						case Layout.A
						/+
							Note: [high]
							sigma [expr]
							[low]
						+/: 	{
							put(cHigh); putNL; 
							putSymbol; putNL; 
							put(cLow); 
						}	break; 
						case Layout.B
						/+
							Note: sigma [expr]
							[low] hidden([high])
						+/: 	{
							putSymbol; putNL; 
							put(cLow); putNL; 
							put(cHigh); //later will be hidden
						}	break; 
						case Layout.C
						/+
							Note: sigma [expr]
							[low] ∈ [high]
						+/: 	{
							putSymbol; putNL; 
							put(cLow); put('∈'); put(cHigh); 
						}	break; 
					}
					assert(cSymbol); 
					
					CodeNode.rearrange; strictCellOrder = false/+Disable binary search among glyphs+/; 
					
					subCells = subCells.remove!cellIsNewLine; //remove all newlines.
					
					if(layout==Layout.B && subCells.canFind(cHigh)/+hide op(1) which is normally empty+/)
					{
						cHigh.outerPos = vec2(0, (cSymbol.outerBottom - cHigh.outerHeight)/2); 
						this.outerHeight -= cHigh.outerHeight; 
					}
					
					version(/+$DIDE_REGION Align the expression to the centerline of the symbol.+/all)
					{
						const 	blk 	= innerSize, 
							symbolCenterY 	= cSymbol.outerTop + cSymbol.outerHeight/2; 
						subCells ~= cExpr; 
						
						auto cExprCenterY()
						{
							/+Note: If the content is a single sigma op, then its' symbol's center is the center.+/
							if(layout != Layout.A /+Bug: fix this for every layout!+/)
							if(auto n = (cast(NiceExpression)(cExpr.singleCellOrNull)))
							if(auto g = (cast(Glyph)(n.subCells.get(0))))
							if(g.ch.among('∏', '∑', '∀', '⇶')/+Todo: centralize these literals+/)
							return 	cExpr.topLeftGapSize.y*2.5f /+Todo: calculate the gap properly+/
								+ g.outerTop + g.outerHeight/2; 
							
							return cExpr.outerHeight/2; 
						} 
						
						cExpr.outerPos = vec2(blk.x, symbolCenterY - cExprCenterY); 
						if(cExpr.outerTop<0)
						{ subCells.each!((a){ a.outerPos.y -= cExpr.outerTop; }); }
						//innerSize = vec2(cExpr.outerRight, max(blk.y, cExpr.outerBottom)); 
						innerSize = calcContentSize; 
					}
					
					version(/+$DIDE_REGION Try to shrink horizontally if the expression is small enough.+/all)
					{
						if(
							cExpr.outerTop	>=cSymbol.outerTop &&
							cExpr.outerBottom	<=cSymbol.outerBottom
						)
						{
							const amount = cExpr.outerLeft - cSymbol.outerRight; 
							if(amount>0)
							{
								cExpr.outerPos.x -= amount; 
								
								if(layout.among(Layout.B, Layout.C))
								{
									//shring it more to the left.
									const extraSpaceLeft = min(
										cSymbol.outerLeft, 
										cExpr.outerRight-cLow.outerRight, 
										cExpr.outerRight-cHigh.outerRight
									); 
									if(extraSpaceLeft>0)
									{
										cSymbol.outerPos.x -= extraSpaceLeft; 
										cExpr.outerPos.x -= extraSpaceLeft; 
									}
								}
								
								innerSize = calcContentSize; 
							}
						}
					}
					
					if(reduceSymbolHeight && cSymbol)
					{
						cSymbol.outerSize.y += reduceSymbolHeight; 
						cSymbol.outerPos.y -= reduceSymbolHeight; 
						
						//put the symbol to the back in zOrder
						subCells = cSymbol ~ subCells.filter!(a=>a !is cSymbol).array; 
					}
					
					{
						//fix tab order of low and high limits.
						const 	a = subCells.countUntil(operands[0]),
							b = subCells.countUntil(operands[1]); 
						if(a>=0 && b>=0 && a>b) swap(subCells[a], subCells[b]); 
					}
				}
			} 
		} 
		static class Inspector : NiceExpression
		{
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{
				super(__traits(parameters)); 
				
				/+ulong id; +/
				if(auto m = moduleOf(this))
				{
					auto s = operands[0].shallowText.strip; 
					ulong a; 
					if(s.startsWith("0x"))	a = s[2..$].to!ulong(16).ifThrown(0); 
					else	a = a.to!ulong.ifThrown(0); 
					/+id = +/m.addInspector(this, (cast(uint)(a>>32))); 
				}
			} 
			
			override void doBuildSourceText(ref SourceTextBuilder builder)
			{
				with(builder)
				{
					ulong id; 
					if(auto m = moduleOf(this))
					{
						if(m.isSaving)	id = m.addInspector(this, (cast(uint)(result.length))); 
						else	id = m.getInspectorId(this); 
					}
					const h = "0x" ~ id.to!string(16); 
					put("(" ~ h ~ ")"); put(operator); put("(", operands[1], ")"); 
				}
			} 
			
			override void doRearrange(ref CodeNodeBuilder builder)
			{
				with(builder)
				{
					enum isHalfSize = false; 
					ulong id; 
					if(auto m = moduleOf(this))
					{ id = m.getInspectorId(this); }
					
					put(operands[1]); //op(1) is the the expression, op(0) is the id, but it is not used.
					
					bkColor = border.color = clBlack; 
					with(style) {
						fontColor 	= clWhite,
						bkColor 	= clBlack,
						fontHeight 	= ((isHalfSize)?(DefaultSubScriptFontHeight) :(DefaultFontHeight)),
						bold 	= false; 
					}
					
					
					const hasNewLine = operator.endsWith(' '); 
					
					if(debugValue!="")
					{
						if(hasNewLine) putNL; else put(' '); 
						
						enum DideCodePrefix = "$"~"DIDE_CODE "; 
						if(debugValue.startsWith(DideCodePrefix))
						{
							//Note: Insert dlang managed code. It's full size.
							const src = debugValue[DideCodePrefix.length .. $]; 
							auto col = new CodeColumn(this, src, (mixin(舉!(TextFormat,q{managed_optionalBlock}))), lineIdx)
							; 
							
							operands[0] = col; put(operands[0]); //reuse former operand of ID
						}
						else
						{
							//just insert plain text fast
							auto 	cells 	= (
								mixin(求map(q{line},q{
									debugValue
									.splitLines
								},q{(mixin(求map(q{ch},q{line},q{(cast(Cell)(new Glyph(ch, style, skConsole)))}))).array}))
							).array,
								col 	= new CodeColumn(this, cells); 
							
							with(col) {
								margin.set(0); 
								border = Border.init; 
								padding.set(0, 2); 
								bkColor = clBlack; 
							}
							
							if(isHalfSize)
							{ col.halfSize = true; mixin(求each(q{r},q{col.rows},q{r.halfSize = true})); }
							
							operands[0] = col; put(operands[0]); //reuse former operand of ID
						}
					}
				}
			} 
			
			override void draw(Drawing dr)
			{
				super.draw(dr); 
				
				static if(0)
				{
					ulong id; 
					if(auto m = moduleOf(this))
					{ id = m.getInspectorId(this); }
					dr.color = clWhite; dr.fontHeight = 3; dr.textOut(outerPos, "0x"~id.to!string(16)); 
				}
				
				
				{
					//highlight changed debugvalues
					const du = (application.tickTime-debugValueUpdatedTime).value(0.5f*second); 
					if(du<1)
					{
						const dc = (application.tickTime-debugValueChangedTime).value(0.5f*second).min(0, 1); 
						dr.alpha = sqr(1-du); dr.color = mix(clYellow, clWhite, 1-dc); 
						dr.lineWidth = -4; 
						dr.drawRect(outerBounds.inflated(dr.lineWidth/2)); 
						dr.alpha = 1; 
					}
				}
			} 
		} 
		static class InteractiveValue : NiceExpression
		{
			this(
				Container parent, int templateIdx_, 
				CodeColumn col0=null, CodeColumn col1 = null, CodeColumn col2 = null
			)
			{
				super(__traits(parameters)); 
				
				controlPropsText = operands[0].extractTrailingCommentText!""; 
				controlProps = controlPropsText.commandLineToStruct!InteractiveControlProps; 
				
				//data type
				controlType = operands[0].byShallowChar.text /+Bug: If this type in unknown, it crashes!!!+/; 
				
				//compile time value
				controlValue = operands[1].byShallowChar.text.to!float.ifThrown(0); 
				
				//optional locationId
				controlId = ((operands[2])?(
					operands[2].byShallowChar.text
					.withoutStarting("0x")
					.to!ulong(16).ifThrown(0)
				):(0)); 
			} 
			
			auto generateIdStr(size_t result_length)
			{
				if(auto m = moduleOf(this))
				if(m.isSaving) controlId = (result_length<<32) | m.fileNameHash; 
				return "0x"~controlId.to!string(16); 
			} 
			
			/+
				override void doBuildSourceText(ref SourceTextBuilder builder)
				{
					with(builder)
					{}
				} 
			+/
			
			void customRearrange(ref CodeNodeBuilder builder, bool hasExpr)
			{
				with(builder)
				{
					if(hasExpr && !controlProps.hideExpr)
					{
						if(controlProps.sameBk)
						operands[1].fillColor(
							syntaxFontColor(skInteract),
							syntaxBkColor(skInteract)
						); 
						else
						operands[1].bkColor = syntaxBkColor(skIdentifier1); 
						if(controlProps.halfSize) operands[1].applyHalfSize; 
						put(operands[1]); 
						if(controlProps.newLine) putNL;  
					}
					
					switch(controlType)
					{
						case "bool": {
							put(' '); /+placeholder+/
							subCells.back.outerSize = vec2(
								controlProps.w.ifz(controlProps.btnEvent ? 3 : 1), 
								controlProps.h.ifz(controlProps.btnEvent ? 1 : 1), 
							) * DefaultFontHeight; 
						}break; 
						case 	"float",
							"int": {
							put(' '); /+Just a placeholder.+/
							subCells.back.outerSize = vec2(
								controlProps.w.ifz(10), 
								controlProps.h.ifz(1)
							) * DefaultFontHeight; 
						}break; 
						default: put(operator); put(operands[0]); put(operands[1]); //unknown type
					}
					
					if(hasExpr && !controlProps.hideExpr && controlProps.newLine)
					{
						CodeNode.rearrange; 
						if(subCells.length==3)
						{
							//align center
							const maxWidth = max(
								subCells.front.outerWidth, 
								subCells.back.outerWidth
							); 
							foreach(a; only(subCells.front, subCells.back))
							a.outerPos.x = (maxWidth - a.outerWidth)/2; 
						}
					}
				}
			} 
			
			override void draw(Drawing dr)
			{
				super.draw(dr); 
				
				if(templateName=="interactiveValue")
				{
					const exeIsRunning = !!dbgsrv.exe_pid; 
					this.bkColor = mix(syntaxBkColor(skInteract), clGray, ((exeIsRunning)?(0):(.33f))); 
					if(subCells.length==1)
					if(auto glyph = (cast(Glyph)(subCells.get(0))))
					glyph.bkColor = this.bkColor; 
				}
				
				if(!isnan(controlValue))
				if(auto m = moduleOf(this)) m.visibleConstantNodes ~= this; 
			} 
			
			void interactiveUI(
				bool useDbgValues,
				bool enabled_, int targetSurface_
			)
			{
				with(im)
				{
					void doit(T)()
					{
						style.bkColor = this.bkColor; 
						style.fontColor = syntaxFontColor(skIdentifier1); 
						auto placeholder = this.subCells.back; 
						
						//Todo: edit permission, cooperate with Undo/Redo
						T act = this.controlValue.to!T; 
						
						float* interactiveRef; uint* interactiveTick; 
						if(useDbgValues && controlId)
						{
							auto iv = &dbgsrv.data.interactiveValues; 
							if(controlId!=iv.ids.get(controlIndex))
							ignoreExceptions({ controlIndex = iv.resolveIndex(controlId, act.to!float); }); 
							if(controlId==iv.ids.get(controlIndex))
							{
								interactiveRef = &iv.floats[controlIndex]; 
								interactiveTick = &iv.ticks[controlIndex]; 
								act = (*interactiveRef).to!T; 
							}
						}
						
						T next = act; 
						
						auto commonParams() => tuple
							(
							enable(enabled_), ((this.identityStr).genericArg!q{id}),
							{ flags.targetSurface = targetSurface_; outerPos = this.worldInnerPos + placeholder.outerPos; }
						); 
						
						bool userModified; 
						void doSlider(T)(ref T val)
						{
							theme = "tool"; 
							userModified = Slider
								(
								val, commonParams[], 
								range(
									controlProps.min, controlProps.max, controlProps.step, 
									cast(RangeType)controlProps.type
								), 
								{
									outerSize = placeholder.innerSize; 
									with((cast(SliderClass)(actContainer)))
									{
										rulerSides 	= (cast(ubyte)(controlProps.rulerSides)),
										rulerDiv0 	= controlProps.rulerDiv0,
										rulerDiv1 	= controlProps.rulerDiv1; 
									}
								}
							); 
						} 
						static if(is(T==bool))
						{
							theme = "tool"; 
							
							if(controlProps.btnEvent)
							{
								auto capt = controlProps.btnCaption; 
								if(capt.empty && operator=="同!") capt = operands[1].byShallowChar.text.strip; 
								next = Btn(
									capt, commonParams[], VAlign.center,
									{ outerSize = placeholder.innerSize; }
								).down; 
								userModified = next != act; 
							}
							else
							{ userModified = ChkBox(next, "", commonParams[]).clicked; }
						}
						else static if(is(T==float))
						{ doSlider(next); }
						else static if(is(T==int))
						{ doSlider(next); }
						
						
						if(useDbgValues)
						{
							if(userModified && interactiveRef)
							{
								enum holdDurationTicks = 5/+Todo: ->settings+/; 
								*interactiveRef 	= next,
								*interactiveTick 	= application.tick + holdDurationTicks; 
							}
						}
						else
						{ if(act!=next) { this.controlValue = next; this.setChanged; }}
					} 
					
					switch(controlType)
					{
						case "bool": 	doit!bool; break; 
						case "float": 	doit!float; break; 
						case "int": 	doit!int; break; 
						default: 
					}
				}
			} 
		} 
	} 
}