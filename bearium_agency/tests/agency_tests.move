#[test_only]
module bearium_agency::agency_tests {
    use bearium::room;
    use bearium::test_helpers;

    use bearium_agency::marketplace::{Self, Marketplace};

    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;

    use std::bcs;
    use std::debug;
    use std::signer;
    use std::vector;

    #[test(
        fx = @aptos_framework,
        bearium = @bearium,
        agency = @bearium_agency,
        host = @0x42,
        player = @0xcafe,
    )]
    fun test_agency(
        fx: &signer,
        bearium: &signer,
        agency: &signer,
        host: &signer,
        player: &signer,
    ) {
        // Room
        room::init_module_test(bearium);
        
        // Agency
        marketplace::register_hook(agency);

        // Marketplace
        let marketplace_id = marketplace::iam(host);
        let marketplace = object::address_to_object<Marketplace>(marketplace_id);
        marketplace::update_marketplace_bps(host, marketplace, 10);
        marketplace::update_referral_commission_bps(host, marketplace, 40);
        let extra = bcs::to_bytes(&marketplace_id);

        // Referral
        let inviter = @0xc0ffee;
        marketplace::bond(player, marketplace, inviter);

        // Skin
        marketplace::update_skin_commission_bps(host, marketplace, 50);
        let builder = @0x1337;
        let skin_id = x"8583d0c1560ca905a74ed46a0cb2bc33a65f3658";
        marketplace::add_skin(host, marketplace, skin_id, builder);
        vector::append(&mut extra, bcs::to_bytes(&skin_id));

        // APT peer
        let (metadata, asset) = test_helpers::apt_apt(fx, 100_000_000);
        let user = signer::address_of(player);
        let (peer_id, peer, metabase) = test_helpers::make_peer(asset, user);

        // Agent
        let stakes = test_helpers::hold(player, peer, 1000, 0);
        test_helpers::disburse<marketplace::Origin>(
            player,
            peer,
            stakes,
            2 * 10_000,
            0,
            extra
        );
        let events = event::emitted_events<marketplace::Origin>();
        debug::print(&events);

        // Assert
        let user_asset = primary_fungible_store::balance(user, metadata);
        let user_alpha = primary_fungible_store::balance(user, metabase);
        let peer_asset = primary_fungible_store::balance(peer_id, metadata);
        let peer_alpha = primary_fungible_store::balance(peer_id, metabase);
        let marketplace_asset = primary_fungible_store::balance(marketplace_id, metadata);
        let marketplace_alpha = primary_fungible_store::balance(marketplace_id, metabase);
        let inviter_asset = primary_fungible_store::balance(inviter, metadata);
        let inviter_alpha = primary_fungible_store::balance(inviter, metabase);
        let builder_asset = primary_fungible_store::balance(builder, metadata);
        let builder_alpha = primary_fungible_store::balance(builder, metabase);
        assert!(user_asset == 100_000_000);
        assert!(peer_asset == 0);
        assert!(marketplace_asset == 0);
        assert!(inviter_asset == 0);
        assert!(builder_asset == 0);
        assert!(peer_alpha == 0);
        assert!(marketplace_alpha == 2);
        assert!(inviter_alpha == 8);
        assert!(builder_alpha == 10);
        assert!(user_alpha == 1000 - marketplace_alpha - inviter_alpha - builder_alpha);
    }
}