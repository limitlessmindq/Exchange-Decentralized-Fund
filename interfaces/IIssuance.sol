// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IIssuance {
    function issue(address tokenIn, uint256 amountIn) external returns(uint256);
    function redeem(uint256 amountIn, address tokenOut) external;
}
