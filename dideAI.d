module dideai; 

import het.ai; 
import didebase; 
import didenode: CodeComment; 
import didedecl: extractThisLevelDString; 
import didetextselectionmanager : TextSelectionManager; 
static struct AiManager
{
	TextSelectionManager textSelections; 
	
	//Todo: Use an IEditor interface for these
	void delegate(string) pasteText; 
	void delegate(string source, int subColumnIdx=-1) insertNode; 
	void delegate() insertNewLine; 
	void delegate() cursorLeftSelect; 
	void delegate() deleteToLeft; 
	
	CodeComment activeAiNode; 
	string[] aiSnippets; 
	
	AiModel aiModel; 
	
	AiChat[CodeComment] pendingAiChatByAiAssistantNode; 
	
	
	
	CodeComment getSurroundingAiNode()
	{
		auto s = textSelections.primary; 
		return ((s)?(s.codeColumn.allParents!CodeComment.filter!((a)=>(a.isAi)).frontOrNull):(null)); 
	} 
	
	void initiate()
	{
		//Todo: activeAiNode must be validated in update()
		
		/+
			This is a one-button function for initiating an AI chat:
			- Memorizes selected code snippets if there is no active aiNode.
			- Attach selected code snippets to active aiNode.
			- Creates a new AI prompt if selection is a single cursor.
			- Selects the active aiNode if inside one.
			(aiNode is CodeComment where customPrefix = "AI:")
		+/
		
		/// A "snippet" is source text or plain text captured for AI processing,  
		/// wrapped in triple quotes when sent to the model.  
		void captureSnippets()
		{
			aiSnippets = textSelections[].map!((a)=>(a.sourceText)).filter!"a!=``".array; 
			textSelections.clear; 
		} 
		
		/// Inserts captured snippets into the active AI node
		void insertSnippets()
		{
			auto col = activeAiNode.content; 
			foreach(src; aiSnippets)
			{
				textSelections.items = col.endSelection(true); 
				if(!col.rows.back.empty) pasteText("\n"); 
				insertNode("/+code:\0+/", 0); 
				pasteText(src); 
				textSelections.items = col.endSelection(true); 
			}
			im.flashInfo(i"Added $(aiSnippets.length) snippets to AI prompt.".text); 
			aiSnippets.clear; //one time use only
		} 
		
		/// Creates a new interactive AI node (textbox) in the editor, ready for user input.  
		void createAiNode()
		{
			insertNode("/+AI:\0+/", 0); 
			activeAiNode = getSurroundingAiNode; 
			im.flashInfo("Type AI prompt, press [Ctrl+Enter] to send."); 
			
			if(aiSnippets.length) insertSnippets; 
		} 
		
		auto ts = textSelections; 
		
		if(ts.empty) { im.flashWarning("Call AI: must have a a cursor or text selection first!"); return; }
		
		if(ts.length==1 && ts[0].valid && ts[0].isZeroLength)
		{
			//create/select active ai node
			auto aiNode = getSurroundingAiNode; 
			if(aiNode)
			{
				activeAiNode = aiNode; 
				im.flashWarning("This is the active AI prompt.  [Alt+A] will copy selection to here."); 
			}
			else
			{ createAiNode; }
		}
		else
		{
			//attach copy code snippets to ai prompt
			captureSnippets; 
			if(activeAiNode)
			{ insertSnippets; }
			else
			{ im.flashInfo(i"$(aiSnippets.length) snippets collected for new AI prompt.".text); }
		}
		
	} 
	
