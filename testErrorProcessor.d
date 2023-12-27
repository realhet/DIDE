//@exe
import het, std.regex; 

class FileNameFixer
{
	private File[string] nameMap; 
	File fix(File f)
	{ return nameMap.require(f.fullName, f.actualFile); }  File opCall(File f)
	{ return fix(f); } File opCall(string s)
	{ return fix(s.File); } 
} 

struct DMDMessage
{
	enum Type { unknown, error, warning, deprecation} 
	enum typePrefixes = ["", "Error: ", "Warning: ", "Deprecation: "],
	typeColorCode = ["", "\33\14", "\33\16", "\33\13"],
	typeColor = [clSilver, clRed, clYellow, clAqua]; 
	
	File file; 
	int line, col, mixinLine; 
	Type type; 
	string content, lineSource; 
	
	int count = 1; //occurences of this message in the multi-module build
	
	DMDMessage[] subMessages; //it's a tree
	
	bool opCast(B : bool)() const
	{ return !!file; } 
	
	bool opEquals(in DMDMessage b)const
	{
		return 	file==b.file && 
			line==b.line && 
			col==b.col && 
			mixinLine==b.mixinLine && 
			type==b.type && 
			content==b.content; 
	}  size_t toHash()const
	{
		const h1 = file.hashOf(line); 
		const h2 = type.hashOf(col); 
		const h3 = content.hashOf(mixinLine); 
		return h1.hashOf(h2.hashOf(h3)); 
	} 
	
	bool isSupplemental() const
	{ return type==Type.unknown && content.startsWith(' '); } 
	
	bool isInstantiatedFrom() const
	{
		return 	isSupplemental && 
			(
			content.stripLeft.startsWith("instantiated from here: ") ||
			content.endsWith(" instantiations, -v to show) ...")
		); 
	} 
	
	private void detectType()
	{
		if(type!=Type.unknown) return; 
		
		foreach(i, prefix; typePrefixes)
		if(i && content.startsWith(prefix))
		{
			content = content[prefix.length .. $]; 
			type = cast(Type) i; 
			break; 
		}
	} 
	
	string locationText() const
	{
		if(!file) return ""; 
		return format!"%s%s(%s,%s)"(
			file.fullName, 
			mixinLine ? "-mixin-"~mixinLine.text : "", 
			line, col, 
		); 
	} 
	
	string toString_internal(int level, bool enableColor, string indentStr) const
	{
		auto res = 	indentStr.replicate(level) ~
			withEndingColon(locationText) ~
			(enableColor ? typeColorCode[type] : "") ~ typePrefixes[type] ~
			(enableColor ? "\33\7" : "") ~ content; 
		
		foreach(const ref sm; subMessages)
		res ~= "\n"~sm.toString_internal(level + sm.isInstantiatedFrom, enableColor, indentStr); 
		
		return res; 
	} 
	
	string toString() const
	{ return toString_internal(0, true, "  "); } 
	
	
	private static
	{
		static withEndingColon(string s)
		{ return s=="" ? "" : s~": "; }  static withStartingSpace(string s)
		{ return s=="" ? "" : " "~s; } 
		
		int[] findQuotePairIndices(string s)
		{
			int[] indices; 
			foreach(i, char ch; s) if(ch=='`') indices ~= i.to!int; 
			
			if(indices.length & 1)
			{
				indices = indices.remove(max(indices.length.to!int - 2, 0)); 
				//it removes the second rightmost element. The leftmost and the rightmost are always valid.
			}
			return indices; 
		} 
		
		string toInnerDComment(string msg)
		{
			//break up DComment tokens in original message
			msg = msg.replace("/+", "/ +").replace("+/", "+ /"); 
			
			//locate all the code snippets inside `` and surround them with / +Code: ... + /
			const indices = findQuotePairIndices(msg); 
			bool opening = false; 
			foreach_reverse(i; indices)
			{
				const 	left = msg[0 .. i],
					right = msg[i+1 .. $]; 
				
				auto separ = opening ? "/+Code: " :"+/"; 
				if(left.endsWith(separ[1])) separ = ' ' ~ separ; //Not to produce "/+/" or "+/+"
				
				msg = left ~ separ ~ right; 
				opening = !opening; 
			}
			
			if(msg.endsWith('/')) msg ~= ' '; //Not to produce "/+/"
			
			//find filenames and transform them into / + $DIDE_LOC ... + /
			
			static rxCodeLocation = ctRegex!(`[a-z]:\\[a-z0-9_\.\-\\!#$%^@~]+.d(-mixin-[0-9]+)?\([0-9]+,[0-9]+\)`, `gim`); 
			//Note: This filename parser only handles English letters.
			
			auto fileNames = msg.matchAll(rxCodeLocation).map!"a[0]".array; 
			foreach(fn; fileNames.sort.uniq)
			{
				msg = msg.replace(fn, "/+$DIDE_LOC " ~ fn ~ "+/"); 
				//Note: The filenames MUST be correct names.
			}
			
			return msg; 
		} 
	} 
	
	
	private string sourceText_internal(int level=0) const
	{
		auto res = 	"\t".replicate(level) ~
			typePrefixes[type] ~
			content.stripLeft ~
			withStartingSpace(locationText); 
		
		foreach(const ref sm; subMessages)
		res ~= "\n"~sm.sourceText_internal(level + sm.isInstantiatedFrom); 
		
		return res; 
	} 
	
