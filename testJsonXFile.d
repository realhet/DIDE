//@exe
//@debug

import het, het.parser; 

alias JSONScanner = StructureScanner_JSON.scanner; 
struct StructureScanner_JSON
{
	mixin((
		(表([
			[q{/+Note: Enter+/},q{/+Note: State+/},q{/+Note: Transitions+/},q{/+Note: Leave+/},q{/+Note: EOF handling+/}],
			[q{"{"},q{object},q{Error("] )") ~ EntryTransitions ~ Trans(": ,", object)},q{"}"},q{}],
			[q{"["},q{array},q{Error(") }") ~ EntryTransitions ~ Trans(",", array)},q{"]"},q{}],
			[q{"'"},q{sqString},q{Ignore(`\\ \'`)},q{`'`},q{}],
			[q{`"`},q{dqString},q{Ignore(`\\ \"`)},q{`"`},q{}],
		]))
	) .GEN!q{GEN_StructureScanner(q{enum NewLineTokens 	= "\r\n \r \n"; })}); 
} 

void parseJson(S)(S scanner)
{
	void skipWhite() { while(!scanner.empty && scanner.front.src.all!isWhite) scanner.popFront; } 
	
	skipWhite; if(scanner.empty || scanner.front.src.among("]", "}")) return; 
	
	if(scanner.front.src==`"`)
	{
		scanner.popFront; 
		if(!scanner.empty && scanner.front.op==StructureScanner.ScanOp.content) { print("STR:", scanner.front.src); scanner.popFront; }
		enforce(!scanner.empty && scanner.front.src==`"`, "Closing `\"` expected."); scanner.popFront; 
		return; 
	}
	if(scanner.front.src==`'`)
	{
		scanner.popFront; 
		if(!scanner.empty && scanner.front.op==StructureScanner.ScanOp.content) { print("STR:", scanner.front.src); scanner.popFront; }
		enforce(!scanner.empty && scanner.front.src==`'`, "Closing `\'` expected."); scanner.popFront; 
		return; 
	}
	
	if(scanner.front.src=="[")
	{
		scanner.popFront; 
		print("ARRAY BEGIN"); 
		again: 
			skipWhite; enforce(!scanner.empty, "Unexpected end in `[`"); 
			parseJson(scanner); 
			skipWhite; enforce(!scanner.empty, "Unexpected end in `[`"); 
		if(scanner.front.src==",") { scanner.popFront; goto again; }
		enforce(scanner.front.src=="]", "`]` expected"); scanner.popFront; 
		print("ARRAY END"); 
		return; 
	}if(scanner.front.src=="{")
	{
		scanner.popFront; 
		
		print("OBJECT BEGIN"); 
		again2: 
			skipWhite; enforce(!scanner.empty, "Unexpected end in `{`"); 
			parseJson(scanner); 
			skipWhite; enforce(!scanner.empty, "Unexpected end in `{`"); 
		if(scanner.front.src.among(",", ":")) { scanner.popFront; goto again2; }
		enforce(scanner.front.src=="}", "`}` expected"); scanner.popFront; 
		print("OBJECT END"); 
		return; 
	}
	
	print("VALUE: ", scanner.front.src.strip); 
	scanner.popFront; 
} 


void main()
{ console({ `c:\d\projects\karc\karc.json`.File.readText.JSONScanner.parseJson; }); } 