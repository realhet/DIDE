//@exe
//@release

import het;

struct DDeclarationRecord{
	string attributes;
	string type;
	string header;
}
DDeclarationRecord[] dDeclarationRecords;


///fun must be: void delegate(char type, dstring token, size_t pos)
void processDLangSentence(alias append)(string str){
	
	static void categorizeDLangChar(dchar ch, ref char s/+state+/){
		if(s=='a'){
			if(!isDLangIdentifierCont(ch)) s = ' ';
		}else if(s=='0'){
			if(!isDLangNumberCont(ch)) s = ' ';
		}else{
			if(isDLangIdentifierStart(ch)) s = 'a';
			else if(isDLangNumberStart(ch)) s = '0';
			else s = ' ';
		}
		//return 'a' for identifiers, '0' for numbers, ' ' for newline. 
		//Otherwise terutn the actual char.
	}
	
	char actState = ' ';
	dstring actWord;
	foreach(idx, dchar ch; str){
		
		//detect words and symbols
		auto lastState = actState;
		bool wordFound = false;
		categorizeDLangChar(ch, actState);
		if(lastState!=actState){
			if(actState!=' ') actWord = "";
			else if(lastState!=' ') wordFound = true;
		}
		if(actState!=' ') actWord ~= ch;
		if(wordFound) append(lastState, actWord.text, idx-actWord.length); //note: no 'else' here!!!
		if(actState==' ') append(actState, ch.text, idx);
	}
	if(actState!=' ') append(actState, actWord.text, str.length-actWord.length);
}


void prettyWrite(string str){
	void append(char type, string s, size_t pos){ 
		switch(type){
			case 'a': write(EgaColor.ltBlue(s)); break;
			case '0': write(EgaColor.ltGreen(s)); break;
			default: write(EgaColor.yellow(s));
		}
	}
	str.processDLangSentence!append;
}

void PrettyText(string str){ with(im){
	void append(char type, string s, size_t pos){ 
		switch(type){
			case 'a': style.fontColor = clBlue; break;
			case '0': style.fontColor = clGreen; break;
			default: style.fontColor = clBlack;
		}
		Text(s);
	}
	
	str.processDLangSentence!append;
}}


string refine(string str, string[] keywords){
	
	bool anyFound;
	string res;
	
	void append(char type, string s, size_t pos){ 
		const match = type=='a' && keywords.canFind(s);
		
		anyFound |= match;

		switch(type){
			case 'a': res ~= match ? " "~s~" " : " ID "; break;
			case '0': res ~= " 0 "; break;
			default: res ~= s.among(" ", "\n") ? " " : s;
		}
	}
	
	str.processDLangSentence!append;
	if(!anyFound) return "";
	
	auto parts = res.split(' ').filter!"a.length".array;
	string res2;
	foreach(p; parts){
		alias chk = isDLangIdentifierCont;
		if(res2.length && chk(res2.back) && chk(p.front)) res2 ~= ' ';
		res2 ~= p;
	}
	
	return res2;
}

