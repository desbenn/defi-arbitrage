// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

contract MockDEX {
    // Simple swap with 1% fee
    function swapExactTokensForTokens(
        uint amountIn,
        uint,
        address[] calldata path,
        address to,
        uint
    ) external returns (uint[] memory amounts) {
        require(path.length == 2, "Only token0 -> token1 swaps");
        MockERC20 tokenIn = MockERC20(path[0]);
        MockERC20 tokenOut = MockERC20(path[1]);

        uint fee = amountIn / 100; // 1% fee
        uint amountOut = amountIn - fee;

        tokenIn.transferFrom(msg.sender, address(this), amountIn);
        tokenOut.mint(to, amountOut);

        amounts = new uint ;
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }
}