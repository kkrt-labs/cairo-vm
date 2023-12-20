from starkware.cairo.common.uint256 import SHIFT, Uint256
from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    bigint_mul,
    UnreducedBigInt5,
    UnreducedBigInt3,
    nondet_bigint3 as nd,
    uint256_to_bigint,
)
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math import abs_value, split_felt

from src.bn254.curve import (
    P0,
    P1,
    P2,
    N_LIMBS,
    N_LIMBS_UNREDUCED,
    DEGREE,
    BASE,
    P0_256,
    P1_256,
    BASE_MIN_1,
)

const SHIFT_MIN_BASE = SHIFT - BASE;
const SHIFT_MIN_P2 = SHIFT - P2 - 1;

func unrededucedUint256_to_BigInt3{range_check_ptr}(x: Uint256) -> (res: BigInt3*) {
    alloc_locals;
    let (low_bigint3) = felt_to_bigint3(x.low);
    let (high_bigint3) = felt_to_bigint3(x.high);
    let res = reduce_3(
        UnreducedBigInt3(
            d0=low_bigint3.d0 + SHIFT * high_bigint3.d0,
            d1=low_bigint3.d1 + SHIFT * high_bigint3.d1,
            d2=low_bigint3.d2 + SHIFT * high_bigint3.d2,
        ),
    );
    return (res,);
}

func felt_to_bigint3{range_check_ptr}(x: felt) -> (res: BigInt3) {
    let (high, low) = split_felt(x);
    let (res) = uint256_to_bigint(Uint256(low, high));
    return (res,);
}
func fq_zero() -> BigInt3 {
    let res = BigInt3(0, 0, 0);
    return res;
}
func fq_eq_zero(x: BigInt3*) -> felt {
    if (x.d0 != 0) {
        return 0;
    }
    if (x.d1 != 0) {
        return 0;
    }
    if (x.d2 != 0) {
        return 0;
    }
    return 1;
}

func assert_fq_eq(x: BigInt3*, y: BigInt3*) {
    assert 0 = x.d0 - y.d0;
    assert 0 = x.d1 - y.d1;
    assert 0 = x.d2 - y.d2;
    return ();
}

func bigint_sqr(x: BigInt3) -> (res: UnreducedBigInt5) {
    return (
        UnreducedBigInt5(
            d0=x.d0 * x.d0,
            d1=2 * x.d0 * x.d1,
            d2=2 * x.d0 * x.d2 + x.d1 * x.d1,
            d3=2 * x.d1 * x.d2,
            d4=x.d2 * x.d2,
        ),
    );
}
// Asserts that x0, x1, x2 are positive and < B and 0 <= x < P
func assert_reduced_felt{range_check_ptr}(x: BigInt3) {
    assert [range_check_ptr] = x.d0;
    assert [range_check_ptr + 1] = x.d1;
    assert [range_check_ptr + 2] = x.d2;
    assert [range_check_ptr + 3] = BASE_MIN_1 - x.d0;
    assert [range_check_ptr + 4] = BASE_MIN_1 - x.d1;
    assert [range_check_ptr + 5] = P2 - x.d2;

    if (x.d2 == P2) {
        if (x.d1 == P1) {
            assert [range_check_ptr + 6] = P0 - 1 - x.d0;
            tempvar range_check_ptr = range_check_ptr + 7;
            return ();
        } else {
            assert [range_check_ptr + 6] = P1 - 1 - x.d1;
            tempvar range_check_ptr = range_check_ptr + 7;
            return ();
        }
    } else {
        tempvar range_check_ptr = range_check_ptr + 6;
        return ();
    }
}

