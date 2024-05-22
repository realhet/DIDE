//@exe

import het; 

void main()
{
	print(
		(mixin(求sum(q{1<=float i<=3},q{},q{((((i)^^(2)))/(3))})))	, (mixin(求sum(q{
			i=10,
			2
		},q{14},q{1})))	, (mixin(求product(q{i},q{2, 4, 5, 6, 7, 8},q{i}))),
		(mixin(求sum(q{1<=float i<=3},q{},q{i})))	, (mixin(求sum(q{
			i=10,
			2
		},q{14},q{
			1+
			1+
			1+
			1+
			1
		})))	, (mixin(求map(q{i},q{2, 4, 5},q{i<<4})))
	); 
	
	(mixin(求each(q{i},q{1, 2, 5, 6, 14},q{print("\33"~cast(char)i~"color")}))); 
	
	//⇶∀∃
} 