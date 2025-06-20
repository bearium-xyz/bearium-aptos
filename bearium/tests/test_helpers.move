#[test_only]
module bearium::test_helpers {
    use bearium::peer::{Self, Peer};

    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use std::option;

    public fun apt_apt(fx: &signer, amount: u64): (Object<Metadata>, FungibleAsset) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(fx);
        let coins = coin::mint<AptosCoin>(amount, &mint_cap);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        (
            option::extract(&mut coin::paired_metadata<AptosCoin>()),
            coin::coin_to_fungible_asset(coins),
        )
    }

    public fun make_peer(asset: FungibleAsset, receiver: address): (address, Object<Peer>, Object<Metadata>) {
        let metadata = fungible_asset::metadata_from_asset(&asset);
        let peer_id = peer::iam(metadata);
        let peer = object::address_to_object<Peer>(peer_id);
        let metabase = object::address_to_object<Metadata>(peer_id);
        primary_fungible_store::deposit(receiver, asset);
        (
            peer_id,
            peer,
            metabase
        )
    }
}