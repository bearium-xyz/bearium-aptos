// SPDX-License-Identifier: BUSL-1.1
module bearium::toss {
    use bearium::peer::{Peer};
    use bearium::room;
    
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::randomness;

    use std::signer;

    #[event]
    struct Toss has drop, store {
        peer_id: address,
        player: address,
        expect: bool,
        result: bool,
        charge: u64,
        credit: u64,
        profit: u64,
        face_bps: u32,
        edge_bps: u16,
    }

    #[randomness]
    entry fun toss<ORIGIN>(
        iam: &signer,
        peer: Object<Peer>,
        charge: u64,
        credit: u64,
        outcome: bool,
        extra: vector<u8>
    ) {
        let stakes = room::hold(iam, peer, charge, credit);
        let actual = randomness::u8_range(0, 2);
        let result = if (actual == 1) true else false;
        let face_bps = face_bps(result, outcome);
        let edge_bps = edge_bps();
        let profit = room::disburse<ORIGIN>(
            iam, peer,
            stakes,
            face_bps,
            edge_bps,
            extra
        );

        event::emit(Toss {
            peer_id: object::object_address(&peer),
            player: signer::address_of(iam),
            expect: outcome,
            result,
            charge,
            credit,
            profit,
            face_bps,
            edge_bps,
        });
    }

    inline fun face_bps(result: bool, expect: bool): u32 {
        if (expect == result) 2 * 10_000
        else 0
    }

    #[view]
    public fun edge_bps(): u16 {
        100 // x 0.01% = 1%
    }

    //------
    // Tests
    //------

    #[test_only]
    use bearium::test_helpers;

    #[test_only]
    use aptos_framework::primary_fungible_store;

    #[test(
        fx = @aptos_framework,
        bearium = @bearium,
        player = @0xcafe,
    )]
    fun test_toss(
        fx: &signer,
        bearium: &signer,
        player: &signer,
    ) {
        // Room
        room::init_module_test(bearium);

        // APT peer
        let (metadata, asset) = test_helpers::apt_apt(fx, 100_000_000);
        let user = signer::address_of(player);
        let (peer_id, peer, metabase) = test_helpers::make_peer(asset, user);

        // Toss
        randomness::initialize_for_testing(fx);
        randomness::set_seed(x"0000000000000000000000000000000000000000000000000000000000000000");
        toss<Toss>(player, peer, 1000, 0, true, vector[]);
        let win = &event::emitted_events<Toss>()[0];
        assert!(win.expect == win.result);
        assert!(win.profit == 980);

        // Balances
        let user_asset = primary_fungible_store::balance(user, metadata);
        let user_alpha = primary_fungible_store::balance(user, metabase);
        let peer_asset = primary_fungible_store::balance(peer_id, metadata);
        let peer_alpha = primary_fungible_store::balance(peer_id, metabase);
        assert!(peer_asset == 0);
        assert!(peer_alpha == 20);
        assert!(user_asset == 100_000_000);
        assert!(user_alpha == 980);
    }
}