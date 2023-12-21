DEGREE = 2
BASE = 2**86
P2 = 3656382694611191768777988

p = 0x30644E72E131A029B85045B68181585D97816A916871CA8D3C208C16D87CFD47


def eval(coeffs, base=BASE):
    x = 0
    for i, c in enumerate(coeffs):
        x += c * base**i
    return x


def split(x, degree=DEGREE, base=BASE):
    coeffs = []
    for n in range(degree, 0, -1):
        q, r = divmod(x, base**n)
        coeffs.append(q)
        x = r
    coeffs.append(x)
    return coeffs[::-1]


def add_mod_p(x: list, y: list, p=p):
    val = (eval(x) + eval(y)) % p
    return split(val)


def sub_mod_p(x: list, y: list, p=p):
    val = (eval(x) - eval(y)) % p
    return split(val)


Xa = [1, 2, 3]
Ya = [4, 5, 6]
Xb = [BASE - 1, BASE - 1, P2 - 1]
Yb = [BASE - 123456, BASE - 123456, P2 - 123456]

print(add_mod_p(Xa, Ya))
print(add_mod_p(Xb, Yb))
print(add_mod_p(Xa, Yb))
print(add_mod_p(Xb, Ya))
print("\n")
print(sub_mod_p(Xa, Ya))
print(sub_mod_p(Xb, Yb))
print(sub_mod_p(Xa, Yb))
print(sub_mod_p(Xb, Ya))
