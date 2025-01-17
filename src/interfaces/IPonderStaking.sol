// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPonderStaking
 * @notice Interface for the PonderStaking contract
 */
interface IPonderStaking {
    /// @notice Emitted when tokens are staked
    event Staked(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when tokens are withdrawn
    event Withdrawn(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when a rebase occurs
    event RebasePerformed(uint256 totalSupply, uint256 totalPonderBalance);

    /// @notice Stakes PONDER tokens and mints xPONDER
    /// @param amount Amount of PONDER to stake
    /// @return shares Amount of xPONDER minted
    function enter(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraws PONDER tokens by burning xPONDER
    /// @param shares Amount of xPONDER to burn
    /// @return amount Amount of PONDER returned
    function leave(uint256 shares) external returns (uint256 amount);

    /// @notice Performs rebase to distribute accumulated fees
    function rebase() external;

    /// @notice Calculates the amount of PONDER that would be returned for a given amount of xPONDER
    /// @param shares Amount of xPONDER to calculate for
    /// @return Amount of PONDER that would be returned
    function getPonderAmount(uint256 shares) external view returns (uint256);

    /// @notice Calculates the amount of xPONDER that would be minted for a given amount of PONDER
    /// @param amount Amount of PONDER to calculate for
    /// @return Amount of xPONDER that would be minted
    function getSharesAmount(uint256 amount) external view returns (uint256);
}