enum 	TypeCTors 	= ["const","immutable","inout","shared"],
	StorageClasses 	= ["extern","align","deprecated","static","abstract","final","override","synchronized","auto","scope","nothrow","pure","__gshared","ref","lazy","out"],
	ProtectionAttributes 	= ["private","protected","public","export","package"],
	DLangValues	= ["null","false","true","this","super"],
	BasicTypes	= ["byte","ubyte", "short","ushort", "int","uint", "long","ulong", "float","double","real", "bool", "char","wchar","dchar", "void"],
	PopularAliases	= ["string", "wstring", "dstring", "size_t", "sizediff_t", "ptrdiff_t", "noreturn",
			  "File", "Path", "DateTime", "Time",
			  "Vector",
			  "vec2", "dvec2", "ivec2", "uvec2", "bvec2", "RG",
			  "vec3", "dvec3", "ivec3", "uvec3", "bvec3", "RGB",
			  "vec4", "dvec4", "ivec4", "uvec4", "bvec4", "RGBA",
			  "Matrix",
		    "mat2" , "mat3" , "mat4" , "mat2x3",  "mat2x4",  "mat3x2",  "mat3x4",  "mat4x2",  "mat4x3",
			  "dmat2", "dmat3", "dmat4", "dmat2x3", "dmat2x4", "dmat3x2", "dmat3x4", "dmat4x2", "dmat4x3",
			  "Bounds",
			  "bounds" , "dbounds" , "ibounds" ,
			  "bounds2", "dbounds2", "ibounds2",
			  "bounds3", "dbounds3", "ibounds3"],
	UserSefiniedTypes	= ["alias","enum","interface","struct","class","union","delegate","function"],
	ProgramKeywords	= ["asm","break","case","catch","continue","default","do","else","finally","for","foreach","foreach_reverse","goto",
			  "if","invariant","module","return","switch","template","throw","try","unittest","while","with",
			  "assert","debug","import","mixin","version"],
	SpecialFunctions	= ["cast","pragma","typeid","typeof","__traits","__parameters","__vector"],
	SpecialKeywords	= ["__EOF__","__DATE__","__TIME__","__TIMESTAMP__","__DATETIME__"/+//EXTRA+/,"__VENDOR__","__VERSION__",
		   "__FILE__","__FILE_FULL_PATH__","__MODULE__","__LINE__","__FUNCTION__","__PRETTY_FUNCTION__"],
	Operators	= ["in","is","new"];

class FrmDLangStats: GLWindow { mixin autoCreate;
	
	int[string][string] signatures;;
	string[] keys;
	
	override void onCreate(){
		alias src = dDeclarationRecords;
		src.fromJson(File(`c:\D\projects\DIDE\DLangStatistics\dDeclarationRecords.json`).readText(true));
	
		foreach(a; src){
			auto keywords = 
				//["static", "with", "if", "while", "for", "foreach", "foreach_reverse", "do"]
				TypeCTors~StorageClasses~ProtectionAttributes~"pragma"~ProgramKeywords~["delegate","function","this"]
			;
			auto s = refine(a.header, keywords);
			
			static void takeFromLeft(ref string s, string[] keywords){
				while(1){
					bool any;
					foreach(kw; keywords){
						if(s.startsWith(kw)){ //bug: word boundary
							any = true;
							s = s[kw.length..$].stripLeft;
						}
					}
					if(!any) break;
				}
			}
			
			takeFromLeft(s, [
				//all signatures:	//10610
				/*"final switch(",	//10609
				"switch(",	//10607
				"static if(",	//10420
				"if(",	//10088
				"debug=ID;",	//Debug Specification
				"version=ID;",	//Version Specification*/
				
				/*"debug (",	
				"debug",	
				"version (",	
				"version",	
				"__gshared",	
				"auto",	
				"abstract",	
				"export",	*/
			]);
			
			if(s.length)
				signatures[s][a.header]++;
		}
		
		keys = signatures.keys.sort.array;
	}

	override void onUpdate(){
		view.navigate(!im.wantKeys, !im.wantMouse);
		invalidate;

		with(im){
			theme = "tool";
			Panel(PanelPosition.topLeft, {
				if(keys.length){
					auto keyChunks = keys.chunks(30);
					static int pageIdx;
					Row("Items: ", keys.length.text);
					Row("Page ", { 
						Slider(pageIdx, range(0, keyChunks.length.to!int-1), { width = fh*16; }); 
						IncDec(pageIdx, range(0, keyChunks.length.to!int-1)); 
					});
					foreach(idx, k; keyChunks[pageIdx]){
						if(Btn({ border.width = 0; flags.hAlign = HAlign.left; PrettyText(k.take(64).text); }, genericId(idx))){
							auto list = signatures[k].byKeyValue.array.sort!((a, b) => a.value > b.value).array;
							
							writeln; prettyWrite(k); writeln;
							foreach(a; list){
								write(format!"%6d: "(a.value));
								prettyWrite(a.key);
								writeln;
							}
							
							
							
						}
					}
				}
			});
		}

	}

	override void onPaint(){
		gl.clearColor(clGray); gl.clear(GL_COLOR_BUFFER_BIT);
	}
}