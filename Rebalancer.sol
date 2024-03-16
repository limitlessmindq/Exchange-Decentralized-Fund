// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "./interfaces/IPoolManager.sol";
import { IPancakeRouter01 } from "./interfaces/IRouterV2.sol";
import { IIssuance } from "./interfaces/IIssuance.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract Rebalancer is IPoolManager, Ownable, ReentrancyGuard {
    // Вся фишка проекта заключается в том, что мы переносим всю работу по выравниванию стаканов на пользователей.
    // Как было: бот на бирже продаёт один токен за другой, в половине случаев, чтобы осуществить операцию, нужно купить промежуточный токен (тот же Dai).
    // Как теперь: пользователь видит, что какой то пул перелит, а какой то пул не долит. Он продаёт мультитокен за перелитый пул, меняет эти монеты на сторонних биржах на монеты недолитого пула. И покупает мультитокен за недолитый пул. В итоге он так на этом зарабатывает. К примеру, у него было 100 мультитокенов, а после того, как он провел этот "арбитраж фонда", у него стало 105 мультитокенов.
    // возможно может быть 2 вида ребаланса:

    // 1 вариант (когда у пользователя изначально нету токенов ETF):

    // работа rebalance контракта:
    // 1) покупка токена фонда за недолитый пул
    // 2) продажа за перелитый пул

    // итог:
    // пользователь получает вознаграждение за выравнивание пулов в Governance токене

    // 2 вариант (когда у пользователя есть токены ETF):

    // 1) продажа токена фонда за перелитый пул
    // 2) покупка токена фонда за недолитый пул

    // итог:
    // пользователь получает вознаграждение за выравнивание пулов в Governance токене
    
    IIssuance public issuance;
    IPoolManager public poolManager;
    IPancakeRouter01 public pancakeV2Router;
    address public WBNB;
    address public share;

    // Filecoin => Filecoin/WBNB Pair
    // mapping(address => address) public pairs;

    enum Action{
        buyAndSell,
        sellAndBuy
    }
    
    error InvalidTokenIn();
    error InvalidValue();
    error Missmatch();

    // сделаю сначала под v2 пулы, а там и v3 добавим. И ограничусь 1-й биржей pancakeswap
    
    // человек отправляет сумму, но нужно вычислить, вдруг эта сумма сбалансирует пул, но не полностью, и возможно не все средства понадобятся для балансировки, поэтому нужно будет вернуть
    
    // поработать со slippage


    function rebalance(Action action, address tokenIn, uint256 amountIn) external payable nonReentrant {
        if(action == Action.buyAndSell) {
            if(tokenIn != WBNB) revert InvalidTokenIn();
            if(amountIn != msg.value) revert InvalidValue();

            uint256 minPosition = minDiscrepancy();
            uint256 maxPosition = maxDiscrepancy();

            address buyPoolToken = poolManager.allPoolTokens(minPosition);
            address[] memory one_path = new address[](2);
            one_path[0] = tokenIn;
            one_path[1] = buyPoolToken;

            address sellPoolToken = poolManager.allPoolTokens(maxPosition);           
            address[] memory two_path = new address[](2);
            two_path[0] = sellPoolToken;
            two_path[1] = tokenIn;

            // поработать со slippage

            uint256 balanceAfter = IERC20(buyPoolToken).balanceOf(address(this));

            pancakeV2Router.swapExactETHForTokens(0, one_path, msg.sender, block.timestamp);

            uint256 balanceBefore = IERC20(buyPoolToken).balanceOf(address(this));

            if(balanceBefore <= balanceAfter) revert Missmatch();

            uint256 amountOut = balanceBefore - balanceAfter;

            uint256 share = poolManager.calcAmountOutToken(buyPoolToken, amountOut);
            uint256 redeemAmoutOut = poolManager.calcAmountOutEDF(sellPoolToken, share);

            issuance.issue(buyPoolToken, amountOut);
            
            issuance.redeem(share, sellPoolToken);

            pancakeV2Router.swapTokensForExactETH(0, redeemAmoutOut, two_path, msg.sender, block.timestamp);


        } else {
            if(tokenIn != share) revert InvalidTokenIn();

            uint256 minPosition = minDiscrepancy();
            uint256 maxPosition = maxDiscrepancy();

            address buyPoolToken = poolManager.allPoolTokens(minPosition);
            address[] memory one_path = new address[](2);
            one_path[0] = tokenIn;
            one_path[1] = buyPoolToken;

            uint256 redeemAmoutOut = poolManager.calcAmountOutEDF(share, amountIn);

            issuance.redeem(amountIn, share);

            uint256 balanceAfter = IERC20(buyPoolToken).balanceOf(address(this));

            pancakeV2Router.swapExactTokensForTokens(redeemAmoutOut, 0, one_path, msg.sender, block.timestamp);

            uint256 balanceBefore = IERC20(buyPoolToken).balanceOf(address(this));

            if(balanceBefore <= balanceAfter) revert Missmatch();

            uint256 amountOut = balanceBefore - balanceAfter;

            issuance.issue(buyPoolToken, amountOut);
        }     
   }

   function minDiscrepancy() public view returns(uint256) {
        int256[] memory discrepancy = poolManager.tokenPoolDiscrepancy();
        uint256 length = discrepancy.length;
        int256 min;
        uint256 position;

        for(uint256 index; index < length; ) {
            min = discrepancy[index];

            if(min > discrepancy[index++]) {
                min = discrepancy[index++];
                position = index;
            }

            unchecked {
                ++index;
            }
        }

        return position;
   }

   function maxDiscrepancy() public view returns(uint256) {
        int256[] memory discrepancy = poolManager.tokenPoolDiscrepancy();
        uint256 length = discrepancy.length;
        int256 max;
        uint256 position;

        for(uint256 index; index < length; ) {
            max = discrepancy[index];

            if(max < discrepancy[index++]) {
                max = discrepancy[index++];
                position = index;
            }

            unchecked {
                ++index;
            }
        }

        return position;
   }
}
