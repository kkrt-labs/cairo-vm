use felt::Felt252;
use num_bigint::BigInt;
use num_traits::{Signed, Zero};

use crate::hint_processor::builtin_hint_processor::hint_utils::{
    get_constant_from_var_name, get_ptr_from_var_name, insert_value_into_ap,
};

use crate::serde::deserialize_program::ApTracking;
use crate::stdlib::{borrow::Cow, collections::HashMap, prelude::*};

use crate::{
    hint_processor::hint_processor_definition::HintReference,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
};

/*  Implements hint:
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
*/
/// This hint is used as a helper for the associated Cairo code for adding two BigInts.
/// The responsibility of this hint is to compute the carry and borrow flags for the addition of two BigInts.
/// and store them in ap in the following order:
/// [ap] = needs_reduction
/// [ap+1] = carry/borrow for the first limb
/// [ap+2] = carry/borrow for the second limb
/// ...
/// [ap+N_LIMBS-1] = carry/borrow for the last limb
pub fn fq_bigint_add(
    vm: &mut VirtualMachine,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
    constants: &HashMap<String, Felt252>,
) -> Result<(), HintError> {
    // CONSTANTS
    // N_LIMBS: The number of limbs in the BigInt representation
    let n_limbs = {
        let n_limbs = get_constant_from_var_name("N_LIMBS", constants)?;
        // Check that N_LIMBS is at most 255
        // If N_LIMBS is 0, then the hint should fail
        if n_limbs.bits() > 8 || n_limbs.is_zero() {
            return Err(HintError::FailedToGetConstant);
        }
        u8::from_be(n_limbs.to_be_bytes()[31])
    };
    println!("n_limbs: {}", n_limbs);
    // BASE: The base of the BigInt representation, e.g. 2**64, 2**86, 2**128, etc.
    let base = get_constant_from_var_name("BASE", constants)?.to_bigint();
    println!("base: {}", base);

    // Initialize p_limbs
    let p_limbs: Vec<Felt252> = (0..n_limbs)
        .map(|i| format!("P{}", i))
        .map(|key| get_constant_from_var_name(&key, constants))
        .map(|res| res.and_then(|val| Ok(val.clone())))
        .collect::<Result<Vec<_>, _>>()?;
    println!("p_limbs: {:?}", p_limbs);
    // Recompute the prime P from its limbs
    // P = sum([p_limbs[i] * BASE**i for i in range(ids.N_LIMBS)])
    let p = p_limbs
        .iter()
        .enumerate()
        .map(|(i, limb)| limb.clone().to_bigint() * base.pow(i as u32))
        .fold(BigInt::zero(), |acc, limb| acc + limb);
    println!("p: {}", p);

    // Get a and b pointers.
    // a and b are two Cairo BigInts of the form:
    // struct BigInt {
    //    d0: felt,
    //    d1: felt,
    //   ...
    // }
    let a = get_ptr_from_var_name("a", vm, ids_data, ap_tracking)?;
    let b = get_ptr_from_var_name("b", vm, ids_data, ap_tracking)?;

    // Get a et b limbs
    let a_limbs: Vec<Felt252> = vm
        .get_integer_range(a, n_limbs as usize)?
        .iter()
        .map(Clone::clone)
        .map(Cow::into_owned)
        .collect();
    println!("a_limbs: {:?}", a_limbs);

    let b_limbs: Vec<Felt252> = vm
        .get_integer_range(b, n_limbs as usize)?
        .iter()
        .map(Clone::clone)
        .map(Cow::into_owned)
        .collect();
    println!("b_limbs: {:?}", b_limbs);

    let sum_limbs: Vec<Felt252> = a_limbs
        .iter()
        .zip(b_limbs.iter())
        .map(|(a_limb, b_limb)| a_limb + b_limb)
        .collect();
    println!("sum_limbs: {:?}", sum_limbs);

    let sum_unreduced = sum_limbs
        .iter()
        .enumerate()
        .map(|(i, limb)| limb.clone().to_bigint() * base.pow(i as u32))
        .fold(BigInt::zero(), |acc, limb| acc + limb);
    println!("sum_unreduced: {}", sum_unreduced);

    // Check if a + b >= p
    let needs_reduction = if sum_unreduced >= p {
        Felt252::from(1)
    } else {
        Felt252::zero()
    };
    println!("needs_reduction: {}", needs_reduction);

    let sum_reduced: Vec<BigInt> = sum_limbs
        .iter()
        .zip(p_limbs.iter())
        .map(|(sum_limb, p_limb)| sum_limb.to_bigint() - p_limb.to_bigint())
        .collect();
    println!("sum_reduced: {:?}", sum_reduced);

    let mut has_carry = Vec::with_capacity(n_limbs as usize);
    has_carry.push(if sum_limbs[0].to_bigint() >= base {
        Felt252::from(1)
    } else {
        Felt252::zero()
    });
    for i in 1..n_limbs {
        if sum_limbs[i as usize].clone() + has_carry[(i - 1) as usize].clone()
            >= base.clone().into()
        {
            has_carry.push(Felt252::from(1));
        } else {
            has_carry.push(Felt252::zero());
        }
    }
    println!("has_carry: {:?}", has_carry);

    let mut has_borrow_carry_reduced: Vec<Felt252> = Vec::with_capacity(n_limbs as usize);
    if sum_reduced[0].is_negative() {
        has_borrow_carry_reduced.push(Felt252::from(-1));
    } else if sum_reduced[0] >= base.clone().into() {
        has_borrow_carry_reduced.push(Felt252::from(1));
    } else {
        has_borrow_carry_reduced.push(Felt252::zero());
    };
    for i in 1..n_limbs {
        if (sum_reduced[i as usize].clone()
            + has_borrow_carry_reduced[(i - 1) as usize]
                .clone()
                .to_bigint())
        .is_negative()
        {
            has_borrow_carry_reduced.push(Felt252::from(-1));
        } else if (sum_reduced[i as usize].clone()
            + has_borrow_carry_reduced[(i - 1) as usize]
                .clone()
                .to_bigint())
            >= base.clone().into()
        {
            has_borrow_carry_reduced.push(Felt252::from(1));
        } else {
            has_borrow_carry_reduced.push(Felt252::zero());
        }
    }
    println!("has_borrow_carry_reduced: {:?}", has_borrow_carry_reduced);

    // Store the results in the memory
    // [ap] = needs_reduction
    insert_value_into_ap(vm, needs_reduction.clone())?;

    // [ap+1] = carry/borrow for the first limb
    // ...
    // [ap+N_LIMBS-1] = carry/borrow for the last limb
    for i in 1..n_limbs {
        if needs_reduction == Felt252::from(1) {
            let ap = (vm.get_ap() + i as usize)?;
            vm.insert_value(ap, has_borrow_carry_reduced[i as usize].clone())
                .map_err(HintError::Memory)?;
        } else {
            let ap = (vm.get_ap() + i as usize)?;
            vm.insert_value(ap, has_carry[i as usize].clone())
                .map_err(HintError::Memory)?;
        }
    }
    println!("on est arrivé la");
    Ok(())
}
