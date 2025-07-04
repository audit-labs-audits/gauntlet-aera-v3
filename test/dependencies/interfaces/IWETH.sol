// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "@oz/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}
