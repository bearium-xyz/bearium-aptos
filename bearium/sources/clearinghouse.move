// SPDX-License-Identifier: BUSL-1.1
module bearium::room {
    // Demonstrates an OpEx hook for marketplace portals
    use bearium::marketplace;

    use bearium::peer::{Self, Peer};

    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use aptos_std::table::{Self, Table};
    use aptos_std::type_info;

    use std::signer;
    use std::vector;

    struct Agency has key {
        registry: Table<address, bool>, // key must be a module address for future hooks
    }

    fun init_module(moor: &signer) {
        move_to(moor, Agency {
            registry: table::new()
        })
    }

    #[test_only]
    public fun init_module_test(moor: &signer) {
        init_module(moor);
    }

    /// This is the placeholder for future hook registrations
    public entry fun register_agent<ORIGIN>() acquires Agency {
        let og = type_to_address<ORIGIN>();
        assert!(og == @bearium);
        let registry = &mut Agency[@bearium].registry;
        table::add(registry, og, true);
    }

    package fun hold(
        iam: &signer,
        peer: Object<Peer>,
        charge: u64,
        credit: u64,
    ): vector<FungibleAsset> {
        let stakes = vector::empty<FungibleAsset>();
        let peer_id = object::object_address(&peer);
        if (charge > 0) {
            let meta = peer::metadata(peer_id);
            let asset = primary_fungible_store::withdraw(iam, meta, charge);
            vector::push_back(&mut stakes, asset);
        };
        if (credit > 0) {
            let base = object::address_to_object<Metadata>(peer_id);
            let alpha = primary_fungible_store::withdraw(iam, base, credit);
            vector::push_back(&mut stakes, alpha);
        };
        stakes
    }

    /// Disburses funds based on game outcome.
    ///
    /// Handles capture, partial return, or surplus payout depending on `face_bps`.
    /// Applies edge fees, invokes optional OpEx hooks, and finalizes player settlement.
    ///
    /// Returns:
    /// - The player's final payout (net of CapEx and OpEx)
    ///
    /// Notes:
    /// - If `face_bps == 0`: full loss, all stakes captured.
    /// - If `face_bps <= 100_00`: partial return, remainder captured.
    /// - If `face_bps > 100_00`: rewards distributed, fees applied.
    package fun disburse<ORIGIN>(
        iam: &signer,
        peer: Object<Peer>,
        stakes: vector<FungibleAsset>,
        face_bps: u32, // zero to odds
        edge_bps: u16, // instant rate
        extra: vector<u8>
    ): u64 acquires Agency {
        let peer_id = object::object_address(&peer);

        let pledge = 0;
        vector::for_each_ref(&stakes, |c| {
            pledge += fungible_asset::amount(c)
        });
        if (pledge == 0) {
            vector::for_each_reverse(stakes, |r| {
                fungible_asset::destroy_zero(r)
            });
            return 0
        };

        let rewards = derive_proportion(pledge, face_bps);
        let player = signer::address_of(iam);

        // full capture
        if (face_bps == 0) {
            peer::capture(peer_id, stakes);
            return 0;
        };
        // capture partial loss, partial return
        if (face_bps <= 100_00) {
            let capture = pledge - rewards;
            let assets = vector<FungibleAsset>[];
            vector::for_each_reverse(stakes, |r| {
                let amount = fungible_asset::amount(&r);
                if (capture >= amount) {
                    vector::push_back(&mut assets, r);
                    capture -= amount;
                } else {
                    if (capture > 0) {
                        let asset = fungible_asset::extract(&mut r, capture);
                        vector::push_back(&mut assets, asset);
                        capture = 0;
                    };
                    primary_fungible_store::deposit(player, r);
                }
            });
            peer::capture(peer_id, assets);
            return rewards;
        };

        // default
        let surplus = rewards - pledge;
        let present = peer::wedge(peer_id, surplus);

        // CapEx
        let instant = derive_proportion(rewards, edge_bps as u32);
        if (instant > 0) {
            let edge = fungible_asset::extract(&mut present, instant);
            primary_fungible_store::deposit(peer_id, edge)
        };

        // OpEx
        let og = type_to_address<ORIGIN>();
        let registry = &Agency[@bearium].registry;
        if (table::contains(registry, og)) {
            let dispatch = *table::borrow(registry, og);
            assert!(dispatch == true); // this is the placeholder for hooks
            marketplace::dispatch(player, rewards, &mut present, extra);
        };

        // Payout
        let profit = fungible_asset::amount(&present);
        vector::push_back(&mut stakes, present);
        vector::for_each_reverse(stakes, |r| {
            primary_fungible_store::deposit(player, r);
        });
        pledge + profit
    }

    fun type_to_address<ORIGIN>(): address {
        let og_type = type_info::type_of<ORIGIN>();
        type_info::account_address(&og_type)
    }

    inline fun derive_proportion(amount: u64, rate_bps: u32): u64 {
        ((amount as u128) * (rate_bps as u128) / 10_000) as u64
    }
}