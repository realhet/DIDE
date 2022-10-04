//@exe
//@debug
///@release

import het.utils, het.structurescanner; 

// STEPScanner ////////////////////////////////////////

/+alias STEPScanner = StructureScanner_STEP.scanner;
struct StructureScanner_STEP{ static:
	mixin StructureScanner;

	enum NewLineTokens	= "\r \n ";
	enum EOFTokens	= "\0";
	enum EOF	= Trans(EOFTokens	, State.unstructured);
	
	enum State : ubyte { // State graph
		/+special system tokens+/ ignore, pop, eof, @Trans("", eof) unstructured, 
		
		@Push("(", structured) @Pop(")") @Push("/*", comment) @Push(`'`, name) @Trans(";", structured) @EOF structured,
		@Pop("*/") @EOF comment,
		@Ignore(`\\ \'`) @Pop("'") @EOF name
	}
}+/


static immutable identifiers = [	"NEXT_ASSEMBLY_USAGE_OCCURRENCE"	,
	"PRODUCT"	,
	"PRODUCT_DEFINITION"	,
	"PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE"	];

enum sortedIdentifiers = identifiers.dup.sort!startsWith.array.join(` `); //sorted by first detection order
//todo: this sorting is not correct: it should only swap the elements that are in conflict with each other and leave the others intact.
//todo: The correct order must be validated in the StructureParser template.

alias STEPScanner = StructureScanner_STEP.scanner;
struct StructureScanner_STEP{ static:
	mixin StructureScanner;
	
	enum NewLineTokens	= "\r \n ";
	enum EOFTokens	= "\0";
	enum EOF	= Trans(EOFTokens	, State.unstructured);
	
	enum State : ubyte { // State graph
		/+special system tokens+/ ignore, pop, eof, @Trans("", eof) unstructured, 
		
		@Push("/*", comment) @Push(`'`, name) @Push("(", bracket) 
		@Trans(sortedIdentifiers, structured)
		@EOF structured,
		
		@Push("/*", comment) @Push(`'`, name) @Push("(", bracket) 
		@Pop(")") @EOF bracket,
		
		@Pop("*/") @EOF comment,
		@Ignore(`\\ \'`) @Pop("'") @EOF name
	}
}

void test_sac(){
	const src = File([`c:\dl\test_123.STEP`, `c:\dl\sac.STEP`][1]).readText;
	T0;
	bool lastOpWasEq;
	auto idMap = assocArray(identifiers, iota(identifiers.length).map!"a+1");
	auto findings = 	src.STEPScanner
		.filter!(a => a.src in idMap)
		.map!(a => a.src.ptr-src.ptr)
		.array;
		
	DT.print;
	readln;
	findings.each!print;
	findings.length.print;
}



			
void main(){ console({ //main() //////////////////////////////////////////////////////////////
	if(1) test_StructureScanner;
	
	if(1) test_sac;
}); }