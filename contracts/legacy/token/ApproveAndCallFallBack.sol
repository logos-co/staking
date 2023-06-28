// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.4.20;
abstract contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 _amount, address _token, bytes memory _data) virtual public;
}