	void launch(bool refreshCache=false)
	{
		{
			auto n = getSurroundingAiNode; 
			if(!n) { im.flashWarning("Can't launch AI prompt.  Cursor must be inside an AI Node.".text); return; }
			activeAiNode = n; 
		}
		
		auto col = activeAiNode.content; 
		static bool isWhite(Cell c)
		{
			if(!c /+null: NewLine+/) return true; 
			if(auto g = (cast(Glyph)(c))) return g.ch.isDLangWhitespace; 
			return false; 
		} 
		static isAi(Cell cell)
		{
			if(isWhite(cell)) return false; 
			if(auto cmt = (cast(CodeComment)(cell))) return cmt.isAiRelated; 
			return false; 
		} 
		static isAssistant(Cell cell)
		=> isAi(cell) && (cast(CodeComment)(cell)).isAssistant; 
		
		static sourceText(Cell c)
		{
			if(!c) return "\n"; 
			if(auto g = (cast(Glyph)(c))) return g.ch.text; 
			if(auto n = (cast(CodeNode)(c))) return n.sourceText; 
			return "?"; 
		} 
		
		TextSelection[] userRanges; 
		foreach(grp; col.byCell.chunkBy!((a)=>(isAi(a))))
		{
			if(!grp[0])
			{
				auto nodes = grp[1].array; 
				while(nodes.length && isWhite(nodes.front)) nodes.popFront; 
				while(nodes.length && isWhite(nodes.back)) nodes.popBack; 
				if(nodes.length)
				{ userRanges ~= col.selectionOf(nodes.front, nodes.back, false); }
			}
		}
		
		//Elfold new user contents
		textSelections.items = userRanges; 
		insertNode("/+User:\0+/"); 
		
		{
			//Put cursor to the end and remove trailing whitespace and all the assistant contents
			textSelections.items = col.endSelection(true); 
			auto cells = col.byCell.array; 
			const trailingWhiteCnt = cells.retro.countUntil!((a)=>(!(isWhite(a) || isAssistant(a)))).to!int; 
			if(trailingWhiteCnt>0)
			{
				foreach(i; 0..trailingWhiteCnt) cursorLeftSelect(); 
				deleteToLeft(); 
			}
		}
		
		
		{
			//Put all the ai contents into new lines
			auto sel = chain(only(Cell.init), col.byCell)
				.array.slide!(No.withPartial)(2)
				.filter!((a)=>(a[0] && isAi(a[1])))//if there's something before the ai node
				.map!((a)=>(col.cursorOf(a[1])))
				.map!((a)=>(TextSelection(a, a, false)))
				.array; 
			if(sel.length) { textSelections.items = sel; insertNewLine(); }
		}
		
		string[][] messages; 
		{
			//Gather the prompt
			messages = 	col.byNode!CodeComment.filter!((a)=>(isAi(a)))
				.map!((a)=>(
				[
					/+role+/	het.wordAt(a.customPrefix, 0).decapitalize, 
					/+content+/	a.content.sourceText/+Todo: process code snippets!+/
				]
			)).array; 
		}
		
		//Select the very end
		textSelections.items = col.endSelection(true); 
		
		//create a new assistant node.
		insertNewLine(); 
		insertNode("/+Assistant:\0+/", 0); 
		auto assistantNode = (cast(CodeComment)(textSelections[0].codeColumn.parent)); 
		
		if(!aiModel)
		{
			aiModel = new AiModel
			(
				//"https://api.deepseek.com/v1/chat/completions",
				"https://api.deepseek.com/chat/completions", 
				/+"deepseek-chat"+/ /+260725 there are 2 new models: flash and pro+/ "deepseek-v4-flash", 
				`You are a helpful assistant.
When working on my code, use strict whitespace preservation!
When generating code, prefer using tab character for indentation!
For multiline blocks like {} and comments /+ +/, put the opening and closing symbols into their own lines.
Use higher level DLang functional constructs when possible: ranges, etc.
Keep the simple blocks/statemenst on the same line of the for, if, etc. Only put multiline blocks onto a new line.
Use GLSL-like vector/matrix operations, my DLang math framework understands those.
Technologies preferred: Win32 64bit platform, Vulkan and GLSL for graphics and compute.
Short answers please! Don't explain only the necessari things, use very short sentences, focus only at the topic. If I need more explaining I will always ask.`
			); 
			with(aiModel)
			apiKey 	= File(appPath, "a.a").readStr,
			cachePath 	= Path(appPath, "WebCache"),
			cached 	= true; 
			NOTIMPL("Ini file for settings!"); 
		}
		
		
		{
			//launch ai query
			if(auto a = assistantNode in pendingAiChatByAiAssistantNode)
			{
				//stop the already running query
				(*a).stop; 
				pendingAiChatByAiAssistantNode.remove(assistantNode); 
			}
			
			auto chat = aiModel.newChat; 
			chat.ask(messages, refreshCache: refreshCache); 
			pendingAiChatByAiAssistantNode[assistantNode] = chat; 
			
			im.flashInfo("Ai: ", "launched ("~chat.identityStr[0..3]~")"); 
		}
	} 
	void update()
	{
		//Todo: check if activeAiNode was deleted...
		CodeComment[] toRemove; 
		foreach(node, chat; pendingAiChatByAiAssistantNode)
		{
			//Todo: check if the node was deleted...
			
			with(chat)
			{
				static if((常!(bool)(0))) {
					update
					(
						(Event event, string s)
						{
							final switch(event)
							{
								case Event.text: 	textSelections.preserve
								(
									{
										textSelections.items = node.content.endSelection(true); 
										pasteText(s); 
										/+
											Todo: should not focus at this editing, 
											the user cant pan elswhere.
										+/
									}
								); 	break; 
								case Event.error: 	print(EgaColor.ltRed("\nError: "~s)); 	break; 
								case Event.warning: 	print(EgaColor.yellow("\nWarning: "~s)); 	break; 
								case Event.done: 	print(EgaColor.ltGreen("\nDone: "~s)); 	break; 
							}
						}
					); 
				}else {
					version(/+$DIDE_REGION RGNSave/restore textSelections+/all)
					{
						Nullable!(string[]) savedTS; 
						void saveTS() { if(savedTS.isNull) savedTS = textSelections.saveTextSelections; } 
						scope(exit) if(!savedTS.isNull) textSelections.restoreTextSelections(savedTS.get); 
					}
					
					
					void seekToEnd()
					{ saveTS; textSelections.items = node.content.endSelection(true); } 
					
					auto st() => markdownProcessor; 
					auto cr() => textSelections.primary.cursors[0]; 
					void stepIn(string prefix)
					{
						auto cmt = cr.codeColumn.lastCell!CodeComment; 
						if(cmt && cmt.customPrefix==prefix)
						textSelections.items = cmt.content.endSelection(true); 
						else insertNode("/+"~prefix~"\0+/",0); 
					} 
					
					bool applyWordWrap()
					{
						bool res/+changed or not+/; 
						
						void wrap(CodeRow row, bool createPara, float extraSize = 0)
						{
							auto originalRow = row; 
							const maxWidth = 600/+Todo: move it outside+/ - extraSize
							; 
							int[] splitPoints; float acc=0; 
							foreach(x; 0..row.cellCount-1)
							{
								if(row.chars[x]==' ' && row.chars[x+1]!=' ')
								{
									const w = row.subCells[x+1].outerLeft-acc; 
									if(w > maxWidth)
									{
										acc += w; 
										splitPoints ~= x; 
									}
								}
							}
							
							if(splitPoints.empty) return; 
							
							res = true; 
							
							if(createPara)
							{
								textSelections.items = row.rowSelection; 
								insertNode("/+Para:"~row.sourceText~"+/"); 
								row = (cast(CodeComment)(row.subCells[0])).enforce.content.rows[0]; 
							}
							
							//create newLines
							auto col = row.parent.enforce; enforce(col.rowCount==1); 
							textSelections.items = 
								splitPoints.map!((x)=>(
								TextSelection(
									TextCursor(col, ivec2(x  , 0)), 
									TextCursor(col, ivec2(x+1, 0)), false
								)
							)).array; 
							insertNewLine(); 
							
							originalRow.clearChanged; 
						} 
						
						auto col = node.content; 
						foreach(y; 0..col.rowCount)
						{
							auto row = col.rows[y]; 
							if(!row.empty)
							{
								if(auto cmt = (cast(CodeComment)(row.subCells.back)))
								{
									if(
										(cmt.isFormatBullet || cmt.isFormatPara) && 
										cmt.content.rowCount==1
									)
									{ wrap(cmt.content.rows[0], false, cmt.outerLeft); continue; }
								}
								wrap(row, true); 
							}
						}
						
						return res; 
					} 
					
					bool makeTables()
					{
						//Note: This is totally unoptimal, but AI is slow, so it's OK for now.
						/+
							Todo: Detect AI links: [RFC 4122](https://tools.ietf.org/html/rfc4122)
							- upgrade the /+Link: link+/ comment too
						+/
						
						bool res/+if changed or not+/; 
						string tableCode; 
						
						int checkTableHeight(CodeRow row)
						{
							bool isTableRow(CodeRow row)
							=> row.length>=2 && row.chars.front=='|' && row.chars.back=='|'; 
							
							if(!isTableRow(row)) return 0; 
							
							if(auto col = (cast(CodeColumn)(row.parent)))
							{
								const bottom = col.subCellIndex(row)/+Todo: slowwww, already known+/; 
								if(bottom>=0)
								{
									int top = -1; 
									foreach_reverse(i; 0..bottom)
									if(isTableRow(col.rows[i])) top = i; else break; 
									if(mixin(界3(q{0},q{top},q{bottom})))
									{
										auto cells = iota(top, bottom+1)
										.map!((y)=>(
											col.rows[y].sourceText
											.withoutStarting('|')
											.withoutEnding('|')
											.splitter('|')
											.map!strip
											.map!((s)=>(s.replace("&124;", "|")))
											.array
										)).array; 
										if(cells.length>=3)
										{
											const res = cells.length.to!int; 
											
											//remove header gridline
											if(cells[1].length && cells[1][0].canFind("---"))
											cells = cells.remove(1); 
											
											tableCode = "/+Structured:(表(["~
											cells.enumerate.map!((r)=>(
												"["~
												r.value.map!((c)=>(
													"q{"~
													((r.index)?(""):("/+Note:"))~
													c/+Todo: valid chars check!+/~
													((r.index)?(""):("+/"))~
													"}"
												)).join(',')~
												"]"
											)).join(',')~
											"]))+/"; 
											return res; 
										}
									}
								}
							}
							
							return 0; 
						} 
						
						again: 
						foreach_reverse(y; 0..node.content.rowCount)
						{
							auto row = node.content.rows[y]; 
							if(const h = checkTableHeight(row))
							{
								//select whole table
								auto ts = row.rowSelection; ts.cursors[0].pos.y -= h-1; 
								textSelections.items = ts; res = true; 
								
								//replace with nice table
								insertNode(tableCode); 
								
								goto again; 
							}
						}
						
						return res; 
					} 
					update_markDown
					(
						((ch){
							version(/+$DIDE_REGION Easy access to last row+/all)
							{
								CodeRow row; void accessLastRow()
								{
									seekToEnd; row = cr.codeColumn.rows[cr.pos.y]; 
									
									/+
										Todo: /+
											Error: Exception: ACCESS_VIOLATION at 7FF763E598DC info: 0, 0
											----------------
											0x00007FF763E598DC in dideai.AiManager.update.__foreachbody_L245_C3.__lambda_L455_C8!dchar.__lambda_L455_C8.accessLastRow at c:\d\projects\dide\dideai.d(459)
											0x00007FF763E5910F in dideai.AiManager.update.__foreachbody_L245_C3.__lambda_L455_C8(__T15)(ch) at c:\d\projects\dide\dideai.d(463)
											0x00007FF763E42349 in het.ai.AiChat.update_markDown.emit at c:\d\libs\het\ai.d(494)
											0x00007FF763E41A28 in het.ai.AiChat.update.processEvent at c:\d\libs\het\ai.d(372)
											0x00007FF763E41850 in update at c:\d\libs\het\ai.d(397)
											0x00007FF763E420F0 in update_markDown at c:\d\libs\het\ai.d(499)
											0x00007FF763E57AAD in dideai.AiManager.update.__foreachbody_L245_C3 at c:\d\projects\dide\dideai.d(563)
											0x00007FF763EBFE1C in aaApply2
											0x00007FF763E578E9 in update at c:\d\projects\dide\dideai.d(571)
											0x00007FF763DB031F in update at c:\d\projects\dide\dideworkspace.d(476)
											0x00007FF763AB2D92 in onUpdate at c:\d\projects\dide\dide.d(750)
											0x00007FF763C36F79 in updateWithActionManager at c:\d\libs\het\win.d(1048)
											0x00007FF763C353B4 in internalUpdate at c:\d\libs\het\win.d(1182)
											0x00007FF763C7F692 in doUpdate at c:\d\libs\het\vulkanwin.d(5619)
											0x00007FF763C34A34 in WndProc at c:\d\libs\het\win.d(795)
										+/
									+/
								} accessLastRow; 
							}
							
							
							if(st.backtickLevel)	stepIn("Highlighted:"); 
							else if(st.asteriskLevel==2)	stepIn("Bold:"); 
							else if(st.asteriskLevel==1)	stepIn("Italic:"); 
							else {
								if(ch=='\n')
								{
									int checkHeadingLevel()
									{
										const hashCount = row.chars.countUntil!q{a!='#'}.to!int; 
										return ((
											hashCount.inRange(1, 6) && 
											row.getChar(hashCount)==' '
										)?(hashCount):(0)); 
									} 
									
									int checkBulletLevel()
									{
										bool chk(int i) => row.getChar(i)=='-' && row.getChar(i+1)==' '; 
										{
											const spaceCount = row.chars.countUntil!q{a!=' '}.to!int.max(0); 
											if(chk(spaceCount)) return (spaceCount+1)/2 + 1; 
										}
										{
											const tabCount = row.chars.countUntil!q{a!='\t'}.to!int.max(0); 
											if(chk(tabCount)) return tabCount+1; 
										}
										return 0; 
									} 
									if(const headingLevel = checkHeadingLevel)
									{
										//process headings
										textSelections.items = row.rowSelection; 
										insertNode("/+H"~headingLevel.text~":"~row.sourceText[headingLevel+1..$]~"+/"); 
									}
									else if(const bulletLevel = checkBulletLevel)
									{
										//process bullet text
										const s = row.sourceText.stripLeft.withoutStarting("- "); 
										textSelections.items = row.rowSelection; 
										pasteText("\t".replicate(bulletLevel)); 
										insertNode("/+Bullet:"~s~"+/"); 
									}
									else if(row.empty)
									{
										//normally there are empty rows after tables, so use thiss trigger to detect them.
										if(
											makeTables + 
											applyWordWrap
										) accessLastRow; 
									}
									else if(row.cellCount>=4 && row.chars.startsWith("/+") && row.chars.endsWith("+/"))
									{
										//detect and insert comments
										textSelections.items = row.rowSelection; 
										insertNode(row.sourceText); 
									}
									
									//remove changed markers from row and subContainers
									row.clearChanged; 
								}
							}
							
							pasteText(ch.text); 
						}),
						((){
							/+onFinalizeCode+/seekToEnd; 
							if(auto cmt = cr.codeColumn.lastCell!CodeComment)
							if(auto col = cmt.content)
							{
								if(cmt.isHighlighted && col.rowCount>2 && col.lastRow.extractThisLevelDString.text.strip=="")
								{
									//strip off language spec and the last empty row
									const language = col.firstRow.extractThisLevelDString.text.strip; 
									col.subCells = col.subCells[1..$-1]; 
									col.needMeasure; 
									
									if(language.among("", "d", "c", "cpp", "glsl", "hlsl"))
									{
										//promote to structured modular code
										cmt.customPrefix = "Structured:"; 
										textSelections.items = cmt.nodeSelection; 
										insertNode(cmt.sourceText); 
									}
								}
							}
						}),
						((){
							/+onFinish+/
							makeTables; applyWordWrap; 
							
							if(node.content.rowCount>1 && node.content.lastRow.empty)
							{
								//remove last empty row
								node.content.subCells = node.content.subCells[0..$-1]; 
								node.content.needMeasure; 
							}
						})
					); 
				}
				
				if(!running)
				{
					node.content.clearChanged; 
					toRemove ~= node; 
				}
			}
		}
		
		foreach(node; toRemove)
		{
			auto chat = pendingAiChatByAiAssistantNode[node]; 
			pendingAiChatByAiAssistantNode.remove(node); 
			im.flashInfo("Ai: ", "finished ("~chat.identityStr[0..3]~")"); 
		}
	} 
} 
/+Todo: Make an AI agent that works in DIDE, like Codex.+/
/+
	AI: /+
		User: Do you know how Codex works?
		
