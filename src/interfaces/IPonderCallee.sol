// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPonderCallee {
    function ponderCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
