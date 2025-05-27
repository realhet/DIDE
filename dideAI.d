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
				"https://api.deepseek.com/v1/chat/completions", "deepseek-chat", 
				`You are a helpful assistant.
I don't want you to reformat my code, keep all whitespace as is.
Use tab for indentation!
For multiline blocks like {} and comments /+ +/, put the opening and closing symbols into their own lines.
Use higher level DLang functional constructs when possible: ranges, etc.
Use GLSL-like vector/matrix operations, the user's framework supports that.
Technologies preferred: Win32 64bit platform, OpenGL GLSL for graphics, Vulkan GLSL for compute.`
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
								{ seekToEnd; row = cr.codeColumn.rows[cr.pos.y]; } accessLastRow; 
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