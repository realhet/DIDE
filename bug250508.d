string 配(string left, string op, string right) /+Note: Tuple operations: (x,y) += (y,x)+/
{
	auto opStr() => '"'~op~'"'; 
	auto isBinaryOp(string op) => !!op.among("+", "-", "*", "/", "%", "^", "~", "<<", ">>", ">>>", "^^"); 
	
	if(op.among("=", "==", "is"))
	return iq{tuple(AliasSeq!($(left)) $(op) tuple($(right)))}.text; 
	else if(isBinaryOp(op))
	return iq{tupleOp!$(opStr)(tuple($(left)),tuple($(right)))}.text; 
	else if(op.endsWith('=') && isBinaryOp(op[0..$-1]))
	return iq{tuple(AliasSeq!($(left))=(tupleOp!$(opStr)(tuple($(left)),tuple($(right)))))}.text; 
	else enforce(false, "Invalid params."); 
	assert(0); 
} 

/+Note: tenary relationals+/
string 界0(string mi, string x, string ma) => iq{($(mi))<($(x)) && ($(x))<($(ma))}.text; 
string 界1(string mi, string x, string ma) => iq{($(mi))<=($(x)) && ($(x))<($(ma))}.text; 
string 界2(string mi, string x, string ma) => iq{($(mi))<($(x)) && ($(x))<=($(ma))}.text; 
string 界3(string mi, string x, string ma) => iq{($(mi))<=($(x)) && ($(x))<=($(ma))}.text; 

/+Note: tenary equal+/
string 等(string a, string b, string c) => iq{($(a))==($(b)) && ($(b))==($(c))}.text; 

//Todo: 製(T, alias def) manufacture constants from simple definitions.  Eg: RGB(255, 0, 0) RGB(red)  <- both should use color display!

/+
	Todo: UnitTest relational operations.
	/+
		Code: string[5] x; auto a(bool b) => ((b)?('✅'):('❌')); 
		(
			mixin(求each(q{i=0},q{4},q{
				((0x5B3C716FD2B).檢((mixin(指(q{x},q{0}))) ~= a(mixin(界0(q{1},q{i},q{4 }))))),
				((0x60BC716FD2B).檢((mixin(指(q{x},q{1}))) ~= a(mixin(界1(q{1},q{i},q{4 }))))),
				((0x663C716FD2B).檢((mixin(指(q{x},q{2}))) ~= a(mixin(界2(q{1},q{i},q{4 }))))),
				((0x6BBC716FD2B).檢((mixin(指(q{x},q{3}))) ~= a(mixin(界3(q{1},q{i},q{4 }))))),
				((0x713C716FD2B).檢((mixin(指(q{x},q{4}))) ~= a(mixin(等(q{2},q{i},q{4-i})))))
			}))
		); 
	+/
+/