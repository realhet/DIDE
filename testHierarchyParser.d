//@exe
//@debug

import het.utils;

immutable ubyte[16] importantChars = [	0x00, 0x0A, 0x0D, 0x1A, 0x22, 0x23, 0x27, 0x28,
	0x29, 0x2D, 0x5B, 0x5D, 0x60, 0x7B, 0x7D, 0xE2];

immutable bool[256] importantChadMap = (){ bool[256] b; foreach(i; importantChars) b[i]=true; return b; }();

bool isImportantChar(char ch){
	enum ver = 0;
	const i = cast(ubyte)ch;
	return ver==0 ? importantChars.canFind(b) : importantCharMap[b];
}

immutable  testSource = q{
  /*cComment*//+dComment/+nested dComment3+/+///slashComment
};

auto splitSource(string sourceText){
	static struct SourceSplitterRange{
		private string s;
		private size_t actLength;
		@property empty(){ return s.empty; }
		
		@property string front(){ 
			
			auto act = "";
			actLength = act.length;
			return act;
		}
		
		void popFront(){
			if(!actLength) cast(void)front;
			s = s[actLength..$];
			actLength = 0;
		}
	}
	
	return SourceSplitterRange(sourceText);
}


struct StructureNode{
	StructureNode[] subNodes;
	string data;  //type specific data
	uint line, column;
	uint lParam;
	ushort wParam;
	Type type;          enum Type : ubyte { plain, cComment, dComment, slashComment }
	ubyte depth;
	
	this(string sourceText){
		"//", "/*", "/+"
	}

	
	
	string sourceText(){
		final switch(type){
			case(Type.plain):	return data;
			case(Type.cComment):	return "/*"~data~"*/";
			case(Type.slashComment):	return "//"~data~"\n";
			case(Type.dComment):	return "/+"~data~subnodes.map!sourceText.join~"+/";
		}
	}
	

} //48

pragma(msg, StructureNode.sizeof);

void main(){ console({
  print("Hello");
});}