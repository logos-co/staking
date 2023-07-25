// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is Ownable, ERC20 {

    constructor() ERC20("Status", "SNT") {

    }

    function mint(address _destination, uint256 _amount) external onlyOwner {
        _mint(_destination, _amount);
    }
}