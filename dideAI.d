module dideai; 

import het.ai; 
import didebase; 
import didenode: CodeComment; 
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
	
	void update()
	{
		//Todo: check if activeAiNode was deleted...
		CodeComment[] toRemove; 
		foreach(node, chat; pendingAiChatByAiAssistantNode)
		{
			//Todo: check if the node was deleted...
			
			with(chat)
			{
				update(
					(Event event, string s)
					{
						final switch(event)
						{
							case Event.text: 	textSelections.preserve
							(
								{
									textSelections.items = node.content.endSelection(true); 
									pasteText(s); 
								}
							); 	break; 
							case Event.error: 	print(EgaColor.ltRed("\nError: "~s)); 	break; 
							case Event.warning: 	print(EgaColor.yellow("\nWarning: "~s)); 	break; 
							case Event.done: 	print(EgaColor.ltGreen("\nDone: "~s)); 	break; 
						}
					}
				); 
				if(!running) toRemove ~= node; 
			}
		}
		
		foreach(node; toRemove)
		{
			auto chat = pendingAiChatByAiAssistantNode[node]; 
			pendingAiChatByAiAssistantNode.remove(node); 
			im.flashInfo("AiChat removed: "~chat.identityStr); 
		}
	} 
	
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
	
	void launch()
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
For newly generated code use TAB to indent.
For multiline blocks like {} and comments /+ +/, put the opening and closing symbols into their own lines.
Use higher level DLang functional constructs when possible: ranges, etc.
Use GLSL-like vector/matrix operations, the user's framework supports that.
Technologies preferred: Win32 64bit platform, OpenGL GLSL for graphics, Vulkan GLSL for compute.

When communicating in expressions or one line code, use this form: /+Code: code+/
When inserting multiline code, use form:
/+Code:
	multiline
	source code goes here
+/

Put yout paragraphs into /+Note: text goes here+/ blocks!
You can do multiline paragrphs like this:
/+Note:
	line1
	line2
+/

Put bullet paragraphs into /+Bullet: text goes here+/ blocks!
It has a multiline variant too:
/+Bullet:
	line1
	line2
+/
Use one bullet paragraph for each bullet item!

Word wrap every paragraphs and bullet paragraphs to around 100 characters!

Put bold text inside /+Bold: text goes here+/ blocks! 

Put italic text inside /+Italic: text goes here+/ blocks! 

Put heading text inside /+Hn: text goes here+/ blocks, where n is in range 1 to 6! 

Sometimes I will give or ask the results in a "table", this is my table format, please preserve this exact format and whitespaces when you are communicating with it: `
				~"\n/+Code:\n"
				~q{
					(表([
						[q{/+Note: Header+/},q{/+Note: 2nd column+/},q{/+Note: 3rd column+/}],
						[q{normal cell},q{"string cell"},q{/+comment cell+/}],
						[q{/+If the whole row is a comment, it's ignored+/}],
						[],
						[q{/+also empty rows are ignored, they are just there for formatting+/}],
						[q{
							another cell 1+1=2
							/+anything D syntax can go here.+/
						},q{`Another string.
This one is multiline and without escapes.`}],
					]))
				}.splitLines[1..$-1].join('\n').outdent
				~"\n+/\n"
			); 
			aiModel.apiKey = File(appPath, "a.a").readStr; 
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
			chat.ask(messages); 
			pendingAiChatByAiAssistantNode[assistantNode] = chat; 
			
			im.flashInfo("AiChat launched: "~chat.identityStr); 
		}
	} 
} 