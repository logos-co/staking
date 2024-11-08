// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.26;

/**
 * @title Singleton Factory (EIP-2470)
 * @notice Exposes CREATE2 (EIP-1014) to deploy bytecode on deterministic addresses based on initialization code and
 * salt.
 * @author Ricardo Guilherme Schmidt (Status Research & Development GmbH)
 */
library AddressLib {
    error ERC2470__CREATE2Failed();
    error ERC2470__CREATE2BadCall();

    function deploy(bytes memory _initCode, bytes32 _salt) internal returns (address payable createdContract) {
        assembly {
            createdContract := create2(callvalue(), add(_initCode, 0x20), mload(_initCode), _salt)
        }
        if (createdContract == address(0)) {
            revert ERC2470__CREATE2Failed();
        }
    }

    function computeAddress(bytes memory, bytes32 _salt) public view returns (address payable) {
        return payable(hashToAddress(abi.encodePacked(bytes1(0xff), address(this), _salt, _initCode)));
    }

    function computeAddress(address _deployer, bytes32 _salt, bytes memory _initCode) public pure returns (address) {
        return hashToAddress(abi.encodePacked(bytes1(0xff), _deployer, _salt, _initCode));
    }

    function hashToAddress(bytes memory b) private pure returns (address addr) {
        return address(uint160(uint256(keccak256(b))));
    }

    function addressToBytes(address a) internal pure returns (bytes memory) {
        return abi.encodePacked(a);
    }

    function bytesToAddress(bytes memory b) external pure returns (address addr) {
        return abi.decode(b, (address));
    }
}
