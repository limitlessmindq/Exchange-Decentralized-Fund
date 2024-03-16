// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPoolManager {
    
    struct PoolInfo {
        bool active;
        address priceFeed;
    }

    function pools(address token) external view returns(bool active, address priceFeed);
    
    function invokeMint(
        address to,
        address tokenIn,
        uint256 amountIn
    ) external;
    
    function invokeBurn(address from, uint256 amountIn, address tokenOut) external;

    function tokenPoolDiscrepancy() external view returns(int256[] memory discrepancy);

    function allPoolTokens(uint256 index) external view returns(address);
    
    function calcAmountOutToken(address tokenIn, uint256 amountIn) external view returns(uint256 amountOut);

    function calcAmountOutEDF(address tokenIn, uint256 amountIn) external view returns(uint256 amountOut);
}
