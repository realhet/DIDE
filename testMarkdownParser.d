//@exe
//@debug
//@/release

const example =
"# H1

### Explanation:

1. **MarkdownFormat Enum**: This enum defines 

2. **MarkDownState Struct**: This struct keeps

3. **processMarkdown Function**: This function 

4. **Handling Special Characters**: The function

5. **Finalization**: When the input string ends with `\0`, the function `` ` `` ``` `` ```

```d
d source code;
```

* item1
* item2
	* subitem3
    * subitem4"; 

		class Cell
{} 

class Glyph
{ dchar ch; } 

class CodeComment : Cell
{ CodeColumn content; } 

class CodeRow
{ dchar[] chars; } 

class CodeColumn
{ CodeRow[] rows; } 



struct MarkdownDecoderState(Cursor)
{ dchar lastChar; } 

void processMarkdown(Cursor)(
	string input, 
	Cursor delegate() getCursor,
	void delegate(dchar) put,
	void delegate(MarkdownFormat, Cursor, Cursor) apply
)
{} 

void main()
{ console({}); } 