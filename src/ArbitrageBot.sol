// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interfaces for Aave v3
interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IPool {
    function flashLoanSimple(
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

// Minimal Interface for a DEX (e.g., Uniswap/Sushiswap V2 Router)
interface IDEXRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function WETH() external view returns (address);
}

contract ArbitrageBot is Initializable, IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    address public immutable i_aavePool;
    address public immutable i_routerA;
    address public immutable i_routerB;
    address public immutable i_owner;

    // --- Constructor & Initialization ---
    constructor(address _aavePool, address _routerA, address _routerB) {
        i_aavePool = _aavePool;
        i_routerA = _routerA;
        i_routerB = _routerB;
        i_owner = msg.sender;
    }

    // --- External Functions ---

    /**
     * @notice Initiates the arbitrage by taking a flash loan.
     * @param _asset The token to loan (e.g., DAI, USDC).
     * @param _amount The amount of the token to loan.
     * @param _tokenB The token to swap to (e.g., WETH).
     */
    function startArbitrage(address _asset, uint256 _amount, address _tokenB) external {
        require(msg.sender == i_owner, "Not owner");
        
        // Encode parameters for the executeOperation call.
        // We'll pass the second token address (e.g., WETH)
        bytes memory params = abi.encodePacked(_tokenB);
        
        // Request the flash loan from Aave Pool
        IPool(i_aavePool).flashLoanSimple(
            address(this),
            _asset,
            _amount,
            params,
            0 // referralCode
        );
    }

    /**
     * @notice The callback function from Aave after the loan is issued.
     * @dev This is where the core arbitrage logic happens.
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Only the Aave Pool contract can call this function
        require(msg.sender == i_aavePool, "AAVE_POOL_ONLY");
        require(initiator == i_owner || initiator == address(this), "INITIATOR_MISMATCH");

        // 1. Setup
        address tokenA = asset; // The loaned asset
        address tokenB = abi.decode(params, (address)); // The second asset (e.g., WETH)
        uint256 loanAmount = amount;
        uint256 amountToRepay = amount + premium;

        // 2. Swap 1: Loaned Token (A) -> Second Token (B) on Router A
        // Approve Router A to spend the loaned tokens
        IERC20(tokenA).safeApprove(i_routerA, loanAmount);
        
        address[] memory path1 = new address[](2);
        path1[0] = tokenA;
        path1[1] = tokenB;

        IDEXRouter(i_routerA).swapExactTokensForTokens(
            loanAmount,
            0, // Minimum amount out (slippage protection is crucial here)
            path1,
            address(this),
            block.timestamp
        );

        // 3. Swap 2: Second Token (B) -> Loaned Token (A) on Router B
        // Calculate the amount of Token B received from the first swap
        uint256 receivedTokenB = IERC20(tokenB).balanceOf(address(this));
        
        // Approve Router B to spend the received tokens
        IERC20(tokenB).safeApprove(i_routerB, receivedTokenB);

        address[] memory path2 = new address[](2);
        path2[0] = tokenB;
        path2[1] = tokenA;

        IDEXRouter(i_routerB).swapExactTokensForTokens(
            receivedTokenB,
            amountToRepay, // The minimum we *must* get back to repay the loan
            path2,
            address(this),
            block.timestamp
        );

        // 4. Repay the Loan
        // Check the balance of Token A (the loaned token)
        uint256 finalBalanceTokenA = IERC20(tokenA).balanceOf(address(this));
        
        // The contract must have enough to cover the loan + premium
        require(finalBalanceTokenA >= amountToRepay, "FAILED_TO_REPAY_LOAN");
        
        // Repay Aave Pool
        IERC20(tokenA).safeTransfer(msg.sender, amountToRepay);

        // 5. Transfer Profit
        // Any remaining Token A is profit
        uint256 profit = IERC20(tokenA).balanceOf(address(this));
        if (profit > 0) {
            IERC20(tokenA).safeTransfer(i_owner, profit);
        }
        
        return true;
    }

    // --- Utility Functions ---

    // Function to withdraw accidentally sent ETH
    function withdrawEther() external {
        require(msg.sender == i_owner, "Not owner");
        (bool success,) = payable(i_owner).call{value: address(this).balance}("");
        require(success, "ETH_TRANSFER_FAILED");
    }
}