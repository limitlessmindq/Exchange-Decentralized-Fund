// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOracle {
    function decode() external view returns (uint80[] memory result);
    function getTotalMarketCap() external view returns(uint80 result);
}