		Right now I'm accessing Deepseek API through my own chat interface.
		But how can I make Deepseek to have an overview over my full codebase I'm working on?
		Obviously seeding the full source code would exhaust the LLM memory capacity. But what clever search algorithms are used when an AI agent, like Codex is searching through codebase? I have the full code identifier tree from the compiler, maybe that can help too, but still the whole tree is 100MB, I can't feed it once. Should I use 'functions' to do that in Deepseek API?
	+/
	/+
		Assistant: /+
			Para: You're asking about a fundamental challenge in AI-assisted coding! Let me explain how Codex
			and similar systems handle codebase navigation, and how you can implement similar strategies
			with Deepseek.
		+/
		
		/+H2: How Codex Works (Simplified)+/
		
		Codex uses a /+Bold: retrieval-augmented generation (RAG)+/ approach with several key strategies:
		
		/+H3: 1. /+Bold: Semantic Chunking+/+/
		Instead of feeding entire files, Codex breaks code into meaningful chunks:
			/+Bullet: Function bodies+/
			/+Bullet: Class definitions+/
			/+Bullet: Method implementations+/
			/+Bullet: Documentation blocks+/
			/+Bullet: Import/export statements+/
		
		Each chunk maintains its context (file path, surrounding declarations).
		
		/+H3: 2. /+Bold: Multi-Stage Retrieval+/+/
		
