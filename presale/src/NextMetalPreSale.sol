// SPDX-License-Identifier: MIT

// // // // // // // // // // // // // // // // // // // // // // // // // // // // // // //
//    ███╗   ██╗███████╗██╗  ██╗████████╗  ███╗   ███╗███████╗████████╗ █████╗ ██╗        //
//    ████╗  ██║██╔════╝╚██╗██╔╝╚══██╔══╝  ████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██║        //
//    ██╔██╗ ██║█████╗   ╚███╔╝    ██║     ██╔████╔██║█████╗     ██║   ███████║██║        //
//    ██║╚██╗██║██╔══╝   ██╔██╗    ██║     ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║        //
//    ██║ ╚████║███████╗██╔╝ ██╗   ██║     ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗   //
//    ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝     ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝   //
// // // // // // // // // // // // // // // // // // // // // // // // // // // // // // //

pragma solidity ^0.8.30;

import { Ownable } from "solady/auth/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract NextMetalPreSale is Ownable {
    using SafeTransferLib for address;

    // Token configuration
    uint256 public constant TOTAL_SUPPLY_CAP = 500_000_000 * 10 ** 18;
    uint8 public constant decimals = 18;
    string public name;
    string public symbol;

    // USDC configuration (6 decimals)
    address public immutable USDC;
    address public treasury;

    // Round identifiers
    uint8 public constant ANGEL_ROUND = 0;
    uint8 public constant SEED_ROUND = 1;
    uint8 public constant VC_ROUND = 2;
    uint8 public constant COMMUNITY_ROUND = 3;

    // Round structure
    struct Round {
        uint256 allocation;
        uint256 pricePerToken; // In USDC (6 decimals) per token (18 decimals)
        uint256 sold;
        uint256 minPurchase;
        uint256 maxPurchase;
        bool isActive;
        bool whitelistRequired;
    }

    // Storage
    mapping(uint8 => Round) public rounds;
    mapping(uint8 => mapping(address => bool)) public whitelist;
    mapping(uint8 => mapping(address => uint256)) public purchasedPerRound;
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
    bool public paused;

    // Events
    event PurchaseMade(uint8 indexed roundId, address indexed buyer, uint256 usdcAmount, uint256 tokenAmount);
    event RoundStarted(uint8 indexed roundId);
    event RoundStopped(uint8 indexed roundId);
    event WhitelistToggled(uint8 indexed roundId, bool isActive);
    event WhitelistedAddressAdded(uint8 indexed roundId, address indexed account);
    event WhitelistedAddressRemoved(uint8 indexed roundId, address indexed account);
    event TreasuryUpdated(address indexed oldAddress, address indexed newAddress);
    event Paused();
    event Unpaused();

    // Custom errors
    error InvalidRound();
    error RoundNotActive();
    error NotWhitelisted();
    error BelowMinimumPurchase();
    error ExceedsMaximumPurchase();
    error ContractPaused();
    error InvalidAddress();

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier validRound(uint8 roundId) {
        if (roundId > COMMUNITY_ROUND) revert InvalidRound();
        _;
    }

    constructor(address _usdc, address _treasury, string memory _name, string memory _symbol) {
        if (_usdc == address(0) || _treasury == address(0)) revert InvalidAddress();

        USDC = _usdc;
        treasury = _treasury;
        name = _name;
        symbol = _symbol;

        _initializeOwner(msg.sender);

        // Initialize rounds
        rounds[ANGEL_ROUND] = Round({
            allocation: 5_000_000 * 10 ** 18,
            pricePerToken: 5 * 10 ** 4, // 0.05 USDC
            sold: 0,
            minPurchase: 0,
            maxPurchase: type(uint256).max,
            isActive: false,
            whitelistRequired: false
        });

        rounds[SEED_ROUND] = Round({
            allocation: 5_000_000 * 10 ** 18,
            pricePerToken: 10 * 10 ** 4, // 0.10 USDC
            sold: 0,
            minPurchase: 0,
            maxPurchase: type(uint256).max,
            isActive: false,
            whitelistRequired: false
        });

        rounds[VC_ROUND] = Round({
            allocation: 10_000_000 * 10 ** 18,
            pricePerToken: 18 * 10 ** 4, // 0.18 USDC
            sold: 0,
            minPurchase: 0,
            maxPurchase: type(uint256).max,
            isActive: false,
            whitelistRequired: false
        });

        rounds[COMMUNITY_ROUND] = Round({
            allocation: 10_000_000 * 10 ** 18,
            pricePerToken: 36 * 10 ** 4, // 0.36 USDC
            sold: 0,
            minPurchase: 0,
            maxPurchase: type(uint256).max,
            isActive: false,
            whitelistRequired: false
        });
    }

    // Main purchase function
    function buy(uint8 roundId, uint256 amountUSDC) external whenNotPaused validRound(roundId) {
        Round storage round = rounds[roundId];

        // Check if round is active
        if (!round.isActive) revert RoundNotActive();

        // Check whitelist if required
        if (round.whitelistRequired && !whitelist[roundId][msg.sender]) {
            revert NotWhitelisted();
        }

        // Check minimum purchase
        if (amountUSDC < round.minPurchase) revert BelowMinimumPurchase();

        // Calculate token amount
        uint256 tokenAmount = (amountUSDC * 10 ** 18) / round.pricePerToken;

        // Check if purchase exceeds round allocation
        uint256 availableTokens = round.allocation - round.sold;
        uint256 actualTokenAmount = tokenAmount;
        uint256 actualUSDCAmount = amountUSDC;

        if (tokenAmount > availableTokens) {
            actualTokenAmount = availableTokens;
            actualUSDCAmount = (availableTokens * round.pricePerToken) / 10 ** 18;
        }

        // Check maximum purchase per wallet
        uint256 newPurchaseAmount = purchasedPerRound[roundId][msg.sender] + actualUSDCAmount;
        if (newPurchaseAmount > round.maxPurchase) revert ExceedsMaximumPurchase();

        // Update state
        round.sold += actualTokenAmount;
        totalSupply += actualTokenAmount;
        balanceOf[msg.sender] += actualTokenAmount;
        purchasedPerRound[roundId][msg.sender] = newPurchaseAmount;

        // Transfer only the actual amount to treasury
        USDC.safeTransferFrom(msg.sender, treasury, actualUSDCAmount);

        emit PurchaseMade(roundId, msg.sender, actualUSDCAmount, actualTokenAmount);
    }

    // Admin functions
    function startRound(uint8 roundId) external onlyOwner validRound(roundId) {
        rounds[roundId].isActive = true;
        emit RoundStarted(roundId);
    }

    function stopRound(uint8 roundId) external onlyOwner validRound(roundId) {
        rounds[roundId].isActive = false;
        emit RoundStopped(roundId);
    }

    function setWhitelistRequired(uint8 roundId, bool required) external onlyOwner validRound(roundId) {
        rounds[roundId].whitelistRequired = required;
        emit WhitelistToggled(roundId, required);
    }

    function addToWhitelist(uint8 roundId, address account) external onlyOwner validRound(roundId) {
        if (account == address(0)) revert InvalidAddress();
        whitelist[roundId][account] = true;
        emit WhitelistedAddressAdded(roundId, account);
    }

    function removeFromWhitelist(uint8 roundId, address account) external onlyOwner validRound(roundId) {
        whitelist[roundId][account] = false;
        emit WhitelistedAddressRemoved(roundId, account);
    }

    function setPurchaseLimits(uint8 roundId, uint256 minAmount, uint256 maxAmount)
        external
        onlyOwner
        validRound(roundId)
    {
        rounds[roundId].minPurchase = minAmount;
        rounds[roundId].maxPurchase = maxAmount;
    }

    function setTokenInfo(string memory _name, string memory _symbol) external onlyOwner {
        name = _name;
        symbol = _symbol;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function getRoundInfo(uint8 roundId)
        external
        view
        validRound(roundId)
        returns (
            uint256 allocation,
            uint256 pricePerToken,
            uint256 sold,
            uint256 minPurchase,
            uint256 maxPurchase,
            bool isActive,
            bool whitelistRequired
        )
    {
        Round memory round = rounds[roundId];
        return (
            round.allocation,
            round.pricePerToken,
            round.sold,
            round.minPurchase,
            round.maxPurchase,
            round.isActive,
            round.whitelistRequired
        );
    }
}
