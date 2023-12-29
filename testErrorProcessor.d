//@exe
//@debug
import het, buildsys, het.parser, std.regex; 

pragma(msg, "PRAGMA MSG TEST\n2nd line"); 

void run()
{
	DMDMessages msgs; 
	msgs.processDMDOutput(`c:\D\projects\DIDE\errorDB\$output.txt`.File.readStr); 
	msgs.dump; 
	msgs.sourceText.print; 
	
	int* a; 
	print(*a); 
	
} 



void main() { console(&run); } 