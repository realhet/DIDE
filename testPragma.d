//@exe
//@debug

import het; 

template T2(string FILE=__FILE__, size_t LINE=__LINE__) { template T2(A...) { alias T2=T1!(FILE,LINE,A); } } 
template T1(string FILE=__FILE__, size_t LINE=__LINE__,A...) { enum T1 = FILE ~ LINE.text ~ A.text; } 
alias t2=T2!(); 
pragma(msg, t2!(i"Hello $(__LINE__) $("World") $("World") $("World")")); 
pragma(msg, t2!(i"Hello $(__LINE__) $("World") $("World")")); 


//template t2 captures the line of the alias, not the pragma.

/*
	import std;
	void main(){
		foreach(i;0..8){
			"alias a".write;
			i.write;
			"=void,".write;
	}}
*/
template T3(alias a0=void,alias a1=void,alias a2=void,alias a3=void,alias a4=void,alias a5=void,alias a6=void,alias a7=void,string FILE=__FILE__, size_t LINE=__LINE__)
{
	alias A=AliasSeq!(); 
	static foreach(int I;0..8) {
		alias B(int J:I)=mixin("a"~I.stringof); 
		static if(! is(B!I==void)) { A=AliasSeq!(A,B!I); }
	}
	alias T3=T1!(FILE,LINE,A); 
} 

pragma(msg, T3!(i"goodbye $("World") $(__LINE__)")); 
pragma(msg, T3!(i"goodbye $("World") $(__LINE__)")); 

//T3 goodbye: The 8 slots are ony enough for 2 $() injections.


template pack(A...) { alias unpack=A; } 
alias T4(alias A,string FILE=__FILE__, size_t LINE=__LINE__)=T1!(FILE,LINE,A.unpack); 
pragma(msg, T4!(pack!(i"farwell $("World")"))); 
pragma(msg, T4!(pack!(i"farwell $("World"~__LINE__.text) $("World")"))); 
pragma(msg, T4!(pack!(i"farwell $("World"~__LINE__.text) $("World") $("World")"))); 
pragma(msg, T4!(pack!(i"farwell $("World"~__LINE__.text) $("World") $("World") $("World")"))); 
pragma(msg, T4!(pack!(i"farwell $("World"~__LINE__.text) $("World") $("World") $("World") $("World")"))); 
pragma(msg, T4!(pack!(i"farwell $("World"~__LINE__.text) $("World") $("World") $("World") $("World") $("World") $("World") $("World") $("World") $("World") $("World")"))); 

void test()
{} 
void main() { noconsole({ test; }); } 