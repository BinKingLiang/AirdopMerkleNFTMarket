// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

contract DiscountToken is ERC20, ERC20Permit {
    constructor() ERC20("DiscountToken", "DTK") ERC20Permit("DiscountToken") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract MerkleNFT is ERC721 {
    uint256 private _tokenIdCounter;

    constructor() ERC721("MerkleNFT", "MNFT") {}

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }
}

contract AirdopMerkleNFTMarket is Multicall {
    DiscountToken public token;
    MerkleNFT public nft;
    bytes32 public merkleRoot;
    mapping(address => bool) public claimed;
    uint256 public nftPrice;
    address public owner;

    event NFTClaimed(address indexed user, uint256 tokenId);

    constructor(address _token, address _nft, bytes32 _merkleRoot, uint256 _nftPrice) {
        token = DiscountToken(_token);
        nft = MerkleNFT(_nft);
        merkleRoot = _merkleRoot;
        nftPrice = _nftPrice;
        owner = msg.sender;
    }

    function permitPrePay(
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        token.permit(tokenOwner, spender, value, deadline, v, r, s);
    }

    function claimNFT(bytes32[] calldata proof) external {
        require(!claimed[msg.sender], "Already claimed");
        require(verifyWhitelist(proof, msg.sender), "Not in whitelist");

        uint256 discountedPrice = nftPrice / 2;
        require(token.transferFrom(msg.sender, owner, discountedPrice), "Token transfer failed");

        uint256 tokenId = nft.mint(msg.sender);
        claimed[msg.sender] = true;

        emit NFTClaimed(msg.sender, tokenId);
    }

    function verifyWhitelist(bytes32[] memory proof, address account) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encode(account));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external {
        require(msg.sender == owner, "Only owner");
        merkleRoot = _merkleRoot;
    }

    function setNFTPrice(uint256 _nftPrice) external {
        require(msg.sender == owner, "Only owner");
        nftPrice = _nftPrice;
    }
}
