// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Importing contracts and libraries
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

// DSCEngine contract definition, inheriting from ReentrancyGuard
contract DSCEngine is ReentrancyGuard {
    // Errors that can be thrown by the contract
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    // Using OracleLib for AggregatorV3Interface type
    using OracleLib for AggregatorV3Interface;

    // State variables and constants
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    // Mappings for token price feeds, collateral deposited, and DSC minted
    mapping(address => address) private s_priceFeeds; // Token to price feed mapping
    mapping(address => mapping(address => uint256)) private s_collateralDeposited; // User to token to amount mapping
    mapping(address => uint256) private s_DSCMinted; // User to DSC minted mapping
    address[] private s_collateralTokens; // Array of collateral tokens

    // Reference to the DecentralizedStableCoin contract
    DecentralizedStableCoin private immutable i_dsc;

    // Events for logging collateral deposits and redemptions
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    // Modifiers to check conditions
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    // Constructor to initialize state variables
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // Function to deposit collateral and mint DSC
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDScToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDScToMint);
    }

    // Function to deposit collateral
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // Function to redeem collateral for DSC
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // Function to redeem collateral
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorBroken(msg.sender);
    }

    // Function to mint DSC
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        _revertIfHealthFactorBroken(msg.sender);
    }

    // Function to burn DSC
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorBroken(msg.sender);
    }

    // Function to liquidate an undercollateralized position
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorBroken(msg.sender);
    }

    // Public view function to get the health factor of a user
    function healthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    // Private function to burn DSC
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    // Private function to redeem collateral
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // Private view function to get account information
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    // Private view function to calculate the health factor of a user
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

   // This function reverts if the health factor of a user is broken
   function _revertIfHealthFactorBroken(address user) internal view {
       uint256 userHealthFactor = _healthFactor(user);
       if (userHealthFactor < MIN_HEALTH_FACTOR) {
           revert DSCEngine__BreaksHealthFactor(userHealthFactor);
       }
   }

   // This function calculates the total value of collateral deposited by a user in USD
   function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
       for (uint256 i = 0; i < s_collateralTokens.length; i++) {
           address token = s_collateralTokens[i];
           uint256 amount = s_collateralDeposited[user][token];
           totalCollateralValueInUsd += getUsdValue(token, amount);
       }
       return totalCollateralValueInUsd;
   }

   // This function converts an amount in USD to the corresponding amount of a token
   function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
       AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
       (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
       return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
   }

   // This function calculates the USD value of a given amount of a token
   function getUsdValue(address token, uint256 amount) public view returns (uint256) {
       AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
       (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
       return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
   }

   // This function returns the account information of a user
   function getAccountInformation(address user) external view returns (uint256, uint256) {
       return _getAccountInformation(user);
   }

   // This function returns the array of collateral tokens
   function getCollateralTokens() external view returns(address[] memory){
       return s_collateralTokens;
   }

   // This function returns the balance of a particular collateral token held by a user
   function getCollateralBalanceOfUser(address token, address user) external view returns(uint256){
       return s_collateralDeposited[user][token];
   }

   // This function returns the price feed of a particular collateral token
   function getCollateralTokenPriceFeed(address token) external view returns(address){
       return s_priceFeeds[token];
   }
}
