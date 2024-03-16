// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Oracle is Ownable {

    mapping(uint256 => uint256) public marketcaps; // 0-19 - marketcaps and 20 - total marketcap

    function encode(uint80[20] calldata marketcap, uint256 totalMarketCap) external onlyOwner{
        uint256 batch1 = uint256(marketcap[0]);
        batch1 |= uint256(marketcap[1]) << 85;
        batch1 |= uint256(marketcap[2]) << 170;
        
        uint256 batch2 = uint256(marketcap[3]);
        batch2 |= uint256(marketcap[4]) << 85;
        batch2 |= uint256(marketcap[5]) << 170;

        uint256 batch3 = uint256(marketcap[6]);
        batch3 |= uint256(marketcap[7]) << 85;
        batch3 |= uint256(marketcap[8]) << 170;

        uint256 batch4 = uint256(marketcap[9]);
        batch4 |= uint256(marketcap[10]) << 85;
        batch4 |= uint256(marketcap[11]) << 170;
        
        uint256 batch5 = uint256(marketcap[12]);
        batch5 |= uint256(marketcap[13]) << 85;
        batch5 |= uint256(marketcap[14]) << 170;

        uint256 batch6 = uint256(marketcap[15]);
        batch6 |= uint256(marketcap[16]) << 85;
        batch6 |= uint256(marketcap[17]) << 170;

        uint256 batch7 = uint256(marketcap[18]);
        batch7 |= uint256(marketcap[19]) << 85;

        marketcaps[1] = batch1;
        marketcaps[2] = batch2;
        marketcaps[3] = batch3;
        marketcaps[4] = batch4;
        marketcaps[5] = batch5;
        marketcaps[6] = batch6;
        marketcaps[7] = batch7;
        marketcaps[8] = totalMarketCap;
    }

    function decode() external view returns (uint80[] memory result) {

        (result[0], result[1], result[2]) = _shard(marketcaps[1]);
        (result[3], result[4], result[5]) = _shard(marketcaps[2]);
        (result[6], result[7], result[8]) = _shard(marketcaps[3]);
        (result[9], result[10], result[11]) = _shard(marketcaps[4]);
        (result[12], result[13], result[14]) = _shard(marketcaps[5]);
        (result[15], result[16], result[17]) = _shard(marketcaps[6]);
        (result[18], result[19], ) = _shard(marketcaps[7]);
    }

    function getTotalMarketCap() external view returns(uint256 result) {
        return marketcaps[8];
    }

    function _shard(uint256 batch) internal pure returns(uint80,uint80,uint80) {
        uint80 marketcap1 = uint80(batch);
        uint80 marketcap2 = uint80(batch >> 85);
        uint80 marketcap3 = uint80(batch >> 170);

        return(marketcap1, marketcap2, marketcap3);
    }
}
