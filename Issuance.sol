// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "./interfaces/IPoolManager.sol"; 

contract Issuance is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error TheTokenIsNotTrackedByTheIndex();
    error IssuanceZeroCheck();

    IPoolManager public immutable poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function issue(address tokenIn, uint256 amountIn) external nonReentrant {
        (bool active, ) = poolManager.pools(tokenIn);
        
        if (!active) revert TheTokenIsNotTrackedByTheIndex();
        if(amountIn == 0) revert IssuanceZeroCheck();
        
        IERC20(tokenIn).safeTransferFrom(
            msg.sender,
            address(poolManager),
            amountIn
        );       

        poolManager.invokeMint(msg.sender, tokenIn, amountIn);
    }

    function redeem(uint256 amountIn, address tokenOut) external nonReentrant {
        if(amountIn == 0) revert IssuanceZeroCheck();
        
        poolManager.invokeBurn(msg.sender, amountIn, tokenOut);

    }
}