// Asserts that x.low, x.high are positive and < 2**128 and 0 <= x < P
func assert_reduced_felt256{range_check_ptr}(x: Uint256) {
    assert [range_check_ptr] = x.low;
    assert [range_check_ptr + 1] = x.high;
    assert [range_check_ptr + 2] = P1_256 - x.high;

    if (x.high == P1_256) {
        assert [range_check_ptr + 3] = P0_256 - 1 - x.low;
        tempvar range_check_ptr = range_check_ptr + 4;
        return ();
    } else {
        tempvar range_check_ptr = range_check_ptr + 3;
        return ();
    }
}
namespace fq_bigint3 {
    func add{range_check_ptr}(a: BigInt3*, b: BigInt3*) -> BigInt3* {
        alloc_locals;
        let (__fp__, _) = get_fp_and_pc();

        %{
            from src.bn254.hints import p, base as BASE, p_limbs

            sum_limbs = [getattr(getattr(ids, 'a'), 'd'+str(i)) + getattr(getattr(ids, 'b'), 'd'+str(i)) for i in range(ids.N_LIMBS)]
            sum_unreduced = sum([sum_limbs[i] * BASE**i for i in range(ids.N_LIMBS)])
            sum_reduced = [sum_limbs[i] - p_limbs[i] for i in range(ids.N_LIMBS)]
            has_carry = [1 if sum_limbs[0] >= BASE else 0]
            for i in range(1,ids.N_LIMBS):
                if sum_limbs[i] + has_carry[i-1] >= BASE:
                    has_carry.append(1)
                else:
                    has_carry.append(0)
            needs_reduction = 1 if sum_unreduced >= p else 0
            has_borrow_carry_reduced = [-1 if sum_reduced[0] < 0 else (1 if sum_reduced[0]>=BASE else 0)]
            for i in range(1,ids.N_LIMBS):
                if (sum_reduced[i] + has_borrow_carry_reduced[i-1]) < 0:
                    has_borrow_carry_reduced.append(-1)
                elif (sum_reduced[i] + has_borrow_carry_reduced[i-1]) >= BASE:
                    has_borrow_carry_reduced.append(1)
                else:
                    has_borrow_carry_reduced.append(0)

            memory[ap] = needs_reduction
            for i in range(ids.N_LIMBS-1):
                if needs_reduction:
                    memory[ap+1+i] = has_borrow_carry_reduced[i]
                else:
                    memory[ap+1+i] = has_carry[i]
        %}

        ap += N_LIMBS;

        let needs_reduction = [ap - 3];
        let cb_d0 = [ap - 2];
        let cb_d1 = [ap - 1];

        if (needs_reduction != 0) {
            // Needs reduction over P.

            local res: BigInt3 = BigInt3(
                (-P0) + a.d0 + b.d0 - cb_d0 * BASE,
                (-P1) + a.d1 + b.d1 + cb_d0 - cb_d1 * BASE,
                (-P2) + a.d2 + b.d2 + cb_d1,
            );

            assert [range_check_ptr] = BASE_MIN_1 - res.d0;
            assert [range_check_ptr + 1] = BASE_MIN_1 - res.d1;
            assert [range_check_ptr + 2] = P2 - res.d2;

            if (res.d2 == P2) {
                if (res.d1 == P1) {
                    assert [range_check_ptr + 3] = P0 - 1 - res.d0;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                } else {
                    assert [range_check_ptr + 3] = P1 - 1 - res.d1;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                }
            } else {
                tempvar range_check_ptr = range_check_ptr + 3;
                return &res;
            }
        } else {
            // No reduction over P.

            local res: BigInt3 = BigInt3(
                a.d0 + b.d0 - cb_d0 * BASE, a.d1 + b.d1 + cb_d0 - cb_d1 * BASE, a.d2 + b.d2 + cb_d1
            );
            assert [range_check_ptr] = BASE_MIN_1 - res.d0;
            assert [range_check_ptr + 1] = BASE_MIN_1 - res.d1;
            assert [range_check_ptr + 2] = P2 - res.d2;

            if (res.d2 == P2) {
                if (res.d1 == P1) {
                    assert [range_check_ptr + 3] = P0 - 1 - res.d0;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                } else {
                    assert [range_check_ptr + 3] = P1 - 1 - res.d1;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                }
            } else {
                tempvar range_check_ptr = range_check_ptr + 3;
                return &res;
            }
        }
    }

