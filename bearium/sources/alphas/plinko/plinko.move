// SPDX-License-Identifier: BUSL-1.1
module bearium::plinko {
    use bearium::peer::{Peer};
    use bearium::room;
    
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::randomness;

    use std::signer;

    #[event]
    struct Plinko has drop, store {
        // common
        peer_id: address,
        player: address,
        charge: u64,
        credit: u64,
        payout: u64,
        face_bps: u32,
        edge_bps: u16,

        // specific
        rows: u8,
        result: u16,
    }

    #[randomness]
    entry fun drop<ORIGIN>(
        iam: &signer,
        peer: Object<Peer>,
        charge: u64,
        credit: u64,
        risk: u8, // 0=Low
        rows: u8,
        extra: vector<u8>
    ) {
        assert!(risk == 0);
        assert!(rows == 8);
        
        let stakes = room::hold(iam, peer, charge, credit);
        
        let bits16 = randomness::u16_integer();
        let result = bitmask(rows, bits16);
        let face_bps = face_bps(risk, rows, count_ones(result));
        let edge_bps = edge_bps(risk);

        let payout = room::disburse<ORIGIN>(
            iam, peer,
            stakes,
            face_bps,
            edge_bps,
            extra
        );

        event::emit(Plinko {
            peer_id: object::object_address(&peer),
            player: signer::address_of(iam),
            charge,
            credit,
            payout,
            face_bps,
            edge_bps,
            // specific
            rows,
            result,
        })
    }

    public fun face_bps(risk: u8, rows: u8, ones: u8): u32 {
        let zeros = rows - ones; // symmetric
        let index = if (ones > zeros) zeros else ones;
        face_bps_table(risk, rows)[index as u64]
    }

    #[view]
    public fun face_bps_table(risk: u8, rows: u8): vector<u32> {
        if (risk == 0) {
            if (rows == 8) return vector[
                5_0000, 1_9000, 1_1000, 1_0000, 6000
            ]
        };
        vector[]
    }

    #[view]
    public fun edge_bps(_risk: u8): u16 {
        100 // x 0.01% = 1%
    }

    // Brian Kernighan's algorithm is used to find the number of set bits in a number.
    fun count_ones(bits: u16): u8 {
        let count = 0u8;
        while (bits != 0) {
            bits = bits & (bits - 1);
            count = count + 1;
        };
        count
    }

    inline fun bitmask(rows: u8, bits16: u16): u16 {
        bits16 & ((0xffff as u16) >> (16 - rows))
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
    fun test_plinko(
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

        // Seed
        randomness::initialize_for_testing(fx);
        randomness::set_seed(x"0000000000000000000000000000000000000000000000000000000000000000");

        // 1x full return
        {
            // Plinko
            drop<Plinko>(player, peer, 1000, 0, 0, 8, vector[]);
            let round = &event::emitted_events<Plinko>()[0];
            assert!(round.result == 31);
            assert!(round.face_bps == 1_0000);
            assert!(round.payout == 1000);

            // Balances
            let user_asset = primary_fungible_store::balance(user, metadata);
            let user_alpha = primary_fungible_store::balance(user, metabase);
            let peer_asset = primary_fungible_store::balance(peer_id, metadata);
            let peer_alpha = primary_fungible_store::balance(peer_id, metabase);
            assert!(peer_asset == 0);
            assert!(peer_alpha == 0);
            assert!(user_asset == 100_000_000);
            assert!(user_alpha == 0);
        };

        randomness::u16_integer(); // skip 56906
    
        // 1.1x profit
        {
            // Plinko
            drop<Plinko>(player, peer, 1000, 0, 0, 8, vector[]);
            let round = &event::emitted_events<Plinko>()[1];
            assert!(round.result == 219);
            assert!(round.face_bps == 1_1000);
            assert!(round.payout == 1089);

            // Balances
            let user_asset = primary_fungible_store::balance(user, metadata);
            let user_alpha = primary_fungible_store::balance(user, metabase);
            let peer_asset = primary_fungible_store::balance(peer_id, metadata);
            let peer_alpha = primary_fungible_store::balance(peer_id, metabase);
            assert!(peer_asset == 0);
            assert!(peer_alpha == 11);
            assert!(user_asset == 100_000_000);
            assert!(user_alpha == 89);
        };

        randomness::u16_integer(); // skip 59388

        // 0.6x partial return
        // Mix charge and credit
        {
            // Plinko
            drop<Plinko>(player, peer, 911, 89, 0, 8, vector[]);
            let round = &event::emitted_events<Plinko>()[2];
            assert!(round.result == 150);
            assert!(round.face_bps == 6000);
            assert!(round.payout == 600);

            // Balances
            let user_asset = primary_fungible_store::balance(user, metadata);
            let user_alpha = primary_fungible_store::balance(user, metabase);
            let peer_asset = primary_fungible_store::balance(peer_id, metadata);
            let peer_alpha = primary_fungible_store::balance(peer_id, metabase);
            assert!(peer_asset == (400 - 89));
            assert!(peer_alpha == 11); // 89 captured credits should be burned
            assert!(user_asset == (100_000_000 - 400 + 89));
            assert!(user_alpha == 0);
        };
    }

    #[test(fx = @aptos_framework)]
    fun test_count_ones(fx: &signer) {
        randomness::initialize_for_testing(fx);
        randomness::set_seed(x"0000000000000000000000000000000000000000000000000000000000000000");
        let bits16 = randomness::u16_integer();
        assert!(bits16 == 52255); // 1100 1100 0001 1111
        let preset = vector[
             8,    31, 5,
             9,    31, 5,
            10,    31, 5,
            11,  1055, 6,
            12,  3103, 7,
            13,  3103, 7,
            14,  3103, 7,
            15, 19487, 8,
            16, 52255, 9,
        ];
        for (i in 0..7) {
            let rows = preset[i * 3] as u8;
            let bits = bitmask(rows, bits16);
            let ones = count_ones(bits) as u16;
            assert!(bits == preset[i * 3 + 1]);
            assert!(ones == preset[i * 3 + 2]);
        };
    }
}