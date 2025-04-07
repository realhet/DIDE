module dideai;    

import het; 

class AiChat
{
	mixin SmartChild!(q{@PARENT AiModel model}); 
	import std.json; 
	import std.net.curl : HTTP; 
	
	enum roleSystem 	= "system"	,
	roleUser 	= "user"	,
	roleAssistant 	= "assistant"	; 
	
	struct Message
	{
		string role/+system, user, assistant+/; 
		string content; 
	} 
	
	struct Query
	{
		Message[] messages; 
		string model; 
		float temperature = 1.0; 
		bool stream; 
	} 
	
	protected
	{
		Query query; 
		string apiUrl, apiKey; 
		SSQueue!string msgQueue; 	
		int incomingMessageIdx; 
		bool workerPending; 
		string buffer; 
	} 
	
	void _construct()
	{}  void _destruct()
	{ stop; } 
	
	
	@property
	{
		bool running() const => workerPending; 
		const messages() => query.messages[max(1, $)..$]; 
	} 
	
	
	enum Event { text, error, warning, done } 
	
	void printEvent(Event event, string s)
	{
		final switch(event)
		{
			case Event.text: 	write(s); 	break; 
			case Event.error: 	print(EgaColor.ltRed("\nError: "~s)); 	break; 
			case Event.warning: 	print(EgaColor.yellow("\nWarning: "~s)); 	break; 
			case Event.done: 	print(EgaColor.ltGreen("\nDone: "~s)); 	break; 
		}
	} 
	
	static private void worker(shared AiChat _chat)
	{
		/+this is where the blocking CURL HTTP client runs.+/
		auto chat = cast()_chat; 
		if(!chat || !chat.incomingMessageIdx) return; 
		
		scope(exit) chat.workerPending = false/+This is the idle state+/; 
		
		//prepare data
		auto 	header 	= [
			"Content-Type"	: "application/json",
			"Authorization"	: "Bearer "~tea_dec(chat.apiKey, "apiKey")
		],
			msg 	= chat.query.toJson(true); 
		string[string] responseHeader; 
		
		//prepare curl
		auto http = HTTP(); 
		foreach(k, v; header) http.addRequestHeader(k, v); 
		http.method 	= HTTP.Method.post,
		http.url 	= chat.apiUrl,
		http.onSend 	= ((void[] data) {
			auto m = cast(void[]) msg; 
			size_t length = m.length > data.length ? data.length : m.length; 
			if(length == 0) return 0; 
			data[0 .. length] = m[0 .. length]; 
			msg = msg[length..$]; 
			return length; 
		}),
		http.onReceiveHeader 	= ((in char[] key, in char[] value) { responseHeader[key.idup] = value.idup; }),
		http.onReceive 	= ((ubyte[] data) {
			if(!chat.workerPending)
			{
				enum CURL_READFUNC_ABORT = 0x10000000; 
				return CURL_READFUNC_ABORT; 
			}
			
			chat.msgQueue.put((cast(string)(data.idup))); 
			return data.length; 
		}); 
		
		http.perform(No.throwOnError); 
		
		if(!mixin(界3(q{200},q{http.statusLine.code},q{299})))
		{ chat.msgQueue.put(i"\nerror: $(http.statusLine.code) $(http.statusLine.reason)\n\n".text); }
	} 
	struct StreamDataEvent
	{
		//string id; //a guid.
		string object; //must be "chat.completion.chunk"
		//uint created; //unix timestamp
		//string model; //""
		//string system_fingerprint; //"fp_3a5770e1b4_prod"
		
		struct Choice
		{
			//int index; // always 0
			struct MessageDelta
			{
				//string role; //"assistant"  only the first data event has this.
				string content; 
			} 
			MessageDelta delta; 
			//logprobs:null,
			string finish_reason; //stop, length, function call, content filter
		} 
		Choice[] choices; 
		
		struct Usage
		{
			int 	prompt_tokens, 
				completion_tokens; 
			struct Details
			{ int cached_tokens; } 
			Details prompt_tokens_details; 
			
			@property cached_prompt_tokens() const 
			=> prompt_tokens_details.cached_tokens; 
			@property total_tokens() const 
			=> prompt_tokens + completion_tokens; 
			
			string toString() const
			{
				const 	st 	= now.localSystemTime, 
					hour	= st.wHour + st.wMinute/60.0,
					scale 	= ((mixin(界3(q{1.5},q{hour},q{17.5})))?(1.0/+Note: normal+/):(0.5/+Note: discount+/)); 
				//Todo: model dependent prices.  this is chat only
				return i"Usage(prompt_hit: $(cached_prompt_tokens), ".text~
				i"prompt_miss: $(prompt_tokens), ".text~
				i"completion: $(completion_tokens), ".text~
				format!"HUF: %.2f, "
				(
					(
						cached_prompt_tokens	*0.07*scale+
						(prompt_tokens-cached_prompt_tokens)	*0.27*scale+
						completion_tokens	*1.10*scale
					)
					/ 1e6 * 380 /+Todo: more accurate usd to huf+/
				)~
				format!"price: %3d%%)"((scale*100).iround); 
			} 
		} 
		Usage usage; 
	} 
	
