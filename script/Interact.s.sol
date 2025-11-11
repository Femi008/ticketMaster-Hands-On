// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/TicketMaster.sol";

contract InteractScript is Script {
    TicketMaster ticketMaster;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ticketMasterAddress = vm.envAddress("TICKETMASTER_ADDRESS");
        
        ticketMaster = TicketMaster(ticketMasterAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Example: Create an event
        createSampleEvent();
        
        vm.stopBroadcast();
    }
    
    function createSampleEvent() internal returns (uint256) {
        uint256 startTime = block.timestamp + 7 days;
        uint256 endTime = startTime + 1 days;
        
        uint256 eventId = ticketMaster.createEvent(
            "Blockchain Conference 2025",
            "ipfs://QmSampleHash123",
            1000, // max supply
            0.1 ether, // price
            startTime,
            endTime,
            true, // transferable
            500 // 5% royalty
        );
        
        console.log("Event created with ID:", eventId);
        return eventId;
    }
    
    function mintTickets(uint256 eventId, uint256 quantity) internal {
        ITicketMaster.Event memory evt = ticketMaster.getEvent(eventId);
        uint256 totalCost = evt.price * quantity;
        
        ticketMaster.mintTicket{value: totalCost}(eventId, quantity);
        console.log("Minted", quantity, "tickets for event", eventId);
    }
    
    function checkEventDetails(uint256 eventId) internal view {
        ITicketMaster.Event memory evt = ticketMaster.getEvent(eventId);
        
        console.log("Event Name:", evt.name);
        console.log("Organizer:", evt.organizer);
        console.log("Max Supply:", evt.maxSupply);
        console.log("Total Minted:", evt.totalMinted);
        console.log("Price:", evt.price);
        console.log("Active:", evt.active);
        console.log("Available:", ticketMaster.getAvailableTickets(eventId));
    }
}