		/+
			Structured: // Pseudo-code for retrieval pipeline
			struct CodeChunk {
				    string path; 
				    string content; 
				    string[] symbols; 
				    size_t startLine, endLine; 
			} 
			
			CodeChunk[] retrieveRelevantCode(string query) {
				    // Stage 1: Embedding-based search
				    auto queryEmbedding = embed(query); 
				    auto candidates = vectorDB.similaritySearch(queryEmbedding, 50); 
				    
				    // Stage 2: Symbol-aware filtering
				    candidates = filterBySymbols(candidates, extractSymbols(query)); 
				    
				    // Stage 3: Dependency graph traversal
				    candidates = expandImports(candidates, dependencyGraph); 
				    
				    // Stage 4: Context window optimization
				    return selectOptimalChunks(candidates, MAX_TOKENS); 
			} 
		+/
		
		/+H3: 3. /+Bold: Symbol Table Utilization+/+/
		
		Your compiler's identifier tree is gold! Here's how to use it:
		
		/+
			Structured: struct SymbolIndex {
				    string name; 
				    SymbolKind kind;  // function, class, variable, etc.
				    string filePath; 
				    size_t line; 
				    string[] references;  // files that reference this symbol
				    string[] dependencies;  // symbols this depends on
			} 
			
			// Build a lightweight index (NOT the full tree)
			SymbolIndex[] buildLightweightIndex(IdentifierTree fullTree) {
				    return fullTree.symbols
				        .filter!(s => s.isPublic || s.isUsed)
				        .map!(
					s => SymbolIndex(
						            s.name,
						            s.kind,
						            s.filePath,
						            s.line,
						            s.references,
						            s.dependencies
					)
				)
				        .array; 
			} 
		+/
		
