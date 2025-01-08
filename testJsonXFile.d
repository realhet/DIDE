//@exe
//@debug
///@release

version(all)
{
	/+
		ChatGPT query:
		In dlang I have an array of strings.
		The strings contain fully qualified names of an identifier, with the full path, separated by dot '.' character.
		The individual parts can contain a template parameter list after the identifier eg: "id!(1, 2)" These are part of the identifier, this specifies a single path location.
		After the last identifier with optional template parameters, there can be a parameter list, it that particular item is a function. Example: "fun(int param1, string param2) : string"
		Your task is to process the alphabetically ordered input string array with the fully qualified names and produce a hierarchical text output with visual block drawing characters. It should look like the result of the DOS tree command.
	+/
	
	
	import std.regex; 
	
	
	// Structure to represent a node in the hierarchy
	struct TreeNode(T)
	{
		T data; 
		TreeNode[] children; 
		
		this(T data) { this.data = data; } 
		
		void addChild(TreeNode node) { children ~= node; } 
	} 
	
	// Parse a fully qualified name into its components
	string[] parseQualifiedName(string fullyQualifiedName)
	{
		//auto regex = ctRegex!`(?<!\w)([a-zA-Z_][a-zA-Z0-9_]*!(\([^)]*\))?|[a-zA-Z_][a-zA-Z0-9_]*)(\([^)]*\)\s*:\s*[a-zA-Z_][a-zA-Z0-9_]*\s*)?`; 
		//auto regex = ctRegex!`([a-zA-Z_][a-zA-Z0-9_]*!(\\([^)]*\\))?|[a-zA-Z_][a-zA-Z0-9_]*)(\\([^)]*\\)\\s*:\\s*[a-zA-Z_][a-zA-Z0-9_]*|\\([^)]*\\))?`; 
		auto regex = ctRegex!`[a-zA-Z_][a-zA-Z0-9_]*(?:!(\\([^)]*\\)))?(?:\\([^)]*\\))?`; 
		return fullyQualifiedName.matchAll(regex).map!(m => m.hit).array; 
	} 
	
	// Add a fully qualified name to the tree
	void addQualifiedName(ref TreeNode!string root, string[] parts)
	{
		auto current = &root; 
		
		foreach(part; parts) {
			auto child = current.children.find!(c => c.data == part); 
			if(child.empty) {
				current.children ~= TreeNode!string(part); 
				current = &current.children[$ - 1]; 
			}else { current = &child.front; }
		}
	} 
	
	// Generate the hierarchical tree output
	static if(0)
	void printTree(TreeNode!string node, string prefix = "")
	{
		writeln(prefix, node.data); 
		
		foreach(i, child; node.children) {
			string newPrefix = prefix ~ (i == node.children.length - 1 ? "  └─" : "  ├─"); 
			printTree(child, newPrefix); 
		}
		
		/+
			- Thank you! There were some errors, but I was able to fix.  It was DLang specific stuff, I know your knowledge is mainly C++.  Dlang is an exotic language..
			GPT: You're welcome! I'm glad you could resolve the issues—it's always impressive to work with such a niche language like DLang. If you need help fine-tuning or exploring other ideas, just let me know!
			
			- But the result is not perfect:
			root
				 └─com
				 └─	 └─example
				 └─	 └─	 ├─Class!(int, string)
				 └─	 └─	 ├─  └─method(int x, int y) : void
				 └─	 └─	 └─OtherClass
				 └─	 └─	 └─  └─subMethod!(true)
			GPT: Thank you for pointing that out! The issue lies in the incorrect use of block-drawing characters in the tree output. Specifically, the prefixes (├─, └─, etc.) aren't being constructed properly when traversing multiple levels of the tree.
			
			Here's the fixed version of the printTree function that ensures the tree structure renders correctly:
		+/
	} 
	
	// Generate the hierarchical tree output
	void printTree(in TreeNode!string node, string prefix = "", bool isLast = true)
	{
		// Print the current node
		if(node.data != "root") { writeln(prefix ~ (isLast ? "└─ " : "├─ ") ~ node.data); }
		
		// Update the prefix for children
		auto newPrefix = prefix ~ (isLast ? "   " : "│  "); 
		
		foreach(i, child; node.children) { printTree(child, newPrefix, i == node.children.length - 1); }
	} 
	
	void treeFqn(string[] input)
	{
		// Input: Alphabetically sorted array of fully qualified names
		static if(0)
		input = [
			"com.example.Class!(int, string)",
			"com.example.Class!(int, string).method(int x, int y) : void",
			"com.example.OtherClass",
			"com.example.OtherClass.subMethod!(true)"
		]; 
		
		input.each!print; 
		
		// Root of the tree
		auto root = TreeNode!string("root"); 
		
		// Build the tree
		foreach(name; input) {
			auto parts = parseQualifiedName(name); 
			addQualifiedName(root, parts); 
		}
		
		// Print the tree
		printTree(root); 
	} 
}

import het, het.parser; 

class ModuleJson
{
	static struct Item
	{
		string kind, name; 
		
		Item[] parameters, members; 
		string[] storageClass, overrides, selective/+import+/; 
		string protection, base, init_, type, originalType, file, deco, baseDeco, value, defaultValue, default_; 
		int line, char_, endline, endchar, offset; 
		
		void dumpStr(alias pred="true")(ref string[] result, const ref Item item, string path="")
		{
			//if(name=="") return; 
			
			if(unaryFun!pred(item))
			{
				auto p = parameters.map!"a.type~` `~a.name".join(", "); 
				//print(kind.padRight(' ', 20), path~name~((p!="")?("("~p~")"):(""))); 
				result ~= path~name~((p!="")?("("~p~")"):("")); 
			}
			foreach(ref a; members) a.dumpStr!pred(result, a, path~name~"."); 
		} 
	} 
	
	string[] dumpStr(alias pred="true")()
	{
		string[] result; 
		foreach(ref a; items) { a.dumpStr!pred(result, a, ""); }
		return result; 
	} 
	
	File file; 
	Item[] items; 
	
	this(File f)
	{
		this.file=f; 
		items.fromJson(file.readText(true)); 
		//if(items.length && items[0].name=="") items[0].name="__MAIN_MODULE__"; 
	} 
} 


/+
	by kind
	module: name, file
	
+/

/+
	size_t calcMem(ModuleJson[] items)
	{ return Item.sizeof*items.length + items.map!((a)=>(a.members.calcMem + a.parameters.calcMem)).sum; } 
+/

void main()
{
	console(
		{
			//treeFqn; 
			
			static if(0)
			{
				auto m = new ModuleJson(`z:\temp\json.txt`.File); 
				m.dumpStr.sort.array.treeFqn; 
			}
			static if(1)
			foreach(f; ((0)?(listFiles(Path(`c:\d\ldc2\import`), "*.*", "name", Yes.onlyFiles, Yes.recursive).map!"a.file".array):([`c:\d\libs\het\package.d`.File])))
			{
				auto res = execute(["ldc2", "-o-", "-X" ,`--Xf=z:\temp\json.txt`, `-Ic:\d\libs`, f.fullName]); 
				
				if(res.status==0)
				{
					auto m = new ModuleJson(`z:\temp\json.txt`.File); 
					m.dumpStr.sort.array.treeFqn; 
				}
				else print("ERROR:", res.output); 
			}
		}
	); 
} 