	string sourceText() const
	{ return "/+\n" ~ toInnerDComment(sourceText_internal) ~ "\n+/"; } 
} 

struct DMDMessages
{
	alias messages this; 
	
	DMDMessage[] messages; 
	string[][File] pragmas; 
	
	//internal state
	private
	{
		size_t[size_t] messageMap; 
		File actSourceFile; 
		DMDMessage* parentMessage; 
		FileNameFixer fileNameFixer; 
	}  void dump()
	{
		void bar() { "-".replicate(80).print; } 
		messages.each!((m){ m.print; bar; }); 
		pragmas.keys.sort.each!(
			(k){
				print(k.fullName, ": Pragma messages:"); 
				pragmas[k].each!((a){ print(a); }); bar; 
			}
		); 
	} 
	
	string sourceText()
	{ return messages.map!"a.sourceText".join("\n"); } 
	
	auto processDMDOutput(string input)
	{
		if(!fileNameFixer) fileNameFixer = new FileNameFixer; 
		
		static decodeColumnMarker(string s)
		{
			return (
				s.endsWith('^') &&(
					s.length==1 || 
					s[0..$-1].map!"a==' '".all
				)
			) ? s.length.to!int : 0; 
		} 
		
		DMDMessage decodeDMDMessage(string s)
		{
			enum rx = ctRegex!`^(\w:\\[\w\\ \-.,]+.d)(-mixin-([0-9]+))?\(([0-9]+),([0-9]+)\): (.*)`; 
			DMDMessage res; 
			auto m = matchFirst(s, rx); 
			if(!m.empty)
			{
				with(res)
				{
					file = fileNameFixer(m[1]); 
					mixinLine = m[3].to!int.ifThrown(0); 
					line = m[4].to!int.ifThrown(0); 
					col = m[5].to!int.ifThrown(0); 
					content = m[6]; 
					detectType; 
				}
			}
			return res; 
		} 
		
		File decodeFileMarker(string line)
		{
			enum rx = ctRegex!`^(\w:\\[\w\\ \-.,]+.d): COMPILER OUTPUT:$`; 
			auto m = matchFirst(line, rx); 
			return m.empty ? File.init : fileNameFixer(m[1]); 
		} 
		
		DMDMessage fetchDMDMessage(ref string[] lines)
		{
			auto msg = decodeDMDMessage(lines.front); 
			if(msg)
			{
				int endIdx; 
				foreach(i; 1 .. lines.length.to!int)
				{
					if(decodeColumnMarker(lines[i])==msg.col)
					{ endIdx = i; break; }
					if(decodeDMDMessage(lines[i])) break; 
					if(decodeFileMarker(lines[i])) break; 
				}
				
				if(endIdx>=2 /+Note: endIdx==1 is invalid, that's  the cited line.+/)
				{
					lines.fetchFront; //first line of a multiline message
					foreach(i; 1..endIdx-1)
					if(lines.length)
					msg.content ~= "\n"~lines.fetchFront; 
					msg.lineSource = lines.fetchFront; 
					lines.fetchFront; //skip the marker line
				}
				else
				{
					lines.fetchFront; //slingle line message
				}
			}
			return msg; 
		} 
		
		auto lines = input.splitLines; 
		
		while(lines.length)
		{
			if(auto msg = fetchDMDMessage(lines))
			{
				if(msg.isSupplemental)
				{
					if(parentMessage)
					{
						auto idx = parentMessage.subMessages.countUntil(msg); 
						if(idx>=0)
						{
							parentMessage = &parentMessage.subMessages[idx]; 
							parentMessage.count++; 
						}
						else
						{
							idx = parentMessage.subMessages.length; 
							parentMessage.subMessages ~= msg; 
							parentMessage = &parentMessage.subMessages[idx]; 
						}
					}
					else
					WARN("No parent message for supplemental message:", msg); 
				}
				else
				{
					const hash = msg.hashOf; 
					if(auto idx = hash in messageMap)
					{
						messages[*idx].count++; 
						parentMessage = &messages[*idx]; 
					}
					else
					{
						const idx = messages.length; 
						messages ~= msg; 
						messageMap[hash] = idx; 
						parentMessage = &messages[idx]; 
					}
				}
			}
			else if(auto f = decodeFileMarker(lines.front))
			{
				lines.popFront; 
				actSourceFile = fileNameFixer(f); 
			}
			else
			{ pragmas[actSourceFile] ~= lines.fetchFront; }
		}
		
		//adjust pragma messages
		foreach(f; pragmas.keys.sort)
		{
			auto list = pragmas[f]; 
			
			while(list.length && list.front.empty) list.popFront; 
			while(list.length && list.back.empty) list.popBack; 
			
			if(list.empty)
			pragmas.remove(f); 
			else
			pragmas[f] = list; 
		}
	} 
	
} 



void run()
{
	DMDMessages msgs; 
	msgs.processDMDOutput(`c:\D\projects\DIDE\errorDB\$output.txt`.File.readStr); 
	msgs.dump; 
	msgs.sourceText.print; 
} 



void main() { console(&run); } 