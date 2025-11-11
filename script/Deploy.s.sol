// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/TicketMaster.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address platformFeeRecipient = vm.envAddress("PLATFORM_FEE_RECIPIENT");
        
        vm.startBroadcast(deployerPrivateKey);
        
        TicketMaster ticketMaster = new TicketMaster(platformFeeRecipient);
        
        console.log("TicketMaster deployed at:", address(ticketMaster));
        console.log("Platform fee recipient:", platformFeeRecipient);
        console.log("Platform fee:", ticketMaster.platformFeeBps(), "bps");
        
        vm.stopBroadcast();
    }
}
