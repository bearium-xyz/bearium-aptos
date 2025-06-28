// SPDX-License-Identifier: BUSL-1.1

/// Marketplace Agency - Reference Implementation
///
/// This module provides a reference implementation of an agency strategy for marketplaces.
///
/// Notes:
/// - This is a reference implementation. Because AIP-112 has not yet matured,
///   the agency logic is included directly within the same package alongside the primitives.
///
/// - The implementation is fully out-of-box. Anyone can launch their own portal
///   by creating companion marketplace objects — no contract deployment required.
///
/// - Demonstrates the referral feature (via campaign hooks).
///
/// This implementation is designed for demonstration, extensibility, and early builder adoption.
module bearium::marketplace {
    friend bearium::room;

    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::object::{Self, ExtendRef, Object};
    use aptos_framework::primary_fungible_store;

    use aptos_std::bcs_stream;
    use aptos_std::table::{Self, Table};

    use std::option::{Self, Option};
    use std::signer;
    use std::vector;

    #[event]
    struct Origin has drop, store {
        marketplace_id: address,
        peer_id: address,
        winner: address,
        gross_reward: u64,
        marketplace_fee: u64,
        inviter: Option<address>,
        referral_commission: u64,
    }

    #[event]
    struct Being has drop, store {
        marketplace_id: address,
        host: address,
    }

    struct Marketplace has key {
        auth_ref: ExtendRef, // The signer's right
        marketplace_bps: u16,
    }

    struct Referral has key {
        registry: Table<address, address>, // invitee-inviter bonds
        commission_bps: u16,
    }

    struct Context {
        marketplace_id: address,
    }

    public entry fun new(host: &signer) {
        iam(host);
    }

    public fun iam(host: &signer): address {
        let host_at = signer::address_of(host);
        // one host can have many marketplaces
        let constructor_ref = &object::create_sticky_object(host_at);
        let marketplace = &object::generate_signer(constructor_ref);
        move_to(
            marketplace,
            Marketplace {
                auth_ref: object::generate_extend_ref(constructor_ref),
                marketplace_bps: 0
            }
        );
        move_to(
            marketplace,
            Referral {
                registry: table::new(),
                commission_bps: 0
            }
        );

        let marketplace_id = object::address_from_constructor_ref(constructor_ref);
        event::emit(Being {
            marketplace_id,
            host: host_at,
        });
        marketplace_id
    }

    #[persistent]
    public(friend) fun dispatch(
        winner: address,
        gross_reward: u64,
        credit: &mut FungibleAsset,
        extras: vector<u8>
    ) acquires Marketplace, Referral {
        if (vector::length(&extras) == 0) return; // do nothing
        let Context { marketplace_id } = to_context(extras);
        let marketplace = object::address_to_object<Marketplace>(marketplace_id);

        let metabase = fungible_asset::metadata_from_asset(credit);
        let peer_id = object::object_address(&metabase);

        let (inviter, referral_commission) = handle_referral(marketplace, winner, gross_reward, credit);
        
        let marketplace_fee = derive_proportion(gross_reward, marketplace_bps(marketplace) as u32);
        if (marketplace_fee > 0) {
            let edge = fungible_asset::extract(credit, marketplace_fee);
            primary_fungible_store::deposit(marketplace_id, edge);
        };
        
        event::emit(Origin {
            marketplace_id,
            peer_id,
            winner,
            gross_reward,
            marketplace_fee,
            inviter,
            referral_commission,
        })
    }

    fun to_context(data: vector<u8>): Context {
        let stream = bcs_stream::new(data);
        Context {
            marketplace_id: bcs_stream::deserialize_address(&mut stream)
        }
    }

    //-----
    // Host
    //-----

    #[view]
    public fun marketplace_bps<T: key>(marketplace: Object<T>): u16 acquires Marketplace {
        let marketplace_id = object::object_address(&marketplace);
        *&Marketplace[marketplace_id].marketplace_bps
    }

    public entry fun update_marketplace_bps<T: key>(host: &signer, marketplace: Object<T>, new_bps: u16) acquires Marketplace {
        let host_at = signer::address_of(host);
        assert!(object::is_owner(marketplace, host_at));
        let marketplace_id = object::object_address(&marketplace);
        Marketplace[marketplace_id].marketplace_bps = new_bps;
    }

    //---------
    // Referral
    //---------

    public entry fun bond(user: &signer, marketplace_id: address, inviter: address) acquires Referral {
        let invitee = signer::address_of(user);
        let registry = &mut Referral[marketplace_id].registry;
        table::add(registry, invitee, inviter);
    }

    #[view]
    public fun referral_commission_bps<T: key>(marketplace: Object<T>): u16 acquires Referral {
        let marketplace_id = object::object_address(&marketplace);
        *&Referral[marketplace_id].commission_bps
    }

    public entry fun update_referral_commission_bps<T: key>(host: &signer, marketplace: Object<T>, new_bps: u16) acquires Referral {
        let host_at = signer::address_of(host);
        assert!(object::is_owner(marketplace, host_at));
        let marketplace_id = object::object_address(&marketplace);
        Referral[marketplace_id].commission_bps = new_bps;
    }

    fun handle_referral<T: key>(
        marketplace: Object<T>,
        winner: address,
        reward: u64,
        credit: &mut FungibleAsset
    ): (Option<address>, u64) acquires Referral {
        let marketplace_id = object::object_address(&marketplace);
        let registry = &Referral[marketplace_id].registry;
        if (!table::contains(registry, winner)) return (option::none(), 0);
        let inviter = *table::borrow(registry, winner);
        let commission = derive_proportion(reward, referral_commission_bps(marketplace) as u32);
        if (commission > 0) {
            let edge = fungible_asset::extract(credit, commission);
            primary_fungible_store::deposit(inviter, edge);
        };
        (
            option::some(inviter),
            commission
        )
    }

    //----------
    // Utilities
    //----------

    inline fun derive_proportion(amount: u64, rate_bps: u32): u64 {
        ((amount as u128) * (rate_bps as u128) / 10_000) as u64
    }
}