	void ask(Message[] messages)
	{
		if(running) return; 
		if(messages.empty) return; 
		
		//Refresh query parameters.
		apiUrl = model.apiUrl; 
		apiKey = model.apiKey; 
		query.model = model.model; 
		query.stream = true; 
		query.temperature = model.temperature; 
		query.messages = messages; 
		
		//Alloc reply message for "assistant" role
		incomingMessageIdx = query.messages.length.to!int; 
		query.messages ~= Message(roleAssistant, ""); 
		
		//Create safeQueue if needed
		if(!msgQueue) msgQueue = new typeof(msgQueue); 
		
		workerPending = true; buffer = ""; 
		spawn(&worker, cast(shared)this); 
	} 
	
	void ask(string[][] messages)
	{
		auto m = messages.map!((a)=>(Message(a.get(0), a.get(1)))).array; 
		
		foreach(a; m)
		enforce(
			a.role.among(roleUser, roleAssistant, roleSystem), 
			i"Invalid Ai role: $(a.role.quoted)".text
		); 
		
		const hasSystem = m.any!((a)=>(a.role==roleSystem)); 
		if(!hasSystem) m = Message(roleSystem, model.system) ~ m; 
		
		ask(m); 
	} 
	
	///this is continuing the current chat
	void ask(string prompt)
	{
		if(running) return; 
		if(prompt.strip=="") return; 
		
		//First message is always from the "system" role
		if(query.messages.empty) query.messages.length = 1; 
		query.messages[0] = Message(roleSystem, model.system); 
		
		//Append current message
		query.messages ~= Message(roleUser, prompt); 
		
		ask(query.messages); 
	} 
	
	void stop()
	{ workerPending = false; } 
	
	
	bool update(void delegate(Event, string) onEvent=null)
	{
		if(onEvent is null) onEvent = &printEvent; 
		
		bool res; 
		
		void processEvent(ref Message message, string event)
		{
			res = true/+there was a change+/; 
			
			event = event.strip; 
			
			bool TRY(string prefix, bool doStrip = true)
			{
				if(event.startsWith(prefix))
				{
					if(doStrip) event = event[prefix.length..$].strip; 
					return true; 
				}
				return false; 
			} 
			if(TRY("data: "))
			{
				if(event=="[DONE]")
				{/+redundant.  finish_reason is enough.+/}
				else if(event.startsWith('{') && event.endsWith('}'))
				{
					StreamDataEvent a; 
					a.fromJson(event, "AIStreamData", ErrorHandling.warn); 
					if(a.choices.length)
					{
						onEvent(Event.text, a.choices[0].delta.content); 
						switch(a.choices[0].finish_reason)
						{
							case "stop": 	{ onEvent(Event.done, a.usage.text); }break; 
							case "length": 	{/+Todo:+/}break; 
							case "function call": 	{/+Todo:+/}break; 
							case "content filter": 	{/+Todo:+/}break; 
							default: 
						}
					}
				}
			}
			else if(TRY(`{"error":`, false))
			{ onEvent(Event.error, event/+Todo: better format these messages+/); }
			else if(TRY("error: "))
			{ onEvent(Event.error, event/+Todo: better format these messages+/); }
			else
			{ onEvent(Event.warning, event); }
		} 
		
		if(msgQueue) foreach(a; msgQueue.fetchAll) { buffer ~= a; }
		
		if(incomingMessageIdx && incomingMessageIdx.inRange(query.messages))
		{
			loop: while(1)
			{
				static foreach(separ; ["\r\n\r\n", "\n\n"])
				{
					{
						const i = buffer.byChar.indexOf(separ); 
						if(i>=0) {
							processEvent(query.messages[incomingMessageIdx], buffer[0..i]); 
							buffer = buffer[i+separ.length..$]; 
							continue loop; 
						}
					}
				}
				break loop; 
			}
		}
		
		return res /+true: messages updated.+/; 
	} 
	
} 
class AiModel
{
	mixin SmartParent!(
		q{
			@STORED string 	apiUrl,
			@STORED string 	model,
			@STORED string 	system 	= "You are a helpful assistant."	,
			@STORED float 	temperature 	= .625	,
			@STORED string 	apiKey 	= ""
		}
	); 
	
	void _construct()
	{}  void _destruct()
	{} 
	
	auto newChat()
	{ return new AiChat(this); } 
	
	///This is the blocking version.  Use newChat.ask() for background version.
	string ask(T)(T prompt)
	{
		if(prompt.empty) return ""; 
		
		auto c = newChat; c.ask(prompt); 
		do { c.update; sleep(15); }while(c.running); 
		c.update/+fetch all remaining parts+/; 
		
		if(!c.query.messages.empty && c.query.messages.back.role==AiChat.roleAssistant)
		return c.query.messages.back.content; 
		return "Unknwon error."; 
	} 
} 

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