		/+H2: Practical Implementation with Deepseek API+/
		
		/+H3: Strategy 1: /+Bold: Hierarchical Context Injection+/+/
		
		/+
			Structured: // Use Deepseek's function calling for codebase queries
			class CodebaseAgent {
				    SymbolIndex[] index; 
				    string[][] chunkCache; // Pre-computed chunks by module
				    
				    // Function 1: Search by symbol
				    @Function("Find code definitions and usages")
				    string searchSymbol(string symbolName) {
					        auto matches = index.filter!(s => s.name.contains(symbolName)); 
					        return matches.map!(s => format("%s:%d - %s", s.filePath, s.line, s.name))
					            .join("\n"); 
				} 
				    
				    // Function 2: Get file context
				    @Function("Get specific file content with line range")
				    string getFileContext(string filePath, int startLine, int endLine) {
					        auto lines = readFileLines(filePath); 
					        return lines[startLine..endLine].join("\n"); 
				} 
				    
				    // Function 3: Get dependency chain
				    @Function("Get dependency chain for a symbol")
				    string getDependencyChain(string symbolName) {
					        // Traverse imports/dependencies
					        return buildChain(symbolName, index); 
				} 
			} 
		+/
		
		/+H3: Strategy 2: /+Bold: Smart Chunk Selection Algorithm+/+/
		
