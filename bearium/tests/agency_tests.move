#[test_only]
module bearium::agency_tests {
    use bearium::marketplace;
    use bearium::peer::{Self, Peer};
    use bearium::room;

    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use std::bcs;
    use std::debug;
    use std::option;
    use std::signer;

    #[test(
        fx = @aptos_framework,
        bearium = @bearium,
        host = @0x42,
        player = @0xcafe,
    )]
    fun test_agency(
        fx: &signer,
        bearium: &signer,
        host: &signer,
        player: &signer,
    ) {
        // Room
        room::init_module_test(bearium);
        
        // Agency
        room::register_agent<marketplace::Origin>();

        // Marketplace
        let marketplace_id = marketplace::iam(host, 20, 80);
        let extra = bcs::to_bytes(&marketplace_id);

        // Referral
        let inviter = @0xc0ffee;
        marketplace::bond(player, marketplace_id, inviter);
        
        // APT peer
        let (metadata, asset) = apt_apt(fx, 100_000_000);
        let peer_id = peer::iam(metadata);
        let peer = object::address_to_object<Peer>(peer_id);
        let metabase = object::address_to_object<Metadata>(peer_id);
        let user = signer::address_of(player);
        primary_fungible_store::deposit(user, asset);

        // Agent
        let stakes = room::hold(player, peer, 1000, 0);
        room::disburse<marketplace::Origin>(
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
        assert!(user_asset == 100_000_000);
        assert!(peer_asset == 0);
        assert!(marketplace_asset == 0);
        assert!(inviter_asset == 0);
        assert!(peer_alpha == 0);
        assert!(marketplace_alpha == 4);
        assert!(inviter_alpha == 16);
        assert!(user_alpha == 1000 - marketplace_alpha - inviter_alpha);
    }

    fun apt_apt(fx: &signer, amount: u64): (Object<Metadata>, FungibleAsset) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(fx);
        let coins = coin::mint<AptosCoin>(amount, &mint_cap);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        (
            option::extract(&mut coin::paired_metadata<AptosCoin>()),
            coin::coin_to_fungible_asset(coins),
        )
    }
}