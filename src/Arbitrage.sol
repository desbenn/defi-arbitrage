// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IDEX {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract Arbitrage {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Execute a simple arbitrage between two DEXs
    function executeArbitrage(
        address dex1,
        address dex2,
        address token0,
        address token1,
        uint amount
    ) external onlyOwner {
        // ✅ Declare and allocate the path array FIRST
        address ;

        // Approve the first DEX to use our token0
        IERC20(token0).approve(dex1, amount);

        // Swap token0 -> token1 on dex1
        path[0] = token0;
        path[1] = token1;

        uint[] memory amounts1 = IDEX(dex1).swapExactTokensForTokens(
            amount,
            0, // no min for demo
            path,
            address(this),
            block.timestamp
        );

        uint token1Received = amounts1[1];

        // Approve dex2 to use token1
        IERC20(token1).approve(dex2, token1Received);

        // Swap token1 -> token0 on dex2
        path[0] = token1;
        path[1] = token0;

        IDEX(dex2).swapExactTokensForTokens(
            token1Received,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function withdraw(address token) external onlyOwner {
        uint balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        IERC20(token).transfer(owner, balance);
    }
}