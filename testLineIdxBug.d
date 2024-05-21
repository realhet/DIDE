//@exe

import het; 

string 求(string op, string low, string high, string expr)
{
	static fetchType(ref string id)
	{
		string type; 
		if(!id.isDLangIdentifier)
		{
			auto parts = id.split(" "); 
			auto id2 = parts.back; 
			type = id[0..$-id2.length]; 
			id = id2; 
		}
		return type; 
	}  static fetchStep(ref string src)
	{
		string step; 
		auto parts = src.splitDLang(","); 
		if(parts.length == 2)
		{
			step = parts[1]; 
			src = parts[0]; 
		}
		return step; 
	} 
	static fetchInclusivity1(ref string src)
	{
		if(src.startsWith('='))
		{ src = src[1..$].stripLeft; return true; }return false; 
	} 
	static fetchInclusivity2(ref string src)/+Note: < or <=   default <=+/
	{
		if(src.startsWith("<"))
		{ src = src[1..$]; return fetchInclusivity1(src); }return true; 
	} 
	
	static string formatCode(
		string type, string id,
		string start, bool includeStart, string end, bool includeEnd, 
		string step, string expr, string op
	)
	{
		if(step=="") step = "1"; 
		static foreach(a; AliasSeq!(start, end, step)) a = "("~a~")"; 
		if(!includeStart) start ~= "+"~step; 
		return format	!"(iota%s(%s,%s,%s).map!((%s)=>(%s)).%s)"
			(
			includeEnd ? "_closed" : "", 
			start, end, step, 
			strip(type~' '~id), expr, op
		); 
	} 
	
	auto parts = low.splitDLang("<"); 
	if(parts.length==3 /+Note: min <= var <= max ,step+/)
	{
		auto 	start 	= parts[0],
			id 	= parts[1],
			end 	= parts[2],
			includeStart 	= fetchInclusivity1(id),
			includeEnd 	= fetchInclusivity1(end),
			step	= fetchStep(end),
			type	= fetchType(id); 
		//also include 'high' to generate an error.
		high = high.splitDLang("")[0]; 
		if(high!="") high = ","~high; 
		return formatCode(type, id, start, includeStart, end, includeEnd, step~high, expr, op); 
	}
	
	parts = low.splitDLang("="); 
	if(parts.length==2 /+Note: var=min, step  |  <=max+/)
	{
		auto 	id	= parts[0],
			type	= fetchType(id),
			start	= parts[1],
			step	= fetchStep(start),
			end	= removeDLangComments(high),
			includeStart 	= true,
			includeEnd	= fetchInclusivity2(end); 
		return formatCode(type, id, start, includeStart, end, includeEnd, step, expr, op); 
	}
	
	{
		/+Note: If non of the above,  ->  it is a .map() on a range.+/
		auto 	elements	= removeDLangComments(high),
			type_and_id 	= removeDLangComments(low); 
		
		/+Add optional [] if there is more , separated items.+/
		if(elements.splitDLang(",").length>=2) elements = '['~elements~']'; 
		
		//Todo: a,b..c,d  felsorolas.
		
		return format	!"((%s).map!((%s)=>(%s)).%s)"	(elements, type_and_id, expr, op); 
	}
	
	//throw new Exception("Invalid sigma-operation operands."); 
} 

string 求sum(string low, string high, string expr)
{ return 求("sum", low, high, expr); } 

string 求product(string low, string high, string expr)
{ return 求("product", low, high, expr); } 



void main()
{
	(mixin(求sum(q{1<=float i<=3},q{},q{i^^2/3}))).print; 
	print((mixin(求sum(q{float i=10, +2},q{14},q{1})))); 
	(mixin(求prod(q{i},q{2, 4, 5},q{i}))).print; 
} 