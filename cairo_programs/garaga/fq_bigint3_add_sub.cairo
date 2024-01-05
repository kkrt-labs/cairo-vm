%builtins output range_check

from starkware.cairo.common.math import assert_le_felt
from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt5
from starkware.cairo.common.registers import get_fp_and_pc
from cairo_programs.garaga.fq import fq_bigint3, assert_reduced_felt
from cairo_programs.garaga.curve import BASE

const P0 = 60193888514187762220203335;
const P1 = 27625954992973055882053025;
const P2 = 3656382694611191768777988;

func main{output_ptr: felt*, range_check_ptr}() {
    alloc_locals;


    tempvar Xa = new BigInt3(1, 2, 3);
    tempvar Ya = new BigInt3(4, 5, 6);
    tempvar Xb = new BigInt3(BASE - 1, BASE - 1, P2 - 1);
    tempvar Yb = new BigInt3(BASE - 123456, BASE - 123456, P2 - 123456);

    let aaa = fq_bigint3.add(Xa, Ya);
    let abb = fq_bigint3.add(Xb, Yb);
    // let aab = fq_bigint3.add(Xa, Yb);
    // let aba = fq_bigint3.add(Xb, Ya);

    // let saa = fq_bigint3.sub(&Xa, &Ya);
    // let sbb = fq_bigint3.sub(&Xb, &Yb);
    // let sab = fq_bigint3.sub(&Xa, &Yb);
    // let sba = fq_bigint3.sub(&Xb, &Ya);

    assert aaa.d0 = 5;
    assert aaa.d1 = 7;
    assert aaa.d2 = 9;

    assert abb.d0 = 17177363941148504960868472;
    assert abb.d1 = 49745297462363211299018783;
    assert abb.d2 = 3656382694611191768654532;

    // assert aab.d0 = 77371252455336267181071809;
    // assert aab.d1 = 77371252455336267181071810;
    // assert aab.d2 = 3656382694611191768654535;

    // assert aba.d0 = 17177363941148504960991932;
    // assert aba.d1 = 49745297462363211299142243;
    // assert aba.d2 = 5;

    // assert saa.d0 = 60193888514187762220203332;
    // assert saa.d1 = 27625954992973055882053022;
    // assert saa.d2 = 3656382694611191768777985;

    // assert sbb.d0 = 123455;
    // assert sbb.d1 = 123455;
    // assert sbb.d2 = 123455;

    // assert sab.d0 = 60193888514187762220326792;
    // assert sab.d1 = 27625954992973055882176482;
    // assert sab.d2 = 123458;

    // assert sba.d0 = 77371252455336267181195259;
    // assert sba.d1 = 77371252455336267181195258;
    // assert sba.d2 = 3656382694611191768777981;

    return ();
}
