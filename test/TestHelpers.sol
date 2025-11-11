// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

contract TestHelpers is Test {
    function createUsers(uint256 count) internal returns (address[] memory) {
        address[] memory users = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = address(uint160(i + 100));
            vm.deal(users[i], 1000 ether);
        }
        return users;
    }
    
    function expectRevertWithMessage(bytes memory message) internal {
        vm.expectRevert(message);
    }
    
    function advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }
    
    function advanceBlock(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }
}