		/+
			Structured: CodeChunk[] selectChunksForQuery(string query, SymbolIndex[] index) {
				    // 1. Extract key symbols from query
				    auto querySymbols = extractSymbols(query); 
				    
				    // 2. Find relevant files
				    auto relevantFiles = index
				        .filter!(s => querySymbols.canFind(s.name))
				        .map!(s => s.filePath)
				        .unique; 
				    
				    // 3. For each file, select optimal chunks
				    CodeChunk[] result; 
				    foreach(file; relevantFiles) {
					        auto fileChunks = getFileChunks(file); 
					        
					        // Prioritize chunks containing query symbols
					        fileChunks.sort!(
						(a, b) => 
							            countMatches(a, querySymbols) > countMatches(b, querySymbols)
					); 
					        
					        // Take top chunks until token limit
					        result ~= fileChunks[0..min(3, fileChunks.length)]; 
				}
				    
				    return result; 
			} 
		+/
		
		/+H3: Strategy 3: /+Bold: Progressive Context Loading+/+/
		
		/+
			Structured: class ProgressiveCodebase {
				    // Start with minimal context
				    string initialPrompt = "I have a D codebase. Ask me for specific parts."; 
				    
				    // On each query, load more context
				    string handleQuery(string query)
				{
					        // 1. Check if we have relevant context
					        auto neededSymbols = extractSymbols(query); 
					        auto missingContext = neededSymbols.filter!(s => !inCache(s)); 
					        
					        // 2. Load missing context asynchronously
					        foreach(symbol; missingContext)
					{            loadContext(symbol); }
					        
					        // 3. Send query with current context window
					        return sendToDeepseek(query, currentContext); 
				} 
			} 
		+/
		
