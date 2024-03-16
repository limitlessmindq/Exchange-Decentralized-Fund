// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { DataConsumerV3 } from "./DataConsumer.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IPoolManager } from "./interfaces/IPoolManager.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { IIndexToken } from "./interfaces/IIndexToken.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract PoolManager is IPoolManager, IOracle, DataConsumerV3, AccessControl { // изменить на не абсктракт и пофиксить ошибку
    using SafeERC20 for IERC20Metadata;

    bytes32 public constant ISSUANCE_ROLE = keccak256("ISSUANCE_ROLE");

    event PoolManagerEmergencySet(bool emergency);
    event PoolManagerIssuanceSet(address issuence);

    error TheTokenIsNotTrackedByTheIndex();

    error PoolManagerOnly(address who);
    error PoolManagerEmergency();
    error PoolManagerZeroCheck();

    IOracle public immutable oracle;
    IIndexToken public immutable indexToken;
    
    uint256 public constant initialPrice = 0.2 * 10 ** 8;
    uint256 public immutable coefficient; 
    address public issuance;

    bool public emergency;

    address[] public allPoolTokens; // sorted based on the index
    mapping(address => IPoolManager.PoolInfo) public pools;

    constructor(address[] memory _tokens, IPoolManager.PoolInfo[] memory _poolInfo, uint256 _coefficient, address _issuance, address _indexToken, address _oracle) {
        coefficient = _coefficient;
        issuance = _issuance;
        indexToken = IIndexToken(_indexToken);
        oracle = IOracle(_oracle);
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ISSUANCE_ROLE, issuance);

        _initialize(_tokens, _poolInfo);
    }

    modifier whenNotEmergency() {
        if (emergency) {
            revert PoolManagerEmergency();
        }
        _;
    }

    function _initialize(address[] memory tokens, IPoolManager.PoolInfo[] memory poolInfo) internal {
        uint256 length = tokens.length;

        for(uint256 index; index < length; ) {
            allPoolTokens.push(tokens[index]);

            pools[tokens[index]] = poolInfo[index];

            unchecked {
                ++index;
            }
        }   
    }

    function EDF_In_USD() public view returns(uint256 currentPrice) {        
        if(indexToken.totalSupply() == 0) {
            currentPrice = initialPrice; 
        } else {
            uint256 totalFundCap = totalFundCapitalization();

            currentPrice = (totalFundCap * 10**18) / coefficient / 10**10;
        }
    }

    function EDF_In_TokenIn(address tokenIn) public view returns(uint256 currentPrice) {
        address priceFeed = pools[tokenIn].priceFeed;
        int tokenInPrice = getChainlinkDataFeedLatestAnswer(priceFeed);
        uint256 priceEdfInUSD = EDF_In_USD();
        uint8 decimals = IERC20Metadata(tokenIn).decimals();

        if(indexToken.totalSupply() == 0) {
            currentPrice = (initialPrice * 10**decimals) / uint256(tokenInPrice); 
        } else {
            currentPrice = (priceEdfInUSD * 10**decimals) / uint256(tokenInPrice);
        }
    }

    function tokenInInEDF(address tokenIn) public view returns(uint256 currentPrice) {
        address priceFeed = pools[tokenIn].priceFeed;
        int tokenInPrice = getChainlinkDataFeedLatestAnswer(priceFeed);
        uint256 priceEdfInUSD = EDF_In_USD();
        uint8 decimals = IERC20Metadata(tokenIn).decimals();

        currentPrice = (uint256(tokenInPrice) * 10**decimals) / priceEdfInUSD;
    }
    
    // получить количество монет (EDF), которые получит пользователь при отправке определенного количества bnb and other coin

    function calcAmountOutToken(address tokenIn, uint256 amountIn) public view returns(uint256 amountOut) {
        uint256 currentPrice = EDF_In_TokenIn(tokenIn);

        amountOut = (amountIn * 10**18) / currentPrice;
    }

    function calcAmountOutEDF(address tokenIn, uint256 amountIn) public view returns(uint256 amountOut) {
        uint256 currentPrice = tokenInInEDF(tokenIn);

        amountOut = (amountIn * 10**18) / currentPrice;
    }

    function calcPercentDiscrepancy(address token) public view returns(int256 percentage) {
        uint256 targetPoolTokenCount = singleTargetPoolTokenCount(token);
        int256 tokenPoolDiscrepancy = singleTokenPoolDiscrepancy(token);

        // Проценты = (Часть / Целое) * 100
        percentage = (tokenPoolDiscrepancy * 10000) / int256(targetPoolTokenCount);
        
    }


    // function calcFee(address token) public view returns(uint256 deposit_fee, uint256 withdraw_fee) {
    //     int256 percentage = calcPercentDiscrepancy(token);
    // }
    
    function invokeMint(
        address to,
        address tokenIn,
        uint256 amountIn
    ) external whenNotEmergency onlyRole(ISSUANCE_ROLE) {
        uint256 amountOut = calcAmountOutToken(tokenIn, amountIn);
        
        indexToken.mint(to, amountOut);
    }

    function invokeBurn(address from, uint256 amountIn, address tokenOut) external onlyRole(ISSUANCE_ROLE) {
        uint256 amountOut = calcAmountOutEDF(tokenOut, amountIn);

        indexToken.burnFrom(from, amountIn);

        IERC20Metadata(tokenOut).safeTransfer(
            from,
            amountOut
        );       
    }

    function setIssuence(address _issuance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(_issuance == address(0)) revert PoolManagerZeroCheck();
        issuance = _issuance;
        emit PoolManagerIssuanceSet(_issuance);
    }

    function setEmergency(bool _emergency) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergency = _emergency;
        emit PoolManagerEmergencySet(_emergency);
    }

    function updateIndex(address[] calldata pools, address[] calldata poolTokens, IPoolManager.PoolInfo[] calldata poolInfo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updatePools(pools, poolInfo);
        _updatePoolTokens(poolTokens);
    }

    function _updatePools(address[] calldata _pools, IPoolManager.PoolInfo[] calldata _poolInfo) internal {
        require(_pools.length == _poolInfo.length, "error");
        uint256 length = _pools.length;

        for(uint256 index; index < length; ) {
            pools[_pools[index]] = _poolInfo[index];

            unchecked {
                ++index;
            }
        }
    }

    function _updatePoolTokens(address[] calldata poolTokens) internal {
        uint256 length = poolTokens.length;

        for(uint256 index; index < length; ) {
            allPoolTokens[index] = poolTokens[index];

            unchecked {
                ++index;
            }
        }
        
    }
    
    function fundTokenCount(address token) public view returns(uint256 balance) {
        balance = IERC20Metadata(token).balanceOf(address(this));
    }
    
    function fundTokensCount() public view returns(uint256[] memory) {
        uint256 length =  allPoolTokens.length;
        uint256[] memory result = new uint256[](length);

        for(uint256 index; index < length; ) {
            uint256 balance = IERC20Metadata(allPoolTokens[index]).balanceOf(address(this));
            result[index] = balance;

            unchecked {
                ++index;
            }
        }
        
        return result;
    }
    
    // процентная доля на рынке

    function singleMarketSharePercentage(address token) public view returns(uint256 percentage) {
        uint80[] memory marketcaps = oracle.decode();
        uint256 totalMarketCap = oracle.getTotalMarketCap();
        uint80 marketcap;
        uint256 length = allPoolTokens.length;

        for(uint256 index; index < length; ) {
            if(allPoolTokens[index] == token) {
                marketcap = marketcaps[index];
            }

            unchecked {
                ++index;
            }
        }

        percentage = (marketcap * 10**18) / totalMarketCap / 100;
    }

    function marketSharePercentage() public view returns(uint256[] memory percentages) {
        uint80[] memory marketcaps = oracle.decode();
        uint256 totalMarketCap = oracle.getTotalMarketCap();
        uint256 length = marketcaps.length;

        for(uint256 index; index < length; ) {
            percentages[index] = (marketcaps[index] * 10**18) / totalMarketCap / 100;

            unchecked {
                ++index;
            }
        }
    }

    // капитализация в фонде

    function singleFundCapitalization(address token) public view returns(uint256 cap) {
        uint256 tokenCount = fundTokenCount(token);
        int256 price = getSinglePrice(token);

        cap = tokenCount * uint256(price);
    }

    function fundCapitalization() public view returns(uint256[] memory caps) {
        uint256[] memory tokensCount = fundTokensCount();
        int256[] memory prices = getMultiplePrices();
        uint256 length = tokensCount.length;

        for(uint256 index; index < length; ) {
            caps[index] = tokensCount[index] * uint256(prices[index]);

            unchecked {
                ++index;
            }
        }

    }

    // общая капитализация в фонде

    function totalFundCapitalization() public view returns(uint256 totalFundCap) {
        uint256[] memory caps = fundCapitalization(); 
        uint256 length = caps.length;

        for(uint256 index; index < length; ) {
            totalFundCap += caps[index];

            unchecked {
                ++index;
            }
        }
    }

    // целевая капитализация

    function singleTargetCapitalization(address token) public view returns(uint256 targetCap) {
        uint256 totalFundCap = totalFundCapitalization();
        uint256 sharePercentage = singleMarketSharePercentage(token);

        targetCap = (totalFundCap * sharePercentage) / 100;
    }

    function targetCapitalization() public view returns(uint256[] memory targetCap) {
        uint256 totalFundCap = totalFundCapitalization();
        uint256[] memory sharePercentages = marketSharePercentage();
        uint256 length = sharePercentages.length;

        for(uint256 index; index < length; ) {
            targetCap[index] = (totalFundCap * sharePercentages[index]) / 100;

            unchecked {
                ++index;
            }
        }
    }

    // целевое количество монет в пуле

    function singleTargetPoolTokenCount(address token) public view returns(uint256 targetTokenCount) {
        int256 price = getSinglePrice(token);
        uint256 targetCap = singleTargetCapitalization(token);

        targetTokenCount = (uint256(price) * 10**18) / targetCap;
    }

    function targetPoolTokenCount() public view returns(uint256[] memory targetTokenCount) {
        int256[] memory prices = getMultiplePrices();
        uint256[] memory targetCap = targetCapitalization();
        uint256 length = targetTokenCount.length;

        for(uint256 index; index < length; ) {
            targetTokenCount[index] = (uint256(prices[index]) * 10**18) / targetCap[index];

            unchecked {
                ++index;
            }
        }
    }

    // Избыток или недостача монет

    function singleTokenPoolDiscrepancy(address token) public view returns(int256 discrepancy) {
        uint256 targetTokenCount = singleTargetPoolTokenCount(token);
        uint256 fundTokenCount = fundTokenCount(token);

        discrepancy = int256(targetTokenCount - fundTokenCount);
    }

    function tokenPoolDiscrepancy() public view returns(int256[] memory discrepancy) {
        uint256[] memory targetTokenCount = targetPoolTokenCount();
        uint256[] memory fundTokensCount = fundTokensCount();
        uint256 length = targetTokenCount.length;

        for(uint256 index; index < length; ) {
            discrepancy[index] = int256(targetTokenCount[index] - fundTokensCount[index]);

            unchecked {
                ++index;
            }
        }
    }

    // получение цен

    function getSinglePrice(address token) public view returns(int256 price) {
        price = getChainlinkDataFeedLatestAnswer(token);
    }

    function getMultiplePrices() public view returns(int256[] memory prices) {
        uint256 length = allPoolTokens.length;

        for(uint256 index; index < length; ) {
            prices[index] = getChainlinkDataFeedLatestAnswer(allPoolTokens[index]);

            unchecked {
                ++index;
            }
        }
    }
}
