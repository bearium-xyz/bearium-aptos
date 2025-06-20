// SPDX-License-Identifier: BUSL-1.1
module bearium::peer {
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef, TransferRef, FungibleAsset};
    use aptos_framework::object::{Self, Object, ConstructorRef, ExtendRef};
    use aptos_framework::primary_fungible_store;

    use std::option;
    use std::string;
    use std::vector;

    //---------
    // Genesis.
    //---------

    #[event]
    struct Being has drop, store {
        peer_id: address,
        metadata: Object<Metadata>,
    }

    /// A Peer is a capacitor
    /// An autonomous object account
    struct Peer has key {
        metadata: Object<Metadata>,
        auth_ref: ExtendRef, // The signer's right
    }

    struct CreditRights has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    public entry fun new(metadata: Object<Metadata>) {
        iam(metadata);
    }

    public fun iam(metadata: Object<Metadata>): address {
        let maker = @bearium; // peers are public goods
        let constructor_ref = &object::create_sticky_object(maker);
        let peer_id = object::address_from_constructor_ref(constructor_ref);
        let (alpha, metabase) = genesis(constructor_ref, metadata);
        let peer = &object::generate_signer(constructor_ref);
        move_to(
            peer,
            Peer {
                metadata,
                auth_ref: object::generate_extend_ref(constructor_ref),
            }
        );
        move_to(
            peer,
            alpha,
        );
        primary_fungible_store::ensure_primary_store_exists(peer_id, metadata); // capital
        primary_fungible_store::ensure_primary_store_exists(peer_id, metabase); // edge

        event::emit(Being {
            peer_id,
            metadata,
        });

        peer_id
    }

    inline fun genesis(iam: &ConstructorRef, meta: Object<Metadata>): (CreditRights, Object<Metadata>) {
        // Most fields are kept the same as the base asset
        // such as the name and symbol, due to string length limitations.
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            iam,
            option::none(), // unlimited supply
            fungible_asset::name(meta),
            fungible_asset::symbol(meta),
            fungible_asset::decimals(meta),
            fungible_asset::icon_uri(meta),
            string::utf8(b"alpha.apt"),
        );
        (
            CreditRights {
                mint_ref: fungible_asset::generate_mint_ref(iam),
                burn_ref: fungible_asset::generate_burn_ref(iam),
                transfer_ref: fungible_asset::generate_transfer_ref(iam),
            },
            object::object_from_constructor_ref<Metadata>(iam),
        )
    }

    friend fun capture(peer_id: address, stakes: vector<FungibleAsset>) acquires Peer, CreditRights {
        let meta = metadata(peer_id);
        vector::for_each_reverse(stakes, |c| {
            let some = fungible_asset::metadata_from_asset(&c);
            if (some == meta) {
                primary_fungible_store::deposit(peer_id, c)
            } else {
                draw(peer_id, c)
            }
        })
    }

    #[view]
    public fun metadata(peer_id: address): Object<Metadata> acquires Peer {
        Peer[peer_id].metadata
    }

    //-------
    // Alpha.
    //-------

    friend bearium::room;

    friend fun wedge(peer_id: address, alpha: u64): FungibleAsset acquires CreditRights {
        let rights = &CreditRights[peer_id];
        fungible_asset::mint(&rights.mint_ref, alpha)
    }

    fun draw(peer_id: address, credit: FungibleAsset) acquires CreditRights {
        let rights = &CreditRights[peer_id];
        fungible_asset::burn(&rights.burn_ref, credit)
    }
}