		/+H2: Recommended Architecture+/
		
		/+
			Structured: // Main codebase interface for Deepseek
			class DeepseekCodebaseAgent {
				    // 1. Pre-compute lightweight index (100MB -> ~5MB)
				    SymbolIndex[] index; 
				    
				    // 2. Pre-compute file chunks (cached, not loaded)
				    ChunkMap chunks; 
				    
				    // 3. Define functions for Deepseek
				    Function[] functions = [
					        Function("search_symbol", "Find symbol definitions and usages"),
					        Function("get_file_structure", "Get file/function structure"),
					        Function("get_code_context", "Get code around specific lines"),
					        Function("get_import_chain", "Get import/dependency chain")
				]; 
				    
				    // 4. Use function calling to narrow context
				    string processQuery(string userQuery)
				{
					        // Deepseek decides which functions to call
					        auto response = deepseek.chat(
						[
							            Message("system", "You have access to codebase functions..."),
							            Message("user", userQuery)
						], functions
					); 
					        
					        // If Deepseek calls functions, execute them
					        if(response.functionCall)
					{
						            auto context = executeFunction(response.functionCall); 
						            // Send back with context
						            return deepseek.chat(
							[
								                Message("system", "Here's the code context:"),
								                Message("system", context),
								                Message("user", userQuery)
							]
						); 
					}
				} 
			} 
		+/
		
