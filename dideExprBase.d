module dideexprbase; 

import didebase, het.parser; 
import didenode : NodeStyle, CodeString, CodeBlock, CodeContainer; 
import didedecl : Declaration; 

version(/+$DIDE_REGION+/all) {
	enum lowestSpecialUnicodeChar = '\u3000' /+Contains all chinese chars used in NiceExpressions+/; 
	
	alias NEP = NiceExpressionTemplate.Pattern; 
	alias NEB = NiceExpressionTemplate.BlockType; 
	alias NEC = NiceExpressionTemplate.CustomClass; 
	
	static struct NiceExpressionTemplate
	{
		mixin((
			(表([
				[q{/+Note: Pattern : ubyte+/},q{/+Note: OpCnt+/},q{/+Note: Text#+/}],
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
				[q{binaryInterpolatedTokenStringTextOp},q{2},q{/+Code: op(iq{}.text,iq{}.text)+/},q{/+Note: 碼! ExternalCode (not used currently)+/}],
				[q{binaryInterpolatedTokenStringOp2},q{3},q{/+Code: op((),iq{},iq{})+/},q{/+Note: 碼! ExternalCode2 first param is _LOCATION_!()+/}],
				[],
				[q{/+Note: special statement: any single row statement where the last char must is a unicode special char+/}],
				[q{specialStatementOp},q{0},q{/+Code: specialStatement+/},q{/+Note: auto 間T=now間+/}],
			]))
		).調!(GEN_enumTable)); 
		
		mixin((
			(表([
				[q{/+Note: BlockType : ubyte+/},q{/+Note: Prefix+/},q{/+Note: Postfix+/}],
				[q{list},q{"("},q{")"}],
				[q{stringMixin},q{"mixin("},q{")"}],
				[q{templateMixin},q{"mixin "},q{""}],
				[q{specialStatement},q{""},q{""}],
			]))
		).調!(GEN_enumTable)); 
		
		enum CustomClass
		{
			NiceExpression, 
			ColorNode, 
			MixinNode, 
			MixinGenerator, 
			MixinTable, 
			SigmaOp, 
			Inspector, 
			InteractiveValue, 
			ShaderNode
		} 
		
		string name; 
		
		BlockType blockType; 
		Pattern pattern; 
		SyntaxKind syntax; 
		
		NodeStyle invertMode; 
		string example, operator; 
		string textCode, rearrangeCode, drawCode, initCode, uiCode; 
		CustomClass customClass; 
		
		
		@property string combinedPattern() const
		=> blockTypePrefix[blockType]~
		patternText[pattern]~
		blockTypePostfix[blockType]; 
		
		@property void combinedPattern(string ptn)
		{
			void setNEP(NEB bt, string ptn)
			{
				this.blockType = bt; 
				try this.pattern = 	patternText.countUntil(ptn).to!NEP; 
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
		string export_()
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
		
		static make(in string[] a...)
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
				customClass 	= a[6].to!NEC; 
				
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
						//Todo: too much redundancy
						static if(what=="q{}")
						{
							auto params = iota(0, cc, 2).map!((i)=>((cast(CodeString)(row.subCells[i])))).array; 
							if(params.all!((s)=>(s && s.type==CodeString.Type.tokenString)))
							{ return params.map!((p)=>(p.content)).array; }
						}
						else static if(what=="tiq{}")
						{
							auto params = iota(0, cc, 2).map!((i)=>((cast(CodeString)(row.subCells[i])))).array; 
							if(params.all!((s)=>(s && s.type==CodeString.Type.interpolated_tokenString_text)))
							{ return params.map!((p)=>(p.content)).array; }
						}
						else static if(what=="()")
						{
							auto params = iota(0, cc, 2).map!((i)=>((cast(CodeBlock)(row.subCells[i])))).array; 
							if(params.all!((b)=>(b && b.type==CodeBlock.Type.list)))
							{ return params.map!((p)=>(p.content)).array; }
						}
						else static if(what=="()iq{}iq{}"/+first is block, rest are interpolated tokenStrings+/)
						{
							auto params = iota(0, cc, 2).map!
							((i){
								auto c = (cast(CodeContainer)(row.subCells[i])); 
								if(i==0)	{
									if(auto b=(cast(CodeBlock)(c)))
									if(b.type==CodeBlock.Type.list) return c; 
								}
								else	{
									if(auto s=(cast(CodeString)(c)))
									if(s.type==CodeString.Type.interpolated_tokenString) return c; 
								}
								return null; 
							}).array; 
							if(params.all)
							{ return params.map!((p)=>(p.content)).array; }
						}
						else static if(what=="()q{}()"/+the 2nd param is a tokenString, rest are brackets+/)
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
						else static assert(0, "Unknown `what`: "~what.quoted); 
					}
				}
			}
			return []; 
		} 
		
		alias extractTokenStringParams 	= extractCodeColumnParams!"q{}",
		extractInterpolatedTokenStringTextParams 	= extractCodeColumnParams!"tiq{}",
		extractListParams 	= extractCodeColumnParams!"()",
		extractListTokenStringParams 	= extractCodeColumnParams!"()q{}()",
		extractInterpolatedTokenStringParams2	= extractCodeColumnParams!"()iq{}iq{}"/+Todo: It's a fucking abomination!+/; 
		
	}
	
	
}