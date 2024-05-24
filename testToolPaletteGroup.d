(表1([
	[q{"expression blocks"},q{
		{}() [] 
		"" r"" `` 
		' ' q{}
	}],
	[q{"math letters"},q{
		π ℯ ℂ α β γ µ 
		Δ δ ϕ ϑ ε
	}],
	[q{"symbols"},q{"° ⍵ ℃ ± ∞ ↔ → ∈ ∉"}],
	[q{"float, double, real"},q{(float(x)) (double(x)) (real(x))}],
	[q{"floor, 
ceil, 
round, 
trunc"},q{
		(floor(x)) (ifloor(x)) (lfloor(x))
		(ceil(x)) (iceil(x)) (lceil(x))
		(round(x)) (iround(x)) (lround(x))
		(trunc(x)) (itrunc(x)) (ltrunc(x))
	}],
	[q{"abs, normalize"},q{(magnitude(a)) (normalize(a))}],
	[q{"multiply, divide, 
dot, cross"},q{
		((a)*(b)) ((a)/(b)) 
		((a).dot(b)) ((a).cross(b))
	}],
	[q{"sqrt, root, power"},q{(sqrt(a)) ((a).root(b)) ((a)^^(b))}],
	[q{"color literals"},q{
		(RGB( , , )) 
		(RGBA( , , , ))
	}],
]));