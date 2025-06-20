#[test_only]
module bearium::peer_tests {
    use bearium::peer;

    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object;

    use std::option;
    use std::string;
    use std::vector;

    #[test]
    fun test_metadata() {
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        let metadata = option::extract(&mut coin::paired_metadata<AptosCoin>());
        assert!(fungible_asset::decimals(metadata) == 8);

        let peer_id = peer::iam(metadata);
        let metabase = object::address_to_object<Metadata>(peer_id);
        assert!(fungible_asset::decimals(metabase) == 8);
        assert!(fungible_asset::project_uri(metabase) == string::utf8(b"alpha.apt"));

        let events = event::emitted_events<peer::Being>();
        assert!(vector::length(&events) == 1);
    }
}