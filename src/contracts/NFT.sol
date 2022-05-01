// SPDX-License-Identifier: MIT
// Creator: DDD(DeDogma DAO)

pragma solidity 0.8.4;

import './library/DTERC721A.sol';
import './library/DTOwnable.sol';
import './library/DTAuth.sol';

import './interfaces/IERC2981Royalties.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

// add test for setOwnersExplicit
// add test for transferfrom and approve
// TODO: msg.sender or _msgSender()
// TODO: @audit different compiler version issue between library and main contract
contract NFT is DTERC721A, DTOwnable, DTAuth,ReentrancyGuard, IERC2981Royalties {
    using ECDSA for bytes32;

    // *******************************************************************************
    //           |                   |                  |                     |
    //  _________|________________.=""_;=.______________|_____________________|_______
    // |                   |  ,-"_,=""     `"=.|                  |
    // |___________________|__"=._o`"-._        `"=.______________|___________________
    //           |                `"=._o`"=._      _`"=._                     |
    //  _________|_____________________:=._o "=._."_.-="'"=.__________________|_______
    // |                   |    __.--" , ; `"=._o." ,-"""-._ ".   |
    // |___________________|_._"  ,. .` ` `` ,  `"-._"-._   ". '__|___________________
    //           |           |o`"=._` , "` `; .". ,  "-._"-._; ;              |
    //  _________|___________| ;`-.o`"=._; ." ` '`."\` . "-._ /_______________|_______
    // |                   | |o;    `"-.o`"=._``  '` " ,__.--o;   |
    // |___________________|_| ;     (#) `-.o `"=.`_.--"_o.-; ;___|___________________
    // ____/______/______/___|o;._    "      `".o|o_.--"    ;o;____/______/______/____
    // /______/______/______/_"=._o--._        ; | ;        ; ;/______/______/______/_
    // ____/______/______/______/__"=._o--._   ;o|o;     _._;o;____/______/______/____
    // /______/______/______/______/____"=._o._; | ;_.--"o.--"_/______/______/______/_
    // ____/______/______/______/______/_____"=.o|o_.--""___/______/______/______/____
    // /______/______/______/______/______/______/______/______/______/______/____/___
    // *******************************************************************************

    // State variables
    uint16 public constant MAX_SUPPLY = 7777;
    uint256 public upgradeRequestFeeInWei;

    struct ContractState {
        bool initilized;
        bool auctionIsActive;
        bool whitelistMintingIsActive;
        bool mintingIsActive;
        bool artIsRevealed;
        bool finished;
    }
    ContractState public state;

    struct ContractAddresses {
        address owner;
        address platformMultisig;
        address decentralTitan;
        address daoTreasuryContract;
        address whiteListVerifier;
        address royaltyFeeReceiverContract;
    }
    ContractAddresses public addresses;

    struct ContractIPFS {
        string godCID;
        string notRevealedArtCID;
        string artCID;
    }
    ContractIPFS public ipfs;

    uint256 constant public MINT_PRICE_IN_WEI = 0.05 * 10**18;
    uint16 constant public MAX_MINT_PER_ADDRESS = 3;
    uint256 immutable public AUCTION_START_TIME ; // epoch time
    uint8 constant public NUMBER_OF_TOKEN_FOR_AUCTION = 3;
    uint256 constant public AUCTION_DURATION = 86400; // in seconds
    uint8 constant public ROYALTY_FEE_PERCENT = 10;
    uint256 constant public AUCTION_DROP_INTERVAL = 600; // in seconds
    uint8 constant private NUMBER_OF_ACTOR = 2;

   

    struct RoyaltyInfo {
        address recipeint;
        uint8 percent;
    }
    RoyaltyInfo private _royaltyes;

    mapping(uint16 => bool) public tokenIsUpgraded;
    mapping(uint16 => string) private _upgradedTokenCIDs;
    mapping(uint16 => bool) public isGodToken;

    struct AuctionConfig {
        uint256 startPrice; // in wei
        uint256 endPrice; // in wei
        uint256 auctionDropPerStep; // in wei
    }
    struct Auction {
        uint8 tokenId;
        uint256 startAt; // epoch time
        uint256 expireAt; // epoch time
        uint256 startPrice; // in wei
        uint256 endPrice; // in wei
        uint256 auctionDropPerStep; // in wei
        bool isSold;
    }
    mapping(uint8 => Auction) public auctions;

    mapping(uint256 => bool) public upgradeRequestFeeIsPaid;

    // Events
    event UpgradeRequestPayment(uint16 tokenId, uint256 value);
    event TokenUpgraded(uint16 tokenId);
    event AuctionsInitialized(uint8 numberOfGods, uint256 startTimeStamp);

    // Enums
    enum WhiteListType {
        NORMAL,
        ROYAL
    }

    enum Actors {
        PLATFORM_MULTISIG,
        DECENTRAL_TITAN
    }

    // Modifiers
    modifier whileAuctionIsActive() {
        require(state.auctionIsActive, 'Not Activated');
        _;
    }
    modifier whileMintingIsActive() {
        require(state.mintingIsActive, 'Not Activated');
        _;
    }
    modifier whileWhiteListMintingIsActive() {
        require(state.whitelistMintingIsActive, 'Not Activated');
        _;
    }
    modifier whileMintingDone() {
        require(state.finished, 'Not Finished');
        require(state.initilized, 'Not Initialized');
        _;
    }

    modifier onlyPlatform() {
        require(addresses.platformMultisig == _msgSender(), 'Only Platform Address');
        _;
    }
    modifier onlyDecentralTitan() {
        require(addresses.decentralTitan == _msgSender(), 'Only DECENTRAL_TITAN');
        _;
    }

    modifier onlyHuman(uint16 tokenId_) {
        require(!isGodToken[tokenId_], 'Only Humans');
        _;
    }

    constructor(
        ContractAddresses memory _addresses,
        string memory godCID_,
        string memory _notRevealedArtCID,
        uint256 _upgradeRequestFeeInWei
    ) DTERC721A('DemmortalTreasure', 'DT') DTOwnable(_addresses.owner) DTAuth(NUMBER_OF_ACTOR) {
        state = ContractState(false, false, false, false, false, false);
        addresses.decentralTitan = _addresses.decentralTitan;
        addresses.owner = _addresses.owner;
        //TODO: use DTAuth in this contract
        addresses.platformMultisig = _addresses.platformMultisig;
        addresses.whiteListVerifier = _addresses.whiteListVerifier;
        ipfs.godCID = godCID_;
        ipfs.notRevealedArtCID = _notRevealedArtCID;
        upgradeRequestFeeInWei = _upgradeRequestFeeInWei;
        //Todo remove it during final deploy and input it as constant variable
        AUCTION_START_TIME = block.timestamp;
    }

    receive() external payable {
        revert('Not Allowed');
    }

    fallback() external payable {
        revert('Call Valid Function');
    }

    // State Management related functions.
    function initializer(
        AuctionConfig[] calldata configs,
        address daoTresury,
        address royaltyReceiverContract
    ) external onlyOwner {
        require(!state.initilized, 'Already Initialized');
        require(!state.finished, 'Already Finished');
        require(!state.auctionIsActive, 'Already Activated');
        state.initilized = true;
        _setupGodAuction(configs);
        state.auctionIsActive = true;
        addresses.daoTreasuryContract = daoTresury;
        addresses.royaltyFeeReceiverContract = royaltyReceiverContract;
        _setRoyalties(addresses.royaltyFeeReceiverContract, ROYALTY_FEE_PERCENT);
    }

    function revealArt(string memory ipfsCid) external onlyOwner {
        require(!state.artIsRevealed, 'Already Revealed');
        uint256 len = bytes(ipfsCid).length;
        require(len > 0, 'CID Is Empty');
        ipfs.artCID = ipfsCid;
        state.artIsRevealed = true;
    }

    //todo move this set address to auth contract and do it in two step change address manner
    function setPlatform(address platform) external onlyPlatform {
        addresses.platformMultisig = platform;
    }

    function setBuyBackTreasury(address buyBackTreasury) external onlyPlatform {
        addresses.daoTreasuryContract = buyBackTreasury;
    }

    function setRoyaltyReceiver(address royaltyDistributerContract) external onlyPlatform {
        addresses.royaltyFeeReceiverContract = royaltyDistributerContract;
        _setRoyalties(addresses.royaltyFeeReceiverContract, ROYALTY_FEE_PERCENT);
    }

    function setUpgradeRequestFeeInWei(uint256 _upgradeRequestFeeInWei) external onlyDecentralTitan whileMintingDone {
        upgradeRequestFeeInWei = _upgradeRequestFeeInWei;
    }

    function startWhiteListMinting() external onlyOwner {
        require(state.initilized, 'Not Initialized');
        require(!state.finished, 'Already Finished');
        require(!state.whitelistMintingIsActive, 'Already Activated');
        state.whitelistMintingIsActive = true;
    }

    function startPublicMinting() external onlyOwner {
        require(!state.finished, 'Already Finished');
        require(!state.mintingIsActive, 'Already Activated');
        require(state.whitelistMintingIsActive, 'Priority Issue');
        state.mintingIsActive = true;
    }

    function finishAuction() external onlyDecentralTitan {
        require(!state.finished, 'Already Finished');
        require(state.initilized, 'Not Initialized');
        require(state.auctionIsActive, 'Not Activated');
        state.auctionIsActive = false;
    }

    function finishMinting() external onlyDecentralTitan {
        require(!state.finished, 'Already Finished');
        require(state.mintingIsActive, 'Not Activated');
        state.mintingIsActive = false;
        state.auctionIsActive = false;
        state.whitelistMintingIsActive = false;
        state.finished = true;
    }

    function updateCID(string memory GodCid, string memory HumanCid) external onlyPlatform {
        uint256 len1 = bytes(GodCid).length;
        if (len1 > 0) {
            ipfs.godCID = GodCid;
        }

        uint256 len2 = bytes(HumanCid).length;
        if (len2 > 0) {
            ipfs.artCID = HumanCid;
        }
    }

    // Auction related functions.

    function buyAGodInAuction(uint8 day) external payable whileAuctionIsActive {
        // buy god
        // require contract in the state of active auction
        require(1 <= day && day <= NUMBER_OF_TOKEN_FOR_AUCTION, 'Day Is Out Of Range');
        require(auctions[day].startAt <= block.timestamp, 'Not Started Yet');
        require(auctions[day].expireAt >= block.timestamp, 'Expired');

        Auction memory auction = auctions[day];
        TokenOwnership memory ownership = ownershipOf(auction.tokenId);
        require(!auction.isSold, 'Already Sold');
        require(ownership.addr == addresses.decentralTitan, 'Bad Initialization');

        uint256 currentPrice = _getAuctionPrice(auction);

        require(auction.endPrice <= currentPrice, 'Receive To Base Price');
        require(currentPrice <= msg.value, 'Not Enough Ether');

        _auctionTransfer(addresses.decentralTitan, msg.sender, auction.tokenId);

        _transferEth(addresses.platformMultisig, msg.value);
        auctions[day].isSold = true;
    }

    function getAuctionPrice(uint8 day) external view whileAuctionIsActive returns (uint256) {
        require(1 <= day && day <= NUMBER_OF_TOKEN_FOR_AUCTION, 'day is out of range');

        Auction memory auction = auctions[day];
        return _getAuctionPrice(auction);
    }

    function whitelistMinting(
        uint8 maxQuantity,
        uint8 quantity,
        WhiteListType whiteListType,
        bytes calldata sig
    ) external payable whileWhiteListMintingIsActive {
        require(isWhitelisted(msg.sender, maxQuantity, whiteListType, sig), 'Bad Signature');
        require(_totalMinted() + quantity <= MAX_SUPPLY, 'Receive To Max Supply');

        uint8 _aux = _getAux(msg.sender);

        require(_aux + quantity <= maxQuantity, 'Receive To Max Quantity');

        if (whiteListType == WhiteListType.ROYAL) {
            _setAux(msg.sender, _aux + quantity);
            _safeMint(msg.sender, quantity);
        } else {
            require(quantity * MINT_PRICE_IN_WEI <= msg.value, 'Not Enoughs Ether');
            _setAux(msg.sender, _aux + quantity);
            _safeMint(msg.sender, quantity);
        }
        if (msg.value > 0) {
            _transferEth(addresses.daoTreasuryContract, msg.value);
        }
    }

    function publicMint(uint256 quantity) external payable whileMintingIsActive {
        require(_totalMinted() + quantity <= MAX_SUPPLY, 'Receive To Max Supply');
        require(_numberMinted(msg.sender) + quantity <= MAX_MINT_PER_ADDRESS, 'Receive To Max Mint Per Address');
        require(quantity * MINT_PRICE_IN_WEI <= msg.value, 'Not Enoughs Ether');
        _safeMint(msg.sender, quantity);
        _transferEth(addresses.daoTreasuryContract, msg.value);
    }

    // Token Upgradeability related functions.
    function upgradeTokenRequestFee(uint16 tokenId) external payable whileMintingDone onlyHuman(tokenId) {
        require(_exists(tokenId), 'Token Not Exists');
        require(upgradeRequestFeeInWei <= msg.value, 'Not Enoughs Ether');

        upgradeRequestFeeIsPaid[tokenId] = true;

        _transferEth(addresses.platformMultisig, msg.value);
        emit UpgradeRequestPayment(tokenId, msg.value);
    }

    function upgradeToken(
        string memory ipfsCid,
        uint16 tokenId,
        bool isGodNow
    ) external whileMintingDone onlyOwner onlyHuman(tokenId) {
        uint256 len = bytes(ipfsCid).length;
        require(len > 0, 'CID is empty');
        require(upgradeRequestFeeIsPaid[tokenId], 'Upgrade Request Fee Not Paid');
        upgradeRequestFeeIsPaid[tokenId] = false;
        _upgradedTokenCIDs[tokenId] = ipfsCid;
        tokenIsUpgraded[tokenId] = true;
        if (isGodNow) {
            isGodToken[tokenId] = true;
        }
        emit TokenUpgraded(tokenId);
    }

    function buyBackToken(uint16 tokenId) external onlyHuman(tokenId) nonReentrant {
        require(_exists(tokenId), 'Token Not Exists');
        TokenOwnership memory ownership = ownershipOf(tokenId);
        require(msg.sender == ownership.addr, 'Is Not Owner');
        _burn(tokenId);
        // TODO: in here we should call function from BuyBack treasury contract and give it the msg.sender as a parameter
    }

    function royaltyInfo(uint256, uint256 value)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = _royaltyes.recipeint;
        royaltyAmount = (value * _royaltyes.percent) / 100;
    }

    // @audit-ok i think we dont need accsess modifire like onlyOwner for this function. double check it.
    function setOwnersExplicit(uint256 quantity) external {
        _setOwnersExplicit(quantity);
    }

    function tokenURI(uint256 tokenId_) public view override returns (string memory) {
        require(_exists(tokenId_), 'Token Not Exists');

        uint16 id = uint16(tokenId_);

        if (tokenIsUpgraded[id]) {
            return string(abi.encodePacked(_upgradedTokenCIDs[id]));
        } else if (isGodToken[id]) {
            return string(abi.encodePacked(ipfs.godCID, '/', Strings.toString(id)));
        } else if (state.artIsRevealed) {
            return string(abi.encodePacked(ipfs.artCID, '/', Strings.toString(id)));
        } else {
            return string(abi.encodePacked(ipfs.notRevealedArtCID));
        }
    }

    function isWhitelisted(
        address account_,
        uint8 maxQuantity_,
        WhiteListType whiteListType_,
        bytes calldata sig_
    ) public view returns (bool) {
        bytes32 msgHash = prefixed(keccak256(abi.encodePacked(account_, maxQuantity_, whiteListType_)));
        return ECDSA.recover(msgHash, sig_) == addresses.whiteListVerifier;
    }

    function _setRoyalties(address recipient, uint8 value) internal {
        _royaltyes = RoyaltyInfo(recipient, uint8(value));
    }

    function _getAuctionPrice(Auction memory auction_) internal view returns (uint256) {
        if (block.timestamp < auction_.startAt) {
            return auction_.startPrice;
        }
        if (block.timestamp > auction_.expireAt) {
            return auction_.endPrice;
        }
        uint256 elapsedTime = block.timestamp - auction_.startAt;
        uint256 steps = elapsedTime / AUCTION_DROP_INTERVAL;
        return auction_.startPrice - (steps * auction_.auctionDropPerStep);
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', hash));
    }

    function _setupGodAuction(AuctionConfig[] memory configs) private {
        require(_totalMinted() + NUMBER_OF_TOKEN_FOR_AUCTION <= MAX_SUPPLY, 'Receive To Max Supply');
        require(configs.length == NUMBER_OF_TOKEN_FOR_AUCTION, 'Bad Configs Length');

        _safeMint(addresses.decentralTitan, NUMBER_OF_TOKEN_FOR_AUCTION);

        // we need set first token id to the token sell in auction for CID availability.
        require(_totalMinted() == NUMBER_OF_TOKEN_FOR_AUCTION, 'Bad Initialization');

        for (uint8 i = 0; i < NUMBER_OF_TOKEN_FOR_AUCTION; i++) {
            Auction memory _auction = Auction(
                i,
                AUCTION_START_TIME + AUCTION_DURATION * i,
                AUCTION_START_TIME + AUCTION_DURATION * (i + 1),
                configs[i].startPrice,
                configs[i].endPrice,
                configs[i].auctionDropPerStep,
                false
            );
            auctions[i + 1] = _auction;
            isGodToken[i] = true;
        }
    }

    function _transferEth(address to_, uint256 amount) private {
        address payable to = payable(to_);
        (bool sent, ) = to.call{value: amount}('');
        require(sent, 'Transfer Failed');
    }

    // @audit are we need a withdraw function due we don't keep any fund in the contract?
}
