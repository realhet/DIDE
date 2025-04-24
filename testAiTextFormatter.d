//@exe
//@debug
import het; 

const input = "Here's an example demonstrating the requested formatting:\n\n# Heading 1 Example\n\nThis is a **paragraph** of text showing normal formatting. It contains some *italicized* words and **bold** phrases to demonstrate emphasis.\n\n## Subheading (Heading 2)\n\n- Bullet point 1 with `inline code`\n- Bullet point 2 with *italic*\n- Nested bullets:\n  - Sub-item A\n  - Sub-item B with **bold text**\n\n### Code Examples\n\nSmall one-liner: `auto result = range.map!(x => x*2).array;`\n\nMultiline block:\n\n```\n/+ \n   Compute shader example \n+/ \nlayout(local_size_x = 32) in;\nvoid main() {\n\tvec4 data = texelFetch(inputImage, ivec2(gl_GlobalInvocationID.xy), 0);\n\tdata.rgb = pow(data.rgb, vec3(2.2));\n\timageStore(outputImage, ivec2(gl_GlobalInvocationID.xy), data);\n}\n```\n\n#### Data Table\n\n| Framework | Version | GPU API   |\n|-----------|---------|-----------|\n| Dlang     | 2.104   | OpenGL 4.6|\n| Rust      | 1.75    | Vulkan 1.3|\n\n##### Embedded JSON\n\n```json\n{\n\t\"project\": \"Formatting Demo\",\n\t\"author\": \"Assistant\",\n\t\"features\": [\n\t\t\"headings\",\n\t\t\"code blocks\",\n\t\t\"tables\"\n\t]\n}\n```\n\nFinal paragraph showing that text continues normally after all special formatting elements. Note the preserved whitespace and indentation in code blocks."; 

class AiMarkdownProcessor
{
	int backtickCount, backtickLevel, asteriskCount, asteriskLevel, codeLineIdx; 
	
	
	void onChar(dchar ch)
	{
		if(ch=='\n')
		{ writeln("CR"); }
		else
		{
			write(
				"\34"~
				(
					backtickLevel ? (codeLineIdx>0 ? "\3" : "\2") : 
					asteriskLevel==1 ? "\5" : 
					asteriskLevel==2 ? "\6" : 
					"\10"
				)
				~ch.text~"\34\0"
			); 
		}
	} 
	
	void onFinalizeCode()
	{ write("\33\15[CODE]\33\7"); } 
	
	void process(dchar ch /+must call with a \0 at the very end.+/)
	{
		
		bool processEnterExit(in dchar marker, ref int count, ref int level, void delegate() onExit = null)
		{
			if(ch==marker) { count++; return true; }
			if(count)
			{
				if(level==0)	{/+enter+/level = count; }
				else if(level==count)	{/+leave+/if(onExit) onExit(); level = 0; }
				else	{/+as is+/foreach(i; 0..level) onChar(marker); }
				count=0; 
			}
			return false; 
		} 
		
		if(processEnterExit('`', backtickCount, backtickLevel, { if(codeLineIdx>0) onFinalizeCode(); })) return; 
		if(!backtickLevel) if(processEnterExit('*', asteriskCount, asteriskLevel)) return; 
		
		
		void finalizeLine()
		{
			asteriskCount = 0; asteriskLevel = 0; 
			backtickCount = 0; 
			if(backtickLevel.inRange(1, 2)) { onFinalizeCode(); backtickLevel = 0;  }
			if(backtickLevel) codeLineIdx++; else codeLineIdx = 0; 
		} 
		
		if(ch=='\r') return; 
		if(ch=='\n') { finalizeLine; onChar('\n'); return; }
		if(ch=='\0') { finalizeLine; return; }
		
		onChar(ch); 
	} 
} 


void test()
{
	auto formatter = new AiMarkdownProcessor; 
	mixin(求each(q{ch},q{input},q{formatter.process(ch)})); 
	formatter.process('\0'); 
} 

void main() { console({ test; }); } 