    func sub{range_check_ptr}(a: BigInt3*, b: BigInt3*) -> BigInt3* {
        alloc_locals;
        let (__fp__, _) = get_fp_and_pc();

        %{
            from src.bn254.hints import p, base as BASE, p_limbs

            sub_limbs = [getattr(getattr(ids, 'a'), 'd'+str(i)) - getattr(getattr(ids, 'b'), 'd'+str(i)) for i in range(ids.N_LIMBS)]
            sub_unreduced = sum([sub_limbs[i] * BASE**i for i in range(ids.N_LIMBS)])
            sub_reduced = [sub_limbs[i] + p_limbs[i] for i in range(ids.N_LIMBS)]
            has_borrow = [-1 if sub_limbs[0] < 0 else 0]
            for i in range(1,ids.N_LIMBS):
                if sub_limbs[i] + has_borrow[i-1] < 0:
                    has_borrow.append(-1)
                else:
                    has_borrow.append(0)
            needs_reduction = 1 if sub_unreduced < 0 else 0
            has_borrow_carry_reduced = [-1 if sub_reduced[0] < 0 else (1 if sub_reduced[0]>=BASE else 0)]
            for i in range(1,ids.N_LIMBS):
                if (sub_reduced[i] + has_borrow_carry_reduced[i-1]) < 0:
                    has_borrow_carry_reduced.append(-1)
                elif (sub_reduced[i] + has_borrow_carry_reduced[i-1]) >= BASE:
                    has_borrow_carry_reduced.append(1)
                else:
                    has_borrow_carry_reduced.append(0)
                    
            memory[ap] = needs_reduction
            for i in range(ids.N_LIMBS-1):
                if needs_reduction:
                    memory[ap+1+i] = has_borrow_carry_reduced[i]
                else:
                    memory[ap+1+i] = has_borrow[i]
        %}

        ap += N_LIMBS;

        let needs_reduction = [ap - 3];
        let cb_d0 = [ap - 2];
        let cb_d1 = [ap - 1];

        if (needs_reduction != 0) {
            // Needs reduction over P.
            local res: BigInt3 = BigInt3(
                P0 + a.d0 - b.d0 - cb_d0 * BASE,
                P1 + a.d1 - b.d1 + cb_d0 - cb_d1 * BASE,
                P2 + a.d2 - b.d2 + cb_d1,
            );

            assert [range_check_ptr] = BASE_MIN_1 - res.d0;
            assert [range_check_ptr + 1] = BASE_MIN_1 - res.d1;
            assert [range_check_ptr + 2] = P2 - res.d2;
            if (res.d2 == P2) {
                if (res.d1 == P1) {
                    assert [range_check_ptr + 3] = P0 - 1 - res.d0;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                } else {
                    assert [range_check_ptr + 3] = P1 - 1 - res.d1;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                }
            } else {
                tempvar range_check_ptr = range_check_ptr + 3;
                return &res;
            }
        } else {
            // No reduction over P.
            local res: BigInt3 = BigInt3(
                a.d0 - b.d0 - cb_d0 * BASE, a.d1 - b.d1 + cb_d0 - cb_d1 * BASE, a.d2 - b.d2 + cb_d1
            );

            assert [range_check_ptr] = res.d0 + (SHIFT_MIN_BASE);
            assert [range_check_ptr + 1] = res.d1 + (SHIFT_MIN_BASE);
            assert [range_check_ptr + 2] = res.d2 + (SHIFT_MIN_P2);
            if (res.d2 == P2) {
                if (res.d1 == P1) {
                    assert [range_check_ptr + 3] = P0 - 1 - res.d0;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                } else {
                    assert [range_check_ptr + 3] = P1 - 1 - res.d1;
                    tempvar range_check_ptr = range_check_ptr + 4;
                    return &res;
                }
            } else {
                tempvar range_check_ptr = range_check_ptr + 3;
                return &res;
            }
        }
    }
}
