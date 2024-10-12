// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.18;

/**
 * @title Singleton Factory (EIP-2470)
 * @notice Exposes CREATE2 (EIP-1014) to deploy bytecode on deterministic addresses based on initialization code and
 * salt.
 * @author Ricardo Guilherme Schmidt (Status Research & Development GmbH)
 */
contract ERC2470 {
    error ERC2470__CREATE2Failed();
    error ERC2470__CREATE2BadCall();

    fallback(bytes calldata _initCode) external payable returns (bytes memory) {
        return toBytes(deploy(_initCode, 0));
    }

    receive() external payable {
        revert ERC2470__CREATE2BadCall();
    }

    function deploy(bytes memory _initCode, bytes32 _salt) public payable returns (address payable createdContract) {
        assembly {
            createdContract := create2(callvalue(), add(_initCode, 0x20), mload(_initCode), _salt)
        }
        if (createdContract == address(0)) {
            revert ERC2470__CREATE2Failed();
        }
    }

    function predict(bytes memory _initCode, bytes32 _salt) public view returns (address payable createdContract) {
        createdContract = payable(
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, _initCode)))))
        );
    }

    function predictFrom(
        bytes memory _initCode,
        bytes32 _salt,
        address _factoryAddress
    )
        public
        pure
        returns (address payable createdContract)
    {
        createdContract = payable(
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), _factoryAddress, _salt, _initCode)))))
        );
    }

    function toBytes(address a) internal pure returns (bytes memory) {
        return abi.encodePacked(a);
    }

    function toAddress(bytes memory b) external pure returns (address addr) {
        return abi.decode(b, (address));
    }
}
