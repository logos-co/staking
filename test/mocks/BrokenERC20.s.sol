// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BrokenERC20 is ERC20 {
    constructor() ERC20("Mock SNT", "SNT") {
        _mint(msg.sender, 1_000_000_000_000_000_000);
    }

    // solhint-disable-next-line no-unused-vars
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }

    // solhint-disable-next-line no-unused-vars
    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }
}
