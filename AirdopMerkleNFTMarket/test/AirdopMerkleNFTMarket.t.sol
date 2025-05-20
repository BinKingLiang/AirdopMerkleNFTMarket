// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AirdopMerkleNFTMarket.sol";

contract AirdopMerkleNFTMarketTest is Test {
    DiscountToken public token;
    MerkleNFT public nft;
    AirdopMerkleNFTMarket public market;
    
    address owner = address(1);
    address user1 = address(2);
    address user2 = address(3);
    
    bytes32 merkleRoot;
    uint256 nftPrice = 100 ether;

    function setUp() public {
        // Create test wallets with private keys
        uint256 privateKey1 = 0x1234;
        uint256 privateKey2 = 0x5678;
        user1 = vm.addr(privateKey1);
        user2 = vm.addr(privateKey2);
        
        vm.startPrank(owner);
        
        // Deploy contracts
        token = new DiscountToken();
        nft = new MerkleNFT();
        
        // Build Merkle tree
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;
        merkleRoot = getMerkleRoot(whitelist);
        
        // Deploy market
        market = new AirdopMerkleNFTMarket(address(token), address(nft), merkleRoot, nftPrice);
        
        // Transfer tokens to test users
        token.transfer(user1, 1000 ether);
        token.transfer(user2, 1000 ether);
        
        vm.stopPrank();
    }

    function testClaimNFT() public {
        // Generate proof for user1
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;
        bytes32[] memory proof = getMerkleProof(whitelist, user1);
        
        // Debug: print merkle root and proof
        console.log("Merkle Root:", vm.toString(merkleRoot));
        console.log("User1 Proof Length:", proof.length);
        for(uint i = 0; i < proof.length; i++) {
            console.log("Proof %d:", i, vm.toString(proof[i]));
        }
        
        vm.startPrank(user1);
        
        // Approve market to spend tokens
        token.approve(address(market), 50 ether);
        
        // Claim NFT
        market.claimNFT(proof);
        
        vm.stopPrank();
        
        // Verify NFT was minted
        assertEq(nft.ownerOf(0), user1);
        assertTrue(market.claimed(user1));
    }

    function testMulticall() public {
        // Generate proof for user2
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;
        bytes32[] memory proof = getMerkleProof(whitelist, user2);
        
        // Set up test wallet
        uint256 privateKey = 0x5678;
        address signer = vm.addr(privateKey);
        vm.startPrank(signer);
        
        // Prepare permit data
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                            signer,
                            address(market),
                            50 ether,
                            token.nonces(signer),
                            block.timestamp + 1 days
                        )
                    )
                )
            )
        );
        
        // Prepare multicall data
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            market.permitPrePay.selector,
            signer,
            address(market),
            50 ether,
            block.timestamp + 1 days,
            v,
            r,
            s
        );
        calls[1] = abi.encodeWithSelector(
            market.claimNFT.selector,
            proof
        );
        
        // Execute multicall
        market.multicall(calls);
        
        vm.stopPrank();
        
        // Verify NFT was minted
        assertEq(nft.ownerOf(0), user2);
        assertTrue(market.claimed(user2));
    }

    // Helper functions for Merkle tree
    function getMerkleRoot(address[] memory addresses) public pure returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encode(addresses[i]));
        }
        return computeMerkleRoot(leaves);
    }

    function getMerkleProof(address[] memory addresses, address account) public pure returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encode(addresses[i]));
        }
        return computeMerkleProof(leaves, keccak256(abi.encode(account)));
    }

    function computeMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];
        
        bytes32[] memory currentLayer = leaves;
        
        while (currentLayer.length > 1) {
            bytes32[] memory nextLayer = new bytes32[]((currentLayer.length + 1) / 2);
            
            for (uint i = 0; i < currentLayer.length; i += 2) {
                if (i + 1 < currentLayer.length) {
                    nextLayer[i / 2] = keccak256(abi.encodePacked(currentLayer[i], currentLayer[i + 1]));
                } else {
                    nextLayer[i / 2] = currentLayer[i];
                }
            }
            
            currentLayer = nextLayer;
        }
        
        return currentLayer[0];
    }

    function computeMerkleProof(bytes32[] memory leaves, bytes32 leaf) internal pure returns (bytes32[] memory) {
        require(leaves.length > 0, "No leaves provided");
        
        // Find leaf index
        uint256 index;
        bool found = false;
        for (uint i = 0; i < leaves.length; i++) {
            if (leaves[i] == leaf) {
                index = i;
                found = true;
                break;
            }
        }
        require(found, "Leaf not found in tree");
        
        // Compute proof
        bytes32[] memory proof = new bytes32[](log2(leaves.length));
        bytes32[] memory currentLayer = leaves;
        uint currentIndex = index;
        
        for (uint i = 0; i < proof.length; i++) {
            uint siblingIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;
            
            if (siblingIndex < currentLayer.length) {
                proof[i] = currentLayer[siblingIndex];
            }
            
            // Move to parent layer
            currentIndex = currentIndex / 2;
            bytes32[] memory nextLayer = new bytes32[]((currentLayer.length + 1) / 2);
            
            for (uint j = 0; j < currentLayer.length; j += 2) {
                if (j + 1 < currentLayer.length) {
                    nextLayer[j / 2] = keccak256(abi.encodePacked(currentLayer[j], currentLayer[j + 1]));
                } else {
                    nextLayer[j / 2] = currentLayer[j];
                }
            }
            
            currentLayer = nextLayer;
        }
        
        return proof;
    }

    function log2(uint x) internal pure returns (uint n) {
        uint temp = x;
        while (temp > 1) {
            temp >>= 1;
            n++;
        }
    }
}
