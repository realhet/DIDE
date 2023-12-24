//@exe
import het; 

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
	
	string toString_internal(int level=0) const
	{
		auto res = format	!"%s%s%s(%d,%d): %s"
		(
			"  ".replicate(level),
			file.fullName, 
			mixinLine ? "-mixin-"~mixinLine.text : "", 
			line, col, 
			typeColorCode[type]~typePrefixes[type]~"\33\7"~content
		); 
		
		foreach(const ref sm; subMessages)
		res ~= "\n"~sm.toString_internal(level+1); 
		
		return res; 
	} 
	
	string toString() const
	{ return toString_internal; } 
	
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
} 

class FileNameFixer
{
	private File[string] nameMap; 
	File fix(File f)
	{ return nameMap.require(f.fullName, f.actualFile); }  File opCall(File f)
	{ return fix(f); } File opCall(string s)
	{ return fix(s.File); } 
} 

auto processDMDOutput(string input, FileNameFixer fileNameFixer = null)
{
	import std.regex; 
	
	if(!fileNameFixer) fileNameFixer = new FileNameFixer; 
	
	static decodeColumnMarker(string s)
	{ return (s.endsWith('^') &&(s.length==1 || s[0..$-1].map!"a==' '".all)) ? s.length.to!int : 0; } 
	
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
	
	auto lines = input.splitLines; 
	
	DMDMessage[] messages; 
	size_t[size_t] messageMap; 
	string[][File] pragmas; 
	
	File actSourceFile; 
	
	DMDMessage* parentMessage; 
	
	while(lines.length)
	{
		if(auto msg = decodeDMDMessage(lines.front))
		{
			//find the end of this message
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
	
	messages.each!print; 
	
	if(1)
	foreach(f; pragmas.keys.sort)
	{
		auto list = pragmas[f]; 
		
		while(list.length && list.front.empty) list.popFront; 
		while(list.length && list.back.empty) list.popBack; 
		
		pragmas[f] = list; 
		
		if(list.length)
		{
			print("Pragmas: ", f); 
			list.each!print; 
		}
	}
} 

void run()
{ `c:\D\projects\DIDE\errorDB\$output.txt`.File.readStr.processDMDOutput; } 



void main() { console(&run); } 