		/+H2: Key Insights+/
		
		/+
			Para: 1. /+Bold: Don't feed the full tree+/ - Use it to build a lightweight index (symbol names, file locations,
			dependencies)
		+/
		
		2. /+Bold: Use function calling+/ - Let Deepseek decide what to look up, like Codex does
		
		3. /+Bold: Cache aggressively+/ - Pre-compute chunks, don't regenerate on each query
		
		4. /+Bold: Progressive loading+/ - Start minimal, expand context based on queries
		
		5. /+Bold: Symbol-aware chunking+/ - Chunk by function/class boundaries, not arbitrary line counts
		
		/+
			Para: The 100MB identifier tree can be compressed to ~2-5MB of useful index data. The actual code
			chunks should be loaded on-demand based on what Deepseek needs for the current task.
		+/
		
		/+
			Para: Would you like me to elaborate on any specific part of this architecture or help implement the
			chunking algorithm for your D codebase?
		+/
		
		/+Note: Usage(prompt_hit: 0, prompt_miss: 255, completion: 1602, HUF: 0.25, price: 100%)+/
	+/
+//+
	Assistant: To build an efficient "code tree navigator" without burning through cash or copying and pasting, you can use a Three-Tier Tree Traversal architecture.Step 1: Map the Project Skeleton (The Directory Tree)Never feed the raw code to the LLM first. Generate an explicit, lightweight tree structure of your codebase using a script or command (tree /F on Windows or find . on Linux). Keep a strict, low-token summary next to each file path.textmy-project/
	│   ├── src/
	│   │   ├── auth.py          # Handles JWT tokens and session validation
	│   │   └── database.py      # SQLite connection pool and migrations
	
	Use code with caution.The 
	
	Agent Loop: You show DeepSeek only this skeleton and ask: "I need to fix a login bug. Look at this map and output only the file paths I need to inspect."Step 2: Extract Class & Function Signatures (The Map)Instead of opening the full 3MB of code, use an abstract syntax tree (AST) parser or a quick script to strip out all the inner logic, leaving only the "skeleton" of the target files.python# DeepSeek only sees this lightweight signature map
	
	class AuthManager:
	    def __init__(self, db_connection): ...
	    def validate_session(self, token: str) -> bool: ...
	    def login_user(self, credentials: dict) -> str: ...
	
	Use code with caution.The 
	
	Agent Loop: DeepSeek reviews the signatures and responds using a standard Function Call: inspect_file_lines(file="src/auth.py", start=10, end=45).Step 3: Targeted Line-Range Inspection (The Execution)Your local script catches DeepSeek’s function call, extracts only lines 10 to 45 of auth.py, and feeds just those 35 lines back to the model.[User Query] ──> 1. Show Project Skeleton ──> [DeepSeek: Picks Files]
	                       │
	                       └──> 2. Show Function Signatures ──> [DeepSeek: Request Lines 10-45]
	                                                                 │
	                                                                 └──> 3. Read 35 Lines of Code
	W
+/