// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {StakeManager} from "../../contracts/StakeManager.sol";

contract StakeManagerNew is StakeManager {
    constructor(address token, address oldManager) StakeManager(token, oldManager